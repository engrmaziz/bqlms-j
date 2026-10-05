# College LMS for 80 Students at $0 With No Payment Card: 20-Stage Cursor Build Plan

Users are students, teachers and administration only. Email is the main notification channel. AI is used for quiz generation only.

## Stack

| Layer | Choice | Card needed |
|---|---|---|
| App | Next.js 16 (App Router, Server Actions, `proxy.ts`), TypeScript strict, Tailwind v4, shadcn/ui | no |
| Hosting | Vercel Hobby (two projects from one repo: app and SCORM origin). A Dockerfile is kept so the same code runs on any container host | no |
| Database | Supabase free project used as plain Postgres (+ `pg_cron`, `pg_net`, `pg_trgm`), Drizzle ORM | no |
| Auth | Better Auth in the same Postgres; email + password, optional Google sign-in | no |
| Background work | Postgres job table + one tick per minute from `pg_cron` | no |
| Files | Backblaze B2 through the S3 API (10 GB free), with a daily read budget enforced in code | no |
| Hot course media | Lesson images and SCORM assets served through the app's CDN cache on unguessable URLs | no |
| Video | Unlisted YouTube embeds only | no |
| Live classes | Link-out to Meet / Zoom / Jitsi with in-app check-in codes; optional Zoom API adapter | no |
| Live updates | Adaptive polling with an explicit request budget | no |
| AI | Vercel AI SDK behind one gateway, free-tier key, quiz generation from course material only | no |
| Notifications | Email (digest-first, daily cap enforced), in-app, Web Push | no |
| Payments | Off by default. Manual proof-of-payment approval; optional hosted-checkout adapter | no |
| PWA | Serwist (`@serwist/turbopack`), Dexie | no |
| Backups | Nightly encrypted `pg_dump` from GitHub Actions to B2 and to a workflow artifact | no |
| Monitoring | Platform logs, dead-man's-switch heartbeat, in-app system page | no |

## Rules for running this plan

- One prompt = one fresh agent session = one commit. Do not start the next prompt while verification is red.
- Prompt 1 writes `AGENTS.md`; every later prompt assumes the agent has read it.
- Single college per deployment.
- Versions are resolved at install time, never from the model's memory.

---

**Prompt 1: Repository Scaffolding, Toolchain & Zero-Cost Guardrails**

```cursor
[Context]: Greenfield repo for a single-college LMS serving about 80 students, their teachers and administrators, on free tiers that need no payment card. Build the skeleton, local infrastructure, quality gates, and the AGENTS.md rules that the next 19 prompts depend on. No feature code yet.

[Files to Create/Modify]:
- package.json, tsconfig.json, next.config.ts, biome.json, components.json, Dockerfile, .dockerignore
- vitest.config.ts (unit), vitest.int.config.ts (integration, real Postgres), playwright.config.ts
- docker-compose.yml, .env.example, .dependency-cruiser.cjs
- src/lib/env.ts, logger.ts, request-context.ts, result.ts, errors.ts, fsm.ts
- src/app/layout.tsx, src/app/page.tsx, src/app/api/health/live/route.ts
- AGENTS.md, .cursor/rules/architecture.mdc (alwaysApply: true; points at AGENTS.md)
- docs/STACK.md, docs/COSTS.md, .github/workflows/ci.yml

[Implementation Details]:
- Scaffold with `pnpm create next-app@latest` (TypeScript, App Router, src dir, Tailwind, Turbopack). Current Node LTS. Resolve dependency versions at install time and record them in docs/STACK.md.
- next.config.ts: output 'standalone' only when BUILD_STANDALONE=1 (used by the Dockerfile; the default build targets Vercel). Security headers: HSTS, X-Content-Type-Options, Referrer-Policy, Permissions-Policy, frame-ancestors 'none'. Dockerfile: multi-stage, non-root user, listens on $PORT.
- tsconfig: strict, noUncheckedIndexedAccess, exactOptionalPropertyTypes; alias @/* -> src/*.
- env.ts: @t3-oss/env-nextjs + zod; build fails on a missing variable.
- request-context.ts: AsyncLocalStorage { requestId, userId? }. logger.ts: pino JSON to stdout with that context; redact authorization, cookie, password, token.
- result.ts: Result<T, AppError>. errors.ts: codes UNAUTHENTICATED | FORBIDDEN | NOT_FOUND | VALIDATION | CONFLICT | RATE_LIMITED | PRECONDITION_FAILED | QUOTA_EXCEEDED | UPSTREAM_UNAVAILABLE | INTERNAL, each mapped to an HTTP status.
- fsm.ts: defineMachine(transitions) -> transition(state, event), throwing PRECONDITION_FAILED on an illegal move.
- docker-compose.yml with healthchecks: postgres:17, minio (+ bucket bootstrap), mailpit.
- Module layout: src/modules/<domain>/{schema,service,policy,actions,queries,index}.ts; dependency-cruiser allows cross-module imports only through index.ts.
- Scripts: dev, build, typecheck, lint, test, test:int, test:e2e, db:generate, db:migrate, db:seed, jobs:dev, verify (= typecheck + lint + depcruise + test + test:int).
- AGENTS.md, numbered rules, verbatim:
  1. One Next.js app, modular monolith, single college. No tenant concept.
  2. Zero-cost, no-card rule: never add a service that needs a paid plan or a payment method on file. Every external service sits behind an interface in src/lib/providers/*, has a free default, a fake for tests, an on/off flag, and a hard usage cap that returns QUOTA_EXCEEDED.
  3. Request handlers are stateless serverless functions. Do no work after the response is sent. No WebSockets or SSE. No in-memory state shared across requests except short-lived caches.
  4. Requests are a budget: the host caps monthly function invocations and CPU, and a project that exceeds them is paused. No polling while a tab is hidden, no per-keystroke requests, cache whatever is cacheable, keep server rendering light.
  5. Every mutation goes through defineAction/defineRoute. Services never read cookies or headers and never accept a user id from client input.
  6. Side effects (email, push, provider calls) run only in jobs enqueued in the same DB transaction as the state change.
  7. Every job step finishes in under 30 seconds, is idempotent, and resumes from a checkpoint.
  8. Only course material is ever sent to an LLM; student-authored content never is. LLM output needs schema validation and human approval before students see it.
  9. Money = integer minor units + currency. Time = timestamptz UTC. IDs = UUIDv7 generated app-side.
  10. The database is small (500 MB): no blobs or base64 in Postgres, bounded jsonb, every append-only table has a retention job.
  11. No `any`, no non-null assertions, no floating promises, no stubs. If blocked, stop and report.
  12. A stage is done only when `pnpm verify` is green.
- docs/COSTS.md: table skeleton (service, free limit, our cap, behavior at cap, where to check). Filled in as providers are added.
- CI: GitHub Actions with a Postgres service container running `pnpm verify`.

[Verification]:
docker compose up -d --wait
pnpm install && pnpm verify
pnpm build
docker build --build-arg BUILD_STANDALONE=1 -t lms . && docker run --rm -d -p 8080:8080 -e PORT=8080 --env-file .env.example --name lms lms
sleep 5 && curl -fsS http://localhost:8080/api/health/live    # expect {"status":"ok"}
docker stop lms
```

---

**Prompt 2: Database Foundation**

```cursor
[Context]: Builds on Prompt 1. Set up Postgres access through Drizzle against a Supabase free project used as plain Postgres, with conventions that keep the database small, closed to Supabase's public Data API, and portable to any other Postgres.

[Files to Create/Modify]:
- drizzle.config.ts, scripts/db-bootstrap.sql, scripts/check-schema.ts, scripts/db-size.ts
- src/db/client.ts, src/db/tx.ts, src/db/seed.ts
- src/db/schema/_shared.ts, src/db/schema/index.ts
- src/modules/settings/schema.ts, service.ts, queries.ts, index.ts, src/lib/flags.ts
- src/db/migrations/* (generated), src/db/__tests__/db.int.test.ts

[Implementation Details]:
- Driver: postgres.js with prepare: false (required by transaction-mode poolers), max 3 connections per function instance, connect_timeout 10s, statement_timeout 5s. Reuse one client per instance (module scope).
- Env: DATABASE_URL = transaction pooler (runtime). DATABASE_URL_SESSION = session-mode pooler (migrations and pg_dump; IPv4-reachable from CI).
- All application tables live in a dedicated Postgres schema `lms` via pgSchema('lms'). db-bootstrap.sql: create schema lms; create extensions pg_trgm and citext; in a guarded DO block revoke all privileges on schema lms from the `anon` and `authenticated` roles if they exist. Document in docs/STACK.md: do not add `lms` to the exposed schemas of the Supabase Data API.
- check-schema.ts: fail if any application table exists in `public`, or if anon/authenticated hold any privilege on schema lms. Add to `pnpm verify`.
- _shared.ts: id() uuid PK with $defaultFn(uuidv7); timestamps(); softDelete(); version() integer for optimistic concurrency.
- tx.ts: withTx(fn) opens a transaction and passes a branded `Tx`. Service functions accept Tx, so a raw client cannot be passed by mistake.
- settings: single-row table (id = 1 enforced by CHECK) holding college_name, timezone, locale, branding jsonb, policies jsonb, flags jsonb, each jsonb typed and validated by zod with defaults. getSettings() cached in memory for 60 seconds. flags.ts: isEnabled(key) reads settings.flags plus env kill switches (KILL_<PROVIDER>=1).
- Migrations: drizzle-kit generate -> committed SQL; db:migrate uses DATABASE_URL_SESSION. Never `push` outside local. Expand/contract only.
- db-size.ts: prints database size and the 15 largest tables with row counts (reused by the admin system page in Prompt 20).
- seed.ts: settings row with sensible defaults. Local development uses docker Postgres; nothing in the code depends on Supabase-only features.

[Verification]:
psql "$DATABASE_URL_SESSION" -f scripts/db-bootstrap.sql
pnpm db:generate && pnpm db:migrate && pnpm db:seed
pnpm tsx scripts/check-schema.ts && pnpm tsx scripts/db-size.ts
pnpm test:int src/db/__tests__/db.int.test.ts
# Tests must prove: a second settings row is rejected; withTx rolls back on throw; 50 concurrent transactions complete on a pool of 3 without connection errors; a query exceeding statement_timeout is cancelled.
```

---

**Prompt 3: Authentication & Sessions**

