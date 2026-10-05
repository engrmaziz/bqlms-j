# AGENTS.md

## Build protocol
This repository is built stage by stage from docs/PLAN.md (20 stages) by an
unattended agent. Nobody is watching while you work. Each task names one stage.

1. Before planning, read docs/PLAN.md (the stack table, the rules, and the
   named stage) and PROGRESS.md. The plan is the specification: do not change
   the stack, add services, or drop details. Fixed constraints: about 80
   students, zero monthly cost, no service that needs a payment card.
2. Do only the named stage. If PROGRESS.md shows it as partial, continue from
   "What remains".
3. Never ask a question and wait for an answer. Nobody will reply. When
   something is ambiguous, choose the option most consistent with the plan,
   record it under "Deviations" in PROGRESS.md, and continue.
4. Run every command in the stage's [Verification] block. Fix failures at the
   cause. Never weaken, skip or delete a test to get a pass, and never report
   a command as passing unless you ran it and saw it pass.
5. If a verification command cannot run here for an environmental reason (it
   needs real credentials, a deployed URL, or interactive input), do not fake
   it and do not stub the feature. List it under "Unverified here" with the
   reason. Everything else must pass.
6. Do not invent library APIs or version numbers. If the plan relies on an API
   you cannot confirm in the installed version, check the library's current
   documentation. If it is still unresolved, finish what is sound, mark the
   stage partial, and explain.
7. If the stage is too large for one task, finish a coherent part that passes
   `pnpm verify`, and mark the stage partial with an exact list of what
   remains.
8. Finish by updating PROGRESS.md and opening ONE pull request against main.
   Every pull request must change PROGRESS.md. Title it
   `Stage N: <stage name>`. In the description list what was done, the
   verification commands you ran with their results, deviations, and
   unverified items.
9. Do not create or modify anything under `.github/`. Do not modify
   docs/PLAN.md. Do not change the sections of this file above
   "Architecture rules". A pull request that touches `.github/` or
   docs/PLAN.md is rejected automatically.

## Environment
You run in a fresh Linux VM with Node.js, Docker and Docker Compose. There
are no real credentials here and none are needed.

At the start of every task, once the files exist, run:

    corepack enable 2>/dev/null || npm install -g pnpm
    pnpm install --frozen-lockfile
    cp -n .env.example .env
    docker compose up -d --wait
    pnpm run --if-present ci:prepare

Contracts you must keep, because CI depends on them:

- `.nvmrc` holds the Node.js major version, and package.json sets
  `packageManager` to the pnpm version in use. Commit pnpm-lock.yaml.
- `.env.example` always holds working values for the local docker compose
  services (Postgres, MinIO, Mailpit) and safe dummy values for everything
  else, so a fresh clone works with `cp .env.example .env`.
- `docker compose up -d --wait` must succeed. Every service needs a
  healthcheck. Do not use one-shot init containers (they break `--wait`); do
  setup such as bucket creation in `ci:prepare` instead.
- `pnpm ci:prepare` brings a fresh environment to the state the tests need
  (database bootstrap SQL, migrations, seed, storage bucket) and is safe to
  run repeatedly. Create it in Stage 1 as a no-op and keep it current.
- CI already exists in .github/workflows/ci.yml. It runs exactly: install,
  `cp -n .env.example .env`, `docker compose up -d --wait`,
  `pnpm run --if-present ci:prepare`, `pnpm verify`, and then `pnpm test:e2e`
  when tests/e2e contains spec files. Your pull request is merged only if
  that passes, so run the same commands before you open it.
- Any script the plan describes as interactive (for example
  scripts/create-owner.ts) must also accept flags or environment variables so
  it can run unattended.

## Overrides to the plan for this environment
The plan was written for a developer at a keyboard. Where it conflicts with
the points below, these points win.

- Workflow files: wherever the plan says to create or change a file under
  `.github/workflows/` (Stages 1 and 20), write it under `docs/workflows/`
  with the same file name instead, and add "copy docs/workflows/<name> to
  .github/workflows/" under "Operator actions". Do not write another CI
  workflow; it already exists.
- This file: Stage 1 adds its numbered rules under a new heading
  "## Architecture rules" at the end of this file and leaves everything above
  it unchanged.
- Hosted services: Supabase, Backblaze B2, SMTP, Vercel, the AI provider and
  GitHub secrets do not exist here. Build and test against the local
  Postgres, MinIO, Mailpit and the provider fakes. In this environment both
  DATABASE_URL and DATABASE_URL_SESSION point at the docker compose Postgres.
  Anything that needs a real account goes under "Operator actions" with exact
  steps.
- Stage 20: write all code, scripts, tests and documents. Run everything that
  works locally (verify, the security and chaos tests, the migration-safety
  check). Deployment, the backup and restore workflows, and the load test
  against a deployed URL are operator actions; write their runbook steps
  precisely.

## PROGRESS.md format
The first two lines, exactly:

    next_stage: <the next stage number; the same number if this stage is partial; "done" once Stage 20 is complete>
    status: <complete | partial>

Then these headings, in this order: Finished stages (one line each),
Installed versions, Deviations, What remains (only if partial), Unverified
here, Operator actions, Notes for the next stage.
