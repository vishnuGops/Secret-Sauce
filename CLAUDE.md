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
- **North star** (see ROADMAP "Product direction" + Phase 25): on top of the chef layer, the app
  will list **restaurants** — an entity *managed by* profiles, never a second login. A restaurant
  has optional member chefs and **signature dishes** that point at existing public recipes.
  Design a new feature so it doesn't fight that: profiles stay the only principal, engagement
  stays on recipes.

## Tech stack

| Layer            | Choice                                                              |
| ---------------- | ------------------------------------------------------------------- |
| UI               | **Flutter** — single **adaptive** codebase (web + mobile + desktop) |
| State management | **Riverpod** — hand-written providers only (see Conventions)        |
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
├── recipeData/                # THE Secret Sauce Kitchen's 14 recipes (content)
│   ├── recipes/<slug>.json    #   one per file — the filename IS the identity
│   ├── schema.json            #   the format, field by field, mapped to columns
│   └── README.md              #   authoring workflow
├── simData/                   # simulation dish LIBRARY (Phase 24, 25/120 authored)
│   ├── dishes/<slug>.json     #   owner-agnostic; NOT recipes until the generator runs
│   ├── schema.json            #   the 2-key delta from recipeData's format
│   └── README.md              #   authoring workflow + directory coverage rules
├── tool/db.dart               # psql wrapper behind the melos db:* scripts
├── tool/recipe_format.dart    # THE validator — shared by both generators below
├── tool/recipes.dart          # validates recipeData/ -> generates seed_recipes.sql
├── tool/sim.dart              # validates simData/  -> generates sim/1_sim_dishes.sql
├── packages/
│   ├── core/lib/
│   │   ├── core.dart              # BARREL — the only public surface of `core`
│   │   ├── src/{models,repositories,services}/ + providers.dart
│   │   └── ../test/               # chef_models_test.dart (model decoding only —
│   │                              # repositories are still untested)
│   └── design_system/lib/
│       ├── design_system.dart     # BARREL — export new widgets here or app can't import them
│       ├── src/{theme,layout,widgets}/
│       └── ../test/               # recipe_card_test.dart, star_rating_test.dart,
│                                  # chef_badge_test.dart
├── apps/app/
│   ├── lib/features/          # auth, discover, chefs, my_recipes, recipe_detail,
│   │                          # recipe_editor, profile — screen + *_providers.dart per feature
│   │                          # (home/ was retired 2026-08-20 — `/` redirects to /discover)
│   ├── lib/routing/           # app_router.dart (routes + redirect), app_shell.dart (picks the
│   │                          #   chrome), top_nav_bar.dart (web), nav_destinations.dart (lists)
│   ├── lib/widgets/           # app-level shared widgets (recipe_grid.dart)
│   ├── lib/main.dart · test/{widget_test,chefs_screen_test,chefs_routing_test,
│   │                          top_nav_bar_test,recipe_editor_test,recipe_detail_test,
│   │                          my_recipes_header_test,recipe_grid_test}.dart
│   │                          # widget_test.dart covers the `/` -> /discover redirect
│   ├── env.example.json       # template; env.local.json (git-ignored) holds real creds
│   └── android/ ios/ web/ windows/   # platform runners are committed — no `flutter create`
└── supabase/
    ├── migrations/0001_init.sql  # THE schema: tables, triggers, RLS, grants, storage, RPCs
    ├── seed.sql                  # DEMO fixtures: accounts, demo chefs, ratings (idempotent)
    ├── seed_recipes.sql          # GENERATED from recipeData/ — never hand-edit
    ├── sim/                      # simulated population (Phase 24); schema `sim`, never `public`
    │   ├── 0_sim_schema.sql      #   config, personas, presets, registries, rand helpers
    │   ├── 1_sim_dishes.sql      #   GENERATED from simData/ — never hand-edit
    │   ├── 2_sim_generate.sql    #   the generator; counters DERIVED from the engagement log
    │   ├── 3_sim_verify.sql      #   30 assertions — the only test coverage this SQL has
    │   └── 9_sim_teardown.sql    #   registry-driven; deletes auth.users rows
    └── scripts/{drop,clean}.sql · rotate_seed_passwords.sql (B018 — hosted, manual)