```cursor
[Context]: Builds on Prompt 2. Add identity with Better Auth stored in our own Postgres, role profiles, invitation-only onboarding that does not depend on email delivery, and the server-side Actor used by all later authorization.

[Files to Create/Modify]:
- src/lib/auth/auth.ts, client.ts, session.ts
- src/app/api/auth/[...all]/route.ts
- src/modules/identity/schema.ts, service.ts, queries.ts, index.ts
- src/proxy.ts, src/lib/csp.ts
- src/app/(auth)/sign-in/page.tsx, accept-invite/[token]/page.tsx, reset/[token]/page.tsx
- scripts/create-owner.ts
- src/modules/identity/__tests__/*.int.test.ts, tests/e2e/auth.spec.ts

[Implementation Details]:
- Better Auth (latest patched stable; follow its docs for the installed version) with the Drizzle adapter; its tables live in schema lms. Email + password. Google sign-in is enabled only when GOOGLE_CLIENT_ID is set and is restricted to email domains listed in settings. TOTP two-factor available to all and required for super_admin and admin. Enable the signed session cookie cache (5 minutes) so most requests do not hit the database. Auth rate limiting uses database storage.
- Public sign-up is disabled. Accounts come only from invitations or the CSV import in Prompt 7.
- profiles(user_id PK, roles role[], status invited|active|suspended, student_number unique nullable, employee_id, phone, created_at). Role enum: super_admin | admin | registrar | faculty | student. A user may hold several roles.
- invitations(email, roles, token_hash, expires_at, accepted_at, created_by): store sha256(token) only; single use; 14-day expiry. The admin UI (Prompt 5) shows a copyable invite link so it can be shared over any channel. Sending it by email arrives in Prompt 6.
- Admin-generated reset links: an admin can create a one-time, 1-hour password reset link for a user and share it out of band. Self-service email reset is offered when SMTP is configured, and those emails always bypass the digest and draw on a reserved part of the daily email cap.
- create-owner.ts: interactive CLI that creates the first super_admin. No default credentials anywhere.
- proxy.ts (Next.js 16 Proxy): delete inbound x-request-id and x-nonce; set a request id; generate a nonce and a strict CSP (script-src 'self' 'nonce-...' 'strict-dynamic'; frame-src and connect-src allowlists from env); presence-only session-cookie check that redirects to /sign-in for protected paths (UX only, not authorization). No database access in the proxy. Exclude static assets with the matcher so the proxy does not consume invocations for them.
- session.ts: getActor() (server-only, wrapped in React cache()): validates the session, loads the profile, returns Actor { userId, roles, status } or null. Suspended users are signed out.
- Cookies: __Host- prefix, Secure, HttpOnly, SameSite=Lax. Sessions: 30 days sliding for students, 12 hours for staff; all sessions revoked on suspension and on password change. requireFreshSession(10 min) helper for sensitive actions.
- Edge cases: emails lowercased and NFC-normalized; enumeration-safe sign-in and reset responses; callbackUrl must be a same-origin relative path.

[Verification]:
pnpm db:generate && pnpm db:migrate && pnpm tsx scripts/check-schema.ts
pnpm tsx scripts/create-owner.ts
pnpm test:int src/modules/identity
pnpm test:e2e tests/e2e/auth.spec.ts
# e2e must cover: sign-up endpoint is closed; invite link -> set password -> sign in; reused and expired invite tokens fail; admin-generated reset link works once; a suspended user is rejected; CSP header carries a nonce; an absolute callbackUrl is ignored.
```

---

**Prompt 4: Authorization, Action Pipeline, Rate Limiting & Audit**

```cursor
[Context]: Builds on Prompt 3. Create the single pipeline for every mutation and API call: authenticate -> rate limit -> validate -> authorize -> execute in a transaction -> audit. Later prompts only declare a permission and a handler.

[Files to Create/Modify]:
- src/lib/authz/permissions.ts, can.ts, scope.ts
- src/lib/actions/define-action.ts, src/lib/api/define-route.ts, src/lib/rate-limit.ts
- src/modules/audit/schema.ts, service.ts, queries.ts, index.ts
- src/modules/idempotency/schema.ts, service.ts
- scripts/check-actions.ts, scripts/gen-permissions-doc.ts, docs/PERMISSIONS.md
- src/lib/authz/__tests__/matrix.test.ts, src/lib/actions/__tests__/pipeline.int.test.ts

[Implementation Details]:
- permissions.ts: const union of `resource:action` strings and a static role -> permission map in code (no editable roles).
- Two checks, both required: role permission AND relationship scope. Scopes: college-wide (super_admin, admin, registrar), instructor-of-section, enrolled-in-section, self. can(actor, permission, resource, loaders) is pure; relationship lookups come from loader functions memoized per request (real loaders are wired in Prompt 7).
- defineAction({ input, permission, resource?, rateLimit?, audit?, handler }): getActor (UNAUTHENTICATED) -> rate limit -> zod parse with .strict() (VALIDATION with field errors) -> withTx -> load resource and can() (FORBIDDEN, or NOT_FOUND where existence must not leak) -> handler(tx, actor, input) -> audit row in the same transaction -> commit -> serializable Result. Unknown exceptions are logged with the request id and returned as INTERNAL without detail.
- defineRoute: the same pipeline for Route Handlers under /api/v1, plus Idempotency-Key support backed by idempotency_keys(key, actor_id, request_hash, response jsonb, expires_at): same key and hash replays the stored response; same key with a different hash -> CONFLICT.
- rate-limit.ts: fixed-window counters in Postgres (no Redis): rate_limits(key, window_start, count, PK(key, window_start)) with a single upsert returning the count. Apply only to buckets that need it: auth, write, upload, ai, message. A retention job (Prompt 6) deletes windows older than one day.
- audit_log: append-only (the runtime role has no UPDATE or DELETE): actor_id, action, resource_type, resource_id, before/after jsonb (allowlisted fields, each capped at 4 KB), ip, request_id, at. Index (at desc) and (resource_type, resource_id). Retention 2 years, pruned by job.
- check-actions.ts: AST check that every export of src/modules/*/actions.ts comes from defineAction and every /api/v1 handler from defineRoute. Part of `pnpm verify`.
- gen-permissions-doc.ts renders the role x permission x scope matrix to docs/PERMISSIONS.md; CI fails on an uncommitted diff.

[Verification]:
pnpm test src/lib/authz
pnpm test:int src/lib/actions
pnpm tsx scripts/check-actions.ts
pnpm tsx scripts/gen-permissions-doc.ts && git diff --exit-code docs/PERMISSIONS.md
# Pipeline tests must show: a forbidden call writes nothing, including no audit row; a handler exception rolls back the audit row; an idempotent replay returns the stored response without re-running the handler; the rate limiter returns RATE_LIMITED at the limit and counts correctly under 20 concurrent calls.
```

---

**Prompt 5: App Shell, Design System, Portals & User Management**

```cursor
[Context]: Builds on Prompts 3-4. Create the mobile-first shell, shared UI primitives and the three portals (admin, faculty, student), plus the first real features: college settings and user/invitation management.

[Files to Create/Modify]:
- src/app/(app)/layout.tsx, error.tsx, not-found.tsx, loading.tsx
- src/app/(app)/admin/layout.tsx, page.tsx, users/page.tsx, users/[userId]/page.tsx, settings/page.tsx
- src/app/(app)/faculty/layout.tsx, page.tsx; src/app/(app)/student/layout.tsx, page.tsx
- src/modules/identity/actions.ts (invite, revoke invite, change roles, suspend, generate reset link)
- src/modules/settings/actions.ts
- src/components/app/app-sidebar.tsx, bottom-nav.tsx, page-header.tsx, data-table.tsx, form.tsx, empty-state.tsx, error-state.tsx, role-switcher.tsx, copy-link.tsx
- src/lib/nav.ts, pagination.ts, datetime.ts, src/lib/i18n/*, messages/en.json, src/lib/query-client.tsx
- tests/e2e/shell.spec.ts, tests/e2e/users.spec.ts, tests/e2e/a11y.spec.ts

[Implementation Details]:
- Mobile-first: design at 360px. Student portal uses a bottom tab bar below md and a sidebar from md up. Touch targets >= 44px. Most students will use phones on slow networks, so keep client JavaScript small.
- Server Components by default; client components only for interaction. Reads go through module queries.ts (getActor -> can -> withTx). Suspense with skeletons per panel.
- Request budget: disable automatic link prefetching for authenticated navigation except on explicit hover or touch, so idle pages do not generate function invocations.
- Each portal layout calls requireRole() server-side; add a code comment that layout guards are UX only and every query and action re-authorizes.
- nav.ts derives navigation from permissions. Multi-role users get a role switcher stored in a cookie.
- data-table.tsx: TanStack Table with server-side sort, filter and pagination from URL params (nuqs). pagination.ts: keyset cursors (sortValue, id).
- form.tsx: react-hook-form + zod resolver using the same schema object as the action; maps VALIDATION field errors onto fields; pending state.
- query-client.tsx: TanStack Query provider for client-side fetching and the polling added in Prompt 14.
- datetime.ts: all rendering through Intl.DateTimeFormat in the college timezone from settings.
- i18n: next-intl with `en` only; every string through messages; logical CSS properties so an RTL locale can be added later.
- Accessibility: skip link, focus moved to the page heading on navigation, aria-live toasts, visible focus.
- Admin > Users: list with search; invite one user (email, roles) and show the copyable invite link; change roles (only super_admin may grant admin or super_admin; nobody can remove the last super_admin); suspend/reactivate; generate a one-time reset link. Every action audited.
- Admin > Settings (super_admin): college name, timezone, branding (logo and brand color with a WCAG AA contrast check), policies and feature flags, all validated by the settings zod schema.
- Error boundaries map AppError codes to UI states and show the request id.

[Verification]:
pnpm verify
pnpm test:e2e tests/e2e/shell.spec.ts tests/e2e/users.spec.ts tests/e2e/a11y.spec.ts
# Run at 360x740 and 1280x800. Each seeded role lands on its portal; a student requesting /admin gets 404; an admin cannot grant super_admin; the last super_admin cannot be demoted or suspended; an idle authenticated page issues no background requests for 60 seconds; axe reports zero serious or critical violations.
```

---

**Prompt 6: Background Jobs, Webhook Ingestion & Email-First Notifications**

