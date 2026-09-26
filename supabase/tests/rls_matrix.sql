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
  v_lineage  uuid;

  -- Phase 23 (the windowed board). Every expected value F12-F19 compares
  -- against is COMPUTED from the database rather than written as a literal:
  -- by the time §F runs, sections A-E have left their own likes and views on
  -- these same fixtures (A7's anonymous view, C16's like, D23's view), so an
  -- absolute count would be a check that fails for a reason having nothing to
  -- do with what it claims to prove. That is the F7 lesson, applied to
  -- engagement rows instead of recipes.
  v_since    timestamptz;
  v_when     timestamptz;
  v_raw      bigint;
  v_pairs    bigint;
  v_pub      bigint;
  v_all      bigint;

  -- B092 (F20/F21). Two public recipes of the owner's that tie on likes and
  -- differ only in recent distinct viewers — created late, in §F, so nothing
  -- in §A-§E has to know they exist.
  v_trend_read   uuid;
  v_trend_unread uuid;
  v_trend_first  uuid;
  v_trend_anon   uuid[];
  v_trend_owner  uuid[];

  -- Phase 35b (§G). An imported profile has no `auth.users` row behind it at
  -- all, which is the one shape sections A-F structurally cannot produce: every
  -- fixture above starts from a signup.
  v_imported     uuid;
  v_imp_recipe   uuid;

  -- Phase 35c (§H). A second imported fixture, with provenance on it — §G's is
  -- about identity, this one is about where a recipe came from.
  v_publisher    uuid;
  v_imp2         uuid;
  v_imp_recipe2  uuid;
  v_merge_recipe uuid;
  v_entity       uuid;
  v_claim        uuid;
  v_me           uuid;
  v_merged       uuid;
  v_claimed_link uuid;
  v_err2         text;
  s2             text;

  -- F22-F24 (the recompute guard): a row's physical address before and after.
  v_ctid1        text;
  v_ctid2        text;
  v_likes1       bigint;
  v_likes2       bigint;

  -- G29-G34 (the pending-claim cap). Sized from `profile_claim_pending_cap()`
  -- rather than a literal, so moving the number does not break the matrix.
  v_cap          int;
  v_cap_profiles uuid[];
  v_msg          text;

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

  -- **`edit`, not `view`** (32a3). `share_permission` has an `edit` value that
  -- every policy ignores — `recipes_update` is `owns_recipe`, full stop — and
  -- the share dialog ships that segment disabled behind `notYetTooltip`
  -- (OPT-S5) because of it. Sharing at the *stronger* reserved level costs
  -- nothing and upgrades every refusal in section C from "a viewer cannot
  -- write" to "not even an `edit` share is an update right", which is the
  -- claim that would quietly become false the day someone wires the segment up.
  insert into recipe_shares (recipe_id, shared_with_user_id, permission)
  values (v_private, v_sharee, 'edit');

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

  -- Food registry fixture (Phase 29a). The matrix must not depend on
  -- nutrition_foods.sql having been applied — it brings its own row, and the
  -- rollback takes it away again.
  insert into food (id, display_name, calories) values ('bl7-food', 'BL-7 fixture food', 100);
  insert into food_alias (alias, food_id) values ('bl7 fixture food', 'bl7-food');
  -- A private mass unit for B22c's known-grams arithmetic (29c): 1 bl7-gram
  -- = 1 g, a spelling the real registry can never carry.
  insert into food_unit (spelling, unit_key, class, factor)
  values ('bl7-gram', 'bl7-gram', 'mass', 1);

  -- S1 (32a4): the bucket contract. **Configuration, not enforcement** — Storage
  -- applies these two columns at its own API edge, which no SQL here can reach,
  -- and RLS never sees the bytes. But the config *is* a plain row, and it is the
  -- part that realistically drifts: a dashboard edit on the hosted project, or a
  -- change here that remembers one bucket and forgets the other. Read as
  -- `postgres`, before the role switches, because `storage.buckets` is not
  -- readable by the API roles.
  select count(*) into n from storage.buckets
   where id in ('recipe-images', 'avatars')
     and file_size_limit = 5242880
     and allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];
  v_log := v_log || format(E'%s\tS1  config · both buckets carry the 32a4 size + MIME limits\t%s of 2', n = 2, n);

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

  -- A7 (32a3): the one write `anon` is *supposed* to have. `anon` holds
  -- `insert on recipe_views` deliberately — a signed-out visitor reading a
  -- public recipe logs a view — and B012's whole design (the counter skips null
  -- `user_id` rows) exists because of it. Pinning the permission the same way
  -- the denials are pinned makes tightening it a decision somebody takes rather
  -- than a line somebody deletes, and pairs with A8: the row lands, the counter
  -- does not move.
  select view_count into n from recipes where id = v_public;
  select err into v_err from public.rls_matrix_do(format(
    'insert into recipe_views (recipe_id, user_id) values (%L, null)', v_public));
  v_log := v_log || format(E'%s\tA7  anon · log an anonymous view of a public recipe\t%s', v_err is null, coalesce(v_err, 'ok'));

  -- A delta, not an absolute: other checks in this file log views too, and a
  -- test that fails because a *different* check ran first proves nothing about
  -- the trigger it names.
  select view_count into v_n from recipes where id = v_public;
  v_log := v_log || format(E'%s\tA8  anon · …and it moves no counter (B012)\t%s',
    v_n = n, format('view_count %s -> %s', n, v_n));

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

  -- B082: fork lineage is server-owned for the same reason a counter is — it is
  -- a claim about someone else's recipe, and `recipes_most_forked` ranks on it.
  -- The column grants are the first of two locks; `save_recipe` is the second
  -- (B23b/B23c), and it needs to be, because a `security definer` function does
  -- not see these grants at all.
  select err into v_err from public.rls_matrix_do(format(
    'update recipes set forked_from_recipe_id = %L where id = %L', v_public, v_private));
  v_log := v_log || format(E'%s\tB9b owner · forge fork lineage by UPDATE must FAIL (B082)\t%s', v_err = '42501', coalesce(v_err, 'no error'));

  select err into v_err from public.rls_matrix_do(format(
    'insert into recipes (owner_id, title, servings, forked_from_recipe_id) '
    'values (%L, ''BL-7 forged fork'', 1, %L)', v_owner, v_public));
  v_log := v_log || format(E'%s\tB9c owner · forge fork lineage by INSERT must FAIL (B082)\t%s', v_err = '42501', coalesce(v_err, 'no error'));

  -- 32a2: the value bounds. A column grant says the owner may write `servings`;
  -- nothing said what a legal `servings` is, so `0` was storable over PostgREST
  -- and every per-serving number downstream divided by it. `23514` is a check
  -- constraint — a different failure from `42501`, and asserting the exact code
  -- is what distinguishes "the bound rejected it" from "the grant did".
  select err into v_err from public.rls_matrix_do(format(
    'update recipes set servings = 0 where id = %L', v_private));
  v_log := v_log || format(E'%s\tB9d owner · servings = 0 must FAIL (32a2)\t%s', v_err = '23514', coalesce(v_err, 'no error'));

  select err into v_err from public.rls_matrix_do(format(
    'update recipes set prep_minutes = -5 where id = %L', v_private));
  v_log := v_log || format(E'%s\tB9e owner · negative prep_minutes must FAIL (32a2)\t%s', v_err = '23514', coalesce(v_err, 'no error'));

  select err into v_err from public.rls_matrix_do(format(
    'update recipes set title = repeat(''x'', 201) where id = %L', v_private));
  v_log := v_log || format(E'%s\tB9f owner · a 201-char title must FAIL (32a2)\t%s', v_err = '23514', coalesce(v_err, 'no error'));

  -- Both length constraints are multi-part predicates, and a check that
  -- exercises one conjunct proves nothing about its siblings — dropping the
  -- constraint turns the tested half red either way. So each conjunct gets its
  -- own line; `attribution` also stands in for the four nullable ones, whose
  -- shared shape is the `is null or` guard most likely to be inverted later.
  select err into v_err from public.rls_matrix_do(format(
    'update recipes set description = repeat(''x'', 10001) where id = %L', v_private));
  v_log := v_log || format(E'%s\tB9g owner · a 10001-char description must FAIL (32a2)\t%s', v_err = '23514', coalesce(v_err, 'no error'));

  select err into v_err from public.rls_matrix_do(format(
    'update recipes set attribution = repeat(''x'', 2001) where id = %L', v_private));
  v_log := v_log || format(E'%s\tB9h owner · a 2001-char attribution must FAIL (32a2)\t%s', v_err = '23514', coalesce(v_err, 'no error'));

  select err, rows into v_err, v_n from public.rls_matrix_do(format(
    'update recipes set attribution = null where id = %L', v_private));
  v_log := v_log || format(E'%s\tB9i owner · a NULL attribution is still legal\t%s', v_err is null and v_n = 1, coalesce(v_err, v_n || ' row'));

  -- The quantity bound is the one with a wrong-number consequence rather than a
  -- missing-value one: B076 showed a negative quantity *subtracting* from an
  -- estimated label. The estimator still skips it defensively; this makes it
  -- unstorable.
  select err into v_err from public.rls_matrix_do(format(
    'insert into ingredients (group_id, name, quantity) values (%L, ''BL-7 negative'', -2)', v_ig_priv));
  v_log := v_log || format(E'%s\tB13a owner · a negative ingredient quantity must FAIL (32a2)\t%s', v_err = '23514', coalesce(v_err, 'no error'));

  select err, rows into v_err, v_n from public.rls_matrix_do(format(
    'insert into ingredients (group_id, name, quantity) values (%L, ''BL-7 to taste'', null)', v_ig_priv));
  v_log := v_log || format(E'%s\tB13b owner · a NULL quantity is still legal ("to taste")\t%s', v_err is null and v_n = 1, coalesce(v_err, v_n || ' row'));

  select err into v_err from public.rls_matrix_do(format(
    'update profiles set display_name = repeat(''x'', 81) where id = %L', v_owner));
  v_log := v_log || format(E'%s\tB11a owner · an 81-char display_name must FAIL (32a2)\t%s', v_err = '23514', coalesce(v_err, 'no error'));

  select err into v_err from public.rls_matrix_do(format(
    'update profiles set bio = repeat(''x'', 501) where id = %L', v_owner));
  v_log := v_log || format(E'%s\tB11b owner · a 501-char bio must FAIL (32a2)\t%s', v_err = '23514', coalesce(v_err, 'no error'));

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
      '[{"name":"Main","ingredients":[{"name":"salt","quantity":1,"unit":"tsp","food_id":"bl7-food"}]}]'::jsonb,
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

  -- Phase 29b: the ingredient → food link rides the same RPC call. This is the
  -- only place the write path is proven — the app never PATCHes `ingredients`
  -- directly, so a save_recipe that dropped the key would fail silently (the
  -- Gotcha 11 "third copy" failure, one column later).
  select count(*) into n
  from ingredients i
  join ingredient_groups g on g.id = i.group_id
  where g.recipe_id = v_saved and i.food_id = 'bl7-food';
  v_log := v_log || format(E'%s\tB22b owner · save_recipe stores the ingredient food link\t%s row', n = 1, n);

  -- Phase 29c: source smuggling. A save CLAIMING `source: 'auto'` with
  -- fabricated numbers must store the label recomputed from the trees this
  -- same call persists, never the claim. bl7-food is 100 kcal/100 g, so
  -- 200 bl7-gram ÷ 2 servings = 100 kcal — not the 9999 the payload asserts.
  -- Proven non-vacuous by commenting the recompute branch out of save_recipe
  -- once (BL-7 ritual): this line alone goes red.
  select err into v_err from public.rls_matrix_do(format(
    'select save_recipe(%L, ''{"title":"BL-7 auto","servings":2,'
    '"nutrition":{"source":"auto","calories":9999}}''::jsonb, '
    '''[{"name":"Main","ingredients":[{"name":"bl7 sugar","quantity":200,'
    '"unit":"bl7-gram","food_id":"bl7-food"}]}]''::jsonb, '
    '''[]''::jsonb, ''BL-7'')', v_saved));
  select nutrition into v_json from recipes where id = v_saved;
  v_log := v_log || format(E'%s\tB22c owner · auto save stores the RECOMPUTED label, not the claim\t%s',
    v_err is null and (v_json->>'calories')::numeric = 100 and v_json->>'source' = 'auto',
    coalesce(v_err, coalesce(v_json::text, 'null')));

  -- And auto with nothing counted stores SQL NULL: an estimate of nothing is
  -- "no info" — the fabricated calories must not survive as a fallback.
  select err into v_err from public.rls_matrix_do(format(
    'select save_recipe(%L, ''{"title":"BL-7 auto empty",'
    '"nutrition":{"source":"auto","calories":9999}}''::jsonb, '
    '''[{"name":"Main","ingredients":[{"name":"unlinked","quantity":1,"unit":"tsp"}]}]''::jsonb, '
    '''[]''::jsonb, ''BL-7'')', v_saved));
  select nutrition into v_json from recipes where id = v_saved;
  v_log := v_log || format(E'%s\tB22d owner · auto with nothing counted stores NULL\t%s',
    v_err is null and v_json is null, coalesce(v_err, coalesce(v_json::text, 'null')));

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

  -- B082's second lock. `save_recipe` is `security definer`, so B9b/B9c's column
  -- grants do not constrain it — without these two the RPC is a way around them.
  -- A **create** claiming lineage is refused outright: on that branch a non-null
  -- value cannot have come from anywhere legitimate, since `fork_recipe` writes
  -- its own row.
  select err into v_err from public.rls_matrix_do(format(
    'select save_recipe(null, ''{"title":"BL-7 forged create","servings":1,'
    '"forked_from_recipe_id":"%s"}''::jsonb, ''[]''::jsonb, ''[]''::jsonb, ''BL-7'')', v_public));
  v_log := v_log || format(E'%s\tB23b owner · save_recipe create claiming lineage must FAIL (B082)\t%s',
    v_err = '42501', coalesce(v_err, 'no error'));

  -- An **update** ignores the claim instead of refusing it, and the asymmetry is
  -- deliberate: the client echoes the whole model back on every save, so a real
  -- fork's real lineage rides in the payload of every edit it ever gets. What
  -- must hold is that the STORED value wins — this forks a recipe, then saves
  -- the fork with a payload pointing somewhere else, and reads the column back.
  v_fork := fork_recipe(v_public);
  select err into v_err from public.rls_matrix_do(format(
    'select save_recipe(%L, ''{"title":"BL-7 fork edited",'
    '"forked_from_recipe_id":"%s"}''::jsonb, ''[]''::jsonb, ''[]''::jsonb, ''BL-7'')',
    v_fork, v_private));
  select forked_from_recipe_id into v_lineage from recipes where id = v_fork;
  v_log := v_log || format(E'%s\tB23c owner · save_recipe update keeps the STORED lineage (B082)\t%s',
    v_err is null and v_lineage = v_public,
    coalesce(v_err, coalesce(v_lineage::text, 'null')));

  -- Publish that self-fork: it is the fixture F11 needs, and a *private* fork
  -- would pass F11 for the wrong reason (the shelf counts public forks only).
  -- Costs the owner one more public recipe and no engagement, so `chef_score`
  -- and therefore F3/F6's tie are untouched.
  perform save_recipe(v_fork,
    '{"title":"BL-7 self fork","visibility":"public"}'::jsonb,
    '[]'::jsonb, '[]'::jsonb, 'BL-7');

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

  -- The `permission` literal is asserted here and nowhere else, which is what
  -- makes the fixture's `edit` (32a3) load-bearing rather than decorative: every
  -- refusal below then reads as "not even an `edit` share is a write right".
  select count(*) into n from recipe_shares
   where recipe_id = v_private and permission = 'edit';
  v_log := v_log || format(E'%s\tC3  shared · select own share row, at the reserved `edit` level\t%s row', n = 1, n);

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

  -- D25a (32a3): the legitimate half — a signed-in user may file a suggestion as
  -- themselves. (`suggestions_insert` is `author_id = auth.uid()` alone; it does
  -- not require the recipe be readable, and this check does not claim it does.)
  -- Without this the insert policy is only ever proven by its refusal, which a
  -- `with check (false)` would satisfy just as well.
  select err, rows into v_err, v_n from public.rls_matrix_do(format(
    'insert into recipe_suggestions (recipe_id, author_id, summary) values (%L, %L, ''BL-7 suggestion'')',
    v_public, v_other));
  v_log := v_log || format(E'%s\tD25a stranger · suggest as themselves\t%s', v_err is null and v_n = 1, coalesce(v_err, v_n || ' row'));

  -- D25b (32a3): authorship cannot be moved, by anybody. Held by the column
  -- grant rather than a policy, because "this column may not change" is a column
  -- statement and saying it in a `with check` would need a subquery reading the
  -- row's own table (the B053 shape) — and because column privileges are checked
  -- *before* RLS, this is `42501` for every role, which is why the check reads
  -- the same from the stranger's seat it actually runs in. D33 below takes the
  -- owner's seat, where the same lock matters most.
  select err into v_err from public.rls_matrix_do(format(
    'update recipe_suggestions set author_id = %L where recipe_id = %L', v_other, v_public));
  v_log := v_log || format(E'%s\tD25b stranger · rewrite a suggestion''s author must FAIL (32a3)\t%s',
    v_err = '42501', coalesce(v_err, 'no error'));

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

  -- D29 (32a3): `tags` has select / insert / delete policies and **no update
  -- policy**, so a rename is denied by nothing existing rather than by something
  -- refusing. That is a working lock and an invisible one — the day somebody
  -- replaces the three with a single `for all`, renames open silently and every
  -- recipe carrying the tag changes meaning at once. Pinning the *absence* is
  -- what makes it a decision. RLS with no matching policy denies by filtering,
  -- so an UPDATE matches **0 rows and raises nothing** (Gotcha 2) — assert the
  -- row count, never the error.
  select err, rows into v_err, v_n from public.rls_matrix_do(format(
    'update tags set name = ''bl7-renamed'' where id = %L', v_tag));
  v_log := v_log || format(E'%s\tD29 stranger · rename a tag matches 0 rows (no update policy)\t%s',
    v_err is null and v_n = 0, coalesce(v_err, v_n || ' row'));

  -- D30 (32a3): `profiles_insert` pins `id` to `auth.uid()`. Profiles normally
  -- arrive from `handle_new_user`, so this policy has never been exercised by a
  -- client at all — a forged row would be a profile someone else's `auth.users`
  -- id points at, and every FK into `profiles` would then attribute their
  -- recipes and ratings to it.
  -- A **fresh** id, not another fixture user's: inserting over an existing
  -- profile fails `23505` on the primary key, which would let this check pass
  -- while proving nothing about the policy. With an id nobody holds, the policy
  -- is the only thing between the statement and the row (verified 2026-08-26 by
  -- widening it to `with check (true)` and watching this line go red).
  select err into v_err from public.rls_matrix_do(
    'insert into profiles (id, display_name) values (gen_random_uuid(), ''BL-7 forged profile'')');
  v_log := v_log || format(E'%s\tD30 stranger · insert a profile AS another user must FAIL\t%s', v_err = '42501', coalesce(v_err, 'no error'));

  -- D31 (32a3): `recipe_suggestions` has select/insert/update policies and **no
  -- delete policy** — the same policy-absence lock D29 pins for `tags`, on the
  -- table this band is actually editing. 0 rows and no error, for the same
  -- reason D29 is (Gotcha 2). The row D25a left behind is the fixture.
  select err, rows into v_err, v_n from public.rls_matrix_do(format(
    'delete from recipe_suggestions where recipe_id = %L', v_public));
  v_log := v_log || format(E'%s\tD31 stranger · delete own suggestion matches 0 rows (no delete policy)\t%s',
    v_err is null and v_n = 0, coalesce(v_err, v_n || ' row'));

  -- D32/D33 (32a3): the owner's seat, which nothing else in this file occupies —
  -- section D holds `v_other`'s claims from :651 through to §E, so D25b above is
  -- a *stranger* hitting the column grant (labelled accordingly). Without these
  -- two, `suggestions_update`'s `using` is proven only by refusals: a change that
  -- locked the owner out entirely would pass every other check in the file.
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner)::text, true);

  select err, rows into v_err, v_n from public.rls_matrix_do(format(
    'update recipe_suggestions set status = ''accepted'' where recipe_id = %L', v_public));
  v_log := v_log || format(E'%s\tD32 owner-of-recipe · move a suggestion''s status\t%s',
    v_err is null and v_n = 1, coalesce(v_err, v_n || ' row'));

  -- The substance of someone else's proposal is not the owner's to rewrite: the
  -- update grant is `status` alone, so this is `42501` at the privilege check.
  select err into v_err from public.rls_matrix_do(format(
    'update recipe_suggestions set summary = ''BL-7 rewritten by the owner'' where recipe_id = %L', v_public));
  v_log := v_log || format(E'%s\tD33 owner-of-recipe · rewrite someone''s suggestion text must FAIL (32a3)\t%s',
    v_err = '42501', coalesce(v_err, 'no error'));

  perform set_config('request.jwt.claims', json_build_object('sub', v_other)::text, true);

  -- ==========================================================================
  -- E. food registry (Phase 29a) — reference data: readable signed-in only,
  --    written by nobody. Write denials are 42501 at the GRANT layer (the
  --    grants block revokes DML — RLS is never consulted), and `anon` has no
  --    select policy at all, so its reads come back empty rather than erroring.
  --    Still v_other's claims from section D — any signed-in user will do.
  -- ==========================================================================
  select count(*) into n from food where id = 'bl7-food';
  v_log := v_log || format(E'%s\tE1  signed-in · select the food registry\t%s row', n = 1, n);

  select err into v_err from public.rls_matrix_do(
    'insert into food (id, display_name) values (''bl7-forged'', ''x'')');
  v_log := v_log || format(E'%s\tE2  signed-in · insert a food must FAIL\t%s', v_err = '42501', coalesce(v_err, 'no error'));

  select err into v_err from public.rls_matrix_do(
    'update food set calories = 9999 where id = ''bl7-food''');
  v_log := v_log || format(E'%s\tE3  signed-in · update a food must FAIL\t%s', v_err = '42501', coalesce(v_err, 'no error'));

  select err into v_err from public.rls_matrix_do(
    'delete from food where id = ''bl7-food''');
  v_log := v_log || format(E'%s\tE4  signed-in · delete a food must FAIL\t%s', v_err = '42501', coalesce(v_err, 'no error'));

  select err into v_err from public.rls_matrix_do(
    'insert into food_alias (alias, food_id) values (''bl7-forged'', ''bl7-food'')');
  v_log := v_log || format(E'%s\tE5  signed-in · insert a food_alias must FAIL\t%s', v_err = '42501', coalesce(v_err, 'no error'));

  select err into v_err from public.rls_matrix_do(
    'insert into food_unit (spelling, unit_key, class) values (''bl7'', ''each'', ''count'')');
  v_log := v_log || format(E'%s\tE6  signed-in · insert a food_unit must FAIL\t%s', v_err = '42501', coalesce(v_err, 'no error'));

  select err, rows into v_err, v_n from public.rls_matrix_do(
    'select * from search_foods(''bl7 fixture'', 5)');
  v_log := v_log || format(E'%s\tE7  signed-in · search_foods finds the fixture\t%s', v_err is null and v_n = 1, coalesce(v_err, v_n || ' row'));

  -- Phase 29d. `recompute_auto_nutrition()` rewrites the `nutrition` column of
  -- every estimated recipe in the table, and it is invoker-rights — so the
  -- ONLY thing standing between a signed-in client and that whole-table write
  -- is the `revoke execute`, which PostgREST would otherwise ignore (it
  -- exposes every `public` function as an RPC). This is the check that proves
  -- the revoke is still there.
  --
  -- Double-locked like E2, and the non-vacuity ritual has to account for it:
  -- granting this function back alone still yields 42501, because its body
  -- calls `recipe_snapshot`, which is revoked from `authenticated` too. Both
  -- grants have to be handed back before this goes red — verified 2026-08-25.
  select err into v_err from public.rls_matrix_do(
    'select recompute_auto_nutrition()');
  v_log := v_log || format(E'%s\tE10 signed-in · recompute_auto_nutrition must FAIL\t%s', v_err = '42501', coalesce(v_err, 'no error'));

  -- Phase 39 (UX-030). `canonicalise_imported_units()` rewrites the unit of
  -- every imported ingredient in the table; only its `revoke execute` keeps it
  -- off the RPC surface. Non-vacuous on a converged database (every CI run):
  -- granted back, it finds nothing to change and returns 0 before reaching the
  -- ALTER that would otherwise also refuse. `canonical_unit` is read-only, but
  -- nothing on the client calls it, so it is revoked the way the Phase 37
  -- cleaners are and pinned here the same way.
  select err into v_err from public.rls_matrix_do(
    'select canonicalise_imported_units()');
  v_log := v_log || format(E'%s\tE11 signed-in · canonicalise_imported_units must FAIL\t%s', v_err = '42501', coalesce(v_err, 'no error'));

  select err into v_err from public.rls_matrix_do(
    'select canonical_unit(''tablespoons'', 3)');
  v_log := v_log || format(E'%s\tE12 signed-in · canonical_unit must FAIL\t%s', v_err = '42501', coalesce(v_err, 'no error'));

  execute 'set local role anon';
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);

  select count(*) into n from food;
  v_log := v_log || format(E'%s\tE8  anon · select the food registry sees nothing\t%s row', n = 0, n);

  select err into v_err from public.rls_matrix_do(
    'select * from search_foods(''bl7 fixture'', 5)');
  v_log := v_log || format(E'%s\tE9  anon · search_foods must FAIL\t%s', v_err = '42501', coalesce(v_err, 'no error'));

  -- ==========================================================================
  -- F. The chef reads behind `/chef/:id` (Phase 30) — and the three chef checks
  --    ROADMAP Phase 18 had listed as unasserted since 2026-08-19.
  --
  --    The page is signed-out safe, so this whole section runs as `anon`: the
  --    claim is not merely "these functions work", it is that a visitor with no
  --    account gets the same ranking every signed-in user does.
  --
  --    `chef_score` / `public_recipe_count` are written directly below. They are
  --    trigger-maintained columns and this is not testing the trigger — it is
  --    testing what the two RPCs do with the values they read, which is the only
  --    way to pin a *tie* deterministically. The whole file rolls back.
  -- ==========================================================================
  execute 'reset role';

  -- --------------------------------------------------------------------------
  -- Phase 23 windowed-board fixtures. **They have to be written BEFORE the two
  -- `update profiles` statements below**, and the ordering is load-bearing: a
  -- like or a view fires `bump_count` -> `recipes_chef_stats` ->
  -- `recompute_chef_stats`, which rewrites `chef_score` and
  -- `public_recipe_count` from the recipe table and would undo the pinned
  -- values F3/F6 exist to test. Written as `postgres` for the same reason the
  -- pins are: §F tests what the RPCs do with the rows, not who may write them.
  -- --------------------------------------------------------------------------

  -- One like inside any window and one dated 90 days back, both on the PUBLIC
  -- recipe, so F13 measures the window and not `visibility`. `v_owner` holds no
  -- like on `v_public` yet: D17 tried to plant one and was refused.
  insert into recipe_likes (user_id, recipe_id) values (v_sharee, v_public);
  insert into recipe_likes (user_id, recipe_id) values (v_other,  v_public);
  update recipe_likes set created_at = now() - interval '90 days'
   where user_id = v_other and recipe_id = v_public;

  -- B012's fixture, and the reason this block exists. Eight more rows land on
  -- the owner's public recipe inside the window, behind only TWO distinct
  -- signed-in viewers:
  --   * five ANONYMOUS rows — `anon` holds `insert on recipe_views` (A7 proves
  --     it), so this is exactly the loop an unauthenticated attacker can run;
  --   * three rows from ONE viewer — `recipe_views` is an append-only log, so a
  --     window that counted rows would let one enthusiast outrank a crowd.
  -- A7 already left an anonymous row here and D23 left one signed-in row, which
  -- is why F14 is written as a relationship rather than as `= 2`.
  for i in 1..5 loop
    insert into recipe_views (recipe_id, user_id) values (v_public, null);
  end loop;
  for i in 1..3 loop
    insert into recipe_views (recipe_id, user_id) values (v_public, v_sharee);
  end loop;

  -- Two chefs on the board with byte-identical scores, and one profile that is
  -- deliberately left off it.
  update profiles set chef_score = 4242, public_recipe_count = 2
   where id in (v_owner, v_sharee);
  update profiles set chef_score = 99999, public_recipe_count = 0
   where id = v_other;

  -- What the window SHOULD say for the owner, read straight off the tables
  -- while still `postgres` — `anon` cannot read `recipe_views` at all
  -- (`views_select` is `owns_recipe`), which is the whole reason
  -- `chef_window_stats` is `security definer` and the whole reason this has to
  -- be measured here rather than inside the checks.
  --
  -- `now()` is fixed for the transaction, so this boundary and the one the RPC
  -- computes are the same instant.
  select count(*) into v_raw
    from recipe_views v
    join recipes r on r.id = v.recipe_id
   where r.owner_id = v_owner and r.visibility = 'public'
     and v.viewed_at >= now() - interval '30 days';

  select count(*) into v_pairs
    from (
      select distinct v.recipe_id, v.user_id
        from recipe_views v
        join recipes r on r.id = v.recipe_id
       where r.owner_id = v_owner and r.visibility = 'public'
         and v.user_id is not null
         and v.viewed_at >= now() - interval '30 days'
    ) d;

  -- The public-only claim, from both sides: C16 left a like on the owner's
  -- PRIVATE recipe, so `v_all > v_pub` is what makes F15 non-vacuous.
  select count(*) into v_pub
    from recipe_likes l
    join recipes r on r.id = l.recipe_id
   where r.owner_id = v_owner and r.visibility = 'public';

  select count(*) into v_all
    from recipe_likes l
    join recipes r on r.id = l.recipe_id
   where r.owner_id = v_owner;

  execute 'set local role anon';
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);

  -- F1: the board itself is anon-callable. Every prior run of this proved it as
  -- `postgres`, which bypasses grants entirely, so it proved nothing about anon.
  select count(*) into n from chefs_leaderboard(100, 0);
  v_log := v_log || format(E'%s\tF1  anon · chefs_leaderboard is callable\t%s row', n > 0, n);

  select count(*) into n from chef_standing(v_owner);
  v_log := v_log || format(E'%s\tF2  anon · chef_standing returns the chef''s row\t%s row', n = 1, n);

  -- F3: THE trap this phase exists around. `dense_rank()` has to be computed
  -- over the whole population and the row picked out of the result; filter
  -- inside the window instead and every chef alive comes back rank 1, which
  -- looks correct on whoever is top of the board.
  select s.chef_rank into n from chef_standing(v_owner) s;
  select count(*) into v_n from chefs_leaderboard(1000, 0) b
   where b.id = v_owner and b.chef_rank = n;
  v_log := v_log || format(E'%s\tF3  anon · chef_standing rank == the board''s rank\t%s',
    v_n = 1, format('rank %s, %s matching board row', n, v_n));

  -- F4: the `public_recipe_count = 0` exclusion, from both directions. A
  -- profile that owns no public recipe holds no rank however high its score —
  -- which is why the score above it is the largest in the fixture.
  select count(*) into n from chef_standing(v_other);
  v_log := v_log || format(E'%s\tF4  anon · chef_standing is empty for a non-chef\t%s row', n = 0, n);

  select count(*) into n from chefs_leaderboard(1000, 0) b where b.id = v_other;
  v_log := v_log || format(E'%s\tF5  anon · the board excludes a non-chef too\t%s row', n = 0, n);

  -- F6: dense_rank ties share a rank. Two profiles, one score, one rank — and
  -- that rank has to be the **board's**, not just equal to each other. Checking
  -- only "one distinct rank" would pass under the F3 bug too, since a
  -- collapsed window rank returns 1 for everybody: verified 2026-08-25 by
  -- breaking the function, where F3 went red and a count-only F6 stayed green.
  select count(*) into n from (
    select a.chef_rank from chef_standing(v_owner) a
    union all
    select b.chef_rank from chef_standing(v_sharee) b
  ) t
  where t.chef_rank = (
    select b2.chef_rank from chefs_leaderboard(1000, 0) b2 where b2.id = v_owner
  );
  v_log := v_log || format(E'%s\tF6  anon · tied chefs share the board''s rank\t%s of 2 agree', n = 2, n);

  -- F7/F10: the two chef-scoped rankings behind `/chef/:id`'s Popular and
  -- Trending tabs (Phase 31). Both are invoker-rights, so `visibility = 'public'`
  -- is filtered inside the function rather than left to RLS, which would show a
  -- chef their own private recipes on the page everyone else sees.
  --
  -- Counted as "no non-public row", not "exactly one row": by the time §F runs,
  -- the owner holds more public recipes than the fixture block created —
  -- section B's `save_recipe` checks each leave one behind, inside the same
  -- transaction. An exact-count assertion here passes today and turns red the
  -- next time a check above it saves a recipe, which is a test that fails for a
  -- reason having nothing to do with what it claims to prove.
  select count(*) into n from chef_top_recipes(v_owner, 50, 0) r
   where r.visibility <> 'public';
  select count(*) into v_n from chef_top_recipes(v_owner, 50, 0) r
   where r.id = v_public;
  v_log := v_log || format(E'%s\tF7  anon · chef_top_recipes is public-only\t%s private of %s expected row',
    n = 0 and v_n = 1, n, v_n);

  -- F8: `p_offset` is actually applied, not accepted and ignored — one page in
  -- is where a dropped argument shows up as the duplicate row Gotcha 24
  -- describes. Asserted as a *difference* rather than an absolute count, for the
  -- same reason F7 is.
  select count(*) into n from chef_top_recipes(v_owner, 50, 0);
  select count(*) into v_n from chef_top_recipes(v_owner, 50, 1);
  v_log := v_log || format(E'%s\tF8  anon · chef_top_recipes honours p_offset\t%s row, %s past offset 1',
    v_n = n - 1, n, v_n);

  -- F9: the B024 trap, asserted rather than hoped for. Phase 31 added a third
  -- argument; if the old `(uuid, int)` overload survives the drop, a two-argument
  -- call matches both and fails 42725 — and nothing else in this file would
  -- notice, because every other call here passes three.
  select err into v_err from public.rls_matrix_do(
    format('select * from chef_top_recipes(%L::uuid, 3)', v_owner));
  v_log := v_log || format(E'%s\tF9  anon · a 2-arg chef_top_recipes call is unambiguous (B024)\t%s',
    v_err is null, coalesce(v_err, 'no error'));

  -- F10: the trending tab. Same visibility claim, plus the fall-through: the
  -- fixture has no like or view inside the seven-day window, so every recipe
  -- scores 0 and the RPC must still return the catalogue newest-first. An empty
  -- result here means a quiet week renders as an empty page.
  select count(*) into n from chef_trending_recipes(v_owner, 50, 0) r
   where r.visibility <> 'public';
  select count(*) into v_n from chef_trending_recipes(v_owner, 50, 0) r
   where r.id = v_public;
  v_log := v_log || format(E'%s\tF10 anon · chef_trending_recipes is public-only and never empty\t%s private of %s expected row',
    n = 0 and v_n = 1, n, v_n);

  -- F11 (B082): the half the column grants cannot reach. `fork_recipe` will
  -- happily fork your own public recipe — legitimately, it is a real copy — so
  -- without the self-exclusion a cook could fork themselves twenty times and
  -- own the `03 MOST FORKED` shelf. Section B left exactly that fixture behind:
  -- one PUBLIC fork of `v_public`, owned by `v_public`'s own owner, and no fork
  -- by anybody else (the stranger's fork in §D is private, which the shelf
  -- already ignores). So the source must not appear at all.
  select count(*) into n from recipes_most_forked(100, 0) r where r.id = v_public;
  v_log := v_log || format(E'%s\tF11 anon · a self-fork does not rank in MOST FORKED (B082)\t%s row', n = 0, n);

  -- ==========================================================================
  -- F12-F19: the WINDOWED board (Phase 23's deferred half). Still `anon`, and
  -- deliberately so — `chef_window_stats` is the one `security definer` read on
  -- this page, and the reason it has to be is that two of the four engagement
  -- logs are not world-readable (`saves_select` is `user_id = auth.uid()`,
  -- `views_select` is `owns_recipe`). Under invoker rights a signed-out visitor
  -- would silently get a board of zeros, which is indistinguishable from a
  -- quiet week. Every check below therefore has to run as the role that would
  -- have seen the zeros.
  -- ==========================================================================

  -- F12: both new functions are reachable without a session, and the windowed
  -- board covers exactly the population the all-time board does. The
  -- `public_recipe_count > 0` filter is defined once, in `chef_window_stats`;
  -- if the two ever disagree, `Score` and `Momentum` are two different boards
  -- wearing one set of tabs.
  select count(*) into n   from chef_window_stats(30);
  select count(*) into v_n from chefs_leaderboard(100000, 0);
  v_log := v_log || format(E'%s\tF12 anon · chef_window_stats covers the board''s population\t%s of %s',
    n > 0 and n = v_n, n, v_n);

  -- F13: the window is a FILTER, not decoration. One of the owner's two likes
  -- is dated 90 days back, so a 30-day window must see strictly fewer of them
  -- than a wide one. An inequality rather than a count, for the F7 reason —
  -- and note this is the check that would still be green if `p_days` were
  -- accepted and ignored the way F8 guards `p_offset`.
  select w.window_likes into n   from chef_window_stats(30, null, v_owner) w;
  select w.window_likes into v_n from chef_window_stats(3650, null, v_owner) w;
  v_log := v_log || format(E'%s\tF13 anon · the window excludes older engagement\t%s',
    v_n > n, format('%s like(s) in 30d vs %s in 3650d', n, v_n));

  -- F14: **the check this block exists for** (B012, Gotcha 10). `anon` holds
  -- `insert on recipe_views`, so a window that counted raw log rows would hand
  -- an unauthenticated loop the top of the Momentum board — the exact hole
  -- `on_view_insert` was written to close, re-opened in a ranking nobody is
  -- auditing. `window_views` must equal the DISTINCT signed-in (recipe, viewer)
  -- pairs, and `v_raw > v_pairs` is the half that makes it non-vacuous: without
  -- it, a function that simply saw no anonymous rows would pass.
  select w.window_views into n from chef_window_stats(30, null, v_owner) w;
  v_log := v_log || format(E'%s\tF14 anon · window views drop anon rows + dedupe the viewer (B012)\t%s',
    n = v_pairs and v_raw > v_pairs,
    format('%s log rows -> %s viewers, rpc said %s', v_raw, v_pairs, n));

  -- F15: public recipes only. `chef_window_stats` is `security definer`, so RLS
  -- is not underneath this — the explicit `visibility = 'public'` filter is the
  -- only thing keeping a private recipe's engagement out of a world-readable
  -- number. C16's like on `v_private` is what `v_all > v_pub` is pointing at.
  select w.window_likes into n from chef_window_stats(3650, null, v_owner) w;
  v_log := v_log || format(E'%s\tF15 anon · private-recipe engagement never enters the window\t%s',
    n = v_pub and v_all > v_pub,
    format('%s public of %s total likes, rpc said %s', v_pub, v_all, n));

  -- F16: `dense_rank()` is computed over the whole population and `limit` /
  -- `offset` are applied OUTSIDE it, so a chef's rank does not depend on which
  -- page they arrived on. Move the paging inside the window instead — the paged
  -- form of Phase 30's trap that F3 pins — and page two ranks a two-row set and
  -- comes back 1, 2.
  --
  -- Bounded to five two-row pages on purpose. This file is safe to run against
  -- a populated database, and paging a 10,000-chef board two rows at a time
  -- would re-aggregate the window 5,000 times.
  select count(*) into n
    from generate_series(0, 8, 2) g
    cross join lateral chefs_leaderboard_windowed(30, 2, g) pp
    join chefs_leaderboard_windowed(30, 10, 0) fb on fb.id = pp.id
   where pp.chef_rank is distinct from fb.chef_rank;
  v_log := v_log || format(E'%s\tF16 anon · a windowed rank is the same on any page\t%s row disagrees', n = 0, n);

  -- F17: Gotcha 24. `offset` only means anything over an ordering with no ties,
  -- and a windowed board is far more tie-prone than the all-time one — most of
  -- the population scores exactly 0 in any given week. Without the unique tail
  -- (`chef_score desc, created_at desc, id`) paging shows one chef twice and
  -- hides another, silently, which is why this asserts BOTH halves: nothing
  -- duplicated and nothing lost.
  select count(*) into v_n from chefs_leaderboard_windowed(30, 10, 0);
  select count(*), count(distinct pp.id) into n, i
    from generate_series(0, 8, 2) g
    cross join lateral chefs_leaderboard_windowed(30, 2, g) pp;
  v_log := v_log || format(E'%s\tF17 anon · paging the windowed board loses and repeats nothing\t%s',
    n = v_n and i = v_n, format('%s rows / %s distinct across 5 pages, %s in one', n, i, v_n));

  -- F18: `created_at` reached the board (Phase 23) — the `New` sort and the
  -- `Joined <month year>` line both need it. This is a RETURNS TABLE change,
  -- which `create or replace` cannot make, so on a database that already held
  -- the ten-column function the apply only succeeds because the
  -- `drop function if exists chefs_leaderboard(int, int)` above it runs first
  -- (B024). A fresh `db reset` cannot tell you that; this can.
  --
  -- `chef_standing` is checked in the same breath because the two share a row
  -- shape deliberately: one client model decodes either, and a column added to
  -- one and not the other is how that quietly stops being true.
  select count(*) into n
    from chefs_leaderboard(100000, 0) b
    join profiles p on p.id = b.id
   where b.created_at is not distinct from p.created_at;
  select count(*) into v_n from chefs_leaderboard(100000, 0);
  select count(*) into i
    from chef_standing(v_owner) s
    join profiles p on p.id = s.id
   where s.created_at is not distinct from p.created_at;
  v_log := v_log || format(E'%s\tF18 anon · chefs_leaderboard + chef_standing carry created_at\t%s',
    n = v_n and n > 0 and i = 1,
    format('%s of %s board rows match profiles, standing %s', n, v_n, i));

  -- F19: `p_since` overrides `p_days`. Two things need it. A paged Momentum
  -- board has to hold its boundary still across page requests — a window
  -- measured from `now()` MOVES between calls, which makes `offset` lie even
  -- over a total order (Gotcha 24, one level out). And a fixture whose
  -- engagement is anchored in the past (the sim pins `sim.epoch_end()`, B044)
  -- can only be crossed by naming an instant: on a simulated database that has
  -- gone stale, a 7-day window is correctly EMPTY, and widening the default
  -- would be fixing the query to suit the data.
  v_since := now() - interval '3650 days';
  select w.window_likes, w.window_start into v_n, v_when
    from chef_window_stats(30, v_since, v_owner) w;
  select w.window_likes into n from chef_window_stats(30, null, v_owner) w;
  v_log := v_log || format(E'%s\tF19 anon · p_since overrides p_days and is echoed back\t%s',
    v_n > n and v_when = v_since,
    format('%s like(s) at 30d vs %s pinned, window_start echoed %s', n, v_n, v_when = v_since));

  -- ==========================================================================
  -- F20-F21: `chef_trending_recipes` gives every seat the SAME order (B092).
  --
  -- The Phase 31 RPC ranks a chef's catalogue on `likes x 2 + distinct
  -- signed-in viewers` over seven days, reading `recipe_views` directly — and
  -- it shipped invoker-rights, while `views_select` is `owns_recipe`. So the
  -- viewer term counted zero for `anon` and for every signed-in non-owner, the
  -- ordering silently degraded to likes alone, and the chef saw a different
  -- Trending tab from their own readers. No error, anywhere.
  --
  -- Two fixtures make the check discriminating rather than decorative: two
  -- public recipes that TIE on likes (zero each) and differ only in recent
  -- distinct viewers, with the unread one created LAST. Ranked correctly, the
  -- well-read older one leads; with the viewer term reading zero rows the two
  -- tie and the documented fall-through (`created_at desc`) puts the unread
  -- newer one first. The wrong answer is therefore a different order, not an
  -- error — which is exactly why this needed a check and not an inspection.
  -- ==========================================================================
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);

  insert into recipes (owner_id, title, description, servings, visibility,
                       prep_minutes, cook_minutes, created_at)
  values (v_owner, 'BL-7 trending: read', 'older, well read', 2, 'public', 5, 5,
          now() - interval '2 days')
  returning id into v_trend_read;

  insert into recipes (owner_id, title, description, servings, visibility,
                       prep_minutes, cook_minutes, created_at)
  values (v_owner, 'BL-7 trending: unread', 'newer, unread', 2, 'public', 5, 5,
          now() - interval '1 day')
  returning id into v_trend_unread;

  -- Three DISTINCT signed-in viewers, inside the seven-day window. Distinct
  -- because the RPC counts `count(distinct v.user_id)` — three rows from one
  -- viewer would rank the same as one, which is B012's rule and is asserted
  -- for the windowed board at F14.
  insert into recipe_views (recipe_id, user_id, viewed_at) values
    (v_trend_read, v_owner,  now() - interval '1 day'),
    (v_trend_read, v_sharee, now() - interval '1 day'),
    (v_trend_read, v_other,  now() - interval '1 day');

  execute 'set local role anon';
  perform set_config('request.jwt.claims', '', true);

  -- F20: the premise. `anon` genuinely cannot read the view log — if this ever
  -- stops being true the rest of this block proves nothing, because the bug it
  -- guards against would have become unreachable for a different reason.
  --
  -- The claim is the RELATIVE order of the two fixtures, not the top of the
  -- page: the owner also owns `v_public`, which sections A-E have left likes
  -- on, and it outranks both. Comparing against `limit 1` would be asserting
  -- something about a third recipe this check is not about.
  select count(*) into n from recipe_views where recipe_id = v_trend_read;
  select array_agg(id order by ord) into v_trend_anon
    from (select id, row_number() over () as ord
            from chef_trending_recipes(v_owner, 100, 0)) x;
  i := array_position(v_trend_anon, v_trend_read);
  v_n := array_position(v_trend_anon, v_trend_unread);
  v_log := v_log || format(E'%s\tF20 anon · ranks on views it cannot itself read (B092)\t%s',
    n = 0 and i is not null and v_n is not null and i < v_n,
    format('anon sees %s view row(s); well-read at #%s, unread at #%s%s',
           n, i, v_n,
           case when i is not null and v_n is not null and i > v_n
                then ' — the viewer term counted zero' else '' end));

  -- F21: and it is the same order the owner gets. Compared as an ordered id
  -- array rather than one row: "the top row agrees" is a weaker claim than
  -- "the page agrees", and paging is what a reader actually scrolls.
  select array_agg(id order by ord) into v_trend_anon
    from (select id, row_number() over () as ord
            from chef_trending_recipes(v_owner, 10, 0)) x;

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner)::text, true);
  select array_agg(id order by ord) into v_trend_owner
    from (select id, row_number() over () as ord
            from chef_trending_recipes(v_owner, 10, 0)) x;

  execute 'set local role anon';
  perform set_config('request.jwt.claims', '', true);
  v_log := v_log || format(E'%s\tF21 anon and the owner get the same Trending order (B092)\t%s',
    v_trend_anon is not null
      and array_length(v_trend_anon, 1) >= 2
      and v_trend_anon = v_trend_owner,
    format('%s row(s) anon vs %s owner, identical: %s',
           coalesce(array_length(v_trend_anon, 1), 0),
           coalesce(array_length(v_trend_owner, 1), 0),
           v_trend_anon is not distinct from v_trend_owner));

  -- ==========================================================================
  -- F22-F24: `recompute_chef_stats` writes NOTHING when nothing moved.
  --
  -- 0001 calls its `is distinct from` guard load-bearing: `recipes_chef_stats`
  -- also watches rating_sum/rating_count, the v1 formula ignores both, so
  -- without the guard every rating anyone writes rewrites the chef's profile
  -- with byte-identical values and leaves a dead tuple on the table every
  -- leaderboard query and every recipe embed reads. No other check here could
  -- see that go: the VALUES are right either way, which is exactly why it had
  -- no assertion (ROADMAP carried-over, Phase 18).
  --
  -- So it is asserted on the one thing an UPDATE cannot avoid changing — the
  -- row's physical address. Every UPDATE writes a new tuple version, HOT or
  -- not, so an unchanged `ctid` means no UPDATE touched the row, and within one
  -- transaction that is a stronger signal than `xmin` (which would not move).
  -- F24 is the control that makes the other two discriminating: a like DOES
  -- move the numbers, so it must move the ctid — otherwise ctid is not
  -- measuring what F22/F23 claim it measures.
  -- ==========================================================================
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);

  -- Settled first, so F22 compares a converged row with itself rather than
  -- depending on every trigger in §A-§F having left it exact.
  perform recompute_chef_stats(v_owner);
  select ctid::text into v_ctid1 from profiles where id = v_owner;
  perform recompute_chef_stats(v_owner);
  select ctid::text into v_ctid2 from profiles where id = v_owner;
  v_log := v_log || format(E'%s\tF22 recompute_chef_stats with nothing changed writes no tuple\t%s',
    v_ctid1 = v_ctid2, format('profile ctid %s -> %s', v_ctid1, v_ctid2));

  -- F23: the case the guard was written for, through the real path — a
  -- signed-in reader rates the chef's public recipe, `recipe_ratings_agg`
  -- moves rating_sum/rating_count, `recipes_chef_stats` fires, and the chef's
  -- profile must come out of it untouched. The rating landing is part of the
  -- claim: a refused rating would leave the ctid alone for the wrong reason.
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', v_sharee)::text, true);
  select err into v_err from rls_matrix_do(format(
    'insert into recipe_ratings (user_id, recipe_id, rating) values (%L, %L, 4.0)',
    v_sharee, v_trend_read));
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  select rating_count into n from recipes where id = v_trend_read;
  select ctid::text into v_ctid2 from profiles where id = v_owner;
  v_log := v_log || format(E'%s\tF23 a rating leaves the chef''s profile row unwritten\t%s',
    v_err is null and n = 1 and v_ctid1 = v_ctid2,
    format('rating %s, rating_count %s, profile ctid %s -> %s',
           coalesce(v_err, 'ok'), n, v_ctid1, v_ctid2));

  -- F24: the control. A like changes `total_likes`, so the same trigger path
  -- has to write the row this time.
  select total_likes into v_likes1 from profiles where id = v_owner;
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', v_sharee)::text, true);
  select err into v_err from rls_matrix_do(format(
    'insert into recipe_likes (user_id, recipe_id) values (%L, %L)', v_sharee, v_trend_read));
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  select ctid::text, total_likes into v_ctid2, v_likes2 from profiles where id = v_owner;
  v_log := v_log || format(E'%s\tF24 control · a like DOES rewrite the chef''s profile row\t%s',
    v_err is null and v_likes2 = v_likes1 + 1 and v_ctid1 <> v_ctid2,
    format('like %s, total_likes %s -> %s, profile ctid %s -> %s',
           coalesce(v_err, 'ok'), v_likes1, v_likes2, v_ctid1, v_ctid2));

  -- ==========================================================================
  -- G1-G24: Phase 35b — identity decoupled from `auth.users`, entities, claims.
  --
  -- Sections A-F above are the proof that the decoupling is BEHAVIOUR-
  -- PRESERVING: every one of them was written against `= auth.uid()` and every
  -- one of them still passes against `= current_profile_id()`, because for a
  -- member the two return the same uuid. That is the whole safety argument for
  -- the migration, and it is worth stating that those 137 checks are the
  -- evidence for it rather than a happy coincidence.
  --
  -- What follows is the part A-F cannot reach: a profile with NO account
  -- behind it. Everything below is new surface, so the rule is the BL-7 one —
  -- a policy with no check here is an unproven policy.
  -- ==========================================================================
  execute 'reset role';

  -- An imported chef, exactly as the corpus importer will write one: a profile
  -- row with no `auth_user_id`, and a public recipe credited to it.
  insert into profiles (id, display_name, kind)
  values (gen_random_uuid(), 'BL-7 imported chef', 'imported')
  returning id into v_imported;

  insert into recipes (owner_id, title, description, servings, visibility,
                       prep_minutes, cook_minutes)
  values (v_imported, 'BL-7 imported recipe', 'imported', 2, 'public', 5, 5)
  returning id into v_imp_recipe;

  -- G1: `current_profile_id()` is null without a session — the property every
  -- `x = current_profile_id()` predicate depends on to be false for `anon`,
  -- which is how `auth.uid()` behaved and therefore how A1-A7 keep passing.
  execute 'set local role anon';
  perform set_config('request.jwt.claims', '', true);
  select current_profile_id() into v_me;
  v_log := v_log || format(E'%s\tG1  anon · current_profile_id() is null\t%s',
    v_me is null, coalesce(v_me::text, 'null'));

  -- G2: and for a member it is exactly the id `auth.uid()` used to return.
  -- This is the invariant `handle_new_user` maintains by writing `id = new.id`;
  -- if it ever stops holding, the storage-bucket policies (still keyed on
  -- `auth.uid()`) and every fixture in this file part company with the schema.
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner)::text, true);
  select current_profile_id() into v_me;
  v_log := v_log || format(E'%s\tG2  owner · current_profile_id() = auth.uid() for a member\t%s',
    v_me = v_owner, coalesce(v_me::text, 'null'));

  -- G3: an imported chef's page is world-readable. It has to be — the credit is
  -- the entire reason the row exists (Phase 35a), and a page nobody can load is
  -- not attribution.
  execute 'set local role anon';
  perform set_config('request.jwt.claims', '', true);
  select count(*) into n from profiles where id = v_imported;
  v_log := v_log || format(E'%s\tG3  anon · an imported profile is readable\t%s row(s)', n = 1, n);

  -- G4: and immutable. Not by a policy that names imported profiles, but
  -- because `current_profile_id()` cannot return one — there is no account it
  -- could resolve from. Asserted as ZERO ROWS, not as an error: an RLS-denied
  -- UPDATE reports success (Gotcha 2), which is the failure mode this whole
  -- file exists for.
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner)::text, true);
  select err, rows into v_err, n from rls_matrix_do(format(
    'update profiles set display_name = ''hijacked'' where id = %L', v_imported));
  v_log := v_log || format(E'%s\tG4  owner · update an imported profile touches 0 rows\t%s',
    n = 0, coalesce(v_err, format('%s row(s)', n)));

  -- G5: the exclusion that makes "empty stats" true in practice. The imported
  -- chef above owns a public recipe, so `public_recipe_count > 0` alone would
  -- seat it on the board — tied at score 0 with every other imported chef and
  -- then ordered by recipe count, which at corpus scale means the board IS the
  -- corpus. `kind = 'member'` is the only thing stopping that.
  execute 'set local role anon';
  perform set_config('request.jwt.claims', '', true);
  select public_recipe_count into n from profiles where id = v_imported;
  select count(*) into v_n from chefs_leaderboard(100000, 0) where id = v_imported;
  v_log := v_log || format(E'%s\tG5  anon · an imported chef is NOT on the leaderboard\t%s',
    v_n = 0 and n > 0,
    format('%s public recipe(s), %s board row(s)', n, v_n));

  -- G6: `chef_standing` has to agree with the board it is a row of, so an
  -- imported chef gets zero rows there too — which the client already renders
  -- as "not ranked yet" (Phase 30's empty case, reused unchanged).
  select count(*) into n from chef_standing(v_imported);
  v_log := v_log || format(E'%s\tG6  anon · chef_standing on an imported chef is empty\t%s row(s)',
    n = 0, n);

  -- G7: the windowed board is the same population, for the same reason.
  select count(*) into n from chef_window_stats(30) w where w.id = v_imported;
  v_log := v_log || format(E'%s\tG7  anon · chef_window_stats excludes imported chefs\t%s row(s)',
    n = 0, n);

  -- G8: their recipes are still browsable. The point of the exclusion is that
  -- an imported chef is not RANKED, not that they are hidden — a corpus that
  -- cannot be read is a corpus that was not worth importing.
  select count(*) into n from recipes where id = v_imp_recipe;
  v_log := v_log || format(E'%s\tG8  anon · an imported chef''s public recipe is readable\t%s row(s)',
    n = 1, n);

  -- ==========================================================================
  -- G9-G14: claims
  -- ==========================================================================
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner)::text, true);

  -- G9: a claim may only be filed against an IMPORTED profile. Without the
  -- `kind` half of `claims_insert` a user could file against another member's
  -- live profile — harmless while approval is manual, and a phishing surface
  -- the moment it is not.
  select err into v_err from rls_matrix_do(format(
    'insert into profile_claims (profile_id, claimant_auth_user_id) values (%L, %L)',
    v_other, v_owner));
  v_log := v_log || format(E'%s\tG9  owner · claim another MEMBER''s profile must FAIL\t%s',
    v_err = '42501', coalesce(v_err, 'no error'));

  -- G10: and only on your own behalf.
  select err into v_err from rls_matrix_do(format(
    'insert into profile_claims (profile_id, claimant_auth_user_id) values (%L, %L)',
    v_imported, v_other));
  v_log := v_log || format(E'%s\tG10 owner · file a claim as somebody else must FAIL\t%s',
    v_err = '42501', coalesce(v_err, 'no error'));

  -- G11: the legitimate case.
  select err into v_err from rls_matrix_do(format(
    'insert into profile_claims (profile_id, claimant_auth_user_id, evidence_url)
     values (%L, %L, ''https://example.test/proof'')', v_imported, v_owner));
  select id into v_claim from profile_claims
   where profile_id = v_imported and claimant_auth_user_id = v_owner;
  v_log := v_log || format(E'%s\tG11 owner · file a claim on an imported profile\t%s',
    v_err is null and v_claim is not null, coalesce(v_err, 'ok'));

  -- G12: `status` is the reviewer's answer, so a claimant cannot pre-approve
  -- their own. There is no update policy AND no update grant; the grant is what
  -- answers first, which is why this is a 42501 and not a silent 0 rows.
  select err, rows into v_err, n from rls_matrix_do(format(
    'update profile_claims set status = ''approved'' where id = %L', v_claim));
  v_log := v_log || format(E'%s\tG12 owner · approve your own claim must FAIL\t%s',
    v_err = '42501', coalesce(v_err, format('%s row(s)', n)));

  -- G13: claims are not public. "Who is trying to claim this chef" is not
  -- something the directory should publish while it is still pending.
  perform set_config('request.jwt.claims', json_build_object('sub', v_other)::text, true);
  select count(*) into n from profile_claims where id = v_claim;
  v_log := v_log || format(E'%s\tG13 stranger · cannot read somebody else''s claim\t%s row(s)',
    n = 0, n);

  -- G14: and the decision RPCs are not reachable from the API at all (Gotcha 3
  -- — PostgREST exposes every function in `public`). This is the lock that
  -- matters most in this section: the function transfers ownership of every
  -- recipe on a profile.
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner)::text, true);
  select err into v_err from rls_matrix_do(format(
    'select approve_profile_claim(%L)', v_claim));
  v_log := v_log || format(E'%s\tG14 owner · approve_profile_claim RPC must FAIL\t%s',
    v_err = '42501', coalesce(v_err, 'no error'));
  select err into v_err from rls_matrix_do(format(
    'select reject_profile_claim(%L, null)', v_claim));
  v_log := v_log || format(E'%s\tG15 owner · reject_profile_claim RPC must FAIL\t%s',
    v_err = '42501', coalesce(v_err, 'no error'));

  -- G16/G17: the two identity columns a client must never move. `kind` is
  -- absent from the column grants entirely; `auth_user_id` is insert-only, so
  -- an UPDATE of it fails at the privilege check before RLS is consulted. The
  -- second is the one that would matter: an update grant there would let a
  -- member re-point their profile at another account.
  select err into v_err from rls_matrix_do(format(
    'update profiles set kind = ''imported'' where id = %L', v_owner));
  v_log := v_log || format(E'%s\tG16 owner · update own profiles.kind must FAIL\t%s',
    v_err = '42501', coalesce(v_err, 'no error'));
  select err into v_err from rls_matrix_do(format(
    'update profiles set auth_user_id = %L where id = %L', v_other, v_owner));
  v_log := v_log || format(E'%s\tG17 owner · update own profiles.auth_user_id must FAIL\t%s',
    v_err = '42501', coalesce(v_err, 'no error'));

  -- ==========================================================================
  -- G18-G23: entities (Phase 25's table, generalised)
  -- ==========================================================================

  -- G18: provenance cannot be forged on creation.
  select err into v_err from rls_matrix_do(format(
    'insert into entities (slug, name, kind, created_by)
     values (''bl7-forged'', ''Forged'', ''restaurant'', %L)', v_other));
  v_log := v_log || format(E'%s\tG18 owner · create an entity attributed to someone else must FAIL\t%s',
    v_err = '42501', coalesce(v_err, 'no error'));

  -- G19: the legitimate create, plus the bootstrap seat. Without the
  -- zero-members clause in `entity_members_insert` a newly created entity has
  -- no owner and therefore can never gain one — the row would be permanently
  -- unmanageable by anybody.
  select err into v_err from rls_matrix_do(format(
    'insert into entities (slug, name, kind, created_by)
     values (''bl7-kitchen'', ''BL-7 Test Kitchen'', ''restaurant'', %L)', v_owner));
  select id into v_entity from entities where slug = 'bl7-kitchen';
  select err into v_err2 from rls_matrix_do(format(
    'insert into entity_members (entity_id, profile_id, role) values (%L, %L, ''owner'')',
    v_entity, v_owner));
  v_log := v_log || format(E'%s\tG19 owner · create an entity and take the first owner seat\t%s',
    v_err is null and v_err2 is null and v_entity is not null,
    format('create %s, seat %s', coalesce(v_err, 'ok'), coalesce(v_err2, 'ok')));

  -- G20: and the bootstrap does not stay open. A stranger cannot seat
  -- themselves once the entity has a member.
  perform set_config('request.jwt.claims', json_build_object('sub', v_other)::text, true);
  select err into v_err from rls_matrix_do(format(
    'insert into entity_members (entity_id, profile_id, role) values (%L, %L, ''owner'')',
    v_entity, v_other));
  v_log := v_log || format(E'%s\tG20 stranger · seat themselves on an owned entity must FAIL\t%s',
    v_err = '42501', coalesce(v_err, 'no error'));

  -- G21: a non-owner cannot edit the entity. Zero rows, not an error — the
  -- Gotcha 2 shape again, and the column grants do not catch this one because
  -- `name` is legitimately updatable by the right person.
  select err, rows into v_err, n from rls_matrix_do(format(
    'update entities set name = ''hijacked'' where id = %L', v_entity));
  v_log := v_log || format(E'%s\tG21 stranger · update an entity touches 0 rows\t%s',
    n = 0, coalesce(v_err, format('%s row(s)', n)));

  -- G22: a PRIVATE recipe may never be a signature dish. The table is
  -- world-readable, so listing one would publish its id and its existence —
  -- the leak `entity_signature_write` says `visibility = 'public'` explicitly
  -- to avoid, rather than leaning on `can_read_recipe` (true for the owner).
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner)::text, true);
  select err into v_err from rls_matrix_do(format(
    'insert into entity_signature_dishes (entity_id, recipe_id) values (%L, %L)',
    v_entity, v_private));
  v_log := v_log || format(E'%s\tG22 owner · list a PRIVATE recipe as a signature dish must FAIL\t%s',
    v_err = '42501', coalesce(v_err, 'no error'));

  -- G23: the public one is fine, and the whole directory reads back signed-out.
  select err into v_err from rls_matrix_do(format(
    'insert into entity_signature_dishes (entity_id, recipe_id) values (%L, %L)',
    v_entity, v_public));
  execute 'set local role anon';
  perform set_config('request.jwt.claims', '', true);
  select count(*) into n from entities where id = v_entity;
  select count(*) into v_n from entity_members where entity_id = v_entity;
  select count(*) into v_raw from entity_signature_dishes where entity_id = v_entity;
  v_log := v_log || format(E'%s\tG23 anon · entity, roster and signature dishes are public\t%s',
    v_err is null and n = 1 and v_n = 1 and v_raw = 1,
    format('%s entity, %s member(s), %s dish(es), write %s',
           n, v_n, v_raw, coalesce(v_err, 'ok')));

  -- ==========================================================================
  -- G24: the merge. The riskiest code in Phase 35b and the only thing here that
  -- moves rows between principals, so it is exercised end to end rather than
  -- argued about: a claimant with their own recipe and their own like takes
  -- over an imported profile that already has one, and afterwards EVERYTHING
  -- must sit on the claimed profile with the old one left as a tombstone.
  --
  -- Run as `postgres`, which is the only caller the revokes above permit.
  -- ==========================================================================
  execute 'reset role';

  -- The claimant's own content, so the merge has something to move.
  insert into recipes (owner_id, title, description, servings, visibility,
                       prep_minutes, cook_minutes)
  values (v_owner, 'BL-7 merge fixture', 'moves', 2, 'public', 5, 5)
  returning id into v_merge_recipe;

  select count(*) into v_raw from recipes where owner_id = v_owner;

  perform approve_profile_claim(v_claim);

  select count(*) into n      from recipes where owner_id = v_imported;
  select count(*) into v_n    from recipes where owner_id = v_owner;
  select auth_user_id, merged_into into v_me, v_merged from profiles where id = v_owner;
  select auth_user_id into v_claimed_link from profiles where id = v_imported;
  select kind::text into s2 from profiles where id = v_imported;

  v_log := v_log || format(E'%s\tG24 merge · every recipe moves to the claimed profile\t%s',
    n = v_raw + 1 and v_n = 0,
    format('%s on claimed (was %s + 1 imported), %s left behind', n, v_raw, v_n));

  v_log := v_log || format(E'%s\tG25 merge · the old profile is a tombstone, not a delete\t%s',
    v_me is null and v_merged = v_imported,
    format('link %s, merged_into %s',
           coalesce(v_me::text, 'null'), coalesce(v_merged::text, 'null')));

  v_log := v_log || format(E'%s\tG26 merge · the claimed profile becomes a member with the link\t%s',
    v_claimed_link = v_owner and s2 = 'member',
    format('link %s, kind %s', coalesce(v_claimed_link::text, 'null'), s2));

  -- And the identity primitive follows the link, which is the point of the
  -- whole exercise: the claimant signs in with the same account and is now the
  -- imported chef.
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner)::text, true);
  select current_profile_id() into v_me;
  v_log := v_log || format(E'%s\tG27 merge · current_profile_id() now resolves to the claimed profile\t%s',
    v_me = v_imported, coalesce(v_me::text, 'null'));

  -- The claim itself is closed, and `unique(auth_user_id)` held throughout —
  -- exactly one profile points at this account.
  execute 'reset role';
  select count(*) into n from profiles where auth_user_id = v_owner;
  select status::text into s2 from profile_claims where id = v_claim;
  v_log := v_log || format(E'%s\tG28 merge · one profile holds the link, claim is approved\t%s',
    n = 1 and s2 = 'approved', format('%s profile(s), status %s', n, s2));

  -- ==========================================================================
  -- G29-G34: the pending-claim cap (Phase 35c).
  --
  -- `claims_insert` allows one pending claim per (profile, claimant) and
  -- nothing else bounded it, so one account could open a claim on every
  -- imported profile in the corpus — each a row a person reviews by hand.
  -- `profile_claims_pending_cap` (an AFTER trigger) holds an account to
  -- `profile_claim_pending_cap()` PENDING claims; a decided one frees its slot.
  --
  -- The stranger files here, not the owner: the owner's account was merged at
  -- G24, and a cap check that passes because the claimant quietly became
  -- somebody else is the H8b failure mode again. These run LAST in §G because
  -- G33 approves one of the stranger's claims, which moves that account's link
  -- too — nothing after this section signs in as the stranger.
  -- ==========================================================================
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  v_cap := profile_claim_pending_cap();
  v_cap_profiles := '{}';
  for i in 1 .. v_cap + 2 loop
    insert into profiles (id, display_name, kind)
    values (gen_random_uuid(), format('BL-7 cap fixture %s', i), 'imported')
    returning id into v_new;
    v_cap_profiles := v_cap_profiles || v_new;
  end loop;

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', v_other)::text, true);

  -- G29: up to the cap, every filing lands.
  v_n := 0;
  for i in 1 .. v_cap loop
    select err into v_err from rls_matrix_do(format(
      'insert into profile_claims (profile_id, claimant_auth_user_id) values (%L, %L)',
      v_cap_profiles[i], v_other));
    if v_err is null then v_n := v_n + 1; end if;
  end loop;
  select count(*) into n from profile_claims
   where claimant_auth_user_id = v_other and status = 'pending';
  v_log := v_log || format(E'%s\tG29 stranger · file claims up to the cap\t%s',
    v_n = v_cap and n = v_cap,
    format('%s of %s filed, %s pending', v_n, v_cap, n));

  -- G30: the next one is refused — by the CAP, which is why the message is
  -- asserted and not only the SQLSTATE: a P0001 from anything else would
  -- otherwise pass. Caught here rather than through `rls_matrix_do` because
  -- that helper returns the code alone.
  begin
    insert into profile_claims (profile_id, claimant_auth_user_id)
    values (v_cap_profiles[v_cap + 1], v_other);
    v_err := null;
    v_msg := null;
  exception when others then
    v_err := sqlstate;
    v_msg := sqlerrm;
  end;
  select count(*) into n from profile_claims
   where claimant_auth_user_id = v_other and status = 'pending';
  v_log := v_log || format(E'%s\tG30 stranger · the cap+1th pending claim must FAIL\t%s',
    v_err = 'P0001' and v_msg = 'profile claim limit reached' and n = v_cap,
    format('%s (%s), %s pending', coalesce(v_err, 'no error'), coalesce(v_msg, '-'), n));

  -- G31: and the cap cannot be used to PROBE another account. Filing on the
  -- capped account's behalf is refused by `claims_insert` (42501), exactly as
  -- G10 is — not by the cap (P0001), which would tell the caller that account
  -- has claims open. This is what the trigger being AFTER, not BEFORE, buys:
  -- the policy's `with check` runs first and the count never sees the row.
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner)::text, true);
  select err into v_err from rls_matrix_do(format(
    'insert into profile_claims (profile_id, claimant_auth_user_id) values (%L, %L)',
    v_cap_profiles[v_cap + 1], v_other));
  v_log := v_log || format(E'%s\tG31 owner · filing for a capped account is the POLICY''s 42501\t%s',
    v_err = '42501', coalesce(v_err, 'no error'));

  -- G32: a REJECTED claim frees its slot. The cap bounds the review queue, not
  -- a person's history — a chef turned down for thin evidence must be able to
  -- file again.
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  select id into v_new from profile_claims
   where claimant_auth_user_id = v_other and profile_id = v_cap_profiles[1];
  perform reject_profile_claim(v_new, 'BL-7: rejected to free a slot');

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', v_other)::text, true);
  select err into v_err from rls_matrix_do(format(
    'insert into profile_claims (profile_id, claimant_auth_user_id) values (%L, %L)',
    v_cap_profiles[v_cap + 1], v_other));
  select count(*) into n from profile_claims
   where claimant_auth_user_id = v_other and status = 'pending';
  v_log := v_log || format(E'%s\tG32 stranger · a rejected claim frees its slot\t%s',
    v_err is null and n = v_cap,
    format('file %s, %s pending', coalesce(v_err, 'ok'), n));

  -- G33: and so does an APPROVED one. Approval goes through the real merge,
  -- which is also what moves this account's link (see the section header).
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  select id into v_new from profile_claims
   where claimant_auth_user_id = v_other and profile_id = v_cap_profiles[2];
  perform approve_profile_claim(v_new);

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', v_other)::text, true);
  select err into v_err from rls_matrix_do(format(
    'insert into profile_claims (profile_id, claimant_auth_user_id) values (%L, %L)',
    v_cap_profiles[v_cap + 2], v_other));
  select count(*) into n from profile_claims
   where claimant_auth_user_id = v_other and status = 'pending';
  v_log := v_log || format(E'%s\tG33 stranger · an approved claim frees its slot\t%s',
    v_err is null and n = v_cap,
    format('file %s, %s pending', coalesce(v_err, 'ok'), n));

  -- G34: the cap is per ACCOUNT, not per table. The stranger is at the cap
  -- again; the owner holds no pending claim (theirs was approved at G24), so
  -- they can file on the profile the stranger's rejected claim released.
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner)::text, true);
  select err into v_err from rls_matrix_do(format(
    'insert into profile_claims (profile_id, claimant_auth_user_id) values (%L, %L)',
    v_cap_profiles[1], v_owner));
  v_log := v_log || format(E'%s\tG34 owner · another account at the cap does not block this one\t%s',
    v_err is null, coalesce(v_err, 'ok'));

  -- ==========================================================================
  -- H1-H8: Phase 35c — provenance, the corpus surface, and the blocklist.
  --
  -- The columns here are the second set in this schema that a client must never
  -- write, and they fail differently from the first: a forged counter changes a
  -- number, a forged `source_url` changes **who a recipe is credited to**. The
  -- checks below are the only thing proving the grant lists exclude them.
  -- ==========================================================================
  execute 'reset role';

  -- An imported fixture: public, flagged, with provenance and a publisher.
  insert into entities (id, slug, name, kind, created_by)
  values (gen_random_uuid(), 'bl7-publisher', 'BL-7 Publisher', 'publication', null)
  returning id into v_publisher;

  insert into profiles (id, display_name, kind)
  values (gen_random_uuid(), 'BL-7 imported byline', 'imported')
  returning id into v_imp2;

  insert into recipes (
    owner_id, title, description, servings, visibility, prep_minutes,
    cook_minutes, is_imported, quality_score, source_url, source_name,
    source_entity_id, imported_at
  ) values (
    v_imp2, 'BL-7 imported fixture', 'imported', 2, 'public', 5, 5,
    true, 90, 'https://example.test/bl7/imported-fixture', 'BL-7 Publisher',
    v_publisher, now()
  )
  returning id into v_imp_recipe2;

  -- H1: it is readable signed out. The corpus is browsable — the point of the
  -- exclusion elsewhere is that it is not RANKED, not that it is hidden.
  execute 'set local role anon';
  perform set_config('request.jwt.claims', '', true);
  select count(*) into n from recipes where id = v_imp_recipe2;
  v_log := v_log || format(E'%s\tH1  anon · an imported recipe is readable\t%s row(s)', n = 1, n);

  -- H2: and it reaches the one surface that shows it.
  select count(*) into n from recipes_corpus(1000000, 0) c where c.id = v_imp_recipe2;
  v_log := v_log || format(E'%s\tH2  anon · recipes_corpus returns it\t%s row(s)', n = 1, n);

  -- H3: while every RANKED shelf excludes it. Checked as a sum across all
  -- five, because one shelf keeping the filter proves nothing about the others
  -- — and the filter was added to five separate function bodies.
  select
    (select count(*) from recipes_quick(1000000, 0) x where x.id = v_imp_recipe2)
  + (select count(*) from recipes_popular(1000000, 0) x where x.id = v_imp_recipe2)
  + (select count(*) from recipes_trending(1000000, 0) x where x.id = v_imp_recipe2)
  + (select count(*) from recipes_projects(1000000, 0) x where x.id = v_imp_recipe2)
  + (select count(*) from recipes_most_forked(1000000, 0) x where x.id = v_imp_recipe2)
  into n;
  v_log := v_log || format(E'%s\tH3  anon · no ranked shelf shows it\t%s hit(s) across 5 shelves',
    n = 0, n);

  -- H4: a `blocked` row leaves the corpus surface. This is what makes a
  -- takedown a data change rather than a deploy, and it is honoured on READ so
  -- the row that records the takedown can survive it.
  execute 'reset role';
  update recipes set rights_mode = 'blocked' where id = v_imp_recipe2;
  execute 'set local role anon';
  perform set_config('request.jwt.claims', '', true);
  select count(*) into n from recipes_corpus(1000000, 0) c where c.id = v_imp_recipe2;
  v_log := v_log || format(E'%s\tH4  anon · a blocked recipe leaves recipes_corpus\t%s row(s)',
    n = 0, n);
  execute 'reset role';
  update recipes set rights_mode = 'functional' where id = v_imp_recipe2;

  -- H5-H7: the provenance columns are server-owned. The owner of a recipe is
  -- the strongest principal there is here, and even they cannot write these —
  -- a claimed chef editing their imported recipe must not be able to clear its
  -- credit or promote it into the ranked shelves.
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner)::text, true);
  select err into v_err from rls_matrix_do(format(
    'update recipes set is_imported = false where id = %L', v_public));
  v_log := v_log || format(E'%s\tH5  owner · update own recipes.is_imported must FAIL\t%s',
    v_err = '42501', coalesce(v_err, 'no error'));

  select err into v_err from rls_matrix_do(format(
    'update recipes set source_url = ''https://evil.test/'' where id = %L', v_public));
  v_log := v_log || format(E'%s\tH6  owner · update own recipes.source_url must FAIL\t%s',
    v_err = '42501', coalesce(v_err, 'no error'));

  select err into v_err from rls_matrix_do(format(
    'update recipes set quality_score = 100 where id = %L', v_public));
  v_log := v_log || format(E'%s\tH7  owner · update own recipes.quality_score must FAIL\t%s',
    v_err = '42501', coalesce(v_err, 'no error'));

  -- And on INSERT, where a client could otherwise mint a row that claims to
  -- have come from a publisher it has nothing to do with.
  select err into v_err from rls_matrix_do(format(
    'insert into recipes (owner_id, title, servings, visibility, source_name) '
    'values (%L, ''forged'', 1, ''public'', ''BBC Good Food'')', v_owner));
  v_log := v_log || format(E'%s\tH8  owner · insert claiming a source_name must FAIL\t%s',
    v_err = '42501', coalesce(v_err, 'no error'));

  -- H8b: a member cannot take a slug in the importer's namespace. Without the
  -- reserved prefix, creating `king-arthur` before an import runs would hand
  -- that publisher's whole catalogue to whoever got there first —
  -- `import_recipe` finds-or-creates by slug, and `entities_update` is
  -- `is_entity_owner`. A free land-grab on 560 names, closed by a `check`.
  --
  -- `current_profile_id()` rather than `v_owner`: **§G's merge moved this
  -- account's link** (G24-G28), so `v_owner` is a tombstone by the time §H runs
  -- and `entities_insert` refuses the row on `created_by` before the constraint
  -- ever sees it. The check then passes for the wrong reason, which is the
  -- failure mode a "must FAIL" assertion is most prone to — it reported 42501
  -- from the policy while claiming to prove 23514 from the namespace.
  select err into v_err from rls_matrix_do(
    'insert into entities (slug, name, kind, created_by) '
    'values (''src:king-arthur'', ''Forged'', ''brand'', current_profile_id())');
  v_log := v_log || format(E'%s\tH8b owner · create an entity under `src:` must FAIL\t%s',
    v_err = '23514', coalesce(v_err, 'no error'));

  -- And the same insert OUTSIDE the namespace succeeds, so H8b is refusing the
  -- prefix rather than refusing everything.
  select err into v_err from rls_matrix_do(
    'insert into entities (slug, name, kind, created_by) '
    'values (''bl7-ordinary-entity'', ''Ordinary'', ''brand'', current_profile_id())');
  v_log := v_log || format(E'%s\tH8c owner · the same insert outside `src:` succeeds\t%s',
    v_err is null, coalesce(v_err, 'ok'));

  -- H9: `import_blocklist` is readable by nobody. RLS is enabled with no policy
  -- at all, which default-denies — and the blanket grants below the policies
  -- are exactly why that has to be asserted: a grant with no policy returns
  -- EMPTY, not an error, so a missing policy and a working one look identical
  -- until somebody checks.
  execute 'reset role';
  insert into import_blocklist (url, source_slug, reason)
  values ('https://example.test/bl7/taken-down', 'bl7-publisher', 'BL-7 fixture')
  on conflict (url) do nothing;

  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner)::text, true);
  select count(*) into n from import_blocklist;
  v_log := v_log || format(E'%s\tH9  signed-in · import_blocklist reads empty\t%s row(s)', n = 0, n);

  execute 'set local role anon';
  perform set_config('request.jwt.claims', '', true);
  select count(*) into v_n from import_blocklist;
  select err into v_err from rls_matrix_do(
    'insert into import_blocklist (url) values (''https://example.test/forged'')');
  v_log := v_log || format(E'%s\tH10 anon · cannot read or write import_blocklist\t%s row(s), write %s',
    v_n = 0 and v_err is not null, v_n, coalesce(v_err, 'SUCCEEDED'));

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