```

`seed.sql` and `seed_recipes.sql` are split on purpose: the first is **demo data** with a
deletion date, the second is **content** that outlives it. No recipe is defined in both.
Both bootstrap the same Secret Sauce Kitchen account with conflict guards, so recipe content is
order-independent — but **apply `seed.sql` first**: `seed_recipes.sql` borrows its taster
accounts for the demo ratings and silently (well, with a notice) skips them otherwise.
`melos run db:reset` and `config.toml`'s `db.seed.sql_paths` both order it correctly.

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

| Layer                                                                               | Status                       |
| ----------------------------------------------------------------------------------- | ---------------------------- |
| `redirect` in [app_router.dart:42-52](apps/app/lib/routing/app_router.dart#L42-L52) | **UX only** — never security |
| Hidden/disabled buttons on a screen                                                 | **UX only**                  |
| RLS policies + `GRANT`s in `supabase/migrations/0001_init.sql`                      | **The real authorization**   |

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
melos run test --no-select          # tests (any package with a test/ dir — currently all three)
melos run format                    # dart format . — see the B027 warning below before running

# Run the app (env creds are wired in). Web-server is the most reliable device here;
# Chrome isn't installed and Edge's debug auto-launch is flaky.
cd apps/app
flutter run -d web-server --web-port 8080 --dart-define-from-file=env.local.json  # open http://localhost:8080
flutter run -d windows --dart-define-from-file=env.local.json                     # native desktop

# Screenshots / any automated browser: the debug web server renders for ONE client only, so a
# second page load is blank (B028). Build and serve statically instead. Deep links are hashed.
# Playwright needs a browser first: `npx playwright install chrome` (Chrome is not installed here).
flutter build web --release --dart-define-from-file=env.local.json
npx serve -l 8099 build/web            # http://localhost:8099/#/discover
```

> **`env.local.json` decides which database you are looking at, and it is not always the hosted
> one.** As of 2026-08-20 it points at the **local** stack (`http://127.0.0.1:54321`), with the
> hosted project's credentials preserved beside it in `apps/app/env.hosted.local.json` — swap the
> two files to switch back. Both names are git-ignored (`env.local*` / `env.*.local*`); a plain
> `env.hosted.json` would **not** be — that is exactly the glob B010 was widened to catch, so never
> save credentials under that name. The local stack needs `supabase start`, and no account in it has
> a password anyone knows: every seeded account gets a random one (B018), so sign up a fresh user
> and collect the confirmation mail from Mailpit at `http://127.0.0.1:54324`, not a real inbox.

> **`melos run format` currently breaks `melos run analyze` (B027).** `dart format` picks its
> style from the _package's_ language version, and all four pubspecs declare `sdk: ">=3.4.0"` —
> under 3.7, so the formatter emits the legacy short style with no trailing commas, and
> `require_trailing_commas` then flags every one it removed. The committed tree is in the newer
> tall style. Until the `sdk:` bound is raised (or the lint dropped), leave formatting alone; if
> you run it by accident, `git checkout --` the files it touched outside your change.

Build, database, and icon tasks are melos scripts (all defined in `melos.yaml`):

