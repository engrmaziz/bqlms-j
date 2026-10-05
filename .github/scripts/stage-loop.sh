#!/usr/bin/env bash
# Build-loop driver. It works from current state, so it is safe to run at any
# time and from any trigger: manual, after CI, or on the schedule.
set -euo pipefail

REPO="${GITHUB_REPOSITORY:?}"
OWNER="${REPO%%/*}"
NAME="${REPO##*/}"
API="https://jules.googleapis.com/v1alpha"
MAX_SESSIONS_PER_STAGE=6
SESSION_STALE_HOURS=6
CI_START_GRACE_MIN=90
STOP_LABEL="loop-stopped"
LOG_LABEL="loop-log"

: "${JULES_API_KEY:?Add the JULES_API_KEY repository secret}"

say()   { echo "[stage-loop] $*"; }
now()   { date +%s; }
epoch() { date -d "$1" +%s; }

# jules METHOD PATH [JSON]  ->  response body in JBODY, HTTP status in JCODE
JBODY=""
JCODE=""
jules() {
  local method="$1" path="$2" data="${3:-}" out
  if [ -n "$data" ]; then
    out=$(curl -sS -X "$method" "$API/$path" \
      -H "x-goog-api-key: $JULES_API_KEY" -H "Content-Type: application/json" \
      -d "$data" -w $'\n%{http_code}') || out=$'\n000'
  else
    out=$(curl -sS -X "$method" "$API/$path" \
      -H "x-goog-api-key: $JULES_API_KEY" -w $'\n%{http_code}') || out=$'\n000'
  fi
  JCODE="${out##*$'\n'}"
  JBODY="${out%$'\n'*}"
}

stop_loop() { # TITLE BODY
  gh label create "$STOP_LABEL" --repo "$REPO" --color B60205 --force \
    --description "The build loop is paused while an issue with this label is open" >/dev/null
  gh issue create --repo "$REPO" --title "$1" --label "$STOP_LABEL" --body "$2"
  say "Stopped: $1"
  exit 0
}

# 1. Paused?
OPEN_STOPS=$(gh issue list --repo "$REPO" --label "$STOP_LABEL" --state open --json number --jq 'length')
if [ "$OPEN_STOPS" != "0" ]; then
  say "Paused: close the open '$STOP_LABEL' issue to resume."
  exit 0
fi

# 2. Log issue (one comment per Jules session the loop starts)
LOG=$(gh issue list --repo "$REPO" --label "$LOG_LABEL" --state open --json number --jq '.[0].number // empty')
if [ -z "$LOG" ]; then
  gh label create "$LOG_LABEL" --repo "$REPO" --color 0E8A16 --force \
    --description "Build loop history" >/dev/null
  LOG=$(gh issue create --repo "$REPO" --title "Build loop log" --label "$LOG_LABEL" \
    --body "The build loop records every Jules session it starts here. Do not close this issue." \
    | grep -o '[0-9]*$')
fi

# 3. Is a pull request open? Merge it or reject it according to CI.
HANDLED_PR=0
PR_JSON=$(gh pr list --repo "$REPO" --state open \
  --json number,headRefName,headRefOid,createdAt \
  --jq 'sort_by(.createdAt) | .[0] // empty')
if [ -n "$PR_JSON" ]; then
  PR=$(jq -r .number <<<"$PR_JSON")
  SHA=$(jq -r .headRefOid <<<"$PR_JSON")
  CREATED=$(jq -r .createdAt <<<"$PR_JSON")
  REASON=""

  RUN_JSON=$(gh run list --repo "$REPO" --workflow ci.yml --commit "$SHA" --limit 1 \
    --json databaseId,status,conclusion --jq '.[0] // empty')

  if [ -z "$RUN_JSON" ]; then
    AGE_MIN=$(( ( $(now) - $(epoch "$CREATED") ) / 60 ))
    if [ "$AGE_MIN" -lt "$CI_START_GRACE_MIN" ]; then
      say "PR #$PR: CI has not started yet."
      exit 0
    fi
    REASON="CI never started for this pull request (possibly a merge conflict with main)."
  else
    if [ "$(jq -r .status <<<"$RUN_JSON")" != "completed" ]; then
      say "PR #$PR: CI is still running."
      exit 0
    fi
    CONCLUSION=$(jq -r .conclusion <<<"$RUN_JSON")
    FILES=$(gh api "repos/$REPO/pulls/$PR/files" --paginate --jq '.[].filename')
    if [ "$CONCLUSION" != "success" ]; then
      REASON="CI finished with conclusion: $CONCLUSION."
    elif grep -Eq '^(\.github/|docs/PLAN\.md$)' <<<"$FILES"; then
      REASON="The pull request changes protected paths (.github/ or docs/PLAN.md)."
    elif ! grep -qx 'PROGRESS.md' <<<"$FILES"; then
      REASON="The pull request does not update PROGRESS.md."
    fi
  fi

  if [ -z "$REASON" ]; then
    gh pr ready "$PR" --repo "$REPO" >/dev/null 2>&1 || true
    if gh pr merge "$PR" --repo "$REPO" --squash --delete-branch; then
      say "Merged PR #$PR."
    else
      REASON="The pull request could not be merged (probably a conflict with main)."
    fi
  fi

  if [ -n "$REASON" ]; then
    gh pr close "$PR" --repo "$REPO" \
      --comment "Closed by the build loop: $REASON The branch is kept so the next attempt can reuse it."
    say "Closed PR #$PR: $REASON"
  fi
  HANDLED_PR=1
