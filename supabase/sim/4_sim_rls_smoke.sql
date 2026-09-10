-- 4_sim_rls_smoke.sql — the RLS policies, exercised **per persona**, as a
-- SIGNED-IN user, against the population 2_sim_generate.sql actually built.
--
-- docs/ROADMAP.md Phase 24 "Verification": "RLS smoke test per persona with
-- `set local role authenticated`". This is that file.
--
-- WHY IT EXISTS NEXT TO THE TWO THINGS THAT LOOK LIKE IT.
--
--   * `supabase/sim/3_sim_verify.sql` runs as `postgres`, which bypasses every
--     policy. It asserts that no row exists which RLS *could not have produced*
--     (a like on a private recipe from outside its share list, a self-rating).
--     That is a statement about the generator, not about the policies: it would
--     pass unchanged on a database with RLS disabled outright.
--   * `supabase/tests/rls_matrix.sql` (BL-7) is the policy matrix, and it is
--     the authority on policy *shape* — but it builds three throwaway users and
--     two recipes of its own. Every seat in it is an owner, a sharee, or a
--     stranger, constructed to make one claim true.
--
-- The gap between them is the everyday case: a real account, holding whatever
-- the persona mix actually gave it, reading the catalogue everyone else can
-- see. 79% of simulated accounts own no public recipe at all — the ghost and
-- the lurker are the two most common users this product has, and until this
-- file nothing had ever asked what they can do while signed in. A policy that
-- is right for a hand-built fixture and wrong for an account with zero recipes
-- (or twenty private ones) fails nowhere else.
--
-- WHAT IT PROVES, for each of the seven personas, seated as one REAL actor
-- drawn from the `sim.actor` registry:
--
--   * a public recipe is readable, including by a persona that owns nothing;
--   * an unrelated private recipe is not — row, content, and version history;
--   * a private recipe IS readable by its owner and by everyone in its
--     `recipe_shares` list (§X, so the zeroes above are not vacuous);
--   * a persona cannot rate its own recipe — the `with check` in
--     `ratings_write`, not a hidden button;
--   * a persona cannot write another user's recipe. **Asserted as a ROW COUNT,
--     never as the absence of an error** (CLAUDE.md Gotcha 2): an RLS-denied
--     `update`/`delete` matches 0 rows and returns SUCCESS, which is the whole
--     reason this file is not three `select`s;
--   * server-owned columns (`like_count`, `chef_score`, fork lineage) are
--     refused on a direct write with `42501` — the column-level grants from
--     B050/OPT-S1 and B082, which RLS cannot express because RLS filters rows;
--   * Discover is readable signed-in by an account that owns nothing.
--
-- SMALL POPULATIONS. A persona with no actor at the current preset is SKIPPED
-- **loudly** — a `raise notice` at the point of the skip and a SKIP line in the
-- report — never silently. Same for the three checks that need the seat to own
-- a recipe. A vacuous pass is the exact failure this file exists to prevent, so
-- a run in which no persona was exercised at all raises.
--
-- NO WALL CLOCK. `sim.epoch_end()` is a pinned anchor (B044) and is typically
-- days or weeks behind `now()`, so nothing here is keyed to "the last 7 days"
-- or to `now()` at all. Every fixture is chosen by identity, never by date.
--
-- It WRITES (a rating, a title) and then ROLLS THE WHOLE TRANSACTION BACK, so
-- it leaves no row, no rating and no helper function behind — and so it must
-- not be run inside another transaction. Read the run lines below rather than
-- pasting the body somewhere.
--
-- Run:  melos run db:sim:rls        (or)
--       psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/sim/4_sim_rls_smoke.sql
--       docker cp supabase/sim/4_sim_rls_smoke.sql supabase_db_secret-sauce:/tmp/4.sql
--       docker exec supabase_db_secret-sauce psql -U postgres -d postgres \
--         -v ON_ERROR_STOP=1 -f /tmp/4.sql
--
-- It is deliberately NOT part of the `db:sim` chain (which is `0 -> 1 -> 2 ->
-- 3`, an explicit list in tool/db.dart, and runs inside `db:reset`): this file
-- writes before it rolls back, and a build step should not. Run it after any
-- change to a policy, a `security definer` function, or the column grants —
-- alongside `melos run db:rls`, never instead of it.
--
-- Trigger: the same list as BL-7, plus any change to the persona table or to
-- what a persona owns.

