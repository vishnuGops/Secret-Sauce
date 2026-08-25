-- nutrition_estimate.sql — fixture trees through estimate_nutrition/match_foods,
-- with EXACT expected labels. Phase 29c.
--
-- The 3_sim_verify.sql rationale: this SQL's arithmetic has no other coverage —
-- packages/core tests decode canned replies, the RLS matrix proves the policy
-- geometry (and the source-smuggling guard, B22c/B22d), and neither can say
-- whether a cup of fixture flour weighs what the ladder claims. Wired into
-- .github/workflows/database.yml after the fresh apply.
--
-- Everything runs as postgres inside ONE transaction that is ROLLED BACK: the
-- fixture foods/units it inserts never survive, so it is safe against a
-- database that already carries the real registry (the only collision, the ''
-- bare-count spelling, is `on conflict do nothing` — the registry's own row has
-- identical semantics). `estimate_nutrition` is pure over its arguments + the
-- registry tables, so no auth context is needed here; the signed-in write path
-- is the matrix's job.
--
-- Run:  psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/nutrition_estimate.sql
--
-- Trigger: any change to estimate_nutrition, match_foods, food_unit's classes,
-- or the rounding rules.

\set ON_ERROR_STOP on

begin;

-- ============================================================================
-- Fixtures. `nt-` prefixed ids/spellings so nothing can collide with the real
-- registry; round per-100 g numbers so every expectation below is exact.
-- ============================================================================
insert into food (id, display_name, calories, total_fat_g, saturated_fat_g,
                  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,
                  total_sugars_g, added_sugars_g, protein_g, grams_per_ml,
                  is_added_sugar)
values
  -- volume-resolvable: 1 nt-cup (240 ml) × 0.5 = 120 g
  ('nt-flour',  'NT test flour',  400,  1,  null, null, null,  80,   3, null, null, 10, 0.5,  false),
  -- volume-UNresolvable (grams_per_ml null); counts via the nt-stick portion
  ('nt-butter', 'NT test butter', 700, 80,   50,  200,  600, null, null, null, null, null, null, false),
  ('nt-garlic', 'NT test garlic', 150, null, null, null, null,  33, null, null, null,  6, null, false),
  ('nt-egg',    'NT test egg',    140,  10, null,  370,  140, null, null, null, null, 12, null, false),
  -- the added-sugars RULE: no authored added_sugars_g, is_added_sugar → Σ total sugars
  ('nt-sugar',  'NT test sugar',  400, null, null, null, null, 100, null, 100, null, null, null, true),
  -- the authored OVERRIDE: added_sugars_g 80 wins over total_sugars_g 82
  ('nt-honey',  'NT test honey',  300, null, null, null, null,  82, null,  82,   80, null, null, true);

insert into food_portion (food_id, unit_key, grams) values
  ('nt-garlic', 'nt-clove', 3),
  ('nt-garlic', 'each',     5),
  ('nt-butter', 'nt-stick', 100),
  ('nt-egg',    'each',     50);

insert into food_unit (spelling, unit_key, class, factor) values
  ('nt-g',     'nt-g',     'mass',   1),
  ('nt-cup',   'nt-cup',   'volume', 240),
  ('nt-clove', 'nt-clove', 'count',  null),
  ('nt-stick', 'nt-stick', 'count',  null);
-- The bare-count marker. The real registry owns this exact row ('' → each);
-- when it is loaded, keep theirs.
insert into food_unit (spelling, unit_key, class, factor)
values ('', 'each', 'count', null)
on conflict (spelling) do nothing;

do $nt$
declare
  v jsonb;