fi

# 4. What is next?
PROGRESS=$(gh api "repos/$REPO/contents/PROGRESS.md?ref=main" -H "Accept: application/vnd.github.raw")
NEXT=$(grep -m1 '^next_stage:' <<<"$PROGRESS" | awk '{print $2}' || true)
STATUS=$(grep -m1 '^status:' <<<"$PROGRESS" | awk '{print $2}' || true)

if [ "$NEXT" = "done" ]; then
  stop_loop "Build complete: operator actions remain" \
    "All 20 stages are merged. Open PROGRESS.md and work through 'Operator actions' and 'Unverified here'. Keep this issue open so the loop stays stopped."
fi
if ! [[ "$NEXT" =~ ^([1-9]|1[0-9]|20)$ ]]; then
  stop_loop "Build loop cannot read PROGRESS.md" \
    "The first line of PROGRESS.md on main must be 'next_stage: <1-20 or done>'. Found: '${NEXT:-nothing}'. Fix the file, close this issue, and run the stage-loop workflow."
fi

# 5. Is the last session the loop started still busy?
STARTS=$(gh api "repos/$REPO/issues/$LOG/comments?per_page=100" --paginate \
  --jq '.[] | select(.body | startswith("started ")) | "\(.created_at) \(.body)"')
LAST=$(tail -n 1 <<<"$STARTS")

if [ "$HANDLED_PR" = "0" ] && [ -n "$LAST" ]; then
  LAST_TIME="${LAST%% *}"
  LAST_SESSION=$(sed -n 's/.*session=\([^ ]*\).*/\1/p' <<<"$LAST")
  AGE_H=$(( ( $(now) - $(epoch "$LAST_TIME") ) / 3600 ))
  if [ -n "$LAST_SESSION" ]; then
    jules GET "$LAST_SESSION"
    STATE=$(jq -r '.state // "UNKNOWN"' <<<"$JBODY" 2>/dev/null || echo UNKNOWN)
    case "$STATE" in
      AWAITING_USER_FEEDBACK)
        MSG=$(jq -n '{prompt:"No operator is available to answer. Follow rule 3 in AGENTS.md: choose the option most consistent with docs/PLAN.md, record it under Deviations in PROGRESS.md, finish the stage, and open the pull request."}')
        jules POST "$LAST_SESSION:sendMessage" "$MSG"
        say "Session $LAST_SESSION was waiting for input; told it to decide and continue (HTTP $JCODE)."
        exit 0
        ;;
      AWAITING_PLAN_APPROVAL)
        jules POST "$LAST_SESSION:approvePlan" '{}'
        say "Approved the plan for $LAST_SESSION (HTTP $JCODE)."
        exit 0
        ;;
      COMPLETED|FAILED)
        UPDATED=$(jq -r '.updateTime // empty' <<<"$JBODY" 2>/dev/null || true)
        REF="${UPDATED:-$LAST_TIME}"
        if [ $(( ( $(now) - $(epoch "$REF") ) / 60 )) -lt 20 ]; then
          say "Session $LAST_SESSION ended recently; waiting for its pull request."
          exit 0
        fi
        say "Session $LAST_SESSION ended ($STATE) without an open pull request."
        ;;
      *)
        if [ "$AGE_H" -lt "$SESSION_STALE_HOURS" ]; then
          say "Jules is working on $LAST_SESSION (state: $STATE)."
          exit 0
        fi
        say "Session $LAST_SESSION looks stale (state: $STATE, ${AGE_H}h old)."
        ;;
    esac
  fi
