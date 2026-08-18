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

> If `melos` isn't recognized as a command, the pub global bin dir isn't on your `PATH`. Either add
> `%LOCALAPPDATA%\Pub\Cache\bin` to `PATH`, or prefix every `melos ...` command below with
> `dart pub global run melos:` (e.g. `dart pub global run melos:melos bootstrap`).

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
  owns the recipes with it, and is safe to re-run (idempotent by title).
- **Local CLI:** `supabase db reset` runs `supabase/seed.sql` automatically after migrations.

> The seed creates its own system user, so it needs no existing account and won't touch any real
> user's "My Recipes".

## Quality gates

```powershell
melos run analyze   # flutter analyze across all packages
melos run test      # run tests
melos run format    # format code
```

## Tasks (melos)

melos is the task runner for the whole workspace (Gradle only builds Android). All tasks are
defined in [melos.yaml](melos.yaml):

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
