# EXECUTION-PLAN — Secret-Sauce

Execution detail for the tasks in [ROADMAP.md](./ROADMAP.md). For each phase: approach, key
files, and acceptance criteria. Kept in sync with the code.

---
> **Shipped phases are archived.** Execution detail for completed Phases 0–23, 26–31 and
> Phase OPT lives in [archive/EXECUTION-PLAN-phases-0-31.md](./archive/EXECUTION-PLAN-phases-0-31.md).
> This file carries only work that is open: Phase 24 (in progress), Phase 25 (designed, not
> started — its schema is absorbed by Phase 35b), Phase 32 (audit remediation), Phase 33 (SQL
> shipped, client open), Phase 35 (the corpus becomes product — shipped
> 2026-09-12), and the ops reference.

---

## Phase 24 — Simulated population: a realistic user + engagement dataset

Roadmap: [ROADMAP.md Phase 24](./ROADMAP.md#phase-24--simulated-population-a-realistic-user--engagement-dataset) ·
Design: [SDS §12](./SDS.md#12-the-simulated-population) (written 2026-08-25)

**Status: working end to end at the `medium` preset.** Built 2026-08-20: the shared validator,
`tool/sim.dart`, `simData/` with **73 of 120** dishes (120 since 2026-09-24), all eight `supabase/sim/*.sql` files, the
`melos run sim:* / db:sim*` scripts, and the CI gate. `melos run db:reset` now rebuilds the whole
thing — 1,694 recipes, 1,016 profiles, ~118k view rows — from an empty database in **~15 seconds**,
and `3_sim_verify.sql` passes all 53 assertions.

**Two decisions below were reversed by what the build found**, and both are worth reading before
trusting the rest of this section:

- **`db:reset` ran the sim for three weeks, and no longer does (reversed again by B113).** The
  2026-08-20 decision was to add it at the owner's request, on the grounds that `engage_existing`
  is false so every pinned standing survived. That reasoning was sound and still is — the defect
  was elsewhere: with the sim (and `seed.sql`) on the default path, the only convenient way to
  build a database produced one whose chef leaderboard was 62 invented profiles against 1 real
  one, and the hosted project had been built that way too. Both are test-only now and `reset`
  ends in `db:audit --strict`, so the original table entry below ("**No.** Reset stays fast, and
  the standings stay reproducible") is the state of the world again, for a second and stronger
  reason. Build the population on purpose with `melos run db:sim`.
- **`master_chef` is not organically reachable at `medium`**, and that is a finding about the
  product rather than the generator — see B043 and "What the dataset proved" below.

**Phase 33 closed the content half** (2026-09-10). `simData/people.json` (17 locales, 544 names, 26
bios) and `simData/vocab.json` (66 tags, 40 title templates) are authored, validated by the same
`tool/sim.dart` that gates the dish library, and loaded by two new generated files — so the tool now
has three sources, three outputs and one `sim:check`. `sim.rand_zipf` draws the tag vocabulary, the
per-persona RLS smoke runs as `melos run db:sim:rls`, and `3_sim_verify.sql` grew group **H** (7
checks) to cover all of it.

Three things that move happened on the way, in ascending order of how quietly they would have gone
wrong:

- **The title templates moved out of `0_sim_schema.sql` and into `vocab.json`** — and the move was
  left half-done, with the rows deleted from the schema file before the loader that replaces them
  existed. `sim.title_variant` is `cross join`ed, so an empty pool generates **zero recipes and
  reports success**. The generator's preflight now refuses every empty or non-dense pool by name.
- **Names are drawn per locale, not per pool.** The old flat `array[…]` literals drew the given and
  the family name independently across every tradition, so roughly fifteen names in sixteen were
  two-culture collages. An actor now draws a locale once and the given name, the family name and
  the bio's `{cuisine}` all read that row. Check **H3** asserts it as a property.
- **B093.** `sim.recipe.slug` is written once (`on conflict (n) do nothing`) and goes stale when
  the library changes; joining through it put `one-pot` on a Sauce. Check **H7** caught it on its
  first run, on the fresh path only.

Still outstanding: 47 more dishes and a run at the `large` preset.

**Problem.** The database has 21 accounts and 23 recipes, and every engagement number in it was
typed by a human into `seed.sql` or a `demo` block. `recipes.like_count` was authored; the
`recipe_likes` rows behind it were not.

> **The `demo` block half of that is now gone (B112).** This section diagnosed authored engagement
> as a *coverage* problem — too few rows to test ranking — and built the sim to fix it. It was also
> an *honesty* problem, which took another three weeks to notice: those authored counters were
> being served to readers as the Kitchen's real popularity. `recipeData`'s `demo` blocks are
> retired and the validator refuses the key; `seed.sql` keeps its authored counters but reaches no
> real database. The contrast drawn below is still exactly right, and is now the audit's detection
> rule: a counter that disagrees with the rows behind it cannot have been written by a trigger. That was fine while the counters were the only thing being
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

## Phase 32 — Audit remediation — SHIPPED 2026-08-26

Six bands, all done. The mechanism, the traps and the verification log for each moved to
[archive/EXECUTION-PLAN-phases-0-31.md](./archive/EXECUTION-PLAN-phases-0-31.md); the shipped-row
summary is in [ROADMAP.md](./ROADMAP.md). Three things it left standing, and they are not
follow-ups to the bands but decisions nobody has taken:

- **`recipe_views` retention** — the table grows without bound and `anon` can insert into it (B012
  protects the *counter*, not the table). Needs a retention or partitioning design.
- **A persisted Bayesian score** for Popular / quick — a full scan per page is fine at 10³ recipes;
  measure before building.
- **Web browser Back in the recipe editor** — `PopScope` covers the platform gesture and nothing
  covers the browser's button (32c2). Closing it needs something Flutter does not expose today.

## Phase 33 — The windowed leaderboard (SQL shipped 2026-09-10; client shipped 2026-09-24)

Roadmap: [ROADMAP.md Phase 33](./ROADMAP.md#phase-33--the-windowed-leaderboard-shipped-2026-09-24) ·
Design: [SDS §10.9](./SDS.md#109-windowed-engagement-phase-33)

**Problem.** `/chefs` is entirely all-time, because `profiles.chef_score` and the three totals
beside it are lifetime counters with no date on them. Phase 23 drew a `Momentum` sort and a
Month / Week hero toggle and shipped both **disabled**, because nothing in the schema could answer
"who moved this month". Phase 24 then built a population whose engagement logs are dated, which is
the input that was missing.

**Shape.** One function computes the window (`chef_window_stats`), one ranks it
(`chefs_leaderboard_windowed`) and adds no arithmetic. That split is the Gotcha 19 pattern: a
Momentum board and a future per-chef momentum line cannot disagree if only one of them can do
sums.

**The three things that cost something.**

1. **`security definer`, forced by RLS rather than chosen for convenience.** `saves_select` is
   `user_id = auth.uid()` and `views_select` is `owns_recipe(recipe_id)`, so a cross-user aggregate
   over those logs reads an *empty table* under invoker rights and returns a plausible, wrong
   number. Under it, `anon` would have seen a board of zeros — indistinguishable from a quiet week.
   Safe to elevate only because the function writes `visibility = 'public'` out explicitly; the
   elevation removes a net nothing was standing on.
2. **The same bug already existed in shipped code (B092).** `chef_trending_recipes` (Phase 31)
   reads `recipe_views` directly and was invoker-rights, so for everyone except the chef the
   distinct-viewer term counted zero and Trending silently degraded to a like ranking. Fixed here,
   and pinned by `rls_matrix.sql` **F20/F21** on fixtures built so the wrong answer is a different
   **order** rather than an error — then proven by reverting the function and watching both fail.
   The neighbouring RPCs were audited at the same time: nothing else reads the logs.
3. **A return-type change is as impossible for `create or replace` as an argument-list change.**
   `created_at` was added to `chefs_leaderboard` (the `New` sort and the `Joined` line both need
   it), so the `drop function if exists chefs_leaderboard(int, int)` line stopped being insurance
   and became load-bearing — and it fails **only** on the upgrade path, which is Gotcha 6 in one
   sentence. `database.yml` now runs `select count(created_at) from chefs_leaderboard(5, 0)` there
   for exactly that reason.

**Paging a moving window.** Gotcha 24 says `offset` needs a total order; a *windowed* surface adds
that the boundary must also hold still, because a window measured from `now()` moves between page 1
and page 2. `p_since` is the client's pin: read `window_start` off page 1, pass it back.

**Verification.** `rls_matrix.sql` F12–F21 (as `anon`, which is the seat that would have seen the
zeros), plus CI smoke calls on the upgrade path. Every expected value in §F is computed from the
database rather than written as a literal, because sections A–E leave their own engagement rows on
the same fixtures.

**Client — shipped 2026-09-24, no new SQL.** Four decisions carry the weight. (1) Sort and window
are **one** state (`BoardView`), because Month/Week without Momentum has no meaning and Momentum
without a span has no window. (2) Page 1 goes without `p_since` and its `window_start` is echoed
on every later page — the **server's** clock, because the rails beside the board send no boundary
and a device clock off by hours would otherwise measure two windows under one label (the first cut
used the device clock; review caught it, B121). Web `DateTime` truncates the echo to milliseconds,
a window under a millisecond wider. (3) Momentum lists **movers
only**; since the RPC orders by window score first, the first zero row ends paging. (4) `New` is
`chefs_leaderboard` with no inner limit, re-ordered and ranged by PostgREST outside the function —
`dense_rank` still sees everyone, and the order is total. The empty window is a state
(`EmptyView`, `QuietShelfCard`), never a spinner.

**What the client was, before it shipped.** `ChefWindowStanding` and its repository/provider, the `Momentum` sort,
the Month / Week toggle, the `New` sort, the Trending/month rails, a per-chef momentum line, and a
real empty state (a stale `sim.epoch_end()` anchor correctly returns an empty week; that must not
render as a spinner). Two smaller pieces shipped alongside the SQL because they were carried-over
items on the same surfaces: the per-step image picker (Ph 9 / B035) and a tappable `ChefBadge` on
the recipe-card cover (Ph 30).

## Phase 35 — The corpus becomes product (designed, nothing built)

Roadmap: [ROADMAP.md Phase 35](./ROADMAP.md#phase-35--the-corpus-becomes-product-shipped-2026-09-12) ·
Depends on [Phase 34](./ROADMAP.md#phase-34--the-scraped-recipe-corpus-at-scale-in-progress) (the corpus) ·
Absorbs [Phase 25](#phase-25--restaurants--signature-dishes) (its `restaurants` table becomes `entities`)

Phase 34 harvested **558,604 recipes** from **560 publishers** with **19,681 named chefs** and the
credit attached. Three things stand between that directory and a product, and they are **ordered** —
each one's answer is the next one's input:

- **35a — Rights, privacy and terms.** What may be shown, under what promise, on which page.
- **35b — Identity.** A chef is a `profiles` row, and 19,681 of them cannot be 19,681 `auth.users`.
- **35c — Ingestion.** The import itself, with every engagement counter at zero.

Building 35c first is the failure mode to avoid: the import writes provenance and rights columns
that 35a decides, and owner rows that 35b decides, so an import built first is an import rewritten
twice.

**Decided by the owner, 2026-09-12** — three questions that change what gets built, so they are
recorded here rather than left to the band that trips over them:

| Question | Decision |
| --- | --- |
| Import scope, against a 500 MB free-tier database | **A curated tier, hosted.** English-first, cover image present, high field coverage — order 20-50k recipes. The importer is tiered, so later tiers are additive. The full 558k stays local until storage is paid for |
| Where imported content appears | **Its own browse surface, unranked.** `is_imported` is filtered out of every ranked Discover shelf; the corpus is reachable through its own surface, through search, and through chef/entity pages, ordered by `quality_score`. The Kitchen's 14 recipes and the sim population keep the front door |
| Build order | **35b, then 35c, with 35a in parallel.** Identity decoupling is the hard dependency for ingestion; the legal pages touch nothing either band needs |

The English-first tier also settles 35c's search question by construction: the curated tier is
English, so `recipe_search_tsv` keeps its `'english'` config and the `language` column is not built.
It becomes open again the first time a non-English tier is imported — which is a re-index of every
row, so it is a tier decision, never an afterthought.

---

### 35a — Rights, privacy and terms

**Status: BUILT 2026-09-12**, minus four facts only the owner can supply. Everything below is what
the three pages now say. `LegalFacts` holds the entity, the governing law, the contact address and
the hosting region as bracketed placeholders, and every document carries a red *Draft — not in
force* banner until all four are filled in — deliberately, because a document missing its operator
and its jurisdiction still reads like a finished document, and that is exactly how one gets
published. Nothing was invented to fill a gap: a Terms page naming the wrong company is not a
placeholder, it is a false statement.

**One thing the plan got wrong, found while wiring it.** The plan put the compact-width links on the
profile screen. `/profile` is in `needsAuth`, so that left a signed-out phone reader with **no route
to any of the three pages** — the web chrome carries its own bar and the compact bottom slot belongs
to the `NavigationBar`. The fix is the auth screen, which is where a signed-out reader on a phone
actually ends up, and it is the better place anyway: the sign-up form is the one moment in the
product where somebody agrees to the terms, so it now says so there.

> **Not legal advice.** This records an engineering position and the reasoning behind it. The legal
> entity, the governing jurisdiction and the contact address are the owner's to supply, and counsel
> should read the three documents before the app is public with corpus content in it.

**The position, in one line: store and show functional content, link everything expressive, never
re-host a photograph.**

Each layer below is a separate risk and they do **not** resolve the same way — which is why a single
"is scraping legal" answer is useless here:

| Layer | What is at stake | Position |
| --- | --- | --- |
| Ingredient lists | Not copyrightable — a list of ingredients is fact/procedure (17 U.S.C. §102(b); _Publications Int'l v. Meredith_, 88 F.3d 473 (7th Cir. 1996)) | Store and display |
| Step prose | Thin but real: functional directions attract little protection, their _expression_ attracts some | Store; display as harvested. Rewrite-on-ingest is the escalation if a publisher objects |
| Headnotes / descriptions | Squarely copyrightable editorial writing | **Not imported.** The harvested `description` stays in `corpus/` and never reaches `recipes.description` |
| Photographs | Squarely copyrightable, and the largest single exposure — 556,926 covers | **Never copied into our Storage.** Hotlink the publisher's own URL (the _server test_, _Perfect 10 v. Amazon_, 508 F.3d 1146 (9th Cir. 2007)), or show nothing |
| The corpus as a database | EU _sui generis_ database right (Dir. 96/9/EC) protects substantial extraction even from facts — 16,191 rows out of one community site is substantial | Per-source caps, a per-source kill switch, and takedown. This is why `rights_mode` exists at all |
| Site terms of use | A contract, independent of copyright — `robots.txt` compliance does not satisfy it | Accepted knowingly: honour robots, honour objections on request, never disguise the client |
| Named people | 19,681 real bylines, a large share of them in the EU — personal data under GDPR Art. 4 | Name, credit and link only. No invented bio, no invented avatar, and **no ranking** (35c) |

**Images, in detail.** Hotlinking is not reproduction, but it spends a publisher's bandwidth and
breaks the moment they send a referrer block. So: a per-source `image_mode` (`hotlink` | `none`),
default `hotlink`, a placeholder on load failure, and `none` as the standing answer to any
objection. **We do not proxy** — a proxy is a copy on our infrastructure wearing a link's clothes.

**Takedown.** A named contact on the Rights page, a five-business-day target, and a **tombstone**:
`import_blocklist(source_slug, url, reason, at)`. A removal without a tombstone undoes itself on the
next harvest.

**Three pages, one screen.** `/legal/privacy`, `/legal/terms`, `/legal/rights`, all served by one
`LegalScreen` reading structured Dart consts — a small `LegalBlock` list (heading / paragraph /
bullet / link), **no `flutter_markdown` dependency**. Each document carries a `lastUpdated` const;
text moving without that date moving is the review failure to watch for. Signed-out safe, root
navigator, absent from `needsAuth` and from both destination lists (Gotcha 18).

**Where the footer goes — and why it is not a footer everywhere.** Discover, Chefs and My Recipes
page forever, and a footer at the end of an infinite scroll is a footer nobody reaches.

- **Web** (`!context.isCompact`): a slim persistent legal bar in `AppShell`'s `bottomNavigationBar`
  slot — a copyright line plus Privacy / Terms / Rights. It is a `Wrap`; at 2.0x text scale it drops
  the copyright line and keeps the three links. This is a fixed-height page region, so it is checked
  at 600px x 2.0x like the nav pill and the card (Gotchas 13/18/22).
- **Compact**: that slot is the `NavigationBar`. The same three links go at the end of the
  **Profile** screen (finite scroll) and into recipe detail's attribution block.
- Every legal page links to its two siblings.

**Privacy has to describe _this_ app**, not a template. What we hold: Supabase Auth email + password
hash; `profiles.display_name / avatar_url / bio`; recipe content; `recipe_likes` / `recipe_saves` /
`recipe_ratings`; and `recipe_views` — a **behavioural log keyed to a user id**, the row most people
would not guess we keep. Processor: Supabase (AWS region to be named). Session token in browser
`localStorage`. Deletion: an `auth.users` delete cascades to `profiles` and every recipe, but
`recipe_views.user_id` is `on delete set null`, so a deleted account **leaves anonymised view rows
behind and the counter never falls** (Gotcha 10). Say that, because it is true.

**Terms has to cover the two things this product does that a template does not:**

- **Forking.** Publishing a recipe publicly grants every other user the right to fork it — a deep
  copy that keeps lineage to the original. It is the core mechanic and it is currently promised
  nowhere.
- **Nutrition and food safety.** `estimate_nutrition` is an estimate over a 78-food registry, sim
  labels are invented arithmetic (BL-5), imported labels are the publisher's. No allergen guarantee,
  no dietary claim. This is the one paragraph with bodily-harm exposure behind it.

**Seed-data fit:** none needed. The three documents are static Dart content and the footer renders
on every screen with no fixture. The rights columns the importer writes are covered in 35c.

**Owner decisions owed before this ships:** legal entity name, governing law / jurisdiction, contact
address for privacy and takedown, Supabase region, and — the big one — **whether corpus content
appears in the public app at all**, or only behind a flag until a licence position exists.

---

### 35b — Identity: `profiles` decoupled from `auth.users`, entities beside them

**Status: the SQL and the client identity path are BUILT and verified (2026-09-12).** What is
described below is what exists, not a proposal. Two items remain and are listed at the end of this
section: the sim fixtures, and the `Entity` model plus the pages that read it.

**The problem.** `profiles.id` is a foreign key to `auth.users(id)` and every RLS policy reads
`= auth.uid()` against it. 19,681 scraped chefs cannot be 19,681 accounts — an account carries an
email, a password reset and a login surface, none of which these people asked for.

**The shape: one identity table, one nullable link.**

```
profiles
  id            uuid primary key                    -- NO LONGER an FK to auth.users
  auth_user_id  uuid unique null -> auth.users(id) on delete set null
  kind          profile_kind not null default 'member'   -- member | imported
  claimed_at    timestamptz null
  merged_into   uuid null -> profiles(id)
```

**The migration is a no-op for every row that exists today** — which is the reason to pick this over
an attribution side-table. Backfill `auth_user_id = id` for everyone; keep `handle_new_user` writing
`id = new.id` for real signups, so for members `id` and the auth uid stay equal forever. Imported
profiles take a random uuid and a null `auth_user_id`.

Every policy predicate changes shape once:

```sql
create or replace function current_profile_id() returns uuid
  language sql stable security definer set search_path = public as $$
  select id from profiles where auth_user_id = auth.uid()
$$;
```

`owner_id = auth.uid()` becomes `owner_id = current_profile_id()`. `security definer` because a user
must resolve their own profile _before_ `profiles_select` is evaluated; `stable` so Postgres calls it
once per statement. **This touched every policy in `0001_init.sql` and therefore all 137 checks in
`rls_matrix.sql`** — the standing BL-7 rule doing its job, and what makes this change provable
instead of hoped for. An unclaimed profile has no `auth_user_id`, so `current_profile_id()` never
returns it and its recipes are immutable by construction: no extra policy required.

**Entities — Phase 25's table, generalised.** The 560 publishers are not people, so they are not
profiles:

```
entities                (id, slug unique, name, kind entity_kind, homepage, country,
                         description, cover_image_url, created_by -> profiles null, ...)
entity_members          (entity_id, profile_id, role, title)
entity_signature_dishes (entity_id, recipe_id, sort_order)
```

`entity_kind` = `restaurant | brand | publication | community | chef_site`. **Phase 25's
`restaurants` becomes `entities where kind = 'restaurant'`**, and its `restaurant_members` /
`restaurant_signature_dishes` become the two tables above. Phase 25's ROADMAP checklist is rewritten
against these names rather than duplicated — the attribution entity and the restaurant entity are
the same table, and building both means writing the directory page twice.

**Claiming.** A chef taking their page transfers ownership of thousands of rows, so it is never a
self-service RLS write:

```
profile_claims (id, profile_id, claimant_auth_user_id, evidence_url,
                status claim_status, created_at, decided_at, decided_by, note)
```

RLS: a signed-in user may insert a claim against an `imported` profile and read their own claims;
nobody may update. Approval is a `security definer` RPC with `execute` revoked from
`anon`/`authenticated` (Gotcha 3) — run by hand at first, by an admin role later.

**The merge is the hard part, and it is why claiming is a design item and not a column.** The
claimant already has a profile (id = their uid). Approving means, in one transaction:

1. move `recipes.owner_id`, `recipe_likes`, `recipe_saves`, `recipe_ratings`, `recipe_shares` and
   `recipe_views` from the old profile to the claimed one, each `on conflict do nothing` — a user
   cannot like one recipe twice, and the merge is exactly where that collides;
2. `update profiles set auth_user_id = null, merged_into = <claimed> where id = <old>`;
3. set `auth_user_id`, `kind = 'member'`, `claimed_at` on the claimed row;
4. `recompute_chef_stats()` on the target.

`unique(auth_user_id)` is what makes a half-done merge impossible. A merged profile is a
**tombstone, not a delete** — its id is in URLs someone has already shared.

**An imported chef's identity is scoped to the publisher, never global.** `corpus/chefs.json` keys on
a normalised name and its own README flags that as deliberately imperfect ("two people called Sarah
on two blogs collapse into one row"). Collapsing two strangers into one identity is a far worse error
than splitting one person into two rows, so the import key is `(source_slug, normalised_name)`, and
merging across publishers is a later evidenced act rather than a side effect of a string match.

**What was verified, and how.** The claim that this migration is behaviour-preserving is not an
argument — it is 137 checks. `rls_matrix.sql` sections A-F were every one of them written against
`= auth.uid()`, and every one of them passes unchanged against `= current_profile_id()`. Run on
2026-09-12 against the local stack:

| Path | Result |
| --- | --- |
| Upgrade (0001 applied over a Phase-33 database) | clean; `profiles_id_fkey` gone, 15 of 15 profiles linked |
| Re-apply (idempotency) | clean, no errors |
| Fresh (throwaway database, real `auth` + `storage` schemas restored into it) | clean; all four new tables, no stale FK |
| `rls_matrix.sql` on both | **165 passed, 0 failed** (137 pre-existing + 28 new in §G) |
| `db:sim` at `small` + `3_sim_verify` | 250 actors, 432 recipes, ALL CHECKS PASSED, 0 unlinked profiles |
| `db:sim:rls` (signs in as real sim actors) | **130 passed, 0 failed, 7 personas seated** |
| `melos run analyze` / `test --no-select` | SUCCESS / 152 core + 129 design_system + 300 app |

Two things went wrong on the way and are worth keeping, because both are the same mistake:

- **A blanket `user_id = auth.uid()` → `current_profile_id()` sweep also rewrote
  `auth_user_id = auth.uid()`**, which is a substring of it — including inside
  `current_profile_id()`'s own body, making the function call itself. It surfaced as `stack depth
  limit exceeded` from every query in the matrix, not as anything resembling the edit that caused
  it. The same substring caught `profiles_insert` one line later. A mechanical identifier rewrite
  needs a word boundary or an eyeball on every hit; "13 replacements" was the count of a correct
  sweep plus two silent corruptions.
- **The PostgREST return shape was checked rather than assumed.** A scalar `security definer` RPC
  returns a bare JSON string (`"7a8795..."`), not a one-element array, so `as String?` is right —
  confirmed with a minted local JWT against the running stack. `packages/core/test` uses a canned
  reply and would have agreed with a wrong guess.

**Seed-data fit — built.** `2_sim_generate.sql` now produces both kinds, and the shape it took is
worth recording because the obvious one is wrong. The imported chefs are **not** `sim.actor` rows.
Everything downstream that adds engagement — the fork weighting (§5), the shares (§6), the reach
table (§7) — joins `sim.actor` to find an owner's persona, so a recipe whose owner is not an actor
is skipped **by construction**, with no filter written anywhere and nothing to forget when a ninth
engagement step is added. Their recipes still ride the ordinary pipeline by being appended to
`sim_titled`, so there is exactly one place that knows how a dish document becomes a recipe.

Two consequences that needed deciding rather than defaulting:

- **They carry no version history**, so `sim_version` gained a `join sim.actor`. That made check
  **D3** ("every recipe has a `current_version_id`") false, and the right answer was to narrow D3
  to actor-owned recipes *and* add the opposite assertion in **I5** — an imported recipe must have
  none. Narrowing an assertion without asserting the other side is how a check quietly stops
  covering anything.
- **Teardown needed its own registry.** `9_sim_teardown.sql`'s safety rule is that every delete is
  driven by `sim.actor` / `sim.recipe` and never by a pattern, and
  `delete from auth.users where id in (select id from sim.actor)` reaches none of these rows —
  they have no account. Hence `sim.imported_profile` and `sim.entity`, and a teardown branch that
  deletes profiles directly.

`rls_matrix.sql` §G still proves the policies and the merge end to end (G24-G28) on fixtures it
builds and rolls back; group **I** (7 checks) proves the *population* — that imported chefs exist,
hold no account, own public recipes, carry **zero** engagement and zero versions, appear on
neither board, and that every entity has an owner, a mixed roster and only public signature
dishes.

---

### 35c — Ingestion: the corpus into Postgres, every counter at zero

**Status: SHIPPED 2026-09-12.** 21,334 recipes, 1,284 imported chefs and 546 publishers are in the
local database, drawn from 543 sources at 40 per source. Total database size **260 MB**, which fits
the free tier — the 3-4 GB estimate was for the whole 558k corpus, and the tier is what avoided it.

**The architecture that mattered: the write path is SQL, not Dart.** `import_recipe(jsonb)` holds
the blocklist check, the idempotency key, the quality score and every deliberate omission;
`tool/corpus_import.dart` maps a corpus record to a document and connects to nothing. The same split
`tool/recipes.dart` uses with `seed_recipe_v2`, and it earns its keep twice over — a rule written in
Dart is a rule the database cannot see, and a tool that reads 8.6 GB of scraped data never holds a
superuser credential (Gotcha 7).

**What the first real run found**, none of which a fixture would have:

- **`profiles.id` had no default on any database that predates Phase 35b** (B109). The `create table`
  carries `default gen_random_uuid()`, but `create table if not exists` does nothing when the table
  exists — and every existing writer supplies an id (`handle_new_user` the auth uid, the seeds fixed
  uuids, the sim `sim.uid(...)`), so nothing noticed for two commits. `import_recipe` is the first
  caller that wants the database to mint one. It failed on the upgrade path while passing on a fresh
  one: Gotcha 6, exactly.
- **A scraped `datePublished` is not a timestamp.** `Thu, 01/06/2022 - 15:47` aborted a batch of 500.
  Now filtered in the tool *and* caught by an exception block in SQL — an unparseable date is an
  unknown date, and one bad string must not cost 500 good recipes.
- **Scraped text overruns the length constraints.** `cuisine` and `category` are trimmed to 80; an
  over-long cover URL is **dropped rather than trimmed**, because a truncated URL is a broken image
  and null is honest.
- **Check D4 was asserting something false about the corpus.** `(owner_id, title)` is the import key
  for *authored* content, so a collision there is a real bug — but a captured recipe is keyed on
  `(source_entity_id, source_url)`, and one cook posting one title at two URLs is a thing the open
  web contains (ten in the first 21,000). D4 is now scoped to non-imported rows and **D4b asserts
  the imported key**, so neither population is merely unchecked. The same shape as D3's narrowing in
  35b: narrowing an assertion without asserting the other side is how a check quietly stops covering
  anything.

**Measured after the import**, as anon: 0 imported rows across all five ranked shelves, 200 of 200
on `recipes_corpus`, 0 imported chefs on the leaderboard (63 real ones still ranked), and 13 of 50
search hits imported — searchable, as designed. `rls_matrix` 175/0, `3_sim_verify` all passed,
`db:sim:rls` 130/0.

**Owner's instruction: empty stats.** Imported recipes and chefs land with `like_count`,
`save_count`, `view_count` and `rating_*` at zero, and `chef_score` / `chef_tier` / the three totals
untouched. The scraped `aggregateRating` (403,529 recipes carry one) is **not** imported into
`rating_avg`: those are our users' ratings, the trigger recomputes them from `recipe_ratings`, and an
imported value would be silently wiped by the first real rating.

**The leaderboard has to be told, or "empty stats" is not what happens.** `chefs_leaderboard` filters
`public_recipe_count > 0` and orders `chef_score desc, public_recipe_count desc` — so 19,681 imported
chefs would all tie at score 0 and then sort by recipe count _inside that tie_, putting a
14,154-recipe publication bot above every other zero-score chef and burying the real board under the
corpus. Both leaderboard RPCs and the `recompute_all_chef_stats` backfill gain `where kind =
'member'`. An imported chef has a page and is browsable; they are **not ranked**. That is also the
right answer to 35a's personal-data position: we do not rank a real person by engagement they never
sought.

**Discover has to be told too.** Every shelf RPC ends `created_at desc, id`, and `created_at` on an
imported row is _import_ time — so 558k rows would bury the 14 kitchen recipes and the entire sim
population on day one. Two new columns on `recipes`:

- `is_imported boolean not null default false`, with a partial index; every ranked shelf filters it
  out. Imported content is browsable and searchable, not ranked.
- `quality_score smallint` — computed **once at import** from field coverage (cover image, servings,
  prep/cook time, ingredient count in a sane band, step count, named chef). It is not engagement; it
  exists because 558k rows with identical zero counters have **no total order**, and `offset` over a
  tie is Gotcha 24's bug at scale. Corpus browsing orders `quality_score desc, id`.

**Provenance columns**, which are also 35a's enforcement surface: `source_url`, `source_name`,
`source_entity_id -> entities`, `imported_at`, `rights_mode` (`functional | link_only | blocked`),
`image_mode` (`hotlink | none`). Each is client-unwritable and therefore needs its line in the
**column-level grant block** and in `kRecipeSelect` (B050 / OPT-P1 — the obligation runs both ways).
`description` is **not** imported (35a). `nutrition` is **not** imported in v1: the scraped block is
strings (`"345 kcal"`), `estimate_nutrition` cannot read non-English ingredient names, and null is
the honest label.

**The importer** is `tool/corpus_import.dart`, beside the other `tool/*.dart` — **not** a generated
`.sql` file. 558k recipes cannot become a committed seed script, and Gotcha 28's boundary stays
physical: the importer reads `corpus/` and writes to a database, and nothing lands in `recipeData/`.
Properties it needs:

- **Idempotent and resumable** on `unique(source_entity_id, source_url)`; re-running a finished shard
  inserts nothing.
- **Triggers disabled for the load**, exactly as the sim does it. Live, every insert fires the
  `search_tsv` trigger, the version trigger and a stats recompute. Re-enable and run one
  `refresh_search_tsv` pass at the end.
- **No `recipe_versions` row per import.** `save_recipe` appends a snapshot holding the whole recipe
  as jsonb; 558k of those is a gigabyte of history nobody edited. An imported recipe starts with no
  version row until its first edit.
- **Tiered.** `--tier` selects a subset by source, language and quality, because the whole corpus
  does not fit: ~6.15M ingredient rows and ~3.79M step rows put the loaded size around **3-4 GB**
  before indexes, against a **500 MB free-tier database**. The first public cut is a curated tier
  (order 20-50k recipes); the full corpus stays local until storage is paid for. This is an owner
  decision with a bill attached, and the one number in this phase that cannot be engineered away.

**Search is English-only and the corpus is not.** `recipe_search_tsv` hard-codes
`to_tsvector('english', ...)`. Korean, Japanese, French, German, Italian and Dutch rows — a large
share of the biggest sources — index as near-noise. Either the imported tier is English-first
(simplest, and it aligns with the curated-tier decision above) or `recipes` gains a `language` column
and the tsvector function takes a `regconfig`. **Decide before importing**: changing the config means
re-indexing every row.

**Deferred, explicitly.** Keyset pagination and BL-2's per-row `recompute_chef_stats` are _not_
triggered by this phase — imported rows carry no engagement, so the recompute never fires for them,
and ranked surfaces exclude them. Both come back the day corpus rows start collecting real
engagement, which is the stats conversation the owner has deferred to a later session.

**Seed-data fit:** 35b's sim additions, plus a **small committed fixture shard** under
`corpus/_fixtures/` (the real shards are git-ignored and `index.jsonl` alone is 273 MB) so the
importer, the provenance columns and the attribution UI have something to run against in CI.

---

## Phase 36 — UI overhaul (36a done 2026-09-24; 36b + 36c done 2026-09-25)

**Procedure lives in the skill**, not here: `.claude/skills/ui-overhaul/SKILL.md` + `references/`
(audit rubric, design-system spec, rebuild loop, ECC-web → Flutter translation). Run `/ui-overhaul`;
it detects the phase from `docs/design/`.

- **36a — done.** [docs/design/AUDIT.md](design/AUDIT.md): live captures in
  `.playwright-mcp/captures/audit-2026-09-24/` (release build, headless Chromium, light + dark),
  12-dimension score 5.1/10, `UX-001…055`, bugs B125–B134, and the Preserve list 36c must keep.
  Signed-in captures came from `.claude/skills/ui-overhaul/scripts/capture_signed_in.mjs`
  (password-grant session injected as `sb-127-auth-token`; credentials from the git-ignored
  `env.test-account.local.json`).
- **36b — done.** [docs/design/DESIGN.md](design/DESIGN.md) v1 and the token layer
  (`packages/design_system/lib/src/theme/`: `app_theme`, `app_palette`, `app_typography`,
  `app_motion`; fonts under `packages/design_system/fonts/`). Ran in the planned order: direction
  and principles approved → tokens + theme wiring → a feature-by-feature value-neutral migration
  (five disjoint file sets) → token-shaped fixes (B133, UX-031, UX-033, UX-049, UX-050) → guard tests
  → docs. The **UX-032 consolidation** (duplicate segmented controls, rank badges, Load more,
  avatars) was scoped out of 36b and carried into 36c; only the kicker half landed
  (`appText.kicker` / `kickerLarge`). `.claude/skills/ui-overhaul/scripts/static_sweep.sh` is the
  re-runnable sweep; AUDIT.md's 2026-09-25 section has the before/after.
- **36c — done.** [docs/design/REBUILD-LOG.md](design/REBUILD-LOG.md): intake → transcribed specs
  (`docs/design/references/`) → delta table → six owner decisions → layers (tokens, primitives,
  screens — Discover and Recipe detail by two parallel agents on disjoint files) → fidelity loop
  (captures on the local stack, Discover 8.35 / detail 8.5) → code review (B135 and three
  pre-merge regressions fixed) → Claude Design bundle and v3 canvases. DESIGN.md is v2. Carried:
  the other surfaces' bespoke pass, the final font, curated cover photos.
- **Independent of the restyle:** the bugs B125–B132 and B134, and UX-037/038/039 (delete a
  recipe, edit a profile, the editor order), can be fixed at any time. Fixing them first shrinks
  what 36c has to preserve.

**Seed-data fit:** the audit's live surfaces run on `db:reset` + the imported corpus. The curated
14 have **no cover photos**, and engagement is zero, so image-led and ranked layouts can only be
judged on a `db:sim` throwaway database or with owner-supplied photographs. Say which one a capture used.

---

## Phase 37 — UX remediation (in progress, 2026-09-26)

Four waves on `feat/phase-37-ux-remediation`, one commit each. Parallel subagents work on disjoint
files under a shared rules file (tokens, Preserve, tests, no git/melos); the lead runs the full gate
(`dart format`, `melos run analyze`, `melos run test --no-select`) after each wave and before its
commit. Every fix carries a regression test verified by reverting the fix.

**Seed-data fit.** Wave A: covered by widget-test fixtures. The one gap is B125 — no curated or sim
recipe has a step photo, so the photo path is proven only with a fixture URL (`step_photo_test.dart`,
`cook_mode_test.dart`); the claimed-member case of B128 is a fake `AuthRepository` whose profile id
differs from its auth uid (the SQL half is `rls_matrix.sql` §G).
Wave B: covered by fixtures plus the local test account. On a plain `db:reset` the Saved tab and
My Recipes are empty for a new account until it saves or writes something — that is the honest state
(B113), and the live check saved one curated recipe and removed it again.

| Wave | Status | Notes |
| --- | --- | --- |
| A — open bugs (B125, B126, B128–B132) | done | 3 subagents + lead; app 534 → 578 tests, design_system 425 → 433 |
| B — delete, profile editing, `?from=`, sign-up confirm, Saved tab | done | 3 subagents + lead; no SQL (existing RLS/grants cover it; D24 pins saves); live stack confirmed `listSaved`'s `!inner` embed and the profile PATCH; app 578 → 650, core 173 → 175 |
| C — a11y semantics, search, retry, fractions, copy | done | 4 subagents + lead (`InteractiveTile` and `RouteTitle` moved to their own files; rail headings; brand spelling); core 175 → 181, design_system 433 → 446, app 650 → 737. Seed data covers all of it — the 14 curated recipes carry cup/tsp quantities and multi-group methods |
| E — import-time data (B127, B134) | done | SQL cleaners + `import_recipe` + idempotent backfill in 0001; client hides imported difficulty. Verified on the local stack's **upgrade path** (old schema + 21k imports, 0001 applied twice — the second changed no row), `corpus_import_fixture.sql` (+ §6, mutation-checked), `rls_matrix.sql` 186/186, `data_audit.sql` clean |
| Review — `/code-review` over the branch | done | 3 reviewers; 16 findings, 0 Critical, 1 High (B136, found by two). All fixed with a regression test except B141 (deferred, logged); see ROADMAP |
| D — component consolidation, doc hygiene | done | 2 subagents + lead: `SegmentedTabs` (labels kept at `labelLarge` — the first cut dropped the sort and rail to 11px), `RankBadge`, `LoadMoreButton`; category-row reveal; the empty `/chefs` board's overflow at 1000px (found by the gate); live pass on a release build — hero tile, search URL replaces history, tab titles, deep-linked Back; design_system 446 → 591, app 737 → 740 |

## Phase 38 — UX remediation, round 2 (in progress, 2026-09-26)

Same method as Phase 37: waves on `feat/phase-38-ux-remediation-2`, parallel subagents on disjoint
files under a shared rules file, the lead writes the shared core pieces first (so no two agents
touch core) and runs the full gate. Waves A–C ran their agents concurrently; each wave is then
committed on its own, gated with the later waves' files stashed, so every commit passes alone.

**Seed-data fit.** Wave A: widget fixtures. The 14 curated recipes carry cup / tsp quantities
(spoken quantities) and multi-group methods with timed steps (the timer strip); **no curated
recipe is a fork**, so the lineage line is proven with fixtures (`recipe_detail_test`,
`recipe_detail_v2_test`) and live only by forking one as the test account. Wave B: fixtures; every
seeded version's `content_snapshot` is `{}`, which is exactly the empty state the version view must
show — a real snapshot exists only after a save or a fork through the app. Wave C: the local stack
has one member chef and ~1,279 imported profiles with zero engagement, so every chefs rail is
empty on real data — the state UX-045 is about; populated rails are fixtures. B141 needs a real
upload, so it is proven with `fake_supabase` request tests and the profile dialog's fakes.

| Wave | Status | Notes |
| --- | --- | --- |
| A — cook mode, recipe page | done | 1 subagent (cook mode) + lead (core `spokenQuantity`, `findSummary`, `versionContent`, parsers; fork lineage; loading Back; UX-055 / UX-048 detail halves) |
| B — editor | pending commit | 2 subagents |
| C — chefs, entities, profile, My Recipes | pending commit | 2 subagents |
| D — a11y, tokens | not started | |

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
  `tool/db.dart` (needs `SUPABASE_DB_URL`, plus either `psql` on PATH **or** `--docker`). Scripts
  in `supabase/scripts/`; the RLS acceptance matrix in `supabase/tests/`.
- **`--docker` applies to every step**, not just `backup` (B033 closed 2026-09-14): the client runs
  inside `postgres:17-alpine` with the repo mounted read-only at `/repo`. Required on a machine with
  no PostgreSQL client, and the correct form for anything hosted regardless (B079/B074).
- **Hosted sync (B115):** `melos run db:hosted:check` is a READ-ONLY drift report — it builds a
  fresh reference database from the repo (migrations → `nutrition_foods.sql` → `seed_recipes.sql`),
  fingerprints it and the target through `supabase/scripts/schema_fingerprint.sql`, and diffs.
  `melos run db:hosted:deploy` is `create → nutrition → recipes → corpus → audit --strict`:
  additive, idempotent, **no `drop`**, `--yes`-gated. The hosted project has no
  `supabase_migrations.schema_migrations` table, so the fingerprint diff is the only thing that can
  answer "is production current?" — and it is, because a written claim about it has now been wrong
  three times (see ROADMAP BL-5 and BL-9).

---

### Environment prerequisites (developer runs these)

1. Install Flutter SDK **3.44.8** (not latest — see [README](../README.md#toolchain-versions));
   `dart pub global activate melos 6.3.3`.
2. `melos bootstrap` then `melos run build_runner --no-select` (codegen).
3. ~~Generate platform runners~~ — web, android, ios, and windows runners are already committed
   under `apps/app/`. Only run `flutter create . --platforms=<missing>` to add a new platform.
4. Create Supabase project; apply `supabase/migrations/0001_init.sql` (or
   `melos run db:hosted:deploy -- --docker --yes`, which also loads the food registry, the curated
   recipes and the captured corpus). `supabase/seed.sql` is TEST-ONLY — never apply it to a real
   project (B113).
5. Copy `apps/app/env.example.json` → `env.local.json` with `SUPABASE_URL` / `SUPABASE_ANON_KEY`.
6. Run: `flutter run -d web-server --web-port 8080 --dart-define-from-file=env.local.json`.
