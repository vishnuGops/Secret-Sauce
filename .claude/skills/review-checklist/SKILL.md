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
without a confirmation or environment check; **adds a `SUPABASE_DB_URL` secret to
`.github/workflows/*`** — CI does run SQL now (`database.yml`, OPT-T1) but only against the
ephemeral stack it starts inside the runner, at a hard-coded local address, and a secret there
would aim `drop.sql` at whatever the secret is; or puts **any literal credential** in `seed.sql` —
a password, token, or API key, including for an account "nobody uses". `drop.sql` deliberately spares `auth.users`, so a
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

**Column grants (B050, fixed by OPT-S1).** RLS filters rows and cannot filter columns, so
`recipes` and `profiles` no longer hold a blanket `insert, update` grant — they hold explicit
column lists in the grants block, mirroring `_writablePayload` / `ProfileRepository.updateMine`.
Flag a diff that: adds a **client-writable** column to either table without adding it to the
matching grant list (the first save that sends it fails `42501`); adds a **server-owned/derived**
column *to* a grant list (that reopens the leaderboard-laundering hole); restores a table-level
`grant update on recipes/profiles`; or writes a server-owned column from Dart. `current_version_id`
is maintained by the `recipe_versions_set_current` trigger — a client PATCH of it is now a bug,
not a convention violation.

**A SELECT policy must not look the row up again (B053, fixed).** Postgres applies the SELECT
policy to the rows an `INSERT … RETURNING` gives back, and PostgREST sends every
`.insert().select()` that way. `recipes_select` used to be `can_read_recipe(id)` — a `stable`
function that re-queries `recipes` by id — so it read the statement snapshot, could not see the
row being inserted, and **every recipe creation failed** with `new row violates row-level security
policy`. It is now inlined against the row's own columns. Flag any SELECT policy that calls a
`stable` function taking the row's **own** id, or otherwise re-queries its own table; passing a
*parent* id (the child tables' `can_read_recipe(recipe_id)`) is fine, since that row already
exists. Seed and sim run as `postgres` and bypass RLS, so this class of bug is invisible to
`3_sim_verify.sql` — it only appears when a real signed-in client writes.

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
- **Saving is one transaction (OPT-A1).** `create()`/`update()` call the `save_recipe` RPC, which
  does row + content + version atomically and computes `version_number` under the row lock. Flag a
  diff that moves any of those steps back to the client, that writes `recipe_versions` from Dart,
  or that adds a client-writable column to `_writablePayload` without adding it to **both** the
  grants block and `save_recipe`'s column list — the last one fails silently, since an absent key
  just never saves. `save_recipe` is `security definer`, so it must keep its `owns_recipe` check
  and its `revoke execute from public/anon`. It must reach `kRecipeSelect` too, or it decodes as
  null on the way back with no error (Gotcha 17). Note the **grant** omission is silent for a
  column the app only ever writes through the RPC — definer rights bypass it — so a new one also
  needs a positive owner-update check in `supabase/tests/rls_matrix.sql`, which is the only thing
  that proves the grant exists. `recipes.nutrition` (Phase 28) is the worked example.
- **A `jsonb` column carrying a Dart model.** `null` from Dart arrives as `'null'::jsonb`, which
  is **not** SQL `NULL` and fails any `jsonb_typeof` check — flag an extraction that is not
  wrapped in `nullif(…, 'null'::jsonb)`. Flag `->>` where `->` is meant: there is no implicit
  text→jsonb cast, so the wrong arrow is a runtime error on the first save.
- **Nested-model `toJson` (B071).** `explicitToJson` is off for `packages/core`. Flag a new
  model-typed field on a `@freezed` class that has neither `includeToJson: false` nor an explicit
  `@JsonKey(toJson: …)` — the generator emits the object itself and `jsonEncode` throws at the
  call site, not at the model.
- **Numeric decoding.** Postgres `numeric` arrives as a JSON number that may be int or double —
  decode via `(value as num).toDouble()` (`recipe_repository.dart:249-250`), never a bare
  `as double` on a new numeric column.

## 4. SQL must survive re-running — High

`supabase/migrations/` is a numbered sequence applied in filename order. `0001_init.sql` is the
baseline, and **it is editable while the project is pre-release** — owner's call, 2026-08-23,
reversing OPT-A9's freeze (CLAUDE.md Gotcha 5; Phase 26's shelf RPCs were folded back in and
`0002_discover_shelves.sql` deleted). So a diff that edits 0001 is **not** a finding today. It
becomes one the day the schema reaches a database that is not ours, because the CLI records applied
versions in `supabase_migrations.schema_migrations` and never re-runs a recorded one — from then on
schema changes belong in a new `NNNN_*.sql` and an edited baseline is silently a no-op. Check
`supabase/migrations/README.md` before assuming which regime is in force.
`melos run db:create` applies the whole directory and tracks no history either way, so every
migration is still applied repeatedly and every statement stays guarded (`if not exists`,
`drop policy if exists`, `create or replace`, `alter table add column if not exists`).

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
that `pubspec.lock` is **committed** (B009, closed by OPT-T4) — a dependency change must arrive
with its lockfile diff, and a diff that re-ignores the lockfiles is itself a finding.

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
(the cover); anything added to the banner or the footer comes out of a fixed budget. The banner is
a **fixed** band (`kRecipeCardBannerHeight` × `context.textScale`, capped at
`kRecipeCardBannerMaxScale`) so one- and two-line titles match (B047) — flag a diff that makes it
intrinsic again, that pins it to a raw pixel height with no text-scale factor (two lines of 2.0×
type do not fit in 65px), or that removes the cap: an unbounded band starves the cover in a
fixed-height tile and turns a 17px overflow at 3.0× into a 48px one (B049).

