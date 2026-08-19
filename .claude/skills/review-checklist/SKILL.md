---
name: review-checklist
description: Criteria data for the `code-review` skill — Secret-Sauce's actual failure modes: destructive db:* scripts against SUPABASE_DB_URL, Postgres trigger/RLS/GRANT geography, client writes that fail silently when RLS denies them, SQL re-run idempotency, pinned Flutter/melos toolchain, credential-file globs. Loaded by `code-review` Step 0; do not invoke directly — invoke `code-review`, which reads this. Read it directly only when asked what this repo's review rules are.
---

# Secret-Sauce review checklist

Apply on top of ordinary correctness review. These encode the failure modes this codebase
actually has. Report a finding only when you can name a concrete input or timing that
produces the wrong behavior. Cite `docs/BUG-TRACKER.md` IDs where listed.

## 1. Destructive DB scripts run against whatever `SUPABASE_DB_URL` points at — Critical

`tool/db.dart:38-71` pipes a SQL file into `psql` using `SUPABASE_DB_URL` verbatim, with **no
confirmation and no prod/local guard**. `db:reset` runs `drop → create → seed`, and `drop.sql`
drops `recipes`, `profiles`, and every content table `cascade`. `seed.sql` writes directly into
`auth.users` with fixed UUIDs and `email_confirmed_at` set, and `README.md`'s "Seed sample
recipes" tells you to paste it into the **hosted** dashboard — so anything in that file executes
on production by documented procedure. Passwords there are randomized
(`crypt(gen_random_uuid()::text, gen_salt('bf'))`) precisely because of this — B018 was nine
log-in-able production accounts whose credentials sat in the repo.

Flag when a diff: adds a destructive action to `tool/db.dart` or widens `drop.sql`/`clean.sql`
without a confirmation or environment check; adds a `db:*` melos script or wires `db:*`/`psql`
into `.github/workflows/*` (CI has no `SUPABASE_DB_URL` today — a new one aims a drop at whatever
secret is added); or puts **any literal credential** in `seed.sql` — a password, token, or API
key, including for an account "nobody uses". `drop.sql` deliberately spares `auth.users`, so a
seeded account is permanent and `db:reset` cannot remove it.

