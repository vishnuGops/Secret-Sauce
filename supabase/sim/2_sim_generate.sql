-- 2_sim_generate.sql — build the simulated population and its history.
--
-- Idempotent, deterministic, scale-parameterized. Re-running with the same seed
-- and preset produces the same database; re-running with a bigger preset adds
-- to it. To SHRINK, run 9_sim_teardown first — nothing here deletes.
--
-- Requires: 0_sim_schema.sql and 1_sim_dishes.sql applied first.
-- Tune with:  update sim.config set value = 'small' where key = 'preset';
--             update sim.config set value = '99'    where key = 'seed';
--
-- ---------------------------------------------------------------------------
-- THE ONE IDEA. supabase/seed.sql writes `like_count = 2500` and no likes. This
-- writes the likes and lets the same arithmetic the triggers use produce 2500.
-- Every counter below is DERIVED from the engagement log, never authored, which
-- is what makes windowed and dated queries possible at all (docs/SDS.md §10.8).
--
-- TWO TRAPS, both of which fail quietly:
--
--   1. Loading ~200k engagement rows with the counter triggers live is ~200k
--      advisory locks, ~200k `update recipes`, and — because recipes_chef_stats
--      watches those columns — ~200k full recompute_chef_stats() passes. The
--      triggers come off for the load and the counters are recomputed
--      set-based. 3_sim_verify then re-derives every counter independently and
--      asserts equality, so "the triggers were off" can never come to mean
--      "the counters are wrong".
--
--   2. The chef recompute is `recompute_all_chef_stats()` — the same function
--      0001_init.sql's backfill runs, so the REAL chef_score() and
--      chef_tier_for() are the only definition of the formula. Restating
--      3 / 5 / 0.2 here would make this a second copy (CLAUDE.md Gotcha 19) and
--      the first one nothing tests.
-- ---------------------------------------------------------------------------

\set ON_ERROR_STOP on

begin;

-- ============================================================================
-- Resolved configuration
-- ============================================================================

create or replace function sim.n_users() returns int language sql stable as $$
  select users from sim.preset where name = sim.cfg('preset', 'medium');
$$;

create or replace function sim.engagement_scale() returns numeric language sql stable as $$
  select engagement_scale from sim.preset where name = sim.cfg('preset', 'medium');
$$;

-- A handful of accounts carry the "famous creator" tail. Creator reach is a
-- power law in every real UGC product, and without an explicit tail no chef
-- ever reaches master_chef: the tier thresholds were set against hand-written
-- demo numbers, not against anything organic.
create or replace function sim.n_stars() returns int language sql stable as $$
  select greatest(1, sim.n_users() / 500);
$$;

-- The window the whole simulated history lives in.
--
-- `epoch_end` is PINNED into sim.config on the first run, never read live from
-- now(). Determinism depends on this: every timestamp is drawn as
-- `from + (to - from) * u`, so a moving `to` moves every date in the dataset.
-- Re-running after a `db:drop` recomputed each recipe's created_at slightly
-- LATER than the value sim.recipe had already recorded, while recipe_versions
-- still derived from the registry — so all 1,671 versions ended up dated before
-- their own recipe. Check C4 in 3_sim_verify.sql caught it; nothing else would
-- have, because every individual file still succeeded.
--
-- 9_sim_teardown clears the key, so a genuinely fresh build re-anchors to today
-- while a re-run on top of existing data stays byte-stable.
insert into sim.config (key, value)
select 'epoch_end', date_trunc('hour', now())::text
where not exists (select 1 from sim.config where key = 'epoch_end');

create or replace function sim.epoch_end() returns timestamptz language sql stable as $$
  select coalesce(
    (select value::timestamptz from sim.config where key = 'epoch_end'),
    date_trunc('hour', now())
  );
$$;

create or replace function sim.epoch_start() returns timestamptz language sql stable as $$
  select sim.epoch_end() - interval '24 months';
$$;

do $$
begin
  if not exists (select 1 from sim.preset where name = sim.cfg('preset', 'medium')) then
    raise exception 'Unknown preset "%" — known: %',
      sim.cfg('preset', 'medium'),
      (select string_agg(name, ', ' order by users) from sim.preset);
  end if;
  if not exists (select 1 from sim.dish) then
    raise exception 'sim.dish is empty — apply supabase/sim/1_sim_dishes.sql first';
  end if;
  raise notice 'sim: preset=% users=% seed=% dishes=%',
    sim.cfg('preset'), sim.n_users(), sim.seed(), (select count(*) from sim.dish);
end $$;

-- ============================================================================
-- Triggers off for the bulk load. Rolled back automatically if this
-- transaction fails, so a crash cannot leave the database with dead triggers.
-- ============================================================================