```powershell
melos run build:apk --no-select        # release APK (also: build:apk:split, build:appbundle)
melos run build:ios --no-select        # macOS only (also: build:ipa — needs signing)
melos run gen:icons --no-select        # launcher icons from apps/app/assets/icon/app_icon.png

# Recipe content — pure file operations, no database or credentials needed.
melos run recipes:validate  # parse + lint recipeData/recipes/*.json
melos run recipes:gen       # regenerate supabase/seed_recipes.sql (commit both)
melos run recipes:check     # fail if that .sql is stale — CI runs this

# Simulation dish library (Phase 24). Same format and the SAME validator as
# recipeData (tool/recipe_format.dart) — a dish is promoted to curated content by
# moving the file and deleting its `sim` block. Nothing here is a recipe until
# supabase/sim/2_sim_generate.sql draws from it (see db:sim below).
melos run sim:validate      # parse + lint + directory coverage rules
melos run sim:gen           # regenerate supabase/sim/1_sim_dishes.sql (commit both)
melos run sim:check         # fail if that .sql is stale — CI runs this

# DB tasks — need `psql` on PATH and $env:SUPABASE_DB_URL. See the warning under Gotchas.
melos run db:create   # apply supabase/migrations/0001_init.sql (idempotent)
melos run db:seed     # load supabase/seed.sql (idempotent; also backfills ratings — B014)
melos run db:recipes  # load supabase/seed_recipes.sql (idempotent; run recipes:gen first)
melos run db:clean    # truncate recipe data, keep schema + users
melos run db:drop     # drop all app tables/types/functions (spares auth.users)
melos run db:reset    # drop -> create -> seed -> recipes -> sim   (~15s from empty)

# Simulated population (Phase 24). Additive and idempotent; ~10s at the default
# `medium` preset (1,000 accounts, ~1,670 recipes, ~118k view rows).
melos run db:sim                          # schema -> dishes -> generate -> verify
melos run db:sim -- --preset=small --seed=7
melos run db:sim:verify                   # 30 assertions, read-only
melos run db:sim:clean -- --yes           # DESTRUCTIVE: deletes the simulated auth.users
```

> **The sim derives its counters; `seed.sql` authors them.** `seed.sql` writes `like_count = 2500`
> with no `recipe_likes` rows behind it. The sim writes the rows and recomputes the counter, which
> is what gives dated and windowed queries anything to read (SDS §10.8). Three rules follow:
> engagement rows must be bulk-loaded with the **counter triggers disabled** (live, the load is one
> `recompute_chef_stats()` per row); the recompute must call the real `chef_score()` /
> `chef_tier_for()` and never restate `3 / 5 / 0.2` (Gotcha 19); and `sim.epoch_end()` is a **pinned**
> time anchor, not `now()` — a moving anchor re-dates every recipe out from under the versions that
> reference it (B044). Teardown is driven by the `sim.actor` / `sim.recipe` **registries**, never by
> an email or id pattern: it deletes `auth.users` rows, and a pattern that is subtly wrong on the
> hosted project has no undo.

> **`melos run db:*` does not work on this machine as written (B033)** — `psql` is not installed,
> and the only client available is the one inside the Supabase Docker container. Applying a schema
> change to the **hosted** project through that container also needs the **Session pooler** host:
> `db.<ref>.supabase.co` is IPv6-only and the container has no IPv6 route. What works:
>
> ```powershell
> $u = "postgresql://postgres.<project-ref>:<pwd>@aws-0-<region>.pooler.supabase.com:5432/postgres"
> Get-Content supabase\migrations\0001_init.sql -Raw |
>   docker exec -i supabase_db_secret-sauce psql $u -v ON_ERROR_STOP=1 -f -
> ```
>
> The pooler user is `postgres.<project-ref>`, not bare `postgres`. A dashboard password reset takes
> a moment to propagate — check auth on its own (`psql $u -c "select 1"`) before blaming the SQL.
> **`SUPABASE_DB_URL` never goes in a dart-define file** (B034, fixed by OPT-S7): those are
> compiled into shipped builds via `--dart-define-from-file`, and this is a superuser credential.
> It lives in `db-url.local.ps1` (git-ignored), dot-sourced per shell — see "Required environment".

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

| Name                | Purpose                         | Lives in                                                            |
| ------------------- | ------------------------------- | ------------------------------------------------------------------- |
| `SUPABASE_URL`      | Project REST/Auth endpoint      | `apps/app/env.local.json` (git-ignored) → `--dart-define-from-file` |
| `SUPABASE_ANON_KEY` | Public anon key                 | same file                                                           |
| `SUPABASE_DB_URL`   | Postgres URI for `db:*` scripts | shell env — **never a dart-define file** (B034)                     |

Copy `apps/app/env.example.json` to `env.local.json` to start. `.vscode/launch.json` and every
`melos run build:*` script already pass the file.

`SUPABASE_DB_URL` is a Postgres **superuser** credential and every key in a dart-define file is
compiled into the shipped bundle, so it lives outside them (B034 / OPT-S7). Copy
`db-url.example.ps1` to `db-url.local.ps1` (git-ignored via `*.local.ps1`) and dot-source it in
the shell you run database tasks from:

