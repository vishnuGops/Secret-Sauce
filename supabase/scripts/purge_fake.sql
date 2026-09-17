-- purge_fake.sql — delete the fabricated accounts, profiles and recipes that
-- `supabase/tests/data_audit.sql` classifies as FAKE, and repair the counters
-- that were authored by hand.
--
-- DESTRUCTIVE. Deletes rows from `auth.users`, which has no undo. There is no
-- PITR on the Supabase free tier, so `melos run db:backup -- --docker` first if
-- the target is anything but a local stack.
--
-- Run it through `melos run db:purge:fake -- --yes`, which runs
-- `9_sim_teardown.sql` immediately before this file. That split is deliberate:
-- the simulated population already has a reviewed, registry-driven teardown and
-- duplicating its logic here would give the project two of them, which is how
-- one of the two ends up subtly wrong.
--
-- ---------------------------------------------------------------------------
-- WHAT THIS FILE REMOVES — and what it deliberately does not
--
-- REMOVES:
--   * `supabase/seed.sql`'s 15 demo fixtures by FIXED ID (B113) — 7 leaderboard
--     chefs (...d1-...d7) and 8 taster accounts (...c1-...c8), plus everything
--     that cascades from them.
--   * `recipeData/_tools/ingest.mjs`'s impersonation accounts (B114) — every
--     `auth.users` row on the reserved `.invalid` TLD, the `kind = 'member'`
--     profile behind it, and the provenance-less recipes it posted as that real
--     named person's own work.
--   * Authored engagement counters on surviving recipes (B112) — recomputed
--     from the rows actually behind them rather than deleted, because the
--     recipe is real content and only its numbers were invented.
--
-- KEEPS, explicitly:
--   * Every `is_imported` recipe with real provenance — the captured corpus.
--   * Every `kind = 'imported'` profile the harvester created from a real
--     byline. Those hold no account and rank nowhere; they are credit, not
--     identity.
--   * `Secret Sauce Kitchen` (...aa) and its 14 curated recipes. A first-party
--     editorial account is not a fabricated chef.
--   * Every real signup, and the food registry.
--
-- ---------------------------------------------------------------------------
-- THE SAFETY MECHANISM IS A FIXED ID OR A RESERVED TLD, NEVER A GUESS
--
-- Same discipline as `9_sim_teardown.sql`. The demo fixtures are named by the
-- literal uuids `seed.sql` pins them at. The impersonation accounts are named
-- by `@corpus.invalid` — RFC 2606 reserves `.invalid` so that no real address
-- can ever exist there, which makes the pattern safe by construction rather
-- than by luck. Nothing below infers fakeness from a display name, a locale or
-- a creation date, because the cost of a false positive is deleting a real
-- person's account with no undo.
--
-- The pre-flight below turns that discipline into an abort: if the set about to
-- be deleted contains a single `is_imported` recipe or a single profile the
-- audit calls real, the transaction raises instead of proceeding.
-- ---------------------------------------------------------------------------

\if :{?confirm}
\else
\set confirm no
\endif

\set ON_ERROR_STOP on

\set kitchen '00000000-0000-0000-0000-0000000000aa'

begin;

-- ===========================================================================
-- 0. The target set, resolved once so the pre-flight and the deletes cannot
--    disagree about what is being removed.
-- ===========================================================================

create temporary table purge_profile (id uuid primary key, reason text not null);
create temporary table purge_account (id uuid primary key, reason text not null);

-- seed.sql's demo fixtures, by the fixed ids that file pins (B113).
insert into purge_profile (id, reason)
select p.id, 'seed.sql demo fixture'
from profiles p
where p.id in (
  '00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000c2',
  '00000000-0000-0000-0000-0000000000c3', '00000000-0000-0000-0000-0000000000c4',
  '00000000-0000-0000-0000-0000000000c5', '00000000-0000-0000-0000-0000000000c6',
  '00000000-0000-0000-0000-0000000000c7', '00000000-0000-0000-0000-0000000000c8',
  '00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000d2',
  '00000000-0000-0000-0000-0000000000d3', '00000000-0000-0000-0000-0000000000d4',
  '00000000-0000-0000-0000-0000000000d5', '00000000-0000-0000-0000-0000000000d6',
  '00000000-0000-0000-0000-0000000000d7'
)
on conflict (id) do nothing;

-- ingest.mjs's impersonation profiles, by reserved TLD (B114).
insert into purge_profile (id, reason)
select p.id, 'ingest.mjs impersonation of a real named chef'
from profiles p
join auth.users u on u.id = p.auth_user_id
where u.email like '%@corpus.invalid'
on conflict (id) do nothing;