alter table recipe_likes   disable trigger recipe_likes_count;
alter table recipe_saves   disable trigger recipe_saves_count;
alter table recipe_views   disable trigger recipe_views_count;
alter table recipe_ratings disable trigger recipe_ratings_agg;
alter table recipes        disable trigger recipes_chef_stats;
alter table recipes        disable trigger recipes_touch;
-- Versions are bulk-inserted many-per-recipe; the pointer is set set-based in
-- step 4 instead, so the per-row trigger would be N-1 wasted UPDATEs per recipe.
alter table recipe_versions disable trigger recipe_versions_set_current;
-- Search documents are rebuilt set-based at the end (OPT-P1). Left enabled, the
-- ingredient load would rebuild each recipe's document once per INSERT
-- statement, and the recipes trigger would build one from a recipe that has no
-- ingredients yet — wasted either way, since every row is rewritten below.
alter table recipes           disable trigger recipes_search_tsv;
alter table ingredients       disable trigger ingredients_search_tsv_ins;
alter table recipe_tags       disable trigger recipe_tags_search_tsv_ins;

-- ============================================================================
-- 1. The population
-- ============================================================================

insert into sim.actor (id, n, persona, created_at)
select
  sim.uid('actor', g.n),
  g.n,
  -- Star accounts are forced to `power` so the famous-creator tail exists at
  -- every preset rather than depending on a lucky draw.
  case when g.n <= sim.n_stars() then 'power'
       else sim.persona_for(sim.rand('actor:' || g.n, 'persona')) end,
  -- Compounding growth: more signups recently than two years ago.
  sim.rand_ts('actor:' || g.n, 'signup', sim.epoch_start(), sim.epoch_end() - interval '1 day', 2.2)
from generate_series(1, sim.n_users()) g(n)
on conflict (n) do nothing;

-- auth.users. One bcrypt hash is computed per run and shared by every simulated
-- account: bcrypt is deliberately slow (~100ms), so hashing per row would cost
-- 100 seconds at the medium preset and 13 minutes at large. The plaintext is a
-- fresh random uuid that is never stored, printed, or returned, so no simulated
-- account is sign-in-able and the shared hash is not a credential (B018 — this
-- file may be run against the hosted project by documented procedure).
do $$
declare
  v_hash text := crypt(gen_random_uuid()::text, gen_salt('bf'));
  v_given text[] := array[
    'Amara','Bruno','Chen','Dara','Elif','Farid','Greta','Hiroshi','Imani','Jonas',
    'Kiran','Lucia','Mateo','Nadia','Omar','Priya','Quentin','Rosa','Sami','Tara',
    'Ulla','Viktor','Wren','Xiomara','Yusuf','Zara','Aoife','Bogdan','Camila','Dmitri',
    'Esther','Fatima','Gabriel','Hana','Ines','Jae','Kwame','Leila','Marek','Noor',
    'Olga','Pedro','Rania','Soren','Thandiwe','Ubah','Vera','Wei'
  ];
  v_family text[] := array[
    'Okonkwo','Castellani','Wei','Nilsson','Yilmaz','Haddad','Lindqvist','Tanaka','Mbeki','Berg',
    'Sharma','Moreau','Alvarez','Petrova','Kaur','Novak','Fischer','Silva','Okafor','Rossi',
    'Andersen','Baptiste','Chowdhury','Delgado','Eriksen','Farrell','Gruber','Hussain','Ivanov','Jensen',
    'Kowalski','Larsen','Mendes','Nakamura','Oyelaran','Pereira','Quintana','Reyes','Sato','Toure',
    'Ueda','Varga','Weber','Xu','Yamada','Zielinski','Adeyemi','Blanc'
  ];
  v_bios text[] := array[
    'Cooking mostly for one, badly, happily.',
    'Weeknight food. Nothing that takes longer than the rice.',
    'Writing down what my parents never measured.',
    'Baker by weekend, spreadsheet by weekday.',
    'I chase texture more than flavour.',
    'Trying to cook through one cookbook a year.',
    'Fermenting things my flatmates have opinions about.',
    'Here to read, not to post.',
    'Feeding four people who agree on nothing.',
    'Ex-restaurant. Recovering.',
    'Everything in one pan or it does not happen.',
    'Learning to cook at 41. It is going fine.'
  ];
