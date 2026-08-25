-- rls_matrix.sql — the RLS acceptance matrix, exercised as a SIGNED-IN user.
--
-- docs/ROADMAP.md BL-7. Everything else that has ever touched RLS in this repo
-- runs as `postgres`, which bypasses policies outright: seed.sql, the sim,
-- 3_sim_verify.sql, CI's database.yml and every hosted check. `anon` was proven
-- in Phase 26. `authenticated` was not — and that is the gap B053 lived in, where
-- `recipes_select` could not see its own `INSERT … RETURNING` row and *every*
-- recipe creation failed, unnoticed, for months.
--
-- What it does, in one transaction that is ROLLED BACK at the end:
--
--   1. creates three throwaway auth users — an owner, a user the owner shares a
--      private recipe with, and an unrelated signed-in stranger;
--   2. creates one private and one public recipe (with content) owned by the owner;
--   3. re-runs the whole matrix under `set local role authenticated` +
--      `request.jwt.claims`, plus an `anon` regression pass;
--   4. prints one PASS/FAIL line per check and RAISES if any failed.
--
-- Nothing survives the run: no auth.users row, no recipe, no helper function.
-- That is why it is safe against any database, including hosted — but note it
-- does WRITE before it rolls back, so do not run it inside another transaction.
--
-- Two failure modes it exists for, because both look exactly like working code:
--   * an `update` / `delete` that RLS denies matches 0 rows and returns SUCCESS
--     (CLAUDE.md Gotcha 2 — the server-side twin of B011);
--   * a `select` policy that cannot see the row its own `INSERT … RETURNING`
--     just wrote (B053).
--
-- Run:  melos run db:rls          (or)
--       psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/rls_matrix.sql
--
-- Trigger: any change to a policy, a `security definer` function, or the column
-- grants in supabase/migrations/0001_init.sql.

\set ON_ERROR_STOP on

begin;

-- Transaction-local arming flag for the helper below. `is_local => true`, so it
-- cannot outlive this transaction and a PostgREST caller has no way to set it in
-- the transaction their RPC runs in.
select set_config('rls_matrix.armed', '1', true);

-- Runs the given statement as the CURRENT role and reports what happened without
-- aborting the outer transaction: `err` is the SQLSTATE (null on success) and
-- `rows` is the row count (-1 when the statement raised). `security invoker`, so
-- RLS and the column grants apply to the caller — which is the entire point.
--
-- Created inside the transaction and dropped before the rollback, so it never
-- reaches a committed schema. It is deliberately NOT `create or replace`: a name
-- collision must fail loudly rather than clobber something real.
--
-- The arming check is not ceremony. This function executes an arbitrary string,
-- Postgres grants EXECUTE on a new function to `public`, and PostgREST exposes
-- every function in `public` as an RPC (Gotcha 3) — so a copy that ever reached
-- a committed schema would be arbitrary SQL at any caller's own grants, which
-- for `anon` is the unmetered `recipe_views` insert loop B012 exists to stop.
-- Three locks: this check, the `drop function` before the rollback, and a
-- `drop function if exists` line in supabase/scripts/drop.sql.
create function public.rls_matrix_do(p_sql text, out err text, out rows bigint)
language plpgsql as $fn$
begin
  if current_setting('rls_matrix.armed', true) is distinct from '1' then
    raise exception 'rls_matrix_do is a test harness and is not armed'
      using errcode = '42501';
  end if;
  err  := null;
  execute p_sql;
  get diagnostics rows = row_count;
exception when others then
  -- The `when others` below has to swallow whatever `p_sql` raised — that is the
  -- job. It must NOT swallow the arming refusal above, which would turn a hard
  -- no into a quiet `(42501, -1)` row, so re-check and re-raise first.
  if current_setting('rls_matrix.armed', true) is distinct from '1' then
    raise;
  end if;
  err  := sqlstate;
  rows := -1;
end
$fn$;

do $rls$
declare
  -- actors
  v_owner    uuid := gen_random_uuid();
  v_sharee   uuid := gen_random_uuid();
  v_other    uuid := gen_random_uuid();
  v_ids      uuid[];
  v_names    text[] := array['BL-7 owner', 'BL-7 sharee', 'BL-7 stranger'];

  -- fixtures
  v_private  uuid;
  v_private2 uuid;
  v_public   uuid;
  v_ig_priv  uuid;
  v_ig_pub   uuid;
  v_sg_priv  uuid;
  v_tag      uuid;
  v_orphan   uuid;

  -- scratch
  v_new      uuid;
  v_saved    uuid;
  v_fork     uuid;
  v_err      text;
  v_n        bigint;
  n          bigint;
  i          int;
  v_json     jsonb;

  -- results
  v_log      text[] := '{}';
  v_pass     int := 0;
  v_fail     int := 0;
  s          text;