```cursor
[Context]: Builds on Prompts 2-5. Provide reliable background work without any queue service: a job table in Postgres drained by a per-minute tick. Add a small inbound-webhook framework for the optional adapters, and a notification service where email is the main channel and the provider's daily sending cap is a hard design constraint.

[Files to Create/Modify]:
- src/modules/jobs/schema.ts, service.ts, registry.ts, drain.ts, schedule.ts, index.ts
- src/app/api/internal/tick/route.ts, scripts/jobs-dev.ts, scripts/cron.sql
- src/modules/webhooks/schema.ts, service.ts, handlers/index.ts; src/app/api/webhooks/[provider]/route.ts
- src/lib/providers/email/{types,smtp,fake}.ts
- src/modules/notifications/schema.ts, service.ts, actions.ts, queries.ts, categories.ts, digest.ts, templates/*.tsx, jobs.ts
- src/app/(app)/notifications/page.tsx, src/app/(app)/settings/notifications/page.tsx, src/components/app/notification-bell.tsx
- docs/COSTS.md (email row); integration tests

[Implementation Details]:
- jobs(id, name, payload jsonb, run_at, status queued|running|done|failed|dead, attempts, max_attempts, locked_until, last_error, dedupe_key unique nullable, created_at). enqueue(tx, name, payload, { runAt?, dedupeKey? }) takes a Tx, so the job commits atomically with the state change.
- registry.ts: job name -> { zod payload schema, handler, maxAttempts }. Handlers open their own short transactions.
- drain.ts: loop with a 45-second budget: reclaim rows whose locked_until has passed; claim up to 5 due jobs with FOR UPDATE SKIP LOCKED, setting status running and locked_until = now + 2 minutes; run each; on success mark done; on error set failed with exponential backoff via run_at, or dead after max_attempts. A handler needing more than about 30 seconds must checkpoint and enqueue its next step.
- schedule.ts: recurring tasks declared in code; each tick enqueues them with dedupeKey = name + time bucket.
- /api/internal/tick: export maxDuration = 60; requires Authorization: Bearer CRON_SECRET (timing-safe compare); runs schedule then drain; finally pings HEARTBEAT_URL if set. scripts/cron.sql schedules it every minute with pg_cron + pg_net, reading the secret from Supabase Vault, and adds a daily job that prunes cron.job_run_details older than 2 days. jobs-dev.ts calls the tick every 5 seconds locally.
- Do not use after(), setTimeout or un-awaited promises for background work. Latency of up to one minute for async effects is accepted.
- Retention jobs: delete done jobs after 7 days, rate-limit windows after 1 day, processed webhook events after 30 days.
- Webhook route (used only by optional adapters later): read the raw body; provider-specific verify(rawBody, headers) with timing-safe comparison; insert webhook_events(provider, external_id unique, payload, status); duplicates return 200 without work; processing is enqueued as a job. Unknown provider -> 404.
- Notifications: notifications (in-app feed, always written), notification_deliveries(channel email|push, kind immediate|digest, status queued|sent|failed|deferred, dedupe_key unique, attempts, error), notification_preferences(user, category, email on/off, push on/off).
- categories.ts: every category declares a delivery class. immediate: security (reset, new sign-in), exam or deadline within 2 hours, payment decision. digest: everything else (announcements, new content, grades released, forum replies, messages, absence notices, reminders further out).
- digest.ts: one digest email per user per day at settings.digest_hour in the college timezone, grouped by course, sent only if there is something unread. Users may choose a second digest time or switch a category to immediate, within a per-user limit of 3 immediate emails per day (extra ones fall into the digest).
- Email: nodemailer over generic SMTP (Mailpit locally). EMAIL_DAILY_CAP (default 250) is enforced by counting today's sent rows, with 30 reserved for security emails. Over the cap, deliveries become deferred and run the next day in priority order: security, deadlines, the rest. With SMTP unconfigured, email is an unavailable channel and the in-app feed still works.
- notify(tx, { recipient, template, data, category, dedupeKey }) writes rows and enqueues delivery. Templates: React Email, plain and small; all strings via i18n keys; every email links back to the in-app item.
- Bell: unread count from the database (polling arrives in Prompt 14). Push arrives in Prompt 19 as a second channel behind the same service.

[Verification]:
pnpm db:generate && pnpm db:migrate && pnpm tsx scripts/check-schema.ts
pnpm test:int src/modules/jobs src/modules/webhooks src/modules/notifications
pnpm jobs:dev &   # then trigger a test notification and confirm it appears in Mailpit
# Tests must prove: a job enqueued in a rolled-back transaction never runs; two concurrent drains never run the same job; a crashed running job is reclaimed after locked_until; a failing job backs off and ends dead after max attempts; the same dedupeKey enqueues once; a tick without the secret is rejected; ten digest-class notifications for one user produce one email; an immediate-class one sends within the next tick; the 4th immediate email of the day rolls into the digest; the global cap defers the (cap+1)th message but still sends a security email from the reserve.
```

---

**Prompt 7: Academic Structure, Enrollment & CSV Import**

```cursor
[Context]: Builds on Prompts 4-6. Model terms, courses, sections, schedules and enrollment, and let the registrar load everyone from a spreadsheet. This relationship graph powers resource-scoped authorization. There are no parent or guardian accounts in this system.

[Files to Create/Modify]:
- src/modules/academics/schema.ts, service.ts, policy.ts, actions.ts, queries.ts, index.ts
- src/modules/enrollment/schema.ts, service.ts, policy.ts, actions.ts, queries.ts, fsm.ts, import.ts, index.ts
- src/lib/authz/scope.ts (wire real loaders)
- src/app/(app)/admin/terms/page.tsx, courses/page.tsx, sections/page.tsx, sections/[sectionId]/page.tsx, import/page.tsx
- integration tests, tests/e2e/registrar.spec.ts

[Implementation Details]:
- Schema: terms(name, starts_on, ends_on, census_date, status planned|active|closed); courses(code unique, title, credits); sections(course_id, term_id, code, capacity, delivery in_person|online|hybrid, status draft|published|archived); section_instructors(section_id, user_id, role lead|co|ta); section_schedules(section_id, weekday, start_time, end_time, room, effective_from, effective_to); holidays(date, name); enrollments(section_id, student_id, status enrolled|waitlisted|dropped|withdrawn|completed, source manual|import|purchase, waitlist_position, unique(section_id, student_id)).
- Capacity: enroll locks the section row (SELECT ... FOR UPDATE), counts enrolled, inserts as enrolled or waitlisted. On drop, promote the first waitlisted student in the same transaction and notify.
- Enrollment FSM via src/lib/fsm.ts: drop before census_date -> dropped; after -> withdrawn; a closed term changes only through a registrar override with a reason (audited).
- CSV import for people and enrollments. At this size it is synchronous: file <= 1 MB and <= 2,000 rows, parsed with csv-parse, each row validated by zod. Step 1 returns a dry-run report (creates, updates, errors with line numbers) and writes nothing. Step 2 applies everything in one transaction, idempotent on natural keys (student_number or email; section code + term).
- Onboarding after import: the result page lists new users with copyable invite links and a downloadable CSV of the links. "Email all invites" enqueues them through notify() so they respect the daily email cap; with 80 students this may spread over more than one day, and the page says so.
- CSV exports neutralize spreadsheet formula injection (prefix cells starting with = + - @).
- Phones normalized to E.164 with libphonenumber-js (stored for contact only; nothing is sent to phones).
- People search: pg_trgm GIN index over name, email, student_number.
- Wire scope loaders: instructor-of-section from section_instructors, enrolled-in-section from enrollments with status enrolled.

[Verification]:
pnpm db:generate && pnpm db:migrate && pnpm tsx scripts/check-schema.ts
pnpm test:int src/modules/academics src/modules/enrollment
pnpm test:e2e tests/e2e/registrar.spec.ts
# Tests must prove: 40 concurrent enroll calls into a capacity-30 section give exactly 30 enrolled and 10 waitlisted in order; a drop promotes waitlist position 1; the dry run writes nothing; re-applying the same file is a no-op; emailing 300 invites with a cap of 250 defers the remainder; faculty cannot read a section they do not teach; a student cannot read another student's enrollment.
```

---

**Prompt 8: File Storage & Video**

```cursor
[Context]: Builds on Prompts 4 and 6. Lessons, submissions, SCORM packages and payment proofs need file storage that works without a payment card. Use Backblaze B2 through its S3-compatible API. Its free tier limits total storage and the number of read operations per day, so both are budgeted in code. Video is unlisted YouTube only.

[Files to Create/Modify]:
- src/lib/providers/storage/{types,s3,fake}.ts
- src/modules/files/schema.ts, service.ts, policy.ts, actions.ts, queries.ts, purposes.ts, fsm.ts, budget.ts, jobs.ts, index.ts
- src/app/api/v1/files/[fileId]/download/route.ts
- src/app/api/v1/media/[fileId]/[key]/route.ts
- src/lib/video/youtube.ts, src/components/app/video-player.tsx, src/components/app/file-uploader.tsx, src/lib/images/compress.ts
- docs/COSTS.md (storage row), docs/STACK.md (storage trade-offs); integration tests, tests/e2e/upload.spec.ts

[Implementation Details]:
- Storage: @aws-sdk/client-s3 + s3-request-presigner pointed at the B2 S3 endpoint (MinIO locally). Private bucket with a CORS rule for browser uploads from the app origin. Key = {purpose}/{fileId}/{sanitizedName}. Never list objects at runtime; Postgres is the index.
- files(owner_id, purpose, delivery signed|cdn, public_key nullable, status pending|uploaded|verified|rejected|deleted, declared_mime, detected_mime, size_bytes, sha256, storage_key).
- purposes.ts: per-purpose MIME allowlist, size cap, delivery mode, and the module policy that authorizes reads. Defaults: lesson_document 20 MB (signed); lesson_image 2 MB (cdn); avatar 512 KB (cdn); submission 10 MB (signed); payment_proof 3 MB (signed); scorm_package 50 MB (signed). No video uploads. Never allow executables, scripts, HTML, SVG, or macro-enabled Office formats.
- budget.ts: (1) STORAGE_BUDGET_BYTES (default 8 GB): requestUpload returns QUOTA_EXCEEDED when live bytes plus the new file would exceed it; also a per-user daily upload limit. (2) STORAGE_DAILY_READ_CAP (default 2,000): storage_reads(day PK, count) is incremented for every presigned download issued and every server-side object read; at the cap, downloads return QUOTA_EXCEEDED with a "try again tomorrow" message. Both figures are shown on the system page (Prompt 20). Confirm the provider's current free limits and record them in docs/COSTS.md.
- compress.ts: images are resized and re-encoded in the browser before upload (max 1600px, WebP or JPEG) to save storage and bandwidth.
- Upload: requestUpload({ purpose, name, size, mime }) -> policy + allowlist + budget -> pending row -> presigned PUT (TTL 5 minutes, signed content length and type). completeUpload(fileId) verifies the object exists with the expected size, sets uploaded, and enqueues verification.
- Verification job: ranged GET of the first bytes, sniff with `file-type`; the detected type must be in the allowlist and agree with the declared type, otherwise rejected and the object deleted. There is no antivirus at this budget; record that residual risk in docs/STACK.md.
- Delivery mode signed (private files): the download route authorizes through the owning module's policy, counts the read, and 302-redirects to a presigned GET (60 seconds). Content-Disposition is attachment except for PDF.
- Delivery mode cdn (lesson images, avatars): files get a 128-bit random public_key. The media route streams the object (max 4 MB) with Cache-Control: public, max-age=31536000, s-maxage=31536000, immutable, so the platform CDN serves repeats and storage is read about once per file. There is no session check on this route: the URL is the capability and is only ever embedded in pages served to authorized users. Document this trade-off (same exposure as an unlisted video) and never use cdn delivery for student work or payment proofs.
- GC job: delete pending rows and objects older than 24 hours; hard-delete soft-deleted files after 30 days so the budget is freed. Admin tool: export a closed term's submissions as a zip manifest of download links, then purge them, to reclaim space.
- Video lessons: a YouTube URL only. youtube.ts validates and extracts the id; the player uses the privacy-enhanced embed domain (in CSP frame-src) and the IFrame Player API to report watched intervals. The faculty UI states that an unlisted video can be viewed by anyone with the link.
- video-player.tsx emits a progress heartbeat every 60 seconds and on pause/end (consumed in Prompt 9).
- file-uploader.tsx: drag/drop, paste, mobile camera capture, progress, abort, retry.

[Verification]:
pnpm db:generate && pnpm db:migrate && pnpm tsx scripts/check-schema.ts
pnpm test:int src/modules/files
pnpm test:e2e tests/e2e/upload.spec.ts
# Tests must prove: an executable renamed .pdf is rejected and its object deleted; an oversize request is refused before upload; with the byte budget at 1 MB a 2 MB upload returns QUOTA_EXCEEDED; with the read cap at 3 the 4th download of the day returns QUOTA_EXCEEDED; the media route sets immutable cache headers and rejects a wrong key; a submission can never be created with cdn delivery; a student cannot download another student's submission; GC frees budget; invalid YouTube URLs are refused.
```

