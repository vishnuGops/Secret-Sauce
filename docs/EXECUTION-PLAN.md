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
**Acceptance:** unauthenticated users land on Discover/auth; authenticated users reach app shell.

## Phase 6 — Home + Discover

**Files:** ~~`.../features/home/*`~~ (retired), `.../features/discover/*`.
**Acceptance:** Discover lists public recipes in Popular/Trending/Recent tabs with a search field.

> **Home was retired.** `/` is now a redirect-only route onto `/discover` — the landing screen
> had no entry in either navigation chrome (the web brand mark already pointed at Discover), so a
> cold start was the only way to see it. Discover is the front door on web and mobile.

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
**Amended 2026-08-19 (B035):** acceptance now also requires that a save preserve every column of
`Ingredient` / `RecipeStep`. The draft types carried only a step's text, so per-step time,
temperature and tip were unreachable when creating a recipe and were erased from the seeded
recipes by any edit — `update()` deletes and re-inserts the groups. Inputs added for time /
temperature / tip and ingredient note / optional; `steps.image_url` is carried through untouched
until a per-step picker exists.

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

## Phase 17 — Fix B022: nested content order reversed

**Status: done.** Fix applied and verified against a local Supabase stack in both directions
(with and without the fix); `melos run analyze` clean in all three packages. Verification table in
[BUG-TRACKER.md](./BUG-TRACKER.md#b022-verification-run-2026-08-18-local-supabase-stack).

**Root cause:** postgrest-dart's `.order(column)` defaults to `ascending: false`. The four
nested-content fetches in `SupabaseRecipeRepository` (`_fetchIngredientGroups` /
`_fetchStepGroups`, `packages/core/lib/src/repositories/recipe_repository.dart:273-315`) omit
the flag, so `ingredient_groups`, `ingredients`, `step_groups`, and `steps` all arrive
descending — steps render last-first. Every other `.order()` call in the repo passes
`ascending: false` explicitly (verified by grep), so the fix surface is exactly these four sites.

**The subtle part — stored-order corruption:** `update()` loads via `getById()` (reversed),
and `_persistContent` re-indexes the list `0..n` on save. Each app-edit therefore **flips the
persisted order**; a recipe edited an odd number of times is reversed in storage and currently
*displays* correctly (double reversal) — it will display wrong once the read is fixed.
`_appendVersion`'s `content_snapshot` inherits the same unreliability. Seeded recipes are clean
(SQL writes ascending; never edited). Parity of past edits is unknowable ⇒ **no auto-repair**;
audit and hand-fix any app-edited recipes (dev-stage data, expected to be a handful at most).

**Fix:** add `ascending: true` to the four calls. Nothing else changes; SQL is correct.

**Acceptance:** on the local stack (core has **no** tests — Gotcha 14 — so a green test run is
no evidence): a recipe with ≥2 groups and ≥5 steps displays groups and steps 1→N; edit + save
**twice** and re-verify after each save (catches the flip-flop); `melos run analyze` clean.
Close B022. — **met.**

**How it was verified** (Chrome is not installed, so the browser eyeball-check in the acceptance
criteria was replaced with something stronger — it drives the real repository code rather than the
rendered widget):

1. A fixture recipe was written straight into the local stack in known-ascending order — 2
   ingredient groups (`IG-A`/`IG-B`, 5 ingredients) and 2 step groups (`SG-A`/`SG-B`, 6 steps) —
   plus a local-only account owning it, so `update()` was reachable.
2. A throwaway harness under `apps/app/test/` (deleted afterwards — it needs a live database, and
   CI has no DB job) constructed `SupabaseRecipeRepository` against that stack and asserted
   `getById()` order, then `update()`d **twice**, re-asserting both the returned model and the
   stored `sort_order`/`step_order` read back independently after each save.
3. The same harness was re-run with the four `ascending: true` flags removed. It fails on the
   first assertion (`['SG-B', 'SG-A']` instead of `['SG-A', 'SG-B']`), so the check genuinely
   discriminates rather than passing vacuously.

That harness is not committed. Repository tests remain blocked on mocking `SupabaseClient`
(ROADMAP Phase 3); this was a one-off verification, not new coverage.

## Phase 18 — Chefs, tiers & leaderboard

**Status: done.** Full design in [SDS.md §10](./SDS.md#10-chefs-tiers--leaderboard); this section
is the build order that was followed. Phase 17 landed first (commit `2f2e6e0`) — leaderboard
verification opens recipes, and reversed steps would have poisoned every eyeball check.

**Approach:** "Chef" is a presentation of `profiles` — no new principal table. Score/tier are
denormalized onto `profiles` (`chef_score`, `chef_tier`, `public_recipe_count`), maintained by a
recompute-from-scratch trigger, exactly the `recipes.rating_*` pattern. Tier ships with every
recipe via PostgREST embedding (`owner:profiles(…)`), so cards render badges with zero extra
round-trips. The leaderboard is an RPC over the denormalized columns. Recipe→chef is 1:1 already
(`owner_id` non-null; forks create new owned recipes) — no schema change for that requirement.

**Files:** `supabase/migrations/0001_init.sql`, `supabase/seed.sql`, `supabase/scripts/drop.sql`,
`packages/core/lib/src/models/{enums,profile,recipe,chef_standing}.dart`,
`packages/core/lib/src/repositories/{chef_repository,recipe_repository,discover_repository}.dart`,
`packages/core/lib/src/providers.dart`,
`packages/design_system/lib/src/widgets/{tier_chip,chef_badge,recipe_card}.dart` + barrel,
`apps/app/lib/features/chefs/*`, `apps/app/lib/routing/{app_router,app_shell}.dart`,
`apps/app/lib/features/recipe_detail/recipe_detail_screen.dart`.

**Build order (each step leaves the tree green):**

1. **SQL first, verified on the local stack before any Dart** (the project's standing rule).
   Enum, columns, `chef_score()`/`chef_tier_for()`, `recompute_chef_stats()`,
   `on_recipe_stats_change`, backfill, `chefs_leaderboard()`, `drop.sql` entries.
   Traps, each a past bug class: trigger **must** be `security definer set search_path = public`
   (it updates a `profiles` row the liker/viewer does not own — invoker rights would silently
   match 0 rows, B011); `recompute_chef_stats` gets EXECUTE revoked (PostgREST exposes every
   `public` function, B-series `bump_count` rule); the blanket grant block predates these
   objects on a fresh apply, so grant EXECUTE on `chefs_leaderboard` explicitly (B013);
   everything guarded/`or replace` for idempotent re-runs (double-apply is part of acceptance).
2. **Seed**: chefs d1–d7 per the SDS table (tier ladder, exact-100 boundary, zero-engagement,
   private-only, tied pair), randomized passwords (B018), `seed_recipe(p_visibility)` with the
   old signature added to `drop.sql`. Re-run must be a no-op-plus-backfill (B014 pattern).
3. **core**: `ChefTier` (+`unknownEnumValue`), `Profile`/`Recipe` fields, `ChefStanding`,
   `ChefRepository`, embedding added to `getById`/`listMine`/`listSharedWithMe`/Discover
   (RPCs take `.select()` embedding for `setof recipes`). `melos run build_runner --no-select`,
   then decode-check against live rows: `chef_score` is Postgres `numeric` ⇒ `(v as num)
   .toDouble()` (Gotcha 11).
4. **design_system**: `TierChip`, `ChefBadge` (+`compact`), barrel exports (Gotcha 13), card
   overlay on the cover `Stack` — **not** a new column row; the tile cannot grow and
   B001/B002/B016 all came from intrinsic children. Widget tests at the card envelope / 2.0×.
   _(The card was later redrawn — ROADMAP Phase 20: the overlay moved bottom-left → bottom-right,
   the tile became fixed-**height** rather than fixed-aspect, and the envelope is now
   `kRecipeCardMinWidth` 288 to `kRecipeCardMaxWidth` 340, not 276/320 — the floor was 264 until
   B048 raised it.)_
5. **app**: `/chefs` in the `ShellRoute` (signed-out safe ⇒ `redirect` untouched), `AppShell`
   destination, leaderboard screen + providers, detail-screen badge.
6. **Docs fold-in**: SDS §3.2/§6/§7/§8 updated to describe reality, §10 trimmed to a pointer;
   `CLAUDE.md` enum count (4→5), feature map `/chefs` row, server-owned columns list +=
   `profiles.chef_score/chef_tier/public_recipe_count`; BUG-TRACKER verification table.

**Acceptance:**

- Local stack: double-apply of `0001_init.sql` is clean and stable; seed lands d1–d7 on their
  exact tiers (incl. score-100 ⇒ `line_cook`); liking/saving/viewing a chef's recipe **as
  another user** moves the owner's score (the definer check); flipping a recipe
  private/deleting it drops its contribution; `select * from chefs_leaderboard(50, 0)` as
  `anon` returns ranked rows, ties share a `dense_rank`, no `public_recipe_count = 0` chefs,
  Kitchen ≈ 10.2k ⇒ `head_chef`.
- App: every recipe card and the detail screen show the owner's badge with the tier under the
  name; `/chefs` renders signed-out; `melos run analyze` and `melos run test --no-select`
  clean; card envelope tests pass at the card's min and max width / 2.0× (288 and 340 today —
  they were 276/320 when this phase shipped, then 264/340; see Phase 20).
- Hosted rollout is one idempotent re-apply of `0001_init.sql` + `seed.sql` (both already safe
  by rule).

**Outcome — all of the above met.** Results table in
[BUG-TRACKER.md](./BUG-TRACKER.md#chefs--leaderboard-verification-run-2026-08-18-local-supabase-stack).
`melos run analyze` clean ×3; `melos run test --no-select` 35 passing. The hosted re-apply is the
one remaining item.

**Two things the plan got wrong, corrected in the build:**

1. **The owner embedding needs an explicit FK hint.** §10.5 specified
   `owner:profiles(id, display_name, avatar_url, chef_tier)`. That form is rejected outright —
   `recipes` and `profiles` are related five ways (`owner_id`, plus many-to-many through
   `recipe_likes`, `recipe_ratings`, `recipe_saves`, `recipe_shares`), so PostgREST answers
   `PGRST201: Could not embed because more than one relationship was found`. The working form
   names the constraint: `owner:profiles!recipes_owner_id_fkey(...)`. It is now a single shared
   constant (`kRecipeSelect` in `core/src/repositories/recipe_queries.dart`) because dropping the
   hint breaks `getById`, both list queries, and all four Discover queries simultaneously.
2. **The leaderboard row overflowed** at the accessibility envelope (B023) — caught by the new
   320 px / 2.0× test before merge, not in review. See the tracker entry.

**How the Dart side was verified** (Chrome is not installed, so no browser pass; `packages/core`
has no test dir, so `melos run test` says nothing about repositories — Gotcha 14): a throwaway
harness under `apps/app/test/` ran `SupabaseChefRepository`, `SupabaseDiscoverRepository`,
`SupabaseRecipeRepository`, and `SupabaseProfileRepository` against the local stack **signed
out**, asserting the seeded tier ladder, the `dense_rank` tie, the exact-100 boundary, both
exclusions, `chef_score` decoding as a `double`, and the owner embedding on all five recipe
surfaces — plus that `anon` cannot call `recompute_chef_stats`. Deleted after the run (CI has no
database job). The committed `chefs_screen_test.dart` covers the screen's
loading/empty/error/tie-render states with a fake `ChefRepository`, no database needed.

## Phase 19 — Authored recipe content, split from the demo seed

Roadmap: [ROADMAP.md Phase 19](./ROADMAP.md#phase-19--authored-recipe-content-split-from-the-demo-seed) ·
Design: [SDS.md §11](./SDS.md#11-recipe-content-vs-demo-data)

**Problem.** The Kitchen's recipes were staged as one flat `recipeData/data.json`: a single array
with a byte-identical duplicate, nine content defects (B025), and a shape the app cannot consume —
`servings` as free text, `amount` as one opaque string, no groups, no times.

**Order of work.** Two commits, deliberately separate. Data corrections first, against the old
shape, so the content diff is reviewable on its own; the structural change second, where every
line moves anyway.

**What shipped.**

1. `recipeData/recipes/<slug>.json`, one file per recipe. The filename is the identity, so the
   filesystem makes a duplicate slug impossible — which is the actual fix for B025's duplicate,
   not the deletion of the second copy.
2. `recipeData/schema.json` + `recipeData/README.md`. The schema is documentation, not a runtime
   dependency (no JSON Schema package in the toolchain), so its rules are restated in
   `tool/recipes.dart` and the two must be changed together — noted in both files.
3. `tool/recipes.dart` (`validate` / `gen` / `check`) → `supabase/seed_recipes.sql`, committed and
   CI-checked. `melos run recipes:*`, `db:recipes`, and `db:reset` extended.
4. `seed_recipe_v2`: group-aware, new name (so it cannot overload `seed_recipe`), B024 drop block
   in the file that recreates it, `execute` revoked (B026), and demo ratings reached through a
   `to_regprocedure` guard so the file outlives `seed.sql`.

**How the SQL was verified.** Docker was already serving an unrelated project's Supabase stack on
port 54322 — the port this project's `config.toml` claims — so rather than stop it, the SQL ran in
a throwaway database inside that same cluster, with the `auth` and `storage` schemas stubbed to
the columns `0001_init.sql` touches. Postgres 17.6, not the configured 15. That is enough to prove
the schema applies, the seed applies twice without duplication, both interleavings with `seed.sql`
are clean (24 recipes / 24 distinct titles / one overload each), grouping and per-group
`step_order` are right, `numeric` quantities and `null`-quantity "to taste" rows land correctly,
and `proacl` is `postgres=X/postgres` on all six seed helpers. It proves **nothing** about real
auth, Storage, or PostgREST — those still need the project's own stack.

**Content coverage** was checked mechanically rather than by eye: 9 titles in and 9 out, 109
ingredients in and 109 out, every old ingredient's distinctive words present in the new file.
Step count rose 35 → 41 (splits, no drops). `data.json` was deleted only after that passed.

**Then the six recipes already in the database.** Source was `seed.sql` rather than a dump of the
hosted project: B022's audit had already established that all six still carry exactly one
`recipe_versions` row, so none has been edited through the editor and the file is what the database
holds. Titles kept byte-identical — that is the dedupe key, so re-applying against the hosted
project is a no-op, not a second copy — and their engagement counters and taster ratings came
across as per-recipe `demo` blocks.

Their `perform seed_recipe(...)` calls were then **deleted from `seed.sql`**, which is the point of
the exercise: one definition per recipe. `seed.sql` keeps the accounts, the `d1`–`d7` demo recipes,
and the rating machinery, and `config.toml` gained `db.seed.sql_paths` so `supabase db reset` still
does everything in one command.

The move had to be provably neutral, since the leaderboard numbers in SDS §10.7 are derived from
those counters. Final run, after `Easy Guacamole` was dropped: 23 recipes / 64 ratings / 16
profiles with both files applied twice, and an identical board — Kitchen 10189 `head_chef` at
`public_recipe_count` 14, Amara 21000 `master_chef`, the Chen Wei / Greta Lindqvist `dense_rank`
tie intact, Dara still at exactly 100. The wrong order was tested too: recipes-first creates every
recipe with **zero** ratings and an explicit notice, and the documented recovery (`seed.sql`, then
re-run) restores the identical 64 / 10189.

**One content decision fell out of the merge.** The staged file and the database each had a
guacamole under a different name. `Easy Guacamole` was dropped in favour of `Fresh Guacamole`, the
one already live. The general rule that settled it: a chef may publish two recipes for the same
dish, however similar, as long as the **titles** differ — duplicate content is a product question,
duplicate titles are a correctness one, because `(owner_id, title)` is the import key and a
collision silently collapses to a single row. `tool/recipes.dart` therefore treats a repeated title
as an error, not a warning.

**Gaps left open**, all recorded in the roadmap: no `recipes.notes` column (notes are appended to
`description`), no reverse-direction lint for a step naming an unlisted ingredient, and no SQL
execution in CI.

## Phase 22 — Chefs v2: podium board + expanded chef card

Roadmap: [ROADMAP.md Phase 22](./ROADMAP.md#phase-22--chefs-v2-podium-board--expanded-chef-card) ·
Design: [SDS.md §10.6](./SDS.md#106-ui) · Source: `Chefs.dc.html` drafts `1b` / `1c` / `1d`

**Problem.** The board renders rank, name, tier and four icon chips. None of it explains the
number on the right: `chef_score` is `3×likes + 5×saves + 0.2×views` over public recipes, and that
formula appears nowhere in the product. A chef sitting at 10,189 cannot tell what would move them,
and the row is not tappable, so there is nothing to open for the answer.

**Order of work.** Bottom-up, because each layer is testable without the one above it: SQL →
`core` → `design_system` → `app` → tests. The dialog is last; everything it renders exists and is
covered before it is wired.

1. **`chef_top_recipes`** in `0001_init.sql`. `setof recipes` like the three Discover RPCs, so the
   client reuses `kRecipeSelect` and the `Recipe` model with no new decode path. Ordered by
   `chef_score(...)` per recipe — the same function the leaderboard aggregates — so "top by points
   contributed" cannot drift from the score it explains. PostgREST cannot order by that expression
   from the client, which is why this is an RPC and not a `.order()`.
2. **`ChefScoring` in `core`.** The expanded card prints `× 3`, `× 5`, `× 0.2` and a ladder at
   100 / 1,000 / 5,000 / 20,000, so those numbers have to exist client-side. They are a **mirror**
   of `chef_score()` / `chef_tier_for()`, which stay the source of truth: the server decides every
   stored score and tier, and the mirror only re-derives what is already on screen. A test pins
   each boundary so the copy cannot silently disagree with the database.
3. **`ChefStandingCard` in `design_system`** (draft 1b). Unlike `RecipeCard` this tile is not
   fixed-height — it is a list row that may grow — so the B001/B002/B016 failure mode does not
   apply directly, but the 2.0× envelope test is kept because the stats row and the score column
   are the same shape that overflowed twice before.
4. **The dialog/sheet.** One content widget, two hosts: `showDialog` capped at 1152 × 720 on ≥600px
   (the design's 80%-of-1440×900), `showModalBottomSheet` with a fixed header and a scrolling body
   on compact.

**Cuts from the design, and why.** Draft 1c and 1d draw a **Follow** button; there is no follow
model in the schema, so nothing on screen pretends there is — the three top-recipe rows tap
through to `/recipe/:id` instead, and "View all 14" is gone with the chef page that would host it.
1c's footnote "Rank recomputes nightly. Last updated 4 hours ago" is **wrong about this build** —
`on_recipe_stats_change` recomputes on every like, save, view and visibility flip — so it is
replaced with copy that says so rather than shipped as drawn.

**Four bugs, and only one of them was a test's to catch** (B029–B032). The tests found the layout
crash. The screenshots found the other three, and the reason is worth keeping: a widget test pumps
`ChefsScreen` **without the shell**, so it cannot see a modal rendering under the shell's FAB and
nav bar (B030); and an overflow test only fails when something overflows, so a chef name quietly
ellipsised to `Amara…` on every mobile row passed every envelope check (B032). `1 recipes` (B031)
was simply nobody looking. A green suite is not a rendered page.

**The layout crash.** The tier spine started as a stretched `Row`
child (`CrossAxisAlignment.stretch`), which is the cheap way to make a 6px bar fill a card's
height. It is wrong here: the card lives in a `ListView`, so its height is unbounded during
layout and `stretch` hands the spine `h=Infinity`. Eleven app tests failed at once with
`BoxConstraints forces an infinite height`. The fix is a `Stack` with a `Positioned` spine —
`IntrinsicHeight` would also work but costs an extra layout pass on every one of 50 rows.

**How the SQL was verified.** `0001_init.sql` was re-applied **in place** to the project's running
local stack (`supabase_db_secret-sauce`) with `ON_ERROR_STOP=1` — the upgrade path from gotcha 6,
not a fresh `db reset`. It applied clean, and `chef_top_recipes` came out with
`anon=X/postgres,authenticated=X/postgres`. Two behaviours were then exercised directly: as `anon`
the RPC returns the Kitchen's top three by contribution in the right order (3,636 / 2,553 / 1,693
points), and as the **private-only** chef `d6` — signed in as themself, via `set local role
authenticated` + a `request.jwt.claims` sub — their own `chef_top_recipes` returns **0 rows**
while they own a private recipe carrying 5,000 likes. That is the explicit `visibility` filter
doing its job under invoker rights; without it the chef's own dialog would have shown a recipe
nobody else can see and numbers nobody else can reproduce.

**Deploy note.** The RPC is new, so the feature is partly inert against a database that has not had
`0001_init.sql` re-applied: the dialog's "Top recipes" section is the only part that depends on it,
and it degrades to `Top recipes are unavailable right now.` rather than taking the card down —
pinned by a test. `melos run db:create` is idempotent and enough (see the warning in `CLAUDE.md`
about what `SUPABASE_DB_URL` points at).

**The hosted project was updated** on 2026-08-19 (there is no production deployment yet), and the
degraded path stopped being hypothetical on the way there — the first round of screenshots was
taken against a hosted database that did not have the RPC, and the card rendered its fallback
copy exactly as the test says it should.

Applying it did not go through `melos run db:create`, and the reason is worth writing down (B033).
That script shells out to `psql`, which **is not installed on this machine** — the only `psql` here
is the one inside the Supabase Docker container. Piping the file through that container then hits a
second wall: `db.<ref>.supabase.co` resolves **IPv6-only**, the Windows host can reach it but the
container has no IPv6 route (`Network is unreachable`). The combination that works is the **Session
pooler** host, which is IPv4, driven by the container's `psql`:

```powershell
$u = (Get-Content apps\app\env.local.json -Raw | ConvertFrom-Json).SUPABASE_DB_URL
Get-Content supabase\migrations\0001_init.sql -Raw |
  docker exec -i supabase_db_secret-sauce psql $u -v ON_ERROR_STOP=1 -f -
```

Two traps inside that: the pooler wants the user as `postgres.<project-ref>`, not bare `postgres`,
and a password reset takes a beat to propagate — an auth failure immediately after resetting is not
necessarily a wrong password. Verify auth on its own (`psql $u -c "select 1"`) before concluding
anything from a failed migration.

## Phase 23 — Chefs page v3 (web): hero, spotlight card, rails

Roadmap: [ROADMAP.md Phase 23](./ROADMAP.md#phase-23--chefs-page-v3-web-hero-spotlight-card-rails) ·
Design: `Chefs Page.dc.html` (page, expanded 1440 × 900) and `Chefs.dc.html` drafts `1e` (spotlight
card, desktop 400 × 560) / `1f` (spotlight card, mobile sheet) ·
[SDS.md §10](./SDS.md#10-chefs-tiers--leaderboard)

**Status: done, web only, and deliberately half the drawn feature.** The page, the hero and the
spotlight card ship against real data. The three rails' *time windows* do not — that half was cut by
the owner before any code, and the shelves that depend on it render honest placeholders. See the
decision table.

**Problem.** `/chefs` was a single 760px column of `ChefStandingCard`s. It answered "who is ahead"
and, since Phase 22, "why" — but only for one chef at a time, only on tap, and only for the top 50
by all-time score. There was no sense of the population (how many chefs, spread across which tiers),
no way to see who is *moving*, and nothing on the page a visitor would look at for pleasure. The
redraw answers the first and third: a hero that states the population and the ranking rule, the
leaderboard demoted to a sticky 404px panel, and rails of a **new collectible "spotlight" card**.

**Scope is web/expanded only.** Compact is byte-identical to Phase 22's board — draft `1f`
(spotlight in a mobile sheet, with Share/Recipes actions and swipe) is deferred, and the hero does
not render below `Breakpoints.compact`.

### The eight decisions, and who took them

The mockup draws several things this build has no data for. Each was settled before code; the four
marked **owner** were the owner's call on the plan, the rest follow Phase 22 precedent.

| # | Mockup draws | Decision |
| --- | --- | --- |
| D1 | A 4:3 "portrait" window on the spotlight card | **owner: leave it empty with the default avatar.** The window renders `avatar_url` when there is one and the same monogram `ChefAvatar` draws everywhere else when there is not. The plan had proposed the signature recipe's cover; the owner chose the avatar, which is the chef, not their food. |
| D2 | `SEASON 1`, serial `S1 · 004/148` | **Drop the season.** No season model exists and inventing one on the client is a fiction the database cannot back. The serial is `004 / 148` — rank over `chefCountProvider`. |
| D3 | `RECOMPUTED 4H AGO` | **Wrong about this build**, exactly like 1c's "recomputes nightly" in Phase 22. `on_recipe_stats_change` fires on every like, save, view and visibility flip. The kicker reads `LIVE · UPDATES ON EVERY LIKE, SAVE AND VIEW`. |
| D4 | `All time / Month / Week`, a `Momentum` tab, and two time-windowed rails | **owner: not now.** The queries are real — `recipe_likes.created_at`, `recipe_saves.created_at` and `recipe_views.viewed_at` all exist, so no snapshot table is needed — but they were cut in favour of shipping the page. Every control is **rendered and disabled** with a tooltip saying why, rather than hidden. |
| D5 | (nothing — a trap the mockup cannot show) | Recorded for whoever builds D4: **the windowed view term must not count anonymous rows.** `recipes.view_count` deliberately ignores them (B012) because `anon` holds `insert` on `recipe_views`; an aggregate over the raw log reopens exactly that inflation vector. |
| D6 | Full rails of moving chefs | **owner: placeholder cards with a TODO.** They would be empty against today's database — `seed.sql` writes the counters directly and leaves the engagement logs almost empty — and seeding dated rows to fix that would fire the counter triggers and move every `chef_score`, invalidating the numbers SDS §10.7 pins. `SpotlightCardPlaceholder` holds the shelf with a footnote naming the reason. |
| D7 | Newsreader (display) + a mono for kickers and serials | **owner: keep the existing font.** Kickers and serials are approximated with `letterSpacing` + `w800`, each marked `TODO(fonts)`. A font change is app-wide, not a `/chefs` change. |
| D8 | `Follow`, `Share card` (1f) | **Cut, same as Phase 22.** No follow model, no share-image pipeline. A spotlight card taps through to the expanded chef dialog. |

### What actually shipped — and the one thing the plan got wrong

**The plan called for four new RPCs. None were written, and none are needed.** Two findings
collapsed the SQL work to nothing:

1. **The hero's tier tiles do not need an aggregate RPC.** `profiles_select` is `using (true)` and
   `chefCount()` already demonstrates the shape — a `limit(1)` body with an exact count in the
   header. `tierCounts()` is five of those, one per rung, issued together. PostgREST cannot
   `group by`; the alternative, selecting every chef's tier and tallying client-side, downloads a
   row per chef and grows without bound. Five bounded counts do not.
2. **The spotlight card does not need a per-chef recipe read.** The draft's "move" row is the
   chef's signature dish, which is one `chef_top_recipes` call per card — eleven round trips for a
   ten-card rail. But draft `1e`'s own note says the second move is *the chef's strongest stat*, and
   that is already in the leaderboard payload: `ChefScoring.breakdown()` sorted by contribution.
   The card renders `Driven by likes · 1,980 likes × 3 · 5,940` from the row it was handed, so a
   rail of ten costs **zero** extra requests and reuses the arithmetic the expanded card explains.

The practical consequence is worth stating plainly: **this phase changes no SQL, so there is
nothing to deploy.** It works against the hosted database exactly as it stands. That also means none
of the local-stack verification the checklist requires for `supabase/**` applies here.

### Order of work

Bottom-up, as planned: `core` → `design_system` → `app` → tests. The spotlight card was built and
tested first, standalone against draft `1e`, before any page work — it is the piece the rest hangs
off, and it is reviewable on its own.

1. **`core`.** `ChefRepository.tierCounts()` (five parallel exact counts); `ChefTier.wireValue`, the
   Postgres enum label, needed because a `.eq('chef_tier', …)` filter cannot go through
   `json_serializable`'s private mapping; `pluralNoun` / `countOf` in `formatting.dart`, hoisted out
   of the closure inside `ChefStandingCard._Stats` so B031 has one place to be got wrong instead of
   four. No `@freezed` file gained a field, so **no `build_runner` run was required**.
2. **`design_system`.** `ChefSpotlightCard` + `SpotlightCardPlaceholder`; `CardRail`; a `board`
   variant of `ChefStandingCard`; `context.textScale` in `adaptive.dart`. All exported from the
   barrel (Gotcha 14).
3. **`app`.** `chefs_hero.dart`; `chefs_screen.dart` rebuilt into three layouts; the providers,
   including `leaderboardPagesProvider` behind `Show all 148`.
4. **Tests**, then analyze, then review.

### Two design calls inside the build

**`spotlightCardHeight(context)` — the tile grows with text, and only with text.** The card is
fixed-size, so by [Gotcha 13] every band except the portrait is intrinsic and comes out of a fixed
budget. The usual answer — let the flexible band absorb the growth — cannot work here: the intrinsic
bands alone exceed 356px well before 2.0×. So the tile's height is `356 + (textScale − 1) × 168`,
where 168 is roughly the height of everything on the card that is text. A rail scrolls inside a page
that scrolls, so a taller card at a larger text scale costs nothing and hides nothing, which
dropping bands would. Past 2.5× the growth clamps and the portrait absorbs the rest; a 3.0× test
pins that last line of defence (and is what caught B039).

**Two independent columns under a fixed hero, not a sticky panel.** The draft scrolls the page and
pins the board with `position: sticky`. Flutter's equivalent is a nested-scroll arrangement, and the
draft already gives the panel its own `max-height: 675px` scroll container — so two columns each
owning their scroll renders the same thing with less to get wrong. The cost is that all three
regions must fit the viewport at once, which is exactly what B037 was.

### Five bugs, three of them the same bug in different places

B037–B041, all in [BUG-TRACKER.md](./BUG-TRACKER.md). B037 (the page over-budget in height at 2.0×)
was caught by the new envelope test and would have failed `top_nav_bar_test` too. B038 (a 50/50 flex
split truncating the chef's name beside dead space) and B041 (empty tooltips on the controls that
work) were found **in review, not by any test** — neither overflows, and an overflow test only fails
when something overflows. B039 (an unbounded rank pill at 3.0×) and B040 (placeholder cards on a
loaded-empty board) were found by tests written for this phase.

The pattern worth carrying forward: **`Expanded` beside `Flexible` in the same row is a 50/50 split,
not a priority order.** Where one child must win, the other should be non-flex inside a
`ConstrainedBox` cap — the shape `RecipeCard` already uses for its difficulty badge (B016).

### Verification

- `melos run analyze` — **No issues found!** in all three packages, `SUCCESS` (read from the output,
  not the exit code — B006/B007).
- `flutter test` per package — core **42**, design_system **88**, app **68**; 198 total, all green.
  Up from 39 / 58 / 49 at Phase 22.
- `/code-review` run over the working tree against `CLAUDE.md` + the repo's review checklist; the
  five findings above were fixed and pinned by tests in the same pass.
- **No SQL, so no local-stack run.** The checklist requires one for any `supabase/**` diff; this
  phase has none, and nothing new needs applying to the hosted project.
- **No screenshots — and this is the gap.** The B028 procedure (release build, static serve) needs a
  browser, and Playwright fails here with `Chromium distribution 'chrome' is not found at
  …\Google\Chrome\Application\chrome.exe`. Phase 22 found four bugs (B029–B032) this way that no
  test could see, and two of this phase's five were review finds of exactly that kind. The visual
  pass is outstanding, not skipped-because-unnecessary. `npx playwright install chrome` unblocks it.

**Acceptance, against the plan's own list:** the hero states the population and the ranking rule ✓;
the board panel scrolls independently and `Show all` widens the page ✓; three rails page by three
with arrows dimming at the ends ✓; a spotlight card opens the expanded chef dialog ✓; 1024 and 1000
degrade without overflow ✓ (pinned at 320 / 360 / 600 / 1000 / 1440 × 2.0×); compact unchanged ✓.
Not met: the three tabs do not reorder the board and the hero filter does not filter, both by D4.

### Deferred

- **D4's windowed half**: `chef_window_stats(p_since)`, `chefs_leaderboard_windowed(p_days, …)`,
  the Trending and month rails, the `Momentum` tab and the hero's Month/Week. Wiring point is
  marked with `TODO(rails)` / `TODO(board)` / `TODO(hero)` at each site. D5 is the trap to read
  first.
- **Draft `1f`** — the spotlight card as a mobile sheet, with swipe and the Share/Recipes actions.
- **The `large` (400 × 560) spotlight size.** Nothing on the page consumes it, and an unused
  variant is a second layout to keep correct for free.
- **Fonts (D7)**, still an app-wide decision.
- **The `New` sort** would work today — `profiles.created_at` exists — but it needs a column
  `chefs_leaderboard` does not return, so it is grouped with the rest of D4 rather than half-built.

## Phase 24 — Simulated population: a realistic user + engagement dataset

Roadmap: [ROADMAP.md Phase 24](./ROADMAP.md#phase-24--simulated-population-a-realistic-user--engagement-dataset) ·
Design: SDS §12 (to be written in this phase)

**Status: working end to end at the `medium` preset.** Built 2026-08-20: the shared validator,
`tool/sim.dart`, `simData/` with **25 of 120** dishes, all five `supabase/sim/*.sql` files, the
`melos run sim:* / db:sim*` scripts, and the CI gate. `melos run db:reset` now rebuilds the whole
thing — 1,694 recipes, 1,016 profiles, ~118k view rows — from an empty database in **~15 seconds**,
and `3_sim_verify.sql` passes all 43 assertions.

**Two decisions below were reversed by what the build found**, and both are worth reading before
trusting the rest of this section:

- **`db:reset` now DOES run the sim** (the table said it should not). At the owner's request, and
  safe: `engage_existing` is false, so the Kitchen and `d1`–`d7` counters stay byte-identical and
  every standing pinned in SDS §10.7 survives. Only the ranks move, which is the point.
- **`master_chef` is not organically reachable at `medium`**, and that is a finding about the
  product rather than the generator — see B043 and "What the dataset proved" below.

Still outstanding: 95 more dishes, `simData/people.json` and `vocab.json` (name pools are inline SQL
arrays for now), the per-persona RLS smoke test, and a run at the `large` preset.

**Problem.** The database has 21 accounts and 23 recipes, and every engagement number in it was
typed by a human into `seed.sql` or a `demo` block. `recipes.like_count` was authored; the
`recipe_likes` rows behind it were not. That was fine while the counters were the only thing being
read, and it stopped being fine three phases ago:

| What is untested | Why the current seed cannot test it |
| --- | --- |
| Leaderboard pagination, `dense_rank` collisions at scale, the `004 / 148` serial | 8 rows |
| Trending / Momentum / Month / Week — Phase 23's whole deferred half | The dated logs are nearly empty; SDS §10.8 says the seed "needs its own answer before the rails do" |
| Popular's Bayesian prior actually suppressing a 1-rating recipe | ≤ 8 ratings exist per recipe, all positive |
| Search relevance and its cost | 23 documents |
| **The most common real user: someone who only reads recipes** | Every account in the database is a creator |

**What this phase is.** A deterministic, idempotent, scale-parameterized generator that produces a
population *and its history* — and derives the counters from that history instead of authoring them.
That inversion is the whole design: `seed.sql` writes `like_count = 2500` and no likes; the sim
writes the likes and lets the same arithmetic the triggers use produce 2500.

### Decisions taken before code

Four are marked **owner** — they change the shape of the deliverable and are the owner's call. All
four were put to the owner on 2026-08-20 and confirmed as proposed; the scale question was decided
alongside them (`medium` — 1,000 users / ~900 recipes — as the default preset).

| Question | Decision |
| --- | --- |
| Where does sim data live? | Rows in `public` (they must be readable by the app), but every helper function, registry, and config table in a new **`sim` schema**. PostgREST exposes `public` only, so nothing here can become an RPC — B026 avoided by construction instead of by a `revoke` block |
| Ship a big generated `.sql`, or generate in-database? | **In-database.** 900 recipes plus ~250k engagement rows as literal SQL is tens of MB of unreviewable diff. The committed artifact is the *dish library* (bounded, generated from JSON, CI-checked like `seed_recipes.sql`); the population is `generate_series` + hashing, so scale is a parameter |
| `random()` or hashing? | **Hashing.** `setseed()` + `random()` is deterministic only for a fixed evaluation order, which a plan change or a parallel scan breaks. `sim.rand(key, stream)` over `hashtextextended` is a pure function of the row's own key — same seed, same database, always |
| **owner:** how many authored dishes? | **120**, in three reviewable batches of 40. That holds the reuse ratio at the `medium` preset to ≤ 10 recipes per dish. Fewer dishes is the obvious place to cut scope, at the cost of Discover looking repetitive |
| **owner:** written or scraped? | **Written.** An ingredient list is not copyrightable but step prose is, and a scrape would put someone else's text in a file this repo publishes. Web research is used to check ratios and technique on unfamiliar dishes, never to copy |
| **owner:** do sim users engage with the Kitchen's 14 recipes? | **No, by default** (`engage_existing = false`). It keeps every number pinned in SDS §10.7 byte-identical with the sim applied, which is worth more than a slightly more mixed Discover page. The flag exists and routes through a baseline table so it stays idempotent when on |
| **owner:** does `db:reset` run the sim? | **No.** Reset stays fast, and the standings stay reproducible without a 250k-row load |
| Images? | `avatar_url` / `cover_image_url` **null** everywhere. No asset exists, and a fabricated external URL 404s offline — which renders as a broken-image box, not the monogram fallback the null path exercises. Knobs left for whoever wires a bucket |

### File layout

```
simData/
├── README.md · schema.json          # format = recipeData's, minus `demo`, plus an optional `sim` block
├── dishes/<slug>.json               # 120 authored dishes, owner-agnostic
├── people.json                      # name pools (~15 locales), bio templates
└── vocab.json                       # Zipf-weighted tags, title-variant templates
tool/
├── recipe_format.dart               # THE validator, extracted from tool/recipes.dart
└── sim.dart                         # validate | gen | check  ->  1_sim_dishes.sql
supabase/sim/
├── 0_sim_schema.sql                 # schema `sim`: rand/uid helpers, registries, personas, presets
├── 1_sim_dishes.sql                 # GENERATED — loads the library into sim.dish (jsonb)
├── 2_sim_generate.sql               # the generator: population, recipes, history, counters
├── 3_sim_verify.sql                 # assertions; raises on violation
└── 9_sim_teardown.sql               # registry-driven delete + drop schema sim cascade
```

The validator extraction is the one change to working code. `tool/recipes.dart` keeps its behaviour
exactly; the proof is that `melos run recipes:check` still passes byte-for-byte afterwards, since it
compares generated text. **Done, and it does.** A second copy of the rules was the alternative, and
`recipeData/schema.json` already carries a "restated in `tool/recipes.dart`, change both" warning —
a third copy makes that warning unmaintainable.

It landed at `tool/recipe_format.dart`, a sibling, rather than the planned `tool/lib/`. `tool/` is a
folder of loose scripts run by path, not a pub package, so there is no `package:` URI that reaches
into it; the only way to satisfy `always_use_package_imports` properly would have been a root `lib/`
owned by the workspace package, which is a bigger structural claim than a shared validator deserves.
Both callers use a relative import with a one-line `ignore` naming the reason. `dart analyze tool`
is clean, and `melos run analyze` never reaches the directory anyway — it runs per-package inside
`packages/**` and `apps/**`.

### The population model

Personas, and the reasoning for the shares. The 90-9-1 rule (90% read, 9% engage, 1% create) is the
starting point; this product moves it upward because keeping *your own* recipes is the core value
proposition, so private-only creators are a real and large group rather than an anomaly.

| Persona | Share | Recipes | Behaviour | What it exists to prove |
| --- | --- | --- | --- | --- |
| Ghost | 22% | 0 | 0–2 views in one session, never returns; a third never view anything | An account with no rows anywhere still renders — profile, tier badge, empty My Recipes |
| Lurker | 43% | 0 | Many views, few likes, rare save, almost never rates | **The default user.** Nothing in the database looks like this today |
| Collector | 14% | 0–1 (private, ~30% of them) | Heavy saves, moderate likes, some ratings | The Saved list at volume; a user whose only recipe is private |
| Casual cook | 11% | 1–3, ~30% private | Moderate everything | `1 recipe` singular copy (B031); mixed visibility in one My Recipes list |
| Regular contributor | 6% | 4–15 public | Active both directions | The bulk of the leaderboard's middle |
| Power chef | 2.5% | 15–60 public | High engagement received | `head_chef` / `master_chef`, the rails, the spotlight cards |
| Vault keeper | 1.5% | 3–20, **all private** | Receives nothing | The private-exclusion path at scale — `d6`'s case, but 15 of them |

~79% of accounts therefore have `public_recipe_count = 0` and never appear on the leaderboard, which
is the number `chefs_leaderboard`'s filter has never actually been exercised against.

**Signups** follow a compounding growth curve over 24 months (more accounts recently than at the
start), with weekday and hour-of-day seasonality so dated queries see a realistic shape rather than a
uniform smear.

**Recipes** take a dish from the library and apply a deterministic variant — a title template
(`Weeknight …`, `… with Brown Butter`, `My Grandmother's …`) plus tweaks to servings, times, one
ingredient and one step. `(owner_id, title)` therefore never collides *within* an owner (the import
key — SDS §11.2) and deliberately does collide *across* owners, which is the legitimate case that
rule permits and nothing in the database currently contains.

**Engagement is a funnel over a view, never an independent draw**: view → like → save → rate, with
per-persona conversion rates. A like without a view is data no real session could produce, and it
would quietly break any windowed metric built on top. Recipe exposure is log-normal — a few recipes
take most of the traffic — modulated by age, with a burst at publication so Trending has signal.

**Ratings are J-shaped**, not normal: mode at 5.0, a long thin tail down to 0.5, shifted per recipe
by a latent quality term. A normal distribution centred on 3.0 is the classic synthetic-data tell and
would make Popular's Bayesian prior look like it was doing nothing. A small polarized set (all 1s and
5s, mean 3.0) is included on purpose.

**Private recipes receive engagement only from their `recipe_shares` rows.** Anything else is data
RLS could not have produced, and it would make the private-exclusion assertions vacuous.

### Counters are derived, not authored

This is the part most likely to be got wrong, and it has a performance trap and a correctness trap.

*Performance.* Inserting ~250k engagement rows with the triggers live is ~250k advisory locks, ~250k
`update recipes`, and — because `recipes_chef_stats` watches those columns — ~250k full
`recompute_chef_stats()` passes. The load is therefore: `alter table … disable trigger` for the five
counter triggers, bulk insert set-based, recompute set-based, re-enable. Target for `medium` is under
60 seconds; without this it is closer to hours.

*Correctness.* The recompute must call the real `chef_score()` and `chef_tier_for()`, never a
restated `3 / 5 / 0.2` (Gotcha 19 — `ChefScoring` in Dart already exists as one mirror too many). And
`3_sim_verify.sql` then re-derives every counter independently and asserts equality, so "the triggers
were off" can never quietly mean "the counters are wrong".

### Edge-case catalogue

The generator produces each of these deliberately, and `3_sim_verify.sql` asserts each is present —
otherwise a tuning change silently drops the interesting rows and leaves a dataset that only contains
the average case.

| Case | Produced by | Protects |
| --- | --- | --- |
| Account with zero rows anywhere | Ghost persona, ~7% of the population | Empty states; a profile with no history |
| `display_name` empty string | 3 accounts (the column's default) | Monogram fallback with nothing to take an initial from |
| 40-character name, emoji name, RTL name, single-word name | A fixed slice of the name pool | B032 — a name that ellipsises rather than overflows; the board row and spotlight card at 404px |
| Exactly one recipe / one rating / one save | Forced on 20 accounts | `1 recipes` copy (B031) |
| Recipe with many views and zero likes | Low-quality latent term, high exposure | Trending vs. Popular actually diverging |
| Recipe with 1 rating at 5.0 | Forced on 15 recipes | The Bayesian prior — these must **not** reach Popular's top 10 |
| Recipe with 50+ ratings at 4.9 | Forced on 5 recipes | The prior not over-suppressing either |
| Polarized ratings (1s and 5s, mean 3.0) | Forced on 10 recipes | `rating_avg` hiding a bimodal reality |
| Same viewer, 30 visits to one recipe | Repeat-visit draw | B012 dedup — `view_count` contribution is 1 |
| Anonymous views, ~30% of the log | `user_id = null` rows | B012 anon exclusion — `view_count` must not move |
| Private recipe with engagement from its share list only | Vault + collector personas | The private-exclusion path in `chef_score` and in RLS |
| Users with 0 / 1 / 12 recipes shared *to* them | Share fan-out draw | My Recipes → Shared-with-me, empty and full |
| Fork, fork-of-a-fork, fork whose source was deleted | ~4% of recipes; 3 sources deleted after | `forked_from_recipe_id`'s `on delete set null`; lineage display |
| Recipe with 1 version vs. 9 versions | Geometric edit count | Version history sheet, empty and long |
| 1 ingredient / 1 step, and 40 ingredients across 5 groups | Library extremes | The editor and the detail screen at both ends |
| `servings` 1 and 24; `cook_minutes` 0; a 12-hour step | Library coverage targets | The servings scaler; no-cook and overnight recipes |
| A tag on 200 recipes and a tag on 1 | Zipf tag draw | Search and any future tag filter |
| Two chefs at an identical `chef_score` | Score-collision forcing | `dense_rank` sharing a rank at scale, not just for `d3`/`d7` |
| A chef 0.2 points below a tier threshold | Forced | `chef_tier_for()`'s `>=` and `numeric` rounding |

### Order of work

1. **Validator extraction**, alone, verified by `recipes:check`. Nothing else changes in that commit.
2. **`sim` schema + helpers + `3_sim_verify.sql` skeleton.** The assertions are written before the
   generator, against zero rows, so they start red.
3. **Dish library batch 1 (40)** + `tool/sim.dart` + `1_sim_dishes.sql`. End-to-end at the `tiny`
   preset with a stub generator.
4. **Generator**: population → recipes → versions/forks/shares → views → likes/saves/ratings →
   recompute. Each stage lands with its assertions turned on.
5. **Dish library batches 2 and 3**, then the presets tuned so the shape assertions pass at `medium`.
6. **Teardown**, verified by generate → teardown → generate producing identical counts.
7. **Docs** — SDS §12, `CLAUDE.md` commands + the two new gotchas, `README.md`, and whatever the
   dataset put in `BUG-TRACKER.md`.

### How it will be verified

Local Supabase stack, `psql` from inside the container (B033 — there is no local client):

```powershell
supabase start
docker exec -i supabase_db_secret-sauce psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f - < supabase/sim/2_sim_generate.sql
```

`3_sim_verify.sql` raises rather than prints, so a red run cannot be mistaken for a slow one. It
covers counter invariants, authorization invariants (no self-rating; no engagement RLS could not have
produced), temporal invariants (nothing predates its parent, nothing is in the future), the shape
assertions above, idempotency (apply twice → identical counts *and* identical counters), and that
`d1`–`d7` plus the Kitchen still hold the scores and tiers SDS §10.7 pins. **Their ranks will move,
and that is the point of the phase.**

Nothing in CI runs SQL today (SDS §11.3), so this script is the only test coverage this phase gets —
which is also the strongest argument yet for the deferred Postgres CI job.

### What the dataset proved (2026-08-20)

The assertion suite was written before the generator and started red, which is the only reason any
of this was caught: **every defect below produced a run that succeeded.**

- **B044, three ways.** A time anchor read from `now()` re-dated every recipe on the second run
  while `recipe_versions` still pointed at the registry's older dates, so all 1,671 versions ended
  up before their own recipe. View ids folded `actor_id` through `% 100000` and collided, so `on
  conflict do nothing` silently dropped view rows and left likes with no view behind them. And
  viewer eligibility was over-constrained to "signed up before the recipe existed", which is both
  wrong (a new user can read an old recipe) and lossy — it discarded ~80% of draws instead of
  resampling, and cost the star chefs most of their reach.
- **B045.** `sim.pick_dish()` reads `sim.dish` but is created in the file that runs *first*, so the
  very first apply on a clean database failed. It survived several green end-to-end runs because
  every machine that had ever run the generator already had the table. Gotcha 6, restated: the
  convenient paths do not exercise the one a new environment takes.
- **B043, and this is the useful one.** With a population to measure against, the `chef_tier`
  thresholds turn out not to describe this product at its current size. The strongest organically
  generated chef — 45 public recipes, 7,885 distinct viewers, 848 likes, 625 saves — scores 7,246.
  `master_chef` wants 20,000. The seeded `d1` reaches 21,000 from 4,000 likes across two recipes,
  which against 1,000 accounts is four likes per recipe from *everyone who exists*. 952 of 1,000
  simulated accounts sit at `home_cook`. The ladder on `/chefs` is, for a real early userbase,
  two rungs. SDS §10.8 predicted exactly this ("provisional product numbers; expect retuning once
  real data exists"); the sim is what made it answerable.

The tempting fix for B043 was to raise the star-exposure multiplier until a `master_chef` appeared.
That would have made the assertion pass and taught the number nothing, so `3_sim_verify.sql`
asserts `master_chef` only at the `large` preset and carries the reason inline. The same judgement
applies to checks E3 and E9 at `tiny`: both measure quantities whose ceiling is set by the size of
the population — a recipe cannot have more distinct viewers than there are users — so at 60 users
they are relaxed or skipped **loudly**, rather than quietly retuned into passing.

### Risks

- **Volume × trigger cost.** Handled by the disable/recompute/re-enable dance, but that requires
  table-owner rights. Fine as `postgres` locally and in the hosted SQL editor; it would not work from
  a PostgREST client, and nothing should try.
- **Teardown deleting the wrong rows.** It deletes `auth.users` rows. Scoped to the `sim.actor`
  registry — never an email pattern, never an id range — and gated behind `--yes`.
- **Hosted application.** The sim is safe to apply there (randomized passwords per B018, emails on a
  domain that cannot receive mail), but it is 250k rows on a free-tier database. `small` is the
  sensible hosted preset; `medium` and `large` are local.
- **Predicted findings, not promises.** `recipes_search` recomputes `recipe_search_document()` per
  row for both the filter and the rank, and `can_read_recipe()` runs per row for every Discover read.
  Neither is visible at 23 recipes. If they show up, they are `BUG-TRACKER` entries in this phase and
  fixes in the next one — a stored tsvector column with a GIN index is the known answer to the first.

## Phase 25 — Restaurants & signature dishes

Roadmap: [ROADMAP.md Phase 25](./ROADMAP.md#phase-25--restaurants--signature-dishes-north-star--designed-not-started) ·
Status: **designed, not started.** This section records the design decisions so Phase 25 starts
from an agreed shape instead of an open question. Nothing below is built.

**What it is.** The product's end state (see ROADMAP "Product direction"): restaurants as a
directory layer above chefs. A restaurant has **member chefs** (optional — most profiles never
join one) and **signature dishes** that point at existing public `recipes`. It is discovery
surface and identity, not a new content system.

**The one decision that shapes everything: a restaurant is not a principal.** Nobody signs in as
a restaurant. It is a row managed by `owner`-role members, exactly the way "chef" is a
presentation of `profiles` rather than a second account type (Phase 18's core call, which this
phase is the payoff for). Consequences:

- Auth is untouched. RLS policies are written against `auth.uid()` membership lookups, the same
  primitive `recipe_shares` already uses.
- The engagement model is untouched. Likes/saves/views/ratings stay on recipes; a restaurant
  reads its numbers *through* its signature dishes and member chefs, it never collects its own.
- Teardown/ownership is simple: `created_by → profiles`, members cascade, no orphan principal.

**Schema shape** (all in `0001_init.sql`, idempotent, guarded — see the ROADMAP checklist for
the column-level detail):

```
restaurants            1 ──< restaurant_members >── 1  profiles
restaurants            1 ──< restaurant_signature_dishes >── 1  recipes
```

Three traps, each a known bug class, called out now so the build doesn't rediscover them:

1. **Grants (B013).** All three tables are created after the blanket grant block on an upgraded
   database — grant `select` to `anon`/`authenticated` and DML to `authenticated` explicitly,
   beside the table.
2. **Signature dishes must be public recipes.** The table is world-readable; a row pointing at a
   private recipe leaks that the recipe exists (title resolves for members, 404s for everyone
   else). Enforce with a `with check` that the recipe is `public` **and** owned by a member —
   and decide what happens when a signature recipe is later flipped private (recommended: a
   trigger deletes the signature row, same "derived state follows source" philosophy as the
   counter triggers).
3. **Embedding needs FK hints from day one (Gotcha 17 / PGRST201).** `restaurants` relates to
   `profiles` via `created_by` and via `restaurant_members` immediately, so
   `members:profiles(...)` is ambiguous at birth. Define a `kRestaurantSelect` constant in
   `core/src/repositories/` the way `kRecipeSelect` was defined, on the first query written.

**Restaurant "score", deliberately deferred.** The obvious aggregate (sum or mean of member
`chef_score`s, or engagement over signature dishes) inherits B043's calibration problem
squared. Ship the directory **unranked** (alphabetical / newest) first; add ranking only after
B043 is settled and Phase 24's sim can generate restaurant populations to calibrate against.

**Build order** (the same bottom-up order every phase since 18 has used):

1. Public chef page `/chef/:id` — the standing prerequisite. Identity header (ChefBadge, tier,
   score breakdown) + a `RecipeGrid` of that chef's public recipes (`chef_top_recipes` already
   exists; it needs a `p_limit` wide enough or a paged variant). The restaurant page copies this
   shape, and every existing `ChefBadge` becomes tappable.
2. SQL: enum, three tables, RLS, grants, `drop.sql` — verified on the local stack including the
   upgrade path (Gotcha 6) and the private-flip trigger, before any Dart.
3. `core`: models, `RestaurantRepository`, `kRestaurantSelect`, providers.
4. `design_system`: restaurant card + member row, barrel exports, 288px / 2.0× envelope tests.
5. `app`: `/restaurants` directory + `/restaurant/:id` detail (both signed-out safe), owner
   management UI (create, members, signature-dish picker over the owner's public recipes).
6. Sim extension: generated restaurants + memberships so the directory is tested at scale.
7. Docs fold-in: SDS gains a §13 (restaurants), CLAUDE.md feature map + enum count, checklist
   doc-sync table.

**Acceptance (to be tightened when the phase starts):** directory and detail render signed-out;
a non-member cannot write a restaurant, its members, or its signature dishes (RLS-verified on
the local stack, not UI-verified); a private recipe cannot be, or remain, a signature dish; the
sim generates restaurants and `3_sim_verify.sql` gains assertions for the membership and
signature invariants; all existing standings in SDS §10.7 unchanged.

## Phase 26 — Discover v2: masthead, three shelves, one archive

Roadmap: [ROADMAP.md Phase 26](./ROADMAP.md#phase-26--discover-v2-masthead-three-shelves-one-archive) ·
[SDS.md §6.0](./SDS.md#60-shelves-phase-26)

**Status: done, both platforms.** No mockup — the shelf idea and the three categories came from the
owner's brief ("horizontal rows like the chefs page, three categories, get creative"), and the
categories were chosen against what the schema can actually rank.

**Problem.** Discover was `Popular / Trending / Recent`: one corpus, three rankings, three tabs.
Every tab answers the same question — *what is doing well* — so a visitor with no opinion about
ranking had nothing to open, and the page had no editorial position at all. It was also the most
generic screen in the product: any recipe app ships those three tabs.

### The three decisions, taken before code

All three were the owner's, on the plan. The fixture question in particular could not wait — two of
the three shelves are empty on a seed-only database, and CLAUDE.md's seed-fit gate says that gets
said out loud *before* building, not discovered after.

| # | Question | Decision |
| --- | --- | --- |
| D1 | Which three shelves | `01 UNDER 30` / `02 WEEKEND PROJECTS` / `03 MOST FORKED`. Two time poles and the lineage axis. The alternatives offered were a cuisine passport (`distinct on (cuisine)` — visually the richest, but no "best Peruvian" signal exists to order it by) and a beginner bench (safest data, but then everything on the page is quick and easy) |
| D2 | Shelves 2–3 are empty on a plain `seed.sql` + `seed_recipes.sql` | Fix it in the **sim**, not by authoring content. The alternative was two new long-cook recipes in `recipeData/` — real content-writing work for a shelf that the sim populates anyway |
| D3 | Do the tabs survive | No. Masthead + shelves + one `EVERYTHING ELSE` grid, with the old three demoted to a **sort**. Keeping the tab bar under the shelves would have left two browsing systems doing the same job |

### Why each shelf ranks on a different signal

This is the part that would have been easy to get wrong by making all three consistent. `UNDER 30`
ranks on the Bayesian rating, `WEEKEND PROJECTS` on saves, `MOST FORKED` on forks — because a
weeknight recipe is picked on whether it is any good, a project on whether it is worth a Saturday
(you *save* a project; you *rate* what you already cooked, and fewer people get that far with a
six-hour braise), and a fork shelf cannot rank on anything else. Three shelves with one ordering
would be one shelf shown three times. Each header prints its own rule.

### The SQL, and the one thing that was not new work

Three RPCs, shipped first as `0002_discover_shelves.sql` and **folded into `0001_init.sql` on
2026-08-23** — the owner's call, on the grounds that the project is pre-release and nothing outside
this machine depends on the schema yet, so an idempotent edit to the baseline beats a second file.
The freeze resumes the moment that stops being true. Same contract as the existing Discover RPCs:
`setof recipes` so `kRecipeSelect`'s owner embed rides along, `stable`, invoker-rights,
`anon`-callable, `p_offset`, and every order ending `created_at desc, id` (Gotcha 24).

Two calls inside it are worth recording:

1. **`site_rating_prior()`.** `recipes_quick` needs the same `m = 5` Bayesian prior `recipes_popular`
   already had inline. Copying the CTE would have made a ranking formula exist twice, which is
   exactly the shape Gotcha 19 is about — so the prior became a function and `recipes_popular` was
   rewritten to read it — identical order, and `site_rating_prior()` is defined **above** both
   callers because Postgres validates a SQL function body at creation. It is **cross-joined**,
   evaluated once per query: written as a per-row
   scalar `bayes_score(rating_sum, rating_count)` it would re-scan every public recipe for every
   public recipe.
2. **`recipes_most_forked` counts public forks only** — a correctness decision, not a filter. The
   RPC is invoker-rights, so an unqualified count is RLS-filtered: a private fork would count for
   its owner and for nobody else, and one recipe would hold two different ranks depending on who
   asked.

### The fixture change: a fork tree with a trunk

The shelf is ranked by fork count, and the sim's forks were drawn **uniformly** from every older
public recipe. Measured on the local stack at `medium`, seed 20260820: 74 forks landed on **54
different sources**, and the most-forked recipe in the entire database had been forked **twice**.
The shelf fills — ties fill anything — but there is no order in it. That is not what forking looks
like anywhere either: people rewrite the recipe everybody already cooks.

So the source is now drawn **weighted by reach**: `sim.exposure_draw(n)` — the same per-recipe
log-normal §7 turns into view rows — times the star-chef multiplier, raised to `sim.fork_bias()`
(default 2.0, a `sim.config` knob). Same seed, same 74 forks, they now land on **28 sources with a
top recipe at 10**, then 5, 5, 3, 3, 3 — a distribution the shelf can actually rank. Verify check
G3 asserts a maximum of 3 or more, which is exactly the assertion the uniform draw fails. The exponent is above 1 because the two effects compound: being
read is popularity-weighted, and wanting to rewrite what you read is popularity-weighted again.
The draw is an exponential race (`order by ln(u) / weight desc limit 1`) — a weighted sample in one
pass, deterministic on the (fork, candidate) pair like every other draw in the generator. It also
replaced two correlated subqueries that scanned and sorted the eligible set twice per fork.

Two consequences to know: `sim.exposure_draw` had to become a **function** (§5 and §7 must draw the
same number for the same recipe, and they run at opposite ends of the file), and the update is
additive — an already-generated database keeps its flat tree until `9_sim_teardown` + regenerate.

### The sliver refactor nobody asked for but the page required

`RecipeGrid` was a `CustomScrollView`. Discover is now one scroll from masthead to the last row of
the archive, and a scrollable cannot nest inside a scrollable. So the grid and its
loading/error/empty ladder were split into `SliverRecipeGrid` / `RecipeAsyncSliverGrid`, measured
with a `SliverLayoutBuilder` (`crossAxisExtent` is the sliver world's `maxWidth`), and the two box
widgets became thin `CustomScrollView` wrappers around them. The other five browsing surfaces did
not change at all — which is the test that the split was done at the right seam.

`SliverFillRemaining(hasScrollBody: false)` on all three states, not the default: when three shelves
have already filled the viewport there is no remaining extent to hand a scroll body, and a spinner
of height zero is a page that looks finished.

### Design: not the chefs page again

The obvious move was a second dark gradient hero and three more icon-tile rails. That would have
made two pages that look like one page with different data in it. Instead:

- **A printed masthead.** A rule, `THE PASS · 1,684 PUBLIC RECIPES` in spaced caps, the title, one
  line of copy, and the search field sitting on the title's baseline. Kitchen jargon on purpose —
  the pass is the counter finished plates go out over, which is what a public vault is.
- **Numbered shelves.** `01` set in the shelf's accent, the title in spaced caps, a hairline rule
  running out to the controls. The numeral says *sequence*; a third icon tile would have said
  "another list". Three different scheme roles (`primary` / `tertiary` / `secondary`) so the
  shelves are told apart at a glance without a literal colour anywhere.
- **The archive is set apart** — heavier rule, no numeral, sort links that underline rather than a
  pill. The shelves are an edit; the grid is the archive, and the two should not look alike.

`CardRailVariant.numbered` sheds its kicker at 700px, its position label at 620, and its arrows at
460 (all × text scale): Discover's rails render at 320px, which the chefs rails never had to.

### Order of work

`core` → `design_system` → `app` → tests, as usual, with the SQL first because everything else is
shaped by what the server can return. The design_system pieces (`CardRailVariant.numbered`,
`RecipeCardPlaceholder`) were built and tested standalone before any page work.

### Verification

- `melos run analyze` — **No issues found!** ×3, read from the output rather than the exit code
  (B006/B007).
- `melos run test --no-select` — core **83**, design_system **99**, app **117**; **299** total, up
  from 281. `melos run format` ran first and analyze stayed green (OPT-T4's guarantee).
- `/code-review` over the working tree against `CLAUDE.md` + the repo checklist. Two findings, both
  fixed here: **B057** — the numbered header's ranking kicker was a non-flex `Text` in a `Row`, so
  it was laid out unbounded (B039's class); the width gate in front of it decides only whether the
  kicker is *drawn*, not how long the caller's string is. Proved by removing the cap and re-running:
  `A RenderFlex overflowed by 721 pixels`. **B058** — a `drop.sql` comment claimed `cascade` would
  reach `recipes_popular` / `recipes_quick`, which Postgres does not record for a quoted SQL
  function body. The review also caught a doc-sync miss (SDS §8's widget table).
- **The SQL ran on every path.** First as `0002` on the *upgrade* path — applied to a database
  that already had `0001`, the path Gotcha 6 says neither `db reset` nor `drop → create` can
  surface — then, after the fold, from a genuinely **empty schema**: `drop.sql` down to 0 tables,
  the folded `0001` up, seed, content, sim. Re-applied four more times with zero errors and no
  duplicate overload on `recipes_popular` (B024). Seed-only shelves measured **10 / 1 / 0** rows
  both before and after the fold — the empty-shelf-03 claim confirmed rather than predicted, and
  proof the fold was behaviour-preserving.
- **The sim ran**, torn down by registry and regenerated at `medium` (1,000 actors, 1,671 recipes);
  `3_sim_verify.sql` printed `ALL CHECKS PASSED` with §G included. The fork numbers in this
  document are measured from that run, both ways, at the same seed.
- **Screenshots** (Chrome was installed for this; B028 procedure: `flutter build web --release`
  then `npx serve`): Discover at 390 / 700 / 1400, `/chefs` at 1400 — closing **Phase 23's**
  outstanding gap, which found nothing — and a forked recipe detail at 1400. Edges were measured
  out of the PNGs with a few lines of Pillow rather than eyeballed, which is the only reason B059
  was found: a 16px-versus-32px inset is invisible at a glance and unmissable in a pixel column.
  Two bugs, **B059** and **B060**, both fixed here.
- **Dark mode verified** (2026-08-23) by pinning `themeMode: ThemeMode.dark`, rebuilding, shooting
  1400 and 390, then reverting and rebuilding light. No defects: the three shelf accents survive
  the brightness flip, and the card banner inverts correctly (light-tone `primary` with dark
  `onPrimary`) rather than staying a dark block with white text.
- **Applied to hosted, 2026-08-23**, through the container `psql` + Session pooler (B033). Exit 0,
  no errors, and the row counts are byte-identical either side of it (24 / 22 / 17 / 26 / 64) — a
  re-apply of the baseline costs data nothing, which is the property the whole editable-baseline
  decision rests on. The apply turned up something worth knowing: **hosted was several phases
  behind**, reporting `does not exist, skipping` for the `search_tsv` triggers (OPT-P1),
  `save_recipe` (OPT-A1) and `recipe_versions_set_current` (OPT-S1). It has all of them now.
- **RLS as `anon` is now proven on the real database** — `set local role anon` in a rolled-back
  transaction returns 10 / 1 / 0 from the three shelves (grants landed) and 22 recipes against
  `postgres`'s 24, i.e. the two private rows filtered. Over PostgREST with the anon key, all five
  Discover RPCs answer `200` with rows. Supabase's DDL event trigger reloaded the schema cache
  unaided.
- Still open: RLS as a **signed-in `authenticated`** user — owner-vs-shared-vs-stranger on a private
  recipe, which is the shape B053 lived in and which the shelves do not exercise.

## Phase 27 — Recipe detail v2 (web)

Roadmap: [ROADMAP.md Phase 27](./ROADMAP.md#phase-27--recipe-detail-v2-web-measured-page-ingredients-rail-method-column) ·
[SDS.md §7.1](./SDS.md#71-recipe-detail-the-two-layouts-phase-27)

**Status: web done, compact not started.** Built from the `Recipe Detail v2.dc.html` canvas, which
was drawn against `Recipe Detail.dc.html` — an as-built transcription of real full-page captures of
the shipped v1 page, taken first precisely so the redesign was measured against what exists rather
than what the old canvas claimed existed. That first canvas covered only the top third of the page
and had missed step groups entirely.

### Order of work, and why

1. **`formatMinutes()` into core, with tests.** The facts strip is the first surface that reads
   durations side by side, where `70 min` beside `40 min` is worse than `1 h 10 m` beside `40 min`.
   Pure function, so it belongs in `core/src/formatting.dart` next to `groupedCount` and
   `isoDate` — not a private helper in the widget that needed it first (the mistake OPT-A7 undid).
2. **`LikeSaveButtons` extracted before either layout used it.** The v2 band and the v1 body both
   need like/save, and B051's fix (toggle, not one-way; signed-out goes to `/auth`; failures
   surface) is subtle enough that a second copy would drift. `_toggleEngagement` moved with it out
   of the screen and into `detail_chips.dart`.
3. **The branch, then the new files.** `recipe_detail_screen.dart` gained one
   `if (context.isExpanded)`; everything new landed in three files beside it. The existing
   `recipe_detail_test.dart` pumps the default 800×600, so it kept exercising v1 unchanged and
   never had to be touched — which is the whole reason the branch is on window width rather than a
   flag.
4. **The envelope test before the browser.** Written to fail: pump the whole page at
   {1000, 1440} × {1.0, 2.0} and assert `takeException()` is null.

### What the envelope test bought

It failed on its first run and found three real overflows (B062/B063/B064) — the servings row, the
rail footer, and the cook-mode teaser. The third only overflows at **1000px**, not 1440, so a
single-width check would have shipped it. All three are the same shape and it is worth stating
plainly, because the repo has now hit it six times: **a non-flex child of a `Row` is laid out at its
intrinsic width, and a `Wrap`/threshold is the fix, not more flexibility on the sibling.** Buttons
whose labels grow with text scale are the reliable trigger.

Getting the widget chain out of a failing envelope test is not obvious: `tester.takeException()`
*consumes* the `FlutterError` before the framework prints its `error-causing widget` dump, so the
failure says only "overflowed by 52 pixels". A throwaway probe test that captures
`FlutterError.onError` into a list and prints each `FlutterErrorDetails` gives the file and line
directly. Worth reaching for immediately next time rather than reasoning about intrinsic widths.

### What the envelope test could not buy

Neither of the two findings `/code-review` turned up afterwards is a layout defect, and neither is
observable on this machine's data — which is the interesting part:

- **B065** — the header band watches `recipeVersionsProvider`, and `versions()` was a bare
  `.select()`, so every page open pulled `recipe_versions.content_snapshot` (a whole recipe as
  `jsonb`, up to nine rows) to render a *count*. Every seeded snapshot is `'{}'`, in all three
  fixture sources, so locally a ~90 KB read looks like a 900-byte one; only a recipe edited through
  `save_recipe` shows the real size. Fixed with `kRecipeVersionSelect`. The general lesson: **the
  fixtures are empty in exactly the places that make an over-fetch cheap**, so "it felt fast
  locally" is not evidence about a read whose payload grows with use.
- **B066** — an ingredient with a unit and no quantity rendered `—` and dropped the unit, while v1
  printed it. Nothing seeded reaches that state; the editor does, on a quantity field that fails to
  parse. A test had to *construct* the fixture to see it, which is now what
  `recipe_detail_v2_test.dart` does (the fake repository takes the recipe so a test can vary it).
  Worth noting how the first fix was itself wrong: adding the unit *after* the note in the chain
  fixed the reported case and silently created a new one — `unit + note + no quantity` then dropped
  the unit instead. Four nullable-ish inputs into one 86px gutter is a truth table, so the fix is
  the whole table (`quantity + unit` → `unit` → `note` → `—`, note beside the name unless it took
  the gutter), and the test pins all four rows rather than the one that was reported.

### Cook mode — the second half

Four of the canvas's eight frames, built as a **mode** rather than another layout: its own route on
the root navigator, its own session, its own theme.

**Two scope questions were settled with the owner before any code**, because both change the
architecture rather than the styling, and guessing wrong wastes the build:

1. *Screen-awake and a background alarm* — `wakelock_plus` and `flutter_local_notifications`, plus
   Android/iOS config on the committed runners, none of it verifiable by a widget test here.
   **Answer: pure Dart now.** The chime is Flutter's own `SystemSound` + `HapticFeedback`, which is
   real and foreground-only, and the copy was rewritten to match ("Keep this screen open", "Chime
   when a timer ends") rather than left promising the canvas's two chips.
2. *The finish screen's "note for next time"* — `recipe_ratings` has no column for it.
   **Answer: ship the rating, drop the note**, with the column it needs named in the roadmap. A
   drawn-but-dead input is a second inert affordance, and this change set exists partly to remove
   the first one.

**Order of work, and the one decision inside each:**

1. **The pure derivations first** (`cook_mode_model.dart`), because they are the part that can be
   wrong invisibly. `flattenCookSteps` has to keep group identity — a flat 1..N loses the `Filling ·
   step 1 of 3` header *and* the weighted progress bar. `cookSegments`' fill counts steps **behind**
   the cook, so a group's first step fills nothing; the canvas draws both readings across two frames
   (33% on C, 50% on D) and this is the one that does not claim credit for a step still in front of
   you.
2. **The session** (`cook_mode_providers.dart`). The design question was how many timers can run.
   One-at-a-time needs arbitration ("a timer is already running on step 4 — replace it?"), which is
   a dialog and a decision the cook should not have to make; **many-at-once with a single shared
   `Timer.periodic`** turned out to be both the simpler code and what the canvas asks for ("it keeps
   counting if you move to the next step"). One ticker also means one thing to cancel on dispose —
   a per-timer periodic is the classic `Timer is still pending` test failure.
3. **The alarm as state, not an event.** `ringing` is a `Set<String>` of step ids held until
   acknowledged. An event (a callback, a one-shot snackbar) is lost on the rebuild that a step
   change causes, which is exactly the case that matters: the bake finishes while you are reading
   step 3.
4. **The step→ingredient derivation**, knowing there is no schema link. Whole-name matching fails on
   real data — the row says "boneless chicken thigh" and the prose says "the chicken" — so it
   matches **word-wise** with a stop-word list, whole-word so `\bbutter\b` does not fire on
   "buttermilk". Hidden when it finds nothing, and labelled as a hint.
5. **The shared quantity formatters moved into core** on the way past. Cook mode's rail draws the
   same quantity gutter as the reading page's, and B066 had just been fixed *twice* in two files
   — so `ingredientQuantityLabel` / `ingredientNoteIsQuantity` / `sentenceCase` / `ingredientOneLine`
   now live in `core/src/formatting.dart` with their own tests, and both rails read them.
6. **The envelope test before the browser**, again.

### What the envelope test bought, again

Three bugs on the first run, and the interesting one is **B067**: the web top bar capped its chips
the documented way — non-flex inside a `ConstrainedBox(maxWidth: constraints.maxWidth / 3)`, the
B038 shape — with the `LayoutBuilder` supplying that width placed *inside* the `Row`. A non-flex
child of a `Row` is laid out unbounded, so `constraints.maxWidth` there is `double.infinity`, the cap
is `infinity / 3`, and it capped nothing. **The fix for a Gotcha 21 overflow reproduced the Gotcha 21
overflow, while reading in review exactly like the accepted shape.** It was 186px over at
1000px × 2.0× and green at 1440 × 2.0 *and* at 1000 × 1.0 — one width or one scale would have shipped
it. Now Gotcha 25: hoist the `LayoutBuilder` to the nearest bounded ancestor.

The other two: `MetaChip` could not degrade (B068 — a shared widget whose `Text` had no
`maxLines`/`overflow`, harmless for `12 min` and 15px over once a caller passed a whole ingredient),
and "not done — back to the last step" did nothing (B069 — `goTo`'s early return guarded on the
index alone, and the finish screen is a *flag* beside the index, so the one control that targets the
current step matched the guard and cleared nothing).

### Compact v2, and retiring v1

The decision that shaped this one was **not** how to draw frame B — it was what to do with the
600–1000 band. Three options, and the third is what shipped:

1. Compact v2 below 600, v1 for 600–1000. Three layouts, one of them a design nobody drew.
2. Compact v2 below 600, expanded v2 down to 600. The expanded page is a 352px rail beside a method
   column inside a measured 1140px page; at 620px that is two columns of about 290px each.
3. **Compact v2 for everything below 1000, v1 deleted.** A single-column cover-first page reads
   correctly at 800px — it is a wider version of the same thing, not a compromise — and it takes the
   layout count from three to two.

So `recipe_content_views.dart` and `_Body` are gone, and `/recipe/:id` is now one
`context.isExpanded` branch between two v2 layouts. `recipe_detail_test.dart` **needed no changes to
its existing tests** to move with it: all eight assert what reached the repository (which value
`setLiked` was sent, how many rows `logView` wrote), not what the tree looked like. That is the
argument for behavioural tests in one paragraph — a layout was deleted underneath them and they
stayed green and stayed meaningful.

The reuse is the other half. `IngredientRail(bordered: false)` and `MethodColumn` are the *same*
widgets the expanded page uses, because the alternative had already been tried: B066 was two copies
of the ingredient list disagreeing across the 1000px branch, and B065/B066 had just been fixed. The
only thing compact re-specifies is `FactsStrip(quad: true)` — six cells across 390px is 65px each,
narrower than the word "Difficulty".

Two shapes here are new and worth naming:

- **A pinned sliver has exactly one height**, so the usual escape hatches do not apply: a `Wrap`
  cannot reflow inside it and a `Row` of intrinsically-sized chips is the Gotcha 21 overflow. The
  jump bar's content therefore scrolls **horizontally** — nothing can overflow in the axis that
  matters, which leaves the height as the only thing to bound against text scale.
- **The bottom bar is outside the scroll**, as `Column(Expanded(scroll), bar)` rather than a `Stack`
  with a reserved bottom padding. The bar's height grows with text scale, so any reserve constant is
  wrong at some scale — overlapping the last step or leaving a gap. Sized by its own content it is
  right at every scale. Cook mode's compact view already used this shape.

**B070 is the finding worth keeping.** The rail's heading row — `Row(Expanded(title), counter)` —
overflowed by 9.5px at 390px × 2.0×, in a widget that had been green for a week. It is the same
non-flex-child diagnosis as B062/B063, which fixed the two rows *below* it and left the heading
alone, correctly at the time: nothing then rendered the rail narrower than the 493px column the
expanded page gives it. Compact reused it at 358px. **A widget's envelope is the set of widths it
has actually been pumped at, and adding a caller re-opens it** — so a reuse is a reason to re-run
the envelope, not a reason to trust it.

### Still not built

Sticky ingredients rail on the expanded page, version-history v2 (needs a snapshot diff), naming the
fork parent (needs a second read), persisted check-offs, and cook mode's two deferred plugins.

## Phase 28 — Nutrition facts: label, tabs, manual entry

Roadmap: [ROADMAP.md Phase 28](./ROADMAP.md#phase-28--nutrition-facts-per-serving-label-rail-tabs-manual-entry-done)

**Status: DONE (2026-08-24).** Shipped as planned. Four things the plan did not anticipate, all
of them small and all of them recorded:

1. **`Recipe.toJson()` does not flatten a nested model** (B071). `explicitToJson` is off for
   `packages/core`, and every other nested field on `Recipe` is `includeToJson: false`, so
   `nutrition` was the first one that had to serialize itself — the generator emitted
   `'nutrition': instance.nutrition` and `jsonEncode` would have thrown at whatever call site
   touched it. Closed with an explicit `@JsonKey(toJson: _nutritionToJson)`. No production caller
   existed yet, which is exactly why it needed a test rather than a fix later.
2. **The editor's collapse had to keep its fields in the `Form`** (B072). A `TextFormField` that
   leaves the tree leaves `Form.validate()` with it, so a half-typed `1/2` could be collapsed out
   of sight and then silently dropped by `tryParse` — the B066 shape, one keystroke away. The
   panel uses `Visibility(maintainState: true)`, and the screen re-opens it when a save is blocked
   so a hidden error is never a dead end. That moved `expanded` from the panel's own state up to
   `_RecipeEditorScreenState`. Review then narrowed the re-open: it fires only when
   `EditNutrition.hasInvalidEntry`, because an unconditional version unfolded eleven nutrition
   boxes whenever a blank **Title** blocked the save.
3. **`EditNutrition.load()` rather than a second instance.** The editor builds its draft in a
   field initializer and `_load()` runs afterwards, so `fromModel` would have produced a second
   object whose `dispose()` nobody wired up. `load()` refills the live controllers; the
   `fromModel` factory is `EditNutrition()..load(n)` and is what the round-trip tests use.
4. **Test fixture percentages have to be distinct.** The label's first fixture put sodium and
   fibre both at 25% and `findsOneWidget` failed for a reason that had nothing to do with the
   widget. The committed fixture is chosen so all eight land on different numbers.

**Added after the fact, on the owner's ask (2026-08-24): the sim generates labels.** The two
all-10 fixtures make the panel *reachable* and stop there — two recipes, and every `% Daily Value`
they print is nonsense. So `sim.nutrition_for(key, category)` in `0_sim_schema.sql` draws one per
simulated recipe and `2_sim_generate.sql` writes it. The decisions worth recording:

- **Derive from calories, don't draw eleven independent numbers.** Independent draws give 200 kcal
  beside 40 g of fat — non-null, and obviously fake to anyone who reads a label. Calories are
  drawn per category, split into fat / protein / carb *energy* shares, and converted at 9 / 4 / 4
  kcal per gram, so the macros reconstruct the calorie figure. A sampled Dessert: 340 kcal,
  14 g fat, 5.5 g protein, 48 g carbs — 14×9 + 5.5×4 + 48×4 = 340, exactly.
- **Per-category ranges as a table, not a `case` ladder.** `sim.nutrition_profile` holds one row
  per category, so retuning Dessert is a one-row update rather than a function rewrite — the same
  reasoning `sim.persona` and `sim.title_variant` already use.
- **Bound every sub-value by its parent, after rounding.** Saturated ≤ total fat, added ≤ total
  sugars, fibre + sugars ≤ carbs. Rounding first and bounding second, because the reverse lets
  `round()` push a child past a bound that was satisfied a moment earlier. A label that
  contradicts itself reads as data, which is worse than no label.
- **~20% get nothing.** The empty state is a real state; a population where every recipe has a
  label cannot demonstrate it, and D5–D7 would be asserting over a set that never varies.
- **`sim.rand` only** (B044). Verified by regenerating the whole population twice from the same
  seed and comparing an md5 over all 1,671 `(n, nutrition)` pairs — identical.

Four new assertions, **D5–D8** (39 → 43): self-consistency, the exact 11-key set, non-negative
numbers, and that both populations exist. D5 confirmed non-vacuous by writing
`saturated_fat_g = 999` into one row and watching it fire, then restoring the row from
`sim.nutrition_for` and getting the original md5 back — which re-proves determinism from the other
direction. Measured shape at `medium`: 1,320 of 1,671 labelled (79%), Main 547 kcal / 38 g protein
average, Dessert 36 g sugars, Sauce 127 kcal.

**What `/code-review` found afterwards**, all fixed in the same change set: the unconditional
re-open above; **B073**, where hoisting the stepper out of `IngredientRail` restated its "is this
scaled?" test and dropped the `servings == 0` guard, so a 0-serving recipe's banner claimed a
colour change the list did not make (the general lesson: an extraction that *restates* a predicate
rather than moving it is where a pure refactor stops being one); a regression test for B072 that
never collapsed the panel and so would have stayed green with `maintainState: true` deleted; and
two doc-sync misses — `NutritionFactsLabel` absent from the SDS §8 widget inventory, and five
present-tense references still calling the RLS matrix 76 checks.

Verified: `melos run analyze` / `test --no-select` / `format` all SUCCESS (core 108,
design_system 113, app 199); `supabase db reset` (fresh) **and** the upgrade path — new `0001` +
new `seed_recipes.sql` layered on a database that already had the old ones, which left exactly one
`seed_recipe_v2` overload; `db:rls` at **79 checks**, and the new grant check confirmed
non-vacuous by revoking `update (nutrition)` once and watching B9a go red; the B072 test confirmed
non-vacuous the same way, by deleting `maintainState: true` and watching it go red;
`recipes:check` and `sim:check` clean; screenshots on the built app for both tabs × both layouts ×
{empty, populated} × {light, dark}. The original plan follows.

The ask, verbatim in product terms: a nutrition panel styled
like the label on a store product; on both layouts it shares the ingredients' place as two tabs
under the servings control (`Ingredients` default, `Nutrition` beside it); both tabs respond to
the servings stepper; manual entry or leave-empty only (auto-calculate later); empty shows
`No nutrition info available`; dummy values of 10 per field on some fixtures so the UI is
inspectable.

### The five decisions, and the alternatives they beat

1. **One `jsonb` column, not eleven `numeric` columns.** The recon that preceded this plan
   enumerated every copy of the writable-recipe-column set — thirteen places:
   `_writablePayload` ([recipe_repository.dart:173-187](../packages/core/lib/src/repositories/recipe_repository.dart#L173-L187)),
   the insert and update grant lists (`0001_init.sql:1208-1215`), `save_recipe`'s insert and
   update branches (`:1939-1988`), `fork_recipe`'s insert list (`:1758-1767`),
   `_kRecipeColumns` ([recipe_queries.dart:32-37](../packages/core/lib/src/repositories/recipe_queries.dart#L32-L37)),
   the `Recipe` model, `seed_recipe_v2`'s signature + insert list + revoke strings (all generated
   from [tool/recipes.dart](../tool/recipes.dart)), the sim's bare insert
   (`2_sim_generate.sql:326-340`), the validator allowlist
   ([tool/recipe_format.dart:95-121](../tool/recipe_format.dart#L95-L121)), `schema.json`, and
   the two test pins (`chef_models_test.dart:312-337`, `recipe_repository_test.dart:24-47`).
   Eleven scalar columns would touch all thirteen, eleven times. One `jsonb` column touches each
   once, and the future auto-calculate writes the same column. The trade — Postgres cannot
   type-check the interior — is bought back with a `jsonb_typeof` check constraint, a fixed
   11-key model on the Dart side, and the authoring validator rejecting unknown keys (its
   standing rule: [tool/recipe_format.dart:240-242](../tool/recipe_format.dart#L240-L242)).
2. **Per-serving values; the label never multiplies them.** The alternative — multiply label
   values by the same factor as ingredient quantities — reads "consistent" and is nutritionally
   wrong: scaling 4 → 8 doubles the batch *and* the servings, so a serving is unchanged. What
   does change with the stepper is the batch, so the label's servings line prints the scaled
   count and one batch line prints `calories × scaled servings`. Both tabs watch
   `selectedServingsProvider(recipe.id)`
   ([recipe_detail_providers.dart:74-76](../apps/app/lib/features/recipe_detail/recipe_detail_providers.dart#L74-L76))
   — the same provider cook mode reads, which is the B066 discipline: one number, one source.
3. **Hoist the stepper; don't duplicate it, don't trap it.** Three shapes considered. Tabs
   *around* the whole rail traps the stepper inside the Ingredients tab — on the Nutrition tab
   the one control the label depends on is invisible. A second stepper inside the nutrition pane
   is B066 by construction. So the stepper and the `Scaled from N` banner move **up** — out of
   `IngredientRail` ([ingredient_rail.dart:93-166](../apps/app/lib/features/recipe_detail/ingredient_rail.dart#L93-L166))
   into a `ServingsRow` widget that the new `RailPanel` host renders above the tab chips, with
   the active pane below. `IngredientRail` keeps heading / list / footer; the host takes the
   `bordered` container (expanded: card, compact: bare), so the pane swap happens inside one
   frame. The cost is honest: restructuring the rail re-opens its width envelope (Gotcha 26 —
   B070 is the proof that reuse re-opens it), so both suites' envelope matrices re-run per tab.
4. **`ChoiceChip`s in a `Wrap`, not `SegmentedButton`.** The share dialog's `SegmentedButton` is
   the app's only segmented control, and it lives in a dialog that owns its width. Here the tab
   row must survive 358 px (compact's content box) at 2.0× text scale, and a segmented control is
   one intrinsic `Row` — the exact Gotcha 21 shape, with no reflow escape. Two `ChoiceChip`s in a
   `Wrap` degrade by wrapping, the same move the rail's own three rows already use. Tab state:
   `StateProvider.autoDispose.family<RailTab, String>` — `autoDispose` so a revisit starts on
   Ingredients (the ask names the default), family-keyed like its two siblings. Compact's
   `_jumpToIngredients` tear-off also resets the provider, so the pinned jump chip cannot scroll
   to a section whose ingredient list is hidden behind the other tab.
5. **The label renders in `design_system`; the numbers come from core.** `NutritionFactsLabel`
   is pure presentation over a `RecipeNutrition` (design_system already depends on core), so
   both detail layouts — and any future surface, an editor preview included — draw one label. The %DV math and
   the value trimming are pure functions in core beside `formatMinutes` — the OPT-A7 rule:
   helpers used by two surfaces live in core with tests, not in the widget that needed them
   first. FDA 2,000-kcal daily values as constants: fat 78 g, saturated 20 g, cholesterol
   300 mg, sodium 2,300 mg, carbs 275 g, fiber 28 g, added sugars 50 g, protein 50 g; no %DV for
   calories, trans fat, or total sugars (the real label omits them too).

### Two SQL traps, named before they are written

- **JSON null is not SQL NULL.** `_writablePayload` will send `'nutrition': null` for a recipe
  without data; in the jsonb payload that is a JSON null, and `p_payload -> 'nutrition'` returns
  `'null'::jsonb` — which is not SQL `NULL`, fails `jsonb_typeof(nutrition) = 'object'`, and
  would poison every save of an empty recipe. Both `save_recipe` branches therefore write
  `nullif(p_payload -> 'nutrition', 'null'::jsonb)`. And it is `->` (jsonb), not `->>` (text):
  there is no implicit `text → jsonb` cast, so the wrong arrow is a runtime error on first save.
  The RLS matrix gets a check asserting a JSON-null payload lands as SQL `NULL`.
- **The grant omission is silent here.** `save_recipe` is `security definer`, so the RPC path
  works even if `nutrition` is missing from the column grants — the failure only appears on a
  direct `PATCH`, which nothing in the app currently issues for recipes. The grant is still
  mandatory (B050's model: grants are the column-level authorization RLS cannot express), and
  because nothing fails loudly without it, the RLS matrix's positive owner-update check on
  `nutrition` is the only thing that proves it exists. Matrix count moves from 76.

### Order of work, and why

1. **SQL first** — column, check constraint, both grants, `save_recipe`, `fork_recipe`, matrix
   checks. Verified on the local stack before any Dart exists, because every later stage decodes
   what this stage returns. `melos run db:rls` after (Gotcha 15's standing trigger).
2. **core** — `RecipeNutrition`, the `Recipe` field, `_kRecipeColumns`, `_writablePayload`, %DV
   helpers, `build_runner`, tests. The `recipe_repository_test.dart` save group asserts
   `p_payload['nutrition']` through the recording client — the request-side half of what the
   matrix proves on the policy side.
3. **Content pipeline** — validator, `schema.json`, `seed_recipe_v2` (+ the B024 drop line for
   the outgoing 17-arg signature, in the generated file and `drop.sql`), the two fixture files
   with all-10 dummies, `"nutrition": null` in the other twelve, `recipes:gen`, `recipes:check`.
   Before the UI, so the UI is built against seeded data, not constructed fixtures alone.
4. **`NutritionFactsLabel`** in design_system + barrel + its own envelope test at
   {320, 358, 493} × {1.0, 2.0} — the widths the rails actually hand it, per Gotcha 26.
5. **Detail restructure, two commits**: first the extraction (`ServingsRow` out of
   `IngredientRail`, `RailPanel` host, both layouts swapped, all existing tests green — a pure
   refactor with a before/after-identical page), then the tabs + nutrition pane + provider. A
   one-commit version would mix a refactor that must change nothing with a feature that changes
   plenty, and the envelope re-runs land with the first commit where a regression is
   unambiguous.
6. **Editor** — `EditNutrition`, the panel, dispose wiring, round-trip tests. Last among the
   code stages because it writes through the payload the earlier stages proved end-to-end.
7. **Envelope + screenshots + docs** — both tabs × both layouts × {empty, populated} ×
   {light, dark} via the B028 procedure; SDS §3.2 / §7.1 / §11; CLAUDE.md's feature map and
   column lists.

### How it will be verified

- `melos run analyze` / `melos run test --no-select` / `melos run format` — grep melos output
  for `SUCCESS`, not the exit code (B006/B007).
- `supabase db reset` (fresh path), then the **upgrade path** (Gotcha 6): reconstruct
  `git show <last-release>:supabase/seed_recipes.sql` + old `0001`, apply, then layer the new
  files. The `seed_recipe_v2` signature change is the exact class B024 shipped through both easy
  paths — the old 17-arg overload must be dropped in the generated file itself, or the upgrade
  path dies with `42725 function … is not unique` while fresh and re-apply stay green.
- `melos run db:rls` — 76 + the new checks, all PASS; revert the grant line once to confirm the
  new check goes red (the non-vacuousness ritual BL-7 established).
- `melos run recipes:check` / `sim:check` — CI's staleness gates.
- Widget suites: compact 390 / 600 / 800 and expanded 1000 / 1440, × {1.0, 2.0}, **per tab**;
  editor 320 / 360 / 600 at 2.0× with the panel expanded.
- Screenshots on the built app (`flutter build web --release`, `npx serve` on a fresh port,
  hash routes): the label with 10s everywhere, the empty tab, dark mode.

### Risks, stated

- **The dummy 10s are load-bearing for inspection and worthless as data.** They exist because
  the ask says so — every %DV they produce is nonsense (10 g fat = 13% DV) and the plan treats
  replacing them as named deferred work, not an afterthought. They cannot reach hosted:
  `seed_recipe_v2` early-returns on existing `(owner_id, title)` (Gotcha 16), which here is a
  feature. *(Closed by Phase 29d, 2026-08-25: the estimator's own output replaced them. The same
  early-return means hosted still carries the 10s — see the BL-5 register.)*
- **The rail refactor is the riskiest diff** — it touches the one widget both layouts share and
  B070 lives in. Mitigated by the two-commit split and the per-tab envelope re-runs.
- **Tab discoverability on compact**: the jump bar keeps its `Ingredients` chip and gains no
  `Nutrition` chip (the tab row sits at the section top and scrolls into view with it). If real
  use shows the tab is missed, a jump-bar chip is a three-line follow-up
  (`recipe_detail_compact.dart:456-469` + a tear-off), not a redesign.
- **`includeIfNull: false` on the model's `toJson`** keeps stored json lean, but means a field
  can never be *explicitly cleared to null* field-by-field through a partial update — acceptable
  because saves always write the whole object (or SQL `NULL`), never a patch.

## Phase 29 — Auto nutrition: food registry, ingredient links, estimated labels

Roadmap: [ROADMAP.md Phase 29](./ROADMAP.md#phase-29--auto-nutrition-food-registry-ingredient-links-estimated-labels-planned--not-started)

**Status: DONE (29a–d, 2026-08-25).** Phase 28's first Deferred item, promoted to its own phase
after the data source question was answered by measurement rather than assumption.

**29d, as landed — the deltas from the plan below:**

- **The fixture split is 12 / 1 / 1, and which recipe got which is an argument, not a coin toss.**
  `fresh-guacamole` is the manual one because two of its six ingredient rows are "to taste"
  (`quantity: null`), so Automatic counts 4 of 6 — it is the recipe where a cook has an actual
  reason to type the numbers, which is what a fixture should demonstrate. `classic-margarita`
  stays null because its estimate is the honest failure mode of a raw-ingredient sum: four juiced
  limes and an orange count as whole fruit, so the drink comes out with 5.3 g of fibre. Shipping
  that as a label would have made the disclosure footnote carry more weight than it can.
- **The refresh path needed a guard the plan did not name.** `db:reset` and `database.yml`'s
  upgrade path both apply `0001_init.sql` *before* `nutrition_foods.sql`, so the on-apply
  backfill can genuinely run against an empty registry — where every label recomputes to null.
  `recompute_auto_nutrition()` therefore returns early when `food` is empty. Nothing to estimate
  *with* is not the same as nothing to estimate, and the difference is a silent data loss.
- **Recomputing to null is one-way, and that is left as documented behaviour.** A null label
  carries no `source`, so the row leaves the backfill's `where` clause permanently. The
  alternative — storing `{"source":"auto"}` alone as a marker — is exactly what `isEmpty` and the
  validator already reject, so there is nowhere to put the flag. Re-picking Automatic in the
  editor is the recovery.
- **A gate the pipeline was missing turned up while writing this.** `recipes:check` proves
  `seed_recipes.sql` matches `recipeData/`; **nothing** proved the numbers inside it still match
  `nutritionData/`. Now that twelve labels are estimator output, that gap is a live drift risk —
  edit a gram weight, ship the registry, forget to regenerate, and a fresh database seeds labels
  the estimator no longer agrees with. `supabase/tests/nutrition_fixtures.sql`
  (`melos run db:nutrition:verify`, wired into CI) closes it, and also covers the backfill itself:
  a corrupted auto label must come back, a manual label must not move, a deleted registry must
  blank nothing. Each of its four assertions was proven non-vacuous by reverting the code it
  covers — the BL-7 ritual applied outside the matrix.
- **No new bug.** The two placeholders were replaced, not fixed around; the estimator, the
  editor, and `save_recipe` were untouched.

**29c, as landed — the deltas from the plan below, so 29d consumes what exists:**

- **`estimate_nutrition` is pure over its arguments *and never reads `recipes` or
  `ingredients`.*** That is what lets the editor preview an **unsaved** draft: it passes the same
  trees `save_recipe` will persist, encoded by a new shared
  [content_payload.dart](../packages/core/lib/src/repositories/content_payload.dart) that both
  call sites use. A preview and a save can therefore never disagree about the tree — which is a
  stronger guarantee than "the arithmetic exists once", and it costs one more restatement site
  for a new ingredient column (now listed in CLAUDE.md's ingredient-column rule).
- **The provenance stamp is applied inside `estimate_nutrition`,** not by its callers, so every
  consumer of the arithmetic stores the identical shape. The RPC returns
  `{label, counted, total, unmatched}`; `label` is JSON null when nothing counted and the
  editor's warning branch keys on exactly that.
- **B075, found by the matrix before the feature shipped:** `estimate_nutrition(…) -> 'label'`
  yields `'null'::jsonb`, not SQL NULL, so an Automatic save with nothing countable aborted with
  `23514` against `recipes_nutrition_is_object`. Both `save_recipe` branches now wrap the
  recomputed value in `nullif(…, 'null'::jsonb)` — the same trap Phase 28 documented for the
  *incoming* payload, one layer deeper on the *outgoing* value. B22d was written before the
  branch was proven and went red on its first run, which is the argument for writing the matrix
  check first.
- **The update branch recomputes against the *effective* servings** — the payload's when sent,
  the row's when omitted — read `for update`, so a concurrent save of the same recipe cannot
  divide by a serving count the other transaction is about to change.
- **`match_foods` returns `[]` rather than omitting the key** for a name with no candidates:
  "looked, found nothing" and "never asked" are different answers, and the review list renders
  the difference.
- **The not-counted list derives its reasons locally** (optional / not linked / no quantity) from
  the draft and only takes *"unit cannot be converted"* from the RPC's `unmatched`, so the list
  is right the instant a row changes, before the next estimate lands.
- **Mode transitions carry the two rules the plan named**, and Auto → Manual seeds from the
  **fresh estimate**, not the stored label — editing a stale number would be the worse default.
- **Two defects caught in this change set's own review, both pre-ship.** **B076**: the ladder
  multiplied a negative `quantity` (storable — no positive check on the column, no validator on
  the editor's Qty box) and *subtracted* from the label, so it now skips `quantity <= 0` the way
  it skips null. **B077**: the estimate refreshed only on discrete events, while the Auto pane's
  empty state tells the cook to link foods *in the ingredient list below* — a different widget —
  and the servings field is the per-serving divisor; both now trigger a 500 ms debounced
  re-estimate. The lesson in both is the same: an estimate is only honest if it describes the
  draft in front of the user.
- **Matrix at 91** (was 89): B22c (smuggled `calories: 9999` stores the recomputed 100) and B22d
  (nothing counted stores SQL NULL), both proven non-vacuous by replacing the recompute
  condition with `if false then` and watching the fabricated value land in the column.
- **Estimator sanity against the real registry**, which no fixture can show: all 14 authored
  recipes produce plausible labels at high coverage, and every unmatched name is one of the
  documented vocabulary gaps. `seed.sql`'s demo recipes estimate 0/N — they predate 29b and have
  no links — which is worth knowing before 29d picks fixtures.

**29b, as landed — the deltas from the plan below, so 29c–d consume what exists:**

- **`food_id` is declared by `alter table … add column if not exists` after the registry
  tables** in `0001_init.sql`, not inline in `create table ingredients` — `ingredients` is
  created before `food` exists in the file's apply order, so the sketch's inline `references
  food` would fail every fresh apply. `ingredients_food_idx` serves the FK's
  `on delete set null` scan and 29c's estimation join.
- **The payload key is `food_id` everywhere except the authoring JSON**, where it is `food`
  (a slug the validator checks against `foods.json` via the new `loadFoodSlugs()`;
  `normaliseIngredientGroups` translates). `seed_recipe_v2`'s signature is unchanged — the
  key rides the existing jsonb argument, so no 42725 exposure, as planned.
- **`FoodRepository` grew a second method**: `displayNames(ids)` — a two-column `in.()` select
  used by the editor to label the link chips of a *loaded* recipe (the DB stores only the id;
  a label picked this session is kept in `EditIngredient.foodLabel`, session-only). Empty input
  makes no request.
- **Typeahead**: `RawAutocomplete` over the existing name controller + a `FocusNode` now owned
  by `EditIngredient`; 250 ms debounce, ≥ 2 chars, every failure (registry unreachable,
  signed-out) collapses to "no suggestions" — a hint surface, deliberately not routed through
  `friendlyError`. **Renaming does not clear the link** (surviving renames is the point of the
  per-row FK); only the chip's delete does. The chip sits on its own line under the row — the
  row was already at its width budget (B070) — and the envelope was re-run at 320/360/600 × 2.0
  with a long label.
- **Matrix at 89** (was 88): B22 now saves a linked ingredient and B22b reads `food_id` back —
  proven non-vacuous by nulling the `save_recipe` pass-through once (B22b alone went red).
- **137/147 recipeData rows linked** by a one-shot alias-matching script (77 distinct foods);
  the 7 unlinkable names match `nutritionData/README.md`'s documented gaps exactly. simData
  stays unlinked (29d's optional curation) but its generated docs now carry `food_id: null`
  explicitly, and the sim's ingredient insert passes the key through.

**29a, as landed — the deltas from the plan below, so 29b–c consume what exists rather than what
was sketched:**

- **`food_unit` is a fourth table** (not in the original three): units.json's SQL mirror, one row
  per accepted spelling (`spelling` PK → `unit_key`, `class`, `factor`; `''` is the bare-count
  marker). Added so 29c's `estimate_nutrition` reads a table the generator maintains instead of
  restating conversions in a function body. Covered by the same RLS/grant/matrix/drop treatment.
- **No `search_tsv` generated column on `food`.** The sketch's tsvector cannot reach
  `food_alias` (a generated column sees one row of one table), so `search_foods` ranks
  exact > prefix > trigram over `lower(display_name)` + `food_alias.alias`, with two `gin_trgm_ops`
  indexes and a total order ending in `f.id`. Returns `(id, display_name)` only.
- **Registry reads are signed-in-only** (`auth.uid() is not null` select policies; `anon` reads
  come back empty rather than erroring, and `search_foods` is revoked from `anon` outright).
- **foods.json carries a machine-owned `extracted` block per food** (per-100 g values, parsed
  portions with their source modifier, derived `grams_per_ml` + which portion derived it);
  authored top-level `per_100g` / `grams_per_ml` / `portions` win per map / value / unit key.
  `tool/nutrition.dart` owns the merge; both tools are bundle-free except `fdc:extract`.
- **Committed registry: 78 foods, 277 aliases, 174 portions.** All 104 distinct recipeData names
  mapped (137/147 ingredient rows linkable); the 7 unlinkable names are documented in
  `nutritionData/README.md`, including the proxy-mapping rule (`fdc_id` names the data source,
  not an identity claim — rice vinegar → cider vinegar's row, dijon → yellow prepared).
- **Matrix at 88** (was 79): section E, E1–E9. The registry write denial is double-locked
  (revoked grant AND zero-policy RLS), so the non-vacuity ritual had to remove both to see red.
- **B074 found during verification:** the documented B033 psql pipe mojibakes multibyte
  characters; the corrected byte-faithful form is `cmd /c "docker exec -i … < file"`. The local
  stack was rebuilt clean; probing the hosted project is an open owner action.

The ask, in product terms: the editor's nutrition panel becomes **Automatic / Manual / None**.
Automatic computes the per-serving label from the ingredients so the cook types nothing; Manual
stays exactly as shipped; None saves `null`. The estimate must be honest — marked on the label,
never presented as measured fact — and switching modes must never destroy data silently.

### What the data measured (2026-08-24, on the actual bundle)

The USDA FoodData Central CSV release of 2026-04-30 (public domain / CC0), 3.1 GB on disk at
`FoodData_Central_csv_2026-04-30/`. Every number below was measured with awk over the real files
before this plan was written, because the v1 feedback nearly shipped two wrong assumptions
(sugars id, added-sugars availability):

| label field | nutrient id | generic foods with a value (of 13,694) |
| --- | --- | --- |
| protein / fat / carbs / sodium | 1003 / 1004 / 1005 / 1093 | 13,543–13,649 (99%) |
| energy (kcal) | 1008, fallback 2047 → 2048 | 13,359 (98%) — the gap is Foundation foods |
| saturated fat / cholesterol / fiber | 1258 / 1253 / 1079 | 12,903–13,033 (94%) |
| total sugars | **2000** — *not* the deprecated 1063 (185 rows) | 11,443 (84%) |
| trans fat | 1257 | 4,289 (**31%**) — stays null-heavy, label omits null rows |
| **added sugars** | 1235 | **0** — exists only on branded label transcriptions |

"Generic" = `sr_legacy_food` + `foundation_food` + `survey_fndds_food`. Two exclusions, both
deliberate: `branded_food` (2.0M rows, 910 MB — barcode-specific, wrong shape for "1 cup flour",
and the only reason the bundle is 3.1 GB) and, from the *matching index*, FNDDS survey foods —
they are composite **dishes** (`chicken tikka masala` would match as an ingredient). That leaves
**8,262** usable foods, curated down to the ~400–600 the kitchen vocabulary actually needs; the
corpus (14 recipes + 25 dishes) contains **237 distinct ingredient names** today.

Portions: 13,044 of 13,694 foods carry ≥ 1 portion row, but SR Legacy sets
`measure_unit_id = 9999` and hides the real unit in the free-text `modifier` (`cup, chopped`,
`tbsp chopped`, `medium (2-1/2" dia)`) — needs its own parser at extract time. Foundation foods
often have **none**: `Flour, wheat, all-purpose, enriched, bleached` (fdc 789890) has zero
portion rows, so "1 cup flour" dies on the most common baking ingredient unless curation prefers
SR Legacy ids and keeps density overrides for staples. The corpus's own unit column is free text
with 25 distinct spellings, including `handful`, `pinch`, `bunch`, `pkg`, `large piece` and the
`clove`/`cloves`, `cup`/`cups` doublets — `nutritionData/units.json` canonicalizes them once.

### The decisions, and the alternatives they beat

1. **Link at input time; never match at save time.** The alternative — fuzzy-match ingredient
   names inside the save path — re-guesses on every save, so the same recipe could print
   different labels on consecutive edits, and a review step degrades into fatigue. Instead the
   ingredients editor gets a typeahead: picking a suggestion writes `ingredients.food_id`
   silently; typing past it leaves plain text. Inference survives only as `match_foods()`, a
   batched one-shot proposing top-3 candidates per **unlinked** name, human-confirmed in a review
   sheet when an old recipe first switches to Auto. Consistency comes from the link being a
   stored fact, not a repeated guess.
2. **Display name and identity are separate columns.** Cooks write `San Marzano tomatoes` and
   `00 pizza flour`; FDC writes `Tomatoes, red, ripe, raw`. Any design that normalizes the
   *rendered* name fights the product's first principle (the structure and readability of the
   recipe). `name` stays free text everywhere; `food_id` is invisible metadata.
3. **`ingredients.food_id` as a real column — not a name-keyed map in the nutrition jsonb.** The
   map variant is cheaper (zero column restatements) and was rejected because it is keyed by the
   one thing the cook is free to edit: rename `butter` to `unsalted butter` and the link dies
   silently; two `butter` rows in different groups collide. A per-row FK survives renames,
   duplicates, forks (deep copy copies it), and the editor's delete-and-reinsert save shape —
   *provided the draft carries it*, which is exactly the B035 obligation and its existing
   round-trip test. The full restatement cost, itemized: `fork_recipe`
   (`0001_init.sql:1799`), `save_recipe` (`:2044`), `seed_recipe_v2`'s insert (generated from
   [tool/recipes.dart:226](../tool/recipes.dart#L226)), the sim's insert
   (`2_sim_generate.sql:380`), [ingredient.dart](../packages/core/lib/src/models/ingredient.dart),
   `EditIngredient` in [edit_models.dart](../apps/app/lib/features/recipe_editor/edit_models.dart),
   both `schema.json`s, and the validator. The read side costs nothing — `kRecipeDetailSelect`
   embeds `ingredients(*)` ([recipe_queries.dart:56-58](../packages/core/lib/src/repositories/recipe_queries.dart#L56-L58)),
   and there is no ingredient-column test pin to move. `on delete set null`, so retiring a
   registry entry orphans links gracefully.
4. **Provenance rides *inside* the jsonb: `source: 'auto'`, absent = manual.** A `nutrition_source`
   column on `recipes` would cost one line in each of the ~13 writable-column copies Phase 28
   enumerated; a 12th jsonb key costs `RecipeNutrition`, `_nutritionKeys`, and nothing else.
   Absent-means-manual is what makes it migration-free: every label already saved and all ~1,320
   sim labels (which are *invented*, not computed — calling them `auto` would be a lie) read
   correctly without touching a row. `None` stays `null`; a Manual save with every box empty
   normalizes to `null` too — the mode collapse is deliberate, one representation per state.
   In Dart it is a plain `String?` with an `isEstimated` getter, not a Postgres enum (nothing in
   SQL switches on it) and not a nested model (B071 stays un-re-armed).
5. **Estimation arithmetic exists exactly once, in SQL.** `estimate_nutrition()` for the
   editor's preview; `save_recipe` calls the same internals when the incoming label claims
   `auto` — **discarding the client's numbers**, so fabricated "estimates" die at the one gate
   that sees the ingredient trees in the same transaction (the Gotcha 11 shape). The rejected
   alternative — a ChefScoring-style Dart mirror for live preview — buys per-keystroke latency
   nobody needs (matches change by discrete picks, not keystrokes) at the price of the Gotcha 19
   two-implementations tax. One RPC round-trip per match change is fine.
6. **The registry is committed, generated data; the 3.1 GB bundle is an authoring tool.** Two
   steps, deliberately split: `tool/fdc.dart` (**extract**) reads the CSVs from a path argument
   and writes per-100 g values + parsed portions *into* `nutritionData/foods.json`, run only when
   adding foods; `tool/nutrition.dart` (**gen**) turns the JSON into
   `supabase/nutrition_foods.sql` with no CSV in sight, so CI's `nutrition:check` works like
   `recipes:check`. Extract output is committed and human-reviewed, which is what lets the
   SR-Legacy modifier parser be imperfect — its mistakes surface in a readable diff, not in a
   label. The rejected alternatives: committing any CSV subset (opaque, unreviewable), or a
   runtime nutrition API (a network dependency + terms-of-service surface for data that never
   changes).
7. **A generic `Estimated from ingredients` footnote, not `from 14 of 16`.** The counted/total
   pair would be two more pinned keys in every copy of the key set, to print a number the editor
   already shows with names attached. `estimate_nutrition` still *returns* counted / total /
   unmatched — the editor renders them; the stored label carries only `source`.

### Schema, and the grams ladder

```sql
create table food (
  id            text primary key,          -- slug: 'all-purpose-flour'
  display_name  text not null,
  fdc_id        int,
  calories numeric, total_fat_g numeric, … protein_g numeric,   -- 11 per-100g columns, EAV flattened
  grams_per_ml  numeric,                   -- null = volume units unresolvable for this food
  is_added_sugar boolean not null default false,
  search_tsv    tsvector generated always as (…) stored
);
create table food_alias   (alias text, food_id text references food);
create table food_portion (food_id text references food, unit_key text, grams numeric);
alter table ingredients add column if not exists food_id text
  references food(id) on delete set null;
create extension if not exists pg_trgm;    -- 0001 has only pgcrypto today
```

RLS on all three, **select-only** for `authenticated`, zero write policies; grants block extended
(Gotcha 4 — both are required); `search_foods` / `match_foods` / `estimate_nutrition` revoked
from `anon` (Gotcha 3 — PostgREST exposes every public function; only the signed-in editor needs
them; the detail page reads the stored label).

Per-ingredient grams, in order, first hit wins — anything that falls through **contributes
nothing and is named in the editor's "not counted" list**:

1. skip outright: `is_optional`, no `food_id`, `quantity is null`
2. mass unit (`g`, `kg`, `oz`, `lb`) → direct conversion
3. volume unit (`ml`, `L`, `tsp`, `Tbsp`, `cup`, `fl oz`, `pint`) → × `grams_per_ml` when set
4. named portion (`clove`, `stick`, `bunch`, `large`, bare count) → `food_portion.unit_key`
5. unresolvable (`handful`, `pinch`, `to taste`) → skip

Then per 100 g × grams, summed, ÷ `recipes.servings` (the base count — Phase 28's per-serving
semantics, untouched). Added sugars = Σ total sugars of `is_added_sugar` foods (the measured 0%
means it can never come from data). Trans fat null when unknown — the label already omits null
rows. **Never guess a density**: a water default makes a cup of flour 236 g instead of 120 g,
which is worse than "not counted".

### Traps, named before they are written

- **The FK makes seed order load-bearing.** `seed_recipes.sql` will insert ingredients carrying
  `food_id`, so `nutrition_foods.sql` must apply first: `db:reset` becomes drop → create →
  **nutrition** → seed → recipes → sim, and `config.toml`'s `sql_paths` gains the file *before*
  `seed_recipes.sql`. The truly-clean path (B045) is the one that bites here — a machine that
  has never loaded the registry fails mid-`seed_recipes` with an FK violation, while every
  machine that ran 29a once stays green. `drop.sql` learns the three tables and the RPCs (B024's
  rule: the drop lives where a re-apply can find it).
- **`db:clean` must spare the registry.** It truncates *recipe* data; `food` is reference data
  with no user rows and survives, or every post-clean seed hits the FK trap above.
- **Source smuggling is a policy question, so the matrix owns it.** A client claiming
  `source: 'auto'` with fabricated numbers must find them discarded. `rls_matrix.sql` gains the
  check: save with `{source: 'auto', calories: 9999}` over known fixture trees, read back the
  recomputed value. Proven non-vacuous the BL-7 way — comment out the recompute branch once,
  watch it go red.
- **Auto with nothing counted must save `null`, loudly.** Zero linked ingredients → an all-null
  estimate → `isEmpty` → normalized to `null` → the recipe silently reopens as **None**. The
  editor warns inline before save instead of letting the mode collapse read as data loss.
- **`_nutritionKeys` and `RecipeNutrition` learn `source` in the same change** — the validator
  rejects unknown keys as hard errors today, so a generated fixture carrying `source` fails
  `recipes:validate` until both sides move. `isEmpty` must ignore it, or `{source: 'auto'}`
  counts as a label.
- **`seed_recipe_v2`'s signature does not change** — ingredients arrive inside the existing
  jsonb argument — so the B024 overload trap (42725) is *not* re-armed. Stated because Phase 28
  hit it and the reviewer will ask.
- **The typeahead re-opens the ingredient row's envelope** (Gotcha 26 / B070 — reuse is a reason
  to re-run it). A suggestion overlay plus a link chip inside a row that already holds quantity /
  unit / name at 320 px × 2.0× is exactly the crowded-Row shape of B038/B062.

### Order of work, and why

1. **29a — registry + pipeline first**, because everything else consumes it: `nutritionData/`,
   both tools, melos scripts, the tables + `search_foods` in `0001`, load order, matrix rows,
   and the 237-name corpus mapping. Ends with `db:reset` green on fresh, upgrade, *and* clean
   paths — no UI change yet.
2. **29b — links at input**: the `food_id` column with its full restatement list in one change
   set (the B035 test is the gate), the typeahead, the repository, recipeData slugs +
   `recipes:gen`. Ships alone: links accumulate value before any estimate exists.
3. **29c — estimation + modes**: `estimate_nutrition` + `match_foods` + the `save_recipe` auto
   branch + `source` + the editor's segmented control, review sheet, preview, and the label
   footnote. SQL before Dart within the stage, `nutrition_estimate.sql` before the editor
   consumes the RPC — the Phase 28 discipline (every later stage decodes what this stage
   returns).
4. **29d — fixture refresh + docs**: estimator output replaces the two all-10 placeholders,
   ≥ 1 manual + ≥ 1 null kept so all three states demo on seed; the idempotent
   recompute-on-apply backfill; SDS / CLAUDE.md / README / BL-5. Landed with one addition —
   `nutrition_fixtures.sql`, the drift gate that keeps those committed labels honest against the
   committed registry, which the plan had not identified as a gap.

### How it will be verified

- `melos run analyze` / `test --no-select` / `format`; `recipes:check` / `sim:check` /
  `nutrition:check` (grep for `SUCCESS`, B006/B007).
- `supabase db reset` fresh; the Gotcha 6 upgrade path; the B045 truly-clean path — named above
  as the one the FK ordering actually threatens.
- `melos run db:rls` — **29a landed the registry rows and RPC-grant checks (79 → 88, §E)**, each
  proven non-vacuous by one deliberate revert (BL-7 ritual; the registry's E2 needed *both* locks
  removed — grant and policy — which is the defense-in-depth working). The source-smuggling check
  is still 29c's.
- `supabase/tests/nutrition_estimate.sql` in `database.yml`: fixture trees with known grams →
  exact labels, the unit ladder edge cases (mass, volume-with-density, named portion,
  unresolvable, optional, null quantity, added-sugar rule), rolled back.
- `fake_supabase` request assertions for `search_foods` / `estimate_nutrition` bodies; the
  `EditIngredient.foodId` round-trip in the existing editor group; widget tests for the
  segmented control, the not-counted list, and mode transitions.
- Screenshots (B028): typeahead open, Auto pane with matches + not-counted, estimated label with
  footnote, × {light, dark}.
- What fixtures cannot show, said now: typeahead *feel* and real match quality — a manual
  local-stack pass, plus the review sheet exercised against an old unlinked recipe.

### Risks, stated

- **Curation is the long pole, not code.** Hand-mapping ~240 names (then ~600) to FDC ids with
  densities and portions is hours of judgment; `tool/fdc.dart` reduces it to review, not zero.
  Scope guard: corpus first, grow on demand.
- **Match quality is contained, not solved.** Human-at-input + reviewable backfill means the
  worst case is an *unlinked* ingredient and a smaller denominator — never a wrong number
  printed silently.
- **Cooking yield is permanently unmodelled.** Raw-ingredient sums ignore reduction, evaporation,
  drained frying oil; `retention_factor.csv` does not model moisture. The footnote is the
  disclosure, and no copy anywhere may call the estimate FDA-compliant.
- **Vocabulary gaps are ongoing** (`tikka spice blend` has no FDC row). The not-counted list is
  the honest surface; the mining loop that turns those names into curation candidates is named
  Deferred, not promised.
- **`pg_trgm` on hosted** — available on Supabase, but the extension create must be verified on
  the pooler path (B033) before the typeahead ships, not after.

## Phase OPT — Optimization & hardening

Roadmap: [ROADMAP.md Phase OPT](./ROADMAP.md#phase-opt--optimization--hardening-backlog-rolling) ·
Source: full design/architecture audit, 2026-08-20 (Dart + SQL sides audited independently, every
logged finding re-verified against the cited source before entering the backlog). New bugs from
the audit: **B050–B052** in [BUG-TRACKER.md](./BUG-TRACKER.md).

**How to work this phase.** It is a rolling backlog, not a sprint: pick from OPT-S first (each is
a live correctness/integrity hole), then OPT-P items as the sim makes them measurable, OPT-A
opportunistically alongside touching work, OPT-T as its own investment. Every SQL item follows
the standing rules — idempotent guards, upgrade-path verification (Gotcha 6), local stack before
hosted (B033 pooler form), `drop.sql`/B024 blocks for signature changes.

### OPT-S — Integrity & correctness

**OPT-S1 — column-level grants (B050) — DONE.** Landed as described below, with one addition the
plan did not anticipate: mirroring `_writablePayload` exactly meant `current_version_id` had to
leave the grant list, but `_appendVersion` was PATCHing it directly (CLAUDE.md called it
"trigger-maintained"; no such trigger existed). It is now genuinely server-owned via the
`recipe_versions_set_current` trigger, the Dart write is gone, and `2_sim_generate.sql` disables
that trigger for its bulk version load. Acceptance met on the local stack — see B050 in the
tracker for the full matrix. Original plan follows.
Mechanism: `grant insert, update, delete on all tables in schema public to authenticated`
(`0001_init.sql:796`) + row-scoped-only `recipes_update` (:666) / `profiles_update` (:656) means
an owner may `PATCH` any column of their own row — including `like_count`, `save_count`,
`view_count`, `rating_*`, and `profiles.chef_score/chef_tier/public_recipe_count`. The
`recipes_chef_stats` trigger then recomputes `chef_score` **from the forged counter**, laundering
it into the public leaderboard. Fix shape: in the grants block, replace the blanket `update` on
`recipes` and `profiles` with explicit column lists mirroring `_writablePayload` /
`ProfileRepository.updateMine` (title, description, cover, cuisine, category, difficulty, times,
servings, visibility, attribution, fork columns / display_name, avatar_url, bio). Notes:
`security definer` functions and everything run as `postgres` (seed, sim, triggers) are
unaffected; `insert` needs the same treatment or the counters are forgeable at creation
(`with check` cannot see columns, only rows — column grants are the correct layer). Acceptance:
on the local stack, as the owner, `PATCH /recipes?id=eq.…` with `{"like_count": 99999}` fails
`42501`; a normal editor save still round-trips; `chefs_leaderboard` unchanged after a re-apply;
upgrade-path apply is clean. Docs: SDS §4 gains the column-grant rule; review-checklist §2 gains
"a new client-writable column must be added to the column grant list".

**OPT-S1a — `recipes_select` must not re-query `recipes` (B053) — DONE.** Not in the original
backlog; found by OPT-S1's acceptance matrix. `recipes_select` was `can_read_recipe(id)`, a
`stable security definer` function that looks the row up **by its own id**. Postgres applies the
SELECT policy to `INSERT … RETURNING` rows and a `stable` function reads the statement snapshot,
so the just-inserted row was invisible and **every `create()` failed**. Nothing caught it because
seed/sim create as `postgres`. Fixed by inlining the policy against the row's own columns;
`can_read_recipe(uuid)` stays for the child tables, which pass a parent id. Verified across
anon / owner / unrelated / shared-user, plus the create path itself; 2.4× faster on a Discover
scan as a side effect.

**OPT-S2 — `.select()` on recipes update/delete — DONE.** An RLS denial matched 0 rows and
returned success (Gotcha 2); `update()` then re-persisted content while believing the parent row
saved. `update()`, `delete()`, and `unshare()` now append `.select()` and throw the new
`WriteDeniedException` on an empty result — in `update()` the check sits **before** the group
deletes, so a denied save can no longer destroy the recipe's content on its way out. `unshare()`
was added to the scope because it is the same one-line fix on the sharing path the checklist
already names; the like/save/rating deletes are keyed by `_uid`, so RLS cannot deny them and they
were left alone. Verified on the local stack: owner update/delete/unshare return a row, a
non-owner's return none. The editor's save already wraps the call in `try/catch`, so the throw
surfaces as a snackbar rather than an unhandled exception; `delete()`/`unshare()` have no UI
caller yet.

**OPT-S3 (B051) — DONE** and **OPT-S4 (B052) — DONE** — see the tracker entries for mechanism;
both were small, both sit on the product's core surfaces (detail, editor). S3 also closed the dead
`_CountAction.activeIcon` param by finally reading `myLiked`/`mySaved` state, added those two
methods to `RecipeRepository` (built on a shared `_hasMyRow`, `currentUser?.id`-based per
Gotcha 9), and routed the signed-out tap to `/auth`. Its regression suite —
`apps/app/test/recipe_detail_test.dart`, 5 tests — is the first slice of OPT-T3 and asserts the
repository is never reached signed-out. S4's half landed in `recipe_editor_test.dart` (4 tests):
a failed load renders `ErrorView` with no form and no Save button, retry recovers, and a
successful load leaves Save enabled.

**OPT-S5 — DONE.** The "Can edit" segment is `enabled: false` behind `notYetTooltip`, which
explains that shared editing is not built (`recipes_update` is `owner_id = auth.uid()`, so a
recipe shared "Can edit" is read-only to the recipient either way — the control promised an
access level the database does not grant). The helper moved from `features/chefs/chefs_hero.dart`
to `apps/app/lib/widgets/not_yet_tooltip.dart` rather than have `my_recipes` import out of
`features/chefs/`; `chefs_hero.dart` re-exports it so existing importers are unaffected. That
clears one of OPT-A3's cross-feature imports early.

**OPT-S6 — DONE.** `fork_recipe` opens with `if auth.uid() is null then raise`, and EXECUTE is
revoked from `public` (which is what PostgREST exposes) and `anon`, then granted back to
`authenticated`. Two independent locks: verified on the local stack that an `anon` call fails
`permission denied for function fork_recipe`, an `authenticated` call with no JWT fails
`must be signed in to fork a recipe`, and a real signed-in user still forks. Previously an
anonymous call reached the INSERT and died on `owner_id`'s not-null constraint — an accident of
the schema reported as a constraint violation, not an authorization failure.

**OPT-S7 — DONE.** B034's open half. `SUPABASE_DB_URL` is out of every dart-define file and into
`db-url.local.ps1`, dot-sourced per shell, template committed as `db-url.example.ps1`, both
covered by new `*.local.ps1` globs in `.gitignore`. The owner rejected a Windows user environment
variable — they run several projects against different databases, and a global value combined
with `tool/db.dart`'s missing prod guard (Gotcha 7) is how you drop the wrong database. Per-shell
and per-project is the safer shape and a `.ps1` cannot reach `--dart-define-from-file`. No
rotation needed: `git log --all -S` finds the credential in 0 commits.

**OPT-S8** is B018's open half. The script side is done and verified locally:
`supabase/scripts/rotate_seed_passwords.sql` re-`crypt`s all 16 seeded accounts to a random value,
keyed on the seed's fixed UUIDs (never a pattern — checklist §8), rotating rather than deleting
because `auth.users` → `profiles` → `recipes` cascades would otherwise destroy the Kitchen's 14
curated recipes and the demo ratings. **Applying it to the hosted project stays a manual owner
action** — it writes production `auth.users`, and `tool/db.dart` has no prod guard. Instructions
are in the script header. The item stays unchecked until that run happens.

### OPT-P — Performance & scalability

The sim (`medium`: 1,671 recipes, ~118k views, 1,000 profiles) turned three predictions into
measurables. Benchmark before/after each with `explain analyze` on the local stack at `medium`;
record numbers in the tracker when an item lands.

| ID | Mechanism (file:line) | Fix shape | Effort | Impact |
| --- | --- | --- | --- | --- |
| P1 ✅ | `recipes_search` evaluated `recipe_search_document()` — four subqueries — **twice per public recipe per search**; nothing indexable | **DONE.** `recipes.search_tsv` + GIN `recipes_search_tsv_idx`, backfilled on apply (guarded `where search_tsv is null`, so a re-apply is a no-op). **539.6 ms → ~1–2.5 ms, >200×**, same 304 matches. `recipe_search_tsv(uuid,text,text)` is the single definition and takes title/description as **arguments** — a BEFORE trigger cannot read its own row back on INSERT (the B053 trap). Child triggers are **statement-level with transition tables**, not row-level: one editor save re-inserts every ingredient and the sim bulk-loads tens of thousands. Five paths verified individually — title edit, ingredient insert, ingredient delete, **group cascade-delete** (the subtle one: the cascade removes ingredients before the group, so the ingredient trigger's join finds nothing — caught by the group trigger's own `recipe_id`), tag add/remove, and tag rename. Postgres rejects `update of name` with transition tables, so the tags trigger takes all UPDATEs and compares names in the body. Sim disables the three insert-side triggers and rebuilds set-based (`is null`-keyed, so it also catches forks); sim runtime unchanged at 9.2 s | M | HIGH |
| P2 ✅ | `recipes_trending` full-scanned + sorted all public recipes; `now()` in the score defeats any index | **DONE.** Bounded to `created_at > now() - interval '30 days'` + partial index `recipes_public_created_idx`. Measured at `medium`: trending **23.4 → 3.9 ms** (6.0×; rows scored 1,344 → 351), Recent **1.1 → 0.23 ms**, seq-scan-plus-sort → bare index scan. Note the index serves **Recent** directly; trending still seq-scans because 351/1,694 ≈ 21% is past the planner's crossover — its win is the smaller candidate set, and the index starts paying as the 30-day slice shrinks relative to the corpus. Trade-off recorded in the function comment: a project with no public recipe in 30 days gets an empty Trending tab, deliberately (seeds create at `now()`, so a fresh install never is) | S | HIGH |
| P3 ✅ | `getById` issued one query per ingredient/step group — 2+G+S round trips per open | **DONE.** One `kRecipeDetailSelect` embed with explicit ascending ordering at all four levels (`ingredient_groups`, `ingredient_groups.ingredients`, `step_groups`, `step_groups.steps` — postgrest-dart passes `referencedTable` through verbatim, so the doubly-nested form works). **4.69 → 1 request on average across public recipes, worst case 8 → 1.** The non-obvious prerequisite: `Recipe.ingredientGroups`/`stepGroups` had **no** `@JsonKey(name:)`, so the snake_case embed would have decoded to the empty default with no error — a silently empty recipe that `update()` then writes back (B035's family). `includeToJson: false` kept, so the version snapshot shape is unchanged. Verified two ways: 10 unit tests in `recipe_embed_test.dart` (decode, every column, empty group, int-vs-double numeric, `toJson` still excludes content), and a throwaway live harness that ran the real repository against the local stack over 60 recipes — order correct at all four levels, owner embed intact, then deleted per Gotcha 15 | M | HIGH |
| P4 ✅ | One save = 2 full `getById` cascades (`_appendVersion` re-read the recipe to build its snapshot, then `update()`/`create()` re-read it again to return) | **DONE.** 2 → **1**. `_appendVersion(Recipe, summary)` takes the recipe instead of an id. Deliberately the **post-save** read, not the caller's draft as the plan first suggested: `_persistContent` assigns fresh group/child ids and renumbers `sort_order` to the list index, so the draft would record ids that never existed. The live harness caught the consequence of the reorder — the single read happens *before* the version row exists, so the returned `currentVersionId` was stale (null on create). `_appendVersion` now returns the new version id and the caller `copyWith`s it, which keeps one read and an accurate return | S | MED |
| P5 ✅ | `chefs_leaderboard` re-aggregated all public recipes per page although scores are denormalized; `recompute_chef_stats` already computed the like/save/view totals and threw them away | **DONE.** `profiles.total_likes/saves/views` are written by the same statement that writes the score, so a total cannot disagree with the score it explains; the board reads all ten columns off `profiles` and aggregates nothing. **3.5 → 0.5 ms** warm at sim `medium` (52 ms cold, 480 buffers of `recipes` gone). Two things the plan did not anticipate: the same recompute UPDATE was restated in **three** files (backfill, `2_sim_generate.sql`, `9_sim_teardown.sql`), so it became `recompute_all_chef_stats()` — three new columns in one place instead of three, and Gotcha 19 enforceable; and the win is not the index — at 172 chefs in 26 pages the planner still prefers a seq scan, and `profiles_leaderboard_idx` (all four ordering keys, partial on `public_recipe_count > 0`) takes over only as `profiles` grows. Verified: totals move with a like and revert on unlike, backfill drift = 0 rows, all sim assertions pass including the new **A6b** | M | MED |
| P6 ✅ | `recipe_likes`/`recipe_saves` PKs lead with `user_id`; no recipe-leading index existed | **DONE.** `recipe_likes_recipe_idx` / `recipe_saves_recipe_idx` on `(recipe_id, created_at desc)`. "Who liked recipe X, newest first": seq scan over 6,483 rows + top-N sort → bare index scan with the **sort eliminated** (0.189 → 0.081 ms; at this size the ms are small, the point is the plan is now O(matching) not O(table)). `created_at` second so one index serves both the by-recipe read and Phase 23's dated windows. Verified the PK still serves the write paths (`myLiked`, unlike) — no regression | S | MED |
| P7 ✅ | `recipeProvider` body called `logView` — every invalidate (like, rate, save) logged another append-only view row | **DONE.** Extracted to `recipeViewLoggerProvider`, an `autoDispose` family the screen **watches**: alive for the visit, untouched by the recipe invalidations, re-run on the next entry. Swallows its own errors — a failed view log must not put the detail screen in an error state. `view_count` was never wrong (B012 counts a user's first row only), but the log rows were real waste. 3 tests: one visit = 1 log, three engagement writes still = 1, signed-out still logs | S | MED |
| P8 ✅ | Search RPC per keystroke — typing "chicken" issued 7 `recipes_search` calls and used 1 | **DONE.** `kSearchDebounce` = 300 ms, `Timer` + `Completer` + `ref.onDispose`: the next keystroke disposes the build, cancels the timer and returns before touching `ref`, so a superseded query never reaches the network rather than arriving late. Empty query short-circuits without waiting, matching the repository. 4 tests, including the one that matters — seven keystrokes 20 ms apart issue **zero** searches until the pause, then exactly one | S | MED |
| P9 ✅ | No pagination: Discover capped 20/30 with no way to reach row 21, `listMine`/`listSharedWithMe` unbounded | **DONE.** All six surfaces page by `kRecipePageSize` (20) behind an explicit **Load more** (owner's call over infinite scroll). `p_offset` on `recipes_popular`/`_trending`/`_search` — each an argument-list change, so each carries its B024 `drop function` in `0001_init.sql` and both signatures in `drop.sql`. The non-obvious half is ordering: `offset` is meaningless over a partial order, so every order-by now ends in `created_at desc, id` (`ts_rank` in particular produces long runs of ties, and a swap between page 1 and page 2 shows one recipe twice while hiding another). Verified on the local stack — page 1 ∪ page 2 is exactly the 40-row single read, in the same order, zero overlap, for all three RPCs plus Recent over real PostgREST. Client state is `PagedRecipesNotifier` (core) — `hasMore` = "the last page came back full", `loadingMore` inside the data so rows stay on screen, incoming duplicates dropped by id, a failed page rethrows without touching the list. Departs from the `leaderboardPagesProvider` precedent deliberately: re-reading 25 ranked leaderboard rows is cheap, re-reading 100 recipe rows with their owner embed to add 20 is not. Took `RecipeAsyncGrid` with it (OPT-A7's grid item) rather than write the Load more control twice. 7 tests | M | MED |
| P10 ✅ | `/chefs` hero = 6 count queries; `chefDetailProvider` awaited profile then top-recipes sequentially | **DONE.** `chefs_tier_counts()` returns one row per tier (`unnest(enum_range(...))` + left join, so empty tiers still appear); **6 → 1 request**. `chefCount()` is gone from the repository entirely rather than kept alongside: it covered the same population, so the total is the sum — `chefCountProvider` derives it and the four call sites share the single fetch. `ChefTier.fromWire` added as the inverse of `wireValue`, since the RPC returns a bare enum label rather than a model. Detail pair now starts both futures before awaiting either; kept `catchError` instead of `Future.wait` so a missing `chef_top_recipes` still costs one section, not the dialog. Verified the RPC matches the old per-tier counts exactly and is `anon`-callable over real PostgREST; a new test pins that the fake's tier counts sum to its board total, which is what makes the derivation legitimate | S–M | LOW |
| P11 | Every like/first-view = full `recompute_chef_stats` over the owner's recipes (:516-522) — accepted in SDS §10.3 | Revisit (debounce/queue) only when measured hot; noted so growth work prices it in | L | deferred |

### OPT-A — Architecture & code quality

The audit's headline: **the layering holds.** Zero UI→Supabase leaks, no `src/` deep imports,
every repository behind its contract, providers hand-written and correctly placed. The items
below are targeted, not structural.

- **A1 — atomic `save_recipe` — DONE** (the phase's one structural item). One `security definer`
  function does create-or-update + content replace + version append in a single transaction, with
  the `fork_recipe` authorization shape: `auth.uid()` check, then `owns_recipe(p_recipe_id)` —
  the same predicate `recipes_update` uses — then EXECUTE revoked from `public`/`anon` and granted
  to `authenticated`. Both refusals raise `42501`; the repository translates that back into
  `WriteDeniedException` so OPT-S2's contract survives the rewrite.
  - **Three things it closed:** the content-loss window (Gotcha 11 — delete-then-reinsert is now
    uninterruptible), the `version_number` race (`max + 1` is read after the update takes the row
    lock, so a concurrent save waits and then sees it), and the round trips — a recipe with 3
    ingredient groups and 4 step groups cost ~10 requests and now costs 2 (the call, plus one
    `getById` for the return value).
  - **`recipe_snapshot(uuid)`** was not in the plan but the version row now has to be written
    server-side, so the snapshot had to be too. `to_jsonb(row) - 'search_tsv'` rather than a column
    list, so a column added later cannot silently fall out of the snapshot. It also repaired
    `fork_recipe`, which stored a literal `'{}'` — a version row recording nothing — because
    hand-assembling that JSON in SQL had not been worth it before.
  - **The new maintenance obligation:** the writable-column set now exists in three places (grants
    block, `_writablePayload`, `save_recipe`). CLAUDE.md Gotcha 11 and the review checklist were
    rewritten around this; the `save_recipe` copy is the one that fails *silently*, because an
    absent key simply never saves.
  - **Verified end to end** with a throwaway harness against the local stack (Gotcha 15), deleted
    after the run along with its two throwaway accounts: create round-trips every column and
    writes version 1 with a real snapshot; an edit that reorders groups replaces content, keeps
    list order as `sort_order`, and appends version 2 parented to version 1 with the pointer
    moved; a non-owner's save raises `WriteDeniedException` and leaves the title untouched; a
    signed-out save is refused. A fork's snapshot was checked separately in SQL — it now carries
    the recipe, both group arrays, and no `search_tsv`.
- **A2 — dead code — DONE.** `features/home/home_screen.dart` (185 lines) deleted; the directory
  went with it. Nothing imported it — `widget_test.dart` already pins that `/` is a redirect with
  no page of its own (B046).
- **A3 — cross-feature imports — DONE.** `share_dialog.dart` moved to `apps/app/lib/widgets/`,
  beside `not_yet_tooltip.dart`, which OPT-S5 had already hoisted out of `features/chefs/` for the
  same reason. Note the direction the old import pointed: `recipe_detail` reached into
  `my_recipes` for a dialog `my_recipes` itself never opened. Sign-out is now
  `ref.read(authRepositoryProvider).signOut()` at both call sites rather than a new
  `signOutProvider`: the plan offered a provider as one option, but a provider that wraps one
  repository call in a closure is indirection with nothing in it — every other command in the app
  (`share`, `setLiked`, `setRating`) is already a direct repository read from the widget.
  `AuthController.signOut()` was deleted with its last caller; the controller keeps exactly the
  two submissions whose `AsyncValue` the auth form renders.
- **A4 — error surfaces — DONE.** `friendlyError(Object?)` in `core/src/friendly_error.dart`,
  used at all 14 surfaces that had an `e.toString()` in them. Mapped: `PostgrestException` by
  code (42501 → "You do not have permission to do that", 23505/23503/23514, PGRST116 → not found,
  PGRST301 → session expired, PGRST202 → "not available on the server yet" — the RPC-missing case
  `chefDetailProvider` already handles by hand), `WriteDeniedException` (which gained a `message`
  getter so the sentence exists without the class name), `StorageException`, the signed-out
  `StateError`, timeouts and socket failures, everything else to one generic line. `AuthException`
  is deliberately **passed through**: GoTrue's messages ("Invalid login credentials") are already
  written for end users, and a switch over them would go stale silently the next time one is
  reworded. Network detection matches the runtime type **name** rather than importing
  `dart:io`/`http` — `SocketException` does not exist on web, and this package declares neither
  dependency. The mapper logs the raw error, so no call site does; 8 tests assert the property
  that matters, that no exception dump reaches the string.
- **A5 — share lookup correctness — DONE.** `findByEmailOrName` is now `searchByName(query,
  {limit})`: `%query%`, up to 8 rows, ranked in Dart as exact → prefix → contains (PostgREST
  cannot order by "is this an exact match"), tie-broken by name then id so the list is stable
  between calls. LIKE wildcards in the query are escaped — `_` alone would otherwise match any
  character — and the escaping was verified against the local stack, not assumed. The dialog does
  the disambiguating: 300 ms debounce (Discover's number, same reason), matches listed with avatar
  and **tier**, which is the only other thing a `profiles` row carries to tell two identical names
  apart; you are filtered out of your own results; a lone match is pre-selected; and Share is
  disabled until someone is chosen — there is no defensible "just share with whichever". The name
  also changed because it was a lie: `profiles` has no email column, and nothing ever matched one.
  6 tests, which also close OPT-T3's share-dialog item.
- **A6 — schema nits — DONE**, one local-stack pass, applied twice for idempotency:
  - **avatars delete policy**, same folder rule as the other three. Without it a replaced avatar
    stayed in a *public* bucket at a guessable path for the life of the project.
  - **`drop function if exists chefs_leaderboard(int, int)`** before its `create or replace`. Not
    load-bearing yet — the signature has never changed — but adding it *after* the ambiguous-
    overload failure means editing a database that already has two (B024).
  - **`recipe_versions_recipe_idx` dropped**: `unique (recipe_id, version_number)` already leads
    with `recipe_id`. Confirmed rather than assumed — `versions()`'s query plans as an *Index Scan
    Backward* on the unique index.
  - **The two deferred FKs are now added only when missing.** The old unconditional drop-and-re-add
    revalidated every row in `recipes` on every apply — work that grows with the table for a
    constraint that never changes.
  - **`tags` decision: free tags stay.** They are unowned by design; owner-curated tags would mean
    a tag row per owner and a discovery surface that cannot join them. What was missing is a way
    back out, so DELETE is now allowed **only for a tag nothing references** — that `not exists` is
    the safety property, since deleting a tag in use would cascade `recipe_tags` rows out of other
    people's recipes and rewrite their search documents. UPDATE stays closed for the same reason
    (a rename rewrites every carrier's document). Verified under `set local role authenticated`:
    an orphan tag deletes, an in-use tag survives the identical statement.
- **A7 — dedupe — DONE.** `StorageService._upload(bucket, …)` replaces two bodies that differed
  by a bucket name; the `<uid>/` prefix now has one definition, which matters because every
  storage policy on both buckets keys on it. The AsyncValue→Loading/Error/Empty/`RecipeGrid`
  scaffold became `RecipeAsyncGrid` under OPT-P9 rather than being copied a third time around the
  Load-more footer. The two hand-rolled date formatters moved to `core/src/formatting.dart` as
  `monthYear` and `isoDate` — kept as **two** functions, not merged: a "joined" line wants a
  readable month and a version history wants a sortable ISO column, and that difference is the
  reason each widget rolled its own in the first place. 2 tests.
- **A8 — file size + literals — DONE.** Three splits, all pure moves — a widget changed file, not
  behaviour, and the private helpers that only one panel uses stayed private in their new homes:
  - `recipe_editor_screen.dart` **880 → 418**: `cover_picker.dart`, `ingredients_editor.dart`,
    `steps_editor.dart`. The two sub-editors stay stateless and keep reporting every mutation
    through `onChanged` — the draft still lives in one state object, which is what makes the split
    safe.
  - `recipe_detail_screen.dart` **629 → 311**: `rating_section.dart`, `recipe_content_views.dart`
    (the ingredient/step renderers — the largest block, and it depends on nothing but the models),
    `detail_chips.dart`.
  - `chef_detail_sheet.dart` **597 → 231**: `chef_score_panel.dart`, `chef_recipes_panel.dart`,
    `chef_detail_common.dart` (the kicker and note both panels share).
  Route literals: the three in the route table became `Routes.newRecipe` /
  `Routes.recipePattern` / `Routes.editRecipePattern` — the pattern constants are new, since
  `Routes.recipe(id)` builds a path and cannot declare one. The split also surfaced three literals
  the plan had not listed, in `chef_recipes_panel.dart` and twice in the editor
  (`context.go('/recipe/${...}')`), which are exactly the "rename silently misses" case and now
  call `Routes.recipe(...)`.
- **A9 — migration split — DONE**, and narrower than the name suggests, on purpose.
  `supabase/migrations/` is now a **numbered sequence**: `0001_init.sql` is the frozen baseline,
  the next schema change is `0002_*.sql`, and `melos run db:create` applies every file in the
  directory in filename order rather than the one hard-coded path. **Partially reversed
  2026-08-23** (owner): pre-release, the baseline is editable again and Phase 26's shelves went into
  0001; the directory machinery is unchanged and the freeze resumes once the schema ships anywhere
  real. The hosted procedure in
  `README.md` changed from "paste 0001" to "apply the new file", which is what actually stops the
  every-apply cost: the profile backfill and the chef backfill recompute whole tables, and shipping
  an unrelated one-liner used to re-run both. (The FK revalidation that was the third item on this
  list is already gone — OPT-A6 guarded it.)
  **What was deliberately not done:** chopping the baseline's 1,900 lines into a dozen files. That
  buys tidiness and costs a real property — a single idempotent file that `db:create`,
  `supabase db reset`, and the dashboard paste all treat identically — for a database whose
  existing installations are already exactly what that file produces. Freezing it is the same
  outcome with none of the risk.
  `supabase/migrations/README.md` is new and carries the rules the split has to survive on:
  numbering, never editing a released file, keeping every statement guarded (nothing here tracks
  history — `db:create` re-applies the directory), B024 drops living in the file that recreates the
  function, grants-and-policies shipping with a new table, and verifying on the upgrade path rather
  than a fresh reset. CLAUDE.md Gotcha 5 and the review checklist's §4 were rewritten to match.

### OPT-T — Tests, tooling & process

- **T1 — the CI database job — DONE.** `.github/workflows/database.yml`, a separate workflow
  gated on `supabase/**`, `recipeData/**`, `simData/**`, `tool/**` so a Dart-only PR does not pay
  for it. `supabase start` inside the runner (minus studio/realtime/storage/imgproxy/edge/
  logflare/vector/supavisor) because plain Postgres cannot apply the baseline —
  `profiles.id → auth.users`. Three paths, in one job so they share the stack:
  1. **Fresh:** drop → every migration → `seed.sql` → `seed_recipes.sql` → sim `tiny` →
     `3_sim_verify.sql`'s 43 assertions.
  2. **Re-apply:** the whole sequence again on top of itself. Every file in this repo claims
     idempotency; nothing checked it before.
  3. **Upgrade path** (Gotcha 6): the **previous** revision of `0001_init.sql`, found with
     `git log -n 2 -- <path>` rather than a tag that does not exist, applied to a dropped
     database, then today's on top. This is the path a deployed project takes and the one B024
     shipped through — both easy paths were green.
  Then a smoke step calling the five RPCs the app actually calls.
  **No secret, and none may be added** — every statement runs against the runner's ephemeral
  stack at the CLI's fixed local address. `tool/db.dart` has no prod guard (Gotcha 7), so a
  `SUPABASE_DB_URL` secret in CI would point `drop.sql` at whatever that secret is; the workflow
  header says so.
  Verified by running the identical sequence against the local stack (the runner itself cannot be
  exercised from here): all three paths clean, `ALL CHECKS PASSED` on the tiny population, the
  five RPCs answer. That run is also what found **B054** — `db:reset` leaves the sim registry
  pointing at a population `drop.sql` deleted, which fails the sim's own assertions. Logged, not
  fixed: the fix makes `db:reset` delete `auth.users` rows and is the owner's call.
  **T1a — the RLS matrix step (BL-7, 2026-08-23).** Every step above runs as `postgres`, which
  bypasses policies, so the job could not have caught B053 and did not catch B061. A fourth step,
  straight after the fresh apply, runs `supabase/tests/rls_matrix.sql`: three throwaway
  `auth.users`, a private and a public recipe with content, 76 checks re-run under
  `set local role authenticated` + `request.jwt.claims`, then `rollback` — so it leaves the
  database exactly as the step before it did and the sim step behind it is unaffected. Also
  available as `melos run db:rls`. Detail and the covered matrix: ROADMAP BL-7 / SDS §4.1.
- **T2 — repository unit tests — DONE**, and the blocker turned out to be the wrong shape of the
  question. Nothing needs to mock `SupabaseClient`: it accepts an `httpClient`, so
  `packages/core/test/support/fake_supabase.dart` slides a recording `BaseClient` underneath it —
  no new dependency (`mock_supabase_http_client` was not needed), no live database, and the
  assertion surface is the request itself. `signInAs` signs in **offline** through
  `recoverSession`, which only touches the network for an expired session; that is what makes the
  `_uid`-dependent methods testable.
  14 tests over `recipe_repository.dart` and `discover_repository.dart`, aimed at the contracts
  this repo has actually broken rather than at coverage: the `kRecipeSelect` FK hint and its
  explicit column list (no `search_tsv`), **B022's four ascending embed orders** — which arrive as
  four namespaced `<table>.order=` parameters, not one repeated one — OPT-P3's single request per
  open, OPT-P9's `limit`/`offset` plus the `id` tie-break that makes an offset mean anything,
  OPT-A1's one `save_recipe` call carrying only writable columns and content as arrays whose
  position *is* `sort_order`, the `42501` → `WriteDeniedException` translation with no follow-up
  read, and the signed-out paths (`myLiked` / `mySaved` / `myRating` answer without a request,
  `logView` sends a null `user_id`, `listMine` throws before the network).
  What it deliberately is not: a PostgREST emulator. Responses are canned, so these prove the
  client's half of the conversation and the decode — not that Postgres would agree. That is what
  the local-stack harnesses and (next) the CI database job are for.
- **T3 — widget tests — DONE**, all four items. Recipe-detail interactions landed with OPT-S3 and
  ShareDialog with OPT-A5; this item added the last two:
  - **`snapRating`** (`packages/core/test/rating_test.dart`, 4 tests). The valuable one is the
    property, not the samples: every input from 0.00 to 6.00 in hundredths must come back inside
    `[0.5, 5.0]` **and** on a half-star step, because this function is the client half of a SQL
    check constraint — a value that slips past it fails as `23514` at the moment someone taps a
    star. Zero is the specific trap: a star widget that reports "unrated" as 0 must not send 0.
  - **The auth screen** (`apps/app/test/auth_screen_test.dart`, 6 tests), driven through the real
    router rather than a bare pump. That is not ceremony — `_submit` calls `context.canPop()`,
    which asserts without a `GoRouter` in the tree, so a bare pump cannot reach the success path
    at all, and `?mode=signup` only means anything through the route. Pinned: each door opens its
    own side, the toggle still owns the mode afterwards, an invalid form never reaches the
    repository, a successful sign-up sends the display name and lands on Discover, and a rejected
    sign-in shows `friendlyError`'s sentence and **stays on `/auth`**.
  Discover already had `discover_search_test.dart` (OPT-P8) and `paging_test.dart` (OPT-P9).
- **T4 — toolchain debt — 2 of 3 DONE.**
  - **`pubspec.lock` committed** (B009), all four. Resolution was previously free to differ
    between machines and between days, which is the root cause of "B005 appeared suddenly": the
    same commit could pull a different `analyzer`. A dependency change is now a reviewable diff.
  - **`sdk: ">=3.7.0"`** in all four pubspecs plus one whole-repo reformat (103 files). `dart
    format` picks its style from the *package's* language version, so under 3.4 it emitted the
    legacy short style and stripped the trailing commas `require_trailing_commas` demands — format
    and analyze could not both be satisfied (B027). Verified in the order that matters:
    `melos run format` **then** `melos run analyze` → SUCCESS, and all 281 tests still pass. The
    bound is now load-bearing in the other direction: lowering it re-arms the trap.
  - **`freezed` 3.x deferred**, tracked as OPT-T4c. It is a breaking model-syntax migration across
    every `@freezed` class plus a `build_runner`/`analyzer` bump, and its only prize is unpinning
    Flutter — which nothing currently needs, and which the pin exists to prevent (B005). Landing it
    at the tail of a large batch, where a regression would be attributed to the wrong change, is
    exactly what "its own change set" was warning against.
- **T5 — screenshots — DONE**, and it paid for itself on the first image.
  `npx playwright install chrome` **fails on this machine** — "Failed to install Google Chrome…
  re-running as Administrator may help" — so branded Chrome is still missing and the Playwright
  **MCP** browser (which is configured for `chrome`) still cannot start. That does not block the
  pass: Playwright's bundled Chromium is already installed, and
  `npx playwright screenshot --browser chromium` drives it fine. Procedure unchanged from B028:
  `flutter build web --release --dart-define-from-file=env.local.json`, `npx serve -l 8099
  build/web`, hashed deep links (`#/discover`).
  Covered: Discover at 390 / 700 / 1400, `/chefs` at 1400, a recipe detail at 1000. Two bugs, both
  of the class this pass exists to catch — neither could fail a widget test:
  - **B055**: the tier chip on a card cover resolved its colour from the *page's* brightness, so a
    dark light-mode shade landed at 14% alpha on a black scrim. Nothing overflowed; the tier was
    simply illegible. Fixed, with a regression test on the resolved colour, and re-shot to confirm.
  - **B056**: like/save counters rendered ungrouped (`1500` next to the chef card's `1,500`).
  `/chefs` v3 itself came out clean — hero, tier tiles, tied ranks sharing a number, the score
  breakdown, and `1 recipe` in the singular (B031 holding).
- **T6 — `tool/db.dart`**: pass `-1` (single transaction) for `db:create`/`db:seed`/`db:recipes`
  so a mid-file failure rolls back instead of leaving half-applied DDL; the sim files manage
  their own transactions and are exempt.

### Phase OPT — closed (2026-08-22)

26 of 29 items done. The three that remain are not scheduled work and moved to
[ROADMAP § Backlog](./ROADMAP.md#backlog--deferred-not-scheduled): **OPT-S8** (BL-1, an owner
action against production `auth.users`), **OPT-P11** (BL-2, accepted debt with a stated revisit
trigger), **OPT-T4c** (BL-4, `freezed` 3.x, its own change set). **B054** joins them as BL-3 — it
needs a decision on whether `db:reset` may delete `auth.users` rows, not a patch. Pick further work
from the Backlog or from Phase 25, not from this phase.

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
- **DB tasks:** `melos run db:create | db:seed | db:clean | db:drop | db:reset | db:rls` via
  `tool/db.dart` (needs `psql` + `SUPABASE_DB_URL`). Scripts in `supabase/scripts/`; the RLS
  acceptance matrix in `supabase/tests/`.

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