**Card grid sizing.** The recipe grid flows from the available width (`FlowGridMetrics.fit`), not
from a breakpoint. Flag a diff that: reintroduces `responsiveColumns` or `childAspectRatio` into
`recipe_grid.dart`; adds a `ConstrainedBox`/`SizedBox` width cap inside `RecipeCard` (a grid
cell's tight constraints override it — the cap has to come from the grid's padding); or lowers
`kRecipeCardMinWidth` without re-pinning the card envelope tests to the new minimum.

**Test the real envelope, not a convenient one.** The card cannot grow, so the row must degrade.
The three axes that actually break it:

| Axis | Worst realistic value | Why |
| --- | --- | --- |
| Card width | **288px** | `kRecipeCardMinWidth` — the narrowest column `FlowGridMetrics.fit` packs to before wrapping (`adaptive.dart`); narrower than the 1-column compact case, which is capped at `kRecipeCardMaxWidth` 340. Raised from 264 by B048: it is the floor at which the metadata row fits *uncut*, so a diff that lowers it is buying a column out of the footer |
| Content | longest label per field | `_timeLabel` reaches `"12h 45m"`; `ratingCount` reaches 4 digits |
| Text scale | **2.0×** | accessibility scaling; the default-scale margin is thin but positive |

**Two flex children in one row split it 50/50 (B038, B026).** `RenderFlex` divides free space by
flex factor, so `Expanded` beside `Flexible` reserves half for each whatever the content is — the
short child leaves dead space, the long child truncates beside it, and nothing overflows, so no
envelope test fails. Flag a row where one child must win and both carry a flex; the accepted shape
is the loser **non-flex inside a `ConstrainedBox`** cap (`LayoutBuilder` → `maxWidth / 2` or `/ 3`),
`FittedBox` if it is a number — `RecipeCard`'s `DifficultyBadge`, `ChefSpotlightCard`'s score and
points. The converse is also a finding: a **non-flex child of a `Row` is laid out unbounded**, so
one added without a cap overflows instead of shrinking (B039, the spotlight rank pill at 3.0×;
B057, the rail's ranking kicker).

**The cap is not the only accepted shape, and it is the wrong one when every child must keep
shrinking (B080).** Then the *weights* carry the priority, and the direction is the part people get
backwards: `RenderFlex` gives each flex child `freeSpace × flex / totalFlex` as its **maximum**, so
a larger factor protects a child rather than sacrificing it. Flag (a) sibling flex children with
**equal** factors where one is plainly shorter than the other — the short one reserves half the row
it does not need, which is this same mechanism one level in; and (b) any comment claiming "X yields
first" sitting above a row where **X carries the larger factor** — that is B080 verbatim, and it
clipped `RecipeCard`'s rating to `5…` while keeping the count. Do not propose the `ConstrainedBox`
cap as the fix without checking the envelope: capping `RecipeCard`'s time label at `maxWidth / 3`
was tried and starved the rating pill until its own `Row` overflowed, in four previously-green
cases. **None of this trips an overflow**, so `takeException()` cannot see it; the assertion that
can is `RenderParagraph.didExceedMaxLines` written as an implication (`value clipped ⇒ count
clipped`), never as a pixel width — the harness font is far wider than Roboto, so a width pins the
harness and an implication survives.

**A childless box sizes to the wrong end of the constraints (B060).** `Container`/`SizedBox` with
no child and no width takes `constraints.biggest` when bounded and `constraints.smallest` when not.
Flag one used as a **rule or underline under a label**: in a `Column` it stretches to the parent's
width (which is how Discover's three sort links ended up stacked, one per line), and in the
unbounded position above it collapses to zero and is simply **not drawn** — the selected-state
indicator was invisible on the web. Neither overflows and neither fails an envelope test. Accepted
shape: a `BorderSide` on the box that holds the label.

**Height budgets, not just width (B037).** `Column(header, Expanded(body))` gives the header its
intrinsic height first; a header taller than the viewport leaves `Expanded` nothing and the column
overflows regardless of what is flexible below. Flag a new fixed-height page region — a
non-scrolling hero, a row of fixed-height columns — that is not bounded against **text scale**.
`context.textScale` (`adaptive.dart`) is the shared measurement; `/chefs` uses it to stack the hero
below `900 × textScale` px and to drop the whole page to one scroll above
`ChefsScreen.maxTwoColumnTextScale`. `ChefSpotlightCard` is the other pattern: a fixed-size tile
whose intrinsic bands exceed its budget before 2.0×, so the tile grows with the text
(`spotlightCardHeight`) rather than dropping bands.

A test at one comfortable width with short content proves nothing — B016 shipped past exactly such
a test (`ratingCount: 12`, `totalMinutes: 0`, 320px). **When quoting overflow figures:**
`flutter test` uses a fixed-width font much wider than Roboto, so "overflowed by N pixels"
overstates the on-device case — use it to prove a row *cannot degrade*, not as a production
measurement. New `design_system` widgets must be added to the `design_system.dart` barrel or
`apps/app` cannot import them.

## 8. Generated content and the simulation — High

Two generators (`tool/recipes.dart` → `supabase/seed_recipes.sql`, `tool/sim.dart` →
`supabase/sim/1_sim_dishes.sql`) and one in-database generator (`supabase/sim/2_sim_generate.sql`).
The failure modes here all shipped once already (B042–B045):

- **Hand-edited generated SQL.** `seed_recipes.sql` and `sim/1_sim_dishes.sql` are outputs —
  flag any diff editing them without the matching `recipeData/`/`simData/` JSON change and a
  regen (`recipes:gen` / `sim:gen`). CI's `recipes:check`/`sim:check` catch staleness, but only
  after the fact.
- **Determinism (B044).** The sim's guarantee is same seed → same database. Flag any `now()`,
  `random()`, or `setseed()` introduced into `2_sim_generate.sql` — timestamps come from the
  pinned `sim.epoch_end()` in `sim.config`, and randomness from `sim.rand(key, stream)`
  (hash-based, order-independent). A moving anchor re-dates recipes out from under the versions
  that reference them, and the run still exits 0.
- **Derived counters (Gotcha 19).** The sim recompute must call `chef_score()` /
  `chef_tier_for()`; flag any restated `3 / 5 / 0.2` or threshold literal in sim SQL. Also flag a
  bulk engagement load with the counter triggers left enabled — that is one
  `recompute_chef_stats()` per row, hours instead of seconds.
- **Teardown scope.** `9_sim_teardown.sql` deletes `auth.users` rows. It must be driven by the
  `sim.actor` / `sim.recipe` registries — flag any deletion keyed on an email or id *pattern*;
  a subtly-wrong pattern on the hosted project has no undo.
- **Schema placement (B026 by construction).** Sim helpers/registries live in schema `sim`,
  which PostgREST cannot reach. Flag a new sim function or table created in `public`.
- **File-order coupling (B045).** The `sim/*.sql` files run 0→9; a function body in an earlier
  file referencing an object a later file creates only fails on a *clean* database. Flag it
  unless guarded (e.g. the table is `create table if not exists` in both files); require
  verification from a dropped-schema state, not just a machine that has run the sim before.
- **Assertions are the only tests.** `3_sim_verify.sql` is the sole coverage the sim has. A diff
  that tunes a distribution until an assertion passes (rather than asserting the honest value,
  loudly relaxed at small presets) is a finding — that is exactly the B043 trap the suite was
  built to resist.

## Project review settings

- **Integration target: `main`.** It is the only branch and both CI triggers gate on it
  (`.github/workflows/ci.yml:3-7`). Most work lands as working-tree changes on `main` — default
  to reviewing staged + unstaged rather than a three-dot diff.
- **Severity defaults:** §1 and §6 findings are Critical. §2 and §4 are Critical when they
  affect `0001_init.sql`/`drop.sql`, High otherwise. §3, §5, and §8 are High (§8's teardown-scope
  rule is Critical — it deletes `auth.users` rows). §7 is Medium.
- Generated `*.g.dart` / `*.freezed.dart` are git-ignored (`.gitignore:11-13`) — their absence
  from a diff is never a finding; the missing `melos run build_runner` is (see below).
- **What the suites can and cannot tell you.** `packages/core/test/` covers model decoding, the
  pure helpers, and — since OPT-T2 — the repositories, through a recording `http.BaseClient` under
  a real `SupabaseClient`: it asserts the *request* (select fragment, embed orders, page window,
  RPC body) against a canned reply, not that Postgres agrees. `database.yml` (OPT-T1) applies the
  schema, seed and sim on a real Postgres — fresh, re-applied, and on the upgrade path. Every
  statement in those steps runs as `postgres`, so **RLS is bypassed there** — but the job now also
  runs `supabase/tests/rls_matrix.sql` (BL-7), which switches to `authenticated` and asserts the
  88-check matrix, so a policy regression of the B053/B061 class does fail CI. What the matrix
  covers is the tables and RPCs it names; a **new** table, policy, or `security definer` function
  needs a check added to it in the same change. Flag a diff that touches a policy, a definer
  function, or the column grants and neither changes `rls_matrix.sql` nor says which existing
  checks already cover it — a *tightening* of an already-asserted policy legitimately needs no new
  check, so the escape is naming them, not silence.

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
| `recipeData/**` | regenerated `supabase/seed_recipes.sql` in the same diff (`recipes:gen`) |
| `simData/**`, `supabase/sim/**`, `tool/sim.dart`, `tool/recipe_format.dart` | regenerated `supabase/sim/1_sim_dishes.sql` when dishes changed (`sim:gen`); `docs/SDS.md` §12 (the simulation dataset — personas, distributions, invariants); ROADMAP Phase 24 status |

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