---

**Prompt 9: Course Builder & Delivery: Syllabus, Modules, Drip Scheduling, Progress**

```cursor
[Context]: Builds on Prompts 7-8. Faculty author course content; students consume it under deterministic release rules; the system tracks progress. Access decisions happen on the server on every read.

[Files to Create/Modify]:
- src/modules/content/schema.ts, service.ts, policy.ts, actions.ts, queries.ts, drip.ts, render.ts, jobs.ts, index.ts
- src/modules/progress/schema.ts, service.ts, queries.ts, intervals.ts, index.ts
- src/app/api/v1/progress/heartbeat/route.ts
- src/app/(app)/faculty/sections/[sectionId]/builder/page.tsx, syllabus/page.tsx
- src/app/(app)/student/sections/[sectionId]/page.tsx, syllabus/page.tsx, lessons/[lessonId]/page.tsx
- src/components/app/rich-editor.tsx, lesson-renderer.tsx, module-tree.tsx
- src/modules/content/__tests__/drip.test.ts, integration tests, tests/e2e/course-delivery.spec.ts

[Implementation Details]:
- Schema: modules(section_id, title, position, status draft|published); lessons(module_id, type rich_text|video|file|embed|scorm|assessment_ref|live_ref, title, position, body jsonb, file_id, video jsonb, est_minutes, status); position is a fractional index string (fractional-indexing). syllabus_versions(section_id, version, content jsonb, published_at, published_by), immutable once published; students see the latest and are notified of changes in their digest.
- Rich text: Tiptap, lazy-loaded for faculty only. Persist ProseMirror JSON (cap 200 KB per lesson). render.ts maps an allowlist of nodes and marks to React on the server; no raw HTML node; images reference cdn-delivery files from Prompt 8; embeds only from an allowlist that matches CSP frame-src.
- drip.ts is a pure function: evaluateAccess(rules, ctx) -> { unlocked, reason, unlocksAt? }. Rule kinds: fixed_date, relative_to_enrollment(days), relative_to_term_start(days), after_completion(lessonIds, all|any), min_score(assessmentId, pct); combined with AND. Evaluated in the college timezone. drip_overrides(student, target, unlocked_at) for accommodations. Instructors bypass.
- Enforcement lives in queries.ts: a locked lesson returns a stub (title, reason, unlocksAt) with no body, no file ids and no video id, and the file download path repeats the check.
- Saving after_completion rules builds the prerequisite graph and rejects cycles.
- Time-based unlocks enqueue a digest notification at unlocksAt that re-evaluates before notifying.
- Progress: lesson_progress(enrollment_id, lesson_id, status, progress_pct, last_position_s, watched jsonb, completed_at, unique(enrollment_id, lesson_id)). Completion by type: rich_text = reached the end plus a minimum dwell; video = at least 90% of unique seconds watched, computed server-side from merged intervals (intervals.ts), so seeking to the end does not complete; file = opened; scorm and assessment = set by their modules.
- Heartbeat route: batched, idempotent, monotonic merge, rate-limited; at most one request per 60 seconds per open lesson plus one on pagehide via sendBeacon.
- Section completion is derived; record it exactly once per enrollment (unique guard) and enqueue the certificate check (Prompt 17).
- Builder: dnd-kit reordering with optimistic update and rollback; publish checklist (unverified files, empty lessons); "view as student" goes through the same query path.
- Clone a section from an earlier term in one transaction: new IDs, shared file references, drip dates re-based.
- Published structure per section is cached with tag invalidation on publish; per-student locks and progress are never cached.

[Verification]:
pnpm test src/modules/content/__tests__/drip.test.ts
pnpm db:generate && pnpm db:migrate && pnpm tsx scripts/check-schema.ts
pnpm test:int src/modules/content src/modules/progress
pnpm test:e2e tests/e2e/course-delivery.spec.ts
# Tests must prove: table-driven drip cases including a DST boundary; a direct fetch of a locked lesson returns a stub and its file route denies; a prerequisite cycle is rejected; seeking a video to the end does not complete it; progress never decreases; an open lesson sends no more than one heartbeat per minute; concurrent reorders converge.
```

---

**Prompt 10: SCORM 1.2 / 2004 Runtime**

```cursor
[Context]: Builds on Prompts 8-9. Add SCORM ingestion and a compliant runtime behind a feature flag (off by default; SCORM is the largest consumer of free quotas in this system). Packages are untrusted third-party JavaScript that expect a synchronous, same-origin API. The isolation origin is free: the same codebase deployed as a second project on a different hostname.

[Files to Create/Modify]:
- src/modules/scorm/schema.ts, service.ts, policy.ts, actions.ts, queries.ts, manifest.ts, zip.ts, cmi-12.ts, cmi-2004.ts, time.ts, jobs.ts, index.ts
- src/lib/scorm/launcher/runtime.ts (browser code), scripts/build-scorm-launcher.ts (esbuild -> string module)
- src/app/api/v1/scorm/launcher/[token]/route.ts, src/app/api/v1/scorm/content/[packageKey]/[...path]/route.ts
- src/app/api/v1/scorm/runtime/init/route.ts, commit/route.ts, terminate/route.ts
- src/proxy.ts (SCORM service restriction), src/components/app/scorm-player.tsx
- tests/fixtures/scorm/build.ts, integration tests, tests/e2e/scorm.spec.ts

[Implementation Details]:
- Isolation: env SERVICE_ROLE = app | scorm and SCORM_ORIGIN. The scorm deployment is the same code on a different hostname. In proxy.ts, when SERVICE_ROLE = scorm, only /api/v1/scorm/launcher/* and /content/* are reachable; everything else is 404 and no cookies are set or read. Refuse to start if SCORM_ORIGIN equals the app origin.
- Limits: package <= 50 MB, <= 2,000 entries, <= 200 MB uncompressed, per-entry compression ratio <= 100; extracted bytes count toward the storage budget.
- Ingest (after a scorm_package file is verified), as a chained job: each step downloads the archive once to the OS temp directory (one storage read), opens it with yauzl, rejects absolute paths, `..` and symlinks, requires a root imsmanifest.xml, uploads entries with bounded concurrency for at most 25 seconds, then checkpoints the entry index, deletes the temp file, and enqueues the next step.
- manifest.ts: fast-xml-parser with entity expansion disabled. Detect 1.2 vs 2004. Extract organizations, items, resources (href, scormType, masteryscore, launch data).
- Tables: scorm_packages, scorm_package_versions (immutable, each with a 128-bit random package_key; re-upload creates a new version; in-flight attempts stay on theirs), scorm_scos, scorm_attempts(enrollment_id, sco_id, attempt_no, cmi jsonb capped at 256 KB, completion_status, success_status, score_raw, score_min, score_max, score_scaled, total_time_s, suspend_data, location, commit_seq).
- Content route on SCORM_ORIGIN: /content/{packageKey}/{path}. Assets up to 4 MB are streamed with Cache-Control: public, max-age=31536000, s-maxage=31536000, immutable, so the platform CDN serves every student after the first and storage is read about once per asset. Larger assets 302 to a presigned URL and count against the daily read cap. The package key is the capability; it is handed out only through the launcher to enrolled users. Course content exposure equals an unlisted link; attempt data is never reachable this way.
- Frames: app page -> iframe to the launcher on SCORM_ORIGIN -> nested iframe to the SCO (same origin as the launcher). SCOs find window.API (1.2) or window.API_1484_11 (2004) by walking parent frames, so the launcher hosts them.
- The API must be synchronous: the launcher calls runtime/init and fills an in-memory CMI cache before setting the SCO iframe src. GetValue reads the cache; SetValue validates, writes and marks dirty; Commit flushes asynchronously (debounced 10 seconds, coalesced, to limit invocations); Terminate and pagehide flush with fetch keepalive.
- Auth for the launcher and runtime: a launch token (JWT via jose: userId, attemptId, scoId, exp 4h) as a Bearer header. Runtime routes allow CORS from SCORM_ORIGIN only, without credentials. Parent <-> launcher postMessage is origin-checked both ways and limited to token refresh, completion signal, resize, navigation.
- Implement the full API surface, session state machine and spec error codes for both versions.
- cmi-12.ts and cmi-2004.ts: element tables with type, access, vocabulary, range and max length (suspend_data 4,096 chars in 1.2; 64,000 in 2004). The server re-validates every commit. Read-only elements are set server-side; entry = resume when suspend data exists.
- Commits carry a monotonic seq; stale seq is ignored. time.ts parses 1.2 timespans and ISO-8601 durations; total time accumulates server-side.
- Normalize 1.2 lesson_status into completion and success; apply masteryscore when the SCO sets no status. On completion update lesson_progress and the gradebook item.
- Scope: single-SCO and multi-SCO with flat navigation. No IMS Simple Sequencing; packages declaring it are accepted with a warning. No offline SCORM.

[Verification]:
pnpm tsx tests/fixtures/scorm/build.ts
pnpm db:generate && pnpm db:migrate && pnpm tsx scripts/check-schema.ts
pnpm test:int src/modules/scorm
pnpm test:e2e tests/e2e/scorm.spec.ts
# Tests must prove: 1.2 and 2004 fixtures launch, set a score, suspend, and after reload GetValue returns the suspend data; zip-slip, zip-bomb and entity-expansion fixtures are rejected; extraction resumes correctly after a simulated step timeout; content responses carry immutable cache headers and a wrong package key is 404; an out-of-order commit is ignored; an expired or other-attempt token is refused; with SERVICE_ROLE=scorm every non-SCORM route is 404; from inside the SCO frame, reading the app page's document throws a cross-origin error.
```

---

**Prompt 11: Assessment Engine: Assignments, Quizzes, Attempts, Rubrics & Gradebook**

