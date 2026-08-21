# ROADMAP — Secret-Sauce

All implementation tasks, grouped by phase. Status is kept in sync with the code
(see the "Docs–code sync" rule in [CLAUDE.md](../CLAUDE.md)).

Legend: `[ ]` not started · `[~]` in progress · `[x]` done

## Product direction (the north star)

Secret-Sauce is a **recipe vault first**, and that stays the core. The end state adds one more
layer of identity on top of the chef layer that Phases 18–23 built:

1. **Recipes** — structured, forkable, versioned. *(Phases 2–20: done)*
2. **Chefs** — a presentation of `profiles`, scored and tiered by engagement with their public
   recipes. *(Phases 18, 22, 23: done)*
3. **Restaurants** — a new entity. A restaurant lists **member chefs** (association is optional —
   most users never join one) and **signature dishes**, which are pointers into the existing
   `recipes` table, not a second recipe system. *(Phase 25: designed, not started)*

The build order to date is deliberately compatible with that end state: "chef" was built as a
presentation of `profiles` rather than a second principal table, and a restaurant will be built as
an entity *managed by* profiles rather than a login of its own — so auth, RLS, and the engagement
model all stay single-principal. The main gaps between here and Phase 25 are listed in that
phase's prerequisites (most notably: there is still no public chef page, and Phase 25's
restaurant page needs the same shape).

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

- [x] ~~Home / landing (intro, feature highlights, sign in/up)~~ — **retired 2026-08-20**. No
      navigation chrome ever linked it (the web brand mark goes to Discover), so a cold start was
      the only way in. `/` is now a redirect-only route onto `/discover`.
- [x] Discover screen (Popular / Trending / Recent tabs) — the front door on both platforms
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
- [x] Per-step time / temperature / tip and per-ingredient note / optional inputs (B035)
- [x] Cover image upload
- [ ] Per-step image upload — the column is carried through a save untouched, but there is no
      picker for it yet (B035)
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

- [x] Widget tests (`RecipeCard`, root `/` → `/discover` redirect) — passing. The Home landing
      test was replaced by the redirect test when that screen was retired.
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
      (B001/B002/B016); envelope tests at 276 px / 2.0× text scale _(v2 moved it to
      bottom-**right** — Phase 20)_

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
- [x] `RecipeCard` chef overlay position is asserted, not just "it renders" — Phase 20 pins it to
      the cover's **bottom-right** (v2 moved it there)

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

## Phase 20 — RecipeCard v2

The card was redrawn in Claude Design ("RecipeCard v2", Secret Sauce project → `Design System.dc.html`)
and ported as-is. Same inputs, same data, new anatomy: the **name leads the card as a banner** on
`colorScheme.primary` instead of sitting under the photo, so it never competes with the cover and
stays legible over a dark or busy image.

- [x] Title banner (`primary` / `onPrimary`, 14 × 10 padding, `titleMedium` w700, **max 2 lines**
      then ellipsis) as the first child of the card
- [x] Cover moved below the banner and made the only **flexible** child — a two-line title eats
      cover height, never card height
- [x] Chef overlay moved **bottom-left → bottom-right** of the cover (same scrim, same
      `ChefBadge(compact: true, onSurfaceImage: true)`)
- [x] Visibility chip moved into the banner and reduced to **icon-only** with the label as a
      `Tooltip` — a "Private" label is the first thing to overflow at 2.0× text scale
- [x] Footer: description (2 lines) + a `outlineVariant` rule above the
      time / rating / difficulty row
- [x] Fix B026 in that row: the difficulty badge had a flex of its own, so it reserved half the
      row whatever its label said — `4.9 (8)` truncated to `4…` at one-column widths. It is now
      the only non-flex child, capped at half the row (`LayoutBuilder` + `ConstrainedBox`; a bare
      intrinsic badge overflows by 1px at 276 / 2.0×), and sits flush right as the mockup has it
- [x] **Fixed height, not fixed aspect**: `kRecipeCardHeight = 352` exported from `design_system`;
      `recipe_grid.dart` passes it as `mainAxisExtent` instead of `childAspectRatio: 0.82`, which
      is what left dead space under every card on a wide window
- [x] The card owns its own height (`SizedBox`), so an unbounded-height parent can never leave the
      cover's `Expanded` unbounded (the original B001 shape)
- [x] Tests: envelope suites (276 / 320 px × 1.0 / 2.0×) still green, `find.text('Private')` →
      `find.byTooltip('Private')`, plus new fixed-height and **overlay-is-bottom-right** assertions
- [x] `melos run analyze` + `melos run test --no-select` clean (67 tests)

One thing from the mockup was **not** ported: the banner's serif (`Newsreader`) title. That is the
design's separate open question — "typography is the one upgrade", a `google_fonts` dependency plus
a `textTheme` in `app_theme.dart` — and it applies to every title in the app, not just this card.
The banner uses the theme's `titleMedium`, so it follows whatever that decision lands on.

### Flowing grid (the design retired the old card and gave the new one a max width)

Claude Design deleted the previous card and added `.rcard { width: 100%; max-width: 340px }` —
"width is fluid between **264px** and **340px**, so a wide grid adds a column instead of stretching
three cards across 1400px".

- [x] `FlowGridMetrics.fit` in [adaptive.dart](packages/design_system/lib/src/layout/adaptive.dart):
      pure function of the available width → column count, tile width, and the gutter that keeps a
      capped row centred. No breakpoint involved, so a drag-resize reflows continuously
- [x] `kRecipeCardMinWidth` (264 at the time; **288** since B048) / `kRecipeCardMaxWidth` (340)
      alongside `kRecipeCardHeight`
- [x] `RecipeGrid` wraps its `GridView` in a `LayoutBuilder` and feeds the metrics in as
      `crossAxisCount` + extra horizontal padding — the delegate always divides the full extent
      between its columns, so **less width to divide** is the only way to cap a tile
- [x] `responsiveColumns` stays for navigation chrome and non-card grids; the recipe grid no
      longer uses it (its doc comment now says so)
- [x] Tests: `flow_grid_test.dart` sweeps every width from 264 to 2400 asserting the tile stays
      inside its bounds, the columns never decrease as the window widens, row + gutters account
      for every pixel, and no wider column count would have fit;
      `apps/app/test/recipe_grid_test.dart` pumps the real grid at 390 / 700 / 1000 / 1440 / 2000,
      checks centring at a capped width, and resizes 400 → 1000 → 640 to prove it reflows
- [x] Card envelope suites re-pinned from 276/320 to **264/340** — the grid's real extremes
- [x] `melos run analyze` clean, 82 tests pass

### Card revision (2026-08-20 — the design fixed two things the port inherited)

`Design System.dc.html` was updated after the port: the banner is now a fixed `65px` band with the
title centred in it, and the fluid range starts at **288px**, not 264. Both are ported.

- [x] Banner is a fixed band — `kRecipeCardBannerHeight` (65) × `context.textScale`, applied as a
      minimum with the title vertically centred, so one-line and two-line names give the same card
      and neighbouring covers start at the same y (B047). Scaled rather than pinned: two lines of
      2.0× type do not fit in 65 raw pixels
- [x] Band capped at `kRecipeCardBannerMaxScale` (2.0) — the card's height is fixed, so an
      unbounded band starves the cover: at 3.0× it took the card from a 17px overflow (the
      pre-existing B049 budget failure) to 48px. Clamped it is 13px, better than the baseline
- [x] `kRecipeCardMinWidth` 264 → **288**, the floor at which the whole time / rating / difficulty
      row fits *uncut*; at 264 the grid was buying an extra column out of the footer (B048)
