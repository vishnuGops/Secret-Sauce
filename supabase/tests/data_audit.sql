-- data_audit.sql — classify every profile, recipe and account as REAL or FAKE.
--
-- READ-ONLY. Writes nothing, creates only temporary tables, and is safe to run
-- against any database including the hosted project. `melos run db:audit`.
--
-- ---------------------------------------------------------------------------
-- WHY THIS EXISTS
--
-- Three separate mechanisms had put fabricated rows in front of a reader, and
-- none of them was visible from the app:
--
--   * B112 — curated recipes carried authored engagement. `recipeData/*.json`
--     had a `demo` block that compiled `like_count = 412` into
--     `seed_recipes.sql` with zero `recipe_likes` rows behind it.
--   * B113 — `supabase/seed.sql`'s 15 demo accounts (7 leaderboard chefs, 8
--     tasters) were applied by `db:reset` and by `config.toml`, so every
--     developer database and the hosted project ranked invented chefs.
--   * B114 — `recipeData/_tools/ingest.mjs` created a real, log-in-able
--     `auth.users` account per corpus chef and posted scraped recipes as that
--     chef's own work: 15 named people, `kind = 'member'`, on the leaderboard,
--     with no provenance on any of the 158 recipes.
--
-- Each was found by looking, not by a failing test. This file is the test.
--
-- ---------------------------------------------------------------------------
-- THE CLASSIFICATION RULE: POSITIVE EVIDENCE, NEVER A GUESS
--
-- Every FAKE bucket below is proved by something the creating code wrote down,
-- in this order of preference:
--
--   1. A REGISTRY. `sim.actor` / `sim.recipe` / `sim.imported_profile` are the
--      rows the generator wrote as it created each row. This is the same
--      mechanism `9_sim_teardown.sql` is built on and for the same reason: a
--      pattern like `email like '%@sim.%'` deletes a real account the day
--      someone signs up with an unlucky address.
--   2. A FIXED ID. `seed.sql` pins its 15 accounts at literal uuids
--      (...c1-...c8, ...d1-...d7), so they are identifiable without a pattern.
--   3. A RESERVED TLD. `@corpus.invalid` (RFC 2606 `.invalid`) and
--      `https://example.test/` (RFC 6761 `.test`) cannot be held or served by
--      anyone, ever. A match is therefore safe by construction, not by luck —
--      this is the only place a pattern is acceptable and the reason is the
--      reservation, not the string.
--   4. AN ARITHMETIC CONTRADICTION. See the engagement section below.
--
-- Nothing here infers fakeness from a name, a locale, a creation date or a
-- round-looking number. A rule that cannot point at one of the four above does
-- not belong in this file, because the cost of a false positive is
-- `purge_fake.sql` deleting a real person's account.
--
-- ---------------------------------------------------------------------------
-- THE ENGAGEMENT CONTRADICTION, AND WHY VIEWS ARE EXEMPT
--
-- `recipes.like_count`, `save_count` and `rating_count` are recomputed FROM
-- SCRATCH by their triggers over `recipe_likes` / `recipe_saves` /
-- `recipe_ratings`. So a counter that disagrees with the number of rows behind
-- it was written by hand, and that is a contradiction rather than a heuristic.
-- Measured on this schema the rule has zero false positives: 21,314 corpus
-- recipes and 452 sim recipes all agree exactly, while it catches precisely the
-- 6 curated recipes that had a `demo` block and the 7 seeded demo chefs.
--
-- `view_count` is NOT checked and must not be. Per CLAUDE.md Gotcha 10 it is a
-- deliberate upper bound on distinct signed-in viewers: anonymous rows are
-- never counted, the counter is monotonic, and `recipe_views.user_id` is
-- `on delete set null`, so a deleted account leaves its contribution behind. A
-- legitimate recipe's `view_count` routinely exceeds its log. Checking it would
-- flag real rows, which is how an audit stops being trusted.
-- ---------------------------------------------------------------------------

\if :{?strict}
\else
\set strict off
\endif

\set ON_ERROR_STOP on
\timing off

