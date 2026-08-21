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

| Tool         | Version                | Notes                                             |
| ------------ | ---------------------- | ------------------------------------------------- |
| Flutter SDK  | **3.44.8** (Dart 3.12.2) | Pinned — see [Toolchain versions](#toolchain-versions) |
| melos        | **6.x** (6.3.3)        | Must match the root `pubspec.yaml` (`^6.1.0`)     |
| Supabase CLI | any                    | Only for a *local* DB; optional if hosted         |

> **Do not just install "latest stable" Flutter.** Newer stables break codegen in this repo.
> Read [Toolchain versions](#toolchain-versions) before deviating.

## Install the Flutter SDK (Windows)

There is no Flutter package in `winget`, so install from git. Any path without spaces works;
`C:\src\flutter` is used throughout this README.

```powershell
# 1. Clone the pinned version (shallow — no full history needed)
git clone --depth 1 -b 3.44.8 https://github.com/flutter/flutter.git C:\src\flutter

# 2. Put Flutter and the pub global bin dir on your PATH (persists for your user)
$parts = [Environment]::GetEnvironmentVariable("Path","User").Split(";")
$parts += "C:\src\flutter\bin"
$parts += "$env:LOCALAPPDATA\Pub\Cache\bin"
[Environment]::SetEnvironmentVariable("Path", ($parts -join ";"), "User")

# 3. Open a NEW terminal, then trigger the first-run Dart SDK download (~600 MB)
flutter --version     # expect: Flutter 3.44.8 ... Dart 3.12.2
```

To move an existing clone to the pinned version instead:

```powershell
cd C:\src\flutter
git fetch --depth 1 origin tag 3.44.8
git checkout -f 3.44.8
flutter --version
```

> Checking out a tag puts the SDK on `channel [user-branch]`, so `flutter upgrade` will not work.
> That is intentional — change versions with `git checkout <tag>` as above.

## First-time setup

```powershell
# 1. Install melos matching the workspace constraint (^6.1.0)
dart pub global activate melos 6.3.3

# 2. Resolve + link all packages
melos bootstrap

# 3. Generate freezed / json_serializable code (runs in packages/core — the only
#    package with build_runner). --no-select skips the package picker; required
#    in any non-interactive shell.
melos run build_runner --no-select

# 4. Supply Supabase credentials (see "Running" below)
Copy-Item apps/app/env.example.json apps/app/env.local.json

# 5. Apply the database schema
supabase start          # or point at a hosted project
supabase db reset       # applies supabase/migrations, then seed.sql + seed_recipes.sql
```

Verify the setup:

```powershell
melos run analyze              # expect: "No issues found!" in core, design_system, app
melos run test --no-select     # expect: all tests passed (app, design_system)
```

> Platform runners for **web, android, ios, and windows are already committed** under
> `apps/app/`. You do **not** need `flutter create`. Only run it if you want to add a platform
> that is missing (`flutter create . --platforms=macos,linux --project-name app`) — it does not
> overwrite `lib/`.

> If `melos` isn't recognized as a command, the pub global bin dir isn't on your `PATH`. Either add
> `%LOCALAPPDATA%\Pub\Cache\bin` to `PATH`, or prefix every `melos ...` command below with
> `dart pub global run melos:` (e.g. `dart pub global run melos:melos bootstrap`).

## Toolchain versions

This repo is pinned to **Flutter 3.44.8 / Dart 3.12.2** and **melos 6.x**. Both pins are load-bearing:

- **Flutter ≤ 3.44.x is required for codegen.** `freezed ^2.5.7` and `json_serializable ^6.8.0`
  resolve to `source_gen` 2.x, which caps `analyzer` at 7.x. `analyzer` 7.x only understands
  language version 3.9 and crashes on Dart 3.13+ sources with
  `Exception: Missing implementation of visitDotShorthandPropertyAccess`. Flutter 3.47.0 ships
  Dart 3.13.0 and therefore **fails `melos run build_runner`**. Moving to a newer Flutter requires
  upgrading to `freezed` 3.x (a breaking model-syntax migration), not just bumping the SDK.
- **melos should be 6.x**, matching the root `pubspec.yaml` (`melos: ^6.1.0`). After a successful
  `melos bootstrap` the workspace-local melos 6.3.3 takes over anyway, regardless of what is
  globally activated — so a mismatched global install only matters before the first bootstrap.
- **`melos run` needs `--no-select` without a TTY.** Any script in `melos.yaml` that declares
  `packageFilters` (`test`, `build_runner`, `build:apk*`, `build:appbundle`, `build:ios`,
  `build:ipa`, `gen:icons`) makes melos prompt "Select a package to run …". In CI or any scripted
  shell that prompt aborts with `StdinException: Error getting terminal echo mode`. This is **not**
  version-specific — melos 6.3.3 does it too. `analyze` and `format` declare no filters and run
  bare. Worse, `melos.bat` still exits 0 when this happens, so a scripted run looks like it passed:

  ```powershell
  melos run analyze                  # fine — no packageFilters
  melos run test --no-select         # needed
  melos run build_runner --no-select # needed
  ```
- **`pubspec.lock` is git-ignored** (`.gitignore:7`), so dependency resolution is not reproducible
  between machines — the same commit can resolve different `analyzer` versions on different days.
  Pinning the SDK is what keeps this stable today; committing the lockfiles would make it exact.

Also verified on this machine: Windows 11 **ARM64**. Flutter 3.44.8 has no ARM64 Dart SDK and
transparently falls back to the x64 build, which works.

## Troubleshooting

| Symptom                                                                   | Cause / fix                                                                                                |
| ------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| `Missing implementation of visitDotShorthandPropertyAccess` during codegen | Flutter too new. Check out 3.44.8 (see above).                                                              |
| `StdinException: Error getting terminal echo mode` from `melos run`        | Script has `packageFilters` and there is no TTY. Add `--no-select` (note `melos.bat` still exits 0 here).   |
| `melos as globally activated doesn't support Dart <x>`                     | melos snapshot built against a different Dart. Re-run `dart pub global activate melos 6.3.3`.               |
| `Building with plugins requires symlink support` on `melos bootstrap`      | Enable Windows Developer Mode: `start ms-settings:developers`. Not needed on 3.44.8, but some versions require it. |
| `flutter` not found after install                                          | PATH only applies to **new** terminals. Open a fresh one.                                                   |
| `flutter run` starts, serves, then exits on its own (code 255)             | It is interactive (`r`/`R`/`q`) and quits on stdin EOF. Run it in a real terminal, not a backgrounded or piped one. For unattended use build instead: `flutter build web --release --dart-define-from-file=env.local.json`. |
| `-d web-server` serves a **blank white page** on the second browser session (no console error) | The debug web server renders for one client; a later load gets the bootstrap scripts and nothing else (B028). For screenshots or any automated browser, build a release bundle and serve it statically instead — see below. |
| A deep link like `http://localhost:8080/recipe/<id>` opens Discover instead   | The web build uses the **hash** URL strategy — the server never sees the path, so it serves the app at `/`, which redirects to `/discover`. Put the route after the hash: `http://localhost:8080/#/recipe/<id>`. |
| `http://localhost:8080/` shows Discover, not a landing page                   | Correct as of 2026-08-20. The landing screen was retired; `/` is a redirect-only route onto `/discover`, which is the front door on web and mobile. |

For screenshots, automated browsers, or anything that opens the app more than once:

```powershell
cd apps/app
flutter build web --release --dart-define-from-file=env.local.json
npx serve -l 8099 build/web    # then open http://localhost:8099/#/discover
```

## Running

Supabase credentials are supplied via a local, git-ignored JSON file (never commit real keys).

1. Copy the template and fill in your project's values:

   ```powershell
   Copy-Item apps/app/env.example.json apps/app/env.local.json
   # then edit apps/app/env.local.json with your SUPABASE_URL and SUPABASE_ANON_KEY
   ```

   > On this machine `env.local.json` currently points at the **local** Supabase stack
   > (`http://127.0.0.1:54321`, needs `supabase start`); the hosted project's values are kept in
   > `apps/app/env.hosted.local.json`. Swap the files to switch. Keep the `.local` in any such
   > filename — `env.local*` and `env.*.local*` are git-ignored, but `env.hosted.json` is **not**
   > (B010).

2. Run with the env file (Flutter's `--dart-define-from-file`). The most reliable option on
   Windows is the **web-server** device (open the printed URL in any browser):

   ```powershell
   cd apps/app
   flutter run -d web-server --web-port 8080 --dart-define-from-file=env.local.json
   # then open http://localhost:8080
   ```

   Other devices:

   ```powershell
   flutter run -d edge --dart-define-from-file=env.local.json      # Edge (auto-launch can be flaky)
   flutter run -d windows --dart-define-from-file=env.local.json   # native Windows desktop
   ```

   > Chrome is not installed here; Edge's debug auto-launch sometimes fails to attach — use
   > `web-server` (open the URL yourself) or `windows` if that happens.

In VS Code you can instead press **F5** and pick **"app (web · Edge)"** or
**"app (Windows desktop)"** — the launch configs already point at `env.local.json`.

> `env.local.json` is git-ignored; `env.example.json` is the committed template.

## Load recipes (Discover page)

Two SQL files, split on purpose:

| File | What it is | Lifespan |
| --- | --- | --- |
| [`supabase/seed_recipes.sql`](supabase/seed_recipes.sql) | All 14 of the Secret Sauce Kitchen's recipes. **Generated** from [`recipeData/recipes/*.json`](recipeData/) — see [recipeData/README.md](recipeData/README.md) | permanent |
| [`supabase/seed.sql`](supabase/seed.sql) | Demo fixtures: the system accounts, 8 tasters, 7 demo chefs and their recipes, and invented engagement so Discover and the leaderboard have a plausible order | delete when there is real traffic |

Both bootstrap the same "Secret Sauce Kitchen" system account with conflict guards, and both are
idempotent.

> **Apply `seed.sql` first.** Recipe *content* does not care about the order, but the demo star
> ratings do: `seed_recipes.sql` borrows `seed.sql`'s taster accounts, so run the other way round
> it creates every recipe and skips every rating (it says so, with a notice). Fix by re-running
> `seed_recipes.sql` afterwards — re-running never touches existing recipe content, but it *does*
> re-apply ratings, which is also how you backfill them after a schema upgrade.

- **Hosted project:** Supabase dashboard → SQL Editor → paste `seed.sql`, Run, then
  `seed_recipes.sql`, Run.
- **Local CLI:** `supabase db reset` applies both in order — `config.toml` lists them under
  `db.seed.sql_paths`.
- **`psql`:** `melos run db:seed` then `melos run db:recipes`, or `melos run db:reset` for
  everything.

> Editing a recipe that a database already has does **not** work by re-applying:
> `seed_recipe_v2` returns early when `(owner_id, title)` exists — it is not an upsert. Delete
> that recipe there first.

> Both files create their own system user, so they need no existing account and won't touch any
> real user's "My Recipes". `seed.sql` also creates 8 dummy **"Taster"** accounts
> (`taster1..8@secretsauce.local`) that supply the star ratings on the curated recipes, so the
> Discover → **Popular** tab (ranked by rating) has a meaningful order from the start.
>
> All 9 seed accounts get a **random, discarded password** — they exist only because
> `profiles.id` is a foreign key to `auth.users`, and nothing ever signs in as them. Never put a
> literal password in `seed.sql`: this file is meant to be run against the hosted project, so a
> committed credential is a live production credential (see B018). If you seeded a database
> *before* this change, rotate or delete those 9 accounts — re-running the seed will not fix
> them, because the insert is `on conflict (id) do nothing`.

## Quality gates

```powershell
melos run analyze   # flutter analyze across all packages
melos run test      # run tests
melos run format    # format code — see the warning below
```

> **Don't run `melos run format` casually — it breaks `melos run analyze` (B027).** `dart format`
> chooses its style from the package's language version; all four pubspecs declare
> `sdk: ">=3.4.0 <4.0.0"`, which is below the 3.7 cutoff, so the formatter rewrites the tree into
> the legacy short style and strips the trailing commas that `require_trailing_commas` requires.
> Fix is to raise the `sdk:` lower bound to `>=3.7.0` (one repo-wide reformat) or drop the lint.

## Tasks (melos)

melos is the task runner for the whole workspace (Gradle only builds Android). All tasks are
defined in [melos.yaml](melos.yaml).

> **Append `--no-select` in non-interactive shells.** Every script below that declares
> `packageFilters` in `melos.yaml` (`test`, `build_runner`, `build:*`, `gen:icons`) first prompts
> "Select a package to run …". In a real terminal just press Enter for the default (all matching
> packages); in CI or a scripted shell the prompt aborts with
> `StdinException: Error getting terminal echo mode` — and `melos.bat` still exits 0, so the
> failure is silent. `analyze` and `format` have no filters and never prompt.

Build:

```powershell
melos run build:apk         # release APK (universal)
melos run build:apk:split   # release APKs split per ABI (smaller)
melos run build:appbundle   # release .aab for Play Store
melos run build:ios         # release iOS build (macOS only, unsigned)
melos run build:ipa         # release .ipa (macOS + signing)
```

Database (require `psql` on PATH and a `SUPABASE_DB_URL` env var — Supabase dashboard →
Project Settings → Database → Connection string → URI).

Keep that URI in a **dot-sourced, git-ignored script**, not in a dart-define file (B034) and not
in a Windows user environment variable — a global value would be inherited by every other repo on
the machine, and `tool/db.dart` fires at whatever it points at with no confirmation and no prod
guard. Copy the template once:

```powershell
Copy-Item db-url.example.ps1 db-url.local.ps1   # then edit in your real URI
```

and dot-source it in each shell you run database tasks from:

```powershell
. .\db-url.local.ps1  # sets $env:SUPABASE_DB_URL for THIS shell only
melos run db:create   # apply schema (supabase/migrations/0001_init.sql)
melos run db:seed     # load demo chefs/tasters/ratings (supabase/seed.sql)
melos run db:recipes  # load authored recipes (supabase/seed_recipes.sql)
melos run db:clean    # truncate recipe data, keep schema + users
melos run db:drop     # drop all app tables/types/functions
melos run db:reset    # drop -> create -> seed -> recipes
```

**No `psql` installed? Use the Supabase container's, and go through the pooler** (B033). The
`db:*` scripts shell out to `psql`; if it is not on PATH the only client on a Docker-based setup is
inside the local stack's DB container. Reaching the **hosted** project from there needs the
**Session pooler** host as well — `db.<ref>.supabase.co` is IPv6-only and the container has no IPv6
route, so it fails with `Network is unreachable`:

```powershell
# Session pooler URI: Dashboard -> Project Settings -> Database -> Connection string -> Session pooler
$u = "postgresql://postgres.<project-ref>:<pwd>@aws-0-<region>.pooler.supabase.com:5432/postgres"
docker exec -i supabase_db_secret-sauce psql $u -c "select 1"        # check auth first
Get-Content supabase\migrations\0001_init.sql -Raw |
  docker exec -i supabase_db_secret-sauce psql $u -v ON_ERROR_STOP=1 -f -
```

The pooler user is `postgres.<project-ref>`, **not** bare `postgres`, and a dashboard password
reset takes a moment to propagate — an auth failure straight after resetting is not proof the
password is wrong.

> ⚠️ `SUPABASE_DB_URL` is a **superuser** connection string and belongs in your shell only. Never
> put it in `apps/app/env.local.json` **or any other dart-define file**: those are passed to every
> build through `--dart-define-from-file`, so a credential in one is one `String.fromEnvironment`
> away from shipping inside a web bundle (B034). `.gitignore` covers `*.local.ps1` for exactly
> this purpose, and a `.ps1` cannot be handed to `--dart-define-from-file` by accident.

Recipe content (no database or credentials needed — these only touch files):

```powershell
melos run recipes:validate  # parse + lint recipeData/recipes/*.json
melos run recipes:gen       # regenerate supabase/seed_recipes.sql — commit both
melos run recipes:check     # fail if that .sql is stale (CI runs this)
```

The simulation **dish library** (`simData/dishes/*.json`) works the same way and is validated by
the same code, so a dish can be promoted into the Kitchen's curated set by moving the file. Nothing
in it becomes a recipe on its own — the generator that draws from it is not built yet
([docs/ROADMAP.md Phase 24](docs/ROADMAP.md)):

```powershell
melos run sim:validate      # parse + lint + directory coverage rules
melos run sim:gen           # regenerate supabase/sim/1_sim_dishes.sql — commit both
melos run sim:check         # fail if that .sql is stale (CI runs this)
```

Building the simulated population itself needs a database. It is part of `db:reset`, so the usual
reset brings everything back:

```powershell
melos run db:reset                          # drop -> create -> seed -> recipes -> sim (~15s)
melos run db:sim                            # just the sim: schema -> dishes -> generate -> verify
melos run db:sim -- --preset=small --seed=7 # tiny | small | medium (default) | large
melos run db:sim:verify                     # 39 assertions, read-only
melos run db:sim:clean -- --yes             # DESTRUCTIVE: removes the simulated accounts
```

At the default `medium` preset that is 1,000 simulated accounts, ~1,670 recipes and ~118k view
rows, generated in about ten seconds. It is additive and idempotent — running it twice changes
nothing. `db:sim:clean` deletes rows from `auth.users`, which has no undo, so it refuses to run
without `--yes`; it removes only what the `sim.actor` / `sim.recipe` registries list, never
anything matched by an email or id pattern.

> The simulated users engage only with simulated recipes (`sim.config.engage_existing` is `false`),
> so the Kitchen's 14 recipes and the `d1`–`d7` demo chefs keep the exact counters and scores
> documented in [docs/SDS.md §10.7](docs/SDS.md). Their **ranks** move once 1,000 more accounts
> exist, which is the point of having them.

No `psql` installed? Use the Supabase CLI's local stack instead — its DB container ships one, and
it is the fastest way to test schema changes without touching the hosted project (needs Docker):

```powershell
supabase start        # local stack; prints API_URL / ANON_KEY for env.local.json
supabase db reset     # applies supabase/migrations/*, then seed.sql + seed_recipes.sql
docker exec supabase_db_secret-sauce psql -U postgres -d postgres -c "select title, rating_avg from recipes_popular(6);"
supabase stop         # tear the containers down
```

Icons: `melos run gen:icons` (see below).

## Build & release (Android)

```powershell
melos run build:apk         # -> apps/app/build/app/outputs/flutter-apk/app-release.apk (~53 MB)
melos run build:apk:split   # per-ABI APKs (arm64 is ~20 MB) under the same folder
melos run build:appbundle   # -> ...outputs/bundle/release/app-release.aab (Play Store)
```

Install the APK on a phone:

- **Copy & sideload:** transfer `app-release.apk` (USB / Drive / chat) → tap it → allow
  "Install from unknown sources" → open **Secret-Sauce**.
- **Over USB** (enable Developer options → USB debugging first):

  ```powershell
  cd apps/app
  flutter install --release --dart-define-from-file=env.local.json
  ```

The release build points at your hosted Supabase, so it works on any network. Two Android
settings are already configured for this to work:

- **INTERNET permission** in [AndroidManifest.xml](apps/app/android/app/src/main/AndroidManifest.xml)
  — Flutter omits it from release builds, which would otherwise block Supabase.
- **`path_provider_android` pinned to `>=2.2.0 <2.3.0`** in
  [apps/app/pubspec_overrides.yaml](apps/app/pubspec_overrides.yaml) — 2.3.x switched to a
  JNI/CMake native build that requires downloading the Android CMake package at build time.
  Re-add this line if it disappears after `melos bootstrap`.

> iOS (`build:ios` / `build:ipa`) requires macOS with the Xcode toolchain.

## App name & launcher icon

App display name:

- **Android:** `android:label` in [android/app/src/main/AndroidManifest.xml](apps/app/android/app/src/main/AndroidManifest.xml) — set to `Secret-Sauce`.
- **iOS:** `CFBundleDisplayName` in [ios/Runner/Info.plist](apps/app/ios/Runner/Info.plist) — set to `Secret-Sauce`.

Launcher icon (uses `flutter_launcher_icons`):

1. Drop a 1024×1024 PNG at `apps/app/assets/icon/app_icon.png`.
2. Run `melos run gen:icons` (config is in [apps/app/pubspec.yaml](apps/app/pubspec.yaml) under
   `flutter_launcher_icons`). This generates Android, iOS, web, and Windows icons.
3. For an Android adaptive icon, add `app_icon_foreground.png` and uncomment the
   `adaptive_icon_*` lines in that config.

## Docs–code sync

Every change updates the relevant docs in `docs/` in the same commit. See the rule in
[CLAUDE.md](./CLAUDE.md#docscode-sync-mandatory).
