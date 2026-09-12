# recipeData — the Secret Sauce Kitchen's own recipes

Source of truth for all 14 recipes the kitchen publishes. **Content**, deliberately
separate from the **demo fixtures** in [`supabase/seed.sql`](../supabase/seed.sql)
(fake chefs, taster accounts, engagement numbers) — those get deleted eventually,
these do not. Every recipe is defined exactly once, here.

```
recipeData/
├── schema.json          # the format, field by field, with its DB mapping
├── recipes/
│   └── <slug>.json      # one recipe per file; filename IS the identity
└── README.md
```

## Why one file per recipe

The filename is the slug, so the filesystem makes duplicate slugs impossible —
the previous single-array `data.json` shipped the same recipe twice and nothing
caught it (B025). One file per recipe also means readable diffs and no merge
conflicts when two branches each add a recipe.

## Workflow

```powershell
melos run recipes:validate   # parse + lint, writes nothing
melos run recipes:gen        # regenerate supabase/seed_recipes.sql
melos run db:recipes         # apply that SQL (needs psql + SUPABASE_DB_URL)
```

`supabase/seed_recipes.sql` is **generated and committed**. CI runs
`melos run recipes:check`, which fails if it is stale — nothing reads the JSON at
runtime, so without that check a stale `.sql` would be applied to a database and
nobody would notice.

## Adding a recipe

1. Create `recipes/<slug>.json`. Copy the nearest existing file; read
   `schema.json` for what each field means.
2. `melos run recipes:validate` — fix errors, read the warnings.
3. `melos run recipes:gen` and commit **both** the JSON and the regenerated SQL.

Four things the validator cares about that are easy to get wrong:

- **`quantity` is a decimal, not a fraction string.** `1.25`, never `"1 1/4"`.
  The recipe detail screen scales every quantity by `target / servings`; a string
  cannot be scaled. Use `null` for "to taste" and put the qualifier in `note`.
- **`servings` is an integer.** Yield that is not a serving count — pan size,
  tart diameter, piece count — goes in `description`.
- **Unattended time is not prep time.** Chilling, rising, and marinating go on
  the step that waits, as `duration_minutes`, so the app can show a timer.
- **`nutrition` is `null` or an object — never `{}`.** `null` is the one
  representation of "no info" the whole feature branches on, so write it out
  explicitly. Values are **per serving at that file's own `servings`** — the
  detail screen never multiplies them, because scaling a recipe up makes a bigger
  batch, not a bigger serving. Unknown keys are hard errors: the `jsonb` column
  would accept them and they would then decode to nothing.

### Nutrition, and where the numbers come from (Phase 29d)

Every label here is now real. Three states exist and all three ship on seed, on
purpose — the app's Automatic / Manual / None modes have to be demonstrable
without a hosted database:

| state | files | what it means |
| --- | --- | --- |
| **auto** (`"source": "auto"`) | 12 | computed by `estimate_nutrition()` from this file's ingredient `food` links |
| **manual** (no `source` key) | `fresh-guacamole` | numbers a cook typed; two rows are "to taste", so auto would count 4 of 6 |
| **none** (`"nutrition": null`) | `classic-margarita` | deliberately no label |

**Manual is spelled by the key's absence** — there is no `"source": "manual"`,
which is what let 29c add the key without migrating a single existing label. An
object carrying only `source` is rejected exactly like `{}`.

**An auto label is a snapshot, not a formula.** These files are static JSON;
nothing recomputes them at runtime. Whenever you change an auto recipe's
ingredients, its `servings`, or anything in [`nutritionData/`](../nutritionData/),
regenerate its label and commit it:

```powershell
# with the local stack up and the registry + recipes loaded
docker exec supabase_db_secret-sauce psql -U postgres -d postgres -t -A -c `
  "select estimate_nutrition(recipe_snapshot(id)->'ingredient_groups', servings)->'label'
     from recipes where title = 'Tuna Fishcakes'"
