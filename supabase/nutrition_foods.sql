-- nutrition_foods.sql — GENERATED FILE. DO NOT EDIT BY HAND.
--
-- Source: nutritionData/{foods.json, units.json}  ·  Generator: tool/nutrition.dart
-- Regenerate with `melos run nutrition:gen`; `melos run nutrition:check`
-- fails if this file is stale.
--
-- DATA ONLY: the food / food_alias / food_portion / food_unit tables, their
-- RLS, grants, and the search_foods RPC live in supabase/migrations/0001_init.sql.
-- Idempotent: foods upsert by id and rows removed from the JSON are deleted
-- (ingredients.food_id — Phase 29b — is `on delete set null`, so retiring a
-- registry entry orphans links gracefully). Alias / portion / unit tables are
-- wiped and reloaded — they are leaves with no dependents.
-- Apply BEFORE seed_recipes.sql once 29b's FK exists; `melos run db:nutrition`
-- and config.toml's sql_paths both order it correctly.

-- Unit registry (from units.json). Spelling '' is the bare-count marker.
delete from food_unit;
insert into food_unit (spelling, unit_key, class, factor) values
  ($nf$g$nf$, $nf$g$nf$, $nf$mass$nf$, 1),
  ($nf$gram$nf$, $nf$g$nf$, $nf$mass$nf$, 1),
  ($nf$grams$nf$, $nf$g$nf$, $nf$mass$nf$, 1),
  ($nf$kg$nf$, $nf$kg$nf$, $nf$mass$nf$, 1000),
  ($nf$kilogram$nf$, $nf$kg$nf$, $nf$mass$nf$, 1000),
  ($nf$kilograms$nf$, $nf$kg$nf$, $nf$mass$nf$, 1000),
  ($nf$oz$nf$, $nf$oz$nf$, $nf$mass$nf$, 28.3495),
  ($nf$ounce$nf$, $nf$oz$nf$, $nf$mass$nf$, 28.3495),
  ($nf$ounces$nf$, $nf$oz$nf$, $nf$mass$nf$, 28.3495),
  ($nf$lb$nf$, $nf$lb$nf$, $nf$mass$nf$, 453.592),
  ($nf$lbs$nf$, $nf$lb$nf$, $nf$mass$nf$, 453.592),
  ($nf$pound$nf$, $nf$lb$nf$, $nf$mass$nf$, 453.592),
  ($nf$pounds$nf$, $nf$lb$nf$, $nf$mass$nf$, 453.592),
  ($nf$ml$nf$, $nf$ml$nf$, $nf$volume$nf$, 1),
  ($nf$millilitre$nf$, $nf$ml$nf$, $nf$volume$nf$, 1),
  ($nf$millilitres$nf$, $nf$ml$nf$, $nf$volume$nf$, 1),
  ($nf$milliliter$nf$, $nf$ml$nf$, $nf$volume$nf$, 1),
  ($nf$milliliters$nf$, $nf$ml$nf$, $nf$volume$nf$, 1),
  ($nf$l$nf$, $nf$l$nf$, $nf$volume$nf$, 1000),
  ($nf$litre$nf$, $nf$l$nf$, $nf$volume$nf$, 1000),
  ($nf$litres$nf$, $nf$l$nf$, $nf$volume$nf$, 1000),
  ($nf$liter$nf$, $nf$l$nf$, $nf$volume$nf$, 1000),
  ($nf$liters$nf$, $nf$l$nf$, $nf$volume$nf$, 1000),
  ($nf$tsp$nf$, $nf$tsp$nf$, $nf$volume$nf$, 4.92892),
  ($nf$teaspoon$nf$, $nf$tsp$nf$, $nf$volume$nf$, 4.92892),
  ($nf$teaspoons$nf$, $nf$tsp$nf$, $nf$volume$nf$, 4.92892),
  ($nf$tbsp$nf$, $nf$tbsp$nf$, $nf$volume$nf$, 14.7868),
  ($nf$tablespoon$nf$, $nf$tbsp$nf$, $nf$volume$nf$, 14.7868),
  ($nf$tablespoons$nf$, $nf$tbsp$nf$, $nf$volume$nf$, 14.7868),
  ($nf$cup$nf$, $nf$cup$nf$, $nf$volume$nf$, 236.588),
  ($nf$cups$nf$, $nf$cup$nf$, $nf$volume$nf$, 236.588),
  ($nf$fl oz$nf$, $nf$fl-oz$nf$, $nf$volume$nf$, 29.5735),
  ($nf$fluid ounce$nf$, $nf$fl-oz$nf$, $nf$volume$nf$, 29.5735),
  ($nf$fluid ounces$nf$, $nf$fl-oz$nf$, $nf$volume$nf$, 29.5735),
  ($nf$pint$nf$, $nf$pint$nf$, $nf$volume$nf$, 473.176),
  ($nf$pints$nf$, $nf$pint$nf$, $nf$volume$nf$, 473.176),
  ($nf$$nf$, $nf$each$nf$, $nf$count$nf$, null),
  ($nf$clove$nf$, $nf$clove$nf$, $nf$count$nf$, null),
  ($nf$cloves$nf$, $nf$clove$nf$, $nf$count$nf$, null),
  ($nf$stalk$nf$, $nf$stalk$nf$, $nf$count$nf$, null),
  ($nf$stalks$nf$, $nf$stalk$nf$, $nf$count$nf$, null),
  ($nf$stick$nf$, $nf$stick$nf$, $nf$count$nf$, null),
  ($nf$sticks$nf$, $nf$stick$nf$, $nf$count$nf$, null),
  ($nf$bunch$nf$, $nf$bunch$nf$, $nf$count$nf$, null),
  ($nf$bunches$nf$, $nf$bunch$nf$, $nf$count$nf$, null),
  ($nf$pkg$nf$, $nf$pkg$nf$, $nf$count$nf$, null),
  ($nf$package$nf$, $nf$pkg$nf$, $nf$count$nf$, null),
  ($nf$packages$nf$, $nf$pkg$nf$, $nf$count$nf$, null),
  ($nf$pouch$nf$, $nf$pouch$nf$, $nf$count$nf$, null),
  ($nf$pouches$nf$, $nf$pouch$nf$, $nf$count$nf$, null),
  ($nf$slice$nf$, $nf$slice$nf$, $nf$count$nf$, null),
  ($nf$slices$nf$, $nf$slice$nf$, $nf$count$nf$, null);