- [x] Tests: new `title banner` group (same centre for one and two lines at 1.0× and 2.0×, clamp at
      two lines); envelope suites re-pinned to 264 (below the floor — must degrade) / 288 / 340;
      `flow_grid_test` and `recipe_grid_test` re-pinned to the new column counts (1408px is four
      capped cards, not five squeezed ones)
- [x] `melos run analyze` SUCCESS, `melos run test --no-select` SUCCESS — 203 tests
      (core 42, design_system 91, app 70)

### Deferred

- [ ] Typography upgrade (Newsreader + Manrope via `google_fonts`) — app-wide, needs a yes/no
- [ ] Cover photography is still placeholder in the design; real shots may change the 352 px height
- [ ] Screenshot pass on the revised card — "the metadata row fits uncut at 288" is exactly the
      claim a widget test cannot make (fixed-width test font), so it needs eyes on a real grid
- [ ] **B049** — the card overflows at 3.0× text scale and always has. The fix is the spotlight
      card's shape (tile height computed from text scale, `mainAxisExtent` with it), which is a
      grid change; deliberately out of scope for the design port
- [ ] Nothing caps the grid's overall width, so a 4K window gets ~13 columns. If that reads as too
      many, the fix is a max content width on the screens, not on the card

## Phase 21 — Top navigation v2 (web only)

Redrawn in Claude Design (`Design System.dc.html` → "Chrome & states") and ported. The old bar put
brand, four destinations, and a `New recipe` button in one row and needed ~700px; it overlapped at
medium. The design's fix is three changes, all implemented in
[top_nav_bar.dart](apps/app/lib/routing/top_nav_bar.dart) — the row now needs ~470px.

- [x] **Profile leaves the destination list** and becomes the avatar at the far right, where it
      also reads as *account*. `PopupMenuButton` behind it: name + `TierChip` header, Profile,
      Sign out. Nothing selected in the pill on `/profile` — the old shell highlighted Discover
      there, because `indexWhere` returning `-1` fell back to 0
- [x] **Destinations sit in a centred segmented pill** (`surfaceContainerHigh` track, active chip
      lifted back to `surfaceContainerLowest` with the design's `0 1px 2px` shadow, `primary` w800
      label + filled icon)
- [x] **`New recipe` left the bar** for the page it belongs to: the My Recipes header (labelled
      `FilledButton` on web, the existing icon on compact, where the shell's FAB is the labelled
      call to action). Search already lives in Discover's search bar
- [x] Signed out: `Sign in` + `Sign up` (`/auth?mode=signup` opens the screen on its sign-up
      side), collapsing to one filled `login` button at medium. My Recipes is not offered signed
      out — it could only bounce to `/auth`
- [x] `ChefAvatar` in `design_system` (exported): initials fallback, optional `primary` ring and
      tier dot, so rank is readable at 34px. `ChefBadge`'s private `_Avatar` was folded into it
- [x] `myProfileProvider` in `core/src/providers.dart` — the bar's avatar and the profile screen
      read one cached profile instead of two. `valueOrNull`, so a slow or failed read still leaves
      a usable account button rather than a spinner in the chrome
- [x] `NavDestination` + the two lists in [nav_destinations.dart](apps/app/lib/routing/nav_destinations.dart):
      mobile keeps four slots including Profile (a phone has no room for an account menu, and a
      fixed four does not reflow on sign-in); web has Discover / Chefs / My Recipes-when-signed-in
- [x] **Labels never wrap.** The pill measures its labels with a `TextPainter` at the live text
      scale and picks the most generous mode that fits: all labels (expanded), active label only
      (medium, and expanded when the measurement says so), icons only. The bar height itself
      scales with the text scaler, capped at 1.6×
- [x] The pill is centred **on the bar**, not between the clusters — `CustomMultiChildLayout`
      reserves `max(brand, actions)` on both sides, so the brand's width does not push it right
- [x] Tests: `apps/app/test/top_nav_bar_test.dart` — destinations per auth state, no Profile and
      no `New recipe` in the bar, the account menu opens, medium collapses to `login`, label
      degradation, **the pill is centred on the bar** (the one contract `_BarLayout` exists for),
      both auth doors, and a 600/760/1000/1400 × 1.0/2.0× no-overflow envelope;
      `apps/app/test/my_recipes_header_test.dart` covers the header's new labelled button
- [x] `melos run analyze` clean; `melos run test --no-select` green (105 tests)

**Review pass** (`/code-review`, same change set). Fixed: the `TextPainter` in `_fit` ran inside
`LayoutBuilder` and was never disposed — a paragraph leak per layout pass, i.e. per frame of a
drag-resize; `TopNavBar.height` defaulted to `kTopNavHeight`, silently opting a caller out of the
text scaling `heightFor` exists to provide, so it is now required; `_fit`'s fall-through to
icons-only now asserts that icons-only actually fits, since below that the pill has nothing left
to degrade; `ChefAvatar` added to SDS §8. **Refuted by measurement:** the labelled `New recipe`
button was flagged as a B016-shaped overflow (it wants ~68px in a 56px toolbar at 2.0×) — probing
it with the guard removed showed the toolbar clamps it with no `RenderFlex` error, so the label
stays at every scale and the envelope test now pins that instead of a fix that was not needed.

Compact is untouched: the design is web-only, so `NavigationBar` + FAB still ship as they were.

### Deferred

- [ ] Every shell screen still draws **its own `AppBar`** under the new bar (Discover, Chefs, My
      Recipes), so web shows two stacked bars. The design's screen mockups have one; folding the
      page title into the content is a per-screen change, not a nav change
- [ ] The design's avatar is a real photo when the profile has one — `ChefAvatar` supports it, but
      no seeded profile carries an `avatar_url`, so initials are what actually render

## Phase 22 — Chefs v2: podium board + expanded chef card

Redrawn in Claude Design (`Chefs.dc.html`, drafts `1b` collapsed / `1c` desktop expanded / `1d`
mobile expanded). The board today lists four icon chips and a score; a chef cannot tell **why**
they are where they are, and a row goes nowhere when tapped. Phase 22 makes the score legible and
the row an entry point.

Four choices settled with the user before any code (the design left all four open):

| Question                | Decision                                                                                |
| ----------------------- | ----------------------------------------------------------------------------------------- |
| Collapsed card          | **1b "podium"** — tier spine, medal glyph for the top 3, `% to next tier` under the score |
| Score breakdown         | **Show the multipliers** (`likes × 3`, `saves × 5`, `views × 0.2`) — the reason to open it |
| Primary action          | **None.** Follow does not exist; the top-recipe rows tap through to `/recipe/:id`        |
| "Top recipes" ordering  | **New `chef_top_recipes` RPC** — exact, reuses `chef_score()` as the source of truth      |

### Schema (`0001_init.sql`, idempotent)

- [x] `chef_top_recipes(p_chef uuid, p_limit int default 3)` → `setof recipes`, `stable`,
      invoker-rights, ordered by `chef_score(like_count, save_count, view_count) desc` with
      deterministic tiebreakers. Filters `visibility = 'public'` **explicitly** (same reason as
      `chefs_leaderboard`: under invoker rights a chef would otherwise see their own private
      recipes in their own dialog and read different numbers than everyone else)
- [x] `grant execute … to anon, authenticated` in the existing `pg_roles` guard block (B013) —
      the dialog is signed-out safe like the board
- [x] B024 drop block for the signature, in the file that recreates it, and the matching line in
      `scripts/drop.sql`

### core

- [x] `ChefScoring` (`core/src/chef_scoring.dart`, plain Dart — no codegen): the **mirror** of
      `chef_score()` and `chef_tier_for()`. Weights 3 / 5 / 0.2, thresholds 100 / 1000 / 5000 /
      20000, plus `pointsToNext` / `progressToNext` / `nextTier` / `unitsToNext` / `breakdown`.
      Exported from `core.dart`
