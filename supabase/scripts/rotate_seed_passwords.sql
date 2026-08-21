-- Rotate the passwords of every account seed.sql creates (B018 / OPT-S8).
--
-- WHY THIS EXISTS
-- Before the B018 fix, `seed.sql` wrote **literal** passwords into the file
-- (`crypt('<literal>', gen_salt('bf'))`) with `email_confirmed_at` pre-set, and
-- README documented pasting that file into the hosted dashboard. Following the
-- project's own instructions therefore created nine confirmed, log-in-able
-- production accounts whose credentials were committed to the repo and are
-- still recoverable from git history.
--
-- The seed itself is fixed — it randomises now — but a database seeded *before*
-- that fix keeps the old hashes forever: every account insert is
-- `on conflict (id) do nothing`, so re-running the corrected seed changes
-- nothing, and `drop.sql` deliberately spares `auth.users` so `db:reset` cannot
-- clear them either. This script is the one thing that closes them.
--
-- ROTATE, DO NOT DELETE. `profiles.id` references `auth.users` on delete
-- cascade and `recipes.owner_id` references `profiles` the same way, so
-- deleting `…aa` would take the Secret Sauce Kitchen's 14 curated recipes with
-- it, and deleting the tasters would remove the demo ratings. Nothing ever
-- signs in as these accounts — they exist only to satisfy the FK — so a random
-- password no one holds is the correct end state, exactly what a fresh seed
-- produces today.
--
-- Targeted by the seed's **fixed UUIDs**, never by an email or id pattern: the
-- teardown-scope rule (review checklist §8) applies to anything that touches
-- `auth.users`, and a subtly wrong pattern on the hosted project has no undo.
-- Idempotent and safe to re-run; each run installs a different random password.
--
-- USAGE (hosted — this is the whole point of the script):
--   . .\db-url.local.ps1            # with the hosted line uncommented
--   Get-Content supabase\scripts\rotate_seed_passwords.sql -Raw |
--     docker exec -i supabase_db_secret-sauce psql $env:SUPABASE_DB_URL -v ON_ERROR_STOP=1 -f -
--
-- Verify afterwards with the check at the bottom: it must report 0 accounts
-- still matching any of the historical passwords you pass it.

create extension if not exists pgcrypto;

do $$
declare
  v_ids uuid[] := array[
    -- the eight demo "taster" accounts
    '00000000-0000-0000-0000-0000000000c1',
    '00000000-0000-0000-0000-0000000000c2',
    '00000000-0000-0000-0000-0000000000c3',
    '00000000-0000-0000-0000-0000000000c4',
    '00000000-0000-0000-0000-0000000000c5',
    '00000000-0000-0000-0000-0000000000c6',
    '00000000-0000-0000-0000-0000000000c7',
    '00000000-0000-0000-0000-0000000000c8',
    -- the Secret Sauce Kitchen system account (owns the curated recipes)
    '00000000-0000-0000-0000-0000000000aa',
    -- the seven demo chef accounts (added after B018; rotated for parity so a
    -- single run leaves no seeded account with an author-chosen password)
    '00000000-0000-0000-0000-0000000000d1',
    '00000000-0000-0000-0000-0000000000d2',
    '00000000-0000-0000-0000-0000000000d3',
    '00000000-0000-0000-0000-0000000000d4',
    '00000000-0000-0000-0000-0000000000d5',
    '00000000-0000-0000-0000-0000000000d6',
    '00000000-0000-0000-0000-0000000000d7'
  ];
  v_rotated int;
  v_missing int;
begin
  update auth.users
     set encrypted_password = crypt(gen_random_uuid()::text, gen_salt('bf')),
         updated_at         = now()
   where id = any(v_ids);
  get diagnostics v_rotated = row_count;

  select cardinality(v_ids) - v_rotated into v_missing;

  raise notice 'B018 rotation: % of % seeded accounts rotated (% not present in this database)',
    v_rotated, cardinality(v_ids), v_missing;

  if v_rotated = 0 then
    raise notice 'Nothing to do — none of the seeded accounts exist here.';
  end if;
end $$;

-- Verification. Replace the literals with the historical passwords recovered
-- from git history and re-run; every count must be 0. Left commented so the
-- script never reintroduces a credential into the repo — which is the whole
-- reason B018 was filed.
--
-- select count(*) as still_matching
--   from auth.users
--  where encrypted_password = crypt('<old-password>', encrypted_password);
