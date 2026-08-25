# nutritionData/ — the food registry (Phase 29)

The committed source for the auto-nutrition food registry. Two files:

- **`foods.json`** — one entry per food: slug, display name, `fdc_id`, aliases,
  authored densities/portions, and an `extracted` block of per-100 g values that
  `tool/fdc.dart` writes from the USDA FoodData Central CSV bundle.
- **`units.json`** — the canonical unit registry: every accepted spelling, its
  class (mass / volume / count), and its conversion factor. The estimator's
  unit arithmetic starts here; nothing in SQL restates a conversion.

`tool/nutrition.dart` generates `supabase/nutrition_foods.sql` from these two
files alone — no CSV in sight, so CI's `nutrition:check` works offline, exactly
like `recipes:check`. The generated SQL is committed; **never hand-edit it.**

## The two tools

```powershell
# EXTRACT — needs the 3.1 GB USDA bundle on disk (never committed). Reads the
# CSVs, writes per-100 g values + parsed portions into foods.json `extracted`
# blocks. Run only when adding foods or refreshing the registry.
melos run fdc:extract -- --bundle="C:\path\to\FoodData_Central_csv_2026-04-30"

# GEN / CHECK — pure file ops, no bundle, no database.
melos run nutrition:gen     # foods.json + units.json -> supabase/nutrition_foods.sql
melos run nutrition:check   # fail if that .sql is stale (CI runs this)
```

The split is deliberate: extract output is committed and human-reviewed, which
is what lets the SR-Legacy portion parser be imperfect — its mistakes surface
in a readable diff, not in a label.

## Authoring workflow

1. Add an entry to `foods.json` (keep slug order): `slug`, `display_name`,
   `fdc_id`, `aliases`. Find the id by searching the bundle's `food.csv` for
   `sr_legacy_food` rows first — Foundation foods often carry **no portions**
   (all-purpose flour has none) — and never use `branded_food` or FNDDS
   survey rows (those are composite dishes).
2. Run `fdc:extract` (fills `extracted`), review the diff, then
   `nutrition:gen`, and commit **all three** files together.
3. Author what extraction cannot know:
   - `portions` — retail units FDC lacks (`bunch`, `pouch`, `pkg`) or portion
     rows whose modifier defeats the parser. Authored portions win over
     extracted ones with the same unit key.
   - `grams_per_ml` — density override; wins over the extracted derivation.
   - `is_added_sugar: true` — sugars, honey, chocolate: the estimator counts
     this food's **total sugars** as added sugars (the FDC bundle has zero
     added-sugar rows for generic foods, so it can never come from data).
   - `note` — required for every **proxy mapping** (an `fdc_id` borrowed from
     a nutritionally-equivalent food, e.g. rice vinegar → cider vinegar).
     `fdc_id` names the data source, not an identity claim.

## Rules

- **Aliases are lowercase and globally unique** across the registry — the
  29b backfill exact-matches ingredient names against them, so a duplicate
  alias makes a link ambiguous. Cover the corpus spelling of every ingredient
  the food should link (accented and unaccented both: `jalapeño`, `jalapeno`).
- **Never guess a density.** A water default makes a cup of flour 236 g
  instead of 120 g, which is worse than "not counted". A food with no
  density and no volume portion simply does not resolve volume units.
- Portion grams are **per one unit** (the extractor divides FDC's
  `amount`-scaled rows back down).
- The `extracted` block is machine-owned. Hand edits to it are overwritten by
  the next `fdc:extract` run — author overrides at the top level instead.

## Known vocabulary gaps (corpus names that stay unlinked)

These recipeData ingredient names have no defensible FDC row and will appear
on the estimator's "not counted" list — that is the honest surface, not a bug:

- `mirin` — no generic FDC row; no close proxy (it is mostly sugar, unlike
  sake or vinegar).
- `orange liqueur` — FDC's only liqueur rows are coffee liqueurs.
- `tikka spice blend` — house blend, no FDC row.
- `bamboo skewers` — not a food.
- `salt and pepper` / `salt and black pepper` — composite rows; the editor
  links one food per ingredient row.
- `hot cooked pasta, polenta, or crusty bread` — a serving suggestion, not a
  measurable ingredient.

simData dish ingredients are optional follow-up curation (Phase 29d), not a
gate — the sim's labels are invented per-recipe and read as manual.