\set ON_ERROR_STOP on

begin;

-- Transaction-local arming flag for the helper below. `is_local => true`, so it
-- cannot outlive this transaction and a PostgREST caller has no way to set it
-- in the transaction their RPC runs in.
select set_config('sim_rls.armed', '1', true);

-- Runs the given statement as the CURRENT role and reports what happened
-- without aborting the outer transaction: `err` is the SQLSTATE (null on
-- success) and `rows` is the row count (-1 when the statement raised).
-- `security invoker`, so RLS and the column grants apply to the caller — which
-- is the entire point, and the only way to tell Gotcha 2's silent 0-row denial
-- from a real refusal.
--
-- The twin of `public.rls_matrix_do`, deliberately under its own name rather
-- than shared: both are created inside a transaction that rolls back, so
-- neither file can rely on the other's copy existing, and a `create or replace`
-- against a name the other file owns would be a way for one test harness to
-- redefine another. Created here, dropped before the rollback, and never
-- `create or replace`: a name collision must fail loudly rather than clobber
-- something real.
--
-- The arming check is not ceremony. This function executes an arbitrary string,
-- Postgres grants EXECUTE on a new function to `public`, and PostgREST exposes
-- every function in `public` as an RPC (Gotcha 3) — so a copy that ever reached
-- a committed schema would be arbitrary SQL at any caller's own grants. Three
-- locks, exactly as BL-7 has: this check, the `drop function` before the
-- rollback, and a `drop function if exists` line in supabase/scripts/drop.sql.
create function public.sim_rls_do(p_sql text, out err text, out rows bigint)
language plpgsql as $fn$
begin
  if current_setting('sim_rls.armed', true) is distinct from '1' then
    raise exception 'sim_rls_do is a test harness and is not armed'
      using errcode = '42501';
  end if;
  err  := null;
  execute p_sql;
  get diagnostics rows = row_count;
exception when others then
  -- The `when others` has to swallow whatever `p_sql` raised — that is the job.
  -- It must NOT swallow the arming refusal above, which would turn a hard no
  -- into a quiet `(42501, -1)` row, so re-check and re-raise first.
  if current_setting('sim_rls.armed', true) is distinct from '1' then
    raise;
  end if;
  err  := sqlstate;
  rows := -1;
end
$fn$;

do $smoke$
declare
  -- population
  v_users    int;
  v_recipes  int;
  v_shelves  boolean;

  -- §X fixture: one private recipe that really is shared with somebody
  v_priv     uuid;
  v_priv_own uuid;
  v_priv_to  uuid;

  -- per-persona seat and its fixtures
  rec            record;
  v_id           text;
  v_actor        uuid;
  v_own_public   uuid;
  v_own_private  uuid;
  v_own_any      uuid;
  v_other_public uuid;
  v_other_priv   uuid;
  v_unrated      uuid;
  v_seats        int := 0;
  v_unread       uuid[] := '{}';

  -- scratch
  v_err  text;
  v_n    bigint;
  n      bigint;

  -- results
  v_log  text[] := '{}';
  v_pass int := 0;
  v_fail int := 0;
  v_skip int := 0;
  v_head text;
  s      text;
