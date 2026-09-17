# ROADMAP — Secret-Sauce

All **open** implementation tasks, grouped by phase. Status is kept in sync with the code
(see the "Docs–code sync" rule in [CLAUDE.md](../CLAUDE.md)). Shipped phases live in
[archive/ROADMAP-phases-0-31.md](./archive/ROADMAP-phases-0-31.md) — when a phase here completes,
move its full section there and leave one row in the "Shipped phases" table plus any open items in
the carried-over register.

Legend: `[ ]` not started · `[~]` in progress · `[x]` done · `[→]` moved elsewhere — to
[Backlog](#backlog--deferred-not-scheduled), or to a later phase that now owns it (the item names
which)

## Product direction (the north star)

Secret-Sauce is a **recipe vault first**, and that stays the core. The end state adds one more
layer of identity on top of the chef layer that Phases 18–23 built:

1. **Recipes** — structured, forkable, versioned. _(Phases 2–20: done)_
2. **Chefs** — a presentation of `profiles`, scored and tiered by engagement with their public
   recipes. _(Phases 18, 22, 23: done)_
3. **Restaurants** — a new entity. A restaurant lists **member chefs** (association is optional —
   most users never join one) and **signature dishes**, which are pointers into the existing
   `recipes` table, not a second recipe system. _(Phase 25: designed, not started)_

The build order to date is deliberately compatible with that end state: "chef" was built as a
presentation of `profiles` rather than a second principal table, and a restaurant will be built as
an entity _managed by_ profiles rather than a login of its own — so auth, RLS, and the engagement
model all stay single-principal. The main gaps between here and Phase 25 are listed in that
phase's prerequisites (most notably: there is still no public chef page, and Phase 25's
restaurant page needs the same shape).

---

## Shipped phases — archived