select set_config('audit.strict', :'strict', false);

-- The Secret Sauce Kitchen system account. First-party publisher of the 14
-- curated recipes — a real editorial identity, not a fabricated chef, and the
-- one seeded account that is deliberately kept.
\set kitchen '00000000-0000-0000-0000-0000000000aa'

create temporary table audit_profile (
  id      uuid primary key,
  bucket  text not null,
  fake    boolean not null,
  detail  text
);

create temporary table audit_recipe (
  id      uuid primary key,
  bucket  text not null,
  fake    boolean not null,
  detail  text
);

create temporary table audit_account (
  id      uuid primary key,
  bucket  text not null,
  fake    boolean not null,
  detail  text
);

-- ===========================================================================
-- 1. FAKE PROFILES
-- ===========================================================================

-- 1a. The simulated population, by registry. Guarded on the schema existing at
-- all: a database that has never run `db:sim` has no `sim` schema, and a static
-- reference to `sim.actor` would make this whole file fail to parse there.
do $audit$
begin
  if to_regclass('sim.actor') is not null then
    insert into audit_profile (id, bucket, fake, detail)
    select a.id, 'sim-actor', true, 'sim.actor persona=' || a.persona
    from sim.actor a
    where exists (select 1 from profiles p where p.id = a.id)
    on conflict (id) do nothing;
  end if;

  -- The sim's own imported-corpus fixture (a Phase 35c preview): profiles with
  -- kind = 'imported' that the generator invented, distinct from the real
  -- bylines the harvester captured. Registry-tracked, so the two never blur.
  if to_regclass('sim.imported_profile') is not null then
    insert into audit_profile (id, bucket, fake, detail)
    select ip.id, 'sim-imported', true, 'sim.imported_profile'
    from sim.imported_profile ip
    where exists (select 1 from profiles p where p.id = ip.id)
    on conflict (id) do nothing;
  end if;
end $audit$;

-- 1b. seed.sql's demo fixtures, by fixed id (B113). Kept out of every default
-- apply path now, but a database seeded before that change still holds them.
insert into audit_profile (id, bucket, fake, detail)
select p.id, 'demo-seed', true,
       'supabase/seed.sql fixed-id fixture (' || p.display_name || ')'
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

-- 1c. ingest.mjs's impersonation accounts (B114). The severity here is not
-- "fake data" — it is that a real named person has a signed-in identity on this
-- database that they did not create, holding recipes credited as their own.
insert into audit_profile (id, bucket, fake, detail)
select p.id, 'impersonation', true,
       'ingest.mjs account for a real named chef: ' || u.email
from profiles p
join auth.users u on u.id = p.auth_user_id
where u.email like '%@corpus.invalid'
on conflict (id) do nothing;

-- ===========================================================================
-- 2. REAL PROFILES — everything the rules above did not name
-- ===========================================================================

insert into audit_profile (id, bucket, fake, detail)
select p.id,
       case
         when p.id = :'kitchen'::uuid   then 'kitchen'
         when p.merged_into is not null then 'claim-tombstone'
         when p.kind = 'imported'       then 'imported-real'
         else 'member-real'
       end,
       false,
       case
         when p.id = :'kitchen'::uuid then 'first-party editorial account'
         when p.kind = 'imported'     then 'byline captured by the harvester'
         else null
       end
from profiles p
on conflict (id) do nothing;

-- ===========================================================================
-- 3. RECIPES
-- ===========================================================================

-- 3a. Simulated, by registry. Includes the rows the sim marks
-- `is_imported = true` for its corpus fixture, which is exactly why the
-- registry is consulted BEFORE the flag: `is_imported` alone is not evidence of
-- provenance, because the sim sets it too.
do $audit$
begin
  if to_regclass('sim.recipe') is not null then
    insert into audit_recipe (id, bucket, fake, detail)
    select s.id, 'sim-recipe', true, 'sim.recipe'
    from sim.recipe s
    where exists (select 1 from recipes r where r.id = s.id)
    on conflict (id) do nothing;
  end if;
end $audit$;

