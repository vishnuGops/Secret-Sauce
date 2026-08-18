# CLAUDE.md — Secret-Sauce

Guidance for AI assistants (and humans) working in this repository. Read this first.

Deep references: [docs/SDS.md](./docs/SDS.md) (data model, RLS, ranking, widget contracts) ·
[docs/ROADMAP.md](./docs/ROADMAP.md) · [docs/EXECUTION-PLAN.md](./docs/EXECUTION-PLAN.md) ·
[docs/BUG-TRACKER.md](./docs/BUG-TRACKER.md) (every rule below with a `Bxxx` tag is explained
there) · [README.md](./README.md) (SDK install, release, troubleshooting).

## What this project is

**Secret-Sauce** is a cross-platform **recipe vault**. Users document, structure, and share
recipes. Recipes can be **forked** (git-style: an independent copy that keeps a link to its
origin) and carry a **version history** so legacy/family recipes stay intact and improvable.

- Recipes are **private** (owner + explicitly shared users) or **public** (discoverable by all).
- The **structure and intuitiveness of a recipe** is the most important part of this product.
  Ingredients and steps are richly modelled (grouped, ordered, with quantities/units/timers) so
  they are easy to follow.

## Tech stack

| Layer            | Choice                                                              |
| ---------------- | ------------------------------------------------------------------- |
| UI               | **Flutter** — single **adaptive** codebase (web + mobile + desktop) |
| State management | **Riverpod** — hand-written providers only (see Conventions)         |
| Models           | **freezed** + **json_serializable**                                 |
| Routing          | **go_router** (`ShellRoute` + responsive shell)                     |
| Backend          | **Supabase** — Postgres, Auth, Storage, Row-Level Security          |
| Monorepo         | **melos** (Dart workspaces)                                         |
| Images           | `cached_network_image`, `image_picker`                              |

There is **one** app entry point — web/mobile/desktop differences are responsive layouts, never a
second app.

## Repository layout

```
secret-sauce/
├── CLAUDE.md · README.md · melos.yaml · pubspec.yaml · analysis_options.yaml
├── .claude/skills/            # code-review + review-checklist (repo's own review criteria)
├── .github/workflows/ci.yml   # analyze + test, pinned Flutter 3.44.8 / melos 6.3.3
├── docs/                      # ROADMAP · EXECUTION-PLAN · SDS · BUG-TRACKER (see "Docs–code sync")
├── tool/db.dart               # psql wrapper behind the melos db:* scripts
├── packages/
│   ├── core/lib/
│   │   ├── core.dart              # BARREL — the only public surface of `core`
│   │   └── src/{models,repositories,services}/ + providers.dart
│   └── design_system/lib/
│       ├── design_system.dart     # BARREL — export new widgets here or app can't import them
│       ├── src/{theme,layout,widgets}/
│       └── ../test/               # recipe_card_test.dart, star_rating_test.dart
├── apps/app/
│   ├── lib/features/          # auth, home, discover, my_recipes, recipe_detail,
│   │                          # recipe_editor, profile — screen + *_providers.dart per feature
│   ├── lib/routing/           # app_router.dart (routes + redirect), app_shell.dart (nav)
│   ├── lib/widgets/           # app-level shared widgets (recipe_grid.dart)
│   ├── lib/main.dart · test/widget_test.dart
│   ├── env.example.json       # template; env.local.json (git-ignored) holds real creds
│   └── android/ ios/ web/ windows/   # platform runners are committed — no `flutter create`
└── supabase/
    ├── migrations/0001_init.sql  # THE schema: tables, triggers, RLS, grants, storage, RPCs
    ├── seed.sql                  # curated public recipes + rating data (idempotent)
    └── scripts/{drop,clean}.sql
```

Note the `src/` layer: model files live at `packages/core/lib/src/models/`, **not**
`packages/core/lib/models/`. Nothing outside a package imports below its barrel.

## Architecture

Feature-first inside `apps/app`; layered inside `packages/core`:

