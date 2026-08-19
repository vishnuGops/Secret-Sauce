# ROADMAP — Secret-Sauce

All implementation tasks, grouped by phase. Status is kept in sync with the code
(see the "Docs–code sync" rule in [CLAUDE.md](../CLAUDE.md)).

Legend: `[ ]` not started · `[~]` in progress · `[x]` done

---

## Phase 0 — Documentation foundation

- [x] Create `CLAUDE.md`
- [x] Create `docs/ROADMAP.md`
- [x] Create `docs/EXECUTION-PLAN.md`
- [x] Create `docs/SDS.md`
- [x] Create `docs/BUG-TRACKER.md`

## Phase 1 — Monorepo scaffold

- [x] `melos.yaml` + root `pubspec.yaml` (Dart workspace)
- [x] `packages/core` package skeleton + `pubspec.yaml`
- [x] `packages/design_system` package skeleton + `pubspec.yaml`
- [x] `apps/app` application skeleton + `pubspec.yaml`
- [x] `analysis_options.yaml` (shared lints)
- [x] `melos bootstrap` resolves cleanly
- [x] CI workflow (analyze + test) — `.github/workflows/ci.yml`

## Phase 2 — Supabase schema + RLS

- [x] `profiles` table + trigger
- [x] Enums: `difficulty`, `recipe_visibility`, `share_permission`, `suggestion_status`
- [x] `recipes` table (+ fork lineage columns)
- [x] `recipe_versions` table (git-like snapshots)
- [x] `ingredient_groups` + `ingredients`
- [x] `step_groups` + `steps`
- [x] `tags` + `recipe_tags`
- [x] `recipe_shares`
- [x] `recipe_likes`, `recipe_saves`, `recipe_views`
- [x] `recipe_ratings` (half-star 0.5–5.0) + aggregate trigger on `recipes.rating_*`
- [x] `recipe_suggestions` (reserved stub for future PR flow)
- [x] RLS policies (public/private/shared)
- [x] Storage buckets (recipe images, avatars)
- [x] Apply migrations to a Supabase project — the hosted project carries the current
      `0001_init.sql` in full (re-applied during the Phase 18 rollout)

## Phase 3 — core package

- [x] Models: `Profile`, `Recipe`, `IngredientGroup`, `Ingredient`, `StepGroup`, `RecipeStep`,
      `RecipeVersion`, `RecipeTag`, enums
- [x] `SupabaseService` (client bootstrap)
- [x] `AuthService` + `AuthRepository`
- [x] `RecipeRepository` (CRUD, fork, versioning) contract + Supabase impl
- [x] `DiscoverRepository` (popular/trending/recent/search) contract + impl
- [x] `StorageService` (image upload)
- [x] `packages/core/test/` exists — model/enum JSON decoding is covered (pure functions; no
      client needed)
- [ ] Unit tests for **repositories** _(still blocked — needs Supabase client mocking)_

## Phase 4 — design_system

- [x] `AppTheme` (light/dark, tokens)
- [x] `RecipeCard` (image, name, description, time, difficulty)
- [x] `DifficultyBadge`
- [x] Adaptive helpers (`Breakpoints`, `AdaptiveLayout`)
- [x] Common widgets (buttons, loading, empty states)

## Phase 5 — app shell + auth

- [x] `main.dart` bootstrap (Supabase init, ProviderScope)
- [x] `go_router` config + responsive `AppShell` (top nav bar / bottom nav)
- [x] Auth controller (Riverpod)
- [x] Sign in / Sign up screens
- [x] Auth guard / redirect

## Phase 6 — Home + Discover

- [x] Home / landing (intro, feature highlights, sign in/up)
- [x] Discover screen (Popular / Trending / Recent tabs)
- [x] Search bar + results
- [x] Public browsing: Discover + public recipe detail accessible without sign-in

## Phase 7 — My Recipes + sharing

- [x] My Recipes screen (My / Shared-with-me tabs)
- [x] Recipe grid using `RecipeCard`
- [x] Share dialog (add users, set permission)

## Phase 8 — Recipe Detail

- [x] Recipe detail screen (structured ingredients + steps)
- [x] Servings scaler
- [x] Like / save actions
- [x] Fork button entry point
- [x] Version history view

## Phase 9 — Recipe Editor

- [x] Create/edit form (metadata)
- [x] Ingredient-group + ingredient editor
- [x] Step-group + step editor
- [x] Cover image upload
- [x] Save → creates new `recipe_version`

