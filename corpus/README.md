# `corpus/` — the scale recipe corpus

Recipes harvested from the public web, kept with the credit attached: who cooked it
(a chef), who published it (a brand, a restaurant, a magazine), and the URL it came
from. This is **not** app content and never becomes seed data — see *Rights* below.

It is separate from `recipeData/` on purpose. `recipeData/recipes/*.json` (flat) is
the Secret Sauce Kitchen's own 14 authored recipes, which `tool/recipe_format.dart`
reads and `melos run recipes:gen` compiles into `supabase/seed_recipes.sql`; the
158-recipe chef corpus under `recipeData/recipes/<chef>/` is the Phase 2 round-trip
fixture. Neither wants tens of thousands of files dropped next to it.

## Layout

```
corpus/
├── sources.json                 # the registry: every site the harvester may crawl
├── recipes/<sourceSlug>.jsonl   # the data — one JSON recipe per line, append-only
├── _state/<sourceSlug>.json     # resume state: URLs done, counts, failure tally
├── _state/discovered/<slug>.json# the sitemap sweep, cached
└── _reports/                    # run summaries
```

**One JSONL shard per source, not one file per recipe.** At 40,000 recipes the
per-file overhead stops being free: a directory listing becomes slow, git indexes
40,000 paths, and every reader has to walk a tree to answer "how many". A shard is
append-only, so an interrupted run resumes by construction — the file is already
valid up to its last complete line.

The tooling lives in [`recipeData/_tools/`](../recipeData/_tools/) with the rest of
the scrapers; only the data lives here.

## Commands

```bash
melos run corpus:discover     # sitemap sweep, cached
melos run corpus:harvest      # fetch + extract everything pending (resumable)
melos run corpus:status       # kept / done / discovered per source
melos run corpus:index        # index.jsonl + chefs/groups/restaurants.json
melos run corpus:report       # _reports/CORPUS.md
melos run corpus:clean        # dedupe + prune
```

The same tools directly, for the flags the melos scripts fix:

```bash
cd recipeData/_tools
node probe_batch.mjs candidates/tier1-brands.json   # qualify candidate sites
node promote.mjs ../_reports/probes/tier1-brands.json  # accepted -> corpus/sources.json
node harvest.mjs --discover                         # sitemap sweep, cached per source
node harvest.mjs --concurrency 6                    # fetch + extract everything pending
node harvest.mjs --only king-arthur --limit 50      # one source, bounded
node harvest.mjs --status                           # what is done, what is left
node corpus_stats.mjs --fields                      # what is actually in the shards
node corpus_index.mjs                               # -> index.jsonl + chefs/groups/restaurants.json
node report.mjs                                     # -> _reports/CORPUS.md (generated, never edited)
node dedupe.mjs --dry                               # duplicates from an interrupted run
node prune.mjs --dry                                # sources spending requests and returning nothing
node repair_state.mjs --dry                         # URLs a 429 closed out without an answer
node retag.mjs --dry                                # recompute derived fields after a brands.mjs change
node corpus_query.mjs --chain "Olive Garden" --limit 5   # ask the index a question
node corpus_export.mjs --files 3                    # -> the app's recipeData shape
```

Everything except `harvest.mjs` and the probes is offline. `dedupe`, `retag` and
`repair_state` rewrite shards and state, so run them with the harvester **stopped**.

## Derived roll-ups

`index.jsonl` is the table of contents: **one line per recipe** with title, chef, group,
source URL, cuisine, category, servings, time, counts, cover image, and any chain it
names. It is the file to open first — 47,000 recipes is not a directory listing anyone
can read, and every question starts with "what is in here". It is generated (and
git-ignored) like the shards.

`chefs.json`, `groups.json` and `restaurants.json` are regenerated from the shards —
delete them and re-run `corpus_index.mjs`. They exist because "158 recipes from 15
chefs" is a sentence someone can hold in their head and "20,000 recipes from 200
sources" is not: the roster is the only way to see whether the corpus is one publisher
wearing many hats or a genuinely wide set of cooks.

A chef is keyed on their normalised **name**, which is deliberately imperfect — two
people called "Sarah" on two blogs collapse into one row, and a byline written "Nagi"
on one page and "Nagi Maehashi" on another stays two. Both are visible in the output,
which is better than a fuzzy match that silently merges strangers.

## Resuming

The harvest is resumable by construction — stop it at any point and run the same
command again:

```bash
cd recipeData/_tools
node harvest.mjs --discover --concurrency 10        # only fills gaps; cached sources are skipped
node harvest.mjs --concurrency 36 --limit 800 --discovered-only
```

`--limit` is a **per-source cap per pass**, not a total: it is what makes the sweep
breadth-first, so 500 sources each contribute before any one of them is exhausted.
Run the same command again to take the next slice. `--discovered-only` keeps a worker
from stalling on a sitemap walk — run `--discover` as a separate process beside it,
which is worth about a 3× difference in throughput.

