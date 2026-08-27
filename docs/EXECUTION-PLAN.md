# EXECUTION-PLAN — Secret-Sauce

Execution detail for the tasks in [ROADMAP.md](./ROADMAP.md). For each phase: approach, key
files, and acceptance criteria. Kept in sync with the code.

---
> **Shipped phases are archived.** Execution detail for completed Phases 0–23, 26–31 and
> Phase OPT lives in [archive/EXECUTION-PLAN-phases-0-31.md](./archive/EXECUTION-PLAN-phases-0-31.md).
> This file carries only work that is open: Phase 24 (in progress), Phase 25 (designed, not
> started), Phase 32 (audit remediation), and the ops reference.

---

## Phase 24 — Simulated population: a realistic user + engagement dataset

Roadmap: [ROADMAP.md Phase 24](./ROADMAP.md#phase-24--simulated-population-a-realistic-user--engagement-dataset) ·
Design: [SDS §12](./SDS.md#12-the-simulated-population) (written 2026-08-25)

**Status: working end to end at the `medium` preset.** Built 2026-08-20: the shared validator,
`tool/sim.dart`, `simData/` with **25 of 120** dishes, all five `supabase/sim/*.sql` files, the
`melos run sim:* / db:sim*` scripts, and the CI gate. `melos run db:reset` now rebuilds the whole
thing — 1,694 recipes, 1,016 profiles, ~118k view rows — from an empty database in **~15 seconds**,
and `3_sim_verify.sql` passes all 46 assertions.

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

This script is the only test coverage this phase gets. It was written when nothing in CI ran SQL at
all, and was the strongest argument for the CI database job — which **OPT-T1 then built**
(`.github/workflows/database.yml`), so the assertions now run on every push against a `tiny`
population instead of only when someone remembers to.

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

1. Public chef page `/chef/:id` — the standing prerequisite, now **planned as its own
   [Phase 30](./archive/EXECUTION-PLAN-phases-0-31.md#phase-30--public-chef-page-chefid)** rather than step 1 here. The restaurant page
   copies its shape, and every existing `ChefBadge` becomes tappable. Two corrections to what this
   line used to assume: the recipe grid is a **paged table read**, not a wider `chef_top_recipes`
   (adding `p_offset` to that function is the B024 overload trap), and the page needs a new
   `chef_standing(p_chef)` RPC because a URL carries a uuid while the existing dialog was handed a
   whole `ChefStanding` — rank is a `dense_rank()` over the population and cannot be derived from
   one row.
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

## Phase 32 — Audit remediation

Roadmap: [ROADMAP.md Phase 32](./ROADMAP.md#phase-32--audit-remediation-planned-2026-08-26).
Source: the 2026-08-26 audit (app layer, shared packages, SQL/tooling/CI — full read-throughs,
every claim cited to file:line at audit time; re-verify a line number before editing, the tree
moves). **Work band by band; each band is its own change set with its own verification.** SQL
items obey the standing rules without exception: edits go into `0001_init.sql` idempotently
(pre-release baseline, Gotcha 5), historical function signatures dropped in-file (B024), every
policy/grant change gets a `rls_matrix.sql` check **proven non-vacuous** (break the code, watch
the check go red, restore), then `melos run db:rls` and the Gotcha 6 upgrade path locally before
anything hosted.

### 32a — SQL integrity & security

**32a1 — fork-lineage forgery — DONE 2026-08-26.** `forked_from_recipe_id` /
`forked_from_version_id` sat in both column-grant lists and `save_recipe` assigned them from the
payload in both branches, so an owner could PATCH or save fake lineage — and
`recipes_most_forked` ranks on it. What shipped, and the two places it went further than this
plan first called for:

1. **Both** grant lists lost the columns, not just update. The plan said "keep insert"; there is
   no legitimate client create carrying lineage, because `fork_recipe` (`security definer`,
   unaffected by grants) writes its own row and the editor then *updates* it.
2. `save_recipe` update branch: the two assignments are simply **gone from the SET list**, so the
   row keeps what `fork_recipe` wrote. That also closed **B088** — the old unconditional
   assignment erased lineage for any caller that omitted the keys.
3. `save_recipe` insert branch: **raises `42501` on any non-null lineage**, rather than the
   plan's "null or `can_read_recipe`". Readable-or-null was the wrong bar: your own public recipe
   is readable, so it still permits self-fork farming — which is what item 5 handles instead.
4. `_writablePayload` **drops both keys** (the plan said keep-and-comment). With the server
   ignoring them on update and rejecting them on insert, sending them could only ever be a no-op
   or an error. `recipe_repository_test.dart` pins their absence from a draft that carries a
   non-null lineage, so the assertion is about dropping a value, not echoing a null.
5. **`recipes_most_forked` counts distinct forkers other than the source's owner.** Grants cannot
   reach this half: forking your own public recipe is honest behaviour, twenty times over is
   farming, and a raw `count(*)` cannot tell them apart. Gotcha 10 / B012's distinct-signed-in-
   actor rule, applied to lineage. `3_sim_verify.sql` **G3** was recounted the same way — a guard
   that measures something the shelf does not is a guard on nothing.
6. Matrix: **B9b** (PATCH lineage → 42501), **B9c** (INSERT lineage → 42501), **B23b**
   (`save_recipe` create claiming lineage → 42501), **B23c** (update keeps the stored value, via a
   real `fork_recipe` fork saved with a payload naming a different source), **F11** (a published
   self-fork does not rank). 102 → **107 checks**.

**Trap that held:** `seed_recipe_v2` and the sim's insert write these columns as `postgres`, so
they are unaffected by grants — they were correctly left alone.

**Verified:** upgrade-path apply exit 0; `db:rls` **107 passed / 0 failed**; every new check proven
non-vacuous — B9b/B9c/B23b/B23c against a schema with all four halves reverted, and **F11
separately against its own clause**, because under the combined break the update branch also wiped
lineage (B088) and F11 then passed for the wrong reason. `nutrition_estimate` /
`nutrition_fixtures` green (the `save_recipe` edit is in their path), `3_sim_verify` ALL CHECKS
PASSED with the shelf unchanged at 6 rows and 0 self-forks in the population — so the ranking
change is a measured no-op on honest data. `melos run analyze` clean; `test --no-select` SUCCESS
(core 130, app 246). Fresh apply left to CI: the change adds no new object, so B045 does not apply.

**32a2 — CHECK constraints + length caps — DONE 2026-08-26.** Five constraints via the guarded
`do $$ … pg_constraint` pattern, each beside its own table: `recipes_servings_positive`,
`recipes_minutes_nonneg`, `recipes_text_lengths` (title 200 / description 10 000),
`profiles_text_lengths` (display_name 80 / bio 500), `ingredients_quantity_positive`.

**Measured before written**, as the plan required: over seed + sim `medium` the real maxima are
title 58, description 319, display_name 51, bio 69, servings 1–24, and **zero** rows violating any
proposed bound — which is what makes the constraints safe to add, since a check validates existing
rows and an apply that trips one aborts mid-file.

Two things the plan did not anticipate, both about where the failure surfaces:

- **`handle_new_user` clamps rather than rejects.** It copies `display_name` out of unvalidated
  signup metadata *inside the signup transaction*, so a constraint violation there would not refuse
  a display name — it would refuse the **account**. It (and the B015 backfill beside it) now wrap
  the value in `left(…, 80)`. Same spirit as the `on conflict do nothing` it already carried.
- **The editor states the same rules first.** The Qty field became a `TextFormField` with a
  validator (empty is legal — "to taste" is a real ingredient with no quantity; `<= 0` and
  unparseable are not), and title/description carry `maxLength` with **`counterText: ''`** — the
  enforcement without the `0/200` counter, which would otherwise add a band of text under two
  fields that the editor's 320/360/600 × 2.0× envelope suite measures.

**Three things `/code-review` changed, all of them scope the first cut had drawn too small:**

- **The cap covers all six text columns `kRecipeSelect` ships**, not two. `attribution`, `cuisine`,
  `category` and `cover_image_url` are in the same select *and* both grant lists, so bounding only
  `title` and `description` left the identical amplifier one column over. Measured too (attribution
  51, cuisine 13, category 9, cover_image_url 0) before the bounds were written.
- **`recipes_text_lengths` is `not valid`.** "Measured first" had been measured against
  fixture-built databases whose generators *already* enforce these bounds
  (`tool/recipe_format.dart` gates servings 1–100, minutes 0–1440, quantity positive-or-null for
  both `recipeData/` and `simData/`), so it proved nothing about the rows that can actually
  violate: a description typed before the editor had a `maxLength`, a display_name from a signup
  before `handle_new_user` clamped. Those exist only on a populated database, and `psql -1` rolls
  back the **whole file** on one bad row. `not valid` enforces every future write and scans nothing
  already there; promoting it is a deliberate `validate constraint` once a table is known clean.
  `profiles` takes the other shape — clamp, then constrain — because truncating a display name is
  what `handle_new_user` already does on every signup, while truncating a cook's prose is data loss.
- **`servings` / `prep` / `cook` gained validators.** Typing `0` in Servings passed
  `Form.validate()`, reached the RPC, and came back as `23514` → *"Some of that information is not
  valid"*, naming none of the editor's fifteen fields. The constraint without the validator moves a
  silent corruption to an unattributable error.

**And one defect of its own making, which is why the matrix gained the conjunct checks.** `if not
exists` on a constraint keys on the **name**: the six-column `recipes_text_lengths` was a silent
no-op on this machine, because the two-column version already existed under that name. Same shape
as B024 for functions, and the fix is the same — drop the superseded definition explicitly in the
file that recreates it. Free to repeat here precisely because the constraint is `not valid`.
`profiles_text_lengths` keeps the plain `if not exists` guard (a re-add would rescan every profile
row — the cost OPT-A6 removed from the deferred FKs) with the rule stated inline for the next edit.

**Verified:** apply over the running database exit 0, **twice** (idempotent); `db:rls`
**117 passed / 0 failed** — B9d–B9i, B11a/B11b, B13a/B13b, where B9i and B13b pin that NULL stays
legal where it means *absent*. Non-vacuity: the deny-checks go red when the constraints are
dropped, the NULL-legal pair stays green, and B9h is the check that caught the name-guard bug.
`nutrition_estimate` / `nutrition_fixtures` / `3_sim_verify` all green (the constraints sit on
tables all three write). `melos run analyze` clean; `test --no-select` SUCCESS (app 247, +1 for the
Qty validator's test, which asks the validator directly for the passing cases — a form that
validates goes on to read a repository this suite has no client for).

**32a3 — the unasserted policies — DONE 2026-08-26.** Seven checks, 117 → **124**. Each covers
something that was true only because nothing contradicted it:

- **D29 — `tags` UPDATE.** Its security is *policy absence*: select/insert/delete exist, update does
  not. Asserted as **0 rows, not an error** — RLS with no matching policy filters rather than
  raises (Gotcha 2), so an error assertion here would fail forever. Proven by adding a
  `tags_update` policy and watching it go red.
- **D30 — forged `profiles` insert.** Against `gen_random_uuid()`, deliberately: aiming it at
  another fixture user's id makes the primary key the thing that refuses (`23505`) and the check
  passes while proving nothing. With a fresh id the policy is the only thing in the way.
- **D25 / D25a / D25b — `recipe_suggestions`.** The refusal was already covered; the *permission*
  was not, and a refusal-only pair passes just as well under `with check (false)`. D25b is the new
  hole: `suggestions_update` had `using` and no `with check`.
- **D31 — the share row is invisible** to someone it was not granted to.
- **A7 / A8 — anon's deliberate write.** `anon` holds `insert on recipe_views` on purpose and
  B012's whole design follows from it. Pinning a *permission* the way denials are pinned makes
  tightening it a decision somebody takes rather than a line somebody deletes; A8 is its twin —
  the row lands, the counter does not move — asserted as a **delta**, because other checks in the
  file log views too.

**`recipe_suggestions` is written through column grants**, the B050 instrument, not through the
policy: `insert (recipe_id, from_recipe_id, author_id, summary, payload)` — `status` omitted, so
the `'open'` default is the only way in and a proposer cannot file their own suggestion
pre-`accepted` — and `update (status)` **alone**.

**The first cut got that grant wrong, and the review is what caught it.** It also granted
`summary`/`payload`, justified as "an author editing their own wording is a legitimate future
feature". The policy contradicts that justification: `suggestions_update` is
`using (owns_recipe(recipe_id))`, so the only principal an update grant can empower is the
**recipe's owner**. Granting the proposal's own text therefore let the owner rewrite someone else's
words under that person's name — the same misattribution this band exists to close, one column
over, and reachable over PostgREST with any signed-in JWT. An author-edit flow needs the *policy*
to admit the author first, and `status` would have to leave the author's reach in the same change.

Two more corrections from the same pass. The added `with check (owns_recipe(recipe_id))` is
**unreachable** — `recipe_id` is ungranted, so a client statement fails `42501` at the privilege
check before RLS is consulted, and every column a client *can* write leaves the expression's value
unchanged; it is kept as belt-and-braces for the day the grant list widens, and the docs now say
that rather than crediting it with the fix. And the **fixture share is `edit`, not `view`** —
`share_permission`'s `edit` is reserved and ignored by every policy, so sharing at the stronger
level costs nothing and upgrades all eleven section-C refusals from "a viewer cannot write" to
"not even an `edit` share is a write right". **C3 now asserts the literal**, because a fixture
change no check observes is a comment, not coverage.

**Verified:** apply exit 0, twice; `db:rls` **126 passed / 0 failed**. Non-vacuity by breaking each
lock in turn and restoring: A7 (revoke anon's insert), D25b (hand back the blanket update grant),
D29 (add a `tags_update` policy), D30 (widen `profiles_insert` to `true`), D31 (add a delete
policy), D33 (grant `summary` back), C3 (revert the fixture to `view`). D32 is the positive one —
the owner *can* move `status` — without which a change locking the owner out entirely would pass
every other check in the file. `nutrition_estimate`, `nutrition_fixtures`, `3_sim_verify` green.
No Dart changed, so `analyze` and `test` were not re-run for this band.

**32a4 — Storage hardening — DONE 2026-08-26.** Both buckets carry `file_size_limit = 5242880`
and `allowed_mime_types = {image/jpeg, image/png, image/webp}`, matching what the app actually
sends (one image from `image_picker`). Written as a guarded `update storage.buckets`, **not** as
part of the `insert … on conflict do nothing`: the buckets predate this, so folding it into the
insert would land on a fresh database and silently skip every database that already has them —
32a2's constraint-guard trap, one object type over.

**Verified through the real Storage API**, which is the only layer that can enforce this: RLS sees
an object row, not the bytes or the declared MIME type, so no `rls_matrix.sql` check can reach it.
A throwaway signup against the local stack, then four uploads to `recipe-images/<uid>/`:

| Upload | Result |
| --- | --- |
| 2 KB `image/png` | **200** — the normal path still works |
| 6 MB `image/png` | **413** `Payload too large` |
| 6 B `text/plain` | **415** `invalid_mime_type` |
| valid png into another user's folder | **403** — the pre-existing folder policy |

Non-vacuity, per lock rather than in aggregate: with both columns set back to null, **row 2 flips
200** (the size limit is what refused it) and **row 3 flips 200** (the MIME allowlist is what
refused that one). Row 1 was 200 either way and proves only that the normal path still works; row 4
is the pre-existing folder policy and is unaffected by this change. The throwaway user and all
three objects were removed afterwards — note `storage.objects` refuses a direct `delete` ("Use the
Storage API instead"), so cleanup goes through the API with the service key.

**Two things the review corrected about what this change is.** The threat it closes is *one object
of unbounded size and any declared type* — **not** quota exhaustion: a per-object limit says
nothing about object *count*, and nothing here caps per-user total bytes. And the app does not
send what the allowlist implies: `StorageService` declares `image/jpeg` on **every** upload (a
default no call site overrides) and `uploadAvatar` has no callers at all, so nothing in the app
writes `avatars`. Two consequences worth keeping — the MIME allowlist cannot break the app path
(and `image/png`/`image/webp` are entries for a client that does not exist yet), and **the size
limit is the load-bearing half**.

Which is why the editor now checks bytes itself against `kMaxUploadBytes` in `core` (the layer that
knows the bucket, mirroring `file_size_limit` the way `ChefScoring` mirrors the score weights).
`maxWidth: 1600` does not keep uploads under 5 MB on its own: the Windows and Linux `image_picker`
implementations ignore their options outright, web skips the resize for gifs, and Android
re-encodes an alpha-bearing pick as lossless PNG. Without the guard the refusal surfaces from
inside `_save`, so the *save* appears to fail and the message names no size. `_pickCover` also
gained the try/catch that 32c4 was going to add and an `imageQuality: 85` that shrinks the common
case.

**This also closes half of a standing BL-6 gap**: "Storage image upload unexercised end-to-end" was
true because nobody had driven an upload from outside the app. It has now been driven — what
remains unexercised is the *app's* picker path, not the bucket contract.

### 32b — SQL performance — DONE 2026-08-26

Nine indexes added, two dropped. Postgres indexes the *referenced* side of a foreign key
automatically and the *referencing* side never, so every unindexed FK column turns a delete on the
other table into a seq scan — once per cascaded row. Added beside their own tables:
`recipes(current_version_id)`, `recipes(forked_from_version_id)`,
`recipe_versions(parent_version_id)`, `recipe_views(user_id)`, `recipe_tags(tag_id)`, all three of
`recipe_suggestions`', and the partial `recipe_views (recipe_id, viewed_at desc, user_id)` behind
`chef_trending_recipes`. Dropped: `recipes_visibility_idx` and `recipes_rating_idx`.

**Measured, warm, one index at a time** (sim `small` — 455 recipes, 1,044 versions, 20,630 views):

| Path | Before | After |
| --- | --- | --- |
| Delete a 9-version recipe — its three version-FK triggers | 0.52 / 0.84 / 0.63 ms | 0.09 / 0.11 / 0.12 ms |
| Delete a profile — the `recipe_views` FK check | 1.61 ms | 0.54 ms |
| `chef_trending_recipes`, busy chef, warm | 0.62–0.65 ms | 0.31–0.34 ms |

**The first measurement said the opposite, and that is the part worth keeping.** Run immediately
after building the indexes, the profile delete looked **3× slower** (32 ms vs 2.5 ms) — cold caches
on a freshly built index, read as a regression. Acting on it would have removed the index that is
in fact 3× faster once warm. Re-measured with `analyze` and repeated runs, and A/B'd the two
`recipe_views` indexes separately, which is what separated "the trending index costs a little
maintenance on set-null updates" (true, 0.54 → 0.84 ms with both) from "the user index is a
regression" (false).

**Two things this data cannot show, stated rather than implied.** `recipe_versions.parent_version_id`
is **null on every row** in a generated population — the sim never chains versions, though
`save_recipe` sets it — so its index is empty here and the 5.5× improvement above is the FK *check*
becoming an index probe rather than a scan, not a lookup returning rows. And `recipe_tags` is empty,
so `recipe_tags_tag_idx` is reasoned-for, not measured: the three readers that key by tag are the
`tags_delete_orphan` policy probe, `on_tags_search_change`'s join, and the FK behind a tag delete.

**Verified:** apply exit 0 twice; `db:rls` 127/0; `nutrition_estimate`, `nutrition_fixtures`,
`3_sim_verify` green; the two dropped indexes confirmed absent and all nine new ones present. No
`drop.sql` entries needed — indexes die with their tables. No Dart in the change.

### 32c — App correctness — DONE 2026-08-26

Five items, one change set, no SQL. What each turned out to be:

**32c1 (B084) — one fork handler.** `forkRecipe(context, ref, recipeId)` in
[fork_action.dart](../apps/app/lib/features/recipe_detail/fork_action.dart) is the only fork path
now. The two call sites disagreed in three ways, not one: the finish screen guarded the signed-out
case and the reading page fired the RPC and rendered the denial (B084); the finish screen navigated
to the fork's *reading* page and the reading page to the editor; and the error copy differed. The
merged handler takes the guard, the editor (a fork exists to be changed, and the copy is private
until its owner says otherwise), and `Could not fork — …`. The messenger is captured **before** the
`await`, because the success path `go`es away from the context that would have to show the snackbar.

**32c2 (B085) — `PopScope`, and the half it cannot reach.** `canPop: !_dirty` over the editor's
`Scaffold`, `onPopInvokedWithResult` and the close button both calling `_confirmDiscard()`. Dirt is
a flag, not a diff: the seven text controllers get listeners in `initState` and every other mutation
already reported itself through an `onChanged`. `_load()` re-baselines and resets it in its
`finally` — filling the fields fires those listeners, so without that every freshly-opened recipe
would arrive "edited".

**The flag has to compare text, not trust the notification** — the review's catch. A
`TextEditingController` is a `ValueNotifier<TextEditingValue>`, and that value carries the
**selection**: tapping into Title moves the caret and fires every listener without a character
changing. Trusting the callback would have reinstated the nag this item exists to remove, one step
later in the story ("open a recipe, tap a field, read it, back out → Discard changes?"). So the
listener diffs each field's text against a baseline captured at load, which also means a character
typed and deleted again comes back clean. Its test enters the *same* string and asserts no dialog;
pointing the listener back at the unconditional setter fails it, which is how the test was proven
non-vacuous.
**Web browser Back is deliberately not covered.** It arrives as new route information for the
`Router`, not as a pop, so nothing consults `PopScope`; claiming B085 closed on web would have been
false. Said in the code, the tracker and the ROADMAP.

**32c3 — the servings scaler is session-scoped.** It was `StateProvider.autoDispose.family` while
`cook_step_view.dart`'s comment said "the provider is not autoDispose precisely so the choice
survives the navigation". The comment described the behaviour the product needs, so the declaration
moved: plain `.family`, the lifetime `checkedIngredientsProvider` and `doneStepsProvider` already
have. Concretely it was a **B066 instance** — scale to 8, walk into cook mode, come back to a page
saying 4 while cook mode says 8.

**32c4 — three hardenings (the fourth had already shipped).** The share dialog captures its
`ScaffoldMessenger` before `Navigator.pop`; the two editors do remove → rebuild → dispose, with the
dispose in a post-frame callback so the row's element is gone before its controllers die (disposing
first worked only because the removal happened in the same frame); and cook-mode timers became
**deadlines**. `_pickCover`'s try/catch landed with 32a4.

The timer rework is the one with a trap in it. A deadline is read from a clock, and
`tester.pump(Duration(seconds: 1))` advances Flutter's fake timer queue while `DateTime.now()` does
not move — so a straight `DateTime.now()` deadline passes analysis, ships, and leaves every
countdown test frozen. Hence `cookClockProvider`, defaulting to `DateTime.now` and overridden in the
suite with `tester.binding.clock.now`, which the same pump *does* advance. Every existing timer test
then passed unchanged, which is the evidence that the model change was behaviour-preserving; the new
one drives a hand-rolled clock ten minutes forward while delivering a single tick — the case a
counter cannot represent and a backgrounded app produces for real. `_tick` recomputes rather than
subtracts, `pauseTimer` banks the exact balance, and `addMinute` re-stamps from **now** (adding a
minute to a deadline already in the past buys nothing).

**32c5 — four dedupes.** One rating handler
([rating_actions.dart](../apps/app/lib/features/recipe_detail/rating_actions.dart)) for the reading
page and the finish screen — same write, same two invalidations, same three strings, two files.
`popOrGo(context, fallback)` replaced four copies of `canPop ? pop : go`; it lives in
[routing/](../apps/app/lib/routing/pop_or_go.dart) rather than the `widgets/` the plan named,
because it is not a widget, and it asks the **Navigator** rather than `GoRouter.canPop()` — the
expanded detail header asks the same question during `build`, and a test that pumps a screen without
a router must not throw there. `ForkedLabel` / `AttributionBlock`
([detail_provenance.dart](../apps/app/lib/features/recipe_detail/detail_provenance.dart)) carry the
two provenance blocks for both layouts, with the two real differences kept as parameters (`expand`,
`boxed`) rather than flattened away. And the cook rail's `SizedBox(width: 74)` is now the reading
rail's `kIngredientQuantityGutter × textScale.clamp(1.0, kDetailRailMaxScale)`; the hardcoded number
did not grow with the type, so `1.25 cup` wrapped to three lines at 2.0× on the surface where the
cook is holding a pan.

**Verified:** `melos run analyze` — **No issues found** in all three packages;
`melos run test --no-select` — **core 130 / design_system 119 / app 261, all passed** (app was 245
before: +16). `melos run format` reformatted 5 files. New tests: fork ×3 on the reading page and ×3
on the finish screen, the servings-lifetime round trip, six editor-leaving tests driven through
`handlePopRoute()` (including the caret-move one above), and the suspended-clock timer. No SQL changed, so no `db:*` run was needed.

### 32d — Shared-package hygiene

- **32d1** — remove `rating_sum` from `kRecipeSelect`
  ([recipe_queries.dart](../packages/core/lib/src/repositories/recipe_queries.dart)); fix the pin
  test's label (it currently lists `rating_sum` under "every column Recipe decodes" — false); add
  the **inverse** test: every column in the select decodes into a `Recipe` field, so
  fetched-but-never-decoded drift fails loudly. Count moves 25 → 24; update the pin.
- **32d2** — export one trim helper from
  [formatting.dart](../packages/core/lib/src/formatting.dart), delete `formatNutritionValue`'s
  byte-identical body (keep the name as a one-line delegate if call sites are many); route
  `RecipeCard._timeLabel` through `formatMinutes` so card and facts strip agree (`1h 10m` vs
  `1 h 10 m` today — pick **one** rendering, update whichever tests pin the other).
- **32d3** — `searchByName`: server orders + limits **before** the client ranks. Over-fetch
  (`limit * 3`, cap 40) then rank client-side, or add an `ilike` prefix pass first. Create
  `profile_repository_test.dart`: `_escapeLike` (literal `%`/`_` in queries), exact-beats-prefix-
  beats-contains, the id tie-break, and `updateMine`'s payload omitting every server-owned column
  (that omission is a documented invariant with no pin today).
- **32d4** — `StorageService` signed-out `StateError` message → `'Not authenticated.'` (the string
  `friendlyError` already matches); add `StorageException` mapping test.
- **32d5** — in `recipe_repository_test.dart`: `delete()` and `unshare()` returning empty →
  `WriteDeniedException` (the OPT-S2 contract, untested); `listByChef` sends
  `visibility=eq.public` (the load-bearing filter — without it an owner sees their own private
  rows on their public page).
- **32d6** — delete `responsiveColumns` (zero call sites) and amend CLAUDE.md Gotcha 13's claim in
  the same commit; delete the dead `notYetTooltip` re-export in `chefs_hero.dart`; move
  `not_yet_tooltip.dart` → `design_system` with barrel export (Gotcha 14) and update importers;
  add `AppRadii.pill = 999` and sweep all 22 `BorderRadius.circular(999)` sites (12 files).

### 32e — Test coverage

- **32e1** — `profile_screen_test.dart`: loading / error / data states, sign-out lands on
  `/discover` (not `/`), avatar initials fallback.
- **32e2** — reading-page rating write: make both detail suites' `setRating` fakes record; assert
  save, clear, invalidation, and the failure snackbar through `RatingSection` itself. Editor save
  path: drive `_save` to `repo.create` (new) and `repo.update` (edit), assert `_canSave` blocks
  until loaded, success navigates, failure snackbars — today no test calls either repo method.
- **32e3** — version-history sheet: one suite hands `versions()` real rows; assert list order,
  "Current" chip, and the empty state copy.

### 32f — CI & operations

- **32f1** — `ci.yml`: add `dart format --set-exit-if-changed .` (or `melos run format` + git
  diff check — pick the one that respects the melos exit-code caveat, B006/B007).
- **32f2** — `database.yml` calls `dart run tool/db.dart` for the apply pipeline instead of
  restating it in bash. Needs `psql` on the runner (`apt-get install postgresql-client`) and
  `SUPABASE_DB_URL` pointing at the **runner-local** stack only — the no-hosted-secret rule
  (Gotcha 7) is about secrets, not the variable name; the workflow keeps zero repository secrets.
  Kills the three-copy pipeline definition (db.dart / workflow / `config.toml`).
- **32f3** — pin `supabase/setup-cli` to an exact CLI version (record the Postgres major it
  ships); move the `rls_matrix` + `3_sim_verify` steps to run **after the upgrade path too**, not
  only the fresh apply.
- **32f4** — new CI job: `flutter build web --release --dart-define-from-file=env.example.json`
  (example creds compile fine; the job proves compilation, not runtime).
- **32f5** — `db:backup` melos script (B079 container form, 17-series client), two dumps:
  `pg_dump --schema=public` as today, **plus the auth data** — `pg_dump --data-only
  --table=auth.users --table=auth.identities` (never auth DDL: a fresh Supabase project already
  owns the `auth` schema as `supabase_auth_admin`, so a schema-level auth restore collides on
  ownership). Output timestamped; restore procedure documented in README (order: auth data before
  public — the FKs point that way). Storage objects: document that they are **not** covered and
  what is lost.
- **32f6** — write the baselining runbook in
  [supabase/migrations/README.md](../supabase/migrations/README.md): when the 0001-editing era
  ends — `supabase migration repair --status applied 0001` (verify the exact incantation against
  the pinned CLI version first), then numbered files resume, then `db push` behaves. Half a page,
  written now, executed once, under no pressure.

### Order of work

32a1 → 32a2/32a3 (one matrix session) → 32b (one SQL session) → 32a4 · then 32c/32d/32e in any
order, each its own change set · 32f last (CI edits are cheap to review together). After every
SQL band: `melos run db:rls`, both easy paths, the upgrade path, and — because 32a1 touches
`save_recipe` — `melos run db:nutrition:estimate` + `db:nutrition:verify` (its estimator branch
must not regress).

### Seed-data fit — outcome 1: existing data covers it

Hardening over existing behavior; no new entity, no new fixture shape. The matrix makes its own
throwaway users/recipes (32a checks ride there); 32a2's bounds are validated against seed + sim
`medium` before commit; 32b's `explain analyze` acceptance runs against the sim at `medium`.
Nothing here needs a new authored recipe, seed account, or sim distribution.

### Risks, stated

- 32a1 changes `save_recipe` — the single save path for every client write. The matrix +
  `nutrition_estimate.sql` + the app's editor round-trip tests are the net; run all three.
- 32a2 can brick an apply over data that violates a bound (constraint adds validate existing
  rows). Measure maxima first; the upgrade path in CI is the regression net afterwards.
- 32c4's timer rework touches cook mode's core loop; the pure-model tests in
  `cook_mode_test.dart` must be re-read, not just re-run — they may assert tick semantics that
  the deadline model changes legitimately.
- 32f2 makes CI depend on `tool/db.dart`'s exit behavior on Linux (melos exit codes propagate
  correctly there per B006/B007 — the caveat is Windows-only, but verify once in the PR).

---

## Build, run & release (ops)

Task runner is **melos** (`melos.yaml`); Gradle only builds Android. See `README.md` for full
detail. Key facts to keep in sync:

- **Run (dev):** web-server is the most reliable device here —
  `flutter run -d web-server --web-port 8080 --dart-define-from-file=env.local.json` (open
  `http://localhost:8080`). Chrome is installed (2026-08-22) but the debug web server renders for
  one client only (B028); Edge auto-launch is flaky; `-d windows` works.
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
