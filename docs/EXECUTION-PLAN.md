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