Suggested fix shape, **advisory by project decision**: gate destructive actions on an explicit
opt-in (`--yes`, or refuse a host that isn't `localhost`/`127.0.0.1`). Its absence in today's
`tool/db.dart` is a known, accepted state — mention at most once as a Nitpick, never as a standing
Critical on an unrelated diff. Critical attaches to a diff that *widens* blast radius, not to the
status quo.

## 2. Trigger / RLS / GRANT geography — Critical

Three distinct enforcement layers must agree, and each has already produced a silent outage:

- **Trigger rights (B011).** A trigger writing a row the acting user does not own must be
  `security definer set search_path = public`, or its `UPDATE` matches 0 rows *with no error*.
  Live: `on_like_change`, `on_save_change`, `on_rating_change`, `handle_new_user`, `fork_recipe`,
  `can_read_recipe`, `owns_recipe` (`0001_init.sql:222-336`, `392-421`, `709-716`).
- **RPC exposure.** PostgREST exposes every `public` function as an RPC. Mutating helpers
  (`bump_count`, `recompute_recipe_rating`) stay invoker-rights **and** have EXECUTE revoked from
  `public`/`anon`/`authenticated` (`0001_init.sql:359-367`) — otherwise a client forges counters.
  A new `security definer` function must open with an authorization check the way `fork_recipe`
  does (`raise exception` unless `can_read_recipe(p_source)`, line 724).
- **GRANTs (B013).** RLS decides *which rows*; GRANT decides whether the role may touch the table
  at all. Coverage comes only from the `grant … on all tables in schema public` block at
  `0001_init.sql:565-581`, so a `create table` added *after* it gets no grants and answers
  `permission denied for table …`.

Flag when a diff: adds a trigger function without `security definer set search_path`; adds a
`public` function that mutates without a matching `revoke execute`; adds a table below the
grants block or outside it; adds a table with `enable row level security` but no policy (RLS
default-denies — reads return empty, not an error); or adds an FK to `profiles` without
considering B015 (an `auth.users` row can exist with no `profiles` row; the backfill at
`0001_init.sql:245-249` is what repairs it — keep it after any `profiles` change).

**View counting (B012, fixed).** `on_view_insert` rolls `recipe_views` into `recipes.view_count`,
but counts **distinct signed-in viewers**, not visits: it skips rows with a null `user_id` and
skips a user's second-and-later row for the same recipe. Two properties keep
`recipes_trending`'s `like_count + view_count` score honest, and a diff must not break either —
`anon` holds `insert` on `recipe_views`, so counting anonymous rows would make trending
inflatable without an account, and `views_insert` pins `user_id` to `auth.uid()` or null, so
views cannot be attributed to another user. Flag any diff that adds a unique constraint on
`recipe_views` (PostgREST cannot express `on conflict` against a partial index — `logView()` is
deliberately a plain insert), counts anonymous views, relaxes that policy, or removes the
`pg_advisory_xact_lock` guarding the read-then-write dedup probe. `view_count` is **monotonic and
an upper bound**, not an exact distinct count — nothing decrements it and `user_id` is
`on delete set null`; flag any diff that treats it as equal to a `count(distinct …)` over the log.
Note when reviewing seeded data that `seed.sql` writes `view_count` directly and never inserts
`recipe_views` rows, so seeded counters intentionally do not match their log.

## 3. Client writes that cannot see an RLS rejection — High

Know which half of this is real, or you will file false positives. An **insert/upsert** violating
a `with check` clause raises `42501` and surfaces through the caller's `catch`. An **update or
delete matching 0 rows returns success** — indistinguishable from a write. So the rule applies to
`.update()`/`.delete()` only: flag one with no `.select()` on a path where the user may not own
the row (sharing, editing a shared recipe, admin-ish flows) — the client-side twin of B011.
`SupabaseRecipeRepository` currently does this throughout (`recipe_repository.dart:143-158`,
`202-229`, `263-269`); severity scales with what a silent no-op costs on that path. Also:

- **Column allowlist.** `_writablePayload` (`recipe_repository.dart:115-129`) omits server-managed
  columns. Flag a diff adding `rating_avg`/`rating_sum`/`rating_count`/`like_count`/`save_count`/
  `view_count`/`current_version_id`/`created_at`/`updated_at` to a client payload — trigger-owned
  (CLAUDE.md, "Ratings").
- **Signed-out paths.** `_uid` throws `StateError` (`recipe_repository.dart:76-80`). Flag a new
  repository call reachable from a signed-out screen (Home, Discover, recipe detail) unless it
  uses `currentUser?.id` like `logView`/`myRating` do.
- **Non-atomic update.** `update()` deletes all `ingredient_groups`/`step_groups` then re-inserts
  (`recipe_repository.dart:147-150`); a failure between them loses the recipe's content. Flag any
  diff lengthening that window.
- **Numeric decoding.** Postgres `numeric` arrives as a JSON number that may be int or double —
  decode via `(value as num).toDouble()` (`recipe_repository.dart:249-250`), never a bare
  `as double` on a new numeric column.

## 4. SQL must survive re-running — High

`0001_init.sql` is the single source of truth, applied repeatedly (`db:create`, `supabase db
reset`, hosted re-apply), so every statement is guarded (`if not exists`, `drop policy if
exists`, `create or replace`, `alter table add column if not exists`).

Flag when a diff: adds a bare `create table`/`create type`/`create policy` with no guard; adds an
`alter table … add column` lacking `if not exists`; or adds an early `return` to a seed helper
that skips later work — exactly B014, where `seed_recipe`'s "already exists" branch skipped the
new rating inserts and ratings silently stayed 0 (fix shape: the early-return path still calls the
new work, `seed.sql:83-87`). Also flag any changed function **signature** in `seed.sql` /
`0001_init.sql` without a matching `drop function if exists <exact signature>` in `drop.sql` —
Postgres keys drops by argument list, so the old overload survives; `drop.sql:42-43` already
carries two `seed_recipe` signatures from one such change.

## 5. Pinned toolchain — High

The Flutter pin is load-bearing, not hygiene (B005): Flutter ≥ 3.47 ships Dart 3.13, which the
`analyzer` 7.x behind `freezed` 2.x cannot parse — `build_runner` dies with
`Missing implementation of visitDotShorthandPropertyAccess`.

Flag when a diff: changes `flutter-version: 3.44.8` (`.github/workflows/ci.yml:20`) or swaps it
for `channel: stable`; bumps `freezed`/`json_serializable`/`analyzer` constraints with no
matching note in `README.md#toolchain-versions`; drops `--no-select` from a `melos run` of a
`packageFilters` script — `test`, `build_runner`, `build:*`, `gen:icons` (B006: picker aborts with
`StdinException: Error getting terminal echo mode` in any non-TTY). On dependency changes, note
that `pubspec.lock` is git-ignored (`.gitignore:7`, B009 still **open**), so widening a constraint
resolves differently per machine and per day.

B007 (`melos` exits 0 after crashing) is a **`melos.bat` shim bug — Windows/local shells only**.
Linux CI's wrapper propagates exit codes, so `ci.yml` relying on them is correct and **not** a
finding. Applies to `.ps1`/`.bat`/local scripts — and to your own verification: running `melos` on
Windows, grep output for `SUCCESS`/`FAILED` rather than trusting the exit code.

## 6. Credential surfaces — Critical

B010: `**/env.local.json` alone did not match an extension-less `env.local` holding live keys.
`.gitignore`'s "Local dart-define env files" block is now `env.local*` / `**/env.local*` /
`**/env.*.local*` with `!**/env.example.json`. Flag a diff narrowing those globs, adding a
credential filename outside them, or putting a real URL/key in `apps/app/env.example.json`.
Untracked tool state counts too: `supabase/.branches/` and `supabase/.temp/` are ignored because
`.temp` gains `project-ref` / `pooler-url` after `supabase link` — flag any new tool-generated
directory left untracked-and-unignored.

`SupabaseService.init()` guards missing dart-defines with `assert` — **stripped in release
builds**, so a release built without `--dart-define-from-file` initializes Supabase with empty
strings. Flag any new required config guarded only by `assert` on a release path.

Verify citations before quoting them: `.gitignore` line numbers in particular have already
drifted once. Prefer naming the pattern or symbol over the line.

## 7. Flutter layout and adaptive rendering — Medium

Three logged bugs are `RenderFlex` overflows: B001 (card in unbounded height), B002 (grid with
fixed aspect ratio), B016 (rating pill added to a row with no flexible child). Flag when a diff:
adds a `Text` inside a `Row`/grid cell with no `maxLines` + `overflow`; adds a child to a
**fixed-height grid tile's** row where every child is intrinsically sized — `Spacer` absorbs
slack but cannot shrink anything, so the row has no capacity to degrade (B016); or changes
`kRecipeCardHeight` / `kRecipeCardMinWidth` / `kRecipeCardMaxWidth` / the grid delegate in
`recipe_grid.dart` without checking the narrow end. `RecipeCard` has exactly one flexible band
(the cover); anything added to the banner or the footer comes out of a fixed budget.

**Card grid sizing.** The recipe grid flows from the available width (`FlowGridMetrics.fit`), not
from a breakpoint. Flag a diff that: reintroduces `responsiveColumns` or `childAspectRatio` into
`recipe_grid.dart`; adds a `ConstrainedBox`/`SizedBox` width cap inside `RecipeCard` (a grid
cell's tight constraints override it — the cap has to come from the grid's padding); or lowers
`kRecipeCardMinWidth` without re-pinning the card envelope tests to the new minimum.

**Test the real envelope, not a convenient one.** The card cannot grow, so the row must degrade.
The three axes that actually break it:

| Axis | Worst realistic value | Why |
| --- | --- | --- |
| Card width | **264px** | `kRecipeCardMinWidth` — the narrowest column `FlowGridMetrics.fit` packs to before wrapping (`adaptive.dart`); narrower than the 1-column compact case, which is capped at `kRecipeCardMaxWidth` 340 |
| Content | longest label per field | `_timeLabel` reaches `"12h 45m"`; `ratingCount` reaches 4 digits |
| Text scale | **2.0×** | accessibility scaling; the default-scale margin is thin but positive |

A test at one comfortable width with short content proves nothing — B016 shipped past exactly such
a test (`ratingCount: 12`, `totalMinutes: 0`, 320px). **When quoting overflow figures:**
`flutter test` uses a fixed-width font much wider than Roboto, so "overflowed by N pixels"
overstates the on-device case — use it to prove a row *cannot degrade*, not as a production
measurement. New `design_system` widgets must be added to the `design_system.dart` barrel or
`apps/app` cannot import them.

## Project review settings

- **Integration target: `main`.** It is the only branch and both CI triggers gate on it
  (`.github/workflows/ci.yml:3-7`). Most work lands as working-tree changes on `main` — default
  to reviewing staged + unstaged rather than a three-dot diff.
- **Severity defaults:** §1 and §6 findings are Critical. §2 and §4 are Critical when they
  affect `0001_init.sql`/`drop.sql`, High otherwise. §3 and §5 are High. §7 is Medium.
- Generated `*.g.dart` / `*.freezed.dart` are git-ignored (`.gitignore:11-13`) — their absence
  from a diff is never a finding; the missing `melos run build_runner` is (see below).
- **`packages/core` now has a `test/` dir, but it covers model decoding only.** Every repository
  method is still untested and still blocked on mocking `SupabaseClient`, and **no SQL is tested
  anywhere** — CI has no database job. A green `melos run test --no-select` says nothing about a
  repository or schema change; require local-stack evidence for those.

## Doc-sync obligations

From CLAUDE.md "Docs–code sync (MANDATORY)" — a change is not complete until these appear in the
same change set. Report misses as `⚠️ Potential issue`.

| Changed path | Doc that must also change |
| --- | --- |
| any behavioral change | `docs/ROADMAP.md` (task status or new task) |
| `supabase/**`, `packages/core/lib/src/models/**`, `packages/core/lib/src/repositories/**` | `docs/SDS.md` (§3 data model, §4 RLS, §6 ranking) |
| a roadmap task implemented | `docs/EXECUTION-PLAN.md` |
| any bug found or fixed | `docs/BUG-TRACKER.md` (new row, or status change) |
| `melos.yaml`, `.github/workflows/**`, `tool/db.dart`, `apps/app/pubspec.yaml`, `env.example.json`, platform dirs (`android/`, `ios/`, `windows/`) | `README.md` **and** CLAUDE.md "Common commands" |
| new/changed `design_system` widget | `docs/SDS.md` §8 (RecipeCard contract / rating widgets table) + barrel export |

## Companion handoffs

- Diff touches any `@freezed` / `@JsonSerializable` file (all of them live in `packages/core` —
  the only package with `build_runner`) → `melos run build_runner --no-select` must have been run;
  codegen output is not in the diff, so say so rather than looking for it. Providers are
  hand-written: a diff adding a `@riverpod` annotation is itself a finding.
- Diff touches Dart under `packages/` or `apps/` → `melos run analyze` (no filters, never prompts)
  and `melos run test --no-select`.
- **Skip both** on a docs-only or SQL-only diff; state the skip in one line.
- Diff touches `supabase/**` → the change is only verified against a local stack
  (`supabase start` + `supabase db reset`, RLS exercised via `set local role authenticated` +
  `request.jwt.claims`). Absent evidence of that run, flag the diff as unverified rather than
  approving the SQL on inspection.