-- The foods. 78 of them, ordered by slug.
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$active-dry-yeast$nf$, $nf$Active dry yeast$nf$, 175043,
  325.0, 7.61, 1.0, null, 0.0, 51.0, 41.22, 26.9, 0.0, null, 40.44,
  0.81, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$all-purpose-flour$nf$, $nf$All-purpose flour$nf$, 168894,
  364.0, 0.98, 0.16, null, 0.0, 2.0, 76.31, 2.7, 0.27, null, 10.33,
  0.53, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$asparagus$nf$, $nf$Asparagus$nf$, 168389,
  20.0, 0.12, 0.04, 0.0, 0.0, 2.0, 3.88, 2.1, 1.88, null, 2.2,
  0.57, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$avocado$nf$, $nf$Avocado$nf$, 171705,
  160.0, 14.66, 2.13, 0.0, 0.0, 7.0, 8.53, 6.7, 0.66, null, 2.0,
  0.63, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$baking-powder$nf$, $nf$Baking powder$nf$, 172803,
  53.0, 0.0, 0.0, null, 0.0, 10600.0, 27.7, 0.2, 0.0, null, 0.0,
  0.93, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$baking-soda$nf$, $nf$Baking soda$nf$, 175040,
  0.0, 0.0, 0.0, null, 0.0, 27360.0, 0.0, 0.0, 0.0, null, 0.0,
  0.93, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$balsamic-vinegar$nf$, $nf$Balsamic vinegar$nf$, 172241,
  88.0, 0.0, 0.0, 0.0, null, 23.0, 17.03, null, 14.95, null, 0.49,
  1.08, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$basil-fresh$nf$, $nf$Fresh basil$nf$, 172232,
  23.0, 0.64, 0.04, 0.0, 0.0, 4.0, 2.65, 1.6, 0.3, null, 3.15,
  0.1, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$black-pepper$nf$, $nf$Black pepper$nf$, 170931,
  251.0, 3.26, 1.39, 0.0, 0.0, 20.0, 63.95, 25.3, 0.64, null, 10.39,
  0.47, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$blueberries$nf$, $nf$Blueberries$nf$, 171711,
  57.0, 0.33, 0.03, 0.0, 0.0, 1.0, 14.49, 2.4, 9.96, null, 0.74,
  0.63, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$brown-sugar$nf$, $nf$Brown sugar$nf$, 168833,
  380.0, 0.0, 0.0, null, 0.0, 28.0, 98.09, 0.0, 97.02, null, 0.12,
  0.93, true)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$butter$nf$, $nf$Butter (unsalted)$nf$, 173430,
  717.0, 81.11, 50.49, null, 215.0, 11.0, 0.06, 0.0, 0.06, null, 0.85,
  0.96, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$butter-salted$nf$, $nf$Butter (salted)$nf$, 173410,
  717.0, 81.11, 51.37, 3.28, 215.0, 643.0, 0.06, 0.0, 0.06, null, 0.85,
  0.96, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$buttermilk$nf$, $nf$Buttermilk$nf$, 172225,
  62.0, 3.31, 1.9, null, 11.0, 105.0, 4.88, 0.0, 4.88, null, 3.21,
  1.04, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$canola-oil$nf$, $nf$Canola oil$nf$, 172336,
  884.0, 100.0, 7.37, 0.4, 0.0, 0.0, 0.0, 0.0, 0.0, null, 0.0,
  0.92, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$cherry-tomatoes$nf$, $nf$Cherry tomatoes$nf$, 321360,
  27.0, 0.63, null, null, null, 6.0, 5.51, 2.1, null, null, 0.83,
  0.64, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$chicken-thigh$nf$, $nf$Chicken thigh (boneless, skinless)$nf$, 173627,
  121.0, 4.12, 1.1, 0.02, 94.0, 95.0, 0.0, 0.0, 0.0, null, 19.66,
  null, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$chocolate-chips$nf$, $nf$Chocolate chips (semisweet)$nf$, 167976,
  480.0, 30.0, 17.75, null, 0.0, 11.0, 63.9, 5.9, 54.5, null, 4.2,
  0.77, true)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$cocoa-powder$nf$, $nf$Cocoa powder (unsweetened)$nf$, 169593,
  228.0, 13.7, 8.07, null, 0.0, 21.0, 57.9, 37.0, 1.75, null, 19.6,
  0.36, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$coriander$nf$, $nf$Fresh coriander (cilantro)$nf$, 169997,
  23.0, 0.52, 0.01, 0.0, 0.0, 46.0, 3.67, 2.8, 0.87, null, 2.13,
  0.07, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$cornstarch$nf$, $nf$Cornstarch$nf$, 169698,
  381.0, 0.05, 0.01, null, 0.0, 9.0, 91.27, 0.9, 0.0, null, 0.26,
  0.54, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$cucumber$nf$, $nf$Cucumber$nf$, 168409,
  15.0, 0.11, 0.04, 0.0, 0.0, 2.0, 3.63, 0.5, 1.67, null, 0.65,
  0.44, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$dark-chocolate$nf$, $nf$Dark chocolate (70–85%)$nf$, 170273,
  598.0, 42.63, 24.49, 0.03, 3.0, 20.0, 45.9, 10.9, 23.99, null, 7.79,
  null, true)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$dijon-mustard$nf$, $nf$Dijon mustard$nf$, 172234,
  60.0, 3.34, 0.21, 0.01, 0.0, 1104.0, 5.83, 4.0, 0.92, null, 3.74,
  1.05, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$dill$nf$, $nf$Fresh dill$nf$, 172233,
  43.0, 1.12, 0.06, 0.0, 0.0, 61.0, 7.02, 2.1, null, null, 3.46,
  0.04, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$egg$nf$, $nf$Egg$nf$, 171287,
  143.0, 9.51, 3.13, 0.04, 372.0, 142.0, 0.72, 0.0, 0.37, null, 12.56,
  1.03, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$egg-yolk$nf$, $nf$Egg yolk$nf$, 172184,
  322.0, 26.54, 9.55, null, 1085.0, 48.0, 3.59, 0.0, 0.56, null, 15.86,
  1.03, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$eggplant$nf$, $nf$Eggplant$nf$, 169228,
  25.0, 0.18, 0.03, 0.0, 0.0, 2.0, 5.88, 3.0, 3.53, null, 0.98,
  0.35, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$flat-leaf-parsley$nf$, $nf$Flat-leaf parsley$nf$, 170416,
  36.0, 0.79, 0.13, 0.0, 0.0, 56.0, 6.33, 3.3, 0.85, null, 2.97,
  0.25, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$garlic$nf$, $nf$Garlic$nf$, 169230,
  149.0, 0.5, 0.09, 0.0, 0.0, 17.0, 33.06, 2.1, 1.0, null, 6.36,
  0.57, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$garlic-powder$nf$, $nf$Garlic powder$nf$, 171325,
  331.0, 0.73, 0.25, 0.0, 0.0, 60.0, 72.73, 9.0, 2.43, null, 16.55,
  0.66, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$ginger$nf$, $nf$Fresh ginger$nf$, 169231,
  80.0, 0.75, 0.2, 0.0, 0.0, 13.0, 17.77, 2.0, 1.7, null, 1.82,
  0.41, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$granulated-sugar$nf$, $nf$Granulated sugar$nf$, 169655,
  387.0, 0.0, 0.0, null, 0.0, 1.0, 99.98, 0.0, 99.8, null, 0.0,
  0.85, true)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$green-onions$nf$, $nf$Green onions (scallions)$nf$, 170005,
  32.0, 0.19, 0.03, 0.0, 0.0, 16.0, 7.34, 2.6, 2.33, null, 1.83,
  0.42, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$gruyere$nf$, $nf$Gruyère$nf$, 171242,
  413.0, 32.34, 18.91, null, 110.0, 714.0, 0.36, 0.0, 0.36, null, 29.81,
  0.56, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$heavy-cream$nf$, $nf$Heavy cream$nf$, 170859,
  340.0, 36.08, 23.03, 1.24, 113.0, 27.0, 2.84, 0.0, 2.92, null, 2.84,
  0.51, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$honey$nf$, $nf$Honey$nf$, 169640,
  304.0, 0.0, 0.0, null, 0.0, 4.0, 82.4, 0.2, 82.12, null, 0.3,
  1.43, true)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$jalapeno$nf$, $nf$Jalapeño$nf$, 168576,
  29.0, 0.37, 0.09, 0.0, 0.0, 3.0, 6.5, 2.8, 4.12, null, 0.91,
  0.38, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$kosher-salt$nf$, $nf$Salt$nf$, 173468,
  0.0, 0.0, 0.0, 0.0, 0.0, 38758.0, 0.0, 0.0, 0.0, null, 0.0,
  1.23, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$leek$nf$, $nf$Leek$nf$, 169246,
  61.0, 0.3, 0.04, 0.0, 0.0, 20.0, 14.15, 1.8, 3.9, null, 1.5,
  0.38, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$lemon$nf$, $nf$Lemon$nf$, 167746,
  29.0, 0.3, 0.04, 0.0, 0.0, 2.0, 9.32, 2.8, 2.5, null, 1.1,
  0.9, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$lemon-juice$nf$, $nf$Lemon juice$nf$, 167747,
  22.0, 0.24, 0.04, 0.0, 0.0, 1.0, 6.9, 0.3, 2.52, null, 0.35,
  1.03, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$lemon-zest$nf$, $nf$Lemon zest$nf$, 167749,
  47.0, 0.3, 0.04, 0.0, 0.0, 6.0, 16.0, 10.6, 4.17, null, 1.5,
  0.41, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$lime$nf$, $nf$Lime$nf$, 168155,
  30.0, 0.2, 0.02, 0.0, 0.0, 2.0, 10.54, 2.8, 1.69, null, 0.7,
  null, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$mini-sweet-peppers$nf$, $nf$Mini sweet peppers$nf$, 170108,
  26.0, 0.3, 0.06, 0.0, 0.0, 4.0, 6.03, 2.1, 4.2, null, 0.99,
  0.63, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$mozzarella$nf$, $nf$Fresh mozzarella$nf$, 170845,
  299.0, 22.14, 13.9, null, 79.0, 486.0, 2.4, 0.0, 0.0, null, 22.17,
  0.47, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$nectarine$nf$, $nf$Nectarine$nf$, 169914,
  44.0, 0.32, 0.03, 0.0, 0.0, 0.0, 10.55, 1.7, 7.89, null, 1.06,
  0.6, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$olive-oil$nf$, $nf$Olive oil$nf$, 171413,
  884.0, 100.0, 13.81, null, 0.0, 2.0, 0.0, 0.0, 0.0, null, 0.0,
  0.91, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$onion$nf$, $nf$Onion$nf$, 170000,
  40.0, 0.1, 0.04, 0.0, 0.0, 4.0, 9.34, 1.7, 4.24, null, 1.1,
  0.68, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$orange$nf$, $nf$Orange$nf$, 169097,
  47.0, 0.12, 0.02, 0.0, 0.0, 0.0, 11.75, 2.4, 9.35, null, 0.94,
  0.76, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$panko$nf$, $nf$Panko bread crumbs$nf$, 174928,
  395.0, 5.3, 1.2, null, 0.0, 732.0, 71.98, 4.5, 6.2, null, 13.35,
  0.46, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$parmesan$nf$, $nf$Parmesan$nf$, 171247,
  420.0, 27.84, 15.37, 0.88, 86.0, 1804.0, 13.91, 0.0, 0.07, null, 28.42,
  0.42, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$peas$nf$, $nf$Green peas (frozen)$nf$, 170016,
  77.0, 0.4, 0.07, 0.0, 0.0, 108.0, 13.62, 4.5, 5.0, null, 5.22,
  0.57, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$pie-crust$nf$, $nf$Pie crust (refrigerated)$nf$, 167932,
  445.0, 25.46, 9.6, null, null, 409.0, 51.11, 1.8, null, null, 2.97,
  null, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$pineapple$nf$, $nf$Pineapple$nf$, 169124,
  50.0, 0.12, 0.01, 0.0, 0.0, 1.0, 13.12, 1.4, 9.85, null, 0.54,
  0.7, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$pineapple-juice$nf$, $nf$Pineapple juice$nf$, 168187,
  53.0, 0.12, 0.01, 0.0, 0.0, 2.0, 12.87, 0.2, 9.98, null, 0.36,
  1.06, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$pork-tenderloin$nf$, $nf$Pork tenderloin$nf$, 168249,
  109.0, 2.17, 0.7, 0.02, 65.0, 53.0, 0.0, 0.0, 0.0, null, 20.95,
  null, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$poultry-seasoning$nf$, $nf$Poultry seasoning$nf$, 171331,
  307.0, 7.53, 3.29, 0.0, 0.0, 27.0, 65.59, 11.3, 1.8, null, 9.59,
  0.3, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$prosciutto$nf$, $nf$Prosciutto$nf$, 173864,
  164.0, 8.8, 0.5, null, 57.0, 814.0, 3.63, 1.3, 1.0, null, 16.6,
  null, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$raspberries$nf$, $nf$Raspberries$nf$, 167755,
  52.0, 0.65, 0.02, 0.0, 0.0, 1.0, 11.94, 6.5, 4.42, null, 1.2,
  0.52, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$red-bell-pepper$nf$, $nf$Red bell pepper$nf$, 170108,
  26.0, 0.3, 0.06, 0.0, 0.0, 4.0, 6.03, 2.1, 4.2, null, 0.99,
  0.63, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$red-pepper-flakes$nf$, $nf$Red pepper flakes$nf$, 170932,
  318.0, 17.27, 3.26, null, 0.0, 30.0, 56.63, 27.2, 10.34, null, 12.01,
  0.36, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$rice-vinegar$nf$, $nf$Rice vinegar$nf$, 173469,
  21.0, 0.0, 0.0, 0.0, 0.0, 5.0, 0.93, 0.0, 0.4, null, 0.0,
  1.01, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$san-marzano-tomatoes$nf$, $nf$Canned whole tomatoes$nf$, 170051,
  16.0, 0.25, 0.03, 0.0, 0.0, 115.0, 3.47, 1.9, 2.55, null, 0.79,
  1.01, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$smoked-gouda$nf$, $nf$Gouda$nf$, 171241,
  356.0, 27.44, 17.61, null, 114.0, 819.0, 2.22, 0.0, 2.22, null, 24.94,
  null, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$smoked-paprika$nf$, $nf$Paprika$nf$, 171329,
  282.0, 12.89, 2.14, 0.0, 0.0, 68.0, 53.99, 34.9, 10.34, null, 14.14,
  0.46, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$spaghetti$nf$, $nf$Spaghetti (dry)$nf$, 169736,
  371.0, 1.51, 0.28, 0.0, 0.0, 6.0, 74.67, 3.2, 2.67, null, 13.04,
  0.38, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$tamari$nf$, $nf$Tamari$nf$, 174278,
  60.0, 0.1, 0.01, 0.0, 0.0, 5586.0, 5.57, 0.8, 1.7, null, 10.51,
  1.22, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$tequila$nf$, $nf$Tequila$nf$, 174815,
  231.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, null, 0.0,
  0.94, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$tomato-passata$nf$, $nf$Tomato passata$nf$, 170460,
  38.0, 0.21, 0.03, 0.0, 0.0, 28.0, 8.98, 1.9, 4.83, null, 1.65,
  1.06, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$tuna$nf$, $nf$Tuna (canned in water)$nf$, 173709,
  86.0, 0.96, 0.21, 0.0, 36.0, 247.0, 0.0, 0.0, 0.0, null, 19.44,
  0.65, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$turbinado-sugar$nf$, $nf$Turbinado sugar$nf$, 170674,
  399.0, 0.0, null, null, null, 3.0, 99.8, null, 99.19, null, 0.0,
  0.85, true)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$unbleached-flour$nf$, $nf$Unbleached wheat flour$nf$, 168936,
  364.0, 0.98, 0.16, null, 0.0, 2.0, 76.31, 2.7, 0.27, null, 10.33,
  0.53, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$vanilla-extract$nf$, $nf$Vanilla extract$nf$, 173471,
  288.0, 0.06, 0.01, 0.0, 0.0, 9.0, 12.65, 0.0, 12.65, null, 0.06,
  0.88, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$water$nf$, $nf$Water$nf$, 174158,
  0.0, 0.0, 0.0, 0.0, 0.0, 2.0, 0.0, 0.0, 0.0, null, 0.0,
  1.0, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$whole-milk$nf$, $nf$Whole milk$nf$, 171265,
  61.0, 3.25, 1.87, null, 10.0, 43.0, 4.8, 0.0, 5.05, null, 3.15,
  1.03, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$yogurt$nf$, $nf$Plain yogurt (whole milk)$nf$, 171284,
  61.0, 3.25, 2.1, null, 13.0, 46.0, 4.66, 0.0, 4.66, null, 3.47,
  1.04, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;
