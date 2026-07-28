# CLAUDE.md — Secret-Sauce

Guidance for AI assistants (and humans) working in this repository. Read this first.

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
| State management | **Riverpod** (+ `riverpod_generator`)                               |
| Models           | **freezed** + **json_serializable**                                 |
| Routing          | **go_router** (responsive shell)                                    |
| Backend          | **Supabase** — Postgres, Auth, Storage, Row-Level Security          |
| Monorepo         | **melos** (Dart workspaces)                                         |
| Images           | `cached_network_image`, `image_picker`                              |

There is **one** app entry point. Web vs mobile differences are handled by **responsive
layouts**, not separate apps.

## Repository layout

```
secret-sauce/
├── CLAUDE.md                  # you are here
├── docs/                      # kept in sync with code — see "Docs–code sync" below
│   ├── ROADMAP.md             # all tasks, grouped by phase, with status
│   ├── EXECUTION-PLAN.md      # per-task execution detail + acceptance criteria
│   ├── SDS.md                 # Software Design Spec (architecture, data model, RLS, screens)
│   └── BUG-TRACKER.md         # bug log
├── melos.yaml                 # monorepo config
├── pubspec.yaml               # workspace root
├── packages/
│   ├── core/                  # "platform" shared core: models, repositories, services
│   │   └── lib/
│   │       ├── models/        # Recipe, Ingredient, Step, RecipeVersion, Profile, ...
│   │       ├── repositories/  # abstract contracts + Supabase implementations
│   │       ├── services/      # supabase client, auth, storage
│   │       └── utils/
│   └── design_system/         # shared UI: theme, RecipeCard, adaptive widgets
│       └── lib/
├── apps/
│   └── app/                   # the Flutter application
│       └── lib/
│           ├── features/      # auth, home, discover, my_recipes, recipe_detail,
│           │                  # recipe_editor, profile
│           ├── routing/       # go_router + responsive shell
│           └── main.dart
└── supabase/
    └── migrations/            # SQL schema + RLS policies
```

**"platform (shared core)"** = `packages/core` + `packages/design_system`.
**mobile/web** = handled inside `apps/app` via responsive layouts.

## Architecture

Feature-first inside `apps/app`; layered inside `packages/core`:

```
UI (features/*, design_system)
   → Controllers/Providers (Riverpod)
      → Repositories (abstract, in core)
         → Supabase services (Postgres/Auth/Storage)
```

- UI never talks to Supabase directly — always through a repository.
- Repositories are defined as abstract contracts in `core/repositories` with Supabase-backed
  implementations, so they can be mocked in tests.
- Models are immutable (`freezed`) with JSON (de)serialization matching the Postgres schema.

## Common commands

> Requires the Flutter SDK (with Dart) and the `melos` global package. Install Flutter first.

```powershell
dart pub global activate melos      # once
melos bootstrap                     # resolve + link all packages
melos run analyze                   # flutter analyze across all packages
melos run test                      # run all tests
melos run build_runner              # codegen (freezed/json/riverpod)
flutter run -d chrome               # run the app on web
flutter run                         # run on connected mobile device/emulator
```

> Supabase credentials are read from `apps/app/env.local.json` (git-ignored) via
> `--dart-define-from-file=env.local.json`. Copy `apps/app/env.example.json` to start. The
> VS Code launch configs already wire this file.

Supabase (local dev):

```powershell
supabase start                      # local stack
supabase db reset                   # apply migrations in supabase/migrations
```

## Conventions

- **Codegen**: after editing any `freezed`/`json`/`riverpod` annotated file, run
  `melos run build_runner`. Never hand-edit generated `*.g.dart` / `*.freezed.dart`.
- **Naming**: files `snake_case.dart`; types `PascalCase`; providers end in `Provider`.
- **Imports**: use package imports (`package:core/...`) across packages, relative within a package.
- **Enums** mirror Postgres enums exactly (`difficulty`, `visibility`).
- **No secrets in the repo.** Supabase URL/anon key come from `apps/app/env.local.json`
  (git-ignored) via `--dart-define-from-file`, not source.
- **Security**: never trust client for authorization — enforce via Supabase **RLS**. Client checks
  are UX only.

## Docs–code sync (MANDATORY)

Documentation and code must always be in sync. For **every** change:

1. Update `docs/ROADMAP.md` task status (`[ ]` → `[x]`, or add new tasks).
2. If behavior/architecture/schema changed, update `docs/SDS.md`.
3. If you implemented a roadmap task, ensure `docs/EXECUTION-PLAN.md` reflects reality.
4. Any bug found or fixed goes into `docs/BUG-TRACKER.md`.

A change is **not complete** until the relevant docs are updated in the same commit/change set.

## Recipe data model (the crucial part)

See `docs/SDS.md` for the full spec. Summary: a `recipe` has grouped `ingredients` and grouped
ordered `steps`; each edit produces a `recipe_version` snapshot (git-like); forking copies a
recipe and records `forked_from_recipe_id` + `forked_from_version_id`. A `recipe_suggestions`
table is reserved (stub) for a future "suggest changes upstream" (PR-like) flow.
