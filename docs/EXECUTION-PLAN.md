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
**Files:** `packages/core/lib/models/*`, `packages/core/lib/repositories/*`,
`packages/core/lib/services/*`, `packages/core/lib/core.dart` (barrel).
**Key contracts:**

- `AuthRepository`: `signIn`, `signUp`, `signOut`, `currentUser`, `authStateChanges`.
- `RecipeRepository`: `getById`, `create`, `update` (→ new version), `delete`, `fork`,
  `listMine`, `listSharedWithMe`, `versions`, `share`.
- `DiscoverRepository`: `popular`, `trending`, `recent`, `search`.
- `StorageService`: `uploadRecipeImage`, `uploadAvatar`.
  **Acceptance:** compiles after codegen; repositories are mockable.

## Phase 4 — design_system

**Approach:** Central theme + reusable adaptive widgets so features stay thin.
**Files:** `packages/design_system/lib/theme/*`, `.../widgets/recipe_card.dart`,
`.../widgets/difficulty_badge.dart`, `.../layout/adaptive.dart`, barrel `design_system.dart`.
**Acceptance:** `RecipeCard` shows image, name, short description, cook time, difficulty badge.

## Phase 5 — app shell + auth

**Approach:** `ProviderScope` root; `go_router` with a `ShellRoute` that swaps bottom-nav (narrow)
for a nav-rail (wide). Auth state drives redirects.
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

**Files:** `DiscoverRepository` impl + discover UI.
**Acceptance:** search matches title/ingredient/tag; trending uses recency-weighted
likes/views; popular uses all-time saves/likes.

## Phase 12 — Polish, tests, verification

**Files:** `packages/*/test/*`, `apps/app/test/*`.
**Acceptance:** `melos run analyze` clean; widget + repository tests pass; manual pass on web +
mobile; empty/loading/error states verified.

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

1. Install Flutter SDK; `dart pub global activate melos`.
2. `melos bootstrap` then `melos run build_runner` (codegen).
3. Generate platform runners once: `cd apps/app && flutter create . --platforms=web,android,ios,windows`.
4. Create Supabase project; apply `supabase/migrations/0001_init.sql`; optionally run `supabase/seed.sql`.
5. Copy `apps/app/env.example.json` → `env.local.json` with `SUPABASE_URL` / `SUPABASE_ANON_KEY`.
6. Run: `flutter run -d web-server --web-port 8080 --dart-define-from-file=env.local.json`.
