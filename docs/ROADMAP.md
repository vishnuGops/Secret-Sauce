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
- [ ] Apply migrations to a Supabase project _(needs Supabase project)_

## Phase 3 — core package

- [x] Models: `Profile`, `Recipe`, `IngredientGroup`, `Ingredient`, `StepGroup`, `RecipeStep`,
      `RecipeVersion`, `RecipeTag`, enums
- [x] `SupabaseService` (client bootstrap)
- [x] `AuthService` + `AuthRepository`
- [x] `RecipeRepository` (CRUD, fork, versioning) contract + Supabase impl
- [x] `DiscoverRepository` (popular/trending/recent/search) contract + impl
- [x] `StorageService` (image upload)
- [ ] Unit tests for repositories _(needs Supabase client mocking)_

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
      `on conflict do nothing` leaves existing password hashes in place)_
- [x] Fix B011: counter/aggregate triggers made `security definer` (RLS was silently dropping
      like/save updates on recipes the acting user doesn't own)
- [x] Fix B013: explicit table grants for `anon` / `authenticated` (current Supabase images no
      longer grant DML on new tables by default)
- [x] Verified on a local Supabase stack: schema + seed apply clean, aggregates/ranking correct,
      RLS rejects self-rating, anon rating, and bad values — see `docs/BUG-TRACKER.md`
- [ ] Re-apply the updated `0001_init.sql` to the **hosted** project (idempotent)

## Phase 15 — Visibility polish

- [x] Public/Private badge on `RecipeCard` (`showVisibility`), enabled on the My Recipes tab
- [x] Confirmed end-to-end: editor toggle → `recipes.visibility` → RLS `can_read_recipe()` →
      Discover only lists `public`; private recipes reach only the owner + `recipe_shares` users

---

### Outstanding (environment-dependent)

Toolchain is set up and verified (bootstrap, codegen, analyze, test, `flutter build web --release`),
and the app runs against the hosted Supabase project with seeded data. These remain:

- **Signed-in flows** not yet exercised on this machine: create / edit / fork / version history and
  Storage image upload.
- **Repository unit tests** with a mocked Supabase client.
- **Mobile/emulator** manual pass (no Android SDK installed on the current machine).
- Squash the single idempotent `0001_init.sql` into versioned migrations once there's real data.