begin
  insert into auth.users (
    instance_id, id, aud, role, email,
    encrypted_password, email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data,
    confirmation_token, recovery_token, email_change_token_new, email_change
  )
  select
    '00000000-0000-0000-0000-000000000000', a.id, 'authenticated', 'authenticated',
    -- A domain that cannot receive mail, so a password reset can never be
    -- delivered to a real inbox.
    'sim-' || a.n || '@sim.secretsauce.local',
    v_hash, a.created_at, a.created_at, a.created_at,
    '{"provider":"email","providers":["email"]}',
    '{}'::jsonb,
    '', '', '', ''
  from sim.actor a
  on conflict (id) do nothing;

  -- Explicit upsert rather than relying on on_auth_user_created: after a
  -- `db:drop` the auth user survives and the trigger only fires on INSERT, so
  -- the profile would never be rebuilt (B015).
  insert into profiles (id, display_name, bio, created_at)
  select
    a.id,
    case
      -- Deliberate edge cases, at fixed indices so they are always present.
      -- Every one of these is a rendering case no seeded account has ever
      -- covered, and three of them are logged bugs (B031, B032).
      when a.n = 11 then ''                                              -- empty: monogram has nothing to use
      when a.n = 12 then 'Maximilian Alexander Featherstonehaugh-Cholmondeley'  -- must ellipsise, not overflow
      when a.n = 13 then 'Пётр Кузнецов'                                  -- non-Latin
      when a.n = 14 then 'مريم الحسيني'                                    -- right-to-left
      when a.n = 15 then 'Björk'                                          -- single word + diacritic
      when a.n = 16 then '🥕 CarrotTop'                                    -- leading emoji
      else v_given[1 + (abs(hashtextextended('g' || a.n, sim.seed())) % array_length(v_given, 1))]
           || ' ' ||
           v_family[1 + (abs(hashtextextended('f' || a.n, sim.seed())) % array_length(v_family, 1))]
    end,
    case when sim.rand_bool('actor:' || a.n, 'hasbio', 0.55)
      then v_bios[1 + (abs(hashtextextended('b' || a.n, sim.seed())) % array_length(v_bios, 1))]
      else null end,
    a.created_at
  from sim.actor a
  on conflict (id) do update
    set display_name = excluded.display_name,
        bio          = excluded.bio;
end $$;

-- ============================================================================
-- 2. Recipes
--
-- Count per creator is skewed toward the low end of their persona's band, so a
-- persona's ceiling is a tail and not an average.
-- ============================================================================

create temporary table sim_new_recipe on commit drop as
with counts as (
  select
    a.id as owner_id, a.n as owner_n, a.persona, a.created_at as joined_at,
    p.min_recipes
      + floor(power(sim.rand('actor:' || a.n, 'nrecipes'), 2.2)
              * (p.max_recipes - p.min_recipes + 1))::int as k
  from sim.actor a
  join sim.persona p on p.code = a.persona
),
expanded as (
  select
    c.owner_id, c.owner_n, c.persona, c.joined_at, g.i,
    -- Globally unique recipe index, stable for a given (owner, i).
    (c.owner_n * 1000 + g.i) as n
  from counts c
  cross join lateral generate_series(1, c.k) g(i)
  where c.k > 0
),
picked as (
  select
    e.*,
    sim.pick_dish(sim.rand('recipe:' || e.n, 'dish')) as slug,
    -- Recipes cluster after signup and thin out: real posting behaviour decays.
    sim.rand_ts('recipe:' || e.n, 'created', e.joined_at, sim.epoch_end(), 0.6) as created_at
  from expanded e
)
select
  sim.uid('recipe', p.n) as id,
  p.n, p.owner_id, p.owner_n, p.persona, p.slug, p.created_at,
  d.doc,
  case when pe.private_rate >= 1.0 then 'private'
       when sim.rand_bool('recipe:' || p.n, 'visibility', pe.private_rate) then 'private'
       else 'public' end::recipe_visibility as visibility,
  -- Occurrence index of this dish for this owner, which is what guarantees
  -- (owner_id, title) uniqueness — the import key (docs/SDS.md §11.2).
  (row_number() over (partition by p.owner_id, p.slug order by p.n))::int as occurrence
from picked p
join sim.dish d on d.slug = p.slug
join sim.persona pe on pe.code = p.persona;

-- One merged, DEDUPLICATED template sequence per dish: the dish's own variants
-- first, then every generic template it does not already contain.
--
-- The dedupe is the whole point. Treating the two lists as disjoint and
-- indexing with an offset looks correct and is not: `indian-chana-masala`
-- authors "Weeknight {title}" itself, and the generic pool has the same
-- template at n=2, so an owner with five copies of that dish got the identical
-- title at occurrence 1 and occurrence 5. That is a (owner_id, title)
-- collision, which the import key silently collapses to one row (SDS §11.2) —
-- caught by check D4 in 3_sim_verify.sql.
create temporary table sim_dish_template on commit drop as
with dish_own as (
  select d.slug, t.ordinality::int as sub, t.value #>> '{}' as template
  from sim.dish d
  cross join lateral jsonb_array_elements(
    coalesce(d.doc -> 'variant_titles', '[]'::jsonb)
  ) with ordinality t(value, ordinality)
),
generic as (
  select d.slug, tv.n as sub, tv.template
  from sim.dish d
  cross join sim.title_variant tv
  where not exists (
    select 1 from dish_own o where o.slug = d.slug and o.template = tv.template
  )
),
merged as (
  select slug, template, 0 as grp, sub from dish_own
  union all
  select slug, template, 1 as grp, sub from generic
)
select
  slug, template,
  (row_number() over (partition by slug order by grp, sub))::int as idx