```

A database that already holds the recipe fixes itself instead:
`recompute_auto_nutrition()` re-estimates every `source = 'auto'` recipe and runs
on every apply of `0001_init.sql`. The JSON is the path for a *fresh* database,
which is why it has to be committed in sync.

**The estimate sums raw ingredients.** It cannot model cooking yield —
evaporation, reduction, drained frying oil — and a juiced fruit counts as the
whole fruit. That is why the label prints `Estimated from ingredients — not a
measured analysis.` and why no copy anywhere may call it FDA-compliant.

## Editing a published recipe

`seed_recipe_v2` returns early when `(owner_id, title)` already exists — it is
**not** an upsert, so re-applying the SQL will not push a content change to a
database that already has that recipe. Delete the recipe there first.

Renaming `title` creates a *second* row rather than renaming the first, because
the slug is a repo-level identity that `recipes` does not store.

## Two recipes for the same dish

Fine, as long as the **titles differ**. Similar or even overlapping content is a
product judgement, not a data problem — the kitchen can publish a quick version
and a long version of the same thing.

What is not fine is two files with the same `title`. `(owner_id, title)` is the
import key, so a collision silently collapses to one row rather than failing;
the validator rejects it as an error for exactly that reason.

## The `demo` block

Six recipes carry a `demo` block — likes, saves, views, and one rating per seeded taster. That is
**fixture data, not content**: it exists so Discover and the chef leaderboard have a plausible
order before there are real users, and it is what keeps the Kitchen's `chef_score` at 10189 now
that these recipes no longer live in `seed.sql`. Delete those blocks along with `seed.sql` when
there is real traffic; the recipes are unaffected.

Ratings are applied through `seed.sql`'s taster accounts, so **`seed.sql` has to be applied
first** — `melos run db:reset` and `config.toml` both order it that way. Applied the other way
round, the recipes are created and the ratings skipped, with a notice; re-run `db:recipes` after
`db:seed` to backfill.

## Unit spellings

The app prints a unit **verbatim** beside its quantity — `formatText` in
[formatting.dart](../packages/core/lib/src/formatting.dart) is `'$amount $unit'`, with no
pluralisation and no normalisation anywhere between here and the screen. Whatever is in
the JSON is what a cook reads. Two rules, and `schema.json` carries the full list:

- **Abbreviation units are lowercase and invariant** — `g` `kg` `ml` `L` `tsp` `tbsp`
  `oz` `lb`. Never `Tbsp`, `tablespoon`, `tablespoons`, `tbsps`, `teaspoon`, `teaspoons`,
  `grams`, `ounces`, `pound`, `pounds`, `lbs`, `litres`. `L` is the one deliberate
  departure from [units.json](../nutritionData/units.json)'s `l` key: a lowercase `l` at
  recipe sizes reads as a `1`. Matching is case-insensitive, so it resolves the same.
- **Word units keep the plural a cook would read** — `2 cups flour`, `3 cloves garlic`,
  `5 slices bread`. Collapsing these to the singular registry key would render
  `3 clove garlic`, and the estimator accepts both spellings anyway, so the singular buys
  nothing and costs English.

**The linter does not check any of this** — `unit` is free text in
[tool/recipe_format.dart](../tool/recipe_format.dart) (it only asserts the type). The
whole corpus was swept once; drift comes back one recipe at a time.

A spelling that is not in `units.json` contributes **nothing** to an auto nutrition
estimate, silently — `tbsps` was in 7 ingredients and had been resolving to zero grams.
A genuinely new unit belongs in `units.json` first, then in a recipe.

## What the linter cannot check

It warns when an ingredient no step mentions (the margarita's orphaned orange
liqueur, B025) and suppresses that on recipes with a catch-all step ("add all
the remaining ingredients"). It cannot check the other direction — a step
calling for salt that the ingredient list never mentions — because that needs a
lexicon. Read the steps against the list when you add a recipe; three of the
nine defects in B025 were exactly that.

## The scraped corpus in `recipes/<chefSlug>/` — and why it is invisible here

Alongside the kitchen's own 14 recipes, `recipeData/` holds a **scraped corpus**: 158
recipes from 15 real chefs, used to test the app against real-world data. It lives in
per-chef subdirectories, with its tooling and reports beside it:

```
recipes/<chefSlug>/<recipeSlug>.json   the corpus — one directory per chef
chefs.json · _tools/ · _state/ · _reports/
```

**None of it reaches the database through this pipeline, and that is deliberate.**
`_load()` in [tool/recipe_format.dart](../tool/recipe_format.dart) calls
`directory.listSync()` **without** `recursive: true` and then `.whereType<File>()`, so
subdirectories are skipped. `melos run recipes:validate` reports 14 no matter how large
the corpus grows.

> **Adding `recursive: true` to that loader would turn every scraped recipe into seeded
> content**, generated into `supabase/seed_recipes.sql` and owned by the Secret Sauce
> Kitchen account, on every database. If you ever need the loader to recurse, exclude
> `recipes/*/` explicitly at the same time.

The corpus gets no validation from this tooling either — it has its own, in
`_tools/`. See [_reports/PHASE1-CORPUS.md](_reports/PHASE1-CORPUS.md) for how it was
captured and [_reports/PHASE2-ROUNDTRIP.md](_reports/PHASE2-ROUNDTRIP.md) for what
ingesting it found.

Recipe text belongs to its rights-holder. Each file stores functional content plus a
link back to the source, for internal testing only — never redistributed, and never
promoted into seed data.