fi

# 6. Attempt cap
ATTEMPTS=$(grep -c " started stage=$NEXT " <<<"$STARTS" || true)
if [ "$ATTEMPTS" -ge "$MAX_SESSIONS_PER_STAGE" ]; then
  stop_loop "Build loop stopped at Stage $NEXT" \
    "Stage $NEXT has used $ATTEMPTS Jules sessions without completing. Look at the closed pull requests and the Jules sessions for this stage, fix or simplify what blocks it, then close this issue and run the stage-loop workflow."
fi
ATTEMPT=$((ATTEMPTS + 1))

# 7. Build the prompt, with context if the previous pull request was rejected
PROMPT="Carry out Stage $NEXT of docs/PLAN.md, following AGENTS.md exactly. PROGRESS.md on main says next_stage: $NEXT, status: ${STATUS:-unknown}. This is attempt $ATTEMPT for this stage."

PREV=$(gh pr list --repo "$REPO" --state all --limit 1 \
  --json number,state,headRefName,headRefOid --jq '.[0] // empty')
if [ -n "$PREV" ] && [ "$(jq -r .state <<<"$PREV")" = "CLOSED" ]; then
  PNUM=$(jq -r .number <<<"$PREV")
  PBRANCH=$(jq -r .headRefName <<<"$PREV")
  PSHA=$(jq -r .headRefOid <<<"$PREV")
  WHY=$(gh pr view "$PNUM" --repo "$REPO" --json comments \
    --jq '[.comments[].body | select(startswith("Closed by the build loop"))][-1] // ""')
  PROMPT+=$'\n\n'"The previous attempt (pull request #$PNUM, branch $PBRANCH) was rejected. $WHY That branch still exists: run 'git fetch origin $PBRANCH' and merge it into your working branch to reuse the work if it is sound, then fix the problem before opening a new pull request."
  RUNID=$(gh run list --repo "$REPO" --workflow ci.yml --commit "$PSHA" --limit 1 \
    --json databaseId,conclusion \
    --jq '.[0] | select(.conclusion != "success") | .databaseId // empty')
  if [ -n "$RUNID" ]; then
    LOGTAIL=$(gh run view "$RUNID" --repo "$REPO" --log-failed 2>/dev/null | tail -n 120 | cut -c1-240 || true)
    if [ -n "$LOGTAIL" ]; then
      PROMPT+=$'\n\n'"Failing CI output (last lines):"$'\n'"$LOGTAIL"
    fi
  fi
fi

# 8. Find this repository in Jules and start the session
jules GET "sources?pageSize=100"
if [ "$JCODE" != "200" ]; then
  say "Jules API error $JCODE while listing sources: $JBODY"
  exit 1
fi
SOURCE=$(jq -r --arg o "${OWNER,,}" --arg r "${NAME,,}" \
  '[.sources[]? | select(((.githubRepo.owner // "") | ascii_downcase) == $o and ((.githubRepo.repo // "") | ascii_downcase) == $r) | .name][0] // empty' <<<"$JBODY")
if [ -z "$SOURCE" ]; then
  say "Jules cannot see $REPO. Give the Jules GitHub app access to this repository."
  exit 1
fi

BODY=$(jq -n --arg p "$PROMPT" --arg t "Stage $NEXT attempt $ATTEMPT" --arg s "$SOURCE" \
  '{prompt:$p, title:$t,
    sourceContext:{source:$s, githubRepoContext:{startingBranch:"main"}},
    automationMode:"AUTO_CREATE_PR", requirePlanApproval:false}')
jules POST "sessions" "$BODY"
if ! [[ "$JCODE" =~ ^2 ]]; then
  say "Could not start Stage $NEXT (HTTP $JCODE): $JBODY"
  say "This is expected when the daily task limit is reached. The scheduled run will try again."
  exit 0
fi

SNAME=$(jq -r '.name // ("sessions/" + (.id // ""))' <<<"$JBODY")
gh issue comment "$LOG" --repo "$REPO" --body "started stage=$NEXT attempt=$ATTEMPT session=$SNAME" >/dev/null
say "Started Stage $NEXT attempt $ATTEMPT as $SNAME."