begin
  -- ==========================================================================
  -- 1. The full grams ladder in one tree, ÷ 2 servings. Row by row:
  --      flour 200 nt-g       mass          → 200 g
  --      flour cup 1 nt-cup   volume × 0.5  → 120 g
  --      butter cup 1 nt-cup  volume, NO density        → not counted
  --      butter 1 nt-stick    portion       → 100 g
  --      garlic 2 nt-clove    portion       →   6 g
  --      egg 2 (no unit)      bare count × 'each' 50 g  → 100 g
  --      sugar 50 nt-g        mass; is_added_sugar rule →  50 g
  --      honey 10 nt-g        mass; authored added override → 10 g
  --      salt 1 handful       unresolvable spelling     → not counted
  --      parsley              unlinked                  → not counted
  --      oil (no quantity)    null quantity             → not counted
  --      chili                is_optional               → not counted
  --      mystery              food_id not in registry   → not counted
  --      debt -50 nt-g        NEGATIVE quantity         → not counted
  --      nothing 0 nt-g       zero quantity             → not counted
  --
  -- The last two matter more than they look: `ingredients.quantity` has no
  -- positive check and the editor's Qty box is a bare TextField, so a negative
  -- row is storable — and it would SUBTRACT from the label, which is a wrong
  -- number rather than a missing one. Both skip with the null case instead.
  -- ==========================================================================
  v := estimate_nutrition('[{"name":"Main","ingredients":[
    {"name":"flour",      "quantity":200, "unit":"nt-g",     "food_id":"nt-flour"},
    {"name":"flour cup",  "quantity":1,   "unit":"nt-cup",   "food_id":"nt-flour"},
    {"name":"butter cup", "quantity":1,   "unit":"nt-cup",   "food_id":"nt-butter"},
    {"name":"butter",     "quantity":1,   "unit":"nt-stick", "food_id":"nt-butter"},
    {"name":"garlic",     "quantity":2,   "unit":"nt-clove", "food_id":"nt-garlic"},
    {"name":"egg",        "quantity":2,   "unit":"",         "food_id":"nt-egg"},
    {"name":"sugar",      "quantity":50,  "unit":"nt-g",     "food_id":"nt-sugar"},
    {"name":"honey",      "quantity":10,  "unit":"nt-g",     "food_id":"nt-honey"},
    {"name":"salt",       "quantity":1,   "unit":"handful",  "food_id":"nt-flour"},
    {"name":"parsley",    "quantity":1,   "unit":"nt-g"},
    {"name":"oil",                        "unit":"nt-g",     "food_id":"nt-flour"},
    {"name":"chili",      "quantity":1,   "unit":"nt-g",     "food_id":"nt-flour", "is_optional":true},
    {"name":"mystery",    "quantity":1,   "unit":"nt-g",     "food_id":"nt-nonexistent"},
    {"name":"debt",       "quantity":-50, "unit":"nt-g",     "food_id":"nt-flour"},
    {"name":"nothing",    "quantity":0,   "unit":"nt-g",     "food_id":"nt-flour"}
  ]}]'::jsonb, 2);

  -- Batch: flour 320 g, butter 100 g, garlic 6 g, egg 100 g, sugar 50 g,
  -- honey 10 g. Per serving = batch ÷ 2; kcal/mg round whole, grams to one
  -- decimal. jsonb compares numbers as numerics, so 25 = 25.0 here.
  assert v->'label' = '{
    "calories": 1180,
    "total_fat_g": 46.6,
    "saturated_fat_g": 25.0,
    "cholesterol_mg": 285,
    "sodium_mg": 370,
    "total_carbs_g": 158.1,
    "dietary_fiber_g": 4.8,
    "total_sugars_g": 29.1,
    "added_sugars_g": 29.0,
    "protein_g": 22.2,
    "source": "auto"
  }'::jsonb, format('ladder label mismatch: %s', v->'label');

  assert (v->>'counted')::int = 7,  format('counted: %s', v->>'counted');
  assert (v->>'total')::int   = 15, format('total: %s',   v->>'total');
  assert v->'unmatched'
    = '["butter cup","chili","debt","mystery","nothing","oil","parsley","salt"]'::jsonb,
    format('unmatched: %s', v->'unmatched');
  -- Trans fat: no fixture carries a value — the key must be ABSENT, never 0.
  assert not (v->'label' ? 'trans_fat_g'), 'trans fat printed a false 0';

  -- ==========================================================================
  -- 2. Nothing counted → label is JSON null (which save_recipe stores as SQL
  --    NULL), the row still listed. Never an all-empty object.
  -- ==========================================================================
  v := estimate_nutrition(
    '[{"name":"Main","ingredients":[{"name":"x","quantity":1,"unit":"nt-g"}]}]'::jsonb, 4);
  assert jsonb_typeof(v->'label') = 'null', format('empty label: %s', v->'label');
  assert (v->>'counted')::int = 0 and (v->>'total')::int = 1;
  assert v->'unmatched' = '["x"]'::jsonb;

  -- ==========================================================================
  -- 3. Null / zero servings behave as 1 — a draft mid-edit must not divide by
  --    zero or null the whole label away.
  -- ==========================================================================
  v := estimate_nutrition(
    '[{"name":"Main","ingredients":[{"name":"flour","quantity":100,"unit":"nt-g","food_id":"nt-flour"}]}]'::jsonb,
    null);
  assert v->'label'->>'calories' = '400', format('null servings: %s', v->'label');
  v := estimate_nutrition(
    '[{"name":"Main","ingredients":[{"name":"flour","quantity":100,"unit":"nt-g","food_id":"nt-flour"}]}]'::jsonb,
    0);
  assert v->'label'->>'calories' = '400', format('zero servings: %s', v->'label');

  -- ==========================================================================
  -- 4. A nutrient no counted food knows stays absent; rounding at one decimal
  --    for grams. honey 10 g ÷ 3: 30 kcal → 10; 8.2 g sugars → 2.7;
  --    8 g added (authored 80/100g, NOT the 82 the rule would derive) → 2.7.
  -- ==========================================================================
  v := estimate_nutrition(
    '[{"name":"Main","ingredients":[{"name":"honey","quantity":10,"unit":"nt-g","food_id":"nt-honey"}]}]'::jsonb,
    3);
  assert v->'label' = '{
    "calories": 10,
    "total_carbs_g": 2.7,
    "total_sugars_g": 2.7,
    "added_sugars_g": 2.7,
    "source": "auto"
  }'::jsonb, format('rounding label mismatch: %s', v->'label');

  -- ==========================================================================
  -- 5. Empty / null trees: counted 0, total 0, label null — the shape a brand
  --    new draft sends before any ingredient exists.
  -- ==========================================================================
  v := estimate_nutrition(null, null);
  assert jsonb_typeof(v->'label') = 'null'
     and (v->>'counted')::int = 0 and (v->>'total')::int = 0
     and v->'unmatched' = '[]'::jsonb,
    format('null tree: %s', v);

  -- ==========================================================================
  -- 6. match_foods: keyed by the trimmed name, top candidates from
  --    search_foods, '[]' when nothing matches (the key stays — "looked,
  --    found nothing" is an answer).
  -- ==========================================================================
  v := match_foods(array['  NT test flour  ', 'zzz no such ingredient']);
  assert v ? 'NT test flour', format('trimmed key missing: %s', v);
  assert v->'NT test flour'->0->>'id' = 'nt-flour',
    format('top candidate: %s', v->'NT test flour');
  assert v->'zzz no such ingredient' = '[]'::jsonb,
    format('no-match key: %s', v->'zzz no such ingredient');

  -- Blank and null input collapse to an empty object, not an error.
  assert match_foods(array['', '   ']) = '{}'::jsonb;
  assert match_foods(null) = '{}'::jsonb;

  raise notice 'nutrition_estimate: all assertions passed';
end
$nt$;

-- Nothing this file wrote is meant to survive it.
rollback;
