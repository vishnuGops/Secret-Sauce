# EXECUTION-PLAN — Secret-Sauce

Execution detail for the tasks in [ROADMAP.md](./ROADMAP.md). For each phase: approach, key
files, and acceptance criteria. Kept in sync with the code.

---

## Phase 0 — Documentation foundation

**Approach:** Author the docs first so code is written against a documented design.
**Files:** `CLAUDE.md`, `docs/ROADMAP.md`, `docs/EXECUTION-PLAN.md`, `docs/SDS.md`,
`docs/BUG-TRACKER.md`.
**Acceptance:** All five files exist, cross-link, and describe the agreed decisions
(Flutter + Supabase, adaptive app, fork lineage + versions, reserved suggestion hook).

## Phase 1 — Monorepo scaffold

**Approach:** Dart-workspace melos monorepo with two packages and one app.
**Files:** `melos.yaml`, root `pubspec.yaml`, `packages/core/pubspec.yaml`,
`packages/design_system/pubspec.yaml`, `apps/app/pubspec.yaml`, `analysis_options.yaml`.
**Acceptance:** `melos bootstrap` links packages; `melos run analyze` is defined.
**Notes:** Versions pinned loosely; developer runs `bootstrap` + `build_runner` after installing SDK.

## Phase 2 — Supabase schema + RLS