```powershell
. .\db-url.local.ps1     # sets $env:SUPABASE_DB_URL for THIS shell only
melos run db:create
```

Deliberately per-shell and per-project rather than a Windows user environment variable: a global
value would be inherited by every other repo on the machine, and `tool/db.dart` fires at whatever
`SUPABASE_DB_URL` says with no confirmation and no prod guard (Gotcha 7). The committed
`db-url.local.ps1` template points at the **local** stack; the hosted pooler URI is a commented
second line, so aiming `db:*` at production is an explicit act.

## Recipe data model (the crucial part)

See [docs/SDS.md §3–§6](./docs/SDS.md) for the full spec. Summary: a `recipe` has grouped
`ingredients` and grouped ordered `steps`; each edit appends a `recipe_version` snapshot
(git-like); forking deep-copies a recipe and records `forked_from_recipe_id` +
`forked_from_version_id`. A `recipe_suggestions` table is reserved (stub) for a future "suggest
changes upstream" (PR-like) flow.

Server-owned columns the client must **never** write (trigger-maintained; omitted from
`_writablePayload` in `recipe_repository.dart`): on `recipes` — `like_count`, `save_count`,
`view_count`, `rating_sum`, `rating_count`, `rating_avg`, `current_version_id`, `created_at`,
`updated_at`; on `profiles` — `chef_score`, `chef_tier`, `public_recipe_count` (omitted from
`ProfileRepository.updateMine`). **This is enforced in the database (B050 fixed by OPT-S1):**
`recipes` and `profiles` hold **column-level** `insert`/`update` grants, not the blanket
table-level one, because RLS filters rows and cannot filter columns. Two consequences: a
`PATCH` of a server-owned column now fails `42501` even for the row's owner, and **a new
client-writable column must be added to the grant list in `0001_init.sql` in the same change**
or the first save carrying it fails the same way. `current_version_id` is moved by the
`recipe_versions_set_current` trigger — never write it from Dart.

**Nested content order (B022).** Ingredient/step groups and their children are stored and read in
**ascending** `sort_order` (`step_order` for steps). postgrest-dart's `.order(column)` defaults to
`ascending: false`, so every nested read passes `ascending: true` explicitly. This is not
cosmetic: `update()` re-persists the list it just read, so a reversed read writes a reversed
order back.

**Ratings**: `recipe_ratings` holds one row per (user, recipe), `0.5`–`5.0` in half-star steps
(SQL check constraint _and_ `snapRating()` in core). A trigger recomputes
`recipes.rating_sum / rating_count / rating_avg` from scratch — clients read those and never
write them. RLS forbids rating your own recipe (`with check`, not just a hidden button).
Discover's **Popular** tab ranks by a Bayesian weighted average of the rating (m = 5 phantom
ratings at the site mean), not raw likes/saves.