```cursor
[Context]: Builds on Prompts 7-9. Deterministic assessment core: authoring, timed attempts with a server-authoritative clock, objective auto-grading, rubric-based manual grading and a gradebook. The realistic peak for this system is one class of 80 starting the same exam in the same few seconds, so that path must be cheap in both database work and request count.

[Files to Create/Modify]:
- src/modules/assessments/schema.ts, service.ts, policy.ts, actions.ts, queries.ts, attempt-fsm.ts, autograde.ts, shuffle.ts, dto.ts, jobs.ts, index.ts
- src/modules/gradebook/schema.ts, service.ts, policy.ts, actions.ts, queries.ts, compute.ts, index.ts
- src/app/(app)/faculty/sections/[sectionId]/assessments/page.tsx, new/page.tsx, [assessmentId]/edit/page.tsx, [assessmentId]/submissions/page.tsx
- src/app/(app)/faculty/sections/[sectionId]/gradebook/page.tsx
- src/app/(app)/student/sections/[sectionId]/assessments/[assessmentId]/page.tsx, attempt/[attemptId]/page.tsx; src/app/(app)/student/grades/page.tsx
- unit, property and integration tests; tests/e2e/assessments.spec.ts

[Implementation Details]:
- Schema: assessments(section_id, type assignment|quiz|exam, points, opens_at, due_at, closes_at, late_policy jsonb, time_limit_s, max_attempts, scoring highest|latest|average, shuffle flags, show_results never|after_submit|after_close|after_release, grade_category_id, rubric_id, status); questions (bank: type mcq_single|mcq_multi|true_false|numeric|short_text|essay|file_upload, stem jsonb, options jsonb, answer_key jsonb, points, tags, difficulty, source human|ai, status draft|approved|retired); assessment_questions; accommodations(student, time_multiplier, extra_attempts, due_override); attempts(assessment_id, student_id, attempt_no, status, started_at, expires_at, submitted_at, snapshot jsonb, score, unique(assessment_id, student_id, attempt_no)); attempt_answers(attempt_id, question_id, response jsonb, client_seq, auto_score, manual_score, feedback, unique(attempt_id, question_id)); submissions(assessment_id, student_id, version, body jsonb, file_ids, submitted_at, is_late); rubrics, rubric_criteria, rubric_levels, rubric_scores.
- Attempt FSM: in_progress -> submitted -> grading -> graded -> released.
- Start, one transaction: check window, enrollment, accommodations, attempt count; INSERT ... ON CONFLICT DO NOTHING then read back (double clicks and retries yield one attempt); copy a keyless question snapshot into the attempt so later edits cannot affect it; expires_at = min(now + limit x multiplier, closes_at). The keyless snapshot per assessment is precomputed at publish, so start is one indexed read and one insert.
- Expiry without timers: every read or write of an attempt first checks expires_at and finalizes it if past (lazy expiry), and a job on each tick submits any in_progress attempt whose expires_at + 30 seconds has passed. Both paths call the same idempotent submit function.
- The client timer is display-only, derived from serverNow and expires_at. Saves after expiry plus grace are rejected.
- Autosave: answers are held locally and flushed in one batched request at most every 20 seconds, on question navigation, and on pagehide (sendBeacon), with a monotonic client_seq; upsert only when the incoming seq is greater. Also mirror answers to sessionStorage-free in-memory state plus IndexedDB so a refresh does not lose work. The UI shows saved/unsaved and retries on reconnect. Submit is idempotent and carries any unsaved answers.
- dto.ts: StudentQuestionView has no answer_key, correctness flags or explanations. A test serializes every student-facing payload and asserts their absence.
- shuffle.ts: seeded PRNG keyed by attempt id, reproducible for regrade disputes.
- autograde.ts (pure): mcq_single exact; mcq_multi all-or-nothing or partial (configurable); numeric with tolerance; short_text against an accepted list after NFKC, case and whitespace normalization, else routed to manual. essay and file_upload are manual.
- Assignment submissions keep every version; lateness computed server-side; only verified files attach.
- Gradebook: grade_categories(section_id, name, weight, drop_lowest); grades(enrollment_id, assessment_id, score, max_score, status draft|released, graded_by, released_at, version); grade_changes history. Optimistic concurrency on version. Release is an explicit action that notifies students in their digest.
- compute.ts: pure final-grade function (weights, drop-lowest, excused, late penalties, college grade scale) mirrored by a SQL view; a fast-check property test asserts they agree. CSV export.
- Integrity signals (focus-loss count, paste count) are information for faculty only; do not claim lockdown.
- The manual grading screen itself is built in Prompt 13.

[Verification]:
pnpm test src/modules/assessments src/modules/gradebook
pnpm db:generate && pnpm db:migrate && pnpm tsx scripts/check-schema.ts
pnpm test:int src/modules/assessments src/modules/gradebook
pnpm test:e2e tests/e2e/assessments.spec.ts
# Tests must prove: 20 concurrent starts by one student create one attempt; 80 different students starting concurrently all succeed on a pool of 3; a save after expiry is rejected; an abandoned attempt is submitted by the tick job and also by lazy expiry, exactly once; a page refresh mid-attempt restores unsaved answers; a 10-minute attempt with steady answering issues fewer than 40 requests; no student payload contains keys; a mid-attempt question edit does not change the snapshot; compute.ts equals the SQL view; concurrent graders conflict.
```

---

**Prompt 12: AI Gateway, Course-Material Text & Quiz Generation**

```cursor
[Context]: Builds on Prompts 8, 9 and 11. AI is used for one thing only: generating draft quiz questions from course material for faculty to review. Add one gateway for all LLM calls with hard caps for a free-tier key, extraction of text from course materials, and the generation flow. No vector database and no student data.

[Files to Create/Modify]:
- src/lib/ai/gateway.ts, models.ts, budget.ts, untrusted.ts
- src/lib/ai/prompts/quiz-generate.v1.ts, quiz-verify.v1.ts
- src/modules/ai/schema.ts, service.ts, queries.ts, index.ts
- src/modules/materials/schema.ts, service.ts, extract.ts, chunk.ts, jobs.ts, index.ts
- src/modules/assessments/generation.ts, generation-jobs.ts, actions.ts (generate + review)
- src/app/(app)/faculty/sections/[sectionId]/assessments/generate/page.tsx, review/[runId]/page.tsx
- evals/quiz-generation/cases.jsonl, evals/quiz-generation/run.ts
- docs/COSTS.md (AI row); unit and integration tests

[Implementation Details]:
- gateway.ts: runTask({ task, actorId, chunks: MaterialChunk[], params, schema }) on the Vercel AI SDK. The input type accepts material chunks only, so student submissions, names or grades cannot be passed by construction. Provider, model id and key come from env through models.ts; no model id at a call site. Structured output validated by zod; one retry on validation failure with the error appended; 25-second timeout with abort. Called only from job steps, one LLM call per step.
- Free-tier behavior: on HTTP 429 the step does not retry in place; it re-enqueues itself with run_at from the Retry-After hint (minimum 60 seconds). AI_MAX_REQUESTS_PER_DAY (default 100) and AI_MAX_REQUESTS_PER_USER_PER_DAY (default 20) are checked before every call; exceed -> QUOTA_EXCEEDED surfaced in the UI. ai_usage(task, model, input_tokens, output_tokens, at) and ai_runs(prompt id + version, input hash, validator results, status).
- Disclosure: the generate page and Settings state that selected course material is sent to an external AI provider, and that a free-tier key may allow the provider to use it to improve their models. A super_admin flag turns AI off entirely.
- untrusted.ts: material text is data: wrapped in delimited blocks, the model is told to treat it as content only, and the task gets no tools.
- Text extraction (job after a lesson document is verified or a rich-text lesson is published): PDF via unpdf, DOCX via mammoth, PPTX via zip + XML, rich-text JSON to plain text. Each extraction costs one storage read. PDFs with no text layer are marked needs_text and shown to faculty with a field to paste notes or a transcript (also the path for YouTube lessons). Never skip silently.
- chunk.ts: structure-aware (headings, slides, pages), 500-800 tokens, each chunk keeps a locator. material_chunks(lesson_id, idx, content, locator jsonb, content_hash). Re-extraction is idempotent on content_hash; chunks are deleted with their source. Cap stored text at 2 MB per section.
- Quiz generation, as a job chain. Input: lesson ids, count (max 30), type mix, difficulty mix. Chunk selection is seeded stratified sampling across the chosen lessons for even coverage. Each step generates one batch of 5 with schema { stem, type, options, correctIndexes, explanation, sourceChunkIds, difficulty }, then enqueues the verify step for that batch.
- Deterministic validators: option count and uniqueness; exactly one correct for single-answer; sourceChunkIds must be a subset of supplied chunks; length bounds; no "all/none of the above"; near-duplicates against the bank and the batch using pg_trgm similarity on normalized stems (> 0.8).
- Verify step (separate prompt that sees only the question and its cited chunks): answerable from the source, key correct, unambiguous. Failures are dropped; the run reports how many survived.
- Survivors are inserted as questions with status draft and source ai, with citations. Review UI: accept, edit, reject, with the cited passage shown. Nothing AI-generated reaches students without faculty approval. The run page polls status every 15 seconds while visible and states that work starts within a minute.
- Evals: cases.jsonl and a runner reporting validator and verifier pass rates; run manually, never in CI.

[Verification]:
pnpm db:generate && pnpm db:migrate && pnpm tsx scripts/check-schema.ts
pnpm test src/lib/ai src/modules/materials
pnpm test:int src/modules/materials src/modules/assessments/generation
pnpm tsx evals/quiz-generation/run.ts --limit 3
# Tests (provider faked) must prove: invalid output retries once then fails cleanly; a 429 re-enqueues with a delay instead of failing; the global and per-user daily caps block calls; with the AI flag off the generate action returns PRECONDITION_FAILED; a type-level test shows a submission cannot be passed to runTask; a question citing an unsupplied chunk is rejected; duplicates are dropped; generated questions are draft and absent from every student query; re-extracting an unchanged file creates no new chunks.
```

---

**Prompt 13: Manual Grading Workflow & Similarity (Plagiarism) Checks**

```cursor
[Context]: Builds on Prompt 11. There is no AI grading in this system, so make manual grading fast and add deterministic similarity detection that costs nothing. Similarity output is evidence for a human, never a verdict.

[Files to Create/Modify]:
- src/modules/grading/schema.ts, service.ts, policy.ts, actions.ts, queries.ts, index.ts
- src/app/(app)/faculty/sections/[sectionId]/assessments/[assessmentId]/grade/page.tsx, grade/[submissionId]/page.tsx
- src/components/app/grader/rubric-panel.tsx, comment-bank.tsx, submission-viewer.tsx, grader-nav.tsx
- src/lib/providers/similarity/{types,internal,fake}.ts
- src/modules/integrity/schema.ts, service.ts, policy.ts, actions.ts, queries.ts, fingerprint.ts, jobs.ts, index.ts
- src/app/(app)/admin/integrity/page.tsx
- unit and integration tests, tests/e2e/grading.spec.ts

[Implementation Details]:
- Grading screen ("grader"): submission on one side, rubric on the other. Click a rubric level to score a criterion; total computed live; overall feedback box; save writes rubric_scores and a draft grade with optimistic concurrency. Keyboard shortcuts: next/previous submission, number keys for levels, save-and-next. Loading the next submission reuses the page shell (one request per submission).
- Text submissions render inline. PDF and image submissions open in the browser's own viewer through the signed download route (one counted storage read per open); other types are download-only. Show the day's remaining read budget to the grader when it is below 30%.
- Comment bank: comment_snippets(owner_id, section_id nullable, text, usage_count). Insert a snippet into feedback with one click; snippets can be personal or shared within a section's instructors.
- Anonymous grading: a per-assessment toggle hides student names and shows stable pseudonyms until grades are released.
- Queue and progress: the grade index page lists ungraded, draft and released counts, sorts by submission time, and filters to "needs grading". Late submissions are flagged with the computed penalty.
- Bulk actions: release all drafts for an assessment (explicit confirmation), apply the same score and comment to selected students (for example non-submitters), and CSV import of scores with a dry run.
- Short-answer and numeric items routed to manual review by autograde appear grouped by question so identical answers can be scored together.
- SimilarityProvider interface: submit(doc) -> ref, getReport(ref). Only the internal implementation is built; the interface is the hook for a commercial checker later.
- fingerprint.ts: normalize text; hash 5-word shingles; winnowing with window 4; store submission_fingerprints(submission_id, hash bigint) indexed on hash, capped at 2,000 per submission. Runs as a job on submit. For file submissions the job extracts text with the Prompt 12 extractors (one storage read); this stays inside our own system and involves no AI.
- Candidates: the same assessment across terms and the same course in prior terms. Score by containment; recover matched spans for highlighting. Exclude assignment template text and, optionally, quoted and cited passages. For code submissions use a token-normalized variant.
- similarity_reports(submission_id, score, matches jsonb, status). Shown in the grader as a collapsible panel with side-by-side highlighted spans. Visible to the section's instructors and admins only; the other student's identity is masked unless the viewer has integrity:investigate. No automatic penalty and no automatic message to students.
- Do NOT build or integrate an "AI-written text" detector. It is unreliable and unsafe as evidence.
- integrity_cases(open -> under_review -> resolved with outcome) with audit, opened from a report by an instructor.

[Verification]:
pnpm db:generate && pnpm db:migrate && pnpm tsx scripts/check-schema.ts
pnpm test src/modules/integrity
pnpm test:int src/modules/grading src/modules/integrity
pnpm test:e2e tests/e2e/grading.spec.ts
# Tests must prove: rubric scoring computes the total and saves a draft; two graders saving the same submission conflict; anonymous mode never includes names in the payload; bulk release changes only drafts and notifies each student once; the score CSV dry run writes nothing; an 80%-copied fixture scores above threshold with correct spans while two independent essays score low; template text is excluded; a student cannot read any similarity report; grading 10 submissions end to end issues fewer than 40 requests.
```

