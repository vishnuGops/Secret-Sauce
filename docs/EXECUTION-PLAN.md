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
and `3_sim_verify.sql` passes all 30 assertions.

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
| P5 | `chefs_leaderboard` (:955-964) re-aggregates all public recipes per page although scores are denormalized; `recompute_chef_stats` (:471-481) already computes the like/save/view totals and throws them away | Persist `total_likes/saves/views` on `profiles` in the same recompute; board becomes a pure indexed scan; partial index `where public_recipe_count > 0` | M | MED |
| P6 ✅ | `recipe_likes`/`recipe_saves` PKs lead with `user_id`; no recipe-leading index existed | **DONE.** `recipe_likes_recipe_idx` / `recipe_saves_recipe_idx` on `(recipe_id, created_at desc)`. "Who liked recipe X, newest first": seq scan over 6,483 rows + top-N sort → bare index scan with the **sort eliminated** (0.189 → 0.081 ms; at this size the ms are small, the point is the plan is now O(matching) not O(table)). `created_at` second so one index serves both the by-recipe read and Phase 23's dated windows. Verified the PK still serves the write paths (`myLiked`, unlike) — no regression | S | MED |
| P7 | `recipeProvider` body calls `logView` (`recipe_detail_providers.dart:7-14`) — every invalidate (like, rate, save) logs another append-only view row | Log once per screen visit from the screen's `initState`/first-build listener | S | MED |
| P8 | Search RPC per keystroke (`discover_providers.dart:19-22`) | ~300 ms debounce in the provider (`Timer` + `ref.onDispose`) | S | MED |
| P9 | No pagination: Discover capped 20/30, `listMine`/`listSharedWithMe` unbounded (`discover_repository.dart:23-56`, `recipe_repository.dart:95-102`) | `limit`/`offset` params + load-more; `leaderboardPagesProvider` is the in-repo precedent | M | MED |
| P10 | `/chefs` hero = 6 count queries (`chef_repository.dart:66-99`); `chefDetailProvider` awaits sequentially (`chefs_providers.dart:121-123`) | `chefs_tier_counts()` RPC returning 5 rows (PostgREST can't `group by`; an RPC can); `Future.wait` the detail pair | S–M | LOW |
| P11 | Every like/first-view = full `recompute_chef_stats` over the owner's recipes (:516-522) — accepted in SDS §10.3 | Revisit (debounce/queue) only when measured hot; noted so growth work prices it in | L | deferred |

### OPT-A — Architecture & code quality

The audit's headline: **the layering holds.** Zero UI→Supabase leaks, no `src/` deep imports,
every repository behind its contract, providers hand-written and correctly placed. The items
below are targeted, not structural.

- **A1 — atomic `update()`** (the one structural item): today `update()` deletes all groups then
  re-inserts (`recipe_repository.dart:150-152`); a failure between the two loses the recipe's
  content (Gotcha 11), and `_appendVersion` computes `version_number` client-side (read-then-
  insert race). Fix: one `save_recipe(...)` Postgres function — update row, replace content,
  append version — in a single transaction, `security definer` **with** an explicit
  `owns_recipe()` check first (the `fork_recipe` pattern), EXECUTE granted to `authenticated`
  only. Closes P4's cascade too when it lands; do it after OPT-S1 so the function is written
  against the tightened grants.
- **A2 — dead code**: `features/home/home_screen.dart` (185 lines) survived its route's
  retirement (B046). Delete; `widget_test.dart` already pins the redirect.
- **A3 — cross-feature imports**: `recipe_detail` imports `my_recipes/share_dialog.dart`
  (shared surface → `apps/app/lib/widgets/`); `top_nav_bar.dart` + `profile_screen.dart` import
  `features/auth/auth_controller.dart` for sign-out (hoist a `signOutProvider`, or move the
  controller beside `myProfileProvider` in core's providers).
- **A4 — error surfaces**: screens render raw `e.toString()` (PostgREST codes, `AuthException`
  dumps) in `ErrorView`/snackbars across discover/my/auth. One `friendlyError(Object)` in core,
  used everywhere; keep the raw error in `debugPrint`.
- **A5 — share lookup correctness**: `findByEmailOrName` (`profile_repository.dart:25-34`) is an
  exact `ilike` (no wildcards) with `limit(1)` on a non-unique display name — "share with Dara"
  can pick the wrong Dara silently. Return a ranked list, `%query%` match, ShareDialog
  disambiguates.
- **A6 — schema nits** (one local-stack pass together): avatars bucket delete policy (parity
  with recipe-images :836); `drop function if exists chefs_leaderboard(int, int)` before its
  `create or replace` (:939 — latent B024); drop redundant `recipe_versions_recipe_idx` (:106 —
  the unique at :104 covers it, the `recipe_views_recipe_idx` precedent); guard the FK
  drop/re-add (:109-117) behind a `pg_constraint` existence check (today every apply rescans
  `recipes`); `tags` write policy (insert-only by any authenticated user, no update/delete —
  decide owner-curated vs. free tags before Phase 25 makes tags discovery-relevant).
- **A7 — dedupe**: `StorageService`'s two identical upload bodies → `_upload(bucket, …)`; the
  AsyncValue→Loading/Error/Empty/`RecipeGrid` scaffold duplicated between Discover and My
  Recipes → one `RecipeAsyncGrid` in `apps/app/lib/widgets/`; the two hand-rolled date
  formatters (`chef_detail_sheet.dart:62-68`, `version_history_sheet.dart:54-55`) →
  `core/src/formatting.dart`, which already declares itself the home for this.
- **A8 — file size + literals**: split `recipe_editor_screen.dart` (826 lines — the two
  sub-editors are natural seams), `chef_detail_sheet.dart` (606), `recipe_detail_screen.dart`
  (561); replace the literal `'/recipe/new'` / `'/recipe/:id/edit'` in `app_router.dart:83-97`
  with `Routes` constants (the one place a rename silently misses).
- **A9 — migration split**: `0001_init.sql`'s every-apply work (profile backfill :264-268, chef
  backfill :526-546, FK revalidation :109-117) grows linearly with hosted data; the file header
  already promises versioned migrations "once there is real data". Do the split **before**
  Phase 25 adds tables; the B024 rule (drops live in the file that recreates the function)
  must survive the split.

### OPT-T — Tests, tooling & process

- **T1 — the CI database job** (Phase 11 item 2 + Phase 24's deferred item, folded): GitHub
  Actions service running the Supabase stack (plain Postgres cannot apply `0001_init.sql` —
  `profiles.id → auth.users`), then `0001_init → seed → seed_recipes → sim tiny →
  3_sim_verify.sql`, twice (idempotency), plus the Gotcha-6 upgrade-path variant
  (`git show <last-release>` base first). ~2–3 min per run. This single job covers the trigger/
  RLS/RPC surface nothing re-verifies today, executes the 30 sim assertions on every PR, and is
  the precondition for OPT-S1/P1/P2/A6 landing with regression cover instead of a one-off
  local-stack note in the tracker.
- **T2 — repository unit tests**: still blocked on mocking `SupabaseClient`; re-evaluate
  `mock_supabase_http_client` (or a thin `PostgrestClient` wrapper injected into the repos)
  before writing a bespoke fake. Start with the read paths (`getById` decode + B022 ordering,
  `kRecipeSelect` shape) — they are the ones OPT-P3 rewrites.
- **T3 — widget tests, priority order**: recipe-detail interactions (signed-out like/save →
  `/auth`; toggle states — pins B051's fix), `snapRating` (pure function, named untested in
  Gotcha 15, five minutes), ShareDialog (disambiguation UI once A5 lands), then discover/auth
  flows.
- **T4 — toolchain debt, one decision each**: commit `pubspec.lock` (B009 — root cause of
  "B005 appeared suddenly"); raise the `sdk:` lower bound to ≥3.7 so `dart format` emits the
  tall style and B027's format-breaks-analyze trap closes (one whole-repo reformat commit);
  then `freezed` 3.x migration (B005's permanent fix — unpins Flutter, breaking model-syntax
  change, its own change set).
- **T5 — screenshots**: `npx playwright install chrome`, then the standing B028 procedure
  (release build + static serve) over `/chefs` v3 and the revised card. Phases 22/23 both
  proved a class of bug (B029–B032, B047/B048) that only this pass sees.
- **T6 — `tool/db.dart`**: pass `-1` (single transaction) for `db:create`/`db:seed`/`db:recipes`
  so a mid-file failure rolls back instead of leaving half-applied DDL; the sim files manage
  their own transactions and are exempt.

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