**Chefs & tiers**: "chef" is a presentation of `profiles`, not a second principal table.
`profiles.chef_score / chef_tier / public_recipe_count` are denormalized aggregates over the
engagement counters of that user's **public** recipes, recomputed from scratch by the
`on_recipe_stats_change` trigger — same pattern as `recipes.rating_*`. `chef_score()` and
`chef_tier_for()` in `0001_init.sql` are the single source of truth for the formula and the
thresholds; an idempotent backfill on every apply is how a change reaches existing rows.
`chefs_leaderboard(limit, offset)` is the `anon`-callable RPC behind `/chefs`, and
`chef_top_recipes(chef, limit)` — `setof recipes`, ordered by `chef_score()` per recipe — backs
the expanded chef card. Details: [SDS §10](./docs/SDS.md#10-chefs-tiers--leaderboard).

Five Postgres enums are mirrored exactly in [enums.dart](packages/core/lib/src/models/enums.dart):
`difficulty`, `recipe_visibility`, `share_permission` (`edit` reserved, unused),
`suggestion_status`, `chef_tier`.

## Feature map

| Route                             | Feature dir              | Notes                                                                                                                    |
| --------------------------------- | ------------------------ | ------------------------------------------------------------------------------------------------------------------------ |
| `/`                               | — (no screen)            | **Redirect-only** → `/discover`. `features/home` was retired 2026-08-20; see the note under the table                    |
| `/auth`                           | `features/auth`          | `authControllerProvider` (AsyncNotifier); redirects to `/discover` when signed in; `?mode=signup` opens the sign-up side |
| `/discover`                       | `features/discover`      | Popular / Trending / Recent + search; all four via `DiscoverRepository`; signed-out safe                                 |
| `/chefs`                          | `features/chefs`         | Web: `chefs_hero.dart` + a 404px leaderboard panel + rails of `ChefSpotlightCard`. Compact: the plain board. A row or card opens `chef_detail_sheet.dart` (dialog on web, sheet on mobile); signed-out safe |
| `/my`                             | `features/my_recipes`    | My / Shared-with-me tabs; `share_dialog.dart` writes `recipe_shares`                                                     |
| `/recipe/:id`                     | `features/recipe_detail` | Servings scaler, rating, like/save, fork, `version_history_sheet.dart`; signed-out safe                                  |
| `/recipe/new`, `/recipe/:id/edit` | `features/recipe_editor` | `edit_models.dart` holds mutable draft types; save appends a version                                                     |
| `/profile`                        | `features/profile`       | Current user; reached from the bottom bar on mobile and the avatar menu on web (`myProfileProvider`)                     |

Only `/discover`, `/chefs`, `/my`, `/profile` sit inside the `ShellRoute` (nav chrome); detail and
editor are pushed on the root navigator. `/profile` is in the shell but is **not** a web
destination, so the top bar's pill highlights nothing there — see Gotcha 18.

**Discover is the front door; `/` is a redirect, not a page.** The landing screen was retired
because no navigation chrome ever linked it — the web brand mark goes to `/discover`, the mobile
bottom bar has no Home slot — so a cold start or a stale bookmark was the only way to reach it.
Two mechanisms are needed and both are load-bearing: `initialLocation: Routes.discover` covers a
mobile/desktop cold start (the platform reports no route), and the redirect-only
`GoRoute(path: Routes.root)` covers web (the browser reports `/`). Adding a `builder` back to that
route resurrects a screen nothing links to — `apps/app/test/widget_test.dart` fails if you do.
Sign-out goes straight to `/discover` from both the avatar menu and the profile screen; do not
point it at `/`.

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
the `code-review` skill). The ones you need while _writing_ code:

1. **Generated code is git-ignored** (`.gitignore:11-13`). A fresh clone does not compile until
   `melos run build_runner --no-select`. Codegen output never appears in a diff — say so rather
   than looking for it. (`pubspec.lock` is ignored too — B009, still open.)
2. **`.update()` / `.delete()` matching 0 rows returns success.** An RLS denial on those is
   invisible to the client (the twin of B011). `.insert()` / `.upsert()` do raise `42501`. Add
   `.select()` to any update/delete on a path where the user may not own the row, and throw
   `WriteDeniedException` (core) when the result is empty — `RecipeRepository.update()`,
   `delete()`, and `unshare()` do this (OPT-S2). In `update()` the check sits **before** the
   group deletes on purpose: a denied save must not reach the content-replacement step. The
   like/save/rating deletes are keyed by the caller's own `_uid`, so RLS cannot deny them and
   they deliberately skip the check.
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
   **Changing a function's argument list is not something `create or replace` can do** — the old
   overload survives beside the new one, and any call matching both fails with
   `42725 … is not unique`. Drop every historical signature **in the file that recreates the
   function**, not only in `drop.sql`: `drop.sql` is a separate destructive script that a plain
   re-apply or re-seed never runs (B024).
6. **Test SQL on the upgrade path, not only on a fresh `db reset`.** `supabase db reset` builds
   from scratch and `drop.sql → create → seed` drops everything first, so neither can surface a
   stale-object bug — and those are the only two paths that are convenient to run. A deployed
   database takes a third path nobody tests: _old schema + old seed already applied, new files
   layered on top_. Reconstruct it with `git show <last-release>:supabase/…` before believing a
   schema change is safe. B024 shipped through a green run of both easy paths. The fourth path is
   a **truly clean machine** (B045): a function in an earlier-numbered file whose body references
   an object a later file creates passes everywhere the object already exists — verify multi-file
   SQL from a dropped-schema state too.