from merged;

create index on sim_dish_template (slug, idx);

create temporary table sim_titled on commit drop as
select
  r.*,
  coalesce(
    replace(
      (select t.template from sim_dish_template t
        where t.slug = r.slug and t.idx = r.occurrence),
      '{title}', r.doc ->> 'title'
    ),
    -- Past the end of the pool an owner holds more copies of one dish than
    -- there are distinct templates. Unreachable in practice; unique anyway.
    (r.doc ->> 'title') || ' №' || r.occurrence
  ) as title
from sim_new_recipe r;

insert into recipes (
  id, owner_id, title, description, cuisine, category, difficulty,
  prep_minutes, cook_minutes, servings, visibility, attribution,
  nutrition, created_at, updated_at
)
select
  t.id, t.owner_id, t.title,
  t.doc ->> 'description', t.doc ->> 'cuisine', t.doc ->> 'category',
  (t.doc ->> 'difficulty')::difficulty,
  (t.doc ->> 'prep_minutes')::int, (t.doc ->> 'cook_minutes')::int,
  (t.doc ->> 'servings')::int,
  t.visibility, t.doc ->> 'attribution',
  -- Phase 28. An authored label wins; otherwise the generator draws one from
  -- the dish's category (`sim.nutrition_for`, defined in 0_sim_schema.sql).
  -- No dish carries one today — a label belongs to a recipe as published, not
  -- to the dish idea — but the format allows it via simData's `$ref`, and
  -- authored-beats-generated is the right precedence if one ever does.
  --
  -- `nullif(…, 'null'::jsonb)` because a dish spelling the field out as an
  -- explicit `"nutrition": null` (which is how recipeData writes "no info")
  -- yields a JSON null here, not SQL NULL — the same trap `save_recipe`
  -- handles, and `recipes_nutrition_is_object` rejects it either way.
  coalesce(
    nullif(t.doc -> 'nutrition', 'null'::jsonb),
    sim.nutrition_for('recipe:' || t.n, t.doc ->> 'category')
  ),
  t.created_at, t.created_at
from sim_titled t
on conflict (id) do nothing;

insert into sim.recipe (id, n, owner_id, slug, created_at)
select t.id, t.n, t.owner_id, t.slug, t.created_at from sim_titled t
on conflict (n) do nothing;

-- ============================================================================
-- 3. Recipe content
--
-- Groups and their children are numbered from 0 WITHIN each group, matching
-- SupabaseRecipeRepository._persistContent. Numbering continuously across
-- groups looks right until the first edit re-persists per-group and silently
-- renumbers everything (the B022 failure mode).
-- ============================================================================

insert into ingredient_groups (id, recipe_id, name, sort_order)
select
  sim.uid('ig', t.n::bigint * 100 + g.ord),
  t.id, coalesce(g.value ->> 'name', ''), g.ord
from sim_titled t
cross join lateral (
  select value, (ordinality - 1)::int as ord
  from jsonb_array_elements(t.doc -> 'ingredient_groups') with ordinality
) g
on conflict (id) do nothing;

insert into ingredients (id, group_id, quantity, unit, name, note, is_optional, sort_order)
select
  sim.uid('ing', t.n::bigint * 10000 + g.ord * 100 + i.ord),
  sim.uid('ig', t.n::bigint * 100 + g.ord),
  nullif(i.value ->> 'quantity', '')::numeric,
  i.value ->> 'unit', i.value ->> 'name', i.value ->> 'note',
  coalesce((i.value ->> 'is_optional')::boolean, false),
  i.ord
from sim_titled t
cross join lateral (
  select value, (ordinality - 1)::int as ord
  from jsonb_array_elements(t.doc -> 'ingredient_groups') with ordinality
) g
cross join lateral (
  select value, (ordinality - 1)::int as ord
  from jsonb_array_elements(g.value -> 'ingredients') with ordinality
) i
on conflict (id) do nothing;

insert into step_groups (id, recipe_id, name, sort_order)
select
  sim.uid('sg', t.n::bigint * 100 + g.ord),
  t.id, coalesce(g.value ->> 'name', ''), g.ord
from sim_titled t
cross join lateral (
  select value, (ordinality - 1)::int as ord
  from jsonb_array_elements(t.doc -> 'step_groups') with ordinality
) g
on conflict (id) do nothing;

insert into steps (id, group_id, step_order, text, duration_minutes, temperature, tip, sort_order)
select
  sim.uid('st', t.n::bigint * 10000 + g.ord * 100 + s.ord),
  sim.uid('sg', t.n::bigint * 100 + g.ord),
  s.ord,
  s.value ->> 'text',
  nullif(s.value ->> 'duration_minutes', '')::int,
  s.value ->> 'temperature',
  s.value ->> 'tip',
  s.ord