Phases 0–23, 26–32 and Phase OPT are **done** and their full task lists, verification logs, and
decision history have moved to [archive/ROADMAP-phases-0-31.md](./archive/ROADMAP-phases-0-31.md).
One line each here; open items they left behind are consolidated in the register below, in the
[Backlog](#backlog--deferred-not-scheduled), or in [Phase 32](#phase-32--audit-remediation--shipped-2026-08-26).

| Phase | What shipped                                                                                   |
| ----- | ---------------------------------------------------------------------------------------------- |
| 0–12  | Foundation: docs, monorepo, schema + RLS, core models/repos, design_system, shell + auth, Discover, My Recipes, recipe detail, editor, fork + versions, search + ranking |
| 13    | Toolchain pinned: Flutter 3.44.8 / Dart 3.12.2 / melos 6.3.3, reproducible Windows setup       |
| 14    | Ratings — half-star, aggregate trigger, Bayesian Popular                                       |
| 15    | Visibility polish (public/private badge, end-to-end RLS check)                                 |
| 16    | Agent-context accuracy audit of CLAUDE.md (B019–B021)                                          |
| 17    | B022 fix — nested content order                                                                |
| 18    | Chefs, tiers & leaderboard (chef_score/chef_tier_for, chefs_leaderboard, /chefs)               |
| 19    | Authored recipe content: recipeData/ + tool/recipes.dart, split from demo seed                 |
| 20    | RecipeCard v2 (banner, fixed height) + flowing grid (FlowGridMetrics)                          |
| 21    | Top navigation v2 (web): avatar menu, centred pill, label degradation                          |
| 22    | Chefs v2: podium board + expanded chef card, chef_top_recipes RPC                              |
| 23    | Chefs page v3 (web): hero, spotlight card, rails; windowed half deferred                       |
| 26    | Discover v2: masthead, three shelves (quick/projects/most-forked RPCs), sliver grids           |
| 27    | Recipe detail v2 (expanded + compact, v1 deleted) + cook mode                                  |
| 28    | Nutrition facts: `recipes.nutrition` jsonb, label widget, manual entry                         |
| 29    | Auto nutrition (a–d): food registry, `food_id` links, `estimate_nutrition`, fixture refresh    |
| 30    | Public chef page `/chef/:id` + `chef_standing` RPC; chef dialog retired                        |
| 31    | Chef page sort tabs (All / Popular / Trending) + `chef_trending_recipes`                       |
| 32    | Audit remediation, six bands: SQL integrity + storage limits (32a), measured indexes (32b), app correctness incl. B084/B085 (32c), shared-package hygiene incl. B083/B086 (32d), the three coverage gaps (32e), CI + a restorable backup B087 (32f) |
| OPT   | Hardening: 26 of 29 items (column grants B050, save_recipe RPC, search_tsv, paging, CI database job, RLS matrix…); remainder → Backlog BL-1/2/4 |
| 36    | Fabricated-data cleanup (B112/B113/B114): `db:audit` + `db:purge:fake`; `seed.sql` and the sim removed from every default path; curated `demo` counters retired; 15 impersonation accounts for real named chefs deleted and `ingest.mjs` made incapable of creating them |

## Carried-over open items (from archived phases)

Open work the archived phases left behind, so nothing is lost with the history. Each names its
origin phase; detail is in the archive.

**Product / UX**

- [ ] Typography upgrade — Newsreader + Manrope via `google_fonts`, app-wide decision (Ph 20/23)
- [x] Per-step image upload picker (Ph 9, B035) — done in Phase 33. Bytes are held on the draft
      and uploaded inside `_save`, exactly as the cover is, so an abandoned edit leaves no orphan
      object in the bucket and nothing reaches the recipe outside the one `save_recipe` call
      (Gotcha 11). One shared pick path (`imagePickerProvider`) means one 5 MB guard (32a4), not
      two. Removing a photo deliberately leaves the stored object alone — a removal that is never
      saved must not destroy the image the recipe still points at
- [~] Chefs windowed half (Ph 23) — **now Phase 33**, which owns the remainder. The SQL half is
      done and pinned (`chef_window_stats`, `chefs_leaderboard_windowed`, `created_at` on both
      leaderboard RPCs, B012's exclusion); the Momentum tab, the Month/Week hero toggle, the
      Trending/month rails and the `New` sort are still drawn and disabled
- [ ] Spotlight card as a mobile sheet (draft 1f) + unused `large` 400×560 size (Ph 23)
- [ ] Shelves do not page ("see all" route); no personalisation; fork count on card needs a
      denormalized `recipes.fork_count` (Ph 26)
- [ ] Cook mode plugins: `wakelock_plus` (screen awake), `flutter_local_notifications`
      (background alarm) — change the honesty copy in the same commit (Ph 27)
- [ ] Cook's note on the finish screen — needs `recipe_ratings.note` column + grant + RLS +
      matrix check + model/repo (Ph 27)
- [ ] Real `step_ingredients` table to promote the derived "you'll need" hint to a checklist (Ph 27)
- [ ] Sticky ingredients rail; version history v2 (diffs); owner-fork lineage line naming the
      parent (Ph 27)
- [ ] Micronutrients + per-100 g display (Ph 28/29); cooking yield/moisture disclosure (Ph 29)
- [ ] Vocabulary mining loop for unlinked ingredient names; `simData` food links (Ph 29)
- [x] `ChefBadge.onTap` on the RecipeCard cover overlay (Ph 30) — done in Phase 33. Wired once in
      `SliverRecipeGrid` (so every paged surface inherits it) and again in `discover_shelf.dart`,
      which builds its cards directly; null when the query embedded no owner, because an inert
      badge beats one that swallows the card's tap. The scrim became a `Material` so the ripple
      lands on the pill instead of under the cover photo. **Still open:** chef page cover art, and
      a Discover → chef link that is not a card badge (Ph 30)
- [ ] `recipes.notes` column (today appended to description); reverse-direction ingredient lint;
      retire `seed.sql` once there is real traffic (Ph 19)
- [ ] Web: Chefs + My Recipes still stack their own `AppBar` under the top bar (Ph 21)
- [ ] "Joined <month year>" reads the profile row's age, not the account's (Ph 22)
- [ ] `/chefs` board is one `limit: 50` page client-side, though the RPC takes an offset (Ph 22)
- [ ] Recipe-detail check-offs are session state, not persisted — the copy says so (Ph 27)
- [ ] Card cover photography is placeholder in the design; real shots may move the 352px card
      height (Ph 20)

**Quality / verification**

- [ ] B049 — card overflows at 3.0× text scale (contract is 2.0×); nothing caps the grid on 4K (Ph 20)
- [ ] Phase 31 pill has no screenshot pass — Gotcha 23's screenshot-only classes unproven
- [ ] Phase 29's editor Auto pane has no screenshot pass either — blocked, the headless driver
      cannot sign in (B028); covered by widget envelopes only
- [ ] `ChefAvatar`'s real-photo path renders nowhere — no seeded or sim profile carries an
      `avatar_url` (Ph 21/24, a standing BL-5 limit)
- [ ] `recompute_chef_stats`'s `is distinct from` guard has no direct assertion (Ph 18)
- [ ] Real-phone pass — nothing was ever exercised on a device (all phases; BL-6)

---

## Phase 24 — Simulated population: a realistic user + engagement dataset

**Status: in progress — only the dish count and a `large` run are left.** The `sim` schema, the
generator, its 53 assertions, and the CI wiring shipped in the first pass. Phase 33 closed the
content half: `people.json` and `vocab.json` are authored and loaded, `sim.rand_zipf` draws the
tag vocabulary, and the per-persona RLS smoke runs (`melos run db:sim:rls`). What remains open
below is the dish library (73 of 120 — already past every coverage target) and a `large`-preset
run. Full design, distribution model, and the
edge-case catalogue in
[EXECUTION-PLAN.md Phase 24](./EXECUTION-PLAN.md#phase-24--simulated-population-a-realistic-user--engagement-dataset).

The problem it solved: every feature built since Phase 18 was a _ranking_ of a population that did
not exist. The seed-only database held 21 accounts and 23 recipes whose engagement counters were
typed by hand into `seed.sql` / a `demo` block. Consequences, all recorded as limits at the time:

- The leaderboard is 8 rows, so pagination, `dense_rank` at scale, and the hero's `004 / 148` serial
  are untested against real cardinality.
- `recipe_likes` / `recipe_saves` / `recipe_views` / `recipe_ratings` are **nearly empty** — the
  counters were written directly. Every windowed or dated query (the Trending rail, `Momentum`, the
  hero's Month/Week — Phase 23's whole deferred half) has nothing to read, which SDS §10.8 calls out
  as needing "its own answer before the rails do". This is that answer.
- Discover's Popular tab is a Bayesian average over ≤ 8 ratings per recipe; nothing proves the prior
  actually suppresses a one-rating recipe.
- No account in the database is a **non-creator**. The product's most common real user — someone who
  only ever reads recipes — has never been rendered.

The deliverable is a deterministic, idempotent, scale-parameterized generator that builds a
plausible population _and its history_, with the engagement log as the source of truth and the
denormalized counters derived from it (the reverse of how `seed.sql` works).

### Content — the dish library

- [~] `simData/dishes/<slug>.json` — **73 of 120** authored dishes, same format as
  `recipeData/recipes/*.json` so a dish can be promoted into the curated set by moving the file.
  Written fresh, not copied (ingredient lists are not copyrightable; step prose is). Sequenced
  for **coverage before count** — all 7 targets below passed at 25, so the remaining 47 add
  variety to an already-valid library rather than being load-bearing. The validator's gate turns
  from warning to error at 100 dishes
- [x] Coverage targets, asserted by `tool/sim.dart` over the whole directory: all 10 `category`
      values, ≥ 24 cuisines (25 dishes, 25 distinct cuisines), the full `difficulty` spread, a
      no-cook dish (`cook_minutes` 0), an overnight step (`duration_minutes` > 480), a multi-group
      dish (SDS §11.1), and a dish serving ≥ 8. Warnings below 100 dishes, errors at or above it —
      a partial batch legitimately misses a category, a finished library does not
- [x] `simData/people.json` — 17 locales, 544 given/family names, 26 bio templates. The locale is
      drawn ONCE per actor and the given name, the family name and the bio's `{cuisine}` all read
      that row, so a name is coherent rather than a two-culture collage — which is what the two
      flat `array[…]` literals in `2_sim_generate.sql` produced about fifteen times in sixteen.
      Asserted by check **H3**
- [x] `simData/vocab.json` — 66 tags and 40 title-variant templates. **Array order is rank and
      rank is the only weight**: `sim.rand_zipf()` turns it into a draw, so `quick` lands on 162
      of 432 recipes at `small` and `smoked` on one. Eligible tags are re-ranked densely per
      category, so a Dessert-only tag leaves no hole in a Soup's ladder (check **H7**). The title
      templates **moved out of `0_sim_schema.sql`** in the same change, which is load-bearing:
      `sim.title_variant` is `cross join`ed, so an empty pool generates ZERO recipes and reports
      success — the generator's preflight now refuses it outright
- [x] `simData/README.md` + `simData/schema.json` — authoring workflow and the format delta from
      `recipeData` (no `demo` block; an optional `sim` block of `weight` + `variant_titles`)

### Tooling

- [x] Extract the validator out of `tool/recipes.dart` into **`tool/recipe_format.dart`** (a sibling,
      not `tool/lib/` — `tool/` is loose scripts, and a root `lib/` would have made the workspace
      package own it) so `recipeData` and `simData` cannot drift into two different definitions of a
      valid recipe. Proof the refactor is neutral: `recipes:check` still passes **byte-for-byte**
- [x] `tool/sim.dart` (`validate` / `gen` / `check`) → **three** generated loaders, committed
      and CI-gated exactly like `seed_recipes.sql`. Creates its own schema and table so it is
      standalone; **upserts** by slug (a library should push content edits, unlike `seed_recipe_v2`)
      and deletes rows whose source file is gone
- [x] `melos run sim:validate` / `sim:gen` / `sim:check`
- [x] `tool/db.dart`: `db:sim`, `db:sim:verify`, `db:sim:clean`. `--preset` / `--seed` are written
      into `sim.config` before the generator reads them rather than passed as psql `-v` vars, so a
      hand-run file behaves identically to the wrapper. `db:sim:clean` deletes `auth.users` rows and
      requires an explicit `--yes`; every action prints the target host first (Gotcha 7)
- [x] **`db:reset` DOES run the sim** — reversing the original plan, at the owner's request. Safe
      because `engage_existing` is false: the Kitchen and `d1`–`d7` counters stay byte-identical and
      every standing pinned in SDS §10.7 survives. Only the **ranks** move. Full reset from an empty
      database, sim included, is ~15s
- [x] CI: `sim:check` added beside `recipes:check`

### The `sim` schema (never `public`)

- [x] `supabase/sim/0_sim_schema.sql` — `create schema if not exists sim`. Every helper function and
      registry table lives here, so PostgREST (which exposes `public` only) cannot reach them. This
      is B026's lesson applied by construction rather than by a `revoke` block
- [x] `sim.rand(key, stream)` and the derived draws — `rand_normal` (Box-Muller), `rand_lognormal`,
      `rand_int`, `rand_bool`, `rand_ts`. All pure functions of
      `hashtextextended(key || stream, seed)`, **not** `setseed()` + `random()`: a hash is
      order-independent, so the same seed yields the same database regardless of plan or parallelism
- [x] `sim.uid(kind, n)` — deterministic ids, so a re-run updates rather than duplicates. **bigint**,
      because at the `large` preset the composed `n * 10000 + …` overflows a 32-bit int (B044)
- [x] `sim.epoch_end()` — the time anchor, **pinned into `sim.config`** on first generate rather than
      read from `now()`. Determinism depends on it and the failure is silent; see B044
- [x] `sim.actor` / `sim.recipe` registries — teardown deletes exactly what is listed here, never by
      an email or id pattern. The registry _is_ the safety mechanism
- [x] `sim.persona`, `sim.preset`, `sim.config`, `sim.title_variant` — the distribution is data, so
      retuning a share is a one-row edit, not a rewrite
- [x] `sim.counter_baseline` — only used when `engage_existing` is on
- [x] `sim.rand_zipf` — the general Zipf draw, plus the two exponents that key it
      (`sim.tag_zipf()` 1.1, `sim.title_zipf()` 0.6) as `sim.config` rows rather than literals

### Generation

- [x] `supabase/sim/2_sim_generate.sql` — set-based, idempotent, one transaction, ~10s at `medium`
- [x] **Personas**: ghost 22% / lurker 43% / collector 14% / casual 11% / regular 6% / power 2.5% /
      vault 1.5%. Measured at `medium`: 21.3 / 45.5 / 14.0 / 9.9 / 5.1 / 2.6 / 1.6, and **95%** of
      simulated accounts own no public recipe
- [x] **Signups** on a compounding growth curve over 24 months
- [x] **Recipes**: per-persona log-normal count; a dish from the library plus a deterministic variant.
      1,671 recipes from 1,000 users at `medium`. Title uniqueness within an owner is guaranteed by a
      merged, **deduplicated** template sequence per dish — treating the dish's own variants and the
      generic pool as disjoint produced a real `(owner_id, title)` collision (caught by check D4)
- [x] **Versions**: geometric edit count, 4,196 rows, `current_version_id` on the last
- [x] **Forks**: ~4% of recipes, always from an older public recipe of a different owner
- [x] **Engagement** as a funnel over a _view_, never independent: view → like → save → rate. At
      `medium`: 97,926 signed-in views, 19,930 anonymous, 6,483 likes, 4,898 saves, 1,839 ratings
- [x] **Ratings** J-shaped, shifted per recipe by a latent quality term, plus a polarized set
- [x] **Private recipes** receive engagement only from their `recipe_shares` rows (902 shares)
- [x] Counters are **derived, not authored**: triggers disabled for the load, counters and
      `chef_score` / `chef_tier` recomputed set-based through the real `chef_score()` and
      `chef_tier_for()` (Gotcha 19), triggers restored
- [x] `engage_existing` (default false) keeps every SDS §10.7 standing byte-identical
- [x] Presets: `tiny` (60) · `small` (250) · `medium` (1,000, default) · `large` (8,000)

### Verification

- [x] `supabase/sim/3_sim_verify.sql` — 53 assertions that `raise exception` rather than print.
      This script _is_ the test suite for this phase — there is no other coverage of the generator —
      and it found all three defects in B044 plus B045. Written when nothing in CI ran SQL at all;
      **OPT-T1 now runs it there** on a `tiny` population, which is what turned it from an opt-in
      script into a regression gate
- [x] Counter invariants (A1–A8), including `view_count` excluding anonymous rows and repeat visits
      (B012) — plus A7/A8, which assert those rows **exist**, so A3 cannot pass vacuously
- [x] Authorization invariants (B1–B5): no self-rating, half-star steps, no engagement on a private
      recipe from outside its share list, and no like or rating without a view
- [x] Temporal invariants (C1–C6): nothing predates its parent, nothing is in the future, no fork
      older than its source
- [x] Structural invariants (D1–D8): B022 ordering, every recipe has a `current_version_id`, no
      `(owner_id, title)` collisions; D5–D8 are Phase 28's nutrition-draw checks
- [x] Shape assertions (E1–E12) — persona coverage, heavy-tail concentration, J-shaped ratings,
      forks, long version histories, and the deliberate edge-case accounts. E3 and E9 are
      **population-aware**: both measure quantities whose ceiling is set by how many users exist, so
      at `tiny` they are relaxed or skipped **loudly** rather than tuned until they pass
- [x] Idempotency: generate twice → identical counts and identical `sum(chef_score)`
- [x] `d1`–`d7` + Kitchen standings asserted unchanged (F1–F3)
- [x] Wall-clock: `medium` generate ~10s; full `db:reset` from an empty database ~15s
- [x] RLS smoke test per persona with `set local role authenticated` —
      `supabase/sim/4_sim_rls_smoke.sql`, run by `melos run db:sim:rls`. Seats one REAL actor per
      persona from the `sim.actor` registry: 130 passed / 6 skipped / 7 personas seated. It is the
      gap between `db:sim:verify` (runs as `postgres`, bypasses every policy) and `db:rls` (builds
      its own three-user fixture, where every seat is an owner, a sharee or a stranger by
      construction). 79% of simulated accounts own no public recipe, and until this file nothing
      had asked what that account can do while signed in. **Not** part of `db:sim` — it writes
      before it rolls back, and `db:sim` runs inside `db:reset`
- [ ] `large` preset never run; `master_chef` is asserted there but unverified
- [x] **The assertion count was stale everywhere: 43 → 46.** 43 was right when Phase 24 shipped;
      Phase 26 added group **G** and no doc followed. Corrected in `CLAUDE.md`, this file, and
      `EXECUTION-PLAN.md` (nine call sites), and SDS §12 now says to recount rather than copy
- [x] **CI's `tiny` preset did not run group G at all** — every check in it is gated on
      `v_users >= 250`, so **G3**, the fork-depth assertion that is the only guard on
      `sim.fork_bias` and therefore on `MOST FORKED` ranking anything, was exercised by **no
      automated run**. With E3 gated the same way, `ALL CHECKS PASSED` at `tiny` meant **42 of 46**.
      Found while writing SDS §12 by running the verifier and reading the notices instead of the
      summary line.
      **Decided 2026-08-26 (owner): option A — raise CI to `small`**, keeping the other two (a
      population-scaled G3, or accepting it out loud) in reserve if the runtime ever bites.
      `database.yml` now seeds `preset=small`: group G executes and E3 no longer skips, so a green
      run means 46 of 46. Costs ~370 extra recipes and ~17k view rows per path.
      Taking it immediately surfaced **B081** — E9 demanded `head_chef` of any population of 250+,
      a rung 250 accounts cannot reach (the top simulated chef scores 3,078). E9 now has four rungs,
      one per reachable ceiling. Verified at `small` on the local stack before committing; the
      preset had never been run by anyone

### Docs

- [x] `docs/SDS.md` §12 — the simulation dataset: personas, distributions, invariants, and the
      derived-counter rule. **Written 2026-08-25**, in nine parts: the derived-counter rule and its
      three consequences, determinism (why hashing rather than `setseed()`, and the pinned time
      anchor), the persona and preset tables as data, the generator step by step, the nutrition
      draw, verification, safety, and the gaps. Two things the writing turned up, both now recorded
      there rather than only here — see the two items directly below
- [x] `CLAUDE.md` — the new commands, and the two traps worth a gotcha entry: engagement rows must
      be loaded with triggers off (or the load is O(rows) profile recomputes), and teardown is
      registry-driven
- [x] `README.md` — `db:sim` / `db:sim:clean` in the database section, with the B033 Docker
      `psql` form
- [x] `docs/BUG-TRACKER.md` — B043 (tier calibration), B044 (three generator defects), B045
      (first-apply ordering) recorded. Two more remain predicted, not yet observed:
      `recipes_search` recomputes `recipe_search_document()` per row for both the filter and the
      rank (no stored tsvector, no GIN index), and `can_read_recipe()` runs per row for every
      Discover read. Neither is visible at 23 recipes

### Deferred

- [ ] `avatar_url` and `cover_image_url` stay **null** for every sim row. There is no image asset and
      an external URL 404s offline, which renders as a broken-image widget rather than the monogram
      fallback the null path gives. Config knobs exist for whoever wires a bucket
- [x] A CI job that applies `0001_init.sql` → `seed` → `recipes` → sim `tiny` → `3_sim_verify.sql`
      — **done by OPT-T1** as `.github/workflows/database.yml`, which also walks the re-apply and
      upgrade paths. Not a "Postgres service" job as written here: `profiles.id` references
      `auth.users`, so it starts the real Supabase stack (database container only) instead
- [ ] Building Phase 23's deferred windowed half on top of this data — the rails now have rows to
      read, but they are still unwritten

---

## Phase 25 — Restaurants & signature dishes (north star — designed, not started)

Design detail and prerequisites: [EXECUTION-PLAN.md Phase 25](./EXECUTION-PLAN.md#phase-25--restaurants--signature-dishes).
A restaurant is an **entity managed by profiles**, never a second principal: nobody signs in "as
a restaurant", so auth, RLS, and the engagement model stay exactly as they are. Signature dishes
are rows pointing at existing `recipes` — no second recipe system.

> **The schema checklist below is superseded by [Phase 35b](#phase-35--the-corpus-becomes-product-shipped-2026-09-12).**
> The corpus needs an attribution entity for 560 publishers and this phase needs a restaurant
> entity; they are the same table, so `restaurants` becomes `entities` with an `entity_kind`
> (`restaurant | brand | publication | community | chef_site`) and the two child tables become
> `entity_members` / `entity_signature_dishes`. Build it once, in 35b. What stays live here is the
> **product** half — the directory and detail pages, the member/signature-dish editor surfaces, the
> sim content, and B043's tier-calibration prerequisite.

### Prerequisites (each is real work, ordered)

- [x] **Public chef page** (`/chef/:id`) — **done in
      [Phase 30](./archive/ROADMAP-phases-0-31.md#phase-30--public-chef-page-chefid--done-2026-08-25)**, 2026-08-25. The restaurant
      page copies its shape: identity header (profile + optional standing) over a paged
      `RecipeAsyncSliverGrid`, on the root navigator, signed-out safe, no nav destination. Two
      things it learned that Phase 25 inherits — a page reached by URL needs its own single-row RPC
      (`chef_standing`, filtered _outside_ the window), and a "belongs to this entity" recipe list
      must filter `visibility = 'public'` explicitly, because RLS hands an owner their own private
      rows and the page would then show them what nobody else can see.
- [ ] Decide the tier-calibration question (B043) before restaurant scores restate it — a
      restaurant aggregate over miscalibrated chef scores bakes the miscalibration in twice.
- [x] SQL regression harness — **done** (OPT-T1's `database.yml` + BL-7's `rls_matrix.sql`, both
      in CI), so Phase 25's new tables, RLS, triggers, and RPCs start covered: add their checks to
      the matrix in the same change set, per the BL-7 standing rule.

### Schema (`0001_init.sql`, idempotent, same rules as every prior phase)

- [ ] `restaurant_role` enum (`owner` | `chef`) — guarded creation like the other five enums
- [ ] `restaurants` table: `id`, `name`, `description`, `city`, `country`, `website`,
      `cover_image_url`, `created_by → profiles`, `created_at`, `updated_at`. Grants added
      explicitly (B013 — the blanket grant block runs before this table exists on upgraded DBs)
- [ ] `restaurant_members`: `restaurant_id`, `profile_id`, `role`, `title` (free text, e.g.
      "Head Chef"), `created_at`; PK `(restaurant_id, profile_id)`. Association is optional by
      construction — a profile with zero rows here is the normal case
- [ ] `restaurant_signature_dishes`: `restaurant_id`, `recipe_id`, `sort_order`, `created_at`;
      PK `(restaurant_id, recipe_id)`. `with check`: the recipe is **public** and owned by a
      member — a private recipe as a signature dish would leak its existence through a
      world-readable table
- [ ] RLS: restaurants + members + signature dishes world-readable (public directory);
      restaurant writes by `owner`-role members; membership writes by `owner` only; signature-dish
      writes by members. Every trigger that crosses ownership: `security definer set search_path`
      (B011 class)
- [ ] Optional denormalized `restaurants.member_count` / signature-dish aggregate — same
      recompute-from-scratch trigger pattern as `rating_*` and `chef_*`; decide the restaurant
      "score" formula only after B043 is settled
- [ ] `drop.sql` entries + B024 signature-drop blocks for any new helper

### core / design_system / app

- [ ] `Restaurant`, `RestaurantMember` models (+ enums mirrored in `enums.dart` — update the
      "five enums" notes in `CLAUDE.md`/SDS when this lands)
- [ ] `RestaurantRepository` (abstract + Supabase impl, wired in `providers.dart`); embedding
      queries will need FK hints from day one — `restaurants ↔ profiles` is related two ways
      (`created_by` + members) at birth, the exact `PGRST201` shape Gotcha 17 documents
- [ ] `profiles`: no schema change — a chef's restaurant affiliation is read through
      `restaurant_members`, so the chef card/page gains an affiliation line without touching the
      score machinery
- [ ] Widgets: restaurant card + member-chef row in `design_system` (barrel exports, envelope
      tests at 288px / 2.0× — same contract as every card)
- [ ] Routes: `/restaurants` (directory; signed-out safe) + `/restaurant/:id` (detail; signed-out
      safe). Nav destination decision per Gotcha 18: a fifth destination costs the web pill its
      labels — measure before adding, or reach restaurants through Discover/chef pages instead
- [ ] Editor surface for owners (create restaurant, manage members, pick signature dishes from
      the owner's public recipes)

### Content / sim

- [ ] Extend the Phase 24 generator: a few % of simulated chefs belong to generated restaurants,
      signature dishes drawn from their public recipes — so the directory, empty states, and
      RLS paths are exercised at scale like everything else.
      **This is a prerequisite of the UI work, not a follow-up** — no fixture today contains a
      restaurant, so the directory, the member list, and the signature-dish rail have nothing to
      render against until it lands. See the "Seed-data fit" gate in
      [CLAUDE.md](../CLAUDE.md#seed-data-fit-mandatory)

---

## Phase 32 — Audit remediation — SHIPPED 2026-08-26

All six bands (32a–32f) are done; the full task list and verification log moved to
[archive/ROADMAP-phases-0-31.md](./archive/ROADMAP-phases-0-31.md). One row in the shipped table
above. What the audit left **undecided** is below — it was never scheduled, and the decision is
still owed.

### Phase 32's undecided items (argue before building)

- `recipe_views` retention/partitioning — the table grows without bound and `anon` can insert
  (B012 protects the counter, not the table); needs a retention design decision
- Persisted Bayesian score for Popular/quick — full-scan-per-page is fine at 10³ recipes; measure
  before ~20k, not now
- Profile editing UI — `updateMine` exists in core but no screen calls it; product intent needed
- Split `cook_step_view.dart` (1145 lines) — mechanical but large; do alongside the next cook-mode
  feature
- `SuggestionStatus` enum + `recipe_suggestions` stub — reserved by design; decide build-or-drop
  when the PR-flow feature is scheduled

---

## Phase 33 — The windowed leaderboard (SQL built; client not started)

**Status: `[~]`.** Everything on `/chefs` above this phase is **all-time**: `profiles.chef_score`
and the three totals beside it are lifetime counters with no date on them, so nothing in the
schema could answer *who moved this month*. That is why Phase 23's `Momentum` sort and the hero's
Month / Week toggle shipped **drawn and disabled**. The engagement logs can answer it, so a
windowed score is a query rather than a new snapshot table — and Phase 24's simulated population
is what finally gave those logs anything to read (SDS §10.8 called this out as needing its own
answer first).

This phase built and pinned the SQL. **No Dart, no widget, no route** — the `Momentum` tab, the
Month/Week toggle and the `New` sort are still drawn and disabled, and closing that is what
remains.

### Schema — `0001_init.sql` (done)

- [x] `chef_window_stats(p_days, p_since, p_chef)` — the **only** place the window is computed.
      Returns likes / saves / views / ratings / new recipes in the window plus a `window_score`
      from the real `chef_score()` (Gotcha 19 — never a restated `3 / 5 / 0.2`). Zeros, not
      missing rows, for a quiet chef, so the board can rank the whole population
- [x] **`security definer`, and not for the usual reason.** Two of the four logs are not
      world-readable — `saves_select` is `user_id = auth.uid()`, `views_select` is
      `owns_recipe(recipe_id)` — so under invoker rights this computes a *different* board for
      every caller: zeros for `anon`, their own numbers for a chef. Safe to elevate because it
      takes no dynamic SQL, writes nothing, pins `search_path`, returns **counts only**, and
      filters `visibility = 'public'` explicitly rather than leaning on RLS to do it
- [x] **Anonymous views excluded, viewer counted once** (B012 / Gotcha 10). `anon` holds
      `insert on recipe_views`, so counting raw rows would hand an unauthenticated loop the top of
      the board. Measured on the local fixture: 3,878 of 20,630 view rows anonymous, and the
      16,752 signed-in rows collapse to 10,083 distinct pairs — a 51% correction, not a rounding
- [x] `chefs_leaderboard_windowed(p_days, p_limit, p_offset, p_since)` — ranks what that returns
      and adds no arithmetic of its own. Same row shape as `chefs_leaderboard` plus the six window
      columns, so one client model decodes both boards and Score / Momentum stay a **re-sort**
- [x] `dense_rank()` over the whole population with `limit`/`offset` applied **outside** it
      (Phase 30's `chef_standing` lesson), and a **total** order ending in `id` — the windowed
      keys tie far more than `chef_score` (most of the board scores 0 in any week), so without it
      `offset` would show one chef twice (Gotcha 24)
- [x] `p_since` pins the boundary. A window measured from `now()` **moves**, which makes `offset`
      lie even over a total order: fetch page 1, read `window_start` off any row, pass it back
- [x] `created_at` added to `chefs_leaderboard` **and** `chef_standing` in lockstep — the `New`
      sort and the `Joined <month year>` line both need it. This is a **return-type** change, which
      `create or replace` refuses exactly as it refuses an argument-list change, so the
      `drop function if exists chefs_leaderboard(int, int)` line went from insurance to
      load-bearing — and it fails **only** on the upgrade path (Gotcha 6)
- [x] Four dated indexes — `recipe_likes`/`recipe_saves`/`recipe_ratings` on `(created_at desc,
      recipe_id)` and `recipe_views` on `(viewed_at desc, recipe_id, user_id) where user_id is not
      null`. The existing composites all lead with `recipe_id`, so none could serve "every like on
      the site in the last 7 days". The `recipe_views` write cost (a fifth index entry on the
      highest-volume insert in the schema) is recorded as *expected* to be indistinguishable, not
      as measured — 32b measured two→four as below the noise floor
- [x] **B092 fixed in the same phase.** `chef_trending_recipes` (Phase 31) had the invoker-rights
      version of this exact defect: it reads `recipe_views` directly, so for `anon` and every
      signed-in non-owner the distinct-viewer term counted zero and the ordering silently degraded
      to likes alone — the chef saw a different Trending tab from their own readers. Now
      `security definer set search_path = public`; it already filtered `visibility = 'public'`
      itself, so nothing was leaning on RLS. Audited the neighbours at the same time: no other
      ranking RPC reads the logs (the Discover shelves and `chef_top_recipes` rank on the
      denormalized counters), so this was the only instance

### Verification (done)

- [x] `rls_matrix.sql` **F12–F19** — the windowed board as `anon`, which is the role that would
      have seen the zeros: reachability, the window as a real filter, B012's exclusion, the
      public-only filter, `dense_rank` outside the paging, the total order, `created_at`, and
      `p_since` overriding `p_days`
- [x] `rls_matrix.sql` **F20–F21** — B092, pinned as *anon and the owner get the same order*, on
      two fixtures that tie on likes and differ only in recent viewers, with the unread one
      created last so the wrong answer is a different **order** rather than an error. Proven by
      reverting the function to `security invoker`: both fail, F20 naming the cause
- [x] `database.yml` smoke calls on the upgrade path, including `count(created_at)` from
      `chefs_leaderboard` (which is what fails if the drop line is ever removed) and a
      three-argument `chefs_leaderboard_windowed` call to exercise `p_since`'s default (B024)

### Client — not started

- [ ] `ChefWindowStanding` model + repository method + provider for
      `chefs_leaderboard_windowed`; `created_at` decoded on the existing leaderboard model
- [ ] `Momentum` sort on `/chefs` and the hero's Month / Week toggle — both already drawn and
      disabled; the board must **pin `p_since` from page 1** for paging to be sound
- [ ] The `New` sort, which is a different ordering and therefore a different query, not a
      tie-break bolted onto `chefs_leaderboard`
- [ ] Trending/month rails, and a per-chef momentum line on `/chef/:id` (`chef_window_stats`
      already takes a `p_chef`)
- [ ] A real **empty state**: a simulated database whose `sim.epoch_end()` anchor has gone stale
      returns an empty week, correctly. That is old data, not a broken query, and it must not
      render as a spinner

---

## Phase 34 — The scraped recipe corpus at scale (in progress)

Batch 1 and 2 captured 158 recipes from 15 chefs across 6 domains, to test the app's model
against real-world data. Phase 34 is the same idea at a different order of magnitude, and with
a second axis: **a recipe is credited to a chef *and* to a group** — a restaurant, a brand, a
publication, a community — because that is how the web actually publishes food, and because
Phase 25's north star (restaurants managed by profiles) needs a corpus that already carries the
distinction.

Data lands in **`corpus/`**, never in `recipeData/`. See CLAUDE.md Gotcha 28 for why that
boundary is physical rather than a convention.

### Crawler (done)

- [x] `robots.mjs` — real `robots.txt` fetch, parse and per-URL evaluation (RFC 9309 longest
      match, `Allow` wins a tie), `Crawl-delay` honoured, **unreachable = disallow**
- [x] `sitemap.mjs` — full index walk, nested indexes, `.gz` bodies, `<sitemapindex>` vs
      `<urlset>`
- [x] `probe_site.mjs` / `probe_batch.mjs` — qualify a candidate before it costs a crawl:
      robots, candidate count, and whether sampled URLs really carry a Recipe node
- [x] `promote.mjs` — probe result -> `corpus/sources.json`, merged by slug, `--batch` tagged
- [x] `harvest.mjs` — per-host serial lanes with per-host delay, cross-source concurrency,
      append-only JSONL shards, resume state, per-source lock, 429/503 backoff + one retry pass
- [x] `brands.mjs` — restaurant/chain detection for copycat recipes, as a *mention* with a
      confidence, never as the publisher
- [x] `dedupe.mjs`, `corpus_stats.mjs`, `corpus_export.mjs`

### Extraction fixes found by the scale-up

- [x] B095 — `3/4 cup` parsed as quantity 3 (regex alternation order); `(198g)` now captured
      as `metric` instead of being left in the ingredient name
- [x] B096 — keywords split on commas only, so `;;`-joined tag lists became one tag
- [x] B097 — `Recipe.author` is empty on most WordPress sites; the byline is one node over
- [x] B098 — an interrupted harvester duplicated records; flush interval, dedupe, lock

Live numbers are in **[corpus/_reports/CORPUS.md](../corpus/_reports/CORPUS.md)**, which is
generated by `report.mjs` from the shards — the figures are never typed into a document, because
a hand-written corpus total is wrong the moment the next source finishes.

### What the corpus showed

- **Recipes are cooked by many people, and differently.** 37,276 dishes have 2+ distinct
  chefs; 194,743 recipes (**34.9%**) belong to one of them. Banana Bread alone: 265 captures,
  216 chefs, 180 publishers, 4–28 ingredients (median 10). That spread is the direct
  evidence the fork/version model was designed for — those are not duplicates to collapse.
  `melos run corpus:similar`.
- **Restaurants barely publish recipes.** Of 592 registered sources only a handful are
  actual restaurants, and they hold 700 recipes between them. The chain axis is real but it
  arrives as a **mention** on a blogger's copycat recipe — 5,871 mentions across 205 chains
  — never as the publisher. Two names had to be removed rather than gated, because a dish
  name cannot be rescued by a cue: "BBQ Chicken" matched 852 barbecue-chicken recipes and
  "Tortilla" 255 recipes containing tortillas.
- **Three of Phase 1's four untestable gaps now have data**: step sections, equipment and
  grouped ingredients. Counts are in the generated report.

### Open

- [ ] ~714,000 discovered URLs are still unfetched — the harvest is **paused, not finished**
      (`melos run corpus:harvest` resumes exactly where it stopped). The remaining backlog is
      concentrated in about eight community giants, each capped at one request per second, so
      throughput there is bounded by politeness rather than by the machine
- [ ] Keep widening the source registry — every candidate tier is a `candidates/*.json` file,
      probed and promoted the same way
- [ ] Sites that answer 403 to this client while loading in a browser are **left alone**:
      getting past that means disguising the client, which is not something to do to a site
      signalling no. That is the whole Dotdash Meredith family (`seriouseats.com`,
      `simplyrecipes.com`, `eatingwell.com`, `foodandwine.com`, and `allrecipes.com` — whose
      root sitemap serves but whose four children all 403), plus `nigella.com` and
      `justonecookbook.com`
- [ ] Sites whose recipes are not in JSON-LD at all (`gordonramsayrestaurants.com` has the node
      but no ingredients; `taste.com.au`, `coles.com.au`) need a per-site HTML extractor or
      nothing — decide per site, do not guess
- [~] Decide where this data lives beyond a local directory. The shards are git-ignored today,
      which is a deferral, not an answer. **Answered in part by
      [Phase 35](#phase-35--the-corpus-becomes-product-shipped-2026-09-12)**: a curated tier is
      imported into Postgres (35c), the rest stays local until storage is paid for, and a small
      committed fixture shard under `corpus/_fixtures/` gives CI something to run against

---


## Phase 35 — The corpus becomes product (SHIPPED 2026-09-12)

Design, reasoning and the decisions behind every line here:
[EXECUTION-PLAN.md Phase 35](./EXECUTION-PLAN.md#phase-35--the-corpus-becomes-product-designed-nothing-built).

Phase 34 harvested 558,604 recipes from 560 publishers with 19,681 named chefs. Three bands stand
between that and a product, and they are **ordered** — 35c writes columns 35a and 35b decide, so
building the importer first means building it twice.

**This phase absorbs Phase 25's schema.** `restaurants` becomes `entities` with an `entity_kind`,
because the attribution entity the corpus needs and the restaurant entity the north star needs are
the same table. Phase 25's checklist above is superseded by 35b's, not duplicated.

**Decided 2026-09-12** (detail in the EXECUTION-PLAN table): import a **curated English-first tier,
hosted** (20-50k recipes; the full 558k stays local until storage is paid for); imported content
gets **its own browse surface and is never ranked**; build order is **35b → 35c, with 35a in
parallel**. The English-first tier is what lets `recipe_search_tsv` keep its `'english'` config —
that reopens the day a non-English tier is imported, and it is a re-index of every row.

### 35a — Rights, privacy and terms — **built 2026-09-12; awaiting four owner facts**

- [x] **The rights position is decided and written into the Rights page**: functional content
      stored and shown, expressive content linked, **photographs never re-hosted** — hotlink or
      nothing, never a proxy, because a proxy is a copy on our infrastructure wearing a link's
      clothes. Headnote/`description` prose is not imported at all
- [x] `LegalScreen` + a sealed `LegalBlock` (heading / paragraph / bullets) over Dart consts, no
      `flutter_markdown` dependency. One route pattern `/legal/:doc` behind
      `Routes.legal(slug)`; an unknown slug falls back to Privacy rather than 404ing. Root
      navigator, signed-out safe, in neither destination list (Gotcha 18), 720px reading measure
- [x] **Privacy** — names `recipe_views` as a behavioural log keyed to the account, says
      signed-out visits are uncounted (B012), and states that deletion leaves the view rows behind
      with the account reference removed and that the counters do not fall (Gotcha 10). Also
      covers the imported chef pages Phase 35b created: no invented bio or photo, not ranked,
      claim or removal on request
- [x] **Terms** — the fork clause is its own section with its own heading, because publishing
      publicly grants every other user a right that cannot be withdrawn afterwards, and it was
      promised nowhere. Plus the nutrition/allergen/food-safety disclaimer, naming all three
      sources a label can come from and the fact that an estimate silently skips what it cannot
      resolve
- [x] **Rights** — attribution (chef and publisher recorded separately, neither inferred), what is
      never copied, how the crawler behaves (robots per URL, unreachable = no, `Crawl-delay`
      honoured, one request per host, a 403 is left alone), takedown at five working days with a
      permanent record so a later crawl cannot undo it, and the copycat rule
- [x] `SiteFooter` + `SiteFooterLink` in `design_system` (barrel-exported). Web: slim persistent
      bar in `AppShell`'s `bottomNavigationBar` slot. Compact: the profile screen, **and the
      sign-up form** — which the plan missed: `/profile` is behind `needsAuth`, so without the
      auth screen a signed-out phone reader had no route to any of the three pages at all. The
      sign-up form also gained the consent sentence, which is the one moment in the product where
      somebody actually agrees to the terms
- [x] Envelope tests: the footer at 360/600/1000/1440 × 1.0/1.5/2.0 and the whole legal page at
      390/600/1000/1440 × 1.0/2.0. The `Wrap` drops the copyright above 1.6× and keeps the links
- [ ] **Owner input required, and the pages say so.** `LegalFacts` in
      [legal_document.dart](../apps/app/lib/features/legal/legal_document.dart) holds the four
      values as bracketed placeholders — legal entity, governing law, contact address, hosting
      region — and `LegalFacts.isComplete` drives a red "Draft — not in force" banner at the top
      of every document until all four are filled in. Nothing was invented: a Terms page naming
      the wrong company is a false statement, not a placeholder
- [ ] Still open from the plan: whether corpus content is public at all or flag-gated (a 35c
      decision, not a page); the recipe-detail attribution block, which has no imported content to
      attribute until 35c lands; and a screenshot pass — the chrome bar sits in a `Scaffold` slot,
      which is exactly the class Gotcha 23 says widget tests do not see

### 35b — Identity: `profiles` decoupled from `auth.users` — **DONE 2026-09-12**

- [x] `profile_kind` enum (`member` | `imported`); `profiles.auth_user_id uuid unique null`,
      `kind`, `claimed_at`, `merged_into`; **the `auth.users` FK on `profiles.id` is dropped** —
      by catalogue shape rather than by name, because the point is that it must be gone. Backfill
      `auth_user_id = id`, so the migration is a no-op for every existing row. The cascade moved
      to `auth_user_id`, so "delete the account, delete the content" still holds — the promise
      35a's privacy page has to make
- [x] `current_profile_id()` — `stable security definer set search_path = public`; all 13 policy
      predicates and three RPC bodies read it now. `handle_new_user` keeps `id = new.id` for real
      signups, so member ids stay equal to their auth uid. `auth.uid()` survives in exactly three
      places, each for a stated reason: the signed-in guards, `profiles_insert` (the row being
      checked is the row that would make the lookup succeed, so the function returns null there),
      and the storage-bucket policies, whose folders are namespaced by the auth uid
- [x] **`rls_matrix.sql`: 165 checks, 0 failed.** All 137 pre-existing checks pass *unchanged* —
      that is the evidence the decoupling is behaviour-preserving, not a coincidence. New §G adds
      28 for the new surface, the claim merge included
- [x] `entity_kind` / `entity_role` enums + `entities` / `entity_members` /
      `entity_signature_dishes` (Phase 25's three tables, generalised), with RLS, column grants,
      every FK column indexed, text-length bounds, and `drop.sql` entries
- [x] `claim_status` enum + `profile_claims`; insert-own/read-own RLS, no update, one live claim
      per claimant per profile (partial unique index, so a rejected claim can be re-filed with
      better evidence instead of being blocked by its own history)
- [x] `approve_profile_claim()` / `reject_profile_claim()` — the **merge**, in one transaction,
      `security definer`, EXECUTE revoked from the API roles. Parks `recipes_chef_stats` for the
      duration (it fires on `owner_id`, so 3,000 recipes would mean 6,000 whole-catalogue
      aggregates), moves everything with `on conflict do nothing`, deletes the self-ratings a
      merge can create, tombstones the old profile via `merged_into`, recomputes both
- [x] The `kind = 'member'` ranking exclusion, moved here from 35c because this is where `kind`
      starts existing: `chefs_leaderboard`, `chefs_leaderboard_windowed`, `chef_standing`,
      `chefs_tier_counts`, `recompute_all_chef_stats` and the leaderboard index. The index was
      **renamed** rather than redefined — `create index if not exists` keys on the name, so
      editing a partial predicate in place applies to a fresh database and is a silent no-op on
      every database that already has it (Gotcha 5 in its index form)
- [x] `seed.sql`, `seed_recipes.sql` (via `tool/recipes.dart`) and `2_sim_generate.sql` write
      `auth_user_id` explicitly. The `on conflict` branches are the ones that mattered: a profile
      that lost its link resolves to nothing, and every policy then denies that account silently
- [x] core: `ProfileIdResolver` + `AuthRepository.currentProfileId()` + `currentProfileIdProvider`;
      `Profile.kind` / `Profile.claimedAt`; `SupabaseRecipeRepository` keys every write on the
      resolved id. Verified through the recording client **and** against the real PostgREST edge,
      where a scalar RPC returns a bare JSON string
- [x] Sim generates both kinds: `sim.imported_profile` and `sim.entity` registries, imported
      chefs drawn from the same name pools with **no auth row and no bio** (no invented
      biography — Phase 35a), their recipes riding the ordinary pipeline by being appended to
      `sim_titled`, and entities with a mixed roster of actors and imported chefs. The engagement
      steps skip them **by construction rather than by a filter**: §5, §6 and §7 all join
      `sim.actor` to find an owner's persona, so a recipe whose owner is not one is never reached.
      `9_sim_teardown.sql` deletes both registries — the imported half matters because those rows
      have no `auth.users` row to be deleted by, which is the registry rule the file already
      states. `3_sim_verify.sql` group **I** (7 checks) pins all of it, and **D3 was narrowed** to
      actor-owned recipes with I5 asserting the other side, so neither state is merely unchecked
- [x] core/app: `Entity` / `EntityMember` models, `EntityKind` / `EntityRole` / `ClaimStatus`
      enums, `EntityRepository` + provider, `/entity/:id` (root navigator, signed-out safe, no nav
      destination), the unclaimed-chef note on `/chef/:id` with a **disabled** claim button behind
      `notYetTooltip` (claiming is an admin RPC — an enabled button would silently do nothing),
      and the affiliation chips. All four repository queries were verified against the real
      PostgREST, not just the recording client: an embed that trips `PGRST201` is exactly what the
      canned-reply test cannot see
- [x] Imported chef identity is keyed to the **publisher**, never global — `import_recipe` looks a
      chef up by `(entity, display_name)` and creates one per entity otherwise. Collapsing two
      strangers into one identity is a far worse error than splitting one person into two rows, and
      only one of the two is correctable later. `corpus/chefs.json` keys on a normalised name
      globally and its own README flags that as deliberately imperfect; the database does not
      inherit it. A page with no byline is credited to the publisher alone, which is the honest
      reading of a page that names nobody

### 35c — Ingestion, with every counter at zero — **DONE 2026-09-12**

**21,334 recipes, 1,284 chefs and 546 publishers are in the local database**, from 543 sources,
at 260 MB. Every guarantee below was checked against that, not against a fixture.

- [x] `recipes`: `is_imported` (+ two partial indexes, one per population — after an import the
      two differ by three orders of magnitude and each query wants only its own side),
      `quality_score smallint` computed once at import from field coverage. Measured: average 97,
      range 35-100 across the imported tier
- [x] `recipes` provenance: `source_url`, `source_name`, `source_entity_id`, `imported_at`,
      `rights_mode`, `image_mode`, plus `import_blocklist` — the permanent record 35a's Rights page
      promises, so a takedown cannot be undone by the next crawl. All six reach `kRecipeSelect` and
      `Recipe`; none reaches a client grant, and `rls_matrix.sql` H5-H8 proves an owner cannot
      write any of them. `image_mode` is honoured through **one** getter
      (`Recipe.displayCoverImageUrl`) rather than at each of the five places that render a cover
- [x] **The `kind = 'member'` ranking exclusion — done in 35b**, because that is where `kind`
      starts existing and a half-filtered board is worse than an unfiltered one. Without it 19,681
      imported chefs tie at score 0 and then sort by `public_recipe_count desc` inside the tie — a
      14,154-recipe publication bot above every real zero-score chef. An imported chef is
      browsable, never ranked (`rls_matrix.sql` G5-G7)
- [x] Scraped `aggregateRating`, `description` and `nutrition` are all **not** imported, and the
      omissions are in `import_recipe` rather than in the tool — a rule written in Dart is a rule
      the database cannot see
- [x] `import_recipe(jsonb)` in SQL holds the whole write path — blocklist, idempotency key,
      quality score, the omissions — and `tool/corpus_import.dart` is a JSON transformer that
      connects to nothing. It writes batched `select import_recipe(...)` files; applying them is a
      separate manual psql step, which keeps a tool that reads 8.6 GB of scraped data away from a
      superuser credential (Gotcha 7). Verified idempotent: re-applying a batch left the count
      unchanged. **No `recipe_versions` row per import**, as designed
- [x] **Settled by the tier.** `_isEnglishSource` excludes the ~10 sources that declare a
      non-English language, so `recipe_search_tsv` keeps its `'english'` config and no `language`
      column is built. It reopens the day a non-English tier is imported — which is a re-index of
      every row, so it stays a tier decision
- [x] The curated tier came in at **260 MB total database** — 21,334 recipes, 243k ingredient
      rows, 158k step rows — which fits the free tier with room to spare. The 3-4 GB figure was for
      the whole 558k corpus and still is; the tier is what avoided it
- [ ] Committed fixture shard under `corpus/_fixtures/` so the **importer** has CI coverage. The
      SQL half is covered (`rls_matrix.sql` §H, `3_sim_verify.sql` group I) and the app half is
      covered (`explore_screen_test.dart`, the repository tests); what is not is the JSON→document
      transform in `tool/corpus_import.dart`, which today is proven only by having been run
- [x] **The `entities.slug` namespace** — closed in 35c, and it had stopped being theoretical the
      moment an import could run. `entities_insert` lets any signed-in member create an entity with
      any slug and the column is `unique`, so taking `king-arthur` before an import would have
      handed that publisher's whole catalogue to whoever got there first (`import_recipe`
      finds-or-creates by slug; `entities_update` is `is_entity_owner`). Imported entities now live
      under a reserved `src:` prefix that `entities_slug_namespace` forbids a member to write.
      Pinned by `rls_matrix.sql` **H8b** (the prefix is refused, 23514) and **H8c** (the same insert
      outside it succeeds, so H8b is not refusing everything)
- [ ] **Bound claim filing** (same review). `claims_insert` allows one pending claim per
      (profile, claimant) and nothing caps the number of profiles one account may file against, so
      a script can open 19,681 claims. Harmless while approval is manual SQL and the table is
      private to its claimant, but it wants a rate limit or a per-account cap before any claim UI
      ships
- [ ] Keyset pagination and BL-2's per-row `recompute_chef_stats` are **deferred, explicitly** —
      imported rows carry no engagement so the recompute never fires, and ranked surfaces exclude
      them. They return the day corpus rows start collecting real engagement

---

## Backlog — deferred, not scheduled

Everything here is **known, decided, and not being worked on**. An item is in the backlog because
it is an owner action, accepted debt, or a deferral with a stated trigger — not because it was
forgotten. Each one names the condition that would pull it back into a phase.

**What is open elsewhere in this document**, so the backlog is not mistaken for the whole picture:
shipped phases (0–23, 26–31, OPT) are archived, and every open item they left behind now lives in
the [Carried-over open items](#carried-over-open-items-from-archived-phases) register above;
**Phase 24 is `[~]` in progress** — everything but the dish count (73 of 120) and a `large`-preset
run is done, Phase 33 having closed the content half; **Phase 33 is `[~]`** — the windowed
leaderboard's SQL is built and pinned, its client is not;
**Phase 25 is designed-not-started** behind one remaining prerequisite (B043's tier calibration —
the public chef page and the SQL harness are both done) **and its schema is now superseded by
Phase 35b's `entities`**; **Phase 35 shipped 2026-09-12** — the legal pages, the identity
layer and the import, with 21,334 recipes in the local database; and **Phase 32** holds the 2026-08-26 audit's remediation items.

#### BL-1 — OPT-S8 (B018) — rotate the hosted seed passwords (owner action)

Nine seeded production accounts still carry the pre-fix literal passwords that were committed in
`seed.sql`. `supabase/scripts/rotate_seed_passwords.sql` is written and verified on the local stack
(16/16 rotated; recipes, ratings and profiles intact). **Deliberately not automated** — it writes to
`auth.users` on production, so no script or CI job may hold that credential.
**Trigger:** run it whenever you next have the hosted DB URL in a shell. Until then, treat those
accounts as compromised.
**Deferred once, knowingly (2026-08-25).** The Phase 29 hosted rollout had the pooler URI in a
shell — precisely the stated trigger — and the owner's call was to skip it as non-priority. Noted
so this does not keep reading as "the trigger has never come up": it has, once, and was declined.
**Closed by absence, measured 2026-09-14 (B115).** `select count(*) from auth.users` on the hosted
project returns **0**. There are no seeded accounts there to rotate, so there is no live credential
behind this item and nothing to treat as compromised on production. It stays written down rather
than deleted because the *local* stack is a different question and because the item's real lesson —
a literal password in a seed file becomes a production account by documented procedure (Gotcha 7) —
is still the rule. Re-open it the moment `seed.sql` is applied to a real database again; it is not
in `db:reset` or `config.toml` any more (B113), so that would have to be deliberate.

#### BL-2 — OPT-P11 — per-engagement-row `recompute_chef_stats` (accepted debt)

Every like and every first-view runs a full aggregate over the actor's public recipes (SDS §10.3).
Correct, and measured fine at sim `medium`. **Trigger:** a real engagement rate where writes
contend — revisit as an incremental delta or a debounced recompute before growth, not now.

#### BL-3 — B054 — `db:reset` leaves a stale sim registry (needs a decision, not a patch)

`drop.sql` never touches schema `sim` and spares `auth.users` by design, so a reset on a machine
that has run the sim leaves 1,000 simulated accounts and a registry describing recipes that no
longer exist; the next `db:sim` builds on the ghost and `3_sim_verify.sql` fails E9 or A7.
Making `drop.sql` drop schema `sim` is **worse** — it strands the `auth.users` rows with no
registry to delete them by. The right shape is `db:reset` running `9_sim_teardown.sql` first, which
makes `db:reset` a `--yes`-gated destructive action that deletes `auth.users` rows.
**Trigger:** owner's call on that gate. Workaround today: `melos run db:sim:clean -- --yes` before
a reset.

#### BL-4 — OPT-T4c — migrate to `freezed` 3.x

B005's permanent fix; unpins Flutter 3.44.8. Breaking model syntax across every `@freezed` class
plus a `build_runner`/`analyzer` bump and a full codegen + verification pass.
**Trigger:** the first time a newer Flutter is actually wanted. Its own change set, never the tail
of a batch.

#### BL-5 — seed & sim coverage register (read this when planning a feature)

Not a task — the standing list of what the fixtures **cannot** demonstrate, so a feature is never
designed onto data that does not exist. See the "Seed-data fit" gate in
[CLAUDE.md](../CLAUDE.md#seed-data-fit-mandatory). Known limits today:

- **`seed.sql` and the sim are TEST-ONLY and reach no default path (B113).** This is the first
  thing to plan around now: `melos run db:reset` builds the schema, the food registry and the 14
  curated recipes and *nothing else*, so a surface that needs accounts, engagement, a population or
  a ranked order is **empty after a reset** and needs `melos run db:seed` / `melos run db:sim` run
  on purpose. Say that out loud in the plan. Do not resolve it by putting either back in `reset` or
  in `config.toml` — `db:reset` ends in `db:audit --strict`, so that change fails CI by design, and
  the honest reading of an empty leaderboard is that it *is* empty until real people arrive.
- `seed.sql` **authors** counters (`like_count = 2500`) with no `recipe_likes` rows behind them, so
  any dated, windowed, or "who did this" query reads empty against demo data alone. The sim writes
  the rows and derives the counters — that is what makes SDS §10.8-style queries testable.
  `melos run db:audit` treats an authored counter as a *contradiction* and reports it as FAKE, which
  is correct for a fixture database and is why the audit runs before the fixtures in CI.
- **Curated content carries no engagement at all (B112).** Six of the 14 recipes used to author
  likes/saves/views/ratings through a `demo` block; it is retired and the validator refuses the key.
  So the Kitchen's `chef_score` is **0**, Discover → Popular has no ratings to rank and falls back
  to its site-mean prior, and a feature that needs a non-trivial engagement order needs the sim.
  This is the register's single biggest change — anything that used to demo on "seed alone" because
  of those six recipes now needs `db:sim`.
- The sim's time anchor is `sim.epoch_end()`, **pinned**, not `now()` (B044) — a feature that keys
  off "recent" must be checked against that anchor, not the wall clock.
- Teardown is registry-driven (B054 above), so a fixture a feature adds outside `sim.actor` /
  `sim.recipe` will not be cleaned up.
- 25 of a planned 120 simulation dishes are authored (Phase 24), so directory/category coverage is
  thin in places — check `simData/README.md`'s coverage rules before assuming a category populates.
- The 14 authored recipes top out at **85 minutes**, contain **no `hard`** difficulty and carry
  **no forks**, so a seed-only database cannot show anything ranked on long cooks or on lineage —
  Phase 26's shelves `02` and `03` are empty there by construction and say so on the page. Both
  need the sim.
- Fork **depth** comes from `sim.fork_bias` (Phase 26). Uniform source selection spreads forks one
  per recipe, which looks like data and ranks like nothing; anything ordered by fork count needs
  the weighted draw and the `≥ 3` assertion in `3_sim_verify.sql` §G.
- **Nutrition labels: `recipeData` is now real, the sim is still invented** (Phase 29d). All 14
  authored recipes carry a genuine label — 12 estimated from their own ingredient links
  (`source: 'auto'`), `fresh-guacamole` manual, `classic-margarita` null — so **all three editor
  modes demo on seed alone**, which was the gap the all-10 placeholders left. What seed still
  cannot give you is _scale_: anything needing hundreds of varied labels needs `db:sim`, where
  `sim.nutrition_for` draws one per recipe from a per-category profile (~80% of the population;
  the other 20% exercise the empty state). Three consequences. A sim label is internally
  consistent arithmetic but **not real nutrition data** for the dish named on the card, so nothing
  may present one as a fact about food. Sim labels carry **no `source`**, so they read as manual
  and `recompute_auto_nutrition()` never touches them — correct, but it means the _backfill_ has
  no sim coverage either; `supabase/tests/nutrition_fixtures.sql` is where it is exercised. The
  **hosted project carried 29d's labels** as of 2026-08-25 — but see the measured-2026-09-14 bullet
  directly below, which supersedes both that claim and the rollout note under it.
- **Hosted is EMPTY and pre-Phase-35, measured 2026-09-14 (B115) — every hosted claim below this
  line is stale.** The two bullets that follow describe the 2026-08-25 rollout and are kept for the
  lesson in them, not as a description of the database. What is actually there now: **0 recipes, 0
  profiles, 0 `auth.users`, 0 rows in every public table**, and a schema that predates 35a/35b/35c
  (no `entities`, `entity_members`, `profile_claims`, `import_blocklist`; no `recipes.is_imported`
  / `source_url` / `quality_score`; no `profiles.kind` / `auth_user_id` / `merged_into`;
  `profiles.id` still carrying its `auth.users` FK). It also has **no
  `supabase_migrations.schema_migrations` table**, which is why nothing caught the drift: there is
  no recorded version to compare against. That gap is now closed by `melos run db:hosted:check`,
  and the bullet above this one is the third time this register has been corrected by measurement —
  which is the argument for a command that measures instead of a note that claims.
- **Hosted was brought from Phase 27 to 29d on 2026-08-25 — and this register had it wrong.**
  It claimed hosted carried "the two all-10 placeholders and twelve nulls". It carried neither:
  Phase 28 had never been applied there, so `recipes.nutrition` did not exist as a column at all,
  nor did `food`, `ingredients.food_id`, `estimate_nutrition` or `recompute_auto_nutrition`. The
  last apply had been 2026-08-23 (Phase 27). **A claim about a database you cannot see goes stale
  silently** — this one was two phases out of date and was being planned around. Measure first.
  What the rollout took, in order: `pg_dump` of the public schema as the only undo (no PITR on the
  free tier), `0001_init.sql`, `nutrition_foods.sql` (78 foods / 277 aliases / 174 portions),
  delete the 14 kitchen recipes, re-apply `seed_recipes.sql`, verify. The delete was safe because
  it was **measured, not assumed**: those 14 carried 0 likes, 0 saves, 0 shares, 0 forks and all
  sat at version 1, their visible like/save/view counters are authored by `seed_recipe_v2`, and
  their 41 rating rows are the seed file's own demo ratings — so everything came back. Total cost
  was 4 rows in `recipe_views` (3 distinct viewers, so `view_count` fell by 1 on three recipes).
  Verified after: 12 `auto` / 1 manual / 1 null, 137 linked ingredients, and **0 drift** between
  the committed labels and what the hosted registry recomputes. Note the general shape — because
  `seed_recipe_v2` is not an upsert (Gotcha 16), delete-and-reseed is the _only_ way to push a
  content change to a database that already has the recipe, and whether that is acceptable is an
  engagement question to be answered with a query, not a guess.
- **The hosted project has no simulated population at all** — and as of 2026-09-14 no content
  either (see the measured bullet above; these numbers are from 2026-08-23 and no longer hold).
  Measured there 2026-08-23, straight after the schema apply: `recipes_quick` **10** rows,
  `recipes_projects` **1**, `recipes_most_forked` **0**. So `03 MOST FORKED` is legitimately empty
  on production until somebody forks something, and the shelf's own copy ("no public recipe has
  been forked") is the correct thing for a visitor to see there — it is not a bug report waiting to
  happen. Do **not** "fix" it by running `db:sim` against hosted: the sim writes ~1,000 `auth.users`
  rows and its teardown is registry-driven, so that is a one-way door on a real project. If hosted
  ever needs a populated fork tree, seed a handful of deliberate forks in `seed.sql` instead, where
  they are content rather than simulation.

#### BL-6 — environment-dependent verification gaps

Not code debt — things this machine cannot exercise. **Fork from the UI** is still unexercised
end-to-end; the **mobile/emulator** manual pass is blocked with no Android SDK installed.
**Trigger:** a machine with the Android SDK, and a local-stack session for the fork flow.

**Storage upload came off this list on 2026-08-26** (32a4), partly: an upload was driven against
the local stack's Storage API with a real signed-in JWT — the folder policy, the size limit and
the MIME allowlist all answered correctly. What is still unexercised is the **app's** picker path
(`image_picker` → `StorageService.uploadRecipeImage`), not the bucket contract it writes into.

**Screenshots are no longer on this list.** Chrome was installed 2026-08-22, so the B028 procedure
(release build + `npx serve` + Playwright) runs here; Phase 26 used it and Phase 23's outstanding
pass was completed at the same time.

**Dark mode has a procedure now** (2026-08-23). The browser cannot emulate `prefers-color-scheme`
after Flutter reads it at boot, so shoot the _app_ instead of the browser: pin
`themeMode: ThemeMode.dark` in `apps/app/lib/main.dart`, rebuild, screenshot, then revert and
rebuild. Check `git diff` on `main.dart` is empty before you call it done — the pin is a two-line
edit that is very easy to leave behind.

**Re-shoot on a new port after a rebuild.** `npx serve` plus the browser's HTTP cache will happily
keep serving the _previous_ build from the same origin: the light rebuild above rendered dark until
it was served on a different port, with `matchMedia` reporting light the whole time. There is no
service worker to blame (Flutter's is not registered in this build) — it is plain HTTP caching, and
it will make a revert look like it did not take.

What still cannot be driven here is a **tap inside the Flutter canvas**: web semantics do not come
up headlessly, so there are no DOM nodes to target and navigation has to be driven by URL.


#### BL-7 — the RLS acceptance matrix as a _signed-in_ user — **DONE (2026-08-23)**

Closed: [supabase/tests/rls_matrix.sql](../supabase/tests/rls_matrix.sql) (`melos run db:rls`) —
**177 checks** as of Phase 35c (102 when BL-7 closed, 137 after Phase 33, 165 after 35b) across
anon / owner / shared-with / stranger / imported chef, rolled back, wired into CI
(`database.yml`). Found B061 on its first complete run. **Standing rule:** any change to a policy,
a `security definer` function, or the column grants → run it, and add a check for any new surface
in the same change. Still not covered by the matrix: Storage bucket RLS (needs the storage
container, not SQL — though 32a4 exercised the bucket contract itself against the real API)
and the PostgREST edge (`packages/core/test/`'s recording client is the other half). Full history
and the coverage table: [archive/ROADMAP-phases-0-31.md](./archive/ROADMAP-phases-0-31.md#bl-7--the-rls-acceptance-matrix-as-a-signed-in-user--done-2026-08-23).

#### BL-8 — lint the ingredient unit vocabulary (B094 follow-up)

`unit` is free text in [tool/recipe_format.dart](../tool/recipe_format.dart) — it asserts the type
and nothing else. So the 2026-09-11 sweep that collapsed five spellings of tbsp/tsp into one
(B094, 246 rewrites across 245 files) is a **one-shot**: the convention now lives only in
`recipeData/schema.json`'s prose and both READMEs, and neither is read at runtime. Drift comes
back one authored recipe at a time, and the failure is silent twice over — the app renders whatever
string is there, and a spelling missing from `nutritionData/units.json` estimates to zero grams
rather than raising (which is how `tbsps` survived in seven ingredients).

The gate is cheap: `recipe_format.dart` already loads `nutritionData/foods.json` for the `food`
slug check, so loading `units.json` beside it costs nothing new. Two rules worth having, and they
are not the same severity — **error** on a spelling that resolves to a known unit but is not this
repo's canonical form (`Tbsp`, `tablespoons`, `grams`), and **warn** on a spelling absent from
`units.json` entirely (`knob`, `sprigs`, `sheets`, `gallons` — 18 such spellings survive the sweep,
each a real authoring decision, not a typo). Making the second one an error would block legitimate
content on a registry gap.

Two wrinkles to settle first, which is why this is a backlog item and not a one-line change: the
canon is **not** simply `units.json`'s keys — `L` is deliberately not `l`, and word units keep
their plural (`3 cloves garlic`, never `3 clove garlic`), so the canonical form has to be declared
somewhere rather than derived. And `simData/` shares the validator, so the gate lands on both
corpora at once.
**Trigger:** the next time a unit spelling is found wrong in review, or any change that touches
`recipe_format.dart`'s validation rules.

#### BL-9 — the hosted production rollout (tooling DONE, the deploy is an owner action)

Target: take the app live. Blocking fact, measured 2026-09-14: the hosted project is **empty and
three phases behind** (B115, and the corrected register bullet under BL-5). Shipping the current
client against it fails on `/explore`, `/entity/:id` and every `current_profile_id()` call — the
identity path, for every signed-in user.

- [x] **Detect the drift at all.** `supabase/scripts/schema_fingerprint.sql` +
      `tool/hosted_check.dart` → `melos run db:hosted:check`. Read-only; builds a fresh reference
      database from the repo and diffs a catalogue inventory. Missing-on-target exits non-zero,
      extra-on-target reports and does not (B116).
- [x] **Make the deploy one idempotent command.** `melos run db:hosted:deploy` =
      `create → nutrition → recipes → corpus → audit --strict`. No `drop`, so it is safe against a
      database holding real accounts; `--yes`-gated with the target named in the refusal message.
- [x] **Make `db:*` able to reach hosted from this machine at all.** `--docker` now applies to
      every step, not just `backup` (B033 closed).
- [x] **Rehearse the upgrade path rather than argue it.** Hosted's pre-change dump restored into a
      scratch database, the repo's schema applied on top (0 errors), full deploy run end to end
      (6m43s → 14 curated + 21,314 imported, **AUDIT CLEAN**), then `db:hosted:check` (in sync) and
      `rls_matrix.sql` (**177 passed, 0 failed**). The negative case too: against the pre-35 schema
      the checker reports 806 missing objects and exits 1.
- [ ] **Run it against hosted.** Owner action. `db:backup -- --docker --out=<dir>` first — the free
      tier has no PITR, so that dump is the only undo. Then `db:hosted:deploy -- --docker --yes`,
      then `db:hosted:check`, then `db:rls`. Budget well over the local 6m43s: the corpus is 71 MB
      of SQL over a Session pooler, not a loopback socket.
- [ ] **Decide whether the 21,314 captured recipes ship.** This is a product and rights call, not a
      technical one, and it is not settled by the tooling being ready. Without them production shows
      **14** recipes; with them the catalogue is overwhelmingly scraped content, which is exactly
      what the Rights page (35a) exists to state. `db:hosted:deploy` includes them; the
      `create → nutrition → recipes` prefix is the answer if the call goes the other way.
- [ ] **Size check before, not after.** The local database is **256 MB** against a 500 MB free-tier
      ceiling, and `recipes` alone is 130 MB of that. There is room, and not a lot of it.

**Trigger:** the next hosted session. Everything above the last three boxes is already built and
verified; what remains needs the production credential and one product decision.