7. **`db:*` scripts fire at whatever `SUPABASE_DB_URL` points at — no confirmation, no prod
   guard** ([tool/db.dart](tool/db.dart)). `db:reset` is `drop → create → seed`. `README.md`
   documents pasting `seed.sql` into the **hosted** dashboard, so anything in that file runs on
   production by documented procedure — never put a literal credential there (B018: nine
   log-in-able production accounts). `drop.sql` spares `auth.users`, so seeded accounts are
   permanent.
8. **`SupabaseService.init()` guards missing credentials with `assert`** — stripped in release
   builds. A release built without `--dart-define-from-file` initializes Supabase with empty
   strings and fails at request time, not startup. Don't guard new required config with `assert`.
9. **Signed-out paths.** `SupabaseRecipeRepository._uid` throws `StateError`. Any repository call
   reachable from Home / Discover / recipe detail must use `currentUser?.id` the way `logView`
   and `myRating` do.
10. **`view_count` is an upper bound on distinct signed-in viewers, not a visit count** (B012).
    `recipe_views` stays an append-only log; `on_view_insert` bumps `recipes.view_count` only on a
    user's **first** row for that recipe, and **never** for anonymous rows — `anon` holds `insert`
    there, so counting them would let an unauthenticated loop inflate `recipes_trending`.
    `views_insert` also pins `user_id` to `auth.uid()` (or null), so views cannot be attributed to
    someone else. The counter is **monotonic** — nothing decrements it, and `user_id` is
    `on delete set null`, so a deleted account leaves its contribution behind. Seeded recipes carry
    synthetic `view_count` values written directly by `seed.sql`, so their counter and their log
    disagree by design. Don't write code that assumes `view_count` equals a `count(distinct …)`
    over the log.
11. **`RecipeRepository.update()` is not atomic**: it deletes all `ingredient_groups` /
    `step_groups` then re-inserts. A failure between the two loses the recipe's content. Don't
    lengthen that window.
12. **Postgres `numeric` arrives as a JSON number that may be int or double** — decode with
    `(value as num).toDouble()`, never a bare `as double`.
13. **Fixed-size cards cannot grow, so their rows must degrade.** Three logged `RenderFlex`
    overflows (B001, B002, B016) came from adding an intrinsically-sized child to a
    `RecipeCard`/grid row. Test the real envelope: **288px** wide (`kRecipeCardMinWidth`, the
    narrowest column the grid packs to), longest labels, **2.0× text scale**. `RecipeCard` is a
    **fixed-height** tile — `kRecipeCardHeight` (352), passed by `recipe_grid.dart` as
    `mainAxisExtent` — with exactly one flexible band, the cover. The title banner is a **fixed**
    band (`kRecipeCardBannerHeight` 65 × `context.textScale`, capped at
    `kRecipeCardBannerMaxScale` 2.0 so it cannot starve the cover, title vertically centred,
    clamped to two lines) so one-line and two-line names give the same card (B047); the footer is
    intrinsic. The card still overflows at **3.0×** and always has (B049) — its contract is 2.0×.
    Whatever you add to either comes out of a fixed budget, and a longer title eats cover height
    rather than growing the card.
    **The card grid flows; it does not switch at breakpoints.** `FlowGridMetrics.fit`
    (`adaptive.dart`) fits as many columns as can each hold `kRecipeCardMinWidth` (288 — the floor
    at which the metadata row fits *uncut*; it was 264 until B048), caps every
    tile at `kRecipeCardMaxWidth` (340), and returns the gutter that centres a capped row;
    `RecipeGrid` feeds that into a `LayoutBuilder` + `SliverGridDelegateWithFixedCrossAxisCount`.
    The delegate always divides the **whole** cross-axis extent between its columns, so a tile can
    only be capped by handing the grid less width — that is what the gutter padding is for; a
    `ConstrainedBox` inside the card is ignored under the cell's tight constraints.
    `responsiveColumns` still exists for navigation chrome and non-card grids — don't wire it back
    into a card grid.
14. **New `design_system` widget → export it from `design_system.dart`**, or `apps/app` cannot
    import it.