---

**Prompt 14: Discussion Forums & Direct Messaging (Polling-Based Live Updates)**

```cursor
[Context]: Builds on Prompts 4-7. Add section forums and direct messages that feel live for 80 users without any realtime service. Postgres is the source of truth; clients learn about changes through one cheap, adaptive polling endpoint. Function invocations are capped by the host, so the polling budget is part of the design.

[Files to Create/Modify]:
- src/modules/messaging/schema.ts, service.ts, policy.ts, actions.ts, queries.ts, index.ts
- src/modules/forums/schema.ts, service.ts, policy.ts, actions.ts, queries.ts, index.ts
- src/modules/live/poll.ts, src/app/api/v1/live/poll/route.ts
- src/lib/live/types.ts, use-live.ts, intervals.ts
- src/app/(app)/messages/page.tsx, [conversationId]/page.tsx
- src/app/(app)/sections/[sectionId]/discussions/page.tsx, [threadId]/page.tsx
- src/components/app/message-composer.tsx, message-list.tsx; notification-bell.tsx (use the poll)
- docs/COSTS.md (request budget); integration tests, tests/e2e/messaging.spec.ts

[Implementation Details]:
- Ordering: every channel (conversation or thread) has last_seq. A write allocates seq with UPDATE ... SET last_seq = last_seq + 1 RETURNING inside the same transaction as the insert. client_msg_id is unique per author for idempotent retries.
- messaging: conversations(type direct|group, last_seq), conversation_participants(last_read_seq, muted), messages(conversation_id, seq, author_id, body jsonb capped at 20 KB, file_ids, edited_at, deleted_at). Policy: student <-> instructor of a shared section always allowed; student <-> student governed by a setting; user-level block list.
- forums: threads(section_id, title, type question|discussion|announcement, pinned, locked, anonymous_to_peers, last_seq), posts(thread_id, parent_post_id for one nesting level, seq, body, accepted_answer), post_votes unique(post_id, user_id). Anonymous posts hide the author from students; instructors always see the author.
- Poll endpoint: POST /api/v1/live/poll with body { watch: [{ kind, id, afterSeq }] (max 5), bell: boolean }. Authorize each watched channel. Respond with, per channel, lastSeq and up to 50 items with seq > afterSeq, plus unread counts for notifications and messages. One round trip, at most two indexed SQL statements. Returns 204 when nothing changed.
- use-live.ts (TanStack Query): poll only while the tab is visible and the device is online. intervals.ts: open conversation 5 seconds, rising to 20 seconds after one minute without changes; open thread 20 seconds; bell alone 120 seconds; immediate poll on focus, on reconnect, and right after the user sends. Hidden tabs make zero requests.
- Budget, written into docs/COSTS.md with the arithmetic: target under 150 poll requests per active student per day on average; the system page (Prompt 20) shows daily poll counts from a lightweight counter that is flushed with the tick, not written per request.
- LiveTransport is an interface (types.ts) with the polling implementation only, so a push transport can replace it later without touching features.
- Client: optimistic insert keyed by client_msg_id, reconciled when the poll returns the stored row.
- Moderation: soft delete with tombstone, report queue for instructors, lock and pin, per-user post rate limit, edit history retained.
- Body is the same allowlisted rich-text JSON as lessons; mentions resolved server-side against section membership; only verified files attach.
- Search: tsvector column with GIN index, limited to the caller's accessible sections and conversations.
- Notifications: announcements, mentions, replies to my thread and new DMs go into the email digest (Prompt 6) and the in-app feed; an item the recipient has already read is left out of the digest.
- No typing indicators and no presence.

[Verification]:
pnpm db:generate && pnpm db:migrate && pnpm tsx scripts/check-schema.ts
pnpm test:int src/modules/messaging src/modules/forums src/modules/live
pnpm test:e2e tests/e2e/messaging.spec.ts
# Tests must prove: 50 concurrent posts to one channel get gap-free unique seq values; a retried send with the same client_msg_id creates one message; watching a channel without access returns nothing for it; with two browser contexts a DM appears in the second within 8 seconds; a hidden tab makes no poll requests for 3 minutes (request interception); an idle visible page makes at most one poll per 120 seconds; the poll issues at most 2 SQL statements; an unchanged poll returns 204; a read message is not included in the digest.
```

---

**Prompt 15: Live Classes (Link-Out Provider, Check-In Codes, Optional Zoom Adapter)**

```cursor
[Context]: Builds on Prompts 6, 7 and 14. Schedule live sessions without paying for video infrastructure: the class runs in whatever free meeting tool the college already uses, opened in a new tab, while the LMS owns scheduling, access, reminders and presence. A thin Zoom API adapter is included for colleges that want automatic meeting creation.

[Files to Create/Modify]:
- src/lib/providers/meeting/{types,link,zoom,fake}.ts
- src/modules/live-sessions/schema.ts, service.ts, policy.ts, actions.ts, queries.ts, fsm.ts, checkin.ts, intervals.ts, jobs.ts, index.ts
- src/modules/webhooks/handlers/zoom.ts
- src/app/(app)/sections/[sectionId]/live/page.tsx, [liveSessionId]/page.tsx, [liveSessionId]/host/page.tsx
- src/app/api/v1/live-sessions/[liveSessionId]/join/route.ts
- docs/STACK.md (why no in-app WebRTC); integration tests, tests/e2e/live.spec.ts

[Implementation Details]:
- MeetingProvider interface: createRoom(session) -> { joinUrl, hostUrl?, providerRoomId? }, endRoom, parseWebhook -> normalized participant.joined / participant.left / room.ended. Do not build or embed WebRTC: one 80-person hour is about 4,800 participant-minutes, beyond free media quotas, and a self-hosted media server needs a paid machine. Record this in docs/STACK.md.
- link provider (default): the instructor pastes a meeting URL (validated against an allowlist of hosts in settings, e.g. meet.google.com, zoom.us, teams.microsoft.com, meet.jit.si) or picks "generate Jitsi room", which builds a URL with a 128-bit random room name. Meetings open in a new tab; never iframe third-party meeting pages.
- live_sessions(section_id, class_session_id nullable, provider, join_url, host_url, provider_room_id, starts_at, ends_at, status scheduled|live|ended|cancelled, recording_url); live_participations(live_session_id, user_id, joined_at, left_at, source click|checkin|provider).
- Join route: the meeting URL is never rendered in page HTML. The join endpoint authorizes (instructor or enrolled, within [starts_at - 10 min, ends_at + 15 min]), records a participation with source click, then 302-redirects.
- Presence for the link provider: checkin.ts issues a 6-digit code that rotates every 60 seconds (HMAC of session secret and time window; the secret stays on the server). The host page shows the current code large enough to screen-share (it refreshes once a minute) and the instructor can run 1-3 check-ins at random moments. Students enter the code in the LMS; a valid entry records source checkin. Attended = clicked join AND passed at least the required number of check-ins (setting). This feeds Prompt 16.
- zoom provider (optional, enabled only when its env vars exist): Server-to-Server OAuth with the token cached in a small DB table and single-flight refresh; create a meeting per session; webhooks through the Prompt 6 framework, verified with x-zm-signature (HMAC-SHA256 over v0:{timestamp}:{rawBody}); answer endpoint.url_validation; map participant joined/left into participations with source provider; unmatched participants go to a manual reconcile list. Note in the UI that free Zoom accounts limit meeting length.
- intervals.ts merges overlapping participation intervals into attended seconds for provider-sourced data.
- Jobs: reminder at T-2 hours as an immediate-class email (it falls inside the 2-hour deadline rule) plus an in-app notice at T-15 minutes; auto-end sessions 30 minutes after ends_at; on end, compute per-student attendance evidence and enqueue the attendance update.
- Recordings: instructors paste a recording link (for example an unlisted YouTube URL), which becomes a video lesson.

[Verification]:
pnpm db:generate && pnpm db:migrate && pnpm tsx scripts/check-schema.ts
pnpm test:int src/modules/live-sessions
pnpm test:e2e tests/e2e/live.spec.ts
# Tests must prove: a non-enrolled user cannot obtain the redirect; joining outside the window is refused; the meeting URL does not appear in any page payload; a URL on a non-allowlisted host is rejected; a check-in code from two windows ago fails; one student cannot check in twice for the same window; a forged Zoom signature is rejected and the URL validation challenge is answered; overlapping provider intervals merge correctly.
```

---

**Prompt 16: Attendance Tracking & Absence Notifications**