- [x] `core/src/formatting.dart` — `groupedCount` / `groupedScore`. Hand-rolled rather than adding
      `intl`: the only need is thousands separators and the product has no localization story.
      `ChefStanding.scoreLabel` now delegates here, so the board reads `21,000`, not `21000`
- [x] `ChefStanding` gained `isPodium`, `tierProgress`, `nextTier`, `nextTierLabel`,
      `pointsToNextLabel` — all derived from the **score**, so a card cannot show "0 to go" beside
      the lower tier
- [x] `ChefRepository.topRecipes(chefId, limit)` — `.rpc(...).select(kRecipeSelect)`, same shape as
      the Discover RPC calls
- [x] `ChefRepository.chefCount()` — exact `count` over `profiles` where `public_recipe_count > 0`,
      for the dialog's "Rank 2 of 148". `limit(1)` keeps the body one row; `count` respects filters
      but ignores `limit`

### design_system

- [x] `ChefStandingCard` — draft 1b. 6px tier spine, `workspace_premium` / `military_tech` medal
      for ranks 1–3 (numeral + `rank` below that), `ChefAvatar` tinted to the tier, dense
      `TierChip`, the four icon-chip stats, score, and `34% to Master` / `top tier reached`.
      `onTap` required — an inert row is what this design answers. Compact drops the stat labels
- [x] The spine is a `Positioned` child of a `Stack`, **not** a stretched `Row` child: the card
      lives in a `ListView`, so its height is unbounded at layout time and
      `CrossAxisAlignment.stretch` hands the spine `h=Infinity`. Caught by the envelope tests on
      the first run; `IntrinsicHeight` would have worked but costs a pass on all 50 rows
- [x] The score is a `FittedBox`, not an ellipsis — a truncated number is worse than a small one
- [x] `TierLadder` — the four thresholds as **evenly spaced anchors** (0 / ⅓ / ⅔ / 1) with the fill
      interpolating between them, `Line / Sous / Head / Master` beneath, current rung highlighted.
      A linear points axis would squash the bottom two tiers into the first 5% of the bar
- [x] `ScoreContributionBar` — one labelled input row (`1,980 likes × 3` … `5,940`) plus its bar
- [x] All three exported from `design_system.dart` (gotcha 14)

### app

- [x] `chefDetailProvider(chefId)` family + `chefCountProvider` in `chefs_providers.dart`. The
      recipe read is caught and flagged, not thrown: a database without the new RPC loses one
      section instead of the whole dialog
- [x] `chef_detail_sheet.dart` — one content widget, two presentations: `showDialog` capped at
      1152 × 720 on ≥600px, `showModalBottomSheet` (`isScrollControlled`, drag handle, fixed
      header, scrolling body) at 94% height on compact — the default 9/16 cap cuts the ladder off.
      Two columns on desktop, stacked on mobile
- [x] `chefs_screen.dart` — board rebuilt on `ChefStandingCard`, row taps open the detail
- [x] No footer action bar on mobile (1d draws Follow + Recipes there; both were cut)
- [x] 1c's "Rank recomputes nightly. Last updated 4 hours ago" is **wrong about this build** —
      `on_recipe_stats_change` fires on every like, save, view and visibility flip — so the card
      says that instead of shipping the mockup's copy

### Tests

- [x] `packages/core/test/chef_scoring_test.dart` — weights and every threshold boundary, pinned
      against the SQL values so the mirror cannot drift silently
- [x] `packages/core/test/chef_models_test.dart` — grouped `scoreLabel` and the new derived fields
- [x] `packages/design_system/test/chef_standing_card_test.dart` — medal vs numeral, tier spine,
      dense labels, top-tier copy, tap target, and a 320 / 360 / 600 / 760 × 1.0 / 2.0× envelope
- [x] `packages/design_system/test/tier_ladder_test.dart` — the anchor mapping, pinned
- [x] `apps/app/test/chefs_screen_test.dart` — extended: the multipliers render, the rank line uses
      the count, a tap opens a `Dialog` on desktop and a `BottomSheet` on a phone, the card
      survives a database with no `chef_top_recipes`, and no `Follow` / `View all` leaks in

### Verified

- [x] `melos run analyze` — **No issues found!** in all three packages
- [x] `flutter test` per package — core 39, design_system 58, app 49 passed (146 total, all green)
- [x] **SQL on a real Postgres.** `0001_init.sql` re-applied in place to the running local stack
      (`supabase_db_secret-sauce`) with `ON_ERROR_STOP=1`: no errors, `chef_top_recipes` created
      with `anon=X/postgres,authenticated=X/postgres`. As `anon` the RPC returns the Kitchen's
      three highest-contributing recipes in the right order (3,636 / 2,553 / 1,693 points). As the
      **private-only** chef `d6`, their own `chef_top_recipes` returns **0 rows** while they own a
      private recipe with 5,000 likes — the explicit `visibility` filter holds under invoker RLS
- [x] **Screenshots of a release build** (`flutter build web --release` + static serve, per B028)
      at 1440×900 and 390×844, board and expanded card. Four bugs came out of them —
      **B029–B032** — none of which the widget tests could see: the tests never pump the shell, and
      an ellipsised name is not an overflow

- [x] **Applied to the hosted project** (2026-08-19, no production yet). `0001_init.sql` piped in
      with `ON_ERROR_STOP=1`, exit 0. `chef_top_recipes` and `chefs_leaderboard` both carry
      `anon=X,authenticated=X,service_role=X`; as `anon` the RPC returns the Kitchen's top three
      (3,636.2 / 2,553 / 1,693). Re-screenshotted against it: Top recipes populates with rating
      pills, likes · saves, and contributed points on both desktop and mobile
- [x] Getting there needed a workaround, recorded as **B033**: `psql` is not installed on this
      machine and the direct `db.<ref>.supabase.co` host is IPv6-only, which the Supabase Docker
      container cannot route. The Session pooler host (IPv4) through the container's `psql` works

### Not verified

- [ ] Nothing here was exercised on a real phone; compact was checked at 390×844 in a browser

### Deferred

- [ ] No public chef page. "View all N recipes" was cut with the Follow button — there is still no
      route that lists one chef's public recipes
- [ ] Pagination: the board is still one `limit: 50` page, though the RPC takes an offset
- [ ] "Joined <month year>" comes from `profiles.created_at`, which is the **profile** row's age,
      not the account's

## Phase 23 — Chefs page v3 (web): hero, spotlight card, rails