insert into food (id, display_name, fdc_id,
  calories, total_fat_g, saturated_fat_g, trans_fat_g,
  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
  total_sugars_g, added_sugars_g, protein_g,
  grams_per_ml, is_added_sugar)
values ($nf$zucchini$nf$, $nf$Zucchini$nf$, 169291,
  17.0, 0.32, 0.08, 0.0, 0.0, 8.0, 3.11, 1.0, 2.5, null, 1.21,
  0.52, false)
on conflict (id) do update set
  display_name = excluded.display_name, fdc_id = excluded.fdc_id,
  calories = excluded.calories, total_fat_g = excluded.total_fat_g, saturated_fat_g = excluded.saturated_fat_g, trans_fat_g = excluded.trans_fat_g, cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg, total_carbs_g = excluded.total_carbs_g, dietary_fiber_g = excluded.dietary_fiber_g, total_sugars_g = excluded.total_sugars_g, added_sugars_g = excluded.added_sugars_g, protein_g = excluded.protein_g,
  grams_per_ml = excluded.grams_per_ml,
  is_added_sugar = excluded.is_added_sugar;

-- Remove foods no longer in the JSON, then reload the leaf tables.
delete from food where id not in (
  $nf$active-dry-yeast$nf$,
  $nf$all-purpose-flour$nf$,
  $nf$asparagus$nf$,
  $nf$avocado$nf$,
  $nf$baking-powder$nf$,
  $nf$baking-soda$nf$,
  $nf$balsamic-vinegar$nf$,
  $nf$basil-fresh$nf$,
  $nf$black-pepper$nf$,
  $nf$blueberries$nf$,
  $nf$brown-sugar$nf$,
  $nf$butter$nf$,
  $nf$butter-salted$nf$,
  $nf$buttermilk$nf$,
  $nf$canola-oil$nf$,
  $nf$cherry-tomatoes$nf$,
  $nf$chicken-thigh$nf$,
  $nf$chocolate-chips$nf$,
  $nf$cocoa-powder$nf$,
  $nf$coriander$nf$,
  $nf$cornstarch$nf$,
  $nf$cucumber$nf$,
  $nf$dark-chocolate$nf$,
  $nf$dijon-mustard$nf$,
  $nf$dill$nf$,
  $nf$egg$nf$,
  $nf$egg-yolk$nf$,
  $nf$eggplant$nf$,
  $nf$flat-leaf-parsley$nf$,
  $nf$garlic$nf$,
  $nf$garlic-powder$nf$,
  $nf$ginger$nf$,
  $nf$granulated-sugar$nf$,
  $nf$green-onions$nf$,
  $nf$gruyere$nf$,
  $nf$heavy-cream$nf$,
  $nf$honey$nf$,
  $nf$jalapeno$nf$,
  $nf$kosher-salt$nf$,
  $nf$leek$nf$,
  $nf$lemon$nf$,
  $nf$lemon-juice$nf$,
  $nf$lemon-zest$nf$,
  $nf$lime$nf$,
  $nf$mini-sweet-peppers$nf$,
  $nf$mozzarella$nf$,
  $nf$nectarine$nf$,
  $nf$olive-oil$nf$,
  $nf$onion$nf$,
  $nf$orange$nf$,
  $nf$panko$nf$,
  $nf$parmesan$nf$,
  $nf$peas$nf$,
  $nf$pie-crust$nf$,
  $nf$pineapple$nf$,
  $nf$pineapple-juice$nf$,
  $nf$pork-tenderloin$nf$,
  $nf$poultry-seasoning$nf$,
  $nf$prosciutto$nf$,
  $nf$raspberries$nf$,
  $nf$red-bell-pepper$nf$,
  $nf$red-pepper-flakes$nf$,
  $nf$rice-vinegar$nf$,
  $nf$san-marzano-tomatoes$nf$,
  $nf$smoked-gouda$nf$,
  $nf$smoked-paprika$nf$,
  $nf$spaghetti$nf$,
  $nf$tamari$nf$,
  $nf$tequila$nf$,
  $nf$tomato-passata$nf$,
  $nf$tuna$nf$,
  $nf$turbinado-sugar$nf$,
  $nf$unbleached-flour$nf$,
  $nf$vanilla-extract$nf$,
  $nf$water$nf$,
  $nf$whole-milk$nf$,
  $nf$yogurt$nf$,
  $nf$zucchini$nf$
);