from sim_titled t
cross join lateral (
  select value, (ordinality - 1)::int as ord
  from jsonb_array_elements(t.doc -> 'step_groups') with ordinality
) g
cross join lateral (
  select value, (ordinality - 1)::int as ord
  from jsonb_array_elements(g.value -> 'steps') with ordinality
) s
on conflict (id) do nothing;

-- ============================================================================
-- 4. Version history
--
-- Most recipes are never edited; a few are edited repeatedly. Geometric, so the
-- version history sheet has both an empty-ish case and a long one.
-- ============================================================================

create temporary table sim_version on commit drop as
select
  r.id as recipe_id, r.n, r.owner_id, r.created_at,
  v.i as version_number,
  sim.uid('ver', r.n::bigint * 100 + v.i) as version_id,
  r.created_at + ((v.i - 1) * interval '1 day'
    * (1 + floor(sim.rand('recipe:' || r.n || ':v' || v.i, 'vgap') * 30))) as ts
from sim.recipe r
cross join lateral generate_series(
  1,
  1 + floor(power(sim.rand('recipe:' || r.n, 'nversions'), 4.0) * 9)::int
) v(i);

insert into recipe_versions (id, recipe_id, version_number, author_id, change_summary, content_snapshot, created_at)
select
  v.version_id, v.recipe_id, v.version_number, v.owner_id,
  case when v.version_number = 1 then 'Created' else 'Revised' end,
  '{}'::jsonb,
  least(v.ts, sim.epoch_end())
from sim_version v
on conflict (id) do nothing;

update recipes r
set current_version_id = last.version_id
from (
  select distinct on (recipe_id) recipe_id, version_id
  from sim_version order by recipe_id, version_number desc
) last
where r.id = last.recipe_id and r.current_version_id is distinct from last.version_id;

-- ============================================================================
-- 5. Forks
--
-- ~4% of recipes, always from an OLDER public recipe so the lineage is
-- chronologically coherent. Includes forks of forks by construction: a fork is
-- eligible as a source for anything created after it.
--
-- The SOURCE is drawn weighted by reach, not uniformly. Uniform is what this
-- did until Phase 26, and it produced a fork tree with no trunk: measured at
-- the medium preset, 74 forks landed on 54 different sources and the
-- most-forked recipe in the database had been forked TWICE. That is not what
-- forking looks like anywhere — people rewrite the recipe everybody already
-- cooks — and it left Discover's MOST FORKED shelf with 20 cards to show and
-- no order to show them in. Weighted, the same 74 forks land on 28 sources
-- with a top recipe at 10.
--
-- Weight = the recipe's own exposure draw (sim.exposure_draw — the SAME number
-- §7 turns into views, so the recipes that get forked are the recipes that get
-- read), times the star-chef multiplier §7 also applies, raised to
-- sim.fork_bias(). A recipe outside the sim — the Kitchen's authored 14 — has
-- no draw, so it takes exp(2.0), the median of the distribution: eligible, and
-- neither favoured nor excluded.
--
-- The draw itself is an exponential race (A-Res weighted sampling): with u
-- uniform in (0,1), the candidate maximising ln(u)/weight is a sample from the
-- weight distribution, in one pass, with no running total to carry. `desc`
-- picks it because ln(u) is negative and a bigger weight pulls the ratio toward
-- zero. Deterministic, like every other draw here: u is keyed on the (fork,
-- candidate) pair, so a re-run reproduces the same tree.
--
-- One lateral instead of the two correlated subqueries this replaces — those
-- scanned and sorted the eligible set twice per fork to return two columns of
-- the same row.
--
-- The `forked_from_recipe_id is null` guard makes this additive, which also
-- means a database generated BEFORE the weighting landed keeps its flat tree:
-- run 9_sim_teardown.sql and regenerate to re-cut it.
-- ============================================================================

update recipes r
set forked_from_recipe_id = src.source_id,
    forked_from_version_id = src.source_version_id
from (
  select
    f.id as fork_id,
    s.id as source_id,
    s.current_version_id as source_version_id
  from sim.recipe sr
  join recipes f on f.id = sr.id
  cross join lateral (
    select r2.id, r2.current_version_id
    from recipes r2
    left join sim.recipe sr2 on sr2.id = r2.id
    left join sim.actor  a2  on a2.id = sr2.owner_id
    where r2.visibility = 'public'
      and r2.created_at < f.created_at
      and r2.owner_id <> f.owner_id
    order by
      ln(greatest(sim.rand(f.id::text || ':' || r2.id::text, 'forksrc'), 1e-12))
      / power(
          coalesce(sim.exposure_draw(sr2.n), exp(2.0))
            * case when a2.n is not null and a2.n <= sim.n_stars() then 8 else 1 end,
          sim.fork_bias()
        ) desc
    limit 1
  ) s
  where sim.rand_bool('recipe:' || sr.n, 'isfork', 0.04)
) src
where r.id = src.fork_id
  and r.forked_from_recipe_id is null;