```cursor
[Context]: Builds on Prompts 6, 7 and 15. Automated attendance from rotating QR codes in the classroom and from live-session evidence, finalization of each class, and a deterministic rules engine that notifies the student, the instructor and administration. Recipients are students, teachers and administrators only; delivery is in-app plus the email digest.

[Files to Create/Modify]:
- src/modules/attendance/schema.ts, service.ts, policy.ts, actions.ts, queries.ts, qr.ts, fsm.ts, rules.ts, jobs.ts, index.ts
- src/app/api/v1/attendance/qr-token/route.ts
- src/app/(app)/faculty/sections/[sectionId]/attendance/page.tsx, [classSessionId]/page.tsx, [classSessionId]/display/page.tsx
- src/app/(app)/student/attend/page.tsx, src/app/(app)/student/attendance/page.tsx
- src/app/(app)/admin/attendance/page.tsx
- src/modules/notifications/templates/absence-*.tsx
- unit and integration tests, tests/e2e/attendance.spec.ts

[Implementation Details]:
- class_sessions(section_id, starts_at, ends_at, room, status scheduled|open|closed|finalized, qr_secret) generated two weeks ahead by a daily job from section_schedules, skipping holidays. attendance_records(class_session_id, student_id, status present|late|absent|excused, source qr|live|manual|system, marked_at, evidence jsonb, unique(class_session_id, student_id)).
- Rotating QR (qr.ts): payload { classSessionId, window, sig } with window = floor(now / 30s) and sig = HMAC-SHA256(qr_secret, classSessionId|window). To save invocations, the qr-token route returns the tokens for the next 10 windows (5 minutes) in one response and the display page rotates through them locally, refetching every 5 minutes; only the instructor's authenticated display page can call it, and the secret never leaves the server. Verification accepts the current window and the previous one. A screenshot is useless within a minute.
- Scan: the QR encodes a URL to /student/attend. The server checks session, enrollment, class open, signature and window, then upserts idempotently. Late = after starts_at + grace from settings.
- Anti-proxy signals: a device id cookie; one device may mark only one student per class session (a second attempt is refused and flagged for the instructor); per-student rate limit. No geofencing.
- Live classes: when a live session ends, apply the attended rule from Prompt 15 and upsert records with source live.
- Manual: instructors can mark or correct until the term closes; each change needs a reason and is audited. Excused absences come from a student request with instructor approval.
- Finalization job (on the tick, for classes past ends_at + grace): every enrolled student without a record becomes absent (source system); status -> finalized; enqueue rule evaluation with run_at = now + correction window (default 30 minutes).
- rules.ts is a pure function over a student's recent records and settings, returning actions:
  - single_absence -> notice to the student (digest) with a link to request an excuse.
  - bunk (present in an earlier class that day, absent in a later one) -> notice to the student and an entry in the admin daily absence report.
  - N consecutive absences, or attendance below the threshold percent in a section -> escalation to the section's lead instructor and to admins/registrars (digest), and a warning to the student.
- Notice job: re-read the record first. If it is no longer absent, send nothing. dedupeKey = student + class session + rule.
- Reports instead of floods: instructors get one line per class in their digest ("3 absent, 1 late"), not one email per student; admins get a single daily absence report listing absences, bunks and escalations with links.
- Admin view: daily absence list, chronic-absence report, flagged scans.

[Verification]:
pnpm test src/modules/attendance
pnpm db:generate && pnpm db:migrate && pnpm tsx scripts/check-schema.ts
pnpm test:int src/modules/attendance
pnpm test:e2e tests/e2e/attendance.spec.ts
# Tests must prove: a token older than two windows is rejected; a token for another class is rejected; a student cannot call the qr-token route; a non-enrolled student cannot mark; one device cannot mark two students; a double scan creates one record; finalization marks the remainder absent exactly once; an absence corrected inside the window sends nothing; the same absence never notifies twice; a class with 5 absences produces one instructor digest line and one admin report entry set, not 5 emails; rules.ts table-driven cases for single, bunk, consecutive and threshold.
```

---

**Prompt 17: Payments, Entitlements & Certificates**

```cursor
[Context]: Builds on Prompts 6-9. Sell course access and certificates with no fixed fees and no payment account. The whole commerce area sits behind a `payments` flag that is off by default. The default provider is manual: the student pays by bank transfer or wallet and the registrar approves the proof. A hosted-checkout adapter sits behind the same interface for later. Certificates work with or without payments.

[Files to Create/Modify]:
- src/lib/providers/payments/{types,manual,stripe,fake}.ts
- src/modules/commerce/schema.ts, service.ts, policy.ts, actions.ts, queries.ts, order-fsm.ts, jobs.ts, index.ts
- src/modules/entitlements/schema.ts, service.ts, queries.ts, index.ts
- src/modules/certificates/schema.ts, service.ts, policy.ts, actions.ts, queries.ts, template.tsx, sign.ts, index.ts
- src/modules/webhooks/handlers/stripe.ts
- src/app/(app)/catalog/page.tsx, catalog/[productId]/page.tsx, orders/[orderId]/page.tsx
- src/app/(app)/student/purchases/page.tsx, student/certificates/page.tsx
- src/app/(app)/admin/commerce/products/page.tsx, orders/page.tsx, orders/[orderId]/page.tsx
- src/app/api/v1/certificates/[certificateId]/pdf/route.ts, src/app/verify/[code]/page.tsx
- docs/STACK.md (hosting licence note); integration tests, tests/e2e/checkout.spec.ts

[Implementation Details]:
- Flag: with `payments` off, catalog and commerce routes return 404, products cannot be created, and certificates are issued on completion alone. docs/STACK.md records that turning payments on makes the deployment commercial, which the free hosting plan does not permit, and points to the container fallback in the runbook.
- PaymentProvider interface: begin(order) -> { kind: 'instructions' | 'redirect', ... }, parseWebhook(raw, headers) -> normalized events, refund(order). No provider types leak past the interface.
- products(type course_access|certificate, section_id or course_id, active); prices(product_id, amount_minor, currency, active); orders(user_id, reference_code unique, status pending|proof_submitted|paid|fulfilled|rejected|expired|refunded, amount_minor, currency, provider, provider_ref, proof_file_id, payer_reference); order_items; order_events.
- manual provider (default): begin returns payment instructions from settings (bank or wallet details) and the order's short reference_code. The student uploads a proof image/PDF (purpose payment_proof) and enters the transaction reference -> proof_submitted. The registrar reviews the proof beside the expected amount and approves or rejects with a reason (requires a fresh session; audited). payer_reference is unique when present, so one receipt cannot pay two orders. Pending orders expire after 7 days by job. Registrars see new proofs in-app and in their digest; the student gets the decision as an immediate email.
- stripe provider (optional, enabled only when its env vars exist): hosted Checkout; fulfillment only from signature-verified webhooks through the Prompt 6 framework; the return page reads status and never grants access; verify amount and currency against the order before marking paid.
- order-fsm.ts makes transitions monotonic so duplicated or out-of-order events and double clicks are safe.
- entitlements(user_id, product_id, source_order_id, starts_at, ends_at, revoked_at). Paying for course access creates the enrollment (source purchase) through the enrollment service so capacity rules apply; if the section filled meanwhile the order moves to a refund-due state and both sides are notified. Content and enrollment policies consult entitlements for paid sections. A refund revokes the entitlement.
- Certificates: eligibility is a pure function (section completed, final grade >= threshold, and the certificate entitlement only if it is a paid product). Issue on completion or on payment, whichever comes last; unique(user_id, section_id) makes issuance idempotent. certificates(serial, user_id, section_id, issued_at, revoked_at, signature).
- No stored PDFs: the pdf route renders on demand with @react-pdf/renderer from the certificate row, so storage use is zero. Rate-limit it and cache the response privately.
- sign.ts: Ed25519 signature over serial + recipient + course + date; public key published in docs. /verify/[code] is public and rate-limited, shows validity, minimal recipient details and revocation status. It is the only unauthenticated data page.
- Money is integer minor units; display with Intl.NumberFormat.

[Verification]:
pnpm db:generate && pnpm db:migrate && pnpm tsx scripts/check-schema.ts
pnpm test:int src/modules/commerce src/modules/entitlements src/modules/certificates
pnpm test:e2e tests/e2e/checkout.spec.ts
# Tests must prove: with the flag off every commerce route is 404 and completion still issues a certificate; with it on, no entitlement exists before approval; approving twice fulfills once; the same payer_reference cannot be used on two orders; a rejected order grants nothing and can be resubmitted; an expired order cannot be approved; a student cannot view another student's order or proof; purchase into a full section becomes refund-due; with the Stripe fake, the same webhook 3 times fulfills once and an amount mismatch is held; certificate issuance is idempotent; a tampered verification code fails; a revoked certificate shows as revoked.
```

---

**Prompt 18: Analytics: Retention Risk & Grading Velocity**

```cursor
[Context]: Builds on the academic, progress, assessment and attendance modules. Provide an explainable student risk score and faculty grading-velocity metrics. With 80 students there is no need for an event pipeline or a trained model: everything is computed from source tables with plain SQL.

[Files to Create/Modify]:
- src/modules/analytics/schema.ts, service.ts, policy.ts, queries.ts, jobs.ts, index.ts
- src/modules/analytics/risk/features.ts, score.ts
- src/modules/analytics/velocity.ts
- src/modules/activity/schema.ts, service.ts (daily activity marker)
- src/app/(app)/admin/analytics/retention/page.tsx, retention/[studentId]/page.tsx, grading/page.tsx
- src/app/(app)/faculty/analytics/page.tsx
- src/components/app/charts/*.tsx
- unit and integration tests

[Implementation Details]:
- Activity: activity_days(user_id, date, PK(user_id, date)) upserted at most once per user per day from getActor (guarded by a cookie so it costs one write a day). This is the only new tracking table; do not add a generic event log.
- features.ts computes, per enrollment, from existing tables with SQL: days since last active day, attendance rate and its 2-week change, missing-submission rate, late rate, grade trajectory (slope across released grades), lesson progress relative to the section median.
- score.ts is a pure weighted function with weights in settings, producing a 0-100 score, a band (low|medium|high), and the three largest contributing factors with their values. An enrollment with too little data returns "insufficient data", never "low risk". Never use protected attributes or proxies for them.
- Do not train a statistical model: 80 students cannot support one. Show this limitation on the dashboard: the score is a transparent early-warning heuristic, not a prediction.
- A weekly job snapshots risk_scores(enrollment_id, as_of, score, band, factors jsonb) so trends are visible; keep 2 years. A move into the high band appears in the admins' and registrars' digest with the factors (never sent to the student). intervention_notes(student, author, note, at) lets staff record follow-up.
- velocity.ts: per assessment, section and instructor: median and p90 hours from submitted_at to grade released_at, ungraded backlog and the age of the oldest item. A settings SLA (default 7 days) drives a weekly line in each instructor's digest and a summary for admins.
- Access: student-level risk is visible to super_admin, admin and registrar; instructors see only aggregate risk bands and their own velocity for sections they teach; students never see a risk score. Aggregates over fewer than 5 students are suppressed.
- Dashboards: shadcn charts (Recharts) rendered from Server Components, lazy-loaded; cached 15 minutes with tag invalidation; each chart has a table fallback and CSV export; filters in URL params. All queries must run under the 5-second statement timeout on the seeded dataset.

[Verification]:
pnpm db:generate && pnpm db:migrate && pnpm tsx scripts/check-schema.ts
pnpm test src/modules/analytics
pnpm test:int src/modules/analytics
# Tests must prove: score.ts table-driven cases produce the expected bands and factor order; no-data enrollments return "insufficient data"; velocity on a fixture equals hand-computed median and p90; an instructor cannot query another section; a group of 4 is suppressed; the weekly snapshot is idempotent for the same as_of; activity_days gets one row per user per day under repeated requests.
```

---

**Prompt 19: PWA, Offline Support & Web Push**

