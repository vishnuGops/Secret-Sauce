# BUG-TRACKER — Secret-Sauce

Tracks all bugs found or fixed. Update in the same change that discovers/fixes a bug
(see "Docs–code sync" in [CLAUDE.md](../CLAUDE.md)).

Severity: `blocker` \| `high` \| `medium` \| `low`
Status: `open` \| `in-progress` \| `fixed` \| `wontfix`

| ID   | Date       | Severity | Area          | Description                                                                  | Status | Fix / Commit                                                                      |
| ---- | ---------- | -------- | ------------- | ---------------------------------------------------------------------------- | ------ | --------------------------------------------------------------------------------- | --- | ---- | ---------- | ---- | ------------- | --------------------------------------------------------------------------------------------------------------------------- | ----- | ----------------------------------------------------------------------------------------------------------------------- |
| B001 | 2026-07-28 | low      | design_system | `RecipeCard` `RenderFlex` overflow when given unbounded height (test only).  | fixed  | Test constrains card to a 320px-wide box, matching real grid usage.               |
| B002 | 2026-07-28 | low      | home          | Feature-card grid overflowed inside the 900px content column (fixed aspect). | fixed  | Switched grid to `mainAxisExtent: 132` and clamped card text (maxLines/ellipsis). |
| B003 | 2026-07-28 | medium   | recipe_editor | New/Edit recipe screen had no back or cancel affordance (reached via `go`).  | fixed  | Added a Cancel (×) `leading` button with a discard-confirmation dialog.           |     | B004 | 2026-07-28 | high | android build | Release APK build failed: `path_provider_android` 2.3.x pulls a JNI/CMake native build; Android CMake download was blocked. | fixed | Pinned `path_provider_android` to `>=2.2.0 <2.3.0` (pre-JNI) via `pubspec_overrides.yaml`; added `INTERNET` permission. |

### Toolchain / setup bugs (found while re-provisioning the dev environment, 2026-08-18)