15. **`packages/core` is only _partly_ tested, and the untested half is the risky half.**
    `packages/core/test/` covers pure JSON→model decoding (enum wire values, column-name
    mappings, `numeric` handling) — no `SupabaseClient` needed, so that blocker never applied
    there. Still untested: **every repository method**, `snapRating`, and anything that issues a
    query. Those remain blocked on mocking `SupabaseClient` (ROADMAP Phase 3). A green run proves
    your models decode; it proves nothing about what the database actually returns. For that,
    verify against a local stack — a throwaway harness under `apps/app/test/` pointed at
    `http://127.0.0.1:54321` is the practical way to drive real repository code; delete it after,
    since CI has no database job.
    **Nothing in CI tests SQL at all** — the formula/threshold functions, the triggers, RLS, and
    the ranking RPCs are covered only by manual local-stack runs recorded in `BUG-TRACKER.md`.
16. **`supabase/seed_recipes.sql` is generated — edit `recipeData/recipes/*.json` instead.**
    `melos run recipes:gen` rewrites it; commit both. CI's `recipes:check` catches a stale file,
    which matters because **nothing reads the JSON at runtime** — drift is invisible until the
    wrong SQL is applied to a database. Three rules the format exists to enforce: `quantity` is a
    decimal (`1.25`, not `"1 1/4"`) because the servings scaler multiplies a `numeric`; `servings`
    is an integer, so pan sizes and piece counts go in `description`; unattended time (chilling,
    rising, marinating) is a step's `duration_minutes`, not `prep_minutes`. `seed_recipe_v2` is
    **not an upsert** — it returns early on an existing `(owner_id, title)`, so re-applying never
    pushes a content edit to a database that already has the recipe.
17. **Embedding `profiles` into a recipe query needs the FK hint.** `recipes` and `profiles` are
    related five ways (`owner_id`, plus many-to-many through likes/ratings/saves/shares), so the
    obvious `owner:profiles(...)` fails with `PGRST201: Could not embed because more than one
relationship was found`. Use the shared `kRecipeSelect` constant in
    [recipe_queries.dart](packages/core/lib/src/repositories/recipe_queries.dart) — it carries
    `owner:profiles!recipes_owner_id_fkey(...)`. Dropping the hint breaks every recipe query at
    once, including the Discover RPCs.
