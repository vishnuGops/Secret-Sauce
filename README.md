# Secret-Sauce

A cross-platform **recipe vault** — document, structure, and share cooking recipes with
git-like **forking** and **version history** to preserve legacy recipes. Built with **Flutter**
(single adaptive codebase for web + mobile) and **Supabase** (Postgres, Auth, Storage, RLS).

> Start with [CLAUDE.md](./CLAUDE.md) for architecture and conventions, and [docs/](./docs) for
> the roadmap, execution plan, design spec, and bug tracker.

## Structure

```
packages/core           # shared platform core: models, repositories, services
packages/design_system  # shared UI: theme, RecipeCard, adaptive widgets
apps/app                # the Flutter application (adaptive web + mobile)
supabase/migrations     # SQL schema + RLS + storage
docs/                   # ROADMAP · EXECUTION-PLAN · SDS · BUG-TRACKER
```

## Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable) with Dart.
- `dart pub global activate melos`
- [Supabase CLI](https://supabase.com/docs/guides/cli) (for local DB) or a hosted Supabase project.

## First-time setup

```powershell
# 1. Resolve all packages
melos bootstrap

# 2. Generate freezed / json / riverpod code
melos run build_runner

# 3. Generate platform runners for the app (does not overwrite lib/)
cd apps/app
flutter create . --platforms=web,android,ios --project-name app
cd ../..

# 4. Apply the database schema
supabase start          # or point at a hosted project
supabase db reset       # applies supabase/migrations
```

## Running

Supabase credentials are supplied via a local, git-ignored JSON file (never commit real keys).

1. Copy the template and fill in your project's values:

   ```powershell
   Copy-Item apps/app/env.example.json apps/app/env.local.json
   # then edit apps/app/env.local.json with your SUPABASE_URL and SUPABASE_ANON_KEY
   ```

2. Run with the env file (Flutter's `--dart-define-from-file`):

   ```powershell
   cd apps/app
   flutter run -d edge --dart-define-from-file=env.local.json
   # or on Windows desktop:  flutter run -d windows --dart-define-from-file=env.local.json
   ```

In VS Code you can instead press **F5** and pick **"app (web · Edge)"** or
**"app (Windows desktop)"** — the launch configs already point at `env.local.json`.

> `env.local.json` is git-ignored; `env.example.json` is the committed template.

## Quality gates

```powershell
melos run analyze   # flutter analyze across all packages
melos run test      # run tests
melos run format    # format code
```

## Docs–code sync

Every change updates the relevant docs in `docs/` in the same commit. See the rule in
[CLAUDE.md](./CLAUDE.md#docscode-sync-mandatory).
