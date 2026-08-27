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
