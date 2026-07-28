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
- [ ] `melos bootstrap` resolves cleanly *(needs Flutter SDK)*
- [ ] CI workflow (analyze + test)

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
- [x] `recipe_suggestions` (reserved stub for future PR flow)
- [x] RLS policies (public/private/shared)
- [x] Storage buckets (recipe images, avatars)
- [ ] Apply migrations to a Supabase project *(needs Supabase project)*

## Phase 3 — core package
- [x] Models: `Profile`, `Recipe`, `IngredientGroup`, `Ingredient`, `StepGroup`, `RecipeStep`,
      `RecipeVersion`, `RecipeTag`, enums
- [x] `SupabaseService` (client bootstrap)
- [x] `AuthService` + `AuthRepository`
- [x] `RecipeRepository` (CRUD, fork, versioning) contract + Supabase impl
- [x] `DiscoverRepository` (popular/trending/recent/search) contract + impl
- [x] `StorageService` (image upload)
- [ ] Unit tests for repositories *(needs SDK)*

## Phase 4 — design_system
- [x] `AppTheme` (light/dark, tokens)
- [x] `RecipeCard` (image, name, description, time, difficulty)
- [x] `DifficultyBadge`
- [x] Adaptive helpers (`Breakpoints`, `AdaptiveLayout`)
- [x] Common widgets (buttons, loading, empty states)

## Phase 5 — app shell + auth
- [x] `main.dart` bootstrap (Supabase init, ProviderScope)
- [x] `go_router` config + responsive `AppShell` (nav rail / bottom nav)
- [x] Auth controller (Riverpod)
- [x] Sign in / Sign up screens
- [x] Auth guard / redirect

## Phase 6 — Home + Discover
- [x] Home / landing (intro, feature highlights, sign in/up)
- [x] Discover screen (Popular / Trending / Recent tabs)
- [x] Search bar + results

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
- [x] Popular ranking (all-time saves/likes)

## Phase 12 — Polish, tests, verification
- [ ] Widget tests (`RecipeCard`, key screens) *(needs SDK)*
- [ ] Repository unit tests *(needs SDK)*
- [ ] `melos run analyze` clean *(needs SDK)*
- [ ] Manual verification on web + mobile *(needs SDK)*
- [ ] Empty/error/loading states pass review

---

### Outstanding (environment-dependent)
These require tooling not present in the scaffold environment and are left for the developer:
- Install **Flutter SDK** + `melos`, run `melos bootstrap`, `melos run build_runner`.
- Create a **Supabase project**, apply `supabase/migrations`, set URL/anon key via `--dart-define`.
- Run codegen (freezed/json/riverpod) before first analyze/run.