-- The accounts behind them. `profiles.auth_user_id` carries no foreign key
-- since Phase 35b (an imported profile has no account), so deleting an
-- `auth.users` row does NOT cascade to its profile and vice versa — both sides
-- have to be named.
insert into purge_account (id, reason)
select u.id, 'account behind a purged profile'
from auth.users u
join purge_profile pp on pp.id = u.id
on conflict (id) do nothing;

insert into purge_account (id, reason)
select u.id, 'account behind a purged profile (claimed identity)'
from auth.users u
join profiles p on p.auth_user_id = u.id
join purge_profile pp on pp.id = p.id
on conflict (id) do nothing;

-- Fixture accounts that never got a profile, or whose profile id was
-- regenerated at some point. A password is a way in whether or not a profile
-- points at it. The Kitchen shares `@secretsauce.local` and is excluded by name.
insert into purge_account (id, reason)
select u.id, 'seed.sql fixture account'
from auth.users u
where (
        u.email like 'taster%@secretsauce.local'
        or u.email similar to 'chef[0-9]+@secretsauce.local'
        or u.email like '%@corpus.invalid'
      )
  and u.email <> 'kitchen@secretsauce.local'
on conflict (id) do nothing;

-- ===========================================================================
-- 1. PRE-FLIGHT — abort rather than delete something real
-- ===========================================================================

do $purge$
declare
  v_imported bigint;
  v_kitchen  bigint;
  v_real_imp bigint;
  v_recipes  bigint;
begin
  -- Not one captured recipe may be in the blast radius. `recipes.owner_id`
  -- cascades, so this is the check that stands between a fixture cleanup and
  -- deleting part of a 21k-row corpus.
  select count(*) into v_imported
  from recipes r join purge_profile pp on pp.id = r.owner_id
  where r.is_imported;

  if v_imported > 0 then
    raise exception
      'ABORT: % imported recipes would cascade from the profiles being purged',
      v_imported
      using hint = 'A captured recipe must never be owned by a fixture profile. '
                   'Investigate before re-running — do not widen the filter.';
  end if;

  -- The first-party editorial account is not a fixture.
  select count(*) into v_kitchen
  from purge_profile where id = '00000000-0000-0000-0000-0000000000aa'::uuid;
  if v_kitchen > 0 then
    raise exception 'ABORT: Secret Sauce Kitchen is in the purge set';
  end if;

  -- Nor is a harvester-created byline. Those hold no account, so nothing above
  -- should be able to select one; the check is here because the consequence of
  -- being wrong is 1,279 credits disappearing silently.
  select count(*) into v_real_imp
  from profiles p join purge_profile pp on pp.id = p.id
  where p.kind = 'imported' and p.auth_user_id is null;
  if v_real_imp > 0 then
    raise exception
      'ABORT: % harvester-created imported profiles are in the purge set', v_real_imp;
  end if;

  select count(*) into v_recipes
  from recipes r join purge_profile pp on pp.id = r.owner_id;

  raise notice 'purge pre-flight OK: % profiles, % accounts, % recipes to remove',
    (select count(*) from purge_profile),
    (select count(*) from purge_account),
    v_recipes;
end $purge$;

-- ===========================================================================
-- 2. CONFIRMATION
-- ===========================================================================

-- The gate is a psql-level branch, not a plpgsql `if`: psql substitutes
-- `:'confirm'` in ordinary SQL text but NOT inside a dollar-quoted body, so a
-- check written in plpgsql would send the literal string `:'confirm'` to the
-- server and fail to parse. `\gset` moves the decision out to a psql variable
-- that `\if` can read.
select (:'confirm' in ('yes', 'y', 'true')) as purge_confirmed
\gset

\if :purge_confirmed
\echo '-- confirmed, deleting --'
\else
\echo ''
\echo '!! purge_fake.sql REFUSED - nothing has been deleted.'
\echo '!! Re-run with: melos run db:purge:fake -- --yes'
\echo ''
do $purge$
begin
  raise exception 'purge_fake.sql requires confirmation'
    using hint = 'Pass --yes. Nothing was deleted; this transaction rolls back.';
end $purge$;
\endif

-- ===========================================================================
-- 3. DELETE
-- ===========================================================================

-- The `recipes_chef_stats` trigger recomputes a profile's aggregates once per recipe row
-- touched. Deleting a fixture chef's whole catalogue would fire it per recipe
-- against a profile that is about to disappear, so it is parked for the
-- duration and the survivors are recomputed from scratch at the end — the same
-- pattern the sim's bulk load and `approve_profile_claim()` use.
alter table recipes disable trigger recipes_chef_stats;

-- Engagement these fixtures left on recipes they did not own. Cascading the
-- profile would remove these anyway; doing it first and explicitly means the
-- surviving recipe's counters are corrected by the same recompute below rather
-- than left holding a vote from a deleted account.
delete from recipe_likes   where user_id in (select id from purge_profile);
delete from recipe_saves   where user_id in (select id from purge_profile);
delete from recipe_ratings where user_id in (select id from purge_profile);
delete from recipe_views   where user_id in (select id from purge_profile);