-- ============================================================================
-- 6. Shares
--
-- A private recipe is only reachable by its owner and the people it is shared
-- with, so this table is also what bounds who may legitimately engage with one.
-- ============================================================================

insert into recipe_shares (recipe_id, shared_with_user_id, permission, created_at)
select distinct on (sr.id, a.id)
  sr.id, a.id, 'view'::share_permission,
  greatest(sr.created_at, a2.created_at) + interval '1 hour'
from sim.recipe sr
join recipes r on r.id = sr.id and r.visibility = 'private'
cross join lateral generate_series(1, sim.rand_int('recipe:' || sr.n, 'nshares', 0, 5)) g(k)
join lateral (
  select act.id, act.created_at
  from sim.actor act
  where act.id <> sr.owner_id
    and act.n = 1 + (abs(hashtextextended('share:' || sr.n || ':' || g.k, sim.seed())) % sim.n_users())
  limit 1
) a on true
join sim.actor a2 on a2.id = a.id
where a2.created_at < sim.epoch_end() - interval '1 hour'
on conflict (recipe_id, shared_with_user_id) do nothing;

-- ============================================================================
-- 7. Views — the base of the funnel
--
-- Nothing below is drawn independently: a like, save, or rating only exists on
-- top of a view. A like with no view is data no real session could produce, and
-- it would quietly break every windowed metric built on this later.
-- ============================================================================

-- Weighted pool: a lurker appears six times, a ghost once, so who does the
-- viewing reflects the persona mix rather than being uniform.
create temporary table sim_pool on commit drop as
select (row_number() over (order by a.n, g.i))::int as slot, a.id as actor_id, a.created_at
from sim.actor a
join sim.persona p on p.code = a.persona
cross join lateral generate_series(1, p.view_weight) g(i);

create index on sim_pool (slot);

-- Reach per recipe: log-normal (a few recipes take most of the traffic),
-- multiplied by the owner's persona boost and the star tail, and capped at the
-- population — a recipe cannot have more distinct viewers than there are users.
--
-- The log-normal itself is `sim.exposure_draw`, not an expression here: §5 has
-- to weight fork sources by the same per-recipe number long before this table
-- exists, and two inline copies of one draw are two copies of a formula
-- (Gotcha 19).
create temporary table sim_reach on commit drop as
select
  sr.id as recipe_id, sr.n, sr.owner_id, r.visibility, r.created_at,
  least(
    greatest(1, round(
      sim.exposure_draw(sr.n)
      * p.exposure_boost
      * case when a.n <= sim.n_stars() then 8 else 1 end
      -- Older recipes have had longer to accumulate.
      * (0.35 + 0.65 * extract(epoch from (sim.epoch_end() - r.created_at))
                     / greatest(extract(epoch from (sim.epoch_end() - sim.epoch_start())), 1))
      * sim.engagement_scale()
    )::int),
    (select count(*)::int from sim.actor)
  ) as target
from sim.recipe sr
join recipes r on r.id = sr.id
join sim.actor a on a.id = sr.owner_id
join sim.persona p on p.code = a.persona;

-- Public recipes draw viewers from the weighted pool; private ones only from
-- their share list, because that is the only audience RLS would ever have
-- allowed. Duplicate draws collapse — the birthday effect makes distinct
-- viewers slightly fewer than `target`, which is realistic anyway.
-- `since` is the earliest moment this pair could have happened: a view has to
-- come after the recipe exists AND after the viewer signs up, whichever is
-- later. Modelling it as eligibility instead — "the viewer must predate the
-- recipe" — is wrong twice over: it says a user who joined last week can never
-- read a two-year-old recipe, and it silently discards most draws rather than
-- resampling them, which cost the star chefs ~80% of their reach.
create temporary table sim_view_pair_raw on commit drop as
select distinct on (recipe_id, actor_id)
  recipe_id, actor_id, owner_id, n, created_at,
  greatest(created_at, viewer_since) as since
from (
  select
    rc.recipe_id, rc.owner_id, rc.n, rc.created_at,
    pool.actor_id, pool.created_at as viewer_since
  from sim_reach rc
  cross join lateral generate_series(1, rc.target) k(k)
  join sim_pool pool
    on pool.slot = 1 + (abs(hashtextextended('view:' || rc.n || ':' || k.k, sim.seed()))
                        % (select count(*)::int from sim_pool))
  where rc.visibility = 'public'

  union all

  select
    rc.recipe_id, rc.owner_id, rc.n, rc.created_at,
    s.shared_with_user_id, a.created_at
  from sim_reach rc
  join recipe_shares s on s.recipe_id = rc.recipe_id
  join sim.actor a on a.id = s.shared_with_user_id
  where rc.visibility = 'private'
) x
where x.actor_id <> x.owner_id
  -- Nothing can happen in the future; a pair with no room left is dropped.
  and greatest(x.created_at, x.viewer_since) < sim.epoch_end();

