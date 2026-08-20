# simData — the simulation dish library

Source material for the **simulated population** (docs/ROADMAP.md Phase 24). Every file here
is an owner-agnostic *dish*, not a recipe: nothing in this directory becomes a `recipes` row
on its own. `supabase/sim/2_sim_generate.sql` draws from the library, assigns a generated
owner, applies a title variant, and dates it.

```
simData/
├── schema.json          # the delta from recipeData/schema.json (two keys)
├── dishes/
│   └── <slug>.json      # one dish per file; filename IS the identity
└── README.md
```

## Same format as recipeData, on purpose

A dish here and a recipe in [`recipeData/`](../recipeData/) are the **same shape**, validated
by the same code — [`tool/recipe_format.dart`](../tool/recipe_format.dart). That is what lets a
dish be promoted into the Kitchen's curated set by moving the file and deleting its `sim`
block. Two directories with two definitions of "valid" would have drifted within a month.

Exactly two keys differ:

| Key | recipeData | simData | Why |
| --- | --- | --- | --- |
| `demo` | allowed | **rejected** | Engagement is *generated* from a modelled history, never authored. A hand-typed `like_count` is the thing Phase 24 exists to stop doing |
| `sim` | rejected | allowed | Generation hints — see below |

### The `sim` block

Both fields are optional.

```json
"sim": {
  "weight": 1.4,
  "variant_titles": ["Weeknight {title}", "{title} with Spinach"]
}
```

- **`weight`** — positive number, default `1`. Relative likelihood the generator draws this
  dish. Raise it for everyday food, lower it for a project bake; a library where a three-hour
  paella is as common as a weeknight curry does not look like a real site.
- **`variant_titles`** — templates, each of which **must** contain `{title}`. The generator
  needs distinct titles per owner because `(owner_id, title)` is the import key, and a
  collision silently collapses two recipes into one row (SDS §11.2). Generic fallbacks apply
  when a dish supplies none.

## Workflow

```powershell
melos run sim:validate   # parse + lint + coverage, writes nothing
melos run sim:gen        # regenerate supabase/sim/1_sim_dishes.sql
```

`supabase/sim/1_sim_dishes.sql` is **generated and committed**, and CI runs
`melos run sim:check` against it — same reasoning as `recipes:check`: nothing reads this JSON
at runtime, so a stale `.sql` would be applied to a database and nobody would notice.

Unlike `seed_recipe_v2`, the generated loader **upserts by slug**. This is a library, not user
data, so pushing a content edit by re-running is the correct behaviour. A dish deleted from
this directory is deleted from `sim.dish` too, or the generator would keep drawing a recipe
whose source file no longer exists.

Everything lands in schema `sim`, never `public`. Supabase exposes `public` to PostgREST, so a
helper placed there becomes a callable RPC by default (B026) — a separate schema makes that
impossible by construction rather than by remembering a `revoke`.

## Coverage rules

These are properties of the **directory**, not of one file, so they live in
[`tool/sim.dart`](../tool/sim.dart) rather than the shared validator. They exist because the
generator's output is only as varied as its input: a library that is 90% mains produces a
Discover page that is 90% mains, and nothing downstream would flag it.

- every one of the 10 `category` values is used
- at least 24 distinct cuisines
- all three `difficulty` values
- at least one no-cook dish (`cook_minutes` 0)
- at least one unattended step over 8 hours (overnight timers are their own case)
- at least one multi-group dish (grouped ingredients are the format's reason to exist)
- the largest dish serves at least 8 (the servings scaler needs range to be worth testing)

Below 100 dishes these report as **warnings** — the library is authored in batches and a
partial batch legitimately misses categories. At 100 and above they become **errors**.

## Adding a dish

1. Create `dishes/<slug>.json`. Copy the nearest existing file; `schema.json` and
   [`recipeData/schema.json`](../recipeData/schema.json) explain every field.
2. `melos run sim:validate` — fix errors, read the warnings.
3. `melos run sim:gen`, and commit the `.json` and the regenerated `.sql` together.

Three rules the format exists to enforce, restated because they are the ones people get wrong:
`quantity` is a decimal (`1.25`, never `"1 1/4"`) because the servings scaler multiplies a
Postgres `numeric`; `servings` is an integer, so pan sizes and piece counts go in
`description`; unattended time — chilling, rising, marinating — is a step's `duration_minutes`,
not `prep_minutes`.

## Where the content comes from

Dishes are **written**, not scraped. An ingredient list is not copyrightable but step prose is,
and copying published instructions would put someone else's text in this repo. Web research is
used to check ratios and technique on unfamiliar dishes, never to copy wording.