begin
  -- Plain Postgres (no PostgREST roles) has nothing to check — the same guard
  -- the grants block in 0001_init.sql uses.
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    raise notice 'no `authenticated` role — this is not a Supabase database, nothing to check';
    return;
  end if;

  -- ==========================================================================
  -- Fixtures, as postgres. Random ids so nothing here can collide with a real
  -- row even in the impossible case that this transaction commits.
  -- ==========================================================================
  v_ids := array[v_owner, v_sharee, v_other];
  for i in 1..3 loop
    insert into auth.users (
      instance_id, id, aud, role, email,
      encrypted_password, email_confirmed_at, created_at, updated_at,
      raw_app_meta_data, raw_user_meta_data,
      confirmation_token, recovery_token, email_change_token_new, email_change
    ) values (
      '00000000-0000-0000-0000-000000000000', v_ids[i], 'authenticated', 'authenticated',
      format('rls-matrix-%s@secretsauce.test', v_ids[i]),
      -- Not a credential (B018): this is not a valid bcrypt hash, so no password
      -- can ever match it, and the row is gone at rollback either way.
      '$2a$10$rls.matrix.fixture.never.signs.in',
      now(), now(), now(),
      '{"provider":"email","providers":["email"]}',
      jsonb_build_object('display_name', v_names[i]),
      '', '', '', ''
    );
  end loop;
  -- profiles come from the on_auth_user_created trigger.

  insert into recipes (owner_id, title, description, servings, visibility,
                       prep_minutes, cook_minutes)
  values (v_owner, 'BL-7 private fixture', 'private', 2, 'private', 5, 5)
  returning id into v_private;

  -- A second private recipe, shared with nobody. It exists only so the two
  -- halves of the like policy can be tested independently: D18 inserts against
  -- `v_private` (which the stranger has no row for, so a denial cannot be
  -- confused with a primary-key conflict) and D19 deletes the pre-existing row
  -- below, on a recipe D18 never touches.
  insert into recipes (owner_id, title, description, servings, visibility,
                       prep_minutes, cook_minutes)
  values (v_owner, 'BL-7 private unshared fixture', 'private', 2, 'private', 5, 5)
  returning id into v_private2;

  insert into recipes (owner_id, title, description, servings, visibility,
                       prep_minutes, cook_minutes)
  values (v_owner, 'BL-7 public fixture', 'public', 2, 'public', 5, 5)
  returning id into v_public;

  insert into ingredient_groups (recipe_id, name) values (v_private, 'Main')
  returning id into v_ig_priv;
  insert into ingredients (group_id, name, quantity, unit)
  values (v_ig_priv, 'salt', 1, 'tsp');
  insert into step_groups (recipe_id, name) values (v_private, 'Method')
  returning id into v_sg_priv;
  insert into steps (group_id, step_order, text) values (v_sg_priv, 0, 'Stir.');

  insert into ingredient_groups (recipe_id, name) values (v_public, 'Main')
  returning id into v_ig_pub;
  insert into ingredients (group_id, name, quantity, unit)
  values (v_ig_pub, 'sugar', 1, 'tsp');

  insert into recipe_shares (recipe_id, shared_with_user_id, permission)
  values (v_private, v_sharee, 'view');

  -- A view logged by the sharee, so B24 (the owner can read the log) and C15
  -- (the person who made the view cannot) both have a row to be right about.
  insert into recipe_views (recipe_id, user_id) values (v_private, v_sharee);

  -- A like on the *unshared* private recipe by the stranger, written here rather
  -- than through RLS: D18 proves they cannot create one, D19 proves the policy
  -- still lets them remove one they already have. Splitting those two is the
  -- whole reason the read test lives in `with check` and not in `using`.
  insert into recipe_likes (user_id, recipe_id) values (v_other, v_private2);

  insert into tags (name) values ('bl7-in-use') returning id into v_tag;
  insert into recipe_tags (recipe_id, tag_id) values (v_public, v_tag);
  insert into tags (name) values ('bl7-orphan') returning id into v_orphan;

  -- ==========================================================================
  -- A. anon — already proven in Phase 26; kept as a regression guard, and
  --    because a signed-in result only means something next to a signed-out one.
  -- ==========================================================================
  execute 'set local role anon';
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);

  select count(*) into n from recipes where id = v_public;
  v_log := v_log || format(E'%s\tA1  anon · select a public recipe\t%s row', n = 1, n);

  select count(*) into n from recipes where id = v_private;
  v_log := v_log || format(E'%s\tA2  anon · select a private recipe\t%s row', n = 0, n);

  select count(*) into n from ingredient_groups where recipe_id = v_private;
  v_log := v_log || format(E'%s\tA3  anon · select a private recipe''s content\t%s row', n = 0, n);

  select err into v_err from public.rls_matrix_do(format(
    'insert into recipes (owner_id, title, servings) values (%L, ''x'', 1)', v_owner));
  v_log := v_log || format(E'%s\tA4  anon · insert a recipe must FAIL\t%s', v_err = '42501', coalesce(v_err, 'no error'));

  select err into v_err from public.rls_matrix_do(format('select fork_recipe(%L)', v_public));
  v_log := v_log || format(E'%s\tA5  anon · fork_recipe must FAIL\t%s', v_err = '42501', coalesce(v_err, 'no error'));

  select err into v_err from public.rls_matrix_do('insert into tags (name) values (''bl7-anon'')');
  v_log := v_log || format(E'%s\tA6  anon · insert a tag must FAIL\t%s', v_err = '42501', coalesce(v_err, 'no error'));

  -- ==========================================================================
  -- B. owner — the row's own user. Reads, the B053 create shape, the writes
  --    that must work, and the columns that must not.
  -- ==========================================================================
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner)::text, true);

  select count(*) into n from recipes where id = v_private;
  v_log := v_log || format(E'%s\tB1  owner · select own private recipe\t%s row', n = 1, n);

  select count(*) into n from recipes where id = v_public;
  v_log := v_log || format(E'%s\tB2  owner · select own public recipe\t%s row', n = 1, n);

  select count(*) into n from ingredient_groups where recipe_id = v_private;
  v_log := v_log || format(E'%s\tB3  owner · select own private content\t%s row', n = 1, n);

  -- B053, longhand and deliberately not through the helper: BOTH failure modes
  -- have to be distinguishable. An error means the SELECT policy rejected the
  -- new row outright; a null id with no error means it silently filtered the
  -- RETURNING clause, which is what `.insert().select().single()` sends.
  begin
    v_new := null;
    insert into recipes (owner_id, title, servings, visibility)
    values (v_owner, 'BL-7 owner create', 1, 'private')
    returning id into v_new;
    v_err := null;
  exception when others then
    v_err := sqlstate;
  end;
  v_log := v_log || format(E'%s\tB4  owner · INSERT … RETURNING gives the row back (B053)\t%s',
    v_err is null and v_new is not null,
    case when v_err is not null then v_err
         when v_new is null then 'no error, but RETURNING was empty'
         else 'ok' end);

  select err, rows into v_err, v_n from public.rls_matrix_do(format(
    'insert into recipes (owner_id, title, servings, visibility) values (%L, ''BL-7 owner public'', 1, ''public'')', v_owner));
  v_log := v_log || format(E'%s\tB5  owner · insert a public recipe\t%s', v_err is null and v_n = 1, coalesce(v_err, v_n || ' row'));

  select err into v_err from public.rls_matrix_do(format(
    'insert into recipes (owner_id, title, servings) values (%L, ''BL-7 forged owner'', 1)', v_other));
  v_log := v_log || format(E'%s\tB6  owner · insert owned by someone else must FAIL\t%s', v_err = '42501', coalesce(v_err, 'no error'));

  select err, rows into v_err, v_n from public.rls_matrix_do(format(
    'update recipes set title = ''BL-7 renamed'' where id = %L', v_private));
  v_log := v_log || format(E'%s\tB7  owner · update own recipe\t%s', v_err is null and v_n = 1, coalesce(v_err, v_n || ' row'));

  -- B050 / OPT-S1: RLS filters rows, never columns. These two are the column
  -- grants doing the work no policy can do.
  select err into v_err from public.rls_matrix_do(format(
    'update recipes set like_count = 9999 where id = %L', v_private));
  v_log := v_log || format(E'%s\tB8  owner · update own like_count must FAIL (B050)\t%s', v_err = '42501', coalesce(v_err, 'no error'));

  select err into v_err from public.rls_matrix_do(format(
    'update recipes set owner_id = %L where id = %L', v_other, v_private));
  v_log := v_log || format(E'%s\tB9  owner · reassign own recipe must FAIL\t%s', v_err = '42501', coalesce(v_err, 'no error'));

  -- The positive half of the same rule, for Phase 28's `nutrition` (a
  -- client-writable column). `save_recipe` is `security definer`, so a missing
  -- grant would NOT show up on the app's save path — a direct PATCH is the only
  -- thing that fails, and nothing in the app issues one for recipes yet. This
  -- check is therefore the only proof the grant exists.
  select err, rows into v_err, v_n from public.rls_matrix_do(format(
    'update recipes set nutrition = ''{"calories":10}''::jsonb where id = %L', v_private));
  v_log := v_log || format(E'%s\tB9a owner · update own nutrition (column grant)\t%s', v_err is null and v_n = 1, coalesce(v_err, v_n || ' row'));

  select err into v_err from public.rls_matrix_do(format(
    'update profiles set chef_score = 9999 where id = %L', v_owner));
  v_log := v_log || format(E'%s\tB10 owner · update own chef_score must FAIL (B050)\t%s', v_err = '42501', coalesce(v_err, 'no error'));

  select err, rows into v_err, v_n from public.rls_matrix_do(format(
    'update profiles set display_name = ''BL-7 renamed'' where id = %L', v_owner));
  v_log := v_log || format(E'%s\tB11 owner · update own display_name\t%s', v_err is null and v_n = 1, coalesce(v_err, v_n || ' row'));

  select err, rows into v_err, v_n from public.rls_matrix_do(format(
    'insert into ingredient_groups (recipe_id, name) values (%L, ''BL-7 group'')', v_private));
  v_log := v_log || format(E'%s\tB12 owner · insert own ingredient_group\t%s', v_err is null and v_n = 1, coalesce(v_err, v_n || ' row'));

  select err, rows into v_err, v_n from public.rls_matrix_do(format(
    'insert into ingredients (group_id, name) values (%L, ''BL-7 ingredient'')', v_ig_priv));
  v_log := v_log || format(E'%s\tB13 owner · insert own ingredient\t%s', v_err is null and v_n = 1, coalesce(v_err, v_n || ' row'));

  select err, rows into v_err, v_n from public.rls_matrix_do(format(
    'insert into steps (group_id, step_order, text) values (%L, 1, ''BL-7 step'')', v_sg_priv));
  v_log := v_log || format(E'%s\tB14 owner · insert own step\t%s', v_err is null and v_n = 1, coalesce(v_err, v_n || ' row'));

  select err, rows into v_err, v_n from public.rls_matrix_do(format(
    'insert into recipe_versions (recipe_id, version_number, author_id, content_snapshot) '
    'values (%L, 99, %L, ''{}''::jsonb)', v_private, v_owner));
  v_log := v_log || format(E'%s\tB15 owner · insert own recipe_version\t%s', v_err is null and v_n = 1, coalesce(v_err, v_n || ' row'));

  -- `ratings_write` forbids rating your own recipe in the policy, not in a
  -- hidden button.
  select err into v_err from public.rls_matrix_do(format(
    'insert into recipe_ratings (user_id, recipe_id, rating) values (%L, %L, 5.0)', v_owner, v_public));
  v_log := v_log || format(E'%s\tB16 owner · rate own recipe must FAIL\t%s', v_err = '42501', coalesce(v_err, 'no error'));

  -- Gotcha 3: PostgREST exposes every function in `public` as an RPC, so the
  -- mutating helpers are only closed by the EXECUTE revokes.
  select err into v_err from public.rls_matrix_do(format('select recompute_chef_stats(%L)', v_other));
  v_log := v_log || format(E'%s\tB17 owner · recompute_chef_stats RPC must FAIL\t%s', v_err = '42501', coalesce(v_err, 'no error'));

  select err into v_err from public.rls_matrix_do('select recompute_all_chef_stats()');
  v_log := v_log || format(E'%s\tB18 owner · recompute_all_chef_stats RPC must FAIL\t%s', v_err = '42501', coalesce(v_err, 'no error'));

  select err into v_err from public.rls_matrix_do(format('select refresh_search_tsv(array[%L::uuid])', v_public));
  v_log := v_log || format(E'%s\tB19 owner · refresh_search_tsv RPC must FAIL\t%s', v_err = '42501', coalesce(v_err, 'no error'));

  select err into v_err from public.rls_matrix_do(format('select bump_count(%L, ''like_count'', 100)', v_public));
  v_log := v_log || format(E'%s\tB20 owner · bump_count RPC must FAIL\t%s', v_err = '42501', coalesce(v_err, 'no error'));

  select err into v_err from public.rls_matrix_do(format('select recipe_snapshot(%L)', v_public));
  v_log := v_log || format(E'%s\tB21 owner · recipe_snapshot RPC must FAIL\t%s', v_err = '42501', coalesce(v_err, 'no error'));

  -- The path the app actually takes (OPT-A1): create and update are one
  -- `security definer` RPC, so this is what a real save proves.
  begin
    v_saved := save_recipe(null,
      '{"title":"BL-7 via save_recipe","servings":2,"visibility":"private",'
      '"nutrition":{"calories":210,"protein_g":9.5}}'::jsonb,
      '[{"name":"Main","ingredients":[{"name":"salt","quantity":1,"unit":"tsp"}]}]'::jsonb,
      '[{"name":"Method","steps":[{"text":"Stir."}]}]'::jsonb,
      'BL-7');
    v_err := null;
  exception when others then
    v_err := sqlstate; v_saved := null;
  end;
  v_log := v_log || format(E'%s\tB22 owner · save_recipe(null, …) creates\t%s',
    v_err is null and v_saved is not null, coalesce(v_err, 'ok'));

  -- Deliberately NOT the shared private fixture: `save_recipe` replaces both
  -- group trees wholesale (Gotcha 11), so pointing this at `v_private` would
  -- empty the content section C2 goes on to read and turn a green run red for
  -- the wrong reason.
  -- The insert branch's `nutrition` extraction, read back. `->` not `->>`, so a
  -- wrong arrow is a runtime error at B22 and this line never gets to disagree.
  select nutrition into v_json from recipes where id = v_saved;
  v_log := v_log || format(E'%s\tB22a owner · save_recipe stores the nutrition object\t%s',
    v_json is not null and (v_json->>'calories')::numeric = 210,
    coalesce(v_json::text, 'null'));

  select err into v_err from public.rls_matrix_do(format(
    'select save_recipe(%L, ''{"title":"BL-7 saved again"}''::jsonb, ''[]''::jsonb, ''[]''::jsonb, ''BL-7'')', v_saved));
  v_log := v_log || format(E'%s\tB23 owner · save_recipe(own id, …) updates\t%s', v_err is null, coalesce(v_err, 'ok'));

  -- JSON null is not SQL NULL. `_writablePayload` always sends the key, so a
  -- recipe with no nutrition arrives as `"nutrition": null` — which `->` returns
  -- as `'null'::jsonb`, a value that fails `recipes_nutrition_is_object`. The
  -- `nullif` in both save branches is what turns it into a real NULL; without it
  -- this update raises 23514 instead of clearing the column.
  select err into v_err from public.rls_matrix_do(format(
    'select save_recipe(%L, ''{"title":"BL-7 cleared","nutrition":null}''::jsonb, ''[]''::jsonb, ''[]''::jsonb, ''BL-7'')', v_saved));
  select nutrition into v_json from recipes where id = v_saved;
  v_log := v_log || format(E'%s\tB23a owner · save_recipe JSON-null nutrition lands as SQL NULL\t%s',
    v_err is null and v_json is null, coalesce(v_err, coalesce(v_json::text, 'null')));

  -- `views_select` is `owns_recipe`, so only the owner reads the log — the
  -- fixture row was written by the sharee (see C15, which must see nothing).
  select count(*) into n from recipe_views where recipe_id = v_private;
  v_log := v_log || format(E'%s\tB24 owner · select own recipe''s view log\t%s row', n = 1, n);

  select err, rows into v_err, v_n from public.rls_matrix_do(format(
    'delete from recipes where id = %L', v_new));
  v_log := v_log || format(E'%s\tB25 owner · delete own recipe\t%s', v_err is null and v_n = 1, coalesce(v_err, v_n || ' row'));

  -- ==========================================================================
  -- C. shared-with — a `recipe_shares` row grants READ and nothing else.
  --    `share_permission` has an 'edit' value, but it is reserved and unused;
  --    every write below must therefore be refused or match zero rows.
  -- ==========================================================================
  perform set_config('request.jwt.claims', json_build_object('sub', v_sharee)::text, true);

  select count(*) into n from recipes where id = v_private;
  v_log := v_log || format(E'%s\tC1  shared · select the shared private recipe\t%s row', n = 1, n);

  select count(*) into n from ingredient_groups where recipe_id = v_private;
  v_log := v_log || format(E'%s\tC2  shared · select its content\t%s row', n >= 1, n);

  select count(*) into n from recipe_shares where recipe_id = v_private;
  v_log := v_log || format(E'%s\tC3  shared · select own share row\t%s row', n = 1, n);

  select count(*) into n from recipe_versions where recipe_id = v_private;
  v_log := v_log || format(E'%s\tC4  shared · select its version history\t%s row', n >= 1, n);

  -- The silent one (Gotcha 2): no error, zero rows. A client that does not add
  -- `.select()` reads this as a successful save.
  select err, rows into v_err, v_n from public.rls_matrix_do(format(
    'update recipes set title = ''BL-7 hijacked'' where id = %L', v_private));
  v_log := v_log || format(E'%s\tC5  shared · update it matches 0 rows (Gotcha 2)\t%s', v_err is null and v_n = 0, coalesce(v_err, v_n || ' row'));

  select err, rows into v_err, v_n from public.rls_matrix_do(format(
    'delete from recipes where id = %L', v_private));
  v_log := v_log || format(E'%s\tC6  shared · delete it matches 0 rows (Gotcha 2)\t%s', v_err is null and v_n = 0, coalesce(v_err, v_n || ' row'));

  select err into v_err from public.rls_matrix_do(format(
    'insert into ingredient_groups (recipe_id, name) values (%L, ''BL-7 hijack'')', v_private));
  v_log := v_log || format(E'%s\tC7  shared · insert content into it must FAIL\t%s', v_err = '42501', coalesce(v_err, 'no error'));

  select err, rows into v_err, v_n from public.rls_matrix_do(format(
    'delete from ingredient_groups where recipe_id = %L', v_private));
  v_log := v_log || format(E'%s\tC8  shared · delete its content matches 0 rows\t%s', v_err is null and v_n = 0, coalesce(v_err, v_n || ' row'));

  select err into v_err from public.rls_matrix_do(format(
    'insert into recipe_versions (recipe_id, version_number, author_id, content_snapshot) '
    'values (%L, 98, %L, ''{}''::jsonb)', v_private, v_sharee));
  v_log := v_log || format(E'%s\tC9  shared · append a version must FAIL\t%s', v_err = '42501', coalesce(v_err, 'no error'));

  select err into v_err from public.rls_matrix_do(format(
    'select save_recipe(%L, ''{"title":"BL-7 hijacked"}''::jsonb, ''[]''::jsonb, ''[]''::jsonb, ''x'')', v_private));
  v_log := v_log || format(E'%s\tC10 shared · save_recipe on it must FAIL\t%s', v_err = '42501', coalesce(v_err, 'no error'));

  select err into v_err from public.rls_matrix_do(format(
    'insert into recipe_shares (recipe_id, shared_with_user_id) values (%L, %L)', v_private, v_other));
  v_log := v_log || format(E'%s\tC11 shared · re-share it must FAIL\t%s', v_err = '42501', coalesce(v_err, 'no error'));

  -- Reading is what the share IS, so these two must work.
  select err into v_err from public.rls_matrix_do(format(
    'insert into recipe_ratings (user_id, recipe_id, rating) values (%L, %L, 4.5)', v_sharee, v_private));
  v_log := v_log || format(E'%s\tC12 shared · rate it\t%s', v_err is null, coalesce(v_err, 'ok'));

  begin
    v_fork := fork_recipe(v_private);
    v_err := null;
  exception when others then
    v_err := sqlstate; v_fork := null;
  end;
  v_log := v_log || format(E'%s\tC13 shared · fork it\t%s', v_err is null and v_fork is not null, coalesce(v_err, 'ok'));

  select count(*) into n from recipes
  where id = v_fork and owner_id = v_sharee and visibility = 'private'
    and forked_from_recipe_id = v_private;
  v_log := v_log || format(E'%s\tC14 shared · the fork is theirs, private, linked\t%s row', n = 1, n);

  select count(*) into n from recipe_views where recipe_id = v_private;
  v_log := v_log || format(E'%s\tC15 shared · cannot read its view log\t%s row', n = 0, n);

  select err into v_err from public.rls_matrix_do(format(
    'insert into recipe_likes (user_id, recipe_id) values (%L, %L)', v_sharee, v_private));
  v_log := v_log || format(E'%s\tC16 shared · like it\t%s', v_err is null, coalesce(v_err, 'ok'));

  select err into v_err from public.rls_matrix_do(format(
    'insert into recipe_saves (user_id, recipe_id) values (%L, %L)', v_sharee, v_private));
  v_log := v_log || format(E'%s\tC17 shared · save it\t%s', v_err is null, coalesce(v_err, 'ok'));

  -- ==========================================================================
  -- D. unrelated signed-in user — the everyday case, and the one where a denial
  --    that reports success is most likely to go unnoticed.
  -- ==========================================================================
  perform set_config('request.jwt.claims', json_build_object('sub', v_other)::text, true);

  select count(*) into n from recipes where id = v_private;
  v_log := v_log || format(E'%s\tD1  stranger · select a private recipe\t%s row', n = 0, n);

  select count(*) into n from recipes where id = v_public;
  v_log := v_log || format(E'%s\tD2  stranger · select a public recipe\t%s row', n = 1, n);

  select count(*) into n from ingredient_groups where recipe_id = v_private;
  v_log := v_log || format(E'%s\tD3  stranger · select private content\t%s row', n = 0, n);

  select count(*) into n from ingredient_groups where recipe_id = v_public;
  v_log := v_log || format(E'%s\tD4  stranger · select public content\t%s row', n >= 1, n);

  select count(*) into n from recipe_versions where recipe_id = v_private;
  v_log := v_log || format(E'%s\tD5  stranger · select private version history\t%s row', n = 0, n);

  select count(*) into n from recipe_shares where recipe_id = v_private;
  v_log := v_log || format(E'%s\tD6  stranger · select who a recipe is shared with\t%s row', n = 0, n);

  select err, rows into v_err, v_n from public.rls_matrix_do(format(
    'update recipes set title = ''BL-7 hijacked'' where id = %L', v_private));
  v_log := v_log || format(E'%s\tD7  stranger · update a private recipe matches 0 rows\t%s', v_err is null and v_n = 0, coalesce(v_err, v_n || ' row'));

  select err, rows into v_err, v_n from public.rls_matrix_do(format(
    'update recipes set title = ''BL-7 hijacked'' where id = %L', v_public));
  v_log := v_log || format(E'%s\tD8  stranger · update a public recipe matches 0 rows\t%s', v_err is null and v_n = 0, coalesce(v_err, v_n || ' row'));

  select err, rows into v_err, v_n from public.rls_matrix_do(format(
    'delete from recipes where id = %L', v_private));
  v_log := v_log || format(E'%s\tD9  stranger · delete a private recipe matches 0 rows\t%s', v_err is null and v_n = 0, coalesce(v_err, v_n || ' row'));

  select err, rows into v_err, v_n from public.rls_matrix_do(format(
    'delete from recipes where id = %L', v_public));
  v_log := v_log || format(E'%s\tD10 stranger · delete a public recipe matches 0 rows\t%s', v_err is null and v_n = 0, coalesce(v_err, v_n || ' row'));

  select err, rows into v_err, v_n from public.rls_matrix_do(format(
    'update profiles set display_name = ''BL-7 hijacked'' where id = %L', v_owner));
  v_log := v_log || format(E'%s\tD11 stranger · update another profile matches 0 rows\t%s', v_err is null and v_n = 0, coalesce(v_err, v_n || ' row'));

  -- Pinned to P0001 *and* to the absence of a fork row, not merely to "something
  -- raised". `fork_recipe`'s refusal is a bare `raise exception`, and OPT-S6's
  -- comment on that function records that an unauthorized call used to get as far
  -- as the INSERT and die on `owner_id`'s not-null constraint — an accident of
  -- the schema, not a guard. A check that accepts any SQLSTATE cannot tell the
  -- guard firing from the guard being gone.
  select err into v_err from public.rls_matrix_do(format('select fork_recipe(%L)', v_private));
  -- Scoped to forks owned by the STRANGER: C13 legitimately forked the same
  -- recipe as the sharee, and counting that one would make this depend on RLS
  -- hiding it rather than on the fork never happening.
  select count(*) into n
  from recipes where forked_from_recipe_id = v_private and owner_id = v_other;
  v_log := v_log || format(E'%s\tD12 stranger · fork an unreadable recipe must FAIL\t%s',
    v_err = 'P0001' and n = 0, coalesce(v_err, 'no error') || ', ' || n || ' fork(s)');

  begin
    v_fork := fork_recipe(v_public);
    v_err := null;
  exception when others then
    v_err := sqlstate; v_fork := null;
  end;
  v_log := v_log || format(E'%s\tD13 stranger · fork a public recipe\t%s', v_err is null and v_fork is not null, coalesce(v_err, 'ok'));

  select err into v_err from public.rls_matrix_do(format(
    'insert into recipe_ratings (user_id, recipe_id, rating) values (%L, %L, 4.0)', v_other, v_public));
  v_log := v_log || format(E'%s\tD14 stranger · rate a public recipe\t%s', v_err is null, coalesce(v_err, 'ok'));

  select err into v_err from public.rls_matrix_do(format(
    'insert into recipe_ratings (user_id, recipe_id, rating) values (%L, %L, 1.0)', v_other, v_private));
  v_log := v_log || format(E'%s\tD15 stranger · rate an unreadable recipe must FAIL\t%s', v_err = '42501', coalesce(v_err, 'no error'));

  select err into v_err from public.rls_matrix_do(format(
    'insert into recipe_ratings (user_id, recipe_id, rating) values (%L, %L, 1.0)', v_owner, v_public));
  v_log := v_log || format(E'%s\tD16 stranger · rate AS another user must FAIL\t%s', v_err = '42501', coalesce(v_err, 'no error'));

  select err into v_err from public.rls_matrix_do(format(
    'insert into recipe_likes (user_id, recipe_id) values (%L, %L)', v_owner, v_public));
  v_log := v_log || format(E'%s\tD17 stranger · like AS another user must FAIL\t%s', v_err = '42501', coalesce(v_err, 'no error'));

  select err into v_err from public.rls_matrix_do(format(
    'insert into recipe_likes (user_id, recipe_id) values (%L, %L)', v_other, v_private));
  v_log := v_log || format(E'%s\tD18 stranger · like an unreadable recipe must FAIL\t%s', v_err = '42501', coalesce(v_err, 'no error'));

  -- The other half of the same rule: `using` stays `user_id = auth.uid()` alone,
  -- so a like that already exists can always be removed. Otherwise an owner
  -- flipping a recipe to private would strand every liker's row.
  select err, rows into v_err, v_n from public.rls_matrix_do(format(
    'delete from recipe_likes where user_id = %L and recipe_id = %L', v_other, v_private2));
  v_log := v_log || format(E'%s\tD19 stranger · unlike an unreadable recipe still works\t%s', v_err is null and v_n = 1, coalesce(v_err, v_n || ' row'));

  select err into v_err from public.rls_matrix_do(format(
    'insert into recipe_saves (user_id, recipe_id) values (%L, %L)', v_other, v_private));
  v_log := v_log || format(E'%s\tD20 stranger · save an unreadable recipe must FAIL\t%s', v_err = '42501', coalesce(v_err, 'no error'));

  -- B012: `views_insert` pins user_id to auth.uid() precisely so views cannot be
  -- attributed to someone else — the counter they move is public.
  select err into v_err from public.rls_matrix_do(format(
    'insert into recipe_views (recipe_id, user_id) values (%L, %L)', v_public, v_owner));
  v_log := v_log || format(E'%s\tD21 stranger · log a view AS another user must FAIL (B012)\t%s', v_err = '42501', coalesce(v_err, 'no error'));

  select err into v_err from public.rls_matrix_do(format(
    'insert into recipe_views (recipe_id, user_id) values (%L, %L)', v_private, v_other));
  v_log := v_log || format(E'%s\tD22 stranger · log a view of an unreadable recipe must FAIL\t%s', v_err = '42501', coalesce(v_err, 'no error'));

  select err into v_err from public.rls_matrix_do(format(
    'insert into recipe_views (recipe_id, user_id) values (%L, %L)', v_public, v_other));
  v_log := v_log || format(E'%s\tD23 stranger · log own view of a public recipe\t%s', v_err is null, coalesce(v_err, 'ok'));

  -- `saves_select` is `user_id = auth.uid()` — unlike likes and ratings, a save
  -- is private to the person who made it. The sharee made one at C17.
  select count(*) into n from recipe_saves where user_id <> v_other;
  v_log := v_log || format(E'%s\tD24 stranger · sees nobody else''s saves\t%s row', n = 0, n);

  select err into v_err from public.rls_matrix_do(format(
    'insert into recipe_suggestions (recipe_id, author_id, summary) values (%L, %L, ''BL-7'')', v_public, v_owner));
  v_log := v_log || format(E'%s\tD25 stranger · suggest AS another user must FAIL\t%s', v_err = '42501', coalesce(v_err, 'no error'));

  -- Tags are a shared namespace on purpose (OPT-A6): any signed-in user may add
  -- one, and may remove one only while nothing references it.
  select err into v_err from public.rls_matrix_do('insert into tags (name) values (''bl7-stranger'')');
  v_log := v_log || format(E'%s\tD26 stranger · insert a tag\t%s', v_err is null, coalesce(v_err, 'ok'));

  select err, rows into v_err, v_n from public.rls_matrix_do(format(
    'delete from tags where id = %L', v_tag));
  v_log := v_log || format(E'%s\tD27 stranger · delete a tag in use matches 0 rows\t%s', v_err is null and v_n = 0, coalesce(v_err, v_n || ' row'));

  select err, rows into v_err, v_n from public.rls_matrix_do(format(
    'delete from tags where id = %L', v_orphan));
  v_log := v_log || format(E'%s\tD28 stranger · delete an orphan tag\t%s', v_err is null and v_n = 1, coalesce(v_err, v_n || ' row'));

  -- ==========================================================================
  -- Report
  -- ==========================================================================
  execute 'reset role';

  raise notice '';
  raise notice '=== BL-7 RLS acceptance matrix (as authenticated) ===';
  -- `%s` renders a boolean through its *output* function, so the first field is
  -- `t`/`f`, not `true`/`false` — cast rather than compare, so it reads the same
  -- either way. A NULL verdict renders as the empty string and is a FAIL, not a
  -- cast error: `v_err = '42501'` is NULL whenever the statement did not raise,
  -- which is exactly the case a "must FAIL" check exists to catch.
  foreach s in array v_log loop
    -- `rpad` TRUNCATES when the label is longer than the width, and on a FAIL
    -- line the tail is the bug id you would grep for. Pad to at least 56, never
    -- cut.
    if coalesce(nullif(split_part(s, E'\t', 1), '')::boolean, false) then
      v_pass := v_pass + 1;
      raise notice 'PASS  %  [%]',
        rpad(split_part(s, E'\t', 2), greatest(56, length(split_part(s, E'\t', 2)))),
        split_part(s, E'\t', 3);
    else
      v_fail := v_fail + 1;
      raise warning 'FAIL  %  [%]',
        rpad(split_part(s, E'\t', 2), greatest(56, length(split_part(s, E'\t', 2)))),
        split_part(s, E'\t', 3);
    end if;
  end loop;
  raise notice '--- % passed, % failed, % total ---', v_pass, v_fail, v_pass + v_fail;

  if v_fail > 0 then
    raise exception 'BL-7: % of % RLS checks FAILED — see the warnings above',
      v_fail, v_pass + v_fail;
  end if;
end
$rls$;

drop function public.rls_matrix_do(text);

-- Nothing this file wrote is meant to survive it.
rollback;