-- Profiles. Cascades to recipes (and through them to ingredient_groups,
-- ingredients, step_groups, steps, recipe_versions), plus shares, suggestions
-- and entity memberships.
delete from profiles where id in (select id from purge_profile);

-- Accounts last: nothing references them now.
delete from auth.users where id in (select id from purge_account);

alter table recipes enable trigger recipes_chef_stats;

-- ===========================================================================
-- 4. REPAIR THE AUTHORED COUNTERS (B112)
-- ===========================================================================

-- Every surviving recipe's counters are recomputed from the rows actually
-- behind them. For the curated 14 that takes `like_count` from an authored 412
-- to the 0 it has earned.
--
-- `like_count` and `save_count` are delta-maintained by `on_like_change()` /
-- `on_save_change()` through `bump_count()`, so no recompute-from-scratch
-- function exists for them and the statement below is the only copy of that
-- arithmetic. The RATING triple is different: `recompute_recipe_rating()` is
-- already the single source of truth for it, including the `round(…, 2)` and
-- the `cnt = 0 -> 0` case that `rating_avg`'s not-null constraint requires. It
-- is called rather than restated, for the same reason `chef_score()` is never
-- restated outside SQL (Gotcha 19) — a second copy of a formula is a second
-- formula.
update recipes r
set like_count = c.likes,
    save_count = c.saves
from (
  select r2.id,
         (select count(*)::int from recipe_likes l where l.recipe_id = r2.id) as likes,
         (select count(*)::int from recipe_saves v where v.recipe_id = r2.id) as saves
  from recipes r2
) c
where c.id = r.id
  and (r.like_count, r.save_count) is distinct from (c.likes, c.saves);

do $purge$
declare
  v_id    uuid;
  v_fixed int := 0;
begin
  for v_id in
    select r.id
    from recipes r
    cross join lateral (
      select count(*)::int as cnt, coalesce(sum(g.rating), 0) as total
      from recipe_ratings g where g.recipe_id = r.id
    ) s
    where r.rating_count <> s.cnt or r.rating_sum <> s.total
  loop
    perform recompute_recipe_rating(v_id);
    v_fixed := v_fixed + 1;
  end loop;
  raise notice '  rating triples recomputed: %', v_fixed;
end $purge$;

-- `view_count` is monotonic and never recomputed on a real database (Gotcha
-- 10), so it is corrected ONLY where it is unambiguously authored: a positive
-- counter with **no `recipe_views` rows at all**. The counter only ever moves on
-- a signed-in viewer's first row, and nothing deletes that row afterwards, so an
-- empty log under a positive counter cannot have been produced by any code path.
--
-- The tempting predicate is "no row with a NON-NULL user_id", and it is wrong:
-- `recipe_views.user_id` is `on delete set null`, so a real recipe viewed by
-- three signed-in users who later deleted their accounts has three rows with
-- null user_ids, a legitimate `view_count` of 3, and would be silently zeroed by
-- it. A recipe whose log holds only null user_ids is genuinely ambiguous —
-- anonymous views (which never counted) look identical to deleted accounts
-- (which did) — so it is left alone. Under-correcting a counter that is
-- documented as an upper bound is the cheap mistake here; deleting real
-- engagement is not.
update recipes r
set view_count = 0
where r.view_count > 0
  and not exists (select 1 from recipe_views v where v.recipe_id = r.id);

-- ===========================================================================
-- 5. RECOMPUTE THE DERIVED CHEF AGGREGATES
-- ===========================================================================

-- The trigger was parked for the deletes, and the counter repair above bypassed
-- it as well, so every surviving profile's score, tier and public recipe count
-- is restated from scratch here. This is `chef_score()` / `chef_tier_for()`
-- doing the arithmetic — the formula is never restated outside them (Gotcha 19).
select recompute_all_chef_stats();

-- ===========================================================================
-- 6. REPORT
-- ===========================================================================

do $purge$
begin
  raise notice 'purge complete';
  raise notice '  profiles remaining: % (% imported, % member)',
    (select count(*) from profiles),
    (select count(*) from profiles where kind = 'imported'),
    (select count(*) from profiles where kind = 'member');
  raise notice '  recipes remaining: % (% imported, % first-party)',
    (select count(*) from recipes),
    (select count(*) from recipes where is_imported),
    (select count(*) from recipes where not is_imported);
  raise notice '  accounts remaining: %', (select count(*) from auth.users);
  raise notice 'verify with: melos run db:audit';
end $purge$;

drop table purge_profile;
drop table purge_account;

commit;