## Phase 10 — Fork + version history

- [x] Fork action (copy + record lineage)
- [x] "Forked from …" attribution on detail
- [x] Version diff/history browsing

## Phase 11 — Search + ranking

- [x] Full-text search (title/ingredient/tag)
- [x] Trending ranking (recency-weighted likes/views)
- [x] Popular ranking — **now rating-based** (Bayesian weighted average; saves/likes only break ties)
- [x] `view_count` rollup trigger — counts distinct signed-in viewers, ignores anonymous and
      repeat views (advisory-locked against concurrent first-views), so trending is not
      inflatable (B012)
- [ ] **SQL regression harness — the largest untested surface in the project.** The B012 view
      trigger, every RLS policy, the rank RPCs, and (as of Phase 18) the whole chef score/tier/
      leaderboard layer are verified only by manual local-stack runs recorded in
      `docs/BUG-TRACKER.md`. CI has no database job, so any of it can regress and ship green —
      and the failure mode for the trigger/RLS bugs is *silence*, not an error (B011, B012).

      Two shapes, deliberately different in value:

      1. `supabase/tests/*.sql` + a `melos run test:sql` script, run against `supabase start`.
         Cheap and repeatable, but opt-in — an opt-in suite for a schema this trigger-heavy goes
         stale.
      2. The above **plus a CI job**. Actually catches regressions. Costs ~2–3 min of Docker
         startup per run, and must be the full Supabase stack rather than a plain Postgres
         service: `profiles.id` references `auth.users`, so a bare Postgres cannot apply
         `0001_init.sql` at all.

      Recommended: (2). Deferred by decision, not oversight.

## Phase 12 — Polish, tests, verification

- [x] Widget tests (`RecipeCard`, Home landing) — passing
- [ ] Repository unit tests _(deferred — need Supabase client mocking)_
- [x] `melos run analyze` clean (core, design_system, app)
- [x] Manual verification on web (`web-server` @ :8080) — sign-up works
- [ ] Manual verification on mobile/emulator _(pending)_
- [x] Empty/error/loading states pass review

---

## Phase 13 — Toolchain / reproducible setup

- [x] Document Windows Flutter SDK install from scratch (no `winget` package) — `README.md`
- [x] Pin toolchain to Flutter 3.44.8 / Dart 3.12.2 + melos 6.3.3, with rationale
- [x] Pin CI to the same versions (`.github/workflows/ci.yml` no longer tracks `channel: stable`)
- [x] Add a setup troubleshooting table to `README.md`
- [x] Log toolchain bugs B005–B010 in `docs/BUG-TRACKER.md`
- [x] Close the `.gitignore` gap that left extension-less `env.local` credential files tracked (B010)
- [x] End-to-end runtime check: web server + Supabase Auth + PostgREST seeded data
- [ ] Commit `pubspec.lock` files so resolution is reproducible _(B009 — currently git-ignored)_
- [ ] Migrate to `freezed` 3.x so the project can track current Flutter stable _(unblocks B005)_

## Phase 14 — Ratings

- [x] `recipe_ratings` table + half-star check constraint (0.5 … 5.0)
- [x] `recompute_recipe_rating()` trigger keeping `recipes.rating_sum / rating_count / rating_avg` exact
- [x] RLS: rate only your own row, only recipes you can read, never your own recipe
- [x] `Recipe.ratingAvg` / `ratingCount` on the model
- [x] `RecipeRepository.myRating / setRating / clearRating`
- [x] `StarRating`, `RatingPill`, `StarRatingInput` widgets in `design_system`
- [x] Rating shown on `RecipeCard`; rate/remove UI on recipe detail
- [x] Popular ranking switched to the Bayesian rating score
- [x] Seed data: 8 "taster" accounts supply believable ratings on the curated recipes
- [x] Widget tests for star rendering, half-star snapping, and range clamping
- [x] Fix B016: `RecipeCard` metadata row overflowed once the rating pill was added — row is now
      fully flexible; regression tests cover 276/320px at 1.0x and 2.0x text scale
- [x] Fix B017: `StarRatingInput` kept a stale preview when a scroll cancelled the gesture
- [x] Fix B018: seed accounts no longer carry literal passwords — randomized, since `seed.sql` is
      documented as safe to run against the hosted project
