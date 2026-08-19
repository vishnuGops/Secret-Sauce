# recipeData — the Secret Sauce Kitchen's own recipes

Source of truth for all 15 recipes the kitchen publishes. **Content**, deliberately
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

Three things the validator cares about that are easy to get wrong:

- **`quantity` is a decimal, not a fraction string.** `1.25`, never `"1 1/4"`.
  The recipe detail screen scales every quantity by `target / servings`; a string
  cannot be scaled. Use `null` for "to taste" and put the qualifier in `note`.
- **`servings` is an integer.** Yield that is not a serving count — pan size,
  tart diameter, piece count — goes in `description`.
- **Unattended time is not prep time.** Chilling, rising, and marinating go on
  the step that waits, as `duration_minutes`, so the app can show a timer.

## Editing a published recipe

`seed_recipe_v2` returns early when `(owner_id, title)` already exists — it is
**not** an upsert, so re-applying the SQL will not push a content change to a
database that already has that recipe. Delete the recipe there first.

Renaming `title` creates a *second* row rather than renaming the first, because
the slug is a repo-level identity that `recipes` does not store.

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

## What the linter cannot check

It warns when an ingredient no step mentions (the margarita's orphaned orange
liqueur, B025) and suppresses that on recipes with a catch-all step ("add all
the remaining ingredients"). It cannot check the other direction — a step
calling for salt that the ingredient list never mentions — because that needs a
lexicon. Read the steps against the list when you add a recipe; three of the
nine defects in B025 were exactly that.