Two files decide what "done" means, and both are per source: `_state/<slug>.json`
(rewritten periodically) and `_state/done/<slug>.log` (appended per URL). A URL that
answered 429 or 5xx is deliberately **not** in either, so the next run retries it.

## The same dish, different chefs

`similar.mjs` answers the question this corpus exists to make answerable: a vault whose
point is forking and version history needs to know whether real cooks publish the same
dish differently. Measured at 558,604 recipes:

| | |
|---|---|
| Distinct dishes | 372,363 |
| Dishes cooked by 2+ chefs | 37,276 |
| Recipes belonging to one of those | 194,743 — **34.9% of the corpus** |
| Dishes with 16+ different chefs | 1,917 |

Banana Bread alone has **265 captures from 216 chefs across 180 publishers**, ranging
from 4 to 28 ingredients (median 10). That spread is the useful part: these are not
duplicates to collapse, they are the same dish as 216 people actually make it, which is
exactly the shape a fork tree is for.

Two titles are one dish when their **content words match as a set** — site furniture
("Easy", "Best", "Homemade", "Recipe", "(Video)") is stripped first, and word order is
ignored, the same judgement `titleOverlap` makes in the scraper. It deliberately does
**not** cluster loosely: "Chocolate Chip Cookies" and "Brown Butter Chocolate Chip
Cookies" stay two dishes, because the second is a different recipe a cook would choose
between — merging them would overstate the overlap and hide the variation being measured.

```bash
melos run corpus:similar                       # dishes with the most distinct chefs
node recipeData/_tools/similar.mjs --summary
node recipeData/_tools/similar.mjs --dish "banana bread" --limit 10
```

## Throughput, measured

Concurrency here is **hosts in flight**, not requests per host — every lane still waits
its site's delay — so raising it costs the sites nothing and costs this machine very
little. Measured on the same corpus, four minutes each:

| Lanes | Recipes/hour |
|---:|---:|
| 24, discovery inline | ~16,000 |
| 36, discovery split out | ~56,700 |
| 56 | ~102,000 |
| 84 | ~160,000 |
| 120 | ~247,000 |

Two things did the work, and neither was speed per request. **Splitting discovery into
its own process** was worth 3.5× on its own: a sitemap walk is a serial crawl that pays
the site's delay, so a worker doing one is a worker fetching no recipes — with 244 of
397 sources undiscovered, most of the fleet was idling. **Per-source caps** (`--limit`)
keep the sweep breadth-first so one 20,000-URL source cannot monopolise a lane.

The harvester holds ~310 MB at 120 lanes and logged no errors at any of these settings.
The floor that is *not* negotiable is `MIN_DELAY_MS` — one request per host per 900 ms.

## Politeness, and what decides it

`robots.mjs` fetches and evaluates each host's real `robots.txt` per URL — longest
match wins, `Allow` wins a tie (RFC 9309). Three rules the harvester follows:

- A host whose `robots.txt` 404s is allow-all. A host whose `robots.txt` is
  **unreachable or 5xx is treated as disallow** — an unknown policy is not
  permission.
- `Crawl-delay` is honoured as stated. `hersheyland.com` and `campbells.com` ask for
  10 seconds and `chicken.ca` for 30, so those sources are slow by instruction.
- A source that has been asked **120 questions and answered none** is abandoned
  mid-run, and the reason is written into its state. `prune.mjs` reaches the same
  conclusion but only when someone runs it — one source spent 930 requests on nothing
  while an unattended pass was in flight, which is 930 requests a site did not need to
  serve.
- Concurrency is **per host**. Six sources at once is six different domains each
  seeing one request at a time; two sources on one host queue behind each other.

## Attribution

Every record carries both halves, and neither is inferred from the other:

| Field | Meaning |
|---|---|
| `entity` | the group that published it — `{slug, name, kind, homepage}` where `kind` is `chef`, `restaurant`, `brand`, `publication` or `community` |
| `attribution.chef` | the person named on the page (JSON-LD `author`), or `null` |
| `attribution.group` | the entity name, always present |
| `attribution.publisher` | JSON-LD `publisher`, falling back to the entity |
| `attribution.sourceUrl` | the URL after redirects |
| `attribution.credit` | a ready-made credit line |
| `source.retrievedAt` | when it was fetched |
| `source.htmlSha256` | hash of the page body as fetched, so a later refetch can prove drift |

A brand site gives a group with a named chef (King Arthur Baking / Erin Jeanne
McDowell). A personal blog gives both as the same person. A community site gives a
group with a member's handle.

## Rights

**Recipe text belongs to its rights-holder.** Each record stores functional content —
ingredients, quantities, steps — plus the source URL and the publisher, so the credit
travels with the row. Editorial prose beyond the recipe is linked, not copied.

This corpus is for internal development and testing of Secret Sauce. It is **not for
redistribution**, it is **not training data**, and nothing in it is promoted into
`supabase/seed*.sql`. `source.rights` restates that per record, and `source.robots`
records the policy that was in force when the row was fetched.
