-- nutrition_fixtures.sql — the committed labels vs. the committed registry,
-- and the backfill that reconciles them. Phase 29d.
--
-- Two different things have no other coverage, and both are about drift:
--
--   1. **`seed_recipes.sql`'s twelve `source = 'auto'` labels are static JSON.**
--      `recipes:check` proves the SQL matches `recipeData/`; nothing proves the
--      numbers inside it still match `nutritionData/`. Edit a gram weight, ship
--      the registry, forget to regenerate — and a fresh database seeds labels
--      the estimator no longer agrees with, invisibly. This file is that gate.
--   2. **`recompute_auto_nutrition()` is the reconciliation path**, and a
--      backfill that quietly does nothing looks exactly like one that works.
--      §3–§5 below break something on purpose and watch it get fixed (or, for a
--      manual label, watch it survive).
--
-- REQUIRES a database that already has the registry AND the recipes:
--   drop → migrations → nutrition_foods.sql → seed.sql → seed_recipes.sql
-- which is `melos run db:reset` and `database.yml`'s fresh-apply step. It runs
-- as postgres inside ONE transaction that is ROLLED BACK, so the deliberate
-- corruption in §3–§5 never survives.
--
-- Run:  psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/nutrition_fixtures.sql
--
-- Trigger: any change to nutritionData/, to an auto recipe's ingredients or
-- servings, or to recompute_auto_nutrition / estimate_nutrition.

\set ON_ERROR_STOP on

begin;

do $nf$
declare
  v_auto     int;
  v_manual   int;
  v_none     int;
  v_stale    text;
  v_auto_id  uuid;
  v_auto_lbl jsonb;
  v_man_id   uuid;
  v_man_lbl  jsonb;
begin
  -- ==========================================================================
  -- 1. All three label states ship on seed alone (the Seed-data fit gate).
  --    Automatic / Manual / None is a three-way choice in the editor, so a
  --    fixture set that can only demonstrate two of them cannot demonstrate
  --    the feature.
  -- ==========================================================================
  select
    count(*) filter (where r.nutrition ->> 'source' = 'auto'),
    count(*) filter (where r.nutrition is not null
                       and r.nutrition ->> 'source' is null),
    count(*) filter (where r.nutrition is null)
  into v_auto, v_manual, v_none
  from recipes r
  join profiles p on p.id = r.owner_id
  where p.display_name = 'Secret Sauce Kitchen';

  assert v_auto   > 0, 'no estimated (source=auto) label in the authored recipes';
  assert v_manual > 0, 'no manual label in the authored recipes';
  assert v_none   > 0, 'no null-nutrition recipe in the authored recipes';

  -- ==========================================================================
  -- 2. Every stored auto label equals what the current registry computes.
  --    This is the whole point of the file: a mismatch means either
  --    `recipeData/` or `nutritionData/` moved without the other.
  -- ==========================================================================
  select string_agg(format('%s: stored %s, computed %s', t.title, t.stored, t.fresh), E'\n  ')
  into v_stale
  from (
    select
      r.title,
      r.nutrition as stored,
      nullif(
        estimate_nutrition(
          recipe_snapshot(r.id) -> 'ingredient_groups',
          r.servings
        ) -> 'label',
        'null'::jsonb
      ) as fresh
    from recipes r
    where r.nutrition ->> 'source' = 'auto'
  ) t
  where t.stored is distinct from t.fresh;

  -- One E'' literal, not two adjacent ones: Postgres concatenates literals
  -- separated by a newline, but only the FIRST may carry the E prefix — so a
  -- `\n` in the continuation would print as a literal backslash-n.
  assert v_stale is null, format(
    E'stored auto labels disagree with the registry — regenerate them and re-run recipes:gen (recipeData/README.md):\n  %s',
    v_stale);

  -- Both §3 and §4 pin a row, and both are read HERE, before anything below
  -- has written: a capture taken after the first `recompute_auto_nutrition()`
  -- would be the post-recompute value, which is precisely the thing under test.
  select r.id, r.nutrition into v_auto_id, v_auto_lbl
  from recipes r
  where r.nutrition ->> 'source' = 'auto'
  order by r.title
  limit 1;

  select r.id, r.nutrition into v_man_id, v_man_lbl
  from recipes r
  join profiles p on p.id = r.owner_id
  where p.display_name = 'Secret Sauce Kitchen'
    and r.nutrition is not null
    and r.nutrition ->> 'source' is null
  order by r.title
  limit 1;

  -- §4 only proves anything while the manual NUMBERS differ from the
  -- estimate's. Compared with `source` stripped, since that key is the one
  -- guaranteed difference and comparing it would make the check vacuous.
  assert v_man_lbl is distinct from (
    nullif(
      estimate_nutrition(
        recipe_snapshot(v_man_id) -> 'ingredient_groups',
        (select servings from recipes where id = v_man_id)
      ) -> 'label', 'null'::jsonb
    ) - 'source'),
    'the manual fixture now equals its own estimate — §4 proves nothing';

  -- ==========================================================================
  -- 3. The backfill actually writes. Corrupt one stored label, recompute,
  --    and it must come back — otherwise §2 above is asserting that two
  --    no-ops agree.
  -- ==========================================================================
  update recipes set nutrition = v_auto_lbl || '{"calories": 99999}'::jsonb
  where id = v_auto_id;

  perform recompute_auto_nutrition();

  assert (select nutrition from recipes where id = v_auto_id) = v_auto_lbl,
    format('backfill did not restore the corrupted label: %s',
           (select nutrition from recipes where id = v_auto_id));

  -- ==========================================================================
  -- 4. A manual label is not the backfill's business. `source`'s ABSENCE is
  --    the only thing marking it, so a predicate that drifted to "recompute
  --    everything" would silently overwrite numbers a human typed — with
  --    different numbers, since the manual fixture is a recipe the estimator
  --    counts only partly.
  -- ==========================================================================
  assert (select nutrition from recipes where id = v_man_id) = v_man_lbl,
    format('the backfill overwrote a manual label: %s',
           (select nutrition from recipes where id = v_man_id));

  -- ==========================================================================
  -- 5. The empty-registry guard. `db:reset` and the CI upgrade path both apply
  --    0001_init.sql BEFORE nutrition_foods.sql, so the backfill's on-apply
  --    call can genuinely run with no registry loaded. Without the guard every
  --    estimated label in the database would be recomputed to null — a data
  --    loss with no error. Destructive, hence last, hence the rollback.
  -- ==========================================================================
  select count(*) into v_auto from recipes where nutrition ->> 'source' = 'auto';

  delete from food_portion;
  delete from food_alias;
  delete from food;   -- ingredients.food_id is `on delete set null`

  perform recompute_auto_nutrition();

  assert (select count(*) from recipes where nutrition ->> 'source' = 'auto') = v_auto,
    'the empty-registry guard did not hold — auto labels were blanked';

  raise notice 'nutrition_fixtures: all assertions passed (% auto, % manual, % none)',
    v_auto, v_manual, v_none;
end
$nf$;

-- §3–§5 corrupt and then delete real rows. Nothing here survives.
rollback;