```cursor
[Context]: Builds on the full UI. Most students will use phones on unreliable connections. Make the app installable, keep lessons readable offline, queue safe writes, and add free push notifications as the second channel next to email. Offline scope stays narrow where integrity matters.

[Files to Create/Modify]:
- next.config.ts (Serwist), src/app/sw.ts, src/app/serwist/[path]/route.ts, src/app/manifest.ts, src/app/~offline/page.tsx
- public/icons/* (192, 512, maskable), src/app/layout.tsx (provider, viewport, theme color)
- src/lib/offline/db.ts (Dexie), outbox.ts, sync.ts, downloads.ts, purge.ts
- src/components/app/offline-indicator.tsx, install-prompt.tsx, update-toast.tsx, download-for-offline.tsx
- src/lib/providers/push/{types,webpush,fake}.ts, src/modules/notifications/push-subscriptions.ts, src/app/api/v1/push/subscribe/route.ts
- src/proxy.ts (CSP worker-src), src/lib/auth/client.ts (purge on sign-out)
- tests/e2e/offline.spec.ts, lighthouserc.json

[Implementation Details]:
- Use Serwist's Turbopack integration (@serwist/turbopack) following its current guide for the installed version; the worker source is src/app/sw.ts served by the route handler. No webpack-only plugin.
- manifest.ts: name and short_name from settings, start_url "/", display standalone, brand theme color, maskable icons.
- Caching: precache the shell and static assets; images (including the cdn media route) and fonts cache-first with expiration, which also reduces invocations and storage reads; navigations network-first with a 3-second timeout falling back to ~offline. Authenticated API responses are not cached generically by the worker.
- Offline lessons are explicit: "Download for offline" on a module stores lesson JSON in IndexedDB (Dexie) and lesson documents/images in a Cache Storage bucket named with the user id, with usage display and a remove control. Downloading documents uses the signed route, so show the user how many items will be fetched and respect the daily read budget. Only lessons the server reports as unlocked can be downloaded; items carry an expiry and revalidate when online. YouTube video and SCORM are not available offline; the UI says so.
- Shared-device safety: on sign-out, user change, or a 401, purge.ts deletes that user's IndexedDB data and caches before redirecting.
- Offline write queue: each operation = { id (sent as Idempotency-Key), route, body, createdAt }. sync.ts flushes on the online event, on visibility change, and via Background Sync where supported, with backoff. A 4xx moves the item to a visible "needs attention" list.
- Allowed offline: lesson progress (monotonic merge on the server), forum post and DM send (client_msg_id), assignment text drafts. Not allowed offline, with clear messaging: starting timed quizzes and exams, QR or code check-in, payments. An attempt already in progress keeps answers locally and flushes when the connection returns, but the server deadline still applies.
- Update flow: a new worker waits; update-toast offers reload; never activate silently while an attempt page is open.
- Web Push: VAPID with the web-push library (free, no account). push_subscriptions(user_id, endpoint unique, keys, user_agent, last_seen_at); subscribe only after an explicit tap; prune endpoints that return 404 or 410. Register `push` as a channel in the Prompt 6 delivery job. Push carries immediate-class items and, optionally per user, digest-class items in real time, which takes pressure off the daily email cap. On iOS push needs the installed app; install-prompt explains this.
- Mobile checks: no layout shift from the bottom nav, inputs do not zoom on focus, safe-area insets respected, student home works on a throttled 3G profile.

[Verification]:
pnpm build && pnpm start &
pnpm test:e2e tests/e2e/offline.spec.ts
pnpm dlx @lhci/cli@latest autorun
# e2e (context.setOffline) must prove: a downloaded lesson opens offline and a non-downloaded one shows the offline page; a forum post written offline is delivered exactly once after reconnect; offline lesson progress syncs; an attempt cannot be started offline, and answers given while briefly offline are saved after reconnect; after sign-out IndexedDB and user caches are empty; a new worker version shows the update toast; a user with push enabled and "push instead of email" set receives no digest email for those items. Lighthouse mobile: installable, performance >= 85 for the student home.
```

---

**Prompt 20: Deployment, Backups, Quota Guardrails, Observability & Verification**

```cursor
[Context]: Final stage. Deploy to free tiers that need no payment card and make the system safe to run there. The main risks are silent quota exhaustion (a host that pauses the project, a storage provider that stops serving reads, an email cap), no managed backups, and a paused database. This stage builds guardrails for exactly those, plus security tests and a load check sized to the real peak.

[Files to Create/Modify]:
- vercel.json, .github/workflows/ci.yml, deploy.yml, backup.yml, restore-drill.yml
- scripts/migrate.ts, scripts/check-migration-safety.ts, scripts/backup.sh, scripts/restore-check.sh
- src/app/api/health/ready/route.ts, src/app/api/internal/backup-report/route.ts
- src/modules/system/schema.ts, service.ts, queries.ts, counters.ts, jobs.ts, index.ts
- src/app/(app)/admin/system/page.tsx
- src/lib/providers/_shared/resilience.ts (timeouts, bounded retries), wired into every provider
- tests/security/idor.int.test.ts, tests/security/headers.e2e.ts, tests/chaos/degraded-modes.int.test.ts
- tests/load/exam-start.js, tests/load/README.md
- docs/COSTS.md (final), docs/RUNBOOK.md, docs/THREAT-MODEL.md

[Implementation Details]:
- Hosting: two Vercel projects on the free plan from the same repository: `lms` (SERVICE_ROLE=app) and `lms-scorm` (SERVICE_ROLE=scorm, only needed when the SCORM flag is on). vercel.json sets the function region nearest the students, and the Supabase project should be in the same geography. Usage limits are shared across the account.
- Deploys are driven from GitHub Actions, not automatic Git deploys: deploy.yml runs verify -> migrations -> `vercel pull`, `vercel build --prod`, `vercel deploy --prebuilt --prod` for each project using VERCEL_TOKEN, VERCEL_ORG_ID and per-project VERCEL_PROJECT_ID secrets. Disable automatic production deployments in the project settings.
- docs/RUNBOOK.md, hosting section: the free plan is licensed for non-commercial use and pauses a project that exceeds its included usage. Record (a) how to check the usage dashboard monthly, (b) that enabling the payments flag requires moving hosts, and (c) the fallback: build the Dockerfile and run it on any container host with a free tier, changing only the scheduler target URL. Note that small free container instances are much slower and may sleep when idle, so the per-minute tick doubles as a keep-alive there.
- Migrations: scripts/migrate.ts with DATABASE_URL_SESSION, run before deploy. check-migration-safety.ts fails on blocking patterns (NOT NULL without default, non-concurrent index on a large table, dropping a column the running release still reads). Rollback = promote the previous deployment; schema stays backward compatible for one release.
- Scheduler: apply scripts/cron.sql (Prompt 6) in the Supabase project and store the cron secret in Vault. The per-minute tick also keeps the free database from being paused for inactivity.
- Backups (the free database tier has none to rely on): backup.yml runs nightly: pg_dump over DATABASE_URL_SESSION -> gzip -> encrypt with age using a public key stored as a secret -> upload to the storage bucket under backups/ with the S3 CLI and also as a workflow artifact with 30-day retention (two independent copies) -> delete bucket copies older than 30 days -> call /api/internal/backup-report with the size. restore-drill.yml runs monthly and on demand: fetch the latest backup, decrypt, restore into a throwaway Postgres service container, compare row counts of key tables. The private key is kept offline; RUNBOOK.md has the manual restore steps.
- counters.ts: in-request counters are not persisted per request. The poll route and other high-volume routes increment a tiny table at most once per minute per instance (batched upsert on the tick path), giving approximate daily request counts by route class without a write per request.
- system module and /admin/system page (super_admin): database size against 500 MB with the 10 largest tables; storage bytes against STORAGE_BUDGET_BYTES; today's storage reads against STORAGE_DAILY_READ_CAP; emails sent today against the cap and the size of the deferred queue; AI requests today against the cap; approximate requests today and month-to-date against a configurable monthly invocation budget; job queue depth, oldest queued job age, dead jobs with retry buttons; last tick time; last successful backup time and size. A daily job puts a warning in the super admins' digest at 70% and sends an immediate email at 90% of any limit, and when the last backup is older than 36 hours or the last tick older than 10 minutes.
- Retention jobs keep the database small: confirm every append-only table has one (jobs, rate_limits, webhook_events, notifications older than 1 year, storage_reads, risk snapshots, audit_log) and add any that are missing.
- Monitoring: structured logs to stdout; /ready checks the database with a 2-second timeout and nothing else; the tick pings HEARTBEAT_URL (any free dead-man's-switch service) so a stalled scheduler or paused project produces an email. Optional Sentry via SENTRY_DSN, off by default.
- resilience.ts: every provider call has a timeout and bounded jittered retries for idempotent operations. tests/chaos proves each degraded mode: SMTP down -> deliveries stay queued and the in-app feed still works; AI down or over quota -> generation shows a clear state and everything else works; storage down or over its read cap -> downloads fail with a clear message and lessons without files still load; payments adapter down -> manual flow unaffected.
- Security verification: idor.int.test.ts enumerates every action and /api/v1 route from the registries and calls each as (a) the wrong role, (b) the right role with the wrong relationship, (c) signed out, asserting FORBIDDEN, NOT_FOUND or UNAUTHENTICATED and no writes. The two capability routes (media, SCORM content) are tested separately: a wrong key is 404 and they can never return a file whose delivery mode is signed. headers test asserts CSP, HSTS and cookie flags on each route class, and that internal routes reject requests without the secret. Dependency audit and secret scanning in CI. THREAT-MODEL.md lists trust boundaries (SCORM origin, capability URLs, webhooks, uploads, LLM inputs, public verify page, internal tick) and the control for each.
- Load check sized to reality and to the quota (k6, short, against the deployed app, run once before each term): 80 virtual users start the same exam within 5 seconds, flush answers every 20 seconds for 5 minutes, then submit. Thresholds in the script: error rate < 1%, p95 < 1,000 ms excluding the first cold-start request, no connection-pool errors. Record results, total requests used, and the measured cold-start time in tests/load/README.md.
- docs/COSTS.md final: one row per service with free limit, our cap, behavior at the cap, where to check usage, and the first paid step if ever needed. State the availability expectation honestly: best effort on free tiers, no SLA.

[Verification]:
pnpm verify
pnpm test:int tests/security tests/chaos
pnpm test:e2e
pnpm tsx scripts/check-migration-safety.ts
gh workflow run deploy.yml && gh run watch
curl -fsS https://<app-url>/api/health/ready
curl -s -o /dev/null -w "%{http_code}" https://<scorm-url>/    # expect 404
gh workflow run backup.yml && gh workflow run restore-drill.yml
k6 run tests/load/exam-start.js
# Done when: the app is live and the SCORM project returns 404 for /; /admin/system shows a tick within the last 2 minutes; a backup exists in the bucket and as an artifact, and the restore drill passes its row-count comparison; the IDOR suite covers 100% of registered actions and routes; every chaos case shows its documented degraded behavior; k6 thresholds pass; /admin/system shows every usage figure below 70%.
```