**Status: done, web only.** Build order, traps and the full account in
[EXECUTION-PLAN.md Phase 23](./EXECUTION-PLAN.md#phase-23--chefs-page-v3-web-hero-spotlight-card-rails).
Redrawn in Claude Design: `Chefs Page.dc.html` (page, expanded 1440 × 900) plus `Chefs.dc.html`
drafts `1e` (spotlight card, desktop 400 × 560) and `1f` (mobile sheet — deferred).

`/chefs` was one 760px column. It answered who is ahead, and since Phase 22 why — but only one chef
at a time, only on tap, only by all-time score. Nothing stated the population, nothing showed who is
*moving*, and there was nothing on the page a visitor would look at for pleasure. **Scope is
web/expanded only; compact is byte-identical to Phase 22.**

Eight decisions taken before code; the four marked **owner** were the owner's call on the plan:

| Mockup draws | Decision |
| --- | --- |
| 4:3 portrait window | **owner:** leave it empty with the default avatar — `avatar_url`, else the monogram `ChefAvatar`. No chef portrait asset exists |
| `SEASON 1` / `S1 · 004/148` | Drop the season — the serial is `004 / 148` |
| `RECOMPUTED 4H AGO` | Wrong about this build, like 1c's "nightly" in Phase 22. Reads `LIVE · UPDATES ON EVERY LIKE, SAVE AND VIEW` |
| Time windows + Momentum tab | **owner:** not now. Controls render **disabled with a tooltip**, not hidden |
| — | Recorded for whoever builds them: windowed views must exclude anonymous rows or B012's inflation vector reopens |
| Full rails | **owner:** placeholder cards + TODO. Empty against today's seed; **do not** seed dated rows — the counter triggers would move every `chef_score` |
| Newsreader + mono | **owner:** keep the existing font; `TODO(fonts)` at each site |
| `Follow` / `Share card` | Cut, same as Phase 22 |

### Schema

- [x] **None.** The plan called for four RPCs and needed zero, which is the phase's most useful
      finding. The hero's tier tiles are five bounded exact counts over `profiles` (PostgREST cannot
      `group by`, and tallying client-side downloads a row per chef); the spotlight card's "move"
      row is the chef's strongest stat, already in the leaderboard payload via
      `ChefScoring.breakdown()`, so a ten-card rail costs **no** extra requests. Nothing to deploy —
      the page works against the hosted database as it stands

### core

- [x] `ChefRepository.tierCounts()` → `Map<ChefTier, int>`, five parallel `count(exact)` reads
      filtered `public_recipe_count > 0` so they sum to `chefCount()`
- [x] `ChefTier.wireValue` — the Postgres enum label, restated because `json_serializable` keeps its
      mapping private and a `.eq('chef_tier', …)` filter needs the string without a decode. Pinned
      by a round-trip test, plus a distinctness check so two rungs cannot silently share a label
- [x] `pluralNoun` / `countOf` in `formatting.dart`, hoisted out of the closure inside
      `ChefStandingCard._Stats` — B031 now has one place to be got wrong instead of four
- [x] No `@freezed` field added, so no `build_runner` run was needed

### design_system

- [x] **`ChefSpotlightCard`** — built and reviewed first, standalone against draft `1e`. Tier drives
      foil, rarity band, accent and glyph; the score sits where a trading card puts HP; the driver
      row names the input doing the most work with the arithmetic behind it; the footer is the
      tier-ladder bar. Portrait window per D1
- [x] `spotlightCardHeight(context)` — the tile is fixed-size, so text growth has nowhere to go, and
      the intrinsic bands exceed the 356px budget well before 2.0×. Height is
      `356 + (textScale − 1) × 168`; past 2.5× the growth clamps and the portrait absorbs the rest
- [x] `SpotlightCardPlaceholder` — same frame and geometry, neutral bands, for the D6 shelves
- [x] `CardRail` — icon tile, title/sub, `1–3 / 10`, arrows dimming at the ends. A horizontal
      `ListView` + `animateTo`, not a translated transform: a web rail must answer drag and trackpad
- [x] `ChefCardVariant.board` on `ChefStandingCard` — rank pill instead of a medal, no stat chips, a
      3px tier progress bar on the bottom edge. A variant, not a second widget
- [x] `context.textScale` in `adaptive.dart`, the one measurement three layouts now size from
- [x] All exported from `design_system.dart` (Gotcha 14)

### app

- [x] `chefs_hero.dart` — dark brand gradient (literal colours in both themes, tier accents resolved
      at `Brightness.dark`), population pill, ranking rule, five tier tiles, window control
- [x] `chefs_screen.dart` — **three** layouts: the untouched compact board; a single-scroll stacked
      page; and the two-column page (`Column(hero, Expanded(Row(panel 404, rails)))`) when the
      window is expanded **and** the text scale is at or below `maxTwoColumnTextScale`
- [x] Deviates from the draft's page-scroll + `position: sticky` on purpose — the panel already owns
      a scroll container there, and nested pinned slivers are the fragile way to the same picture
- [x] Board panel: `Score / Momentum / New`, and `Show all 148` wired to a wider first page —
      closing Phase 22's pagination item above
- [x] Three rails; a spotlight card taps through to the existing expanded chef dialog
- [x] `notYetTooltip` — explains a deliberately inert control and gets out of the way of a working
      one

### Tests — 198 green, up from 146

- [x] `chef_scoring_test.dart` / `chef_models_test.dart` — `pluralNoun` / `countOf`, and
      `wireValue` round-tripping through the decoder (core **42**)
- [x] `chef_spotlight_card_test.dart` — score/rank/serial/tier/totals, the driver row picking the
      real top contribution, `1 recipe` singular, top-tier copy, foil ramp, monogram fallback, the
      name-versus-score width ratio, and the tile envelope at 1.0 / 1.3 / 1.6 / 2.0 / **3.0**×
- [x] `card_rail_test.dart` — arrows dim at both ends, position label arithmetic, no controls when
      the shelf fits, footnote
- [x] `chef_standing_card_test.dart` — board variant: rank pill, no medal, progress value, `1
      recipe`, tap target, 404px envelope at 1.0 / 1.5 / 2.0× (design_system **88**)
- [x] `chefs_screen_test.dart` — hero counts, three rails, placeholder footnotes, disabled controls
      staying inert, `Show all` widening the RPC's limit, an empty board showing **no** Popular
      shelf, spotlight → dialog, and the page envelope at 320 / 360 / 600 / 1000 / 1440 × 2.0×,
      which sweeps all three layouts (app **68**)

### Verified

- [x] `melos run analyze` — **No issues found!** ×3, `SUCCESS` read from the output rather than the
      exit code (B006/B007)