-- A dense, globally unique number per (recipe, viewer) pair, used to build view
-- ids. The obvious shortcut — folding actor_id through
-- `hashtextextended(...) % 100000` — collides between two viewers of the same
-- recipe, and the colliding row is then swallowed by `on conflict (id) do
-- nothing`, leaving a like whose view does not exist. Check B4 in
-- 3_sim_verify.sql caught exactly that.
create temporary table sim_view_pair on commit drop as
select (row_number() over (order by recipe_id, actor_id))::bigint as pair_no, *
from sim_view_pair_raw;

create index on sim_view_pair (pair_no);

-- The log is append-only and keeps repeat visits. `recipes.view_count` counts
-- distinct signed-in viewers, so these extra rows must NOT move it — which is
-- exactly the B012 invariant 3_sim_verify asserts.
insert into recipe_views (id, recipe_id, user_id, viewed_at)
select
  sim.uid('view', vp.pair_no * 10 + v.visit),
  vp.recipe_id, vp.actor_id,
  sim.rand_ts('v:' || vp.n || ':' || vp.actor_id || ':' || v.visit, 'when',
              vp.since, sim.epoch_end(), 1.8)
from sim_view_pair vp
cross join lateral generate_series(
  1,
  1 + floor(power(sim.rand('v:' || vp.n || ':' || vp.actor_id, 'visits'), 3.0) * 4)::int
) v(visit)
on conflict (id) do nothing;

-- Anonymous views: roughly 30% again on top. `anon` holds INSERT on this table,
-- so counting these would reopen the inflation vector B012 closed. They are
-- logged and must never reach the counter.
insert into recipe_views (id, recipe_id, user_id, viewed_at)
select
  sim.uid('anonview', rc.n::bigint * 100000 + k.k),
  rc.recipe_id, null,
  sim.rand_ts('av:' || rc.n || ':' || k.k, 'when', rc.created_at, sim.epoch_end(), 1.8)
from sim_reach rc
cross join lateral generate_series(1, greatest(1, (rc.target * 3) / 10)) k(k)
where rc.visibility = 'public'
on conflict (id) do nothing;

-- ============================================================================
-- 8. Likes, saves, ratings — strictly subsets of the viewers
-- ============================================================================

insert into recipe_likes (user_id, recipe_id, created_at)
select vp.actor_id, vp.recipe_id,
       sim.rand_ts('l:' || vp.n || ':' || vp.actor_id, 'when', vp.since, sim.epoch_end(), 1.8)
from sim_view_pair vp
join sim.actor a on a.id = vp.actor_id
join sim.persona p on p.code = a.persona
where sim.rand('l:' || vp.n || ':' || vp.actor_id, 'like') < p.like_rate
on conflict (user_id, recipe_id) do nothing;

insert into recipe_saves (user_id, recipe_id, created_at)
select vp.actor_id, vp.recipe_id,
       sim.rand_ts('s:' || vp.n || ':' || vp.actor_id, 'when', vp.since, sim.epoch_end(), 1.8)
from sim_view_pair vp
join sim.actor a on a.id = vp.actor_id
join sim.persona p on p.code = a.persona
where sim.rand('s:' || vp.n || ':' || vp.actor_id, 'save') < p.save_rate
on conflict (user_id, recipe_id) do nothing;

-- Ratings are J-SHAPED, not normal: the mode is 5.0 with a long thin tail down
-- to 0.5. A bell centred on 3.0 is the classic synthetic-data tell, and it
-- would make Discover's Bayesian prior look like it was doing nothing.
--
-- `q` is the recipe's latent quality and controls the exponent, so a genuinely
-- weak recipe produces a genuinely low average rather than noise around the
-- same mean. A small polarized set (1s and 5s, mean ~3) is forced on purpose.
--
-- The owner is already excluded by sim_view_pair — RLS forbids self-rating with
-- a `with check`, so a self-rating here would be data the app could not create.
insert into recipe_ratings (user_id, recipe_id, rating, created_at, updated_at)
select
  vp.actor_id, vp.recipe_id,
  case
    when sim.rand_bool('recipe:' || vp.n, 'polarized', 0.012)
      then case when sim.rand('rt:' || vp.n || ':' || vp.actor_id, 'pole') < 0.5
                then 1.0 else 5.0 end
    else greatest(0.5, least(5.0,
      round((5.0 - 4.5 * power(
        sim.rand('rt:' || vp.n || ':' || vp.actor_id, 'val'),
        1.2 + 3.5 * sim.rand('recipe:' || vp.n, 'quality')
      )) * 2) / 2))
  end::numeric(2,1),
  sim.rand_ts('rt:' || vp.n || ':' || vp.actor_id, 'when', vp.since, sim.epoch_end(), 1.8),
  sim.rand_ts('rt:' || vp.n || ':' || vp.actor_id, 'when', vp.since, sim.epoch_end(), 1.8)