| ID   | Date       | Severity | Area     | Description                                                                                                                                                                  | Status  | Fix / Commit                                                                                                                          |
| ---- | ---------- | -------- | -------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| B005 | 2026-08-18 | blocker  | codegen  | `melos run build_runner` crashes on Flutter 3.47.0 / Dart 3.13.0: `Exception: Missing implementation of visitDotShorthandPropertyAccess`. `freezed` 2.x → `source_gen` 2.x caps `analyzer` at 7.x, which only understands language 3.9. Hits `freezed` **and** `riverpod_generator`. | fixed   | Pinned the SDK to Flutter 3.44.8 / Dart 3.12.2. Permanent fix is migrating to `freezed` 3.x (breaking model syntax) — not done.        |
| B006 | 2026-08-18 | high     | tooling  | Any `melos run <script>` whose script declares `packageFilters` (`test`, `build_runner`, `build:*`, `gen:icons`) prompts "Select a package to run …". With no TTY it aborts with `StdinException: Error getting terminal echo mode`, so CI/scripted runs fail. Not version-specific — melos 6.3.3 and 8.3.0 both do it. `analyze`/`format` declare no filters and are unaffected. | fixed   | Pass `--no-select`. Added to `README.md`, `CLAUDE.md`, and `.github/workflows/ci.yml`. Compounded by B007's silent exit-0.            |
| B007 | 2026-08-18 | medium   | tooling  | `melos.bat` exits 0 even when melos itself crashed — seen both with `Can't load Kernel binary: Invalid kernel binary format version` (snapshot built against a different Dart, after an SDK switch) and with the B006 prompt abort. Scripted runs therefore report success on failure. | fixed   | Re-run `dart pub global activate melos 6.3.3` after any Flutter/Dart change. Do not trust melos exit codes in scripts — grep output for `SUCCESS`/`FAILED`. |
| B008 | 2026-08-18 | medium   | build    | `GridView.count(mainAxisExtent:)` (B002's fix) does not exist on Flutter ≤ 3.35.x, so the app fails to compile there: `The named parameter 'mainAxisExtent' isn't defined`.   | wontfix | Not an issue on the pinned 3.44.8. If an older SDK is ever needed, use `GridView.builder` + `SliverGridDelegateWithFixedCrossAxisCount`, which has had `mainAxisExtent` since Flutter 2.0. |
| B009 | 2026-08-18 | medium   | tooling  | `pubspec.lock` is git-ignored (`.gitignore:7`), so dependency resolution is not reproducible — the same commit resolves different `analyzer`/`freezed` versions on different machines and dates. This is the root cause behind B005 appearing "suddenly". | open    | Consider committing `pubspec.lock` for the app + packages so resolution is exact.                                                      |
| B010 | 2026-08-18 | high     | security | `.gitignore` matched only `**/env.local.json`. A credentials file saved as `apps/app/env.local` (no extension) held live `SUPABASE_URL` / `SUPABASE_ANON_KEY` but was **not** ignored, so it was one `git add -A` away from being committed. It also silently did nothing, since `--dart-define-from-file` reads `env.local.json`. | fixed   | Broadened to extension-less globs `env.local*` / `**/env.local*` / `**/env.*.local*`, with `!**/env.example.json` to keep the template tracked. Verified the file was never staged or committed. |

### Schema / RLS bugs (found while adding ratings, 2026-08-18)

| ID   | Date       | Severity | Area   | Description                                                                                                                                                                                                                                                                                          | Status | Fix / Commit                                                                                                                                                                                     |
| ---- | ---------- | -------- | ------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| B011 | 2026-08-18 | high     | schema | Counter triggers ran with **invoker** rights, but `recipes_update` (RLS) only allows `owner_id = auth.uid()`. So liking/saving another user's recipe updated **0 rows** — silently, with no error — and `like_count` / `save_count` stayed at 0 for everyone except the owner. The new rating aggregate would have had the same hole. | fixed  | `on_like_change`, `on_save_change`, `on_rating_change` are now `security definer set search_path = public`. `bump_count` / `recompute_recipe_rating` stay invoker-rights with EXECUTE revoked from `public`, `anon`, `authenticated` so they are not callable as PostgREST RPCs. |
| B013 | 2026-08-18 | blocker  | schema | The schema granted nothing to the PostgREST roles, relying on Supabase's legacy "grant all on new tables to anon/authenticated" defaults. Current Supabase images only default to `Dxt` (TRUNCATE/REFERENCES/TRIGGER), so on a freshly provisioned project (and on `supabase db reset` locally) **every** API call failed with `permission denied for table recipes`. The existing hosted project works only because it predates that change. | fixed  | Added an explicit grants block to `0001_init.sql`: `usage` on schema `public` + `select` to `anon`/`authenticated`, DML to `authenticated`, `insert on recipe_views` to `anon`. Guarded on the `anon` role existing so plain Postgres still applies. RLS still filters rows. |
| B014 | 2026-08-18 | high     | seed   | `seed_recipe()` returned early when a recipe with that title already existed, so re-running `seed.sql` on an **already-seeded** database skipped the new rating inserts entirely. Symptom: schema applied fine, `rating_avg`/`rating_count` stayed `0` for every curated recipe, and the UI correctly rendered "no ratings" — looking like the feature was missing. | fixed  | Rating insertion moved into `seed_ratings(recipe, ratings)`; the early-return path now calls it before returning, so a re-run backfills ratings without touching existing content. Verified by deleting all `recipe_ratings` locally and re-running the seed. |
| B015 | 2026-08-18 | high     | schema | A signed-in user with an `auth.users` row but **no `profiles` row** could not rate, save, or even open a recipe: every FK into `profiles` failed with `23503 … Key is not present in table "profiles"` (seen on `recipe_ratings_user_id_fkey` and `recipe_views_user_id_fkey`). Happens to accounts created before the `profiles` table/trigger existed, and to every account after a `db:drop` — that drops `profiles` while `auth.users` survives, and `on_auth_user_created` only fires on **insert**, so the row is never rebuilt. | fixed  | `0001_init.sql` now backfills `profiles` from `auth.users` for any missing id (idempotent, runs on every apply), and `handle_new_user()` inserts `on conflict (id) do nothing` so a stale profile can't fail a signup. Reproduced locally with a profile-less user, then verified view + rating both succeed after the backfill. |
| B012 | 2026-08-18 | medium   | schema | `recipes.view_count` was never incremented — `logView()` inserts into `recipe_views`, but no trigger rolled that up. `recipes_trending` scores on `like_count + view_count`, so trending was effectively likes-only (seeded recipes looked fine because the seed writes `view_count` directly). Fixing it naively would have been worse: `recipe_views` has no unique constraint and `anon` holds `insert` on it, so a `+1 per row` trigger would have let an unauthenticated refresh loop inflate trending without limit. A second hole surfaced on the way: `views_insert`'s `with check` verified only `can_read_recipe(recipe_id)`, never `user_id`, so any client could attribute views to another user. | fixed  | Added `on_view_insert()` (`security definer set search_path = public`, per B011) counting **distinct signed-in viewers**: it skips null-`user_id` rows and any row where that user already has one for the recipe, backed by `recipe_views_recipe_user_idx`. No unique constraint on purpose — PostgREST cannot express `on conflict` inference against a partial index, so a duplicate would surface to the client as `23505`; deduping in the trigger keeps `logView()` a plain insert and keeps the full log. The probe is a read-then-write, so it takes a per-(recipe, user) `pg_advisory_xact_lock` — without it two concurrent first-views from one account each miss the other's uncommitted row and both bump (reproduced: 940 → 942). `views_insert` tightened to `user_id is null or user_id = auth.uid()`. `on_view_insert` added to `drop.sql`; the now-redundant `recipe_views_recipe_idx` dropped. Note `view_count` is **monotonic** — `user_id` is `on delete set null` and nothing decrements, so it is an upper bound on distinct viewers, not an exact count. Verified on the local stack — see the 2026-08-18 view-count run below. |

### UI bugs (found reviewing the ratings change, 2026-08-18)

| ID   | Date       | Severity | Area          | Description                                                                                                                                                                                                                                                                            | Status | Fix / Commit                                                                                                                                                                                                                          |
| ---- | ---------- | -------- | ------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| B016 | 2026-08-18 | medium   | design_system | `RecipeCard`'s metadata row had no flexible child, so adding `RatingPill` overflowed it (`RenderFlex overflowed by 73 pixels`) on a rated recipe with a long time label — e.g. "12h 45m" + "4.5 (1250)" at the 276px 2-column card width. Same class as B001/B002. Worst at large text scale. | fixed  | Metadata group wrapped in `Expanded`; time label, `RatingPill` (both texts), and `DifficultyBadge` label now `Flexible` + ellipsis. Regression tests cover 276/320px at 1.0x and 2.0x text scale.                                       |
| B018 | 2026-08-18 | high     | seed / security | `seed.sql` created the 8 "taster" accounts and the "Secret Sauce Kitchen" account with **literal passwords written into the file** (`crypt('<literal>', gen_salt('bf'))`, redacted here — the kitchen one is recoverable from history before this fix) and `email_confirmed_at` pre-set. `README.md` documents pasting `seed.sql` into the **hosted** dashboard SQL Editor, so following the project's own instructions created 9 confirmed, log-in-able production accounts whose credentials were committed to the repo. `authenticated`-tier access: rate recipes, create spam recipes, like/save. `drop.sql` spares `auth.users`, so `db:reset` could not remove them. | fixed  | Both now use `crypt(gen_random_uuid()::text, gen_salt('bf'))` — nothing ever signs in as them; they exist only because `profiles.id` FKs `auth.users`. Verified on the local stack: seed applies, 6 recipes / 41 ratings / 9 users, both old passwords authenticate 0 rows, re-run still idempotent. **Any already-seeded database keeps the old hashes** (`on conflict (id) do nothing`) — rotate or delete those 9 accounts manually. |
| B017 | 2026-08-18 | medium   | design_system | `StarRatingInput` kept a stale preview after a cancelled gesture: press a star, hold past the tap deadline, then scroll — the enclosing `ListView` claims the gesture, `onTapUp`/`onHorizontalDragEnd` never fire, so `onChangeEnd` never fires but `_preview` stays set. The stars then show an unsaved rating that `didUpdateWidget` cannot clear, because `value` never changed. | fixed  | Added `onTapCancel` / `onHorizontalDragCancel` → `_cancel()`, which drops `_preview` and re-emits `value`. Regression test drives press-hold-scroll inside a `ListView`.                                                                 |

### Data-ordering bugs (found planning the chefs/leaderboard feature, 2026-08-18)

| ID   | Date       | Severity | Area | Description | Status | Fix / Commit |
| ---- | ---------- | -------- | ---- | ----------- | ------ | ------------ |
| B022 | 2026-08-18 | high     | core | Recipe steps (and ingredients, and both group lists) render in **reverse order** — the last step shows first. Root cause: postgrest-dart's `.order(column)` defaults to `ascending: false`, and the four nested-content fetches in `SupabaseRecipeRepository._fetchIngredientGroups` / `_fetchStepGroups` ([recipe_repository.dart:273-315](../packages/core/lib/src/repositories/recipe_repository.dart)) omit `ascending: true` — so `ingredient_groups`, `ingredients`, `step_groups`, and `steps` all come back descending. Every other `.order()` in the repo passes `ascending: false` explicitly and is correct. **Secondary damage:** `update()` round-trips through `getById()` — the editor loads the reversed list, and `_persistContent` re-indexes it `0..n` on save, so the **stored** order flips on every edit. A recipe edited an odd number of times has reversed rows in the DB (and then *displays* correctly under the current bug — double reversal). `_appendVersion` snapshots via `getById()` too, so `content_snapshot` list order is also unreliable for edited recipes. Seeded recipes are unaffected in storage (`seed.sql` writes ascending SQL directly and they are never edited). | fixed | `ascending: true` added to all four call sites in `_fetchIngredientGroups` / `_fetchStepGroups`, with a comment naming the postgrest-dart default so it is not "cleaned up" later. Verified on the local stack in both directions — see the B022 verification run below. **Stored-order audit: nothing to repair.** All 6 recipes on the hosted project have exactly one `recipe_versions` row (`version_number = 1`, `'Seeded recipe'`), so no recipe has ever been saved through the editor and no persisted order was ever flipped. (`updated_at` on those rows has moved, but that is `recipes_touch` firing for the rating/counter triggers, not an edit.) **Residual gap:** the project's one real account (`Vishnu`, created 2026-08-18) may own private recipes, which are not readable with the anon key — if any were created *and* edited before this fix, check them by hand. |

### Documentation bugs (found auditing `CLAUDE.md` against the code, 2026-08-18)

| ID   | Date       | Severity | Area | Description                                                                                                                                                                                                                                                                                                                                                                                                       | Status | Fix / Commit                                                                                                                                                                                                                                                                                       |
| ---- | ---------- | -------- | ---- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| B019 | 2026-08-18 | medium   | docs | `CLAUDE.md` "Conventions" said imports are "relative within a package", but `analysis_options.yaml` enables `always_use_package_imports` — every in-package import in `core` is `package:core/src/...`. Following the documented rule produces code that fails `melos run analyze`. Same section also listed the Postgres enum as `visibility` (real name: `recipe_visibility`) and named only 2 of the 4 enums.       | fixed  | `CLAUDE.md` now states package imports everywhere, lists all four enums, and links `enums.dart`.                                                                                                                                                                                                    |
| B020 | 2026-08-18 | medium   | docs | `CLAUDE.md`'s repository tree omitted the `src/` layer — it showed `packages/core/lib/models/`, but the real path is `packages/core/lib/src/models/`. It also claimed a `core/lib/utils/` directory that does not exist, and omitted `tool/`, `supabase/seed.sql`, `supabase/scripts/`, `.github/workflows/`, `.claude/skills/`, `apps/app/lib/widgets/`, and both `test/` directories. Same drift in `EXECUTION-PLAN.md` Phases 3–4. | fixed  | `CLAUDE.md` tree corrected and annotated; `docs/EXECUTION-PLAN.md` Phases 3 and 4 updated to the real `lib/src/...` paths. `docs/SDS.md` §2's layer table still uses loose non-`src/` paths (`packages/core/repositories`) — descriptive, left as is.                                              |
| B021 | 2026-08-18 | low      | docs | `CLAUDE.md` advertised Riverpod "+ `riverpod_generator`". The generator was a dev dependency in `core` and `app`, but **no `@riverpod` annotation existed anywhere** — every provider is hand-written. An agent reading this would add annotated providers, splitting the codebase across two provider styles.                                                                                                          | fixed  | Documented as hand-written-providers-only, and the unused `riverpod_annotation` / `riverpod_generator` deps were removed from both `packages/core` and `apps/app`. `apps/app` also lost `build_runner` — it had no annotated sources, so all codegen now runs in `packages/core` alone. Re-verified: bootstrap, build_runner (21 outputs, core only), analyze (clean ×3), test (13 passing). |

---

### Schema verification run (2026-08-18, local Supabase stack)

`supabase start` + `supabase db reset` against the local stack (Docker images already cached),
then RLS behavior exercised with `set local role` / `request.jwt.claims`:

| Check                                                       | Result                                        |
| ----------------------------------------------------------- | --------------------------------------------- |
| `0001_init.sql` + `seed.sql` apply cleanly                  | pass (no errors; 6 recipes seeded)            |
| Rating aggregates from seed                                 | pass — e.g. cookies 4.88/8, guacamole 4.50/3  |
| `recipes_popular()` order                                   | pass — descending weighted score              |
| Non-owner likes a recipe (B011)                             | pass — `like_count` 128 → 129                 |
| Non-owner rates + re-rates (upsert)                         | pass — avg 4.69 → 4.44, count unchanged at 8  |
| Removing a rating                                           | pass — avg 4.64, count 7                      |
| Owner rating own recipe                                     | rejected by RLS ✔                             |
| Rating `4.3` / `0`                                          | rejected by check constraint ✔                |
| Anonymous rating                                            | `permission denied` ✔                         |
| Private recipe: other user / anon                           | invisible; visible after `recipe_shares` row ✔ |
| Recipe flipped to `public`                                  | anon can read ✔                               |
| PostgREST `/rpc/recipes_popular` as `anon`                  | pass — `rating_avg` is a JSON number          |

The hosted project still needs the updated `0001_init.sql` re-applied (idempotent) to pick up
`recipe_ratings`, the B011 `security definer` fix, and the B013 grants.

### View-count verification run (2026-08-18, local Supabase stack)

`supabase start` + `supabase db reset`, then the B012 trigger exercised via `set local role` /
`request.jwt.claims` against a seeded recipe (baseline `view_count` 3050):

| Check                                                        | Result                                     |
| ------------------------------------------------------------ | ------------------------------------------ |
| Signed-in non-owner logs a first view                        | pass — 3050 → 3051                         |
| Same user re-views 5× (refresh loop)                         | pass — unchanged at 3051                   |
| A second distinct signed-in user                             | pass — 3051 → 3052                         |
| Anonymous views ×20 (`user_id is null`, role `anon`)         | pass — inserted, counter unchanged at 3052 |
| User forging a view as another `user_id`                     | `new row violates row-level security policy for table "recipe_views"` ✔ |
| Log vs. counter after the run                                | 27 rows / 2 distinct users → counter +2 ✔  |
| `0001_init.sql` re-applied on top                            | exit 0, `view_count` unchanged (idempotent) |
| `recipes_trending()` / `recipes_popular()` after the change  | pass — both still ordered correctly        |
| **Two concurrent first-views, one account** (overlapping transactions) | pass — 2100 → 2101, 2 log rows, 1 bump |
| Same race with `pg_advisory_xact_lock` removed (control)     | 940 → **942** — confirms the race is real and the lock is what prevents it |
| `recipe_views` index topology after re-apply                 | `recipe_views_pkey`, `recipe_views_recipe_user_idx` (redundant `recipe_views_recipe_idx` dropped) |

### B022 verification run (2026-08-18, local Supabase stack)

`supabase start`, then a fixture recipe written directly into the DB in known-ascending order
(2 ingredient groups / 5 ingredients, 2 step groups / 6 steps) and a local-only account owning it
so `update()` was reachable. A throwaway harness under `apps/app/test/` (**not committed** — it
needs a live database and CI has no DB job) drove the real `SupabaseRecipeRepository`.

Chrome is not installed on this machine, so the browser eyeball-check was replaced by this
harness, which exercises the same code path the screen does and asserts stored order too.

| Check                                                                        | Result                                          |
| ---------------------------------------------------------------------------- | ----------------------------------------------- |
| `.order()` default in postgrest 2.9.1 (`postgrest_transform_builder.dart`)   | `bool ascending = false` — root cause confirmed  |
| Raw PostgREST `order=sort_order.desc` vs `.asc` on the fixture               | `SG-B, SG-A` / `step-b3…` vs `SG-A, SG-B` / `step-a1…` |
| `getById()` group + step + ingredient order, with the fix                    | pass — `SG-A, SG-B`, steps `a1→b3`, ingredients `a1→b2` |
| `update()` ×1 — returned model **and** stored `sort_order`/`step_order`      | pass — unchanged                                |
| `update()` ×2 — same checks again (catches the flip-flop)                    | pass — unchanged                                |
| **Control:** same harness with the four `ascending: true` flags removed      | **fails** — `['SG-B', 'SG-A']`; the check is not vacuous |
| `melos run analyze` (core, design_system, app)                               | clean ×3                                        |
| Hosted audit: `recipe_versions` per recipe                                   | 6 recipes, all `v1 'Seeded recipe'` — never app-edited |

## Known environment limitations (not bugs)

- **Verified 2026-08-18** on Flutter 3.44.8 / Dart 3.12.2 (SDK at `C:\src\flutter`, melos 6.3.3):
  `melos bootstrap`, `melos run build_runner` (21 outputs), `melos run analyze` (clean in all three
  packages), `melos run test` (all passed), and `flutter build web --release` all succeed.
- Host is Windows 11 **ARM64**; Flutter 3.44.8 has no ARM64 Dart SDK and falls back to x64. Works.
- Windows **Developer Mode** is off on this machine. Flutter 3.44.8 bootstraps fine without it, but
  some Flutter versions fail with `Building with plugins requires symlink support` — enable it via
  `start ms-settings:developers` if that appears.
- **Runtime verified 2026-08-18** with real credentials in `apps/app/env.local.json`:
  `flutter run -d web-server --web-port 8080 --dart-define-from-file=env.local.json` serves the app
  (HTTP 200), Supabase Auth answers on `/auth/v1/health` (GoTrue v2.190.0), and PostgREST returns
  the seeded public recipes via `/rest/v1/recipes` — so the schema, RLS anon-read policy, and
  `supabase/seed.sql` are all applied on the hosted project.
- Not yet verified: signed-in flows (create / edit / fork / version history), image upload to
  Storage, and anything on Android or iOS.
- Web runs via the `web-server` device (`http://localhost:8080`); Chrome is not installed and
  Edge's auto-launch debugger fails, so use `-d web-server` or `-d windows`.
- Supabase project is provisioned (hosted); the consolidated `supabase/migrations/0001_init.sql`
  is idempotent and applied.

## Template for new entries

```
| B001 | 2026-07-28 | high | recipe_editor | Saving edit does not bump version_number | open | |
```