delete from food_alias;
delete from food_portion;
insert into food_alias (alias, food_id) values
  ($nf$active dry yeast$nf$, $nf$active-dry-yeast$nf$),
  ($nf$yeast$nf$, $nf$active-dry-yeast$nf$),
  ($nf$instant yeast$nf$, $nf$active-dry-yeast$nf$),
  ($nf$dry yeast$nf$, $nf$active-dry-yeast$nf$),
  ($nf$all-purpose flour$nf$, $nf$all-purpose-flour$nf$),
  ($nf$all purpose flour$nf$, $nf$all-purpose-flour$nf$),
  ($nf$flour$nf$, $nf$all-purpose-flour$nf$),
  ($nf$plain flour$nf$, $nf$all-purpose-flour$nf$),
  ($nf$00 pizza flour$nf$, $nf$all-purpose-flour$nf$),
  ($nf$00 flour$nf$, $nf$all-purpose-flour$nf$),
  ($nf$asparagus$nf$, $nf$asparagus$nf$),
  ($nf$asparagus spears$nf$, $nf$asparagus$nf$),
  ($nf$avocado$nf$, $nf$avocado$nf$),
  ($nf$avocados$nf$, $nf$avocado$nf$),
  ($nf$ripe avocados$nf$, $nf$avocado$nf$),
  ($nf$ripe avocado$nf$, $nf$avocado$nf$),
  ($nf$baking powder$nf$, $nf$baking-powder$nf$),
  ($nf$baking soda$nf$, $nf$baking-soda$nf$),
  ($nf$bicarbonate of soda$nf$, $nf$baking-soda$nf$),
  ($nf$sodium bicarbonate$nf$, $nf$baking-soda$nf$),
  ($nf$balsamic vinegar$nf$, $nf$balsamic-vinegar$nf$),
  ($nf$golden balsamic vinegar$nf$, $nf$balsamic-vinegar$nf$),
  ($nf$white balsamic vinegar$nf$, $nf$balsamic-vinegar$nf$),
  ($nf$basil$nf$, $nf$basil-fresh$nf$),
  ($nf$fresh basil$nf$, $nf$basil-fresh$nf$),
  ($nf$fresh basil leaves$nf$, $nf$basil-fresh$nf$),
  ($nf$basil leaves$nf$, $nf$basil-fresh$nf$),
  ($nf$black pepper$nf$, $nf$black-pepper$nf$),
  ($nf$ground black pepper$nf$, $nf$black-pepper$nf$),
  ($nf$pepper$nf$, $nf$black-pepper$nf$),
  ($nf$cracked black pepper$nf$, $nf$black-pepper$nf$),
  ($nf$freshly ground black pepper$nf$, $nf$black-pepper$nf$),
  ($nf$blueberries$nf$, $nf$blueberries$nf$),
  ($nf$fresh blueberries$nf$, $nf$blueberries$nf$),
  ($nf$blueberry$nf$, $nf$blueberries$nf$),
  ($nf$brown sugar$nf$, $nf$brown-sugar$nf$),
  ($nf$light brown sugar$nf$, $nf$brown-sugar$nf$),
  ($nf$dark brown sugar$nf$, $nf$brown-sugar$nf$),
  ($nf$butter$nf$, $nf$butter$nf$),
  ($nf$unsalted butter$nf$, $nf$butter$nf$),
  ($nf$salted butter$nf$, $nf$butter-salted$nf$),
  ($nf$buttermilk$nf$, $nf$buttermilk$nf$),
  ($nf$cultured buttermilk$nf$, $nf$buttermilk$nf$),
  ($nf$canola oil$nf$, $nf$canola-oil$nf$),
  ($nf$oil$nf$, $nf$canola-oil$nf$),
  ($nf$vegetable oil$nf$, $nf$canola-oil$nf$),
  ($nf$neutral oil$nf$, $nf$canola-oil$nf$),
  ($nf$rapeseed oil$nf$, $nf$canola-oil$nf$),
  ($nf$cherry tomatoes$nf$, $nf$cherry-tomatoes$nf$),
  ($nf$grape tomatoes$nf$, $nf$cherry-tomatoes$nf$),
  ($nf$cherry tomato$nf$, $nf$cherry-tomatoes$nf$),
  ($nf$boneless chicken thigh$nf$, $nf$chicken-thigh$nf$),
  ($nf$chicken thigh$nf$, $nf$chicken-thigh$nf$),
  ($nf$chicken thighs$nf$, $nf$chicken-thigh$nf$),
  ($nf$boneless skinless chicken thighs$nf$, $nf$chicken-thigh$nf$),
  ($nf$chocolate chips$nf$, $nf$chocolate-chips$nf$),
  ($nf$semisweet chocolate chips$nf$, $nf$chocolate-chips$nf$),
  ($nf$semi-sweet chocolate chips$nf$, $nf$chocolate-chips$nf$),
  ($nf$dark chocolate chips$nf$, $nf$chocolate-chips$nf$),
  ($nf$unsweetened cocoa powder$nf$, $nf$cocoa-powder$nf$),
  ($nf$cocoa powder$nf$, $nf$cocoa-powder$nf$),
  ($nf$cocoa$nf$, $nf$cocoa-powder$nf$),
  ($nf$dutch process cocoa$nf$, $nf$cocoa-powder$nf$),
  ($nf$fresh coriander$nf$, $nf$coriander$nf$),
  ($nf$coriander$nf$, $nf$coriander$nf$),
  ($nf$cilantro$nf$, $nf$coriander$nf$),
  ($nf$fresh cilantro$nf$, $nf$coriander$nf$),
  ($nf$coriander leaves$nf$, $nf$coriander$nf$),
  ($nf$cornstarch$nf$, $nf$cornstarch$nf$),
  ($nf$corn starch$nf$, $nf$cornstarch$nf$),
  ($nf$cornflour$nf$, $nf$cornstarch$nf$),
  ($nf$cucumber$nf$, $nf$cucumber$nf$),
  ($nf$cucumbers$nf$, $nf$cucumber$nf$),
  ($nf$persian cucumbers$nf$, $nf$cucumber$nf$),
  ($nf$persian cucumber$nf$, $nf$cucumber$nf$),
  ($nf$english cucumber$nf$, $nf$cucumber$nf$),
  ($nf$dark chocolate$nf$, $nf$dark-chocolate$nf$),
  ($nf$bittersweet chocolate$nf$, $nf$dark-chocolate$nf$),
  ($nf$70% chocolate$nf$, $nf$dark-chocolate$nf$),
  ($nf$dijon mustard$nf$, $nf$dijon-mustard$nf$),
  ($nf$mustard$nf$, $nf$dijon-mustard$nf$),
  ($nf$whole-grain mustard$nf$, $nf$dijon-mustard$nf$),
  ($nf$fresh dill$nf$, $nf$dill$nf$),
  ($nf$dill$nf$, $nf$dill$nf$),
  ($nf$dill weed$nf$, $nf$dill$nf$),
  ($nf$egg$nf$, $nf$egg$nf$),
  ($nf$eggs$nf$, $nf$egg$nf$),
  ($nf$whole egg$nf$, $nf$egg$nf$),
  ($nf$large egg$nf$, $nf$egg$nf$),
  ($nf$large eggs$nf$, $nf$egg$nf$),
  ($nf$egg yolk$nf$, $nf$egg-yolk$nf$),
  ($nf$egg yolks$nf$, $nf$egg-yolk$nf$),
  ($nf$eggplant$nf$, $nf$eggplant$nf$),
  ($nf$aubergine$nf$, $nf$eggplant$nf$),
  ($nf$eggplants$nf$, $nf$eggplant$nf$),
  ($nf$flat-leaf parsley$nf$, $nf$flat-leaf-parsley$nf$),
  ($nf$parsley$nf$, $nf$flat-leaf-parsley$nf$),
  ($nf$fresh parsley$nf$, $nf$flat-leaf-parsley$nf$),
  ($nf$italian parsley$nf$, $nf$flat-leaf-parsley$nf$),
  ($nf$garlic$nf$, $nf$garlic$nf$),
  ($nf$fresh garlic$nf$, $nf$garlic$nf$),
  ($nf$garlic cloves$nf$, $nf$garlic$nf$),
  ($nf$garlic powder$nf$, $nf$garlic-powder$nf$),
  ($nf$fresh ginger$nf$, $nf$ginger$nf$),
  ($nf$ginger$nf$, $nf$ginger$nf$),
  ($nf$ginger root$nf$, $nf$ginger$nf$),
  ($nf$grated ginger$nf$, $nf$ginger$nf$),
  ($nf$sugar$nf$, $nf$granulated-sugar$nf$),
  ($nf$white sugar$nf$, $nf$granulated-sugar$nf$),
  ($nf$granulated sugar$nf$, $nf$granulated-sugar$nf$),
  ($nf$granulated cane sugar$nf$, $nf$granulated-sugar$nf$),
  ($nf$organic cane sugar$nf$, $nf$granulated-sugar$nf$),
  ($nf$organic granulated cane sugar$nf$, $nf$granulated-sugar$nf$),
  ($nf$cane sugar$nf$, $nf$granulated-sugar$nf$),
  ($nf$caster sugar$nf$, $nf$granulated-sugar$nf$),
  ($nf$green onions$nf$, $nf$green-onions$nf$),
  ($nf$green onion$nf$, $nf$green-onions$nf$),
  ($nf$scallions$nf$, $nf$green-onions$nf$),
  ($nf$scallion$nf$, $nf$green-onions$nf$),
  ($nf$spring onions$nf$, $nf$green-onions$nf$),
  ($nf$spring onion$nf$, $nf$green-onions$nf$),
  ($nf$gruyère$nf$, $nf$gruyere$nf$),
  ($nf$gruyere$nf$, $nf$gruyere$nf$),
  ($nf$gruyere cheese$nf$, $nf$gruyere$nf$),
  ($nf$heavy cream$nf$, $nf$heavy-cream$nf$),
  ($nf$heavy whipping cream$nf$, $nf$heavy-cream$nf$),
  ($nf$double cream$nf$, $nf$heavy-cream$nf$),
  ($nf$whipping cream$nf$, $nf$heavy-cream$nf$),
  ($nf$honey$nf$, $nf$honey$nf$),
  ($nf$jalapeño$nf$, $nf$jalapeno$nf$),
  ($nf$jalapeno$nf$, $nf$jalapeno$nf$),
  ($nf$jalapeños$nf$, $nf$jalapeno$nf$),
  ($nf$jalapenos$nf$, $nf$jalapeno$nf$),
  ($nf$salt$nf$, $nf$kosher-salt$nf$),
  ($nf$kosher salt$nf$, $nf$kosher-salt$nf$),
  ($nf$sea salt$nf$, $nf$kosher-salt$nf$),
  ($nf$table salt$nf$, $nf$kosher-salt$nf$),
  ($nf$fine sea salt$nf$, $nf$kosher-salt$nf$),
  ($nf$flaky salt$nf$, $nf$kosher-salt$nf$),
  ($nf$leek$nf$, $nf$leek$nf$),
  ($nf$leeks$nf$, $nf$leek$nf$),
  ($nf$lemon$nf$, $nf$lemon$nf$),
  ($nf$lemons$nf$, $nf$lemon$nf$),
  ($nf$lemon juice$nf$, $nf$lemon-juice$nf$),
  ($nf$fresh lemon juice$nf$, $nf$lemon-juice$nf$),
  ($nf$juice of lemon$nf$, $nf$lemon-juice$nf$),
  ($nf$lemon zest$nf$, $nf$lemon-zest$nf$),
  ($nf$lemon peel$nf$, $nf$lemon-zest$nf$),
  ($nf$zest of lemon$nf$, $nf$lemon-zest$nf$),
  ($nf$lime$nf$, $nf$lime$nf$),
  ($nf$limes$nf$, $nf$lime$nf$),
  ($nf$mini sweet peppers$nf$, $nf$mini-sweet-peppers$nf$),
  ($nf$mini sweet pepper$nf$, $nf$mini-sweet-peppers$nf$),
  ($nf$mini peppers$nf$, $nf$mini-sweet-peppers$nf$),
  ($nf$fresh mozzarella$nf$, $nf$mozzarella$nf$),
  ($nf$mozzarella$nf$, $nf$mozzarella$nf$),
  ($nf$mozzarella cheese$nf$, $nf$mozzarella$nf$),
  ($nf$buffalo mozzarella$nf$, $nf$mozzarella$nf$),
  ($nf$nectarine$nf$, $nf$nectarine$nf$),
  ($nf$nectarines$nf$, $nf$nectarine$nf$),
  ($nf$olive oil$nf$, $nf$olive-oil$nf$),
  ($nf$extra-virgin olive oil$nf$, $nf$olive-oil$nf$),
  ($nf$extra virgin olive oil$nf$, $nf$olive-oil$nf$),
  ($nf$evoo$nf$, $nf$olive-oil$nf$),
  ($nf$onion$nf$, $nf$onion$nf$),
  ($nf$onions$nf$, $nf$onion$nf$),
  ($nf$yellow onion$nf$, $nf$onion$nf$),
  ($nf$red onion$nf$, $nf$onion$nf$),
  ($nf$white onion$nf$, $nf$onion$nf$),
  ($nf$brown onion$nf$, $nf$onion$nf$),
  ($nf$orange$nf$, $nf$orange$nf$),
  ($nf$oranges$nf$, $nf$orange$nf$),
  ($nf$panko bread crumbs$nf$, $nf$panko$nf$),
  ($nf$panko$nf$, $nf$panko$nf$),
  ($nf$bread crumbs$nf$, $nf$panko$nf$),
  ($nf$breadcrumbs$nf$, $nf$panko$nf$),
  ($nf$dried breadcrumbs$nf$, $nf$panko$nf$),
  ($nf$parmesan$nf$, $nf$parmesan$nf$),
  ($nf$parmesan cheese$nf$, $nf$parmesan$nf$),
  ($nf$parmigiano-reggiano$nf$, $nf$parmesan$nf$),
  ($nf$grated parmesan$nf$, $nf$parmesan$nf$),
  ($nf$peas$nf$, $nf$peas$nf$),
  ($nf$green peas$nf$, $nf$peas$nf$),
  ($nf$frozen peas$nf$, $nf$peas$nf$),
  ($nf$petits pois$nf$, $nf$peas$nf$),
  ($nf$refrigerated pie crust$nf$, $nf$pie-crust$nf$),
  ($nf$pie crust$nf$, $nf$pie-crust$nf$),
  ($nf$shortcrust pastry$nf$, $nf$pie-crust$nf$),
  ($nf$pineapple$nf$, $nf$pineapple$nf$),
  ($nf$fresh pineapple$nf$, $nf$pineapple$nf$),
  ($nf$pineapple chunks$nf$, $nf$pineapple$nf$),
  ($nf$pineapple juice$nf$, $nf$pineapple-juice$nf$),
  ($nf$pork$nf$, $nf$pork-tenderloin$nf$),
  ($nf$pork tenderloin$nf$, $nf$pork-tenderloin$nf$),
  ($nf$pork loin$nf$, $nf$pork-tenderloin$nf$),
  ($nf$poultry seasoning$nf$, $nf$poultry-seasoning$nf$),
  ($nf$prosciutto$nf$, $nf$prosciutto$nf$),
  ($nf$parma ham$nf$, $nf$prosciutto$nf$),
  ($nf$raspberries$nf$, $nf$raspberries$nf$),
  ($nf$fresh raspberries$nf$, $nf$raspberries$nf$),
  ($nf$raspberry$nf$, $nf$raspberries$nf$),
  ($nf$red bell pepper$nf$, $nf$red-bell-pepper$nf$),
  ($nf$bell pepper$nf$, $nf$red-bell-pepper$nf$),
  ($nf$red pepper$nf$, $nf$red-bell-pepper$nf$),
  ($nf$sweet peppers$nf$, $nf$red-bell-pepper$nf$),
  ($nf$capsicum$nf$, $nf$red-bell-pepper$nf$),
  ($nf$red pepper flakes$nf$, $nf$red-pepper-flakes$nf$),
  ($nf$red chilli flakes$nf$, $nf$red-pepper-flakes$nf$),
  ($nf$chilli flakes$nf$, $nf$red-pepper-flakes$nf$),
  ($nf$chili flakes$nf$, $nf$red-pepper-flakes$nf$),
  ($nf$crushed red pepper$nf$, $nf$red-pepper-flakes$nf$),
  ($nf$cayenne$nf$, $nf$red-pepper-flakes$nf$),
  ($nf$cayenne pepper$nf$, $nf$red-pepper-flakes$nf$),
  ($nf$rice vinegar$nf$, $nf$rice-vinegar$nf$),
  ($nf$rice wine vinegar$nf$, $nf$rice-vinegar$nf$),
  ($nf$san marzano tomatoes$nf$, $nf$san-marzano-tomatoes$nf$),
  ($nf$canned tomatoes$nf$, $nf$san-marzano-tomatoes$nf$),
  ($nf$whole peeled tomatoes$nf$, $nf$san-marzano-tomatoes$nf$),
  ($nf$canned whole tomatoes$nf$, $nf$san-marzano-tomatoes$nf$),
  ($nf$tinned tomatoes$nf$, $nf$san-marzano-tomatoes$nf$),
  ($nf$smoked gouda$nf$, $nf$smoked-gouda$nf$),
  ($nf$gouda$nf$, $nf$smoked-gouda$nf$),
  ($nf$gouda cheese$nf$, $nf$smoked-gouda$nf$),
  ($nf$smoked paprika$nf$, $nf$smoked-paprika$nf$),
  ($nf$paprika$nf$, $nf$smoked-paprika$nf$),
  ($nf$sweet paprika$nf$, $nf$smoked-paprika$nf$),
  ($nf$hot paprika$nf$, $nf$smoked-paprika$nf$),
  ($nf$spaghetti$nf$, $nf$spaghetti$nf$),
  ($nf$pasta$nf$, $nf$spaghetti$nf$),
  ($nf$dried pasta$nf$, $nf$spaghetti$nf$),
  ($nf$dry pasta$nf$, $nf$spaghetti$nf$),
  ($nf$linguine$nf$, $nf$spaghetti$nf$),
  ($nf$bucatini$nf$, $nf$spaghetti$nf$),
  ($nf$tamari$nf$, $nf$tamari$nf$),
  ($nf$soy sauce$nf$, $nf$tamari$nf$),
  ($nf$shoyu$nf$, $nf$tamari$nf$),
  ($nf$tequila blanco$nf$, $nf$tequila$nf$),
  ($nf$tequila$nf$, $nf$tequila$nf$),
  ($nf$vodka$nf$, $nf$tequila$nf$),
  ($nf$gin$nf$, $nf$tequila$nf$),
  ($nf$rum$nf$, $nf$tequila$nf$),
  ($nf$whiskey$nf$, $nf$tequila$nf$),
  ($nf$tomato passata$nf$, $nf$tomato-passata$nf$),
  ($nf$passata$nf$, $nf$tomato-passata$nf$),
  ($nf$tomato puree$nf$, $nf$tomato-passata$nf$),
  ($nf$tomato purée$nf$, $nf$tomato-passata$nf$),
  ($nf$tuna$nf$, $nf$tuna$nf$),
  ($nf$canned tuna$nf$, $nf$tuna$nf$),
  ($nf$tuna in water$nf$, $nf$tuna$nf$),
  ($nf$turbinado sugar$nf$, $nf$turbinado-sugar$nf$),
  ($nf$raw sugar$nf$, $nf$turbinado-sugar$nf$),
  ($nf$demerara sugar$nf$, $nf$turbinado-sugar$nf$),
  ($nf$unbleached wheat flour$nf$, $nf$unbleached-flour$nf$),
  ($nf$organic unbleached wheat flour$nf$, $nf$unbleached-flour$nf$),
  ($nf$unbleached all-purpose flour$nf$, $nf$unbleached-flour$nf$),
  ($nf$vanilla extract$nf$, $nf$vanilla-extract$nf$),
  ($nf$vanilla$nf$, $nf$vanilla-extract$nf$),
  ($nf$pure vanilla extract$nf$, $nf$vanilla-extract$nf$),
  ($nf$water$nf$, $nf$water$nf$),
  ($nf$filtered water$nf$, $nf$water$nf$),
  ($nf$ice$nf$, $nf$water$nf$),
  ($nf$ice water$nf$, $nf$water$nf$),
  ($nf$cold water$nf$, $nf$water$nf$),
  ($nf$warm water$nf$, $nf$water$nf$),
  ($nf$hot water$nf$, $nf$water$nf$),
  ($nf$whole milk$nf$, $nf$whole-milk$nf$),
  ($nf$milk$nf$, $nf$whole-milk$nf$),
  ($nf$full-fat milk$nf$, $nf$whole-milk$nf$),
  ($nf$plain yoghurt$nf$, $nf$yogurt$nf$),
  ($nf$plain yogurt$nf$, $nf$yogurt$nf$),
  ($nf$yogurt$nf$, $nf$yogurt$nf$),
  ($nf$yoghurt$nf$, $nf$yogurt$nf$),
  ($nf$natural yoghurt$nf$, $nf$yogurt$nf$),
  ($nf$zucchini$nf$, $nf$zucchini$nf$),
  ($nf$courgette$nf$, $nf$zucchini$nf$),
  ($nf$zucchinis$nf$, $nf$zucchini$nf$),
  ($nf$courgettes$nf$, $nf$zucchini$nf$);

