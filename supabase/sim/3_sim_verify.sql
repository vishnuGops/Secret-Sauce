-- 3_sim_verify.sql — assertions over the generated dataset.
--
-- Every check RAISES rather than prints. Nothing in CI runs SQL (docs/SDS.md
-- §11.3), so this file is the entire test suite for the sim: a generator that
-- silently produced garbage would otherwise look exactly like one that worked.
--
-- Read-only. Safe to run at any time, including against a database where the
-- sim has never been applied (it exits early).
--
-- Run:  docker exec -i supabase_db_secret-sauce psql -U postgres -d postgres \
--         -v ON_ERROR_STOP=1 -f - < supabase/sim/3_sim_verify.sql

\set ON_ERROR_STOP on

-- One block, one `raise exception` per invariant. Each message names the
-- invariant and the offending count, so a failure says what broke rather than
-- just that something did.

do $verify$
declare
  v_users   int;
  v_recipes int;
  n bigint;
  m bigint;
  v_detail text;
begin
  if not exists (select 1 from information_schema.schemata where schema_name = 'sim') then
    raise notice 'sim schema absent — nothing to verify';
    return;
  end if;
  select count(*) into v_users   from sim.actor;
  select count(*) into v_recipes from sim.recipe;
  if v_users = 0 then
    raise notice 'sim has no actors — run 2_sim_generate.sql first';
    return;
  end if;

  raise notice '=== sim verify: % actors, % recipes, preset=% seed=% ===',
    v_users, v_recipes, sim.cfg('preset'), sim.seed();

  -- ==========================================================================
  -- A. Counter invariants — the counters must equal what the triggers would
  --    have produced. This is what makes "triggers were disabled for the load"
  --    a performance decision rather than a correctness risk.
  -- ==========================================================================

  select count(*) into n
  from sim.recipe sr join recipes r on r.id = sr.id
  where r.like_count <> (select count(*) from recipe_likes l where l.recipe_id = sr.id);
  if n > 0 then raise exception 'A1 like_count disagrees with recipe_likes on % recipes', n; end if;

  select count(*) into n
  from sim.recipe sr join recipes r on r.id = sr.id
  where r.save_count <> (select count(*) from recipe_saves s where s.recipe_id = sr.id);
  if n > 0 then raise exception 'A2 save_count disagrees with recipe_saves on % recipes', n; end if;

  -- B012: view_count counts DISTINCT SIGNED-IN viewers. Anonymous rows and
  -- repeat visits live in the log and must not reach the counter.
  select count(*) into n
  from sim.recipe sr join recipes r on r.id = sr.id
  where r.view_count <> (
    select count(distinct v.user_id) from recipe_views v
    where v.recipe_id = sr.id and v.user_id is not null
  );
  if n > 0 then raise exception 'A3 view_count is not the distinct signed-in viewer count on % recipes (B012)', n; end if;

  select count(*) into n
  from sim.recipe sr join recipes r on r.id = sr.id
  where r.rating_count <> (select count(*) from recipe_ratings rt where rt.recipe_id = sr.id)
     or r.rating_sum   <> (select coalesce(sum(rt.rating), 0) from recipe_ratings rt where rt.recipe_id = sr.id);
  if n > 0 then raise exception 'A4 rating aggregates disagree with recipe_ratings on % recipes', n; end if;

  -- chef_score must come from the real function, never a restated 3/5/0.2.
  select count(*) into n
  from profiles p
  where p.chef_score <> (
    select chef_score(coalesce(sum(r.like_count),0), coalesce(sum(r.save_count),0),
                      coalesce(sum(r.view_count),0))
    from recipes r where r.owner_id = p.id and r.visibility = 'public'
  );
  if n > 0 then raise exception 'A5 chef_score disagrees with chef_score() on % profiles (Gotcha 19)', n; end if;

  select count(*) into n from profiles p where p.chef_tier <> chef_tier_for(p.chef_score);
  if n > 0 then raise exception 'A6 chef_tier disagrees with chef_tier_for() on % profiles', n; end if;

  -- OPT-P5: the persisted engagement totals are what `chefs_leaderboard` now
  -- shows, so a drift here is a wrong number on a public page — and it would be
  -- invisible, since nothing re-derives them at read time any more.
  select count(*) into n
  from profiles p
  left join (
    select r.owner_id,
           coalesce(sum(r.like_count), 0)::bigint as likes,
           coalesce(sum(r.save_count), 0)::bigint as saves,
           coalesce(sum(r.view_count), 0)::bigint as views
    from recipes r
    where r.visibility = 'public'
    group by r.owner_id
  ) s on s.owner_id = p.id
  where (p.total_likes, p.total_saves, p.total_views)
        is distinct from (coalesce(s.likes, 0), coalesce(s.saves, 0), coalesce(s.views, 0));
  if n > 0 then raise exception 'A6b total_likes/saves/views disagree with the public recipes on % profiles (OPT-P5)', n; end if;

  -- There must actually BE anonymous and repeat rows, or A3 proved nothing.
  select count(*) into n from recipe_views v join sim.recipe sr on sr.id = v.recipe_id
   where v.user_id is null;
  if n = 0 then raise exception 'A7 no anonymous view rows — A3 is vacuous'; end if;

  select count(*) into n from (
    select v.recipe_id, v.user_id from recipe_views v
    join sim.recipe sr on sr.id = v.recipe_id
    where v.user_id is not null
    group by v.recipe_id, v.user_id having count(*) > 1
  ) x;
  if n = 0 then raise exception 'A8 no repeat-visit rows — the dedup half of A3 is vacuous'; end if;

  -- ==========================================================================
  -- B. Authorization invariants — no row RLS could not have produced.
  -- ==========================================================================

  select count(*) into n
  from recipe_ratings rt join recipes r on r.id = rt.recipe_id
  where r.owner_id = rt.user_id;
  if n > 0 then raise exception 'B1 % self-ratings — RLS forbids rating your own recipe', n; end if;

  select count(*) into n
  from recipe_ratings rt join sim.recipe sr on sr.id = rt.recipe_id
  where rt.rating < 0.5 or rt.rating > 5.0 or (rt.rating * 2) <> floor(rt.rating * 2);
  if n > 0 then raise exception 'B2 % ratings outside 0.5-5.0 half-star steps', n; end if;

  -- A private recipe is only reachable by its owner and its share list, so
  -- engagement from anyone else is data the app could never have created.
  select count(*) into n from (
    select l.user_id, l.recipe_id from recipe_likes l
      join sim.recipe sr on sr.id = l.recipe_id
      join recipes r on r.id = sr.id
     where r.visibility = 'private' and l.user_id <> r.owner_id
       and not exists (select 1 from recipe_shares s
                       where s.recipe_id = r.id and s.shared_with_user_id = l.user_id)
    union all
    select v.user_id, v.recipe_id from recipe_views v
      join sim.recipe sr on sr.id = v.recipe_id
      join recipes r on r.id = sr.id
     where r.visibility = 'private' and v.user_id is not null and v.user_id <> r.owner_id
       and not exists (select 1 from recipe_shares s
                       where s.recipe_id = r.id and s.shared_with_user_id = v.user_id)
  ) x;
  if n > 0 then raise exception 'B3 % engagement rows on private recipes from outside the share list', n; end if;

  -- Every like/save/rating must sit on top of a view. A like with no view is
  -- not a session any real user could have had, and it breaks anything
  -- windowed that is built on this later.
  -- This check earned its keep immediately: it caught view ids being built from
  -- `hashtextextended(actor_id) % 100000`, which collides between two viewers of
  -- the same recipe often enough that ~29 recipes lost a view row to `on
  -- conflict do nothing` while still recording the like.
  select count(*) into n
  from recipe_likes l join sim.recipe sr on sr.id = l.recipe_id
  where not exists (select 1 from recipe_views v
                    where v.recipe_id = l.recipe_id and v.user_id = l.user_id);
  if n > 0 then raise exception 'B4 % likes with no corresponding view — the funnel is broken', n; end if;

  select count(*) into n
  from recipe_ratings rt join sim.recipe sr on sr.id = rt.recipe_id
  where not exists (select 1 from recipe_views v
                    where v.recipe_id = rt.recipe_id and v.user_id = rt.user_id);
  if n > 0 then raise exception 'B5 % ratings with no corresponding view', n; end if;

  -- ==========================================================================
  -- C. Temporal invariants — nothing predates its parent, nothing is future.
  -- ==========================================================================

  select count(*) into n
  from sim.recipe sr join recipes r on r.id = sr.id join sim.actor a on a.id = sr.owner_id
  where r.created_at < a.created_at;
  if n > 0 then raise exception 'C1 % recipes created before their owner signed up', n; end if;

  select count(*) into n
  from recipe_views v join sim.recipe sr on sr.id = v.recipe_id join recipes r on r.id = sr.id
  where v.viewed_at < r.created_at;
  if n > 0 then raise exception 'C2 % views logged before the recipe existed', n; end if;

  select count(*) into n
  from recipe_ratings rt join sim.recipe sr on sr.id = rt.recipe_id join recipes r on r.id = sr.id
  where rt.created_at < r.created_at;
  if n > 0 then raise exception 'C3 % ratings written before the recipe existed', n; end if;

  select count(*) into n
  from recipe_versions rv join sim.recipe sr on sr.id = rv.recipe_id join recipes r on r.id = sr.id
  where rv.created_at < r.created_at;
  if n > 0 then raise exception 'C4 % versions dated before their recipe', n; end if;

  select count(*) into n from (
    select 1 from sim.actor where created_at > now()
    union all select 1 from sim.recipe where created_at > now()
    union all select 1 from recipe_views v join sim.recipe sr on sr.id=v.recipe_id where v.viewed_at > now()
  ) x;
  if n > 0 then raise exception 'C5 % simulated rows dated in the future', n; end if;

  -- A fork must descend from something older than itself.
  select count(*) into n
  from recipes f join sim.recipe sr on sr.id = f.id join recipes src on src.id = f.forked_from_recipe_id
  where src.created_at >= f.created_at;
  if n > 0 then raise exception 'C6 % forks older than their source', n; end if;

  -- ==========================================================================
  -- D. Structural invariants — content ordering (B022).
  -- ==========================================================================

  select count(*) into n from (
    select recipe_id from ingredient_groups g join sim.recipe sr on sr.id = g.recipe_id
    group by recipe_id having min(sort_order) <> 0
  ) x;
  if n > 0 then raise exception 'D1 % recipes whose ingredient groups do not start at sort_order 0', n; end if;

  select count(*) into n from (
    select group_id from steps s
    join step_groups g on g.id = s.group_id join sim.recipe sr on sr.id = g.recipe_id
    group by group_id having min(step_order) <> 0
  ) x;
  if n > 0 then raise exception 'D2 % step groups whose step_order does not restart at 0 (B022)', n; end if;

  select count(*) into n from sim.recipe sr join recipes r on r.id = sr.id
   where r.current_version_id is null;
  if n > 0 then raise exception 'D3 % recipes with no current_version_id', n; end if;

  -- (owner_id, title) is the import key; a collision silently collapses two
  -- recipes into one row on any re-import (SDS §11.2).
  select count(*) into n from (
    select owner_id, title from recipes group by owner_id, title having count(*) > 1
  ) x;
  if n > 0 then raise exception 'D4 % (owner_id, title) collisions', n; end if;

  -- Phase 28. `sim.nutrition_for` builds the label from a calorie draw rather
  -- than field by field, so the interesting failure is not "is it null" — it is
  -- a label that contradicts itself, which reads as data on the panel and is
  -- worse than no label at all. Three parent/child bounds, all of which the
  -- function applies AFTER rounding for exactly this reason.
  select count(*) into n
  from sim.recipe sr join recipes r on r.id = sr.id
  where r.nutrition is not null
    and (
         (r.nutrition ->> 'saturated_fat_g')::numeric > (r.nutrition ->> 'total_fat_g')::numeric
      or (r.nutrition ->> 'added_sugars_g')::numeric  > (r.nutrition ->> 'total_sugars_g')::numeric
      or (r.nutrition ->> 'dietary_fiber_g')::numeric
       + (r.nutrition ->> 'total_sugars_g')::numeric  > (r.nutrition ->> 'total_carbs_g')::numeric
    );
  if n > 0 then raise exception 'D5 % nutrition labels contradict themselves (sub-value exceeds its parent)', n; end if;

  -- The key set is the 11 `RecipeNutrition` decodes, no more and no fewer. An
  -- extra key is accepted by the jsonb column and then decodes to nothing —
  -- the read-side twin of the authoring validator's unknown-field error — and a
  -- missing one would mean a `case` fell through to null.
  select count(*) into n
  from sim.recipe sr join recipes r on r.id = sr.id
  where r.nutrition is not null
    and (
      select array_agg(k order by k) from jsonb_object_keys(r.nutrition) k
    ) is distinct from array[
      'added_sugars_g','calories','cholesterol_mg','dietary_fiber_g','protein_g',
      'saturated_fat_g','sodium_mg','total_carbs_g','total_fat_g','total_sugars_g',
      'trans_fat_g'
    ];
  if n > 0 then raise exception 'D6 % nutrition labels do not carry exactly the 11 RecipeNutrition keys', n; end if;

  select count(*) into n
  from sim.recipe sr join recipes r on r.id = sr.id
  cross join lateral jsonb_each(coalesce(r.nutrition, '{}'::jsonb)) e
  where jsonb_typeof(e.value) <> 'number' or (e.value)::text::numeric < 0;
  if n > 0 then raise exception 'D7 % nutrition values are not non-negative numbers', n; end if;

  -- Both states have to EXIST, or the two checks above are vacuous and the
  -- detail screen's `No nutrition info available` branch has nothing to stand
  -- on. The draw is 80/20, so at `tiny` the band is loose on purpose.
  select round(100.0 * count(*) filter (where r.nutrition is not null) / greatest(count(*), 1))
    into n from sim.recipe sr join recipes r on r.id = sr.id;
  if n < 50 or n > 95 then
    raise exception 'D8 %%% of simulated recipes carry a nutrition label — expected 50-95%% (the 20%% with none exercise the empty state)', n;
  end if;

  -- ==========================================================================
  -- E. Shape — is this dataset actually the one we designed?
  --    These are the checks that catch a tuning change quietly flattening the
  --    distribution into "every recipe is average".
  -- ==========================================================================

  -- The population is mostly non-creators. This is the case the database has
  -- never contained, and the whole reason the sim exists.
  select round(100.0 * count(*) filter (where p.public_recipe_count = 0) / count(*))
    into n from profiles p join sim.actor a on a.id = p.id;
  if n < 70 then raise exception 'E1 only %%% of simulated accounts own no public recipe — expected >= 70%%', n; end if;

  -- Every persona must actually appear.
  select count(*) into n from sim.persona p
   where not exists (select 1 from sim.actor a where a.persona = p.code);
  if n > 0 then raise exception 'E2 % personas produced no accounts', n; end if;

  -- Heavy tail: the top 10% of recipes should take a disproportionate share of
  -- the views. A flat distribution means the log-normal collapsed.
  --
  -- The threshold is population-aware because the concentration has a hard
  -- ceiling that has nothing to do with the distribution: a recipe cannot have
  -- more distinct viewers than there are users, so at the `tiny` preset every
  -- popular recipe saturates at 60 and the tail is compressed by arithmetic,
  -- not by a bug. Asserting 40% everywhere would fail `tiny` forever and teach
  -- everyone to ignore the check.
  if v_users >= 250 then
    select round(100.0 * (
      select coalesce(sum(view_count), 0) from (
        select r.view_count from sim.recipe sr join recipes r on r.id = sr.id
        order by r.view_count desc limit greatest(1, (select count(*) from sim.recipe) / 10)
      ) top
    ) / nullif((select sum(r.view_count) from sim.recipe sr join recipes r on r.id = sr.id), 0))
    into n;
    if n is null or n < 40 then
      raise exception 'E3 top 10%% of recipes hold only % percent of views, want >= 40 (exposure tail too flat)', n;
    end if;
  else
    -- Not a softer threshold — the check is meaningless here and a number
    -- tuned until it passes would be worse than no check. With 60 users a
    -- popular recipe saturates at 59 distinct viewers while the median already
    -- reaches ~25, so the ratio cannot exceed roughly 25% no matter how heavy
    -- the tail is. Skipped, loudly.
    raise notice 'E3 skipped: at % users the per-recipe viewer cap bounds this ratio regardless of distribution', v_users;
  end if;

  -- Ratings are J-shaped: the mode is at the top of the scale, not the middle.
  select count(*) into n from recipe_ratings rt join sim.recipe sr on sr.id = rt.recipe_id
   where rt.rating >= 4.5;
  select count(*) into m from recipe_ratings rt join sim.recipe sr on sr.id = rt.recipe_id
   where rt.rating between 2.5 and 3.5;
  if n <= m then
    raise exception 'E4 ratings are not J-shaped: % at 4.5-5.0 vs % at 2.5-3.5', n, m;
  end if;

  -- Both visibilities, and private recipes that really are shared with someone.
  select count(*) into n from sim.recipe sr join recipes r on r.id=sr.id where r.visibility='private';
  if n = 0 then raise exception 'E5 no private recipes'; end if;
  select count(*) into n from recipe_shares s join sim.recipe sr on sr.id = s.recipe_id;
  if n = 0 then raise exception 'E6 no recipe_shares rows — the shared-with-me tab has nothing'; end if;

  -- Forks, and a version history with both a short and a long case.
  select count(*) into n from sim.recipe sr join recipes r on r.id=sr.id
   where r.forked_from_recipe_id is not null;
  if n = 0 then raise exception 'E7 no forks'; end if;

  select count(*) into n from (
    select rv.recipe_id from recipe_versions rv join sim.recipe sr on sr.id = rv.recipe_id
    group by rv.recipe_id having count(*) >= 5
  ) x;
  if n = 0 then raise exception 'E8 no recipe with 5+ versions — the history sheet has no long case'; end if;

  -- The tier ladder should be a pyramid, and the famous-creator tail must
  -- actually reach the top rungs — those thresholds were set against
  -- hand-written demo numbers and nothing organic had ever tested them.
  --
  -- Tiered by population for the same reason as E3: the tier thresholds are
  -- absolute point counts, but the reachable maximum is bounded by how many
  -- users exist to do the liking. At 60 users a recipe tops out near 72 points
  -- however popular it is, so head_chef (5,000) is not reachable by any
  -- distribution — only by more people.
  --
  -- master_chef is asserted only at `large`, and that is a finding rather than
  -- a convenience. The tier thresholds were calibrated against the hand-written
  -- demo numbers in seed.sql, where chef d1 scores 21,000 from 4,000 likes and
  -- 1,600 saves across TWO recipes. At the medium preset that is four likes per
  -- recipe from every one of the 1,000 accounts in existence. The threshold does
  -- not describe a 1,000-user platform, so demanding it here would only teach
  -- whoever tunes this to inflate the exposure model until the number appears.
  -- See docs/BUG-TRACKER.md B043.
  if v_users >= 5000 then
    v_detail := 'master_chef'; m := 1;
    select count(*) into n from profiles p join sim.actor a on a.id = p.id
     where p.chef_tier = 'master_chef';
  elsif v_users >= 250 then
    v_detail := 'head_chef'; m := 1;
    select count(*) into n from profiles p join sim.actor a on a.id = p.id
     where p.chef_tier in ('head_chef', 'master_chef');
  else
    -- 60 users cannot generate 1,000 points for anyone, so the strongest
    -- claim available at this size is that the tail exists at all.
    v_detail := 'line_cook'; m := 1;
    select count(*) into n from profiles p join sim.actor a on a.id = p.id
     where p.chef_tier <> 'home_cook';
  end if;
  if n < m then
    raise exception 'E9 no simulated chef reached % at % users — the exposure tail is too weak',
      v_detail, v_users;
  end if;

  -- Deliberate edge cases must survive tuning changes.
  if not exists (select 1 from profiles p join sim.actor a on a.id=p.id
                 where a.n = 11 and p.display_name = '') then
    raise exception 'E10 the empty-display_name account is missing';
  end if;
  if not exists (select 1 from profiles p join sim.actor a on a.id=p.id
                 where a.n = 12 and length(p.display_name) > 40) then
    raise exception 'E11 the long-display_name account is missing (B032)';
  end if;
  select count(*) into n from (
    select r.owner_id from sim.recipe sr join recipes r on r.id = sr.id
    where r.visibility = 'public' group by r.owner_id having count(*) = 1
  ) x;
  if n = 0 then raise exception 'E12 no chef with exactly 1 public recipe — the "1 recipe" copy case (B031)'; end if;

  -- ==========================================================================
  -- F. The pre-existing seed must be untouched while engage_existing is off.
  --    Every standing pinned in docs/SDS.md §10.7 depends on this.
  -- ==========================================================================

  if sim.cfg('engage_existing', 'false') = 'false' then
    select count(*) into n from (
      select l.recipe_id from recipe_likes l
        where l.user_id in (select id from sim.actor)
          and l.recipe_id not in (select id from sim.recipe)
      union all
      select v.recipe_id from recipe_views v
        where v.user_id in (select id from sim.actor)
          and v.recipe_id not in (select id from sim.recipe)
    ) x;
    if n > 0 then
      raise exception 'F1 % engagement rows from simulated users on non-simulated recipes, but engage_existing is false', n;
    end if;

    -- Spot-check two of the pinned standings directly.
    select chef_score::text into v_detail from profiles
     where id = '00000000-0000-0000-0000-0000000000d1';
    if v_detail is not null and v_detail::numeric <> 21000 then
      raise exception 'F2 Amara Okonkwo scores % — SDS §10.7 pins 21000', v_detail;
    end if;
    select chef_score::text into v_detail from profiles
     where id = '00000000-0000-0000-0000-0000000000d4';
    if v_detail is not null and v_detail::numeric <> 100 then
      raise exception 'F3 Dara Nilsson scores % — SDS §10.7 pins exactly 100 (proves >= is inclusive)', v_detail;
    end if;
  end if;

  -- ==========================================================================
  -- G. Discover's shelves have something to show (Phase 26).
  --
  --    The sim is where a browsing surface gets its population, so "this
  --    fixture can demonstrate that feature" is an assertion, not a hope
  --    (CLAUDE.md, Seed-data fit). Two of the three shelves exist ONLY here:
  --    the authored 14 recipes top out at 85 minutes and carry no forks, so a
  --    seed-only database shows UNDER 30 and two empty shelves.
  --
  --    Every RPC below is EXECUTED at any preset — a shelf whose SQL is broken
  --    fails here — but the row counts are only ASSERTED from `small` up. At 60
  --    users the recipe draw is small enough that "no dish over two hours got
  --    picked" is luck, not a regression, and the same reasoning gates E9.
  -- ==========================================================================

  if to_regprocedure('public.recipes_quick(int, int)') is null then
    raise notice 'G skipped — the Discover shelf RPCs are not applied';
  else
    select count(*) into n from recipes_quick(20, 0);
    select count(*) into m from recipes_projects(20, 0);
    raise notice 'shelves: under-30 %, projects %, most-forked %',
      n, m, (select count(*) from recipes_most_forked(20, 0));

    if v_users >= 250 then
      if n = 0 then
        raise exception 'G1 UNDER 30 is empty — no public recipe totals 1..30 minutes';
      end if;
      if m = 0 then
        raise exception 'G2 WEEKEND PROJECTS is empty — no public recipe is >= 120 min or hard';
      end if;

      -- The shelf ranks by fork count, so it needs a fork tree with a trunk and
      -- not just 20 recipes tied at one. This is what sim.fork_bias() buys, and
      -- it is the assertion that fails if the weighting is ever flattened back
      -- to a uniform draw.
      select coalesce(max(fork_count), 0) into n from (
        select count(*) as fork_count
        from recipes f
        where f.forked_from_recipe_id is not null and f.visibility = 'public'
        group by f.forked_from_recipe_id
      ) x;
      if n < 3 then
        raise exception 'G3 the most-forked recipe has only % fork(s) — MOST FORKED cannot rank (check sim.fork_bias)', n;
      end if;
    end if;
  end if;

  raise notice 'ALL CHECKS PASSED';
end
$verify$;

-- ---------------------------------------------------------------------------
-- Informational summary. Not assertions — these are the numbers worth eyeballing
-- after a tuning change.
-- ---------------------------------------------------------------------------

select p.code as persona, count(*) as accounts,
       round(100.0 * count(*) / sum(count(*)) over (), 1) as pct
from sim.actor a join sim.persona p on p.code = a.persona
group by p.code, p.sort_order order by p.sort_order;

select pr.chef_tier, count(*) as chefs
from profiles pr join sim.actor a on a.id = pr.id
group by pr.chef_tier order by 2 desc;

select
  (select count(*) from sim.recipe) as recipes,
  (select count(*) from sim.dish)   as dishes,
  round((select count(*) from sim.recipe)::numeric
        / nullif((select count(*) from sim.dish), 0), 1) as reuse_per_dish,
  (select count(distinct title) from recipes r join sim.recipe sr on sr.id = r.id) as distinct_titles;
