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
supabase db reset       # applies supabase/migrations
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

## Running

Supabase credentials are supplied via a local, git-ignored JSON file (never commit real keys).

1. Copy the template and fill in your project's values:

   ```powershell
   Copy-Item apps/app/env.example.json apps/app/env.local.json
   # then edit apps/app/env.local.json with your SUPABASE_URL and SUPABASE_ANON_KEY
   ```

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

## Seed sample recipes (Discover page)

To populate Discover with curated public recipes, run [supabase/seed.sql](supabase/seed.sql):

- **Hosted project:** open the Supabase dashboard → SQL Editor → paste the contents of
  `supabase/seed.sql` → Run. It creates a dedicated **"Secret Sauce Kitchen"** system account,
  owns the recipes with it, and is safe to re-run (idempotent by title). Re-running on an
  already-seeded database leaves recipe content alone but **does** (re)apply the star ratings, so
  it is also the way to backfill ratings after upgrading the schema.
- **Local CLI:** `supabase db reset` runs `supabase/seed.sql` automatically after migrations.

> The seed creates its own system user, so it needs no existing account and won't touch any real
> user's "My Recipes". It also creates 8 dummy **"Taster"** accounts
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
melos run format    # format code
```

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
Project Settings → Database → Connection string → URI):

```powershell
$env:SUPABASE_DB_URL = "postgresql://postgres:<pwd>@db.<ref>.supabase.co:5432/postgres"
melos run db:create   # apply schema (supabase/migrations/0001_init.sql)
melos run db:seed     # load curated recipes (supabase/seed.sql)
melos run db:clean    # truncate recipe data, keep schema + users
melos run db:drop     # drop all app tables/types/functions
melos run db:reset    # drop -> create -> seed
```

No `psql` installed? Use the Supabase CLI's local stack instead — its DB container ships one, and
it is the fastest way to test schema changes without touching the hosted project (needs Docker):

```powershell
supabase start        # local stack; prints API_URL / ANON_KEY for env.local.json
supabase db reset     # applies supabase/migrations/* then supabase/seed.sql
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