insert into food_portion (food_id, unit_key, grams) values
  ($nf$active-dry-yeast$nf$, $nf$tbsp$nf$, 12.0),
  ($nf$active-dry-yeast$nf$, $nf$tsp$nf$, 4.0),
  ($nf$all-purpose-flour$nf$, $nf$cup$nf$, 125.0),
  ($nf$asparagus$nf$, $nf$bunch$nf$, 450),
  ($nf$asparagus$nf$, $nf$cup$nf$, 134.0),
  ($nf$avocado$nf$, $nf$cup$nf$, 150.0),
  ($nf$avocado$nf$, $nf$each$nf$, 201.0),
  ($nf$baking-powder$nf$, $nf$tsp$nf$, 4.6),
  ($nf$baking-soda$nf$, $nf$tsp$nf$, 4.6),
  ($nf$balsamic-vinegar$nf$, $nf$cup$nf$, 255.0),
  ($nf$balsamic-vinegar$nf$, $nf$tbsp$nf$, 16.0),
  ($nf$balsamic-vinegar$nf$, $nf$tsp$nf$, 5.3),
  ($nf$basil-fresh$nf$, $nf$bunch$nf$, 60),
  ($nf$basil-fresh$nf$, $nf$cup$nf$, 24.0),
  ($nf$basil-fresh$nf$, $nf$tbsp$nf$, 2.65),
  ($nf$black-pepper$nf$, $nf$tbsp$nf$, 6.9),
  ($nf$black-pepper$nf$, $nf$tsp$nf$, 2.3),
  ($nf$blueberries$nf$, $nf$cup$nf$, 148.0),
  ($nf$brown-sugar$nf$, $nf$cup$nf$, 220.0),
  ($nf$brown-sugar$nf$, $nf$tsp$nf$, 3.0),
  ($nf$butter$nf$, $nf$cup$nf$, 227.0),
  ($nf$butter$nf$, $nf$stick$nf$, 113.0),
  ($nf$butter$nf$, $nf$tbsp$nf$, 14.2),
  ($nf$butter-salted$nf$, $nf$cup$nf$, 227.0),
  ($nf$butter-salted$nf$, $nf$stick$nf$, 113.0),
  ($nf$butter-salted$nf$, $nf$tbsp$nf$, 14.2),
  ($nf$buttermilk$nf$, $nf$cup$nf$, 245.0),
  ($nf$canola-oil$nf$, $nf$cup$nf$, 218.0),
  ($nf$canola-oil$nf$, $nf$tbsp$nf$, 14.0),
  ($nf$canola-oil$nf$, $nf$tsp$nf$, 4.5),
  ($nf$cherry-tomatoes$nf$, $nf$cup$nf$, 152.0),
  ($nf$cherry-tomatoes$nf$, $nf$each$nf$, 9.94),
  ($nf$cherry-tomatoes$nf$, $nf$pint$nf$, 300),
  ($nf$chicken-thigh$nf$, $nf$each$nf$, 149.0),
  ($nf$chicken-thigh$nf$, $nf$oz$nf$, 28.25),
  ($nf$chocolate-chips$nf$, $nf$cup$nf$, 182.0),
  ($nf$chocolate-chips$nf$, $nf$oz$nf$, 28.35),
  ($nf$cocoa-powder$nf$, $nf$cup$nf$, 86.0),
  ($nf$cocoa-powder$nf$, $nf$tbsp$nf$, 5.4),
  ($nf$coriander$nf$, $nf$bunch$nf$, 93),
  ($nf$coriander$nf$, $nf$cup$nf$, 16.0),
  ($nf$cornstarch$nf$, $nf$cup$nf$, 128.0),
  ($nf$cucumber$nf$, $nf$cup$nf$, 104.0),
  ($nf$cucumber$nf$, $nf$each$nf$, 301.0),
  ($nf$dark-chocolate$nf$, $nf$oz$nf$, 28.35),
  ($nf$dijon-mustard$nf$, $nf$cup$nf$, 249.0),
  ($nf$dijon-mustard$nf$, $nf$tsp$nf$, 5.0),
  ($nf$dill$nf$, $nf$cup$nf$, 8.9),
  ($nf$egg$nf$, $nf$cup$nf$, 243.0),
  ($nf$egg$nf$, $nf$each$nf$, 50),
  ($nf$egg-yolk$nf$, $nf$cup$nf$, 243.0),
  ($nf$egg-yolk$nf$, $nf$each$nf$, 17.0),
  ($nf$eggplant$nf$, $nf$cup$nf$, 82.0),
  ($nf$eggplant$nf$, $nf$each$nf$, 548),
  ($nf$flat-leaf-parsley$nf$, $nf$bunch$nf$, 60),
  ($nf$flat-leaf-parsley$nf$, $nf$cup$nf$, 60.0),
  ($nf$flat-leaf-parsley$nf$, $nf$tbsp$nf$, 3.8),
  ($nf$garlic$nf$, $nf$clove$nf$, 3.0),
  ($nf$garlic$nf$, $nf$cup$nf$, 136.0),
  ($nf$garlic$nf$, $nf$tsp$nf$, 2.8),
  ($nf$garlic-powder$nf$, $nf$tbsp$nf$, 9.7),
  ($nf$garlic-powder$nf$, $nf$tsp$nf$, 3.1),
  ($nf$ginger$nf$, $nf$cup$nf$, 96.0),
  ($nf$ginger$nf$, $nf$slice$nf$, 2.2),
  ($nf$ginger$nf$, $nf$tsp$nf$, 2.0),
  ($nf$granulated-sugar$nf$, $nf$cup$nf$, 200.0),
  ($nf$granulated-sugar$nf$, $nf$tsp$nf$, 4.2),
  ($nf$green-onions$nf$, $nf$cup$nf$, 100.0),
  ($nf$green-onions$nf$, $nf$each$nf$, 15.0),
  ($nf$green-onions$nf$, $nf$tbsp$nf$, 6.0),
  ($nf$gruyere$nf$, $nf$cup$nf$, 132.0),
  ($nf$gruyere$nf$, $nf$oz$nf$, 28.35),
  ($nf$gruyere$nf$, $nf$pkg$nf$, 170.0),
  ($nf$gruyere$nf$, $nf$slice$nf$, 28.0),
  ($nf$heavy-cream$nf$, $nf$cup$nf$, 120.0),
  ($nf$heavy-cream$nf$, $nf$fl-oz$nf$, 29.8),
  ($nf$heavy-cream$nf$, $nf$tbsp$nf$, 15.0),
  ($nf$honey$nf$, $nf$cup$nf$, 339.0),
  ($nf$honey$nf$, $nf$tbsp$nf$, 21.0),
  ($nf$jalapeno$nf$, $nf$cup$nf$, 90.0),
  ($nf$jalapeno$nf$, $nf$each$nf$, 14),
  ($nf$kosher-salt$nf$, $nf$cup$nf$, 292.0),
  ($nf$kosher-salt$nf$, $nf$tbsp$nf$, 18.0),
  ($nf$kosher-salt$nf$, $nf$tsp$nf$, 6.0),
  ($nf$leek$nf$, $nf$cup$nf$, 89.0),
  ($nf$leek$nf$, $nf$each$nf$, 89),
  ($nf$leek$nf$, $nf$slice$nf$, 6.0),
  ($nf$lemon$nf$, $nf$cup$nf$, 212.0),
  ($nf$lemon$nf$, $nf$each$nf$, 58.0),
  ($nf$lemon-juice$nf$, $nf$cup$nf$, 244.0),
  ($nf$lemon-juice$nf$, $nf$each$nf$, 48.0),
  ($nf$lemon-juice$nf$, $nf$fl-oz$nf$, 30.5),
  ($nf$lemon-zest$nf$, $nf$tbsp$nf$, 6.0),
  ($nf$lemon-zest$nf$, $nf$tsp$nf$, 2.0),
  ($nf$lime$nf$, $nf$each$nf$, 67.0),
  ($nf$mini-sweet-peppers$nf$, $nf$cup$nf$, 149.0),
  ($nf$mini-sweet-peppers$nf$, $nf$each$nf$, 30),
  ($nf$mini-sweet-peppers$nf$, $nf$tbsp$nf$, 9.3),
  ($nf$mozzarella$nf$, $nf$cup$nf$, 112.0),
  ($nf$mozzarella$nf$, $nf$oz$nf$, 28.35),
  ($nf$mozzarella$nf$, $nf$slice$nf$, 28.33),
  ($nf$nectarine$nf$, $nf$cup$nf$, 143.0),
  ($nf$nectarine$nf$, $nf$each$nf$, 142.0),
  ($nf$olive-oil$nf$, $nf$cup$nf$, 216.0),
  ($nf$olive-oil$nf$, $nf$tbsp$nf$, 13.5),
  ($nf$olive-oil$nf$, $nf$tsp$nf$, 4.5),
  ($nf$onion$nf$, $nf$cup$nf$, 160.0),
  ($nf$onion$nf$, $nf$each$nf$, 110.0),
  ($nf$onion$nf$, $nf$slice$nf$, 38.0),
  ($nf$onion$nf$, $nf$tbsp$nf$, 10.0),
  ($nf$orange$nf$, $nf$cup$nf$, 180.0),
  ($nf$orange$nf$, $nf$each$nf$, 131.0),
  ($nf$panko$nf$, $nf$cup$nf$, 108.0),
  ($nf$panko$nf$, $nf$oz$nf$, 28.35),
  ($nf$parmesan$nf$, $nf$cup$nf$, 100.0),
  ($nf$parmesan$nf$, $nf$oz$nf$, 28.35),
  ($nf$parmesan$nf$, $nf$tbsp$nf$, 5.0),
  ($nf$peas$nf$, $nf$cup$nf$, 134.0),
  ($nf$peas$nf$, $nf$pkg$nf$, 284.0),
  ($nf$pie-crust$nf$, $nf$each$nf$, 229),
  ($nf$pineapple$nf$, $nf$cup$nf$, 165.0),
  ($nf$pineapple$nf$, $nf$each$nf$, 905.0),
  ($nf$pineapple$nf$, $nf$slice$nf$, 166.0),
  ($nf$pineapple-juice$nf$, $nf$cup$nf$, 250.0),
  ($nf$pineapple-juice$nf$, $nf$fl-oz$nf$, 31.3),
  ($nf$pork-tenderloin$nf$, $nf$lb$nf$, 453.6),
  ($nf$pork-tenderloin$nf$, $nf$oz$nf$, 28.25),
  ($nf$poultry-seasoning$nf$, $nf$tbsp$nf$, 4.4),
  ($nf$poultry-seasoning$nf$, $nf$tsp$nf$, 1.5),
  ($nf$prosciutto$nf$, $nf$pkg$nf$, 85),
  ($nf$prosciutto$nf$, $nf$slice$nf$, 28.0),
  ($nf$raspberries$nf$, $nf$cup$nf$, 123.0),
  ($nf$raspberries$nf$, $nf$each$nf$, 1.9),
  ($nf$raspberries$nf$, $nf$pint$nf$, 312.0),
  ($nf$red-bell-pepper$nf$, $nf$cup$nf$, 149.0),
  ($nf$red-bell-pepper$nf$, $nf$each$nf$, 119.0),
  ($nf$red-bell-pepper$nf$, $nf$tbsp$nf$, 9.3),
  ($nf$red-pepper-flakes$nf$, $nf$tbsp$nf$, 5.3),
  ($nf$red-pepper-flakes$nf$, $nf$tsp$nf$, 1.8),
  ($nf$rice-vinegar$nf$, $nf$cup$nf$, 239.0),
  ($nf$rice-vinegar$nf$, $nf$tbsp$nf$, 14.9),
  ($nf$rice-vinegar$nf$, $nf$tsp$nf$, 5.0),
  ($nf$san-marzano-tomatoes$nf$, $nf$cup$nf$, 240.0),
  ($nf$san-marzano-tomatoes$nf$, $nf$each$nf$, 111.0),
  ($nf$san-marzano-tomatoes$nf$, $nf$tbsp$nf$, 15.0),
  ($nf$smoked-gouda$nf$, $nf$oz$nf$, 28.35),
  ($nf$smoked-gouda$nf$, $nf$pkg$nf$, 198.0),
  ($nf$smoked-paprika$nf$, $nf$tbsp$nf$, 6.8),
  ($nf$smoked-paprika$nf$, $nf$tsp$nf$, 2.3),
  ($nf$spaghetti$nf$, $nf$cup$nf$, 91.0),
  ($nf$spaghetti$nf$, $nf$oz$nf$, 28.5),
  ($nf$tamari$nf$, $nf$tbsp$nf$, 18.0),
  ($nf$tamari$nf$, $nf$tsp$nf$, 6.0),
  ($nf$tequila$nf$, $nf$fl-oz$nf$, 27.8),
  ($nf$tomato-passata$nf$, $nf$cup$nf$, 250.0),
  ($nf$tuna$nf$, $nf$cup$nf$, 154.0),
  ($nf$tuna$nf$, $nf$oz$nf$, 28.35),
  ($nf$tuna$nf$, $nf$pouch$nf$, 85),
  ($nf$turbinado-sugar$nf$, $nf$cup$nf$, 202.0),
  ($nf$turbinado-sugar$nf$, $nf$tsp$nf$, 4.6),
  ($nf$unbleached-flour$nf$, $nf$cup$nf$, 125.0),
  ($nf$vanilla-extract$nf$, $nf$cup$nf$, 208.0),
  ($nf$vanilla-extract$nf$, $nf$tbsp$nf$, 13.0),
  ($nf$vanilla-extract$nf$, $nf$tsp$nf$, 4.2),
  ($nf$water$nf$, $nf$cup$nf$, 237.0),
  ($nf$water$nf$, $nf$fl-oz$nf$, 29.6),
  ($nf$water$nf$, $nf$ml$nf$, 1.0),
  ($nf$whole-milk$nf$, $nf$cup$nf$, 244.0),
  ($nf$whole-milk$nf$, $nf$fl-oz$nf$, 30.5),
  ($nf$whole-milk$nf$, $nf$tbsp$nf$, 15.0),
  ($nf$yogurt$nf$, $nf$cup$nf$, 245.0),
  ($nf$zucchini$nf$, $nf$cup$nf$, 124.0),
  ($nf$zucchini$nf$, $nf$each$nf$, 196.0),
  ($nf$zucchini$nf$, $nf$slice$nf$, 9.9);

do $$ begin raise notice 'Food registry loaded (78 foods, 277 aliases, 174 portions)'; end $$;