begin
  -- ==========================================================================
  -- Guards. Each returns rather than raises: this file is safe to run against a
  -- database that has never seen the sim, and against plain Postgres.
  -- ==========================================================================
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    raise notice 'no `authenticated` role — this is not a Supabase database, nothing to check';
    return;
  end if;
  if not exists (select 1 from information_schema.schemata where schema_name = 'sim') then
    raise notice 'sim schema absent — run supabase/sim/0_sim_schema.sql first, nothing to check';
    return;
  end if;

  select count(*) into v_users   from sim.actor;
  select count(*) into v_recipes from sim.recipe;
  if v_users = 0 or v_recipes = 0 then
    raise notice 'sim has % actors and % recipes — run 2_sim_generate.sql first, nothing to check',
      v_users, v_recipes;
    return;
  end if;

  raise notice '';
  raise notice '=== Phase 24 per-persona RLS smoke: % actors, % recipes, preset=% seed=% ===',
    v_users, v_recipes, sim.cfg('preset'), sim.seed();

  -- The Discover shelf RPCs are Phase 26 and may not be applied on an older
  -- database; 3_sim_verify.sql's group G guards the same way.
  v_shelves := to_regprocedure('public.recipes_quick(int, int)') is not null;

  -- ==========================================================================
  -- A. Fixtures, chosen as postgres. Nothing here is created — every id below
  --    is a row the generator already wrote, which is the difference between
  --    this file and supabase/tests/rls_matrix.sql.
  -- ==========================================================================
  select count(*) into n from sim.recipe sr join recipes r on r.id = sr.id
   where r.visibility = 'public';
  v_log := v_log || format(E'%s\tA1  fixture · the population holds public recipes\t%s of %s',
    n > 0, n, v_recipes);

  select r.id, r.owner_id, s2.shared_with_user_id
    into v_priv, v_priv_own, v_priv_to
  from sim.recipe sr
  join recipes r on r.id = sr.id
  join recipe_shares s2 on s2.recipe_id = r.id
  where r.visibility = 'private'
  order by sr.n, s2.shared_with_user_id
  limit 1;
  v_log := v_log || format(E'%s\tA2  fixture · a private recipe with a share row\t%s',
    v_priv is not null, coalesce(v_priv::text, 'none — §X will skip'));

  select count(*) into n from sim.persona p
   where exists (select 1 from sim.actor a where a.persona = p.code);
  v_log := v_log || format(E'%s\tA3  fixture · personas with at least one actor\t%s of %s',
    n > 0, n, (select count(*) from sim.persona));

  -- ==========================================================================
  -- P. One seat per persona.
  --
  --    The seat is a REAL actor, drawn deterministically and preferring the one
  --    that can answer the most questions: an account owning both a public and
  --    a private recipe first, then a private one, then a public one, then the
  --    lowest `n`. That preference is not cherry-picking a passing case — every
  --    check below is a claim about authorization, not about the account — it
  --    is how a `collector` (0..1 recipes) or a `vault` (private only) gets its
  --    ownership checks exercised at all instead of skipped.
  -- ==========================================================================
  for rec in select code, sort_order, label from sim.persona order by sort_order loop
    execute 'reset role';
    v_id := format('P%s', rec.sort_order);

    select a.id into v_actor
    from sim.actor a
    left join lateral (
      select count(*) filter (where r.visibility = 'public')  as pub,
             count(*) filter (where r.visibility = 'private') as priv
      from sim.recipe sr join recipes r on r.id = sr.id
      where sr.owner_id = a.id
    ) o on true
    where a.persona = rec.code
    order by (o.pub > 0 and o.priv > 0) desc, o.priv > 0 desc, o.pub > 0 desc, a.n
    limit 1;

    -- LOUD, per the Seed-data rule: a persona nobody drew is a persona nobody
    -- tested, and that has to be visible in the output rather than inferred
    -- from a smaller total.
    if v_actor is null then
      raise notice 'SKIP  % (%) · no actor at preset "%" — persona NOT exercised',
        rec.code, rec.label, sim.cfg('preset');
      v_log := v_log || format(E's\t%s.0  %s · no actor at this preset\tpersona SKIPPED', v_id, rec.code);
      v_skip := v_skip + 1;
      continue;
    end if;

    select r.id into v_own_public
    from sim.recipe sr join recipes r on r.id = sr.id
    where sr.owner_id = v_actor and r.visibility = 'public' order by sr.n limit 1;

    select r.id into v_own_private
    from sim.recipe sr join recipes r on r.id = sr.id
    where sr.owner_id = v_actor and r.visibility = 'private' order by sr.n limit 1;

    v_own_any := coalesce(v_own_public, v_own_private);

    select r.id into v_other_public
    from sim.recipe sr join recipes r on r.id = sr.id
    where r.visibility = 'public' and r.owner_id <> v_actor order by sr.n limit 1;

    -- Deliberately a private recipe this seat has NO relationship to: not the
    -- owner and not on its share list. Picking the §X fixture instead would
    -- make every zero below depend on the seat happening not to be a sharee,
    -- which is luck at one preset and a false pass at another.
    select r.id into v_other_priv
    from sim.recipe sr join recipes r on r.id = sr.id
    where r.visibility = 'private'
      and r.owner_id <> v_actor
      and not exists (
        select 1 from recipe_shares s2
        where s2.recipe_id = r.id and s2.shared_with_user_id = v_actor
      )
    order by sr.n limit 1;

    -- A public recipe this seat has not already rated, so P.16's success is the
    -- policy allowing the write and not a primary-key conflict being reported
    -- as one.
    select r.id into v_unrated
    from sim.recipe sr join recipes r on r.id = sr.id
    where r.visibility = 'public' and r.owner_id <> v_actor
      and not exists (
        select 1 from recipe_ratings rt
        where rt.recipe_id = r.id and rt.user_id = v_actor
      )
    order by sr.n limit 1;

    -- Both of these are fixtures the seat's checks pass as an id, so a NULL
    -- would not fail a claim — it would raise 23502 halfway through and take
    -- the run down for a reason having nothing to do with authorization. Skip
    -- the seat loudly instead, and only count it once it can actually be sat.
    if v_other_public is null or v_unrated is null then
      raise notice 'SKIP  % · no public recipe by another owner that this seat has not already rated — persona NOT exercised',
        rec.code;
      v_log := v_log || format(E's\t%s.0  %s · no usable public fixture\tpersona SKIPPED', v_id, rec.code);
      v_skip := v_skip + 1;
      continue;
    end if;
    v_seats := v_seats + 1;

    raise notice 'seat  % (%) · actor % · owns public=%, private=%',
      rec.code, rec.label, v_actor,
      coalesce(v_own_public::text, '-'), coalesce(v_own_private::text, '-');

    -- ------------------------------------------------------------------------
    -- Sit down. Everything from here to the next `reset role` is this persona.
    -- ------------------------------------------------------------------------
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub', v_actor)::text, true);

    -- --- reads ---------------------------------------------------------------
    select count(*) into n from recipes where id = v_other_public;
    v_log := v_log || format(E'%s\t%s.1  %s · reads another user''s public recipe\t%s row',
      n = 1, v_id, rec.code, n);

    select count(*) into n from ingredient_groups where recipe_id = v_other_public;
    v_log := v_log || format(E'%s\t%s.2  %s · reads that recipe''s content\t%s row',
      n >= 1, v_id, rec.code, n);

    if v_other_priv is null then
      raise notice 'SKIP  %.3-5 % · no unrelated private recipe in this population', v_id, rec.code;
      v_log := v_log || format(E's\t%s.3  %s · read an unrelated private recipe\tno such fixture', v_id, rec.code);
      v_skip := v_skip + 1;
    else
      -- Recorded so the zeroes can be shown to be about the READER rather than
      -- about a row that was not there (§X6).
      v_unread := v_unread || v_other_priv;

      select count(*) into n from recipes where id = v_other_priv;
      v_log := v_log || format(E'%s\t%s.3  %s · cannot read an unrelated private recipe\t%s row',
        n = 0, v_id, rec.code, n);

      select count(*) into n from ingredient_groups where recipe_id = v_other_priv;
      v_log := v_log || format(E'%s\t%s.4  %s · cannot read its content\t%s row',
        n = 0, v_id, rec.code, n);

      select count(*) into n from recipe_versions where recipe_id = v_other_priv;
      v_log := v_log || format(E'%s\t%s.5  %s · cannot read its version history\t%s row',
        n = 0, v_id, rec.code, n);
    end if;

    if v_own_private is null then
      raise notice 'SKIP  %.6 % · owns no private recipe — the owner-read half is not exercised here',
        v_id, rec.code;
      v_log := v_log || format(E's\t%s.6  %s · reads own private recipe\towns none', v_id, rec.code);
      v_skip := v_skip + 1;
    else
      select count(*) into n from recipes where id = v_own_private;
      v_log := v_log || format(E'%s\t%s.6  %s · reads own private recipe\t%s row',
        n = 1, v_id, rec.code, n);
    end if;

    -- `saves_select` is `user_id = auth.uid()`: unlike a like or a rating, a
    -- save is private to the person who made it. At this population size the
    -- sim has written thousands of them, so a policy that leaked would be
    -- unmistakable here in a way it is not against three fixture rows.
    select count(*) into n from recipe_saves where user_id <> v_actor;
    v_log := v_log || format(E'%s\t%s.7  %s · sees nobody else''s saves\t%s row',
      n = 0, v_id, rec.code, n);

    -- --- writes denied SILENTLY (Gotcha 2) -----------------------------------
    -- The point of the whole file. RLS denies these by filtering rows, so the
    -- statement succeeds and touches nothing; a client that does not add
    -- `.select()` reads that as a saved edit. Assert the COUNT, never the
    -- absence of an error.
    select err, rows into v_err, v_n from public.sim_rls_do(format(
      'update recipes set title = ''sim-rls probe'' where id = %L', v_other_public));
    v_log := v_log || format(E'%s\t%s.8  %s · update another user''s public recipe matches 0 rows (Gotcha 2)\t%s',
      v_err is null and v_n = 0, v_id, rec.code, coalesce(v_err, v_n || ' row'));

    select err, rows into v_err, v_n from public.sim_rls_do(format(
      'delete from recipes where id = %L', v_other_public));
    v_log := v_log || format(E'%s\t%s.9  %s · delete another user''s public recipe matches 0 rows (Gotcha 2)\t%s',
      v_err is null and v_n = 0, v_id, rec.code, coalesce(v_err, v_n || ' row'));

    if v_other_priv is not null then
      select err, rows into v_err, v_n from public.sim_rls_do(format(
        'update recipes set title = ''sim-rls probe'' where id = %L', v_other_priv));
      v_log := v_log || format(E'%s\t%s.10 %s · update an unreadable private recipe matches 0 rows\t%s',
        v_err is null and v_n = 0, v_id, rec.code, coalesce(v_err, v_n || ' row'));
    end if;

    -- --- writes denied LOUDLY (42501) ----------------------------------------
    select err into v_err from public.sim_rls_do(format(
      'insert into ingredient_groups (recipe_id, name) values (%L, ''sim-rls hijack'')', v_other_public));
    v_log := v_log || format(E'%s\t%s.11 %s · insert content into another user''s recipe must FAIL\t%s',
      v_err = '42501', v_id, rec.code, coalesce(v_err, 'no error'));

    -- B050 / OPT-S1: RLS filters rows and cannot filter columns, so the
    -- counters are held by column-level grants instead. Aimed at the seat's OWN
    -- recipe wherever it has one, because "not even the owner" is the claim.
    select err into v_err from public.sim_rls_do(format(
      'update recipes set like_count = like_count + 1 where id = %L',
      coalesce(v_own_any, v_other_public)));
    v_log := v_log || format(E'%s\t%s.12 %s · write like_count must FAIL (B050)\t%s%s',
      v_err = '42501', v_id, rec.code, coalesce(v_err, 'no error'),
      case when v_own_any is null then ' (no own recipe — aimed at another user''s)' else ' (own recipe)' end);

    select err into v_err from public.sim_rls_do(format(
      'update profiles set chef_score = 9999 where id = %L', v_actor));
    v_log := v_log || format(E'%s\t%s.13 %s · write own chef_score must FAIL (B050)\t%s',
      v_err = '42501', v_id, rec.code, coalesce(v_err, 'no error'));

    -- B082: fork lineage is server-owned for the same reason a counter is — it
    -- is a claim about someone else's recipe, and `recipes_most_forked` ranks
    -- on it.
    select err into v_err from public.sim_rls_do(format(
      'update recipes set forked_from_recipe_id = %L where id = %L',
      v_other_public, coalesce(v_own_any, v_other_public)));
    v_log := v_log || format(E'%s\t%s.14 %s · forge fork lineage must FAIL (B082)\t%s',
      v_err = '42501', v_id, rec.code, coalesce(v_err, 'no error'));

    -- `ratings_write`'s third conjunct: `not owns_recipe(recipe_id)`. In the
    -- policy, not in a hidden button.
    if v_own_any is null then
      raise notice 'SKIP  %.15 % · owns no recipe — the self-rating refusal is not exercised here',
        v_id, rec.code;
      v_log := v_log || format(E's\t%s.15 %s · rate own recipe must FAIL\towns none', v_id, rec.code);
      v_skip := v_skip + 1;
    else
      select err into v_err from public.sim_rls_do(format(
        'insert into recipe_ratings (user_id, recipe_id, rating) values (%L, %L, 5.0)',
        v_actor, v_own_any));
      v_log := v_log || format(E'%s\t%s.15 %s · rate own recipe must FAIL\t%s',
        v_err = '42501', v_id, rec.code, coalesce(v_err, 'no error'));
    end if;

    -- --- the positives, so none of the above passes vacuously ----------------
    select err, rows into v_err, v_n from public.sim_rls_do(format(
      'insert into recipe_ratings (user_id, recipe_id, rating) values (%L, %L, 4.0)',
      v_actor, v_unrated));
    v_log := v_log || format(E'%s\t%s.16 %s · rate another user''s public recipe\t%s',
      v_err is null and v_n = 1, v_id, rec.code, coalesce(v_err, v_n || ' row'));

    if v_own_any is null then
      raise notice 'SKIP  %.17 % · owns no recipe — the owner-write half is not exercised here',
        v_id, rec.code;
      v_log := v_log || format(E's\t%s.17 %s · update own recipe\towns none', v_id, rec.code);
      v_skip := v_skip + 1;
    else
      select err, rows into v_err, v_n from public.sim_rls_do(format(
        'update recipes set description = ''sim-rls owner write'' where id = %L', v_own_any));
      v_log := v_log || format(E'%s\t%s.17 %s · update own recipe matches 1 row\t%s',
        v_err is null and v_n = 1, v_id, rec.code, coalesce(v_err, v_n || ' row'));
    end if;

    -- Discover, signed in. The ghost and the lurker own nothing at all, so this
    -- is the entire product for them — and `recipes_select`'s first disjunct
    -- (`visibility = 'public'`) plus the shelf RPCs' EXECUTE grants are the only
    -- things standing between them and an empty app.
    select count(*) into n from (
      select r.id from recipes r where r.visibility = 'public'
      order by r.created_at desc, r.id limit 20
    ) page;
    if v_shelves then
      select count(*) into v_n from recipes_quick(20, 0);
      v_log := v_log || format(E'%s\t%s.18 %s · Discover reads: browse page + UNDER 30 shelf\t%s + %s row',
        n > 0 and v_n > 0, v_id, rec.code, n, v_n);
    else
      v_log := v_log || format(E'%s\t%s.18 %s · Discover reads: browse page (shelf RPCs not applied)\t%s row',
        n > 0, v_id, rec.code, n);
    end if;
  end loop;

  execute 'reset role';

  -- ==========================================================================
  -- X. The other half of the private-recipe claim: the row IS readable, by
  --    exactly the two principals the policy names. Without this section every
  --    zero in P.3–P.5 would also be produced by a private recipe that simply
  --    did not exist.
  -- ==========================================================================
  if v_priv is null then
    raise notice 'SKIP  X1-X6 · no private recipe with a share row at preset "%" — the owner/sharee half is NOT exercised',
      sim.cfg('preset');
    v_log := v_log || format(E's\tX1-X6 shared · the owner/sharee read half\tno shared private recipe');
    v_skip := v_skip + 1;
  else
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub', v_priv_own)::text, true);

    select count(*) into n from recipes where id = v_priv;
    v_log := v_log || format(E'%s\tX1  owner · reads their own private recipe\t%s row', n = 1, n);

    perform set_config('request.jwt.claims', json_build_object('sub', v_priv_to)::text, true);

    select count(*) into n from recipes where id = v_priv;
    v_log := v_log || format(E'%s\tX2  shared-with · reads the private recipe\t%s row', n = 1, n);

    select count(*) into n from ingredient_groups where recipe_id = v_priv;
    v_log := v_log || format(E'%s\tX3  shared-with · reads its content\t%s row', n >= 1, n);

    -- A share is a READ right and nothing more. `share_permission` has an
    -- `edit` value every policy ignores (`recipes_update` is `owns_recipe`,
    -- full stop), and the sim writes `view` — so this is the silent denial
    -- again, on a row the reader can genuinely see.
    select err, rows into v_err, v_n from public.sim_rls_do(format(
      'update recipes set title = ''sim-rls probe'' where id = %L', v_priv));
    v_log := v_log || format(E'%s\tX4  shared-with · update it matches 0 rows (Gotcha 2)\t%s',
      v_err is null and v_n = 0, coalesce(v_err, v_n || ' row'));

    select err into v_err from public.sim_rls_do(format(
      'insert into recipe_shares (recipe_id, shared_with_user_id) values (%L, %L)',
      v_priv, v_priv_own));
    v_log := v_log || format(E'%s\tX5  shared-with · re-share it must FAIL\t%s',
      v_err = '42501', coalesce(v_err, 'no error'));

    select err into v_err from public.sim_rls_do(format(
      'insert into recipe_versions (recipe_id, version_number, author_id, content_snapshot) '
      'values (%L, 99, %L, ''{}''::jsonb)', v_priv, v_priv_to));
    v_log := v_log || format(E'%s\tX6  shared-with · append a version must FAIL\t%s',
      v_err = '42501', coalesce(v_err, 'no error'));

    execute 'reset role';
  end if;

  -- The non-vacuity guard for P.3–P.5: every private recipe a seat could not
  -- read is still there when postgres looks. A run where these rows had been
  -- deleted out from under the seats would otherwise read as a clean pass.
  if array_length(v_unread, 1) is null then
    raise notice 'SKIP  X7 · no seat had an unrelated private recipe to be refused';
    v_log := v_log || format(E's\tX7  non-vacuity · the refused rows exist\tnothing refused');
    v_skip := v_skip + 1;
  else
    select count(distinct id) into n from recipes where id = any (v_unread);
    v_log := v_log || format(E'%s\tX7  non-vacuity · every refused private recipe exists as postgres\t%s of %s',
      n = (select count(distinct u) from unnest(v_unread) u), n,
      (select count(distinct u) from unnest(v_unread) u));
  end if;

  -- ==========================================================================
  -- Report
  -- ==========================================================================
  raise notice '';
  raise notice '=== Phase 24 per-persona RLS smoke (as authenticated) ===';
  foreach s in array v_log loop
    v_head := split_part(s, E'\t', 1);
    -- `rpad` TRUNCATES when the label is longer than the width, and on a FAIL
    -- line the tail is the bug id you would grep for. Pad to at least 68, never
    -- cut. NULL renders as the empty string and lands in the FAIL branch, which
    -- is correct: `v_err = '42501'` is NULL whenever the statement did not
    -- raise, and that is exactly what a "must FAIL" check exists to catch.
    if v_head = 's' then
      -- Already counted at the point of the skip, where the `raise notice`
      -- naming the reason was emitted; this line is the report's copy of it.
      raise notice 'SKIP  %  [%]',
        rpad(split_part(s, E'\t', 2), greatest(68, length(split_part(s, E'\t', 2)))),
        split_part(s, E'\t', 3);
    elsif v_head = 't' then
      v_pass := v_pass + 1;
      raise notice 'PASS  %  [%]',
        rpad(split_part(s, E'\t', 2), greatest(68, length(split_part(s, E'\t', 2)))),
        split_part(s, E'\t', 3);
    else
      v_fail := v_fail + 1;
      raise warning 'FAIL  %  [%]',
        rpad(split_part(s, E'\t', 2), greatest(68, length(split_part(s, E'\t', 2)))),
        split_part(s, E'\t', 3);
    end if;
  end loop;
  raise notice '--- % passed, % failed, % skipped, % personas seated of % ---',
    v_pass, v_fail, v_skip, v_seats, (select count(*) from sim.persona);

  if v_fail > 0 then
    raise exception 'Phase 24 RLS smoke: % of % checks FAILED — see the warnings above',
      v_fail, v_pass + v_fail;
  end if;
  -- A run that seated nobody is not a pass: every assertion above is
  -- conditional on a seat, so zero seats would print "0 failed" and prove
  -- nothing whatsoever. Belt and braces rather than a live path — the guards at
  -- the top return early on an empty registry, and `sim.actor.persona` is an FK
  -- into `sim.persona`, so actors-without-personas cannot happen. It costs one
  -- comparison and it is the line that keeps this file from ever becoming the
  -- vacuous pass it exists to prevent.
  if v_seats = 0 then
    raise exception 'Phase 24 RLS smoke: NO persona had an actor — nothing was exercised';
  end if;
  raise notice 'ALL CHECKS PASSED';
end
$smoke$;

drop function public.sim_rls_do(text);

-- Nothing this file wrote is meant to survive it: the ratings, the title and
-- description writes, and the helper above all go away here.
rollback;