- [ ] Rotate/delete the 9 seed accounts on any **already-seeded** database _(B018 — the seed's
      `on conflict do nothing` leaves existing password hashes in place)_. **Now more pressing:**
      the hosted project is live and those 9 rows predate the fix, so if they were created from
      the pre-B018 seed they still carry the committed literal passwords. The 7 Phase 18 chef
      accounts are **not** affected — they were randomized from their first insert.
- [x] Fix B011: counter/aggregate triggers made `security definer` (RLS was silently dropping
      like/save updates on recipes the acting user doesn't own)
- [x] Fix B013: explicit table grants for `anon` / `authenticated` (current Supabase images no
      longer grant DML on new tables by default)
- [x] Verified on a local Supabase stack: schema + seed apply clean, aggregates/ranking correct,
      RLS rejects self-rating, anon rating, and bad values — see `docs/BUG-TRACKER.md`
- [x] Re-apply the updated `0001_init.sql` to the **hosted** project (idempotent) — done during
      the Phase 18 rollout, so the hosted project now carries the B012 view-count trigger and the
      tightened `views_insert` policy as well as the chef objects

## Phase 15 — Visibility polish

- [x] Public/Private badge on `RecipeCard` (`showVisibility`), enabled on the My Recipes tab
- [x] Confirmed end-to-end: editor toggle → `recipes.visibility` → RLS `can_read_recipe()` →
      Discover only lists `public`; private recipes reach only the owner + `recipe_shares` users

## Phase 16 — Agent-context accuracy

- [x] Audit `CLAUDE.md` against the code; correct the repository tree (`src/` layer), the import
      rule (`always_use_package_imports`), the enum list, and the Riverpod codegen claim
      (B019–B021)
- [x] Add a "Gotchas & invariants" section to `CLAUDE.md` citing B005–B018, plus a routes/feature
      map and a real-vs-cosmetic enforcement table
- [x] Fix the pre-`src/` paths in `docs/EXECUTION-PLAN.md` Phases 3–4 _(B020)_
- [x] Drop the unused `riverpod_annotation` / `riverpod_generator` deps from `core` + `app`, and
      `build_runner` from `app` (no annotated sources there) _(B021)_
- [x] Document the `packages/core` test-coverage hole in `CLAUDE.md` (repositories, `snapRating`,
      and JSON decoding are untested; `melos run test` says nothing about `core`)

## Phase 17 — Fix B022: nested content order reversed

- [x] Add `ascending: true` to the four nested-content `.order()` calls in
      `SupabaseRecipeRepository._fetchIngredientGroups` / `_fetchStepGroups`
      (postgrest-dart defaults to descending — B022)
- [x] Audit stored order of any recipe **edited through the app**: each save round-trip flipped
      the persisted `sort_order`/`step_order` (odd number of edits ⇒ reversed in storage); repair
      manually — parity is unknowable, so no auto-fix.
      **Result: nothing to repair.** All 6 recipes on the hosted project carry exactly one
      `recipe_versions` row (`version_number = 1`, `'Seeded recipe'`), so none was ever saved
      through the editor. Caveat recorded in `BUG-TRACKER.md`: the one real account's *private*
      recipes are not anon-readable and could not be inspected.
- [x] Verify on the local Supabase stack (core has no tests — a green `melos run test` proves
      nothing here): recipe with 5+ steps, 2+ groups displays 1→N; edit + save twice; re-check
- [x] Close B022 in `docs/BUG-TRACKER.md`

## Phase 18 — Chefs, tiers & leaderboard

Design: [SDS.md §10](./SDS.md#10-chefs-tiers--leaderboard) ·
Execution: [EXECUTION-PLAN.md Phase 18](./EXECUTION-PLAN.md#phase-18--chefs-tiers--leaderboard)

### Schema (`0001_init.sql`, idempotent)

- [x] `chef_tier` enum (guarded) — five tiers `home_cook … master_chef`
- [x] `profiles.chef_score / chef_tier / public_recipe_count` via `add column if not exists`
- [x] `chef_score()` + `chef_tier_for()` immutable functions (single source of truth)
- [x] `recompute_chef_stats(uuid)` — invoker-rights, EXECUTE revoked from API roles
- [x] `on_recipe_stats_change` trigger on `recipes` — **`security definer set search_path =
      public`** (writes other users' `profiles` rows; B011 class), handles insert/delete/update
      incl. `visibility` and `owner_id` changes
- [x] Idempotent backfill recomputing all profiles on every apply
- [x] `chefs_leaderboard(p_limit, p_offset)` RPC — dense_rank, deterministic tie-breaks,
      excludes `public_recipe_count = 0`, explicit `visibility = 'public'` filter
- [x] `drop.sql`: new functions/trigger/type + the old `seed_recipe` signature
- [x] Grants check: new function EXECUTE for `anon`/`authenticated` on `chefs_leaderboard` only
      (B013 class — the blanket grant block runs before these objects exist on first apply)

### core

- [x] `ChefTier` Dart enum (5 values, `unknownEnumValue` fallback) — updates the "four enums"
      note in `CLAUDE.md`
- [x] `Profile` + `chefScore` / `chefTier` / `publicRecipeCount`; `Recipe` + embedded
      `Profile? owner`; codegen re-run
- [x] Owner embedding added to recipe list/detail/RPC queries — as the shared `kRecipeSelect`
      constant in `recipe_queries.dart`. **The plain `owner:profiles(…)` form does not work**:
      `recipes` and `profiles` are related five ways, so PostgREST answers `PGRST201` unless the
      FK is named (`owner:profiles!recipes_owner_id_fkey(…)`)
- [x] `ChefStanding` model + `ChefRepository` (abstract + Supabase impl, provider wiring)

### design_system

- [x] `TierChip` (theme-aware tier colors, light + dark)
- [x] `ChefBadge` (avatar + name + tier **under** the name; `compact` variant)
- [x] Barrel exports for both (Gotcha 13)
- [x] `RecipeCard`: chef badge as **cover overlay, bottom-left** — never a new column row
      (B001/B002/B016); envelope tests at 276 px / 2.0× text scale

### app

- [x] `/chefs` route in the `ShellRoute` + `AppShell` destination (signed-out safe — no redirect
      change)
- [x] `features/chefs/`: leaderboard screen + providers (loading/empty/error states)
- [x] Recipe detail: full `ChefBadge` under the title

### Seed + verification

- [x] Seed chefs d1–d7 (fixed UUIDs, randomized passwords — B018): one per tier, exact-threshold
      boundary, zero-engagement, private-only, tied-score pair
- [x] `seed_recipe()` + `p_visibility` param (old signature → `drop.sql`)
- [x] Local-stack verification run recorded in `BUG-TRACKER.md`: idempotent double-apply, tier
      boundaries, trigger fires for non-owner engagement (definer check), leaderboard
      exclusions/ties, anon RPC call
- [x] Widget tests: `TierChip`, `ChefBadge`, card overlay envelope, leaderboard screen states;
      `melos run analyze` + `test --no-select` clean (35 tests)
- [x] Fix B023: two `RenderFlex` overflows in the leaderboard row, found by the new
      320 px / 2.0× envelope test before merge
- [x] Docs sync: SDS §3/§4/§7/§8/§10 fold-in, `CLAUDE.md` feature map + enum count +
      server-owned columns list + FK-hint gotcha (`README.md` unchanged — no command changes)
- [x] Coverage audit + gap fill: added `packages/core/test/` (**first tests in `core`** — model
      decoding is pure, so the `SupabaseClient`-mocking blocker never applied to it) covering the
      `ChefTier` wire format, the `unknownEnumValue` fallback, `ChefStanding` / `Profile` /
      `Recipe.owner` decoding, `numeric`-as-int-or-double, and a `kRecipeSelect` FK-hint guard;
      plus `chefs_routing_test.dart` pinning `/chefs` as signed-out safe while the guarded routes
      stay guarded. 35 → 65 tests
- [x] Re-apply `0001_init.sql` to the **hosted** project — applied; backfill scored all 10
      existing profiles, Kitchen lands `head_chef` at 10197
- [x] Fix B024: `seed.sql` failed on any **already-seeded** database — the `seed_recipe` signature
      change left two overloads and every call matched both. Drops now live in `seed.sql` itself,
      not only `drop.sql`
- [x] Re-run the fixed `seed.sql` on the **hosted** project — done. Verified over the anon API:
      7 leaderboard rows, all five tiers, Chen Wei / Greta Lindqvist share rank 4, Kitchen at
      10197 (8 above the local 10189 — the hosted DB carries one extra like and save from the
      B011 verification run, which is exactly `3+5`)

### Test coverage — remaining gaps (deferred)

Widget + model coverage landed with the feature (65 tests). These are what is still uncovered;
none blocks the feature, all are real regression surface.

- [ ] **SQL regression harness for the chef objects** — see Phase 11's entry, which this folds
      into: `chef_score()` / `chef_tier_for()` thresholds (incl. the inclusive-at-100 boundary),
      `recompute_chef_stats` and its `is distinct from` guard, `on_recipe_stats_change`
      (**`security definer`** — drop it and non-owner engagement silently stops counting, B011
      again), public-only filtering, `dense_rank` ties, the `public_recipe_count = 0` exclusion,
      and `anon` being able to call `chefs_leaderboard` but **not** `recompute_chef_stats`.
      Verified by hand once (BUG-TRACKER); nothing re-verifies it.
- [ ] `ChefRepository.leaderboard` unit test _(blocked with the other repositories — Phase 3)_
- [ ] Recipe detail renders the owner badge _(needs a `RecipeRepository` fake — 15 methods)_
- [ ] My Recipes passes `showChef: false` _(cheap; the widget flag is tested, the screen wiring
      is not)_
- [ ] `ChefBadge` `onTap` / `onSurfaceImage` / avatar-URL branches
- [ ] `RecipeCard` chef overlay is positioned **bottom-left** _(currently only asserted to render
      and not overflow)_

---

## Phase 19 — Authored recipe content, split from the demo seed

Separates the Secret Sauce Kitchen's **content** from the **demo fixtures** it was tangled with,
so the fake chefs, taster accounts, and invented engagement numbers in `supabase/seed.sql` can be
deleted later without taking the real recipes with them.

The staged recipes arrived as one flat `recipeData/data.json` with a duplicate entry and nine
content defects (B025) in a shape the app cannot use: `servings` as free text, `amount` as one
opaque string (`"1 1/4 cup"` — the servings scaler multiplies a `numeric`, so it cannot scale a
string), no ingredient/step groups, and every time field null.

### Authoring format

- [x] `recipeData/recipes/<slug>.json`, one recipe per file — the filename **is** the identity,
      so a duplicate slug is impossible by construction. Readable diffs; no merge conflicts when
      two branches each add a recipe.
- [x] `recipeData/schema.json` — every field documented against the column it maps to.
      Deliberately **not** loaded at runtime (no JSON Schema dependency in the toolchain), so the
      rules are duplicated in `tool/recipes.dart` and both must change together.
- [x] `recipeData/README.md` — workflow, and the three things that are easy to get wrong
      (decimal quantities, integer servings, unattended time as `duration_minutes`).
- [x] All 9 recipes restructured: grouped ingredients and steps, decimal `quantity` + `unit` +
      `note` + `is_optional`, integer `servings`, real `prep_minutes` / `cook_minutes`, and per-step
      `duration_minutes` / `temperature` / `tip`. Verified no content lost — 109 ingredients in,
      109 out, every title matched.
- [x] `recipeData/data.json` deleted; it is fully superseded and still in git history.

### Tooling

- [x] `tool/recipes.dart` — `validate` / `gen` / `check`. Generates
      `supabase/seed_recipes.sql`, which is committed.
- [x] `melos run recipes:validate | recipes:gen | recipes:check`; `melos run db:recipes`;
      `db:reset` extended to `drop → create → seed → recipes`.
- [x] CI runs `recipes:check`. Nothing reads the JSON at runtime, so without it a stale generated
      `.sql` would be applied to a database and nobody would notice.
- [x] Unused-ingredient lint (the margarita's orphaned orange liqueur, B025), suppressed on
      recipes with a catch-all step. Confirmed non-vacuous by re-introducing the defect.

### `seed_recipe_v2`

- [x] Group-aware helper, distinct name from `seed_recipe` so the two never overload each other.
      Numbers `step_order` **from 0 within each group**, matching
      `SupabaseRecipeRepository._persistContent` — continuous numbering would have been silently
      renumbered by the first edit.
- [x] B024 guard: the drop block for historical signatures lives in the file that recreates the
      function, with the rule stated for the next signature change.
- [x] `execute` revoked from `public` / `anon` / `authenticated` on both new helpers (B026).
- [x] Demo ratings applied through `seed.sql`'s tasters via a `to_regprocedure` guard, so this file
      keeps working after that file is deleted.

### Verification (local Postgres, 2026-08-18)

Ran in a throwaway database rather than the project's own stack — Docker was already serving an
unrelated project on port 54322. Postgres 17.6 vs the config's 15; the `auth` and `storage` schemas
were stubbed to the columns `0001_init.sql` touches. So this proves the SQL applies and the data
lands; it does **not** exercise real auth, real Storage, or PostgREST.

- [x] `0001_init.sql` → `seed_recipes.sql` applies clean; **twice** with no duplication
      (9 recipes / 109 ingredients / 41 steps either way)
- [x] Both interleavings with `seed.sql` — 24 recipes, 24 distinct titles, both function overloads
      present exactly once, no error in either order
- [x] Grouping and per-group `step_order` correct (teriyaki: sauce 0-1, skewers 0-3)
- [x] `numeric` quantities, `note`, and `is_optional` all land correctly; `null` quantity for
      "to taste" survives
- [x] `notes` appended to `description` as a trailing paragraph
- [x] `proacl` on both helpers is `postgres=X/postgres` — PUBLIC/anon/authenticated revoked
- [x] Kitchen `chef_score` unchanged at 10189 / `head_chef` (`public_recipe_count` 6 → 15), so the
      authored recipes add no phantom engagement

### Migrating the six recipes already in the database

- [x] `Classic Margherita Pizza`, `Spaghetti Aglio e Olio`, `Chicken Tikka Masala`,
      `Fluffy Buttermilk Pancakes`, `Fresh Guacamole`, `Brown Butter Chocolate Chip Cookies`
      authored into `recipeData/recipes/`. Source was `seed.sql`, which is what the hosted
      database contains — B022's audit established that all six still have exactly one
      `recipe_versions` row, so none has ever been edited through the editor.
- [x] Titles kept byte-identical (the `(owner_id, title)` dedupe key), so re-applying against the
      hosted project is a no-op rather than a second copy.
- [x] Engagement counters and taster ratings carried over as per-recipe `demo` blocks.
- [x] The six `perform seed_recipe(...)` calls **removed from `seed.sql`** — one definition per
      recipe. `seed.sql` keeps the accounts, the `d1`–`d7` demo recipes, and the rating machinery.
- [x] `config.toml` gained `db.seed.sql_paths = ["./seed.sql", "./seed_recipes.sql"]`, so
      `supabase db reset` still populates Discover in one command.
- [x] Verified (re-run after `Easy Guacamole` was dropped): 23 recipes / 64 ratings / 16 profiles,
      both files applied twice, and the **identical** leaderboard — Kitchen 10189 `head_chef` with
      `public_recipe_count` 14, Amara 21000 `master_chef`, the Chen Wei / Greta Lindqvist
      `dense_rank` tie, Dara at exactly 100 `line_cook`.
- [x] Verified the bad order too: recipes-first creates every recipe with **0** ratings and an
      explicit notice, and `seed.sql` → re-run `seed_recipes.sql` backfills to the identical
      64 / 10189.

> **Two guacamoles, resolved.** `Fresh Guacamole` (from the database) and `Easy Guacamole` (from
> the staged file) were different recipes — 3 avocados with coriander versus 2 with cherry
> tomatoes, jalapeño, and garlic. `Easy Guacamole` was dropped; `Fresh Guacamole` is the one that
> was already live. **Product rule confirmed in the process:** a chef may publish two recipes for
> the same dish, however similar, *provided the titles differ*. Duplicate content is allowed;
> duplicate titles are not, because `(owner_id, title)` is the import key — a second file with the
> same title silently collapses into one row rather than erroring, which is why
> `tool/recipes.dart` rejects it outright.

### Deferred

- [ ] **`recipes.notes` column.** There is nowhere to put a recipe-level note, so `tool/recipes.dart`
      appends it to `description`. Lossless, but it lands in the card summary.
- [ ] **Reverse-direction lint** — a step calling for an ingredient the list never mentions. Three
      of B025's nine defects were exactly that; it needs a lexicon and is still a manual read.
- [ ] **No SQL test in CI**, as with every other `.sql` in this repo — `recipes:check` compares
      text, it never runs the generated SQL.
- [ ] Retire `supabase/seed.sql` entirely once there is real traffic — the accounts, the `d1`–`d7`
      demo recipes, and the rating machinery. Recipes already survive without it; the only loss is
      the demo ratings, which is the point.

---

### Outstanding (environment-dependent)

Toolchain is set up and verified (bootstrap, codegen, analyze, test, `flutter build web --release`),
and the app runs against the hosted Supabase project with seeded data. These remain:

- **Signed-in flows** not yet exercised on this machine: create / edit / fork / version history and
  Storage image upload.
- **Repository unit tests** with a mocked Supabase client.
- **Mobile/emulator** manual pass (no Android SDK installed on the current machine).
- Squash the single idempotent `0001_init.sql` into versioned migrations once there's real data.