-- 3b. Owned by a profile already proved fake.
insert into audit_recipe (id, bucket, fake, detail)
select r.id, 'owned-by-' || ap.bucket, true, ap.detail
from recipes r
join audit_profile ap on ap.id = r.owner_id and ap.fake
on conflict (id) do nothing;

-- 3c. Marked imported but carrying no provenance at all. Nothing should be able
-- to produce this: `import_recipe()` writes `source_url` in the same statement
-- it sets the flag. A row here means something else wrote the flag.
insert into audit_recipe (id, bucket, fake, detail)
select r.id, 'import-without-provenance', true,
       'is_imported with source_url, source_name and source_entity_id all null'
from recipes r
where r.is_imported
  and r.source_url is null
  and r.source_name is null
  and r.source_entity_id is null
on conflict (id) do nothing;

-- 3d. Provenance pointing at a reserved TLD — a fabricated citation. Caught
-- here as well as by the registry so the check survives a dropped `sim` schema.
--
-- Anchored on the HOST rather than matched anywhere in the string: a bare
-- `like '%.invalid/%'` would also call a real URL fabricated for having a path
-- segment that happens to end `.invalid/`. `split_part(url, '/', 3)` is the
-- authority component of `scheme://host/path`, so the suffix test applies to
-- the hostname only — which is the thing the RFCs actually reserve.
insert into audit_recipe (id, bucket, fake, detail)
select r.id, 'fabricated-provenance', true,
       'source_url on a reserved TLD: ' || r.source_url
from recipes r
where r.source_url like '%://%'
  and (
        split_part(r.source_url, '/', 3) like '%.test'
     or split_part(r.source_url, '/', 3) like '%.invalid'
     or split_part(r.source_url, '/', 3) like '%.test:%'
     or split_part(r.source_url, '/', 3) like '%.invalid:%'
      )
on conflict (id) do nothing;

-- 3e. AUTHORED ENGAGEMENT: a counter the triggers would not have produced.
-- Reported separately from the buckets above so each row is counted once and
-- the finding is actionable on its own — a real recipe lands here if somebody
-- hand-edits a counter, which is the case this check exists to catch in future.
insert into audit_recipe (id, bucket, fake, detail)
select r.id, 'authored-engagement', true,
       'counters disagree with the rows behind them:'
       || case when r.like_count <> c.likes
               then ' like_count=' || r.like_count || ' rows=' || c.likes else '' end
       || case when r.save_count <> c.saves
               then ' save_count=' || r.save_count || ' rows=' || c.saves else '' end
       || case when r.rating_count <> c.ratings
               then ' rating_count=' || r.rating_count || ' rows=' || c.ratings else '' end
from recipes r
cross join lateral (
  select (select count(*) from recipe_likes   l where l.recipe_id = r.id) as likes,
         (select count(*) from recipe_saves   v where v.recipe_id = r.id) as saves,
         (select count(*) from recipe_ratings g where g.recipe_id = r.id) as ratings
) c
where r.like_count   <> c.likes
   or r.save_count   <> c.saves
   or r.rating_count <> c.ratings
on conflict (id) do nothing;

-- 3f. Real recipes — everything left.
insert into audit_recipe (id, bucket, fake, detail)
select r.id,
       case
         when r.is_imported                 then 'corpus-real'
         when r.owner_id = :'kitchen'::uuid then 'curated'
         else 'member-real'
       end,
       false,
       null
from recipes r
on conflict (id) do nothing;

-- ===========================================================================
-- 4. ACCOUNTS — auth.users is the row with a password on it, so it gets its own
-- pass rather than being inferred from profiles. A fake account with no profile
-- is still a way in.
-- ===========================================================================

do $audit$
begin
  if to_regclass('sim.actor') is not null then
    insert into audit_account (id, bucket, fake, detail)
    select a.id, 'sim-actor', true, 'sim.actor'
    from sim.actor a
    where exists (select 1 from auth.users u where u.id = a.id)
    on conflict (id) do nothing;
  end if;
end $audit$;