**Approach:** A single idempotent SQL file builds the full schema — enums, tables, indexes,
triggers/functions, RLS, storage buckets, and the discovery/fork RPCs.
**Files:** `supabase/migrations/0001_init.sql` (one consolidated schema).
**Data model:** see [SDS.md](./SDS.md#data-model). Fork lineage via
`forked_from_recipe_id` / `forked_from_version_id`; version snapshots in `recipe_versions`;
`recipe_suggestions` reserved for future upstream PRs.
**RLS:** public recipes readable by all; private readable by owner + `recipe_shares`; writes
owner-only. `profiles` self-manage.
**Idempotency (early dev):** all migrations are safe to re-run — enums are guarded with
`do $$ ... $$` existence checks, tables/indexes use `if not exists`, deferred FKs use
`drop constraint if exists` + add, and triggers/policies use `drop ... if exists` before create.
Squash into proper versioned migrations once there is real data.
**Acceptance:** `supabase db reset` (or re-running the scripts) applies cleanly; policies enforce
visibility.

## Phase 3 — core package

**Approach:** Immutable freezed models mirroring the schema; abstract repositories + Supabase impls.
**Files:** `packages/core/lib/src/models/*`, `packages/core/lib/src/repositories/*`,
`packages/core/lib/src/services/*`, `packages/core/lib/src/providers.dart`,
`packages/core/lib/core.dart` (barrel — the only public surface).
**Key contracts:**

- `AuthRepository`: `signIn`, `signUp`, `signOut`, `currentUser`, `authStateChanges`.
- `RecipeRepository`: `getById`, `create`, `update` (→ new version), `delete`, `fork`,
  `listMine`, `listSharedWithMe`, `versions`, `share`, `myRating`, `setRating`, `clearRating`.
- `DiscoverRepository`: `popular`, `trending`, `recent`, `search`.
- `StorageService`: `uploadRecipeImage`, `uploadAvatar`.
  **Acceptance:** compiles after codegen; repositories are mockable.

## Phase 4 — design_system

**Approach:** Central theme + reusable adaptive widgets so features stay thin.
**Files:** `packages/design_system/lib/src/theme/*`, `.../src/widgets/recipe_card.dart`,
`.../src/widgets/difficulty_badge.dart`, `.../src/widgets/state_views.dart`,
`.../src/layout/adaptive.dart`, barrel `design_system.dart`.
**Acceptance:** `RecipeCard` shows image, name, short description, cook time, average star rating
(when rated), difficulty badge, and an optional Public/Private pill.

## Phase 5 — app shell + auth

**Approach:** `ProviderScope` root; `go_router` with a `ShellRoute` that swaps bottom-nav (narrow)
for a fixed top navigation bar (wide). Auth state drives redirects.
**Files:** `apps/app/lib/main.dart`, `.../routing/app_router.dart`, `.../routing/app_shell.dart`,
`.../features/auth/*`.
**Acceptance:** unauthenticated users land on Home/auth; authenticated users reach app shell.

## Phase 6 — Home + Discover

**Files:** `.../features/home/*`, `.../features/discover/*`.
**Acceptance:** Home explains features with sign in/up; Discover lists public recipes in
Popular/Trending/Recent tabs with a search field.

## Phase 7 — My Recipes + sharing

**Files:** `.../features/my_recipes/*`.
**Acceptance:** Two tabs (My / Shared-with-me) render a `RecipeCard` grid; share dialog writes
to `recipe_shares`.

## Phase 8 — Recipe Detail

**Files:** `.../features/recipe_detail/*`.
**Acceptance:** grouped ingredients + ordered steps render; servings scaler recomputes
quantities; like/save toggle; fork button; version history list.

## Phase 9 — Recipe Editor

**Files:** `.../features/recipe_editor/*`.
**Acceptance:** create/edit recipe with ingredient/step groups and cover image; saving an edit
creates a new `recipe_version`.

## Phase 10 — Fork + version history

**Files:** editor/detail controllers + `RecipeRepository.fork`, `.versions`.
**Acceptance:** forking creates an independent recipe linked to origin; detail shows
"Forked from …"; version history browsable.

## Phase 11 — Search + ranking

**Files:** `DiscoverRepository` impl + discover UI, `supabase/migrations/0001_init.sql`
(`recipes_trending`, `recipes_popular`, `recipes_search`, `on_view_insert`).
**Acceptance:** search matches title/ingredient/tag; trending uses recency-weighted
likes/views; popular ranks by the Bayesian rating score (see Phase 14), with saves/likes
only as a tie-breaker.
**Trending inputs are one-per-user (B012):** `like_count` by the `recipe_likes` PK, and
`view_count` by `on_view_insert`, which bumps only on a user's first `recipe_views` row for a
recipe and never for anonymous rows. That asymmetry is deliberate — `anon` holds `insert` on
`recipe_views`, so counting anonymous views would make trending inflatable with no account. No
unique constraint was added: PostgREST cannot express `on conflict` inference against a partial
index, so `logView()` stays a plain insert and the append-only log survives for analytics.
`views_insert` additionally pins `user_id` to `auth.uid()` (or null), and the dedup probe takes a
per-(recipe, user) advisory lock so two concurrent first-views cannot both bump. `view_count` is
monotonic — nothing decrements it and `user_id` is `on delete set null`, so it is an **upper
bound** on distinct viewers. Seeded recipes keep synthetic `view_count` values written directly by
`seed.sql`, so their counter and log differ by design. Verified on the local stack — table in
[BUG-TRACKER.md](./BUG-TRACKER.md).

## Phase 12 — Polish, tests, verification

**Files:** `packages/*/test/*`, `apps/app/test/*`.
**Acceptance:** `melos run analyze` clean; widget + repository tests pass; manual pass on web +
mobile; empty/loading/error states verified.

## Phase 14 — Ratings

**Approach:** Ratings live in their own table (`recipe_ratings`, PK `user_id + recipe_id`) so a
user has exactly one rating per recipe and re-rating is an upsert. The client never writes the
aggregate: an `after insert/update/delete` trigger calls `recompute_recipe_rating()`, which
recomputes `rating_sum` / `rating_count` / `rating_avg` from the rating rows — exact by
construction, so the denormalized values cannot drift the way an incremental `+1` can.

**Files:** `supabase/migrations/0001_init.sql` (table, constraint, trigger, RLS, `recipes_popular`),
`supabase/seed.sql` + `supabase/scripts/drop.sql`, `packages/core/lib/src/models/recipe.dart`,
`packages/core/lib/src/repositories/recipe_repository.dart`,
`packages/design_system/lib/src/widgets/star_rating.dart` (+ `recipe_card.dart`),
`apps/app/lib/features/recipe_detail/*`.

**Rules:**

- Range 0.5 … 5.0 in half-star steps, enforced by a SQL check constraint _and_ snapped
  client-side by `snapRating()` in `core`.
- No self-rating: the RLS `with check` clause rejects `owns_recipe(recipe_id)`. The detail screen
  explains this instead of showing a disabled control.
- Signed-out visitors see the average and a "Sign in to rate" prompt.
- `Popular` = Bayesian weighted average (`m = 5` prior ratings at the site mean) so a lone 5-star
  recipe cannot outrank a well-rated one. Formula in [SDS.md](./SDS.md#6-discovery--ranking).

**Seed:** `seed_taster_ids()` defines 8 fixed dummy accounts; `seed_recipe(..., p_ratings jsonb)`
delegates to `seed_ratings()` so Discover → Popular has a meaningful order out of the box.
`seed_ratings()` is also called on the "recipe already exists" path — re-running `seed.sql` on a
live database backfills ratings without recreating content (B014).

**Acceptance:** rating a recipe from the detail screen updates the average and rating count;
re-rating overwrites; "Remove" deletes the row and the aggregate drops; Popular is ordered by the
weighted score; `melos run analyze` and `melos run test --no-select` are clean.
**Status:** done. Code, tests, and SQL all verified — the schema and seed were applied to a local
Supabase stack (`supabase start` + `supabase db reset`) and the RLS/aggregate/ranking behavior was
exercised there; results table in [BUG-TRACKER.md](./BUG-TRACKER.md). Two pre-existing schema bugs
surfaced and were fixed on the way (B011 invoker-rights counter triggers, B013 missing PostgREST
grants). The **hosted** project still needs the updated `0001_init.sql` re-applied — it is
idempotent, so `melos run db:create` or a dashboard paste is enough.

**Local verification loop** (no `psql` needed — the CLI's DB container has one):

```powershell
supabase start                     # local stack (config in supabase/config.toml)
supabase db reset                  # applies supabase/migrations/* then seed.sql
docker exec supabase_db_secret-sauce psql -U postgres -d postgres -c "select title, rating_avg from recipes_popular(6);"
supabase stop                      # when done
```

## Phase 15 — Visibility polish

**Approach:** Public/private was already complete end-to-end (editor toggle → `recipes.visibility`
→ RLS `can_read_recipe()`); the gap was that a card gave no hint which it was.
**Files:** `packages/design_system/lib/src/widgets/recipe_card.dart` (`showVisibility`),
`apps/app/lib/widgets/recipe_grid.dart`, `apps/app/lib/features/my_recipes/my_recipes_screen.dart`.
**Acceptance:** cards in the "My Recipes" tab carry a Public/Private pill; Discover cards do not
(everything there is public by definition).

## Phase 17 — Fix B022: nested content order reversed

**Status: done.** Fix applied and verified against a local Supabase stack in both directions
(with and without the fix); `melos run analyze` clean in all three packages. Verification table in
[BUG-TRACKER.md](./BUG-TRACKER.md#b022-verification-run-2026-08-18-local-supabase-stack).

**Root cause:** postgrest-dart's `.order(column)` defaults to `ascending: false`. The four
nested-content fetches in `SupabaseRecipeRepository` (`_fetchIngredientGroups` /
`_fetchStepGroups`, `packages/core/lib/src/repositories/recipe_repository.dart:273-315`) omit
the flag, so `ingredient_groups`, `ingredients`, `step_groups`, and `steps` all arrive
descending — steps render last-first. Every other `.order()` call in the repo passes
`ascending: false` explicitly (verified by grep), so the fix surface is exactly these four sites.

**The subtle part — stored-order corruption:** `update()` loads via `getById()` (reversed),
and `_persistContent` re-indexes the list `0..n` on save. Each app-edit therefore **flips the
persisted order**; a recipe edited an odd number of times is reversed in storage and currently
*displays* correctly (double reversal) — it will display wrong once the read is fixed.
`_appendVersion`'s `content_snapshot` inherits the same unreliability. Seeded recipes are clean
(SQL writes ascending; never edited). Parity of past edits is unknowable ⇒ **no auto-repair**;
audit and hand-fix any app-edited recipes (dev-stage data, expected to be a handful at most).

**Fix:** add `ascending: true` to the four calls. Nothing else changes; SQL is correct.

**Acceptance:** on the local stack (core has **no** tests — Gotcha 14 — so a green test run is
no evidence): a recipe with ≥2 groups and ≥5 steps displays groups and steps 1→N; edit + save
**twice** and re-verify after each save (catches the flip-flop); `melos run analyze` clean.
Close B022. — **met.**

**How it was verified** (Chrome is not installed, so the browser eyeball-check in the acceptance
criteria was replaced with something stronger — it drives the real repository code rather than the
rendered widget):

1. A fixture recipe was written straight into the local stack in known-ascending order — 2
   ingredient groups (`IG-A`/`IG-B`, 5 ingredients) and 2 step groups (`SG-A`/`SG-B`, 6 steps) —
   plus a local-only account owning it, so `update()` was reachable.
2. A throwaway harness under `apps/app/test/` (deleted afterwards — it needs a live database, and
   CI has no DB job) constructed `SupabaseRecipeRepository` against that stack and asserted
   `getById()` order, then `update()`d **twice**, re-asserting both the returned model and the
   stored `sort_order`/`step_order` read back independently after each save.
3. The same harness was re-run with the four `ascending: true` flags removed. It fails on the
   first assertion (`['SG-B', 'SG-A']` instead of `['SG-A', 'SG-B']`), so the check genuinely
   discriminates rather than passing vacuously.

That harness is not committed. Repository tests remain blocked on mocking `SupabaseClient`
(ROADMAP Phase 3); this was a one-off verification, not new coverage.

## Phase 18 — Chefs, tiers & leaderboard

**Status: done.** Full design in [SDS.md §10](./SDS.md#10-chefs-tiers--leaderboard); this section
is the build order that was followed. Phase 17 landed first (commit `2f2e6e0`) — leaderboard
verification opens recipes, and reversed steps would have poisoned every eyeball check.

**Approach:** "Chef" is a presentation of `profiles` — no new principal table. Score/tier are
denormalized onto `profiles` (`chef_score`, `chef_tier`, `public_recipe_count`), maintained by a
recompute-from-scratch trigger, exactly the `recipes.rating_*` pattern. Tier ships with every
recipe via PostgREST embedding (`owner:profiles(…)`), so cards render badges with zero extra
round-trips. The leaderboard is an RPC over the denormalized columns. Recipe→chef is 1:1 already
(`owner_id` non-null; forks create new owned recipes) — no schema change for that requirement.

**Files:** `supabase/migrations/0001_init.sql`, `supabase/seed.sql`, `supabase/scripts/drop.sql`,
`packages/core/lib/src/models/{enums,profile,recipe,chef_standing}.dart`,
`packages/core/lib/src/repositories/{chef_repository,recipe_repository,discover_repository}.dart`,
`packages/core/lib/src/providers.dart`,
`packages/design_system/lib/src/widgets/{tier_chip,chef_badge,recipe_card}.dart` + barrel,
`apps/app/lib/features/chefs/*`, `apps/app/lib/routing/{app_router,app_shell}.dart`,
`apps/app/lib/features/recipe_detail/recipe_detail_screen.dart`.

**Build order (each step leaves the tree green):**

1. **SQL first, verified on the local stack before any Dart** (the project's standing rule).
   Enum, columns, `chef_score()`/`chef_tier_for()`, `recompute_chef_stats()`,
   `on_recipe_stats_change`, backfill, `chefs_leaderboard()`, `drop.sql` entries.
   Traps, each a past bug class: trigger **must** be `security definer set search_path = public`
   (it updates a `profiles` row the liker/viewer does not own — invoker rights would silently
   match 0 rows, B011); `recompute_chef_stats` gets EXECUTE revoked (PostgREST exposes every
   `public` function, B-series `bump_count` rule); the blanket grant block predates these
   objects on a fresh apply, so grant EXECUTE on `chefs_leaderboard` explicitly (B013);
   everything guarded/`or replace` for idempotent re-runs (double-apply is part of acceptance).
2. **Seed**: chefs d1–d7 per the SDS table (tier ladder, exact-100 boundary, zero-engagement,
   private-only, tied pair), randomized passwords (B018), `seed_recipe(p_visibility)` with the
   old signature added to `drop.sql`. Re-run must be a no-op-plus-backfill (B014 pattern).
3. **core**: `ChefTier` (+`unknownEnumValue`), `Profile`/`Recipe` fields, `ChefStanding`,
   `ChefRepository`, embedding added to `getById`/`listMine`/`listSharedWithMe`/Discover
   (RPCs take `.select()` embedding for `setof recipes`). `melos run build_runner --no-select`,
   then decode-check against live rows: `chef_score` is Postgres `numeric` ⇒ `(v as num)
   .toDouble()` (Gotcha 11).
4. **design_system**: `TierChip`, `ChefBadge` (+`compact`), barrel exports (Gotcha 13), card
   overlay bottom-left on the cover `Stack` — **not** a new column row; the tile is fixed-aspect
   and B001/B002/B016 all came from intrinsic children. Widget tests at 276 px / 2.0×.
5. **app**: `/chefs` in the `ShellRoute` (signed-out safe ⇒ `redirect` untouched), `AppShell`
   destination, leaderboard screen + providers, detail-screen badge.
6. **Docs fold-in**: SDS §3.2/§6/§7/§8 updated to describe reality, §10 trimmed to a pointer;
   `CLAUDE.md` enum count (4→5), feature map `/chefs` row, server-owned columns list +=
   `profiles.chef_score/chef_tier/public_recipe_count`; BUG-TRACKER verification table.

**Acceptance:**

- Local stack: double-apply of `0001_init.sql` is clean and stable; seed lands d1–d7 on their
  exact tiers (incl. score-100 ⇒ `line_cook`); liking/saving/viewing a chef's recipe **as
  another user** moves the owner's score (the definer check); flipping a recipe
  private/deleting it drops its contribution; `select * from chefs_leaderboard(50, 0)` as
  `anon` returns ranked rows, ties share a `dense_rank`, no `public_recipe_count = 0` chefs,
  Kitchen ≈ 10.2k ⇒ `head_chef`.
- App: every recipe card and the detail screen show the owner's badge with the tier under the
  name; `/chefs` renders signed-out; `melos run analyze` and `melos run test --no-select`
  clean; card envelope tests pass at 276 px / 2.0×.
- Hosted rollout is one idempotent re-apply of `0001_init.sql` + `seed.sql` (both already safe
  by rule).

**Outcome — all of the above met.** Results table in
[BUG-TRACKER.md](./BUG-TRACKER.md#chefs--leaderboard-verification-run-2026-08-18-local-supabase-stack).
`melos run analyze` clean ×3; `melos run test --no-select` 35 passing. The hosted re-apply is the
one remaining item.

**Two things the plan got wrong, corrected in the build:**

1. **The owner embedding needs an explicit FK hint.** §10.5 specified
   `owner:profiles(id, display_name, avatar_url, chef_tier)`. That form is rejected outright —
   `recipes` and `profiles` are related five ways (`owner_id`, plus many-to-many through
   `recipe_likes`, `recipe_ratings`, `recipe_saves`, `recipe_shares`), so PostgREST answers
   `PGRST201: Could not embed because more than one relationship was found`. The working form
   names the constraint: `owner:profiles!recipes_owner_id_fkey(...)`. It is now a single shared
   constant (`kRecipeSelect` in `core/src/repositories/recipe_queries.dart`) because dropping the
   hint breaks `getById`, both list queries, and all four Discover queries simultaneously.
2. **The leaderboard row overflowed** at the accessibility envelope (B023) — caught by the new
   320 px / 2.0× test before merge, not in review. See the tracker entry.

**How the Dart side was verified** (Chrome is not installed, so no browser pass; `packages/core`
has no test dir, so `melos run test` says nothing about repositories — Gotcha 14): a throwaway
harness under `apps/app/test/` ran `SupabaseChefRepository`, `SupabaseDiscoverRepository`,
`SupabaseRecipeRepository`, and `SupabaseProfileRepository` against the local stack **signed
out**, asserting the seeded tier ladder, the `dense_rank` tie, the exact-100 boundary, both
exclusions, `chef_score` decoding as a `double`, and the owner embedding on all five recipe
surfaces — plus that `anon` cannot call `recompute_chef_stats`. Deleted after the run (CI has no
database job). The committed `chefs_screen_test.dart` covers the screen's
loading/empty/error/tie-render states with a fake `ChefRepository`, no database needed.

## Phase 19 — Authored recipe content, split from the demo seed

Roadmap: [ROADMAP.md Phase 19](./ROADMAP.md#phase-19--authored-recipe-content-split-from-the-demo-seed) ·
Design: [SDS.md §11](./SDS.md#11-recipe-content-vs-demo-data)

**Problem.** The Kitchen's recipes were staged as one flat `recipeData/data.json`: a single array
with a byte-identical duplicate, nine content defects (B025), and a shape the app cannot consume —
`servings` as free text, `amount` as one opaque string, no groups, no times.

**Order of work.** Two commits, deliberately separate. Data corrections first, against the old
shape, so the content diff is reviewable on its own; the structural change second, where every
line moves anyway.

**What shipped.**

1. `recipeData/recipes/<slug>.json`, one file per recipe. The filename is the identity, so the
   filesystem makes a duplicate slug impossible — which is the actual fix for B025's duplicate,
   not the deletion of the second copy.
2. `recipeData/schema.json` + `recipeData/README.md`. The schema is documentation, not a runtime
   dependency (no JSON Schema package in the toolchain), so its rules are restated in
   `tool/recipes.dart` and the two must be changed together — noted in both files.
3. `tool/recipes.dart` (`validate` / `gen` / `check`) → `supabase/seed_recipes.sql`, committed and
   CI-checked. `melos run recipes:*`, `db:recipes`, and `db:reset` extended.
4. `seed_recipe_v2`: group-aware, new name (so it cannot overload `seed_recipe`), B024 drop block
   in the file that recreates it, `execute` revoked (B026), and demo ratings reached through a
   `to_regprocedure` guard so the file outlives `seed.sql`.

**How the SQL was verified.** Docker was already serving an unrelated project's Supabase stack on
port 54322 — the port this project's `config.toml` claims — so rather than stop it, the SQL ran in
a throwaway database inside that same cluster, with the `auth` and `storage` schemas stubbed to
the columns `0001_init.sql` touches. Postgres 17.6, not the configured 15. That is enough to prove
the schema applies, the seed applies twice without duplication, both interleavings with `seed.sql`
are clean (24 recipes / 24 distinct titles / one overload each), grouping and per-group
`step_order` are right, `numeric` quantities and `null`-quantity "to taste" rows land correctly,
and `proacl` is `postgres=X/postgres` on all six seed helpers. It proves **nothing** about real
auth, Storage, or PostgREST — those still need the project's own stack.

**Content coverage** was checked mechanically rather than by eye: 9 titles in and 9 out, 109
ingredients in and 109 out, every old ingredient's distinctive words present in the new file.
Step count rose 35 → 41 (splits, no drops). `data.json` was deleted only after that passed.

**Then the six recipes already in the database.** Source was `seed.sql` rather than a dump of the
hosted project: B022's audit had already established that all six still carry exactly one
`recipe_versions` row, so none has been edited through the editor and the file is what the database
holds. Titles kept byte-identical — that is the dedupe key, so re-applying against the hosted
project is a no-op, not a second copy — and their engagement counters and taster ratings came
across as per-recipe `demo` blocks.

Their `perform seed_recipe(...)` calls were then **deleted from `seed.sql`**, which is the point of
the exercise: one definition per recipe. `seed.sql` keeps the accounts, the `d1`–`d7` demo recipes,
and the rating machinery, and `config.toml` gained `db.seed.sql_paths` so `supabase db reset` still
does everything in one command.

The move had to be provably neutral, since the leaderboard numbers in SDS §10.7 are derived from
those counters. Final run, after `Easy Guacamole` was dropped: 23 recipes / 64 ratings / 16
profiles with both files applied twice, and an identical board — Kitchen 10189 `head_chef` at
`public_recipe_count` 14, Amara 21000 `master_chef`, the Chen Wei / Greta Lindqvist `dense_rank`
tie intact, Dara still at exactly 100. The wrong order was tested too: recipes-first creates every
recipe with **zero** ratings and an explicit notice, and the documented recovery (`seed.sql`, then
re-run) restores the identical 64 / 10189.

**One content decision fell out of the merge.** The staged file and the database each had a
guacamole under a different name. `Easy Guacamole` was dropped in favour of `Fresh Guacamole`, the
one already live. The general rule that settled it: a chef may publish two recipes for the same
dish, however similar, as long as the **titles** differ — duplicate content is a product question,
duplicate titles are a correctness one, because `(owner_id, title)` is the import key and a
collision silently collapses to a single row. `tool/recipes.dart` therefore treats a repeated title
as an error, not a warning.

**Gaps left open**, all recorded in the roadmap: no `recipes.notes` column (notes are appended to
`description`), no reverse-direction lint for a step naming an unlisted ingredient, and no SQL
execution in CI.

## Build, run & release (ops)

Task runner is **melos** (`melos.yaml`); Gradle only builds Android. See `README.md` for full
detail. Key facts to keep in sync:

- **Run (dev):** web-server is the most reliable device here —
  `flutter run -d web-server --web-port 8080 --dart-define-from-file=env.local.json` (open
  `http://localhost:8080`). Chrome is not installed; Edge auto-launch is flaky; `-d windows` works.
- **Build tasks:** `melos run build:apk | build:apk:split | build:appbundle | build:ios | build:ipa`
  (all run in `apps/app` with `--dart-define-from-file=env.local.json`). APK output:
  `apps/app/build/app/outputs/flutter-apk/app-release.apk`.
- **Android release requirements:** `INTERNET` permission in `AndroidManifest.xml`;
  `path_provider_android` pinned `>=2.2.0 <2.3.0` in `apps/app/pubspec_overrides.yaml` (2.3.x pulls
  a JNI/CMake native build). Install to device: `flutter install --release --dart-define-from-file=env.local.json`.
- **App name:** Android `android:label`, iOS `CFBundleDisplayName` = `Secret-Sauce`.
- **Launcher icon:** `flutter_launcher_icons` config in `apps/app/pubspec.yaml`; source at
  `apps/app/assets/icon/app_icon.png`; generate with `melos run gen:icons`.
- **DB tasks:** `melos run db:create | db:seed | db:clean | db:drop | db:reset` via `tool/db.dart`
  (needs `psql` + `SUPABASE_DB_URL`). Scripts in `supabase/scripts/`.

---

### Environment prerequisites (developer runs these)

1. Install Flutter SDK **3.44.8** (not latest — see [README](../README.md#toolchain-versions));
   `dart pub global activate melos 6.3.3`.
2. `melos bootstrap` then `melos run build_runner --no-select` (codegen).
3. ~~Generate platform runners~~ — web, android, ios, and windows runners are already committed
   under `apps/app/`. Only run `flutter create . --platforms=<missing>` to add a new platform.
4. Create Supabase project; apply `supabase/migrations/0001_init.sql`; optionally run `supabase/seed.sql`.
5. Copy `apps/app/env.example.json` → `env.local.json` with `SUPABASE_URL` / `SUPABASE_ANON_KEY`.
6. Run: `flutter run -d web-server --web-port 8080 --dart-define-from-file=env.local.json`.