- [x] `flutter test` per package — 42 / 88 / 68, all green
- [x] `/code-review` against `CLAUDE.md` + the repo review checklist. Five findings, all fixed and
      pinned by tests in the same pass — **B037–B041**. Two of them (B038's 50/50 flex split,
      B041's empty tooltips) were review finds no test could make: neither overflows
- [x] No SQL in the diff, so no local-stack run applies and nothing needs applying to the hosted
      project

### Not verified

- [ ] **No screenshots.** The B028 procedure needs a browser and Playwright reports `Chromium
      distribution 'chrome' is not found`. Phase 22 found four bugs that way that no test could see,
      and two of this phase's five were the same kind. Outstanding, not unnecessary —
      `npx playwright install chrome` unblocks it
- [ ] Nothing exercised on a real phone; compact is unchanged from Phase 22 either way

### Deferred

- [ ] The windowed half: `chef_window_stats(p_since)`, `chefs_leaderboard_windowed(p_days, …)`, the
      Trending and month rails, `Momentum`, and the hero's Month/Week. Wiring points carry
      `TODO(rails)` / `TODO(board)` / `TODO(hero)`; read the anonymous-views trap first
- [ ] Draft `1f` — spotlight card as a mobile sheet, with swipe and the Share/Recipes actions
- [ ] The `large` 400 × 560 spotlight size — nothing consumes it, and an unused variant is a second
      layout to keep correct for free
- [ ] The `New` sort would work today (`profiles.created_at` exists) but needs a column
      `chefs_leaderboard` does not return, so it moves with the rest of the windowed work
- [ ] Display/mono fonts — an app-wide decision, not a `/chefs` one
- [ ] Still no public chef page, so a spotlight card's only destination is the expanded dialog

## Phase 24 — Simulated population: a realistic user + engagement dataset

**Status: in progress.** Tooling and the first dish batch are built; the `sim` schema, the
generator, and verification are not. Full design, distribution model, and the edge-case catalogue in
[EXECUTION-PLAN.md Phase 24](./EXECUTION-PLAN.md#phase-24--simulated-population-a-realistic-user--engagement-dataset).

Every feature built since Phase 18 is a *ranking* of a population that does not exist. The database
holds 21 accounts and 23 recipes, all of whose engagement counters were typed by hand into
`seed.sql` / a `demo` block. Consequences, all of them already recorded elsewhere as limits:

- The leaderboard is 8 rows, so pagination, `dense_rank` at scale, and the hero's `004 / 148` serial
  are untested against real cardinality.
- `recipe_likes` / `recipe_saves` / `recipe_views` / `recipe_ratings` are **nearly empty** — the
  counters were written directly. Every windowed or dated query (the Trending rail, `Momentum`, the
  hero's Month/Week — Phase 23's whole deferred half) has nothing to read, which SDS §10.8 calls out
  as needing "its own answer before the rails do". This is that answer.
- Discover's Popular tab is a Bayesian average over ≤ 8 ratings per recipe; nothing proves the prior
  actually suppresses a one-rating recipe.
- No account in the database is a **non-creator**. The product's most common real user — someone who
  only ever reads recipes — has never been rendered.

The deliverable is a deterministic, idempotent, scale-parameterized generator that builds a
plausible population *and its history*, with the engagement log as the source of truth and the
denormalized counters derived from it (the reverse of how `seed.sql` works).

### Content — the dish library

- [~] `simData/dishes/<slug>.json` — **25 of 120** authored dishes, same format as
      `recipeData/recipes/*.json` so a dish can be promoted into the curated set by moving the file.
      Written fresh, not copied (ingredient lists are not copyrightable; step prose is). Batch 1 was
      sequenced for **coverage before count** — all 7 targets below already pass at 25, so the
      remaining 95 add variety to an already-valid library rather than being load-bearing
- [x] Coverage targets, asserted by `tool/sim.dart` over the whole directory: all 10 `category`
      values, ≥ 24 cuisines (25 dishes, 25 distinct cuisines), the full `difficulty` spread, a
      no-cook dish (`cook_minutes` 0), an overnight step (`duration_minutes` > 480), a multi-group
      dish (SDS §11.1), and a dish serving ≥ 8. Warnings below 100 dishes, errors at or above it —
      a partial batch legitimately misses a category, a finished library does not
- [ ] `simData/people.json` — given/family name pools across ~15 locales, bio templates
- [ ] `simData/vocab.json` — the tag vocabulary (Zipf-weighted), title-variant templates
- [x] `simData/README.md` + `simData/schema.json` — authoring workflow and the format delta from
      `recipeData` (no `demo` block; an optional `sim` block of `weight` + `variant_titles`)

### Tooling

- [x] Extract the validator out of `tool/recipes.dart` into **`tool/recipe_format.dart`** (a sibling,
      not `tool/lib/` — `tool/` is loose scripts, and a root `lib/` would have made the workspace
      package own it) so `recipeData` and `simData` cannot drift into two different definitions of a
      valid recipe. Proof the refactor is neutral: `recipes:check` still passes **byte-for-byte**
- [x] `tool/sim.dart` (`validate` / `gen` / `check`) → `supabase/sim/1_sim_dishes.sql`, committed
      and CI-gated exactly like `seed_recipes.sql`. Creates its own schema and table so it is
      standalone; **upserts** by slug (a library should push content edits, unlike `seed_recipe_v2`)
      and deletes rows whose source file is gone
- [x] `melos run sim:validate` / `sim:gen` / `sim:check`
- [x] `tool/db.dart`: `db:sim`, `db:sim:verify`, `db:sim:clean`. `--preset` / `--seed` are written
      into `sim.config` before the generator reads them rather than passed as psql `-v` vars, so a
      hand-run file behaves identically to the wrapper. `db:sim:clean` deletes `auth.users` rows and
      requires an explicit `--yes`; every action prints the target host first (Gotcha 7)
- [x] **`db:reset` DOES run the sim** — reversing the original plan, at the owner's request. Safe
      because `engage_existing` is false: the Kitchen and `d1`–`d7` counters stay byte-identical and
      every standing pinned in SDS §10.7 survives. Only the **ranks** move. Full reset from an empty
      database, sim included, is ~15s
- [x] CI: `sim:check` added beside `recipes:check`

### The `sim` schema (never `public`)

- [x] `supabase/sim/0_sim_schema.sql` — `create schema if not exists sim`. Every helper function and
      registry table lives here, so PostgREST (which exposes `public` only) cannot reach them. This
      is B026's lesson applied by construction rather than by a `revoke` block
- [x] `sim.rand(key, stream)` and the derived draws — `rand_normal` (Box-Muller), `rand_lognormal`,
      `rand_int`, `rand_bool`, `rand_ts`. All pure functions of
      `hashtextextended(key || stream, seed)`, **not** `setseed()` + `random()`: a hash is
      order-independent, so the same seed yields the same database regardless of plan or parallelism
- [x] `sim.uid(kind, n)` — deterministic ids, so a re-run updates rather than duplicates. **bigint**,
      because at the `large` preset the composed `n * 10000 + …` overflows a 32-bit int (B044)
- [x] `sim.epoch_end()` — the time anchor, **pinned into `sim.config`** on first generate rather than
      read from `now()`. Determinism depends on it and the failure is silent; see B044
- [x] `sim.actor` / `sim.recipe` registries — teardown deletes exactly what is listed here, never by
      an email or id pattern. The registry *is* the safety mechanism
- [x] `sim.persona`, `sim.preset`, `sim.config`, `sim.title_variant` — the distribution is data, so
      retuning a share is a one-row edit, not a rewrite
- [x] `sim.counter_baseline` — only used when `engage_existing` is on
- [ ] `sim.rand_zipf` — the tag vocabulary it was for is not built yet

### Generation

- [x] `supabase/sim/2_sim_generate.sql` — set-based, idempotent, one transaction, ~10s at `medium`
- [x] **Personas**: ghost 22% / lurker 43% / collector 14% / casual 11% / regular 6% / power 2.5% /
      vault 1.5%. Measured at `medium`: 21.3 / 45.5 / 14.0 / 9.9 / 5.1 / 2.6 / 1.6, and **95%** of
      simulated accounts own no public recipe
- [x] **Signups** on a compounding growth curve over 24 months
- [x] **Recipes**: per-persona log-normal count; a dish from the library plus a deterministic variant.
      1,671 recipes from 1,000 users at `medium`. Title uniqueness within an owner is guaranteed by a
      merged, **deduplicated** template sequence per dish — treating the dish's own variants and the
      generic pool as disjoint produced a real `(owner_id, title)` collision (caught by check D4)
- [x] **Versions**: geometric edit count, 4,196 rows, `current_version_id` on the last
- [x] **Forks**: ~4% of recipes, always from an older public recipe of a different owner
- [x] **Engagement** as a funnel over a *view*, never independent: view → like → save → rate. At
      `medium`: 97,926 signed-in views, 19,930 anonymous, 6,483 likes, 4,898 saves, 1,839 ratings
- [x] **Ratings** J-shaped, shifted per recipe by a latent quality term, plus a polarized set
- [x] **Private recipes** receive engagement only from their `recipe_shares` rows (902 shares)
- [x] Counters are **derived, not authored**: triggers disabled for the load, counters and
      `chef_score` / `chef_tier` recomputed set-based through the real `chef_score()` and
      `chef_tier_for()` (Gotcha 19), triggers restored
- [x] `engage_existing` (default false) keeps every SDS §10.7 standing byte-identical
- [x] Presets: `tiny` (60) · `small` (250) · `medium` (1,000, default) · `large` (8,000)

### Verification

- [x] `supabase/sim/3_sim_verify.sql` — 39 assertions that `raise exception` rather than print.
      Nothing in CI runs SQL (SDS §11.3), so this script *is* the test suite for this phase, and it
      found all three defects in B044 plus B045
- [x] Counter invariants (A1–A8), including `view_count` excluding anonymous rows and repeat visits
      (B012) — plus A7/A8, which assert those rows **exist**, so A3 cannot pass vacuously
- [x] Authorization invariants (B1–B5): no self-rating, half-star steps, no engagement on a private
      recipe from outside its share list, and no like or rating without a view
- [x] Temporal invariants (C1–C6): nothing predates its parent, nothing is in the future, no fork
      older than its source
- [x] Structural invariants (D1–D4): B022 ordering, every recipe has a `current_version_id`, no
      `(owner_id, title)` collisions
- [x] Shape assertions (E1–E12) — persona coverage, heavy-tail concentration, J-shaped ratings,
      forks, long version histories, and the deliberate edge-case accounts. E3 and E9 are
      **population-aware**: both measure quantities whose ceiling is set by how many users exist, so
      at `tiny` they are relaxed or skipped **loudly** rather than tuned until they pass
- [x] Idempotency: generate twice → identical counts and identical `sum(chef_score)`
- [x] `d1`–`d7` + Kitchen standings asserted unchanged (F1–F3)
- [x] Wall-clock: `medium` generate ~10s; full `db:reset` from an empty database ~15s
- [ ] RLS smoke test per persona with `set local role authenticated` — not written
- [ ] `large` preset never run; `master_chef` is asserted there but unverified

### Docs

- [ ] `docs/SDS.md` §12 — the simulation dataset: personas, distributions, invariants, and the
      derived-counter rule _(still the one unwritten doc for this phase)_
- [x] `CLAUDE.md` — the new commands, and the two traps worth a gotcha entry: engagement rows must
      be loaded with triggers off (or the load is O(rows) profile recomputes), and teardown is
      registry-driven
- [x] `README.md` — `db:sim` / `db:sim:clean` in the database section, with the B033 Docker
      `psql` form
- [x] `docs/BUG-TRACKER.md` — B043 (tier calibration), B044 (three generator defects), B045
      (first-apply ordering) recorded. Two more remain predicted, not yet observed:
      `recipes_search` recomputes `recipe_search_document()` per row for both the filter and the
      rank (no stored tsvector, no GIN index), and `can_read_recipe()` runs per row for every
      Discover read. Neither is visible at 23 recipes

### Deferred

- [ ] `avatar_url` and `cover_image_url` stay **null** for every sim row. There is no image asset and
      an external URL 404s offline, which renders as a broken-image widget rather than the monogram
      fallback the null path gives. Config knobs exist for whoever wires a bucket
- [ ] A Postgres service job in CI that applies `0001_init.sql` → `seed` → `recipes` → sim `tiny` →
      `3_sim_verify.sql`. It is the obvious payoff of having written the assertions, but it is a CI
      change, not a data one
- [ ] Building Phase 23's deferred windowed half on top of this data — the rails now have rows to
      read, but they are still unwritten

---

## Phase 25 — Restaurants & signature dishes (north star — designed, not started)

Design detail and prerequisites: [EXECUTION-PLAN.md Phase 25](./EXECUTION-PLAN.md#phase-25--restaurants--signature-dishes).
A restaurant is an **entity managed by profiles**, never a second principal: nobody signs in "as
a restaurant", so auth, RLS, and the engagement model stay exactly as they are. Signature dishes
are rows pointing at existing `recipes` — no second recipe system.

### Prerequisites (each is real work, ordered)

- [ ] **Public chef page** (`/chef/:id`) — deferred since Phase 22 and now load-bearing: the
      restaurant page is the same shape (identity header + recipe grid), and a member-chef row
      needs somewhere to tap through to. Build the chef page first; the restaurant page copies it.
- [ ] Decide the tier-calibration question (B043) before restaurant scores restate it — a
      restaurant aggregate over miscalibrated chef scores bakes the miscalibration in twice.
- [ ] SQL regression harness (Phase 11's item): Phase 25 adds tables, RLS, triggers, and RPCs on
      top of a schema whose existing SQL has no automated tests. Land the CI database job first so
      the new surface starts covered instead of joining the backlog.

### Schema (`0001_init.sql`, idempotent, same rules as every prior phase)

- [ ] `restaurant_role` enum (`owner` | `chef`) — guarded creation like the other five enums
- [ ] `restaurants` table: `id`, `name`, `description`, `city`, `country`, `website`,
      `cover_image_url`, `created_by → profiles`, `created_at`, `updated_at`. Grants added
      explicitly (B013 — the blanket grant block runs before this table exists on upgraded DBs)
- [ ] `restaurant_members`: `restaurant_id`, `profile_id`, `role`, `title` (free text, e.g.
      "Head Chef"), `created_at`; PK `(restaurant_id, profile_id)`. Association is optional by
      construction — a profile with zero rows here is the normal case
- [ ] `restaurant_signature_dishes`: `restaurant_id`, `recipe_id`, `sort_order`, `created_at`;
      PK `(restaurant_id, recipe_id)`. `with check`: the recipe is **public** and owned by a
      member — a private recipe as a signature dish would leak its existence through a
      world-readable table
- [ ] RLS: restaurants + members + signature dishes world-readable (public directory);
      restaurant writes by `owner`-role members; membership writes by `owner` only; signature-dish
      writes by members. Every trigger that crosses ownership: `security definer set search_path`
      (B011 class)
- [ ] Optional denormalized `restaurants.member_count` / signature-dish aggregate — same
      recompute-from-scratch trigger pattern as `rating_*` and `chef_*`; decide the restaurant
      "score" formula only after B043 is settled
- [ ] `drop.sql` entries + B024 signature-drop blocks for any new helper

### core / design_system / app

- [ ] `Restaurant`, `RestaurantMember` models (+ enums mirrored in `enums.dart` — update the
      "five enums" notes in `CLAUDE.md`/SDS when this lands)
- [ ] `RestaurantRepository` (abstract + Supabase impl, wired in `providers.dart`); embedding
      queries will need FK hints from day one — `restaurants ↔ profiles` is related two ways
      (`created_by` + members) at birth, the exact `PGRST201` shape Gotcha 17 documents
- [ ] `profiles`: no schema change — a chef's restaurant affiliation is read through
      `restaurant_members`, so the chef card/page gains an affiliation line without touching the
      score machinery
- [ ] Widgets: restaurant card + member-chef row in `design_system` (barrel exports, envelope
      tests at 288px / 2.0× — same contract as every card)
- [ ] Routes: `/restaurants` (directory; signed-out safe) + `/restaurant/:id` (detail; signed-out
      safe). Nav destination decision per Gotcha 18: a fifth destination costs the web pill its
      labels — measure before adding, or reach restaurants through Discover/chef pages instead
- [ ] Editor surface for owners (create restaurant, manage members, pick signature dishes from
      the owner's public recipes)

### Content / sim

- [ ] Extend the Phase 24 generator: a few % of simulated chefs belong to generated restaurants,
      signature dishes drawn from their public recipes — so the directory, empty states, and
      RLS paths are exercised at scale like everything else

---

## Phase OPT — Optimization & hardening backlog (rolling)

Findings from the 2026-08-20 design/architecture audit (Dart + SQL), plus the open items prior
phases deferred, consolidated in one place. Detail — mechanism, fix shape, acceptance — in
[EXECUTION-PLAN.md Phase OPT](./EXECUTION-PLAN.md#phase-opt--optimization--hardening).
This phase is **rolling**: items are picked by priority band, not executed top-to-bottom in one
sitting. New audit findings land here; `Bxxx` tags mean the mechanism is in `BUG-TRACKER.md`.

### OPT-S — Integrity & correctness (do these first)

- [x] **OPT-S1 (B050, high):** column-level `INSERT`/`UPDATE` grants on `recipes` / `profiles` —
      an owner could forge `like_count` / `chef_score` over PostgREST and the leaderboard believed
      it. Also made `current_version_id` server-owned for real (`recipe_versions_set_current`
      trigger) so it could leave the grant list. Verified on the local stack, both the upgrade
      path and a clean reset
- [x] **OPT-S1a (B053, high):** `recipes_select` called `can_read_recipe(id)`, a `stable` function
      that cannot see the row an `INSERT … RETURNING` is inserting — so **creating a recipe failed
      outright**. Policy inlined against the row's own columns. Found by OPT-S1's acceptance
      matrix; pre-existing. Also 2.4× faster on a Discover scan (15.7 ms → 6.5 ms at sim `medium`)
- [x] **OPT-S2:** added `.select()` + empty-result check to the `recipes` `update()` / `delete()`
      calls in `recipe_repository.dart`, plus `unshare()` (same class, same one-line fix); they
      throw `WriteDeniedException` instead of reporting a silent no-op as success (Gotcha 2)
- [x] **OPT-S3 (B051):** recipe-detail like/save — guards signed-out (routes to `/auth`), reads
      `myLiked`/`mySaved`, both are toggles, failures surface. New `recipe_detail_test.dart`
      (5 tests) is the first slice of OPT-T3's recipe-detail suite
- [x] **OPT-S4 (B052):** recipe-editor `_load()` failure path — catches, renders `ErrorView` with
      retry instead of the form, and `_canSave` blocks Save until a load has succeeded (4 tests)
- [x] **OPT-S5:** share dialog no longer offers a working-looking "Can edit" — the segment is
      `enabled: false` behind `notYetTooltip`, which moved to `apps/app/lib/widgets/` so the
      dialog isn't importing out of `features/chefs/` (pre-empts an OPT-A3 item)
- [x] **OPT-S6:** `fork_recipe` — explicit `auth.uid() is null` guard **and** EXECUTE revoked from
      `public`/`anon`, granted back to `authenticated`; both locks verified on the local stack
- [x] **OPT-S7 (B034):** `SUPABASE_DB_URL` moved out of the dart-define files into a dot-sourced,
      git-ignored `db-url.local.ps1` (template committed as `db-url.example.ps1`). Per-shell and
      per-project rather than a global user env var, so it cannot leak into another repo's `db:*`
      run. History checked: the credential was never committed, so no rotation needed
- [ ] **OPT-S8 (B018):** rotate the pre-fix seed accounts on the **hosted** project.
      `supabase/scripts/rotate_seed_passwords.sql` is written and verified on the local stack
      (16/16 rotated, recipes/ratings/profiles intact) — **running it against hosted is the
      owner's action**, deliberately not automated: it writes to `auth.users` on production

### OPT-P — Performance & scalability (sim `medium` makes these measurable)

- [x] **OPT-P1:** `recipes_search` recomputed `recipe_search_document()` twice per public recipe
      per search. Now a trigger-maintained `recipes.search_tsv` + GIN index: **539.6 ms → ~1–2.5 ms
      (>200×)** at sim `medium`, identical result set (304 matches). Statement-level triggers with
      transition tables cover title/description, ingredients, group cascade-deletes, tagging and
      tag renames. `kRecipeSelect` moved off `*` so the ~450-byte tsvector doesn't ship (~13 KB
      per 30-card page)
- [x] **OPT-P2:** `recipes_trending` bounded to 30 days + partial index
      `recipes_public_created_idx (created_at desc) where visibility='public'`. At sim `medium`:
      trending **23.4 ms → 3.9 ms** (6.0×, 1,344 → 351 rows scored); Discover **Recent**
      **1.1 ms → 0.23 ms** and now a pure index scan with the sort eliminated
- [x] **OPT-P3:** `getById` was 2+G+S round trips (one per group) — now **one** nested PostgREST
      embed with foreign-table ordering, B022's explicit ascending kept at all four levels.
      **4.69 requests → 1 on average**, worst case 8 → 1. Needed `@JsonKey(name:)` on
      `Recipe.ingredientGroups`/`stepGroups`, without which content silently decoded as empty
- [x] **OPT-P4:** one editor save cost 2 full `getById` cascades (`_appendVersion` + the return).
      Now **1**: the post-save read feeds both the snapshot and the return value, and
      `_appendVersion` returns the new version id so the pointer is carried over rather than
      re-read. Snapshot is the post-save read on purpose — the caller's draft has stale ids
- [x] **OPT-P5:** `chefs_leaderboard` re-aggregated all public recipes per page for numbers
      `recompute_chef_stats` already had — `profiles.total_likes/saves/views` now persist them and
      the board reads them straight off the row: **3.5 ms → 0.5 ms** warm at sim `medium` (52 ms
      cold), zero aggregation. New `recompute_all_chef_stats()` replaces the same UPDATE restated
      in three files (backfill, sim generate, sim teardown) — Gotcha 19 in one place. Partial
      `profiles_leaderboard_idx` on the board's exact ordering supersedes `profiles_chef_score_idx`;
      new sim assertion A6b fails if a total ever drifts from the recipes behind it
- [x] **OPT-P6:** added `(recipe_id, created_at desc)` to `recipe_likes` / `recipe_saves` — both
      PKs lead with `user_id`, so every recipe-leading read was a seq scan. "Who liked recipe X,
      newest first" goes seq-scan-over-6,483-rows + sort → **pure index scan, sort eliminated**;
      write paths still PK-served. Unblocks Phase 23's windowed rails
- [x] **OPT-P7:** `logView` fired on every `recipeProvider` re-resolution, so each like/save/rate
      appended another `recipe_views` row. Moved to its own `recipeViewLoggerProvider`
      (`autoDispose` = one per visit); 3 tests pin it
- [x] **OPT-P8:** Discover search fired per keystroke — 300 ms debounce in
      `searchResultsProvider` (`kSearchDebounce`), superseded queries cancelled on dispose so they
      never reach the network; 4 tests pin it
- [x] **OPT-P9:** pagination for all six browsing surfaces — Discover's four lists and both My
      Recipes tabs. `p_offset` on the three Discover RPCs, `.range()` on the table reads, and a
      **total** order everywhere (`… , created_at desc, id`) so a page boundary cannot duplicate or
      skip a row. Client state is one `PagedRecipesNotifier` in `core`; every surface renders
      through the new `RecipeAsyncGrid`, which also absorbed the duplicated
      Loading/Error/Empty/grid ladder (OPT-A7's grid item, done early). **Load more button, not
      infinite scroll** — owner's call. 7 tests in `paging_test.dart`
- [x] **OPT-P10:** `/chefs` hero issued 6 count queries → **1** `chefs_tier_counts()` RPC;
      `chefCount()` deleted because the total is the sum of the tiers, and `chefCountProvider`
      now derives it (4 call sites share the one request). `chefDetailProvider` starts both
      requests before awaiting either, keeping the non-fatal top-recipes fallback
- [ ] **OPT-P11 (accepted, revisit before growth):** per-engagement-row `recompute_chef_stats`
      is a full aggregate per like/first-view — fine now (SDS §10.3), the hot-path cost later

### OPT-A — Architecture & code quality

- [x] **OPT-A1:** `save_recipe(...)` — one transactional RPC for create/update + content replace
      + version append. Closes Gotcha 11's data-loss window, computes `version_number` under the
      row lock (race gone), and collapses a save from ~10 requests to 2 (the call + one read).
      `recipe_snapshot()` builds the version snapshot server-side and also fixed `fork_recipe`,
      whose first version stored a literal `'{}'`. Verified end to end on the local stack with a
      throwaway harness (create, edit with reorder, non-owner refused, signed-out refused), then
      deleted per Gotcha 15
- [x] **OPT-A2:** deleted the retired `features/home/home_screen.dart` (185 dead lines) and its
      directory; nothing imported it and `widget_test.dart` already pins the `/` redirect
- [x] **OPT-A3:** `share_dialog.dart` → `apps/app/lib/widgets/` (it was in `my_recipes`, which
      never opened it — `recipe_detail` did); sign-out is a direct
      `authRepositoryProvider.signOut()` at both call sites instead of a cross-feature import of
      `AuthController`, whose now-unused `signOut()` went with it
- [x] **OPT-A4:** `friendlyError()` in core maps `PostgrestException` codes (42501, 23505, 23503,
      23514, PGRST116/301/202), `AuthException` (passed through — GoTrue writes those for users),
      `StorageException`, `WriteDeniedException`, the signed-out `StateError`, and network faults
      to one actionable sentence; it logs the raw error itself, so no call site does. All 14
      surfaces converted (Discover/My grid, chefs board + sheet, recipe detail incl. fork/rate,
      editor load + save, profile, auth, share dialog). 8 tests
- [x] **OPT-A5:** `findByEmailOrName` → `searchByName`, a `%query%` match returning up to 8
      profiles ranked exact → prefix → contains (LIKE wildcards in the query escaped). ShareDialog
      now debounces the lookup, lists the matches with avatar + tier, excludes you, auto-selects a
      lone match, and keeps **Share disabled until one is chosen** — with three "Amara Baptiste"s
      in the sim data, "share with Amara" was picking one at random and reporting success.
      6 tests (also closes OPT-T3's share-dialog item)
- [x] **OPT-A6:** five schema nits, one local-stack pass. Avatars bucket gained its delete policy
      (parity with recipe-images — a replaced avatar was unreachable-but-public forever);
      `chefs_leaderboard` gained its B024 drop-guard; redundant `recipe_versions_recipe_idx`
      dropped (the `(recipe_id, version_number)` unique already leads with `recipe_id` — verified
      `versions()` still index-scans); the two deferred FKs are added only when absent, so a
      re-apply no longer revalidates every `recipes` row; `tags` keeps free creation but gained
      **delete-when-orphaned** and stays un-updatable — proven both ways on the local stack
- [x] **OPT-A7:** three dedupes. `StorageService`'s two upload bodies differed by bucket name
      alone → one `_upload(bucket, …)`; the grid scaffold landed with OPT-P9 (`RecipeAsyncGrid`);
      the two hand-rolled date formatters became `monthYear` / `isoDate` in `formatting.dart`
      (2 tests — the month table is 0-indexed and the ISO one pads two fields)
- [x] **OPT-A8:** the three oversized screens split along their real seams — editor **880 → 418**
      (`cover_picker`, `ingredients_editor`, `steps_editor`), detail **629 → 311**
      (`rating_section`, `recipe_content_views`, `detail_chips`), chef sheet **597 → 231**
      (`chef_score_panel`, `chef_recipes_panel`, `chef_detail_common`). Pure moves: no widget
      changed, only its address. Route literals gone from the route table **and** from three
      feature call sites the plan had not spotted — `Routes.recipePattern` /
      `editRecipePattern` are the new match-side constants
- [x] **OPT-A9:** `supabase/migrations/` is a numbered sequence and `0001_init.sql` is the
      **frozen baseline**; the next schema change is `0002_*.sql`. `db:create` applies the whole
      directory in filename order, and the hosted procedure is now "apply only the new file" — so
      shipping a one-liner stops re-running the baseline's two whole-table backfills. The
      baseline's content was deliberately **not** chopped into pieces: that would trade a real
      property (one re-appliable file every doc and script depends on) for tidiness.
      `supabase/migrations/README.md` carries the rules, including the B024 drop discipline

### OPT-T — Tests, tooling & process (existing debt, consolidated)

- [x] **OPT-T1:** `.github/workflows/database.yml` — a second job that starts the Supabase stack
      inside the runner and walks **three** paths: fresh apply → seed → recipes → sim tiny → the
      39 assertions; a full re-apply (the only thing that checks the idempotency every file
      claims); and the **upgrade path** (Gotcha 6) — the previous revision of the baseline applied
      first, today's layered on top, which is the path B024 shipped through. No `SUPABASE_DB_URL`
      secret, by design. Verified by running the same sequence locally, which also turned up
      **B054** (`db:reset` leaves a stale sim registry)
- [x] **OPT-T2:** repository tests exist — 14 of them, without mocking `SupabaseClient` at all.
      `SupabaseClient` takes an `httpClient`, so `test/support/fake_supabase.dart` records the
      request and replies from a queue; `signInAs` uses `recoverSession` to sign in offline. Pins
      the contracts that have broken here: the `kRecipeSelect` FK hint and column list, B022's four
      ascending embed orders, OPT-P3's one request per open, OPT-P9's `limit`/`offset` and total
      ordering, OPT-A1's single `save_recipe` body (writable columns only), the `42501` →
      `WriteDeniedException` translation, and the signed-out paths that must not reach the network
- [x] **OPT-T3:** the whole list is closed. Recipe-detail interactions landed with OPT-S3, the
      share dialog with OPT-A5, and this item added `snapRating` (4 tests, including the property
      that every input in range produces a value the SQL check constraint accepts) and the auth
      screen (6 tests through the **real router**: which door `?mode=signup` opens, validation
      before network, a failed sign-in showing the mapped message and staying put)
- [ ] **OPT-T4:** toolchain: commit `pubspec.lock` (B009) · raise the `sdk:` bound / settle
      B027 formatter conflict · migrate to `freezed` 3.x to unpin Flutter (B005)
- [x] **OPT-T5:** screenshot pass done over Discover (390 / 700 / 1400), `/chefs` v3 at 1400, and
      a recipe detail at 1000, through the B028 procedure (release build + static serve). Branded
      Chrome still will not install (needs Administrator), so the pass runs on Playwright's bundled
      **Chromium** via `npx playwright screenshot` — the MCP browser is the only thing that needs
      `chrome`. Found and fixed **B055** (tier chip unreadable on a card cover — the defect is
      colour only, so no layout test could see it) and **B056** (ungrouped like/save counters).
      `/chefs` v3 verified correct: hero, tier tiles, tie ranks, score explanations, `1 recipe`
      singular
- [x] **OPT-T6:** `tool/db.dart` runs `create` / `seed` / `recipes` / `drop` / `clean` under
      `psql -1`, one transaction **per file**, so a mid-file failure rolls back instead of leaving
      a partial schema. The sim files stay exempt — they manage their own transactions and toggle
      triggers. Verified: all three big files apply cleanly under `-1`, and a deliberate
      mid-file error leaves nothing behind

---

### Outstanding (environment-dependent)

Toolchain is set up and verified (bootstrap, codegen, analyze, test, `flutter build web --release`),
and the app runs against the hosted Supabase project with seeded data. These remain:

- **Signed-in flows**: create / edit / version history **were exercised end-to-end on the local
  stack** during OPT-P4 (throwaway account + harness, both deleted afterwards) — create with every
  column, the trigger-set `current_version_id`, an edit that adds an ingredient, ordering preserved
  across the delete-and-reinsert, both version snapshots, the search document refreshing, a private
  recipe staying out of public search, and a signed-out update throwing rather than reporting
  success. That run is what found the stale-pointer bug in P4's first cut. **Still not exercised:**
  fork from the UI, and Storage image upload.
- **Repository unit tests** with a mocked Supabase client.
- **Mobile/emulator** manual pass (no Android SDK installed on the current machine).
- Squash the single idempotent `0001_init.sql` into versioned migrations once there's real data.