18. **Navigation chrome is two bars with two destination lists**, both in
    [nav_destinations.dart](apps/app/lib/routing/nav_destinations.dart): compact keeps four slots
    _including Profile_; the web bar ([top_nav_bar.dart](apps/app/lib/routing/top_nav_bar.dart))
    drops Profile for the avatar account menu and hides My Recipes when signed out. A new
    destination has to pick a list. The web bar carries **destinations and identity only** — `New
recipe` lives on the My Recipes header and search in Discover's search bar; putting either
    back is what crowded the row at medium. Its pill measures label widths with a `TextPainter`
    and drops labels to icons rather than wrapping, so a longer destination costs the others their
    labels — check any change at 600px and 2.0× text scale, the same envelope as the card (#13).
19. **`ChefScoring` mirrors SQL — edit both sides in one commit.**
    [chef_scoring.dart](packages/core/lib/src/chef_scoring.dart) restates the score weights
    (3 / 5 / 0.2) and the tier thresholds (100 / 1000 / 5000 / 20000) in Dart, because the expanded
    chef card *explains* them (`1,980 likes × 3`, `9,811 points to Master Chef`). SQL remains the
    source of truth — nothing writes a score or a tier from Dart. Change `chef_score()` /
    `chef_tier_for()` without changing this file and the card starts explaining a formula the
    database does not use. `packages/core/test/chef_scoring_test.dart` exists to fail loudly when
    that happens, so a failure there means **check which side moved**, not *update the expectation*.
20. **A field the recipe editor's draft types drop is a field the next save deletes** (B035).
    `RecipeRepository.update()` does not patch — `_persistContent` deletes the recipe's groups and
    re-inserts the `Recipe` the editor handed it, so
    [edit_models.dart](apps/app/lib/features/recipe_editor/edit_models.dart) must mirror **every**
    column of `Ingredient` and `RecipeStep`, including ones with no input widget yet
    (`steps.image_url` is carried through verbatim for that reason). It modelled a step as its text
    alone, which both hid `temperature` / `duration_minutes` / `tip` from anyone creating a recipe
    *and* silently wiped them from the seeded recipes on any edit. Add a column to either model and
    you add it to the draft in the same change — `apps/app/test/recipe_editor_test.dart`'s
    round-trip group fails if you don't. Same trap as B022's secondary damage.
21. **`Expanded` beside `Flexible` in one row is a 50/50 split, not a priority order** (B038, and
    B026 before it). `RenderFlex` divides the free space by flex factor, so a two-flex-child row
    reserves half for each *whatever the content says* — the short child leaves dead space and the
    long one truncates beside it. Where one child must win, make the other **non-flex inside a
    `ConstrainedBox`** cap (`LayoutBuilder` → `maxWidth: constraints.maxWidth / 2` or `/ 3`) with a
    `FittedBox` if it is a number. That is the shape `RecipeCard` uses for `DifficultyBadge`, the
    spotlight card for its score and points, and the board row for its score. The other half of the
    same rule: a **non-flex child of a `Row` is laid out with an unbounded main axis**, so anything
    in that position without a cap overflows rather than shrinking (B039).
22. **A page can be over-budget in height the same way a card row is over-budget in width** (B037).
    `Column(header, Expanded(body))` gives the header its intrinsic height first — if the header is
    taller than the viewport, `Expanded` gets nothing and the column overflows; no amount of
    flexibility below it helps. Layouts that fix their own space (a non-scrolling hero over
    fixed-height columns) must therefore bound themselves against **text scale**, not just width:
    `context.textScale` in `adaptive.dart` is the shared measurement, and `/chefs` uses it twice —
    the hero stacks its parts below `900 × textScale` px, and the whole page drops to a single
    scroll above `ChefsScreen.maxTwoColumnTextScale`. Check any new fixed-height page region at
    2.0×, the same envelope as the card (#13) and the nav bar (#18).
23. **A modal opened from a shell screen needs `useRootNavigator: true`** (B030). `AppShell` is a
    `Scaffold` that owns the bottom `NavigationBar` and the FAB **and** wraps the shell's inner
    navigator, so a default `showModalBottomSheet` / `showDialog` attaches below that chrome: the
    FAB paints over the sheet on mobile and the top nav bar stays undimmed above the dialog on web.
    No widget test sees this — tests pump the screen without the shell — so it is a screenshot
    check, not a test one. Two more things only screenshots catch: a name that **ellipsises**
    rather than overflows (B032), and copy like `1 recipes` (B031).

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

## Final response format (MANDATORY)

Every task response ends with an **executive summary** — what changed and what it means, readable
by someone who did not watch the work happen. Keep the whole thing under ~25 lines. Use this
skeleton, dropping any section that would be empty:

```markdown
## Summary

<1–3 sentences: what was asked, what is now true. Plain language, no jargon dumps.>

**Changed**

- `path/to/file.dart` — what changed and why (one line each)

**Verified**

- `melos run analyze` — SUCCESS / `melos run test --no-select` — 12 passed
- (or) not run, because <reason>
- Code review using /code-review outcomes

**Docs updated**

- `docs/ROADMAP.md` — task X marked done

**Open / next**

- <anything left undone, blocked, or assumed — say it plainly>
```

Rules for it:

- **Lead with the outcome, not the journey.** No step-by-step replay of tool calls, no narration
  of dead ends unless the dead end changes what the user should do next.
- **One line per file.** Group trivial edits (`3 test files — updated fixtures`) instead of
  listing each.
- **Verified means run.** Quote the actual command and its real result. On Windows, `melos.bat`
  exits 0 even on failure (B006/B007) — report what the output said (`SUCCESS`/`FAILED`), not the
  exit code. If nothing was run, say so; never imply a green run that did not happen.
- **State what was skipped.** Partial work, assumptions, and anything deferred go under
  _Open / next_ — omission reads as completion.
- **No praise, no filler, no "let me know if…".** Facts only.
- File references stay clickable markdown links (`[recipe_card.dart](packages/design_system/lib/src/widgets/recipe_card.dart)`),
  not backticks, per the harness rule.
- Detail belongs **above** the summary, not inside it. The summary is the last thing in the
  response and never repeats a full explanation already given.
