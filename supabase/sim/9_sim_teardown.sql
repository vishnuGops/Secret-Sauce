-- 9_sim_teardown.sql — remove everything the simulation created.
--
-- DESTRUCTIVE. Deletes rows from `auth.users`, which has no undo.
--
-- ---------------------------------------------------------------------------
-- THE SAFETY MECHANISM IS THE REGISTRY, NOT A PATTERN.
--
-- Every delete below is driven by `sim.actor` / `sim.recipe` — the tables the
-- generator wrote as it created each row. It would be shorter to match on
-- `email like '%@sim.secretsauce.local'` or on an id range, and that is exactly
-- the shape of deletion that removes a real account the day someone signs up
-- with an unlucky address or the seed constant changes. If the registry is
-- gone, this script deletes nothing, which is the correct failure direction.
--
-- WHAT IT KEEPS: schema `sim` itself, the dish library, personas, presets and
-- config — so `2_sim_generate.sql` can immediately rebuild. To remove the
-- machinery as well:
--
--   drop schema sim cascade;
--
-- WHAT IT DOES NOT TOUCH: the Kitchen's 14 recipes, the d1-d7 demo chefs, the
-- taster accounts, or any real user. Those come from seed.sql / seed_recipes.sql
-- and are not in the registry.
-- ---------------------------------------------------------------------------

\set ON_ERROR_STOP on

begin;

do $$
begin
  if not exists (select 1 from information_schema.schemata where schema_name = 'sim') then
    raise notice 'sim schema absent — nothing to tear down';
    return;
  end if;
  raise notice 'sim teardown: removing % actors and % recipes',
    (select count(*) from sim.actor), (select count(*) from sim.recipe);
end $$;

-- Restore the pre-sim counters of recipes the sim did not create. Only ever
-- populated when engage_existing was true; a no-op otherwise.
do $$
begin
  if to_regclass('sim.counter_baseline') is not null then
    update recipes r
    set like_count = b.like_count,
        save_count = b.save_count,
        view_count = b.view_count
    from sim.counter_baseline b
    where r.id = b.recipe_id
      and (r.like_count, r.save_count, r.view_count)
          is distinct from (b.like_count, b.save_count, b.view_count);
    delete from sim.counter_baseline;
  end if;
end $$;

-- Engagement the simulated users left on recipes they did not own. Deleting the
-- profile would cascade these anyway, but doing it explicitly first means the
-- counter triggers fire and correct any recipe that survives — which is the
-- case that matters when engage_existing was on.
delete from recipe_likes   where user_id in (select id from sim.actor);
delete from recipe_saves   where user_id in (select id from sim.actor);
delete from recipe_ratings where user_id in (select id from sim.actor);
delete from recipe_views   where user_id in (select id from sim.actor);

-- Anonymous view rows carry no user_id, so nothing above reaches them. They are
-- only ever written against simulated recipes, so they cascade with the recipe
-- delete below — there is no orphan case to clean up separately.

-- Recipes: cascades to ingredient_groups, ingredients, step_groups, steps,
-- recipe_versions, recipe_tags, recipe_shares, likes, saves, views, ratings.
-- A non-sim recipe forked from one of these keeps its row — forked_from_recipe_id
-- is `on delete set null`, so the lineage is dropped, not the recipe.
delete from recipes where id in (select id from sim.recipe);

-- Profiles cascade from auth.users, but delete them explicitly so the order is
-- stated rather than relied upon.
delete from profiles   where id in (select id from sim.actor);
delete from auth.users where id in (select id from sim.actor);

delete from sim.recipe;
delete from sim.actor;

-- Release the pinned time anchor so the next build dates itself to today. While
-- data exists the anchor must NOT move — every timestamp is drawn relative to
-- it, so a shifting `epoch_end` re-dates recipes out from under the versions
-- and engagement that already reference them.
delete from sim.config where key = 'epoch_end';

-- The counters on any surviving recipe are now whatever the triggers left them
-- at. Recompute chef standing from scratch for everyone, exactly as the
-- idempotent backfill in 0001_init.sql does.
update profiles p
set public_recipe_count = s.cnt,
    chef_score          = s.score,
    chef_tier           = chef_tier_for(s.score)
from (
  select
    pr.id,
    count(r.id)::int as cnt,
    chef_score(
      coalesce(sum(r.like_count), 0),
      coalesce(sum(r.save_count), 0),
      coalesce(sum(r.view_count), 0)
    ) as score
  from profiles pr
  left join recipes r on r.owner_id = pr.id and r.visibility = 'public'
  group by pr.id
) s
where p.id = s.id
  and (p.public_recipe_count, p.chef_score, p.chef_tier)
      is distinct from (s.cnt, s.score, chef_tier_for(s.score));

do $$
begin
  raise notice 'sim teardown complete — % recipes and % profiles remain (non-sim)',
    (select count(*) from recipes), (select count(*) from profiles);
end $$;

commit;