```
UI (features/*, design_system)
   → Riverpod providers (feature `*_providers.dart`; shared ones in core/src/providers.dart)
      → Repositories (abstract contract + Supabase impl, same file, in core/src/repositories)
         → Supabase (Postgres / Auth / Storage) — enforcement lives here
```

Request lifecycle, e.g. opening a recipe: [app_router.dart](apps/app/lib/routing/app_router.dart)
matches `/recipe/:id` → [recipe_detail_screen.dart](apps/app/lib/features/recipe_detail/recipe_detail_screen.dart)
watches `recipeProvider(id)` → [recipe_detail_providers.dart](apps/app/lib/features/recipe_detail/recipe_detail_providers.dart)
calls `recipeRepositoryProvider` → [recipe_repository.dart](packages/core/lib/src/repositories/recipe_repository.dart)
`getById` issues PostgREST queries → RLS `recipes_select` decides what comes back.

- UI never talks to Supabase directly — always through a repository.
- Every repository is an `abstract interface class` + a `Supabase*` implementation, wired in
  [providers.dart](packages/core/lib/src/providers.dart), so it can be swapped for a fake.
- Models are immutable (`freezed`) with JSON keys matching the Postgres column names exactly.

### Where enforcement really happens

| Layer                                                                                 | Status                    |
| ------------------------------------------------------------------------------------- | ------------------------- |
| `redirect` in [app_router.dart:42-52](apps/app/lib/routing/app_router.dart#L42-L52)    | **UX only** — never security |
| Hidden/disabled buttons on a screen                                                     | **UX only**               |
| RLS policies + `GRANT`s in `supabase/migrations/0001_init.sql`                          | **The real authorization** |

`/my`, `/profile`, `/recipe/new`, and `*/edit` redirect to `/auth` when signed out. Everything
else — Home, Discover, search, public recipe detail — is deliberately reachable signed-out, and
RLS is what keeps private recipes out of those responses.

## Common commands

> **Pinned toolchain: Flutter 3.44.8 (Dart 3.12.2) + melos 6.x.** The Flutter pin is load-bearing:
> newer Flutter breaks `build_runner` (the `analyzer` 7.x that `freezed` 2.x pulls in cannot parse
> Dart 3.13 sources — B005). The melos pin just matches the root `pubspec.yaml` (`^6.1.0`).
> Full rationale and Windows install steps: [README.md](./README.md#toolchain-versions).

> If `melos` is not on `PATH` (pub global bin dir missing), prefix commands with
> `dart pub global run melos:` — e.g. `dart pub global run melos:melos bootstrap`.

```powershell
dart pub global activate melos 6.3.3  # once — matches root pubspec (`melos: ^6.1.0`)
melos bootstrap                     # resolve + link all packages
melos run build_runner --no-select  # codegen (freezed/json) — REQUIRED before first analyze/run
melos run analyze                   # flutter analyze across all packages
melos run test --no-select          # tests (apps/app + design_system; core has no test dir)
melos run format                    # dart format .

# Run the app (env creds are wired in). Web-server is the most reliable device here;
# Chrome isn't installed and Edge's debug auto-launch is flaky.
cd apps/app
flutter run -d web-server --web-port 8080 --dart-define-from-file=env.local.json  # open http://localhost:8080
flutter run -d windows --dart-define-from-file=env.local.json                     # native desktop
```

Build, database, and icon tasks are melos scripts (all defined in `melos.yaml`):

```powershell
melos run build:apk --no-select        # release APK (also: build:apk:split, build:appbundle)
melos run build:ios --no-select        # macOS only (also: build:ipa — needs signing)
melos run gen:icons --no-select        # launcher icons from apps/app/assets/icon/app_icon.png

# DB tasks — need `psql` on PATH and $env:SUPABASE_DB_URL. See the warning under Gotchas.
melos run db:create   # apply supabase/migrations/0001_init.sql (idempotent)
melos run db:seed     # load supabase/seed.sql (idempotent; also backfills ratings — B014)
melos run db:clean    # truncate recipe data, keep schema + users
melos run db:drop     # drop all app tables/types/functions (spares auth.users)
melos run db:reset    # drop -> create -> seed
```

> `--no-select` is required for every script that declares `packageFilters` in `melos.yaml`
> (`test`, `build_runner`, `build:*`, `gen:icons`). Without a TTY the package picker aborts with
> `StdinException: Error getting terminal echo mode` — and `melos.bat` still exits 0, so a
> scripted run fails silently (B006/B007). `analyze`, `format`, and `db:*` have no filters and
> never prompt. On Windows, grep melos output for `SUCCESS`/`FAILED` instead of trusting the
> exit code; Linux CI's wrapper propagates codes correctly.

Supabase (local dev — needs Docker; the DB container ships `psql`, so no local install needed):

```powershell
supabase start                      # local stack (prints API_URL / ANON_KEY)
supabase db reset                   # apply supabase/migrations/* then supabase/seed.sql
docker exec supabase_db_secret-sauce psql -U postgres -d postgres -c "<query>"   # inspect
supabase stop                       # tear down
```

> Verify every schema change here before touching the hosted project. RLS behavior can be
> exercised with `begin; set local role authenticated; set local request.jwt.claims = '{"sub":"<uuid>"}'; ...`.

## Required environment

| Name                | Purpose                        | Lives in                                                       |
| ------------------- | ------------------------------ | -------------------------------------------------------------- |
| `SUPABASE_URL`      | Project REST/Auth endpoint     | `apps/app/env.local.json` (git-ignored) → `--dart-define-from-file` |
| `SUPABASE_ANON_KEY` | Public anon key                | same file                                                       |
| `SUPABASE_DB_URL`   | Postgres URI for `db:*` scripts | shell env only — never a file                                   |

Copy `apps/app/env.example.json` to `env.local.json` to start. `.vscode/launch.json` and every
`melos run build:*` script already pass the file.

## Recipe data model (the crucial part)

See [docs/SDS.md §3–§6](./docs/SDS.md) for the full spec. Summary: a `recipe` has grouped
`ingredients` and grouped ordered `steps`; each edit appends a `recipe_version` snapshot
(git-like); forking deep-copies a recipe and records `forked_from_recipe_id` +
`forked_from_version_id`. A `recipe_suggestions` table is reserved (stub) for a future "suggest
changes upstream" (PR-like) flow.

Server-owned columns the client must **never** write (trigger-maintained; omitted from
`_writablePayload` in `recipe_repository.dart`): `like_count`, `save_count`, `view_count`,
`rating_sum`, `rating_count`, `rating_avg`, `current_version_id`, `created_at`, `updated_at`.

**Ratings**: `recipe_ratings` holds one row per (user, recipe), `0.5`–`5.0` in half-star steps
(SQL check constraint _and_ `snapRating()` in core). A trigger recomputes
`recipes.rating_sum / rating_count / rating_avg` from scratch — clients read those and never
write them. RLS forbids rating your own recipe (`with check`, not just a hidden button).
Discover's **Popular** tab ranks by a Bayesian weighted average of the rating (m = 5 phantom
ratings at the site mean), not raw likes/saves.

Four Postgres enums are mirrored exactly in [enums.dart](packages/core/lib/src/models/enums.dart):
`difficulty`, `recipe_visibility`, `share_permission` (`edit` reserved, unused), `suggestion_status`.

## Feature map

| Route                             | Feature dir              | Notes                                                     |
| --------------------------------- | ------------------------ | --------------------------------------------------------- |
| `/`                               | `features/home`          | Landing; signed-out safe                                  |
| `/auth`                           | `features/auth`          | `authControllerProvider` (AsyncNotifier); redirects to `/discover` when signed in |
| `/discover`                       | `features/discover`      | Popular / Trending / Recent + search; all four via `DiscoverRepository`; signed-out safe |
| `/my`                             | `features/my_recipes`    | My / Shared-with-me tabs; `share_dialog.dart` writes `recipe_shares` |
| `/recipe/:id`                     | `features/recipe_detail` | Servings scaler, rating, like/save, fork, `version_history_sheet.dart`; signed-out safe |
| `/recipe/new`, `/recipe/:id/edit` | `features/recipe_editor` | `edit_models.dart` holds mutable draft types; save appends a version |
| `/profile`                        | `features/profile`       | Current user                                              |

Only `/discover`, `/my`, `/profile` sit inside the `ShellRoute` (nav chrome); detail and editor
are pushed on the root navigator.

## Conventions

- **Codegen**: after editing any `freezed`/`json`-annotated file, run
  `melos run build_runner --no-select`. Never hand-edit generated `*.g.dart` / `*.freezed.dart`.
  Only `packages/core` has codegen — it is the only package with `build_runner`, so it is the only
  one the script touches.
- **Providers are hand-written; there is no riverpod codegen.** `riverpod_annotation` /
  `riverpod_generator` were removed as unused (B021) — every provider is a plain `Provider` /
  `FutureProvider` / `StateProvider` / `NotifierProvider`. Don't reintroduce generated providers
  in a one-off file. Feature providers live in `features/<name>/<name>_providers.dart`;
  cross-cutting ones in `core/src/providers.dart`. Names end in `Provider`.
- **Imports are always `package:` — including within a package.** `analysis_options.yaml` enables
  `always_use_package_imports`, so `core/src/providers.dart` imports `package:core/src/...` and
  app files import `package:app/...`. A relative import fails `melos run analyze`.
- **Naming**: files `snake_case.dart`; types `PascalCase`.
- **Lints beyond `flutter_lints`**: `prefer_const_constructors`, `prefer_final_locals`,
  `unawaited_futures`, `require_trailing_commas`.
- **Layout**: use `AppSpacing` / `AppRadii` tokens and `responsiveColumns` / `AdaptiveLayout` /
  `context.isCompact` from `design_system`; breakpoints are 600 (compact) and 1000 (medium) —
  don't hard-code widths.
- **No secrets in the repo.** Credentials come from `env.local.json` via `--dart-define-from-file`.
- **Security**: never trust the client for authorization — enforce via Supabase **RLS**.

## Gotchas & invariants

The full, evidence-cited version of this list is
[.claude/skills/review-checklist/SKILL.md](.claude/skills/review-checklist/SKILL.md) (loaded by
the `code-review` skill). The ones you need while *writing* code:

1. **Generated code is git-ignored** (`.gitignore:11-13`). A fresh clone does not compile until
   `melos run build_runner --no-select`. Codegen output never appears in a diff — say so rather
   than looking for it. (`pubspec.lock` is ignored too — B009, still open.)
2. **`.update()` / `.delete()` matching 0 rows returns success.** An RLS denial on those is
   invisible to the client (the twin of B011). `.insert()` / `.upsert()` do raise `42501`. Add
   `.select()` to any update/delete on a path where the user may not own the row.
3. **Trigger rights.** A trigger that writes a row the acting user does not own must be
   `security definer set search_path = public`, or the UPDATE silently affects 0 rows (B011).
   Mutating helpers stay invoker-rights **and** must `revoke execute` from
   `public`/`anon`/`authenticated` — PostgREST exposes every `public` function as an RPC.
4. **`GRANT` and RLS are both required.** A new table must be covered by the grants block at
   `0001_init.sql:565-581`, or every API call returns `permission denied for table …` (B013).
   RLS with no policy default-denies: reads return empty, not an error.
5. **`0001_init.sql` is one idempotent file, re-applied in place** (`db:create`, `supabase db
   reset`, hosted paste). Every statement must be guarded: `if not exists`,
   `drop policy if exists`, `create or replace`, `alter table … add column if not exists`.
   Change a function signature → add the exact old signature to `supabase/scripts/drop.sql`.
6. **`db:*` scripts fire at whatever `SUPABASE_DB_URL` points at — no confirmation, no prod
   guard** ([tool/db.dart](tool/db.dart)). `db:reset` is `drop → create → seed`. `README.md`
   documents pasting `seed.sql` into the **hosted** dashboard, so anything in that file runs on
   production by documented procedure — never put a literal credential there (B018: nine
   log-in-able production accounts). `drop.sql` spares `auth.users`, so seeded accounts are
   permanent.
7. **`SupabaseService.init()` guards missing credentials with `assert`** — stripped in release
   builds. A release built without `--dart-define-from-file` initializes Supabase with empty
   strings and fails at request time, not startup. Don't guard new required config with `assert`.
8. **Signed-out paths.** `SupabaseRecipeRepository._uid` throws `StateError`. Any repository call
   reachable from Home / Discover / recipe detail must use `currentUser?.id` the way `logView`
   and `myRating` do.
9. **`view_count` is an upper bound on distinct signed-in viewers, not a visit count** (B012).
   `recipe_views` stays an append-only log; `on_view_insert` bumps `recipes.view_count` only on a
   user's **first** row for that recipe, and **never** for anonymous rows — `anon` holds `insert`
   there, so counting them would let an unauthenticated loop inflate `recipes_trending`.
   `views_insert` also pins `user_id` to `auth.uid()` (or null), so views cannot be attributed to
   someone else. The counter is **monotonic** — nothing decrements it, and `user_id` is
   `on delete set null`, so a deleted account leaves its contribution behind. Seeded recipes carry
   synthetic `view_count` values written directly by `seed.sql`, so their counter and their log
   disagree by design. Don't write code that assumes `view_count` equals a `count(distinct …)`
   over the log.
10. **`RecipeRepository.update()` is not atomic**: it deletes all `ingredient_groups` /
    `step_groups` then re-inserts. A failure between the two loses the recipe's content. Don't
    lengthen that window.
11. **Postgres `numeric` arrives as a JSON number that may be int or double** — decode with
    `(value as num).toDouble()`, never a bare `as double`.
12. **Fixed-aspect cards cannot grow, so their rows must degrade.** Three logged `RenderFlex`
    overflows (B001, B002, B016) came from adding an intrinsically-sized child to a
    `RecipeCard`/grid row. Test the real envelope: **276px** wide (2 columns at the 600px
    breakpoint), longest labels, **2.0× text scale**.
13. **New `design_system` widget → export it from `design_system.dart`**, or `apps/app` cannot
    import it.
14. **`packages/core` has no `test/` directory**, so every repository, `snapRating`, and all JSON
    decoding are untested — `melos run test --no-select` only covers `apps/app` and
    `design_system`. Repository tests are blocked on mocking `SupabaseClient` (ROADMAP Phase 3).
    Treat a green test run as *no evidence at all* about `core`; verify core changes against a
    local Supabase stack instead.

## Docs–code sync (MANDATORY)

Documentation and code must always be in sync. **The docs that must be kept current are:**
`README.md`, `CLAUDE.md`, and everything under `docs/` (`ROADMAP.md`, `EXECUTION-PLAN.md`,
`SDS.md`, `BUG-TRACKER.md`).

For **every** change, before it is considered done:

1. Update `docs/ROADMAP.md` task status (`[ ]` → `[x]`, or add new tasks).
2. If behavior/architecture/schema changed, update `docs/SDS.md`.
3. If you implemented a roadmap task, ensure `docs/EXECUTION-PLAN.md` reflects reality.
4. Any bug found or fixed goes into `docs/BUG-TRACKER.md`.
5. **If you changed how the project is run, built, released, configured, or set up** (commands,
   flags, devices, env vars, tasks, app name/icon, platform config), update `README.md` **and**
   the "Common commands" section of this `CLAUDE.md`. Keep example commands copy-paste accurate
   for this environment (e.g. web runs via `-d web-server`, not `-d chrome`).

A change is **not complete** until the relevant docs above are updated in the same commit/change
set. When in doubt, re-read the affected doc and confirm every command/flag still matches reality.

**Maintenance rule for this file:** if a human corrects an agent twice about the same project
fact, add it here — citing the bug ID if there is one. When a rule stops being true, delete it
the same day.