from sim_view_pair vp
join sim.actor a on a.id = vp.actor_id
join sim.persona p on p.code = a.persona
where sim.rand('rt:' || vp.n || ':' || vp.actor_id, 'rate') < p.rate_rate
on conflict (user_id, recipe_id) do nothing;

-- ============================================================================
-- 9. Derive the counters
--
-- Everything above wrote LOG rows. This is the only place counters are set, and
-- it computes them the same way the triggers would have.
-- ============================================================================

with agg as (
  select
    sr.id as recipe_id,
    (select count(*) from recipe_likes l where l.recipe_id = sr.id)                  as likes,
    (select count(*) from recipe_saves s where s.recipe_id = sr.id)                  as saves,
    -- Distinct SIGNED-IN viewers. Anonymous rows and repeat visits are in the
    -- log and deliberately absent from this number (B012).
    (select count(distinct v.user_id) from recipe_views v
      where v.recipe_id = sr.id and v.user_id is not null)                            as views,
    (select count(*) from recipe_ratings rt where rt.recipe_id = sr.id)              as rcount,
    (select coalesce(sum(rt.rating), 0) from recipe_ratings rt where rt.recipe_id = sr.id) as rsum
  from sim.recipe sr
)
update recipes r
set like_count   = agg.likes,
    save_count   = agg.saves,
    view_count   = agg.views,
    rating_count = agg.rcount,
    rating_sum   = agg.rsum,
    rating_avg   = case when agg.rcount = 0 then 0 else round(agg.rsum / agg.rcount, 2) end
from agg
where r.id = agg.recipe_id;

-- Chef standing, through the REAL functions: `recompute_all_chef_stats()` is
-- the same statement the idempotent backfill at the end of 0001_init.sql runs,
-- and it is a function rather than a fourth copy of the UPDATE precisely so the
-- formula lives in one place (Gotcha 19).
select recompute_all_chef_stats();

-- ============================================================================
-- Triggers back on
-- ============================================================================

alter table recipe_likes   enable trigger recipe_likes_count;
alter table recipe_saves   enable trigger recipe_saves_count;
alter table recipe_views   enable trigger recipe_views_count;
alter table recipe_ratings enable trigger recipe_ratings_agg;
alter table recipes        enable trigger recipes_chef_stats;
alter table recipes        enable trigger recipes_touch;
alter table recipe_versions enable trigger recipe_versions_set_current;
alter table recipes           enable trigger recipes_search_tsv;
alter table ingredients       enable trigger ingredients_search_tsv_ins;
alter table recipe_tags       enable trigger recipe_tags_search_tsv_ins;

-- Build every simulated recipe's search document in one pass, now that its
-- ingredients and tags are all in place (OPT-P1). Keyed on `search_tsv is null`
-- rather than a join to `sim.recipe`: the triggers were off for the whole load,
-- so NULL identifies exactly the rows this run created — including the forks,
-- which are not all registered the same way — and seeded recipes (built with the
-- triggers on) are already non-null, so this cannot touch them.
update recipes r
   set search_tsv = recipe_search_tsv(r.id, r.title, r.description)
 where r.search_tsv is null;

-- Counts are scoped to sim.recipe on purpose. Reporting global totals would
-- fold in the 64 taster ratings from seed.sql and make the funnel look wrong
-- (more ratings than likes), which is exactly the kind of number someone
-- chases for an hour before realising it was the message, not the data.
do $$
declare v_views bigint; v_anon bigint; v_likes bigint; v_saves bigint; v_ratings bigint;
begin
  select count(*) filter (where v.user_id is not null),
         count(*) filter (where v.user_id is null)
    into v_views, v_anon
    from recipe_views v join sim.recipe sr on sr.id = v.recipe_id;
  select count(*) into v_likes   from recipe_likes   l  join sim.recipe sr on sr.id = l.recipe_id;
  select count(*) into v_saves   from recipe_saves   s  join sim.recipe sr on sr.id = s.recipe_id;
  select count(*) into v_ratings from recipe_ratings rt join sim.recipe sr on sr.id = rt.recipe_id;
  raise notice 'sim complete (sim-owned rows only): % actors, % recipes, % views (+% anon), % likes, % saves, % ratings',
    (select count(*) from sim.actor), (select count(*) from sim.recipe),
    v_views, v_anon, v_likes, v_saves, v_ratings;
end $$;

commit;