insert into audit_account (id, bucket, fake, detail)
select u.id, 'impersonation', true, 'ingest.mjs (B114): ' || u.email
from auth.users u
where u.email like '%@corpus.invalid'
on conflict (id) do nothing;

-- The email patterns here are a SECOND opinion beside the fixed-id list, not
-- the primary rule: `@secretsauce.local` is a non-routable name this repo owns,
-- and a fixture whose id was regenerated at some point would otherwise go
-- unnoticed. The Kitchen shares that domain and is excluded by name.
insert into audit_account (id, bucket, fake, detail)
select u.id, 'demo-seed', true, 'supabase/seed.sql fixture: ' || u.email
from auth.users u
where (
        u.id in (select ap.id from audit_profile ap where ap.bucket = 'demo-seed')
        or u.email like 'taster%@secretsauce.local'
        or u.email similar to 'chef[0-9]+@secretsauce.local'
      )
  and u.email <> 'kitchen@secretsauce.local'
on conflict (id) do nothing;

insert into audit_account (id, bucket, fake, detail)
select u.id,
       case when u.id = :'kitchen'::uuid then 'kitchen' else 'real-signup' end,
       false, u.email
from auth.users u
on conflict (id) do nothing;

-- ===========================================================================
-- 5. REPORT
-- ===========================================================================

\echo ''
\echo '================ DATA AUDIT ================'
\echo ''
\echo '-- profiles --'
select bucket, count(*) as n, case when fake then 'FAKE' else 'real' end as verdict
from audit_profile group by bucket, fake order by fake desc, n desc;

\echo '-- recipes --'
select bucket, count(*) as n, case when fake then 'FAKE' else 'real' end as verdict
from audit_recipe group by bucket, fake order by fake desc, n desc;

\echo '-- accounts (auth.users) --'
select bucket, count(*) as n, case when fake then 'FAKE' else 'real' end as verdict
from audit_account group by bucket, fake order by fake desc, n desc;

\echo '-- impersonation detail (B114) — every one of these is a real person --'
select ap.detail, count(r.id) as recipes
from audit_profile ap
left join recipes r on r.owner_id = ap.id
where ap.bucket = 'impersonation'
group by ap.detail order by ap.detail;

\echo '-- ranked surfaces: is anything fake reachable from the leaderboard? --'
select count(*) as fake_profiles_on_leaderboard
from audit_profile ap
join profiles p on p.id = ap.id
where ap.fake and p.kind = 'member' and p.public_recipe_count > 0;

\echo ''

-- ===========================================================================
-- 6. VERDICT
-- ===========================================================================

do $audit$
declare
  v_p      bigint;
  v_r      bigint;
  v_a      bigint;
  v_board  bigint;
  v_strict boolean := coalesce(current_setting('audit.strict', true), 'off')
                        in ('on', 'true', 'yes', '1');
begin
  select count(*) into v_p from audit_profile where fake;
  select count(*) into v_r from audit_recipe  where fake;
  select count(*) into v_a from audit_account where fake;
  select count(*) into v_board
  from audit_profile ap join profiles p on p.id = ap.id
  where ap.fake and p.kind = 'member' and p.public_recipe_count > 0;

  if v_p = 0 and v_r = 0 and v_a = 0 then
    raise notice 'AUDIT CLEAN — no fabricated profile, recipe or account found';
    return;
  end if;

  raise notice 'AUDIT FOUND FABRICATED DATA: % profiles, % recipes, % accounts',
    v_p, v_r, v_a;
  if v_board > 0 then
    raise notice '  of which % are ranked on the chef leaderboard right now', v_board;
  end if;
  raise notice '  remove it with: melos run db:purge:fake -- --yes';

  if v_strict then
    raise exception
      'data audit failed in strict mode: % fake profiles, % fake recipes, % fake accounts',
      v_p, v_r, v_a
      using hint = 'A default apply path must not create fabricated rows. '
                   'Run `melos run db:audit` for the per-bucket breakdown.';
  end if;
end $audit$;

drop table audit_profile;
drop table audit_recipe;
drop table audit_account;
