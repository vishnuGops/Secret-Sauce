-- schema_fingerprint.sql — a stable, sorted inventory of the `public` schema.
--
-- READ-ONLY. Safe against the hosted project.
--
-- Why this exists: the hosted project has no `supabase_migrations.schema_migrations`
-- table (it was applied by hand through psql, not by `supabase db push`), so there
-- is nothing that records which version of `0001_init.sql` it is carrying. Gotcha 5
-- says an edited baseline is silently wrong once a database you do not control has
-- it; this file is how we tell whether hosted has drifted from the repo without
-- trusting a version number that does not exist.
--
-- The comparison is a catalogue inventory rather than a `pg_dump` diff on purpose:
-- pg_dump output reorders, re-wraps and re-quotes between client versions, so it
-- produces noise diffs that hide the one real change. Every row here is a fact the
-- app depends on — a column and its type, a function and its arity, a policy and
-- its command, a grant, an index, a trigger, an enum label.
--
-- Deliberately NOT fingerprinted: function BODIES. They are 231 KB of text whose
-- whitespace changes constantly, and a body change with no signature change cannot
-- break a caller the way a dropped column or a missing policy can. Re-applying
-- `0001_init.sql` is idempotent and cheap, so the answer to "did a body change?" is
-- to re-apply, not to diff.
--
-- Usage — run against both databases and diff the two outputs:
--   melos run db:hosted:check
-- or by hand:
--   docker run --rm -v "<repo>/supabase:/sql:ro" postgres:17-alpine \
--     psql "$env:SUPABASE_DB_URL" -t -A -f /sql/scripts/schema_fingerprint.sql

\pset pager off
\pset tuples_only on
\pset format unaligned

-- Tables ---------------------------------------------------------------------
select 'table|' || table_name
from information_schema.tables
where table_schema = 'public' and table_type = 'BASE TABLE'
order by 1;

-- Columns: name, type, nullability, default presence ------------------------
-- The default is reduced to a boolean because `gen_random_uuid()` and `now()`
-- render differently across server versions while meaning the same thing.
select 'column|' || table_name || '.' || column_name
       || '|' || data_type
       || '|' || is_nullable
       || '|' || case when column_default is null then 'nodefault' else 'default' end
from information_schema.columns
where table_schema = 'public'
order by 1;

-- Enum types and their labels, in declaration order --------------------------
select 'enum|' || t.typname || '|' || e.enumlabel
from pg_type t
join pg_enum e on e.enumtypid = t.oid
join pg_namespace n on n.oid = t.typnamespace
where n.nspname = 'public'
order by t.typname, e.enumsortorder;

-- Functions: name, arity, argument types, volatility, security --------------
-- `prosecdef` is in here because Gotcha 3 and B092 both turn on it: a function
-- that silently stops being `security definer` reads an empty table and reports
-- a plausible number.
select 'function|' || p.proname
       || '|' || p.pronargs
       || '|' || pg_get_function_identity_arguments(p.oid)
       || '|' || case p.provolatile when 'i' then 'immutable'
                                    when 's' then 'stable'
                                    else 'volatile' end
       || '|' || case when p.prosecdef then 'definer' else 'invoker' end
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  -- Extension-owned functions (pgcrypto etc.) are not ours and land in whichever
  -- schema the extension was created in, which differs between the local stack
  -- and hosted for historical reasons. Exclude them or every run shows 60 diffs.
  and not exists (
    select 1 from pg_depend d
    where d.objid = p.oid and d.deptype = 'e'
  )
order by 1;

-- RLS: is it enabled, and which policies exist -------------------------------
select 'rls|' || c.relname || '|' || case when c.relrowsecurity then 'on' else 'OFF' end
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r'
order by 1;

select 'policy|' || tablename || '|' || policyname || '|' || cmd
       || '|' || coalesce(array_to_string(roles, ','), '')
from pg_policies
where schemaname = 'public'
order by 1;

-- Grants: the other half of authorization (Gotcha 4), including the COLUMN-level
-- grants that OPT-S1 introduced for `recipes` and `profiles`.
--
-- Narrowed to SELECT/INSERT/UPDATE/DELETE: TRUNCATE, TRIGGER and REFERENCES come
-- from Supabase's project-level `alter default privileges grant all on tables`,
-- not from 0001_init.sql, so they are present on any Supabase database and absent
-- on a plain `create database`. Including them makes every run show noise that
-- hides the one grant that actually went missing.
select 'grant|' || table_name || '|' || grantee || '|' || privilege_type
from information_schema.role_table_grants
where table_schema = 'public' and grantee in ('anon', 'authenticated', 'service_role')
  and privilege_type in ('SELECT', 'INSERT', 'UPDATE', 'DELETE')
order by 1;

select 'colgrant|' || table_name || '.' || column_name || '|' || grantee || '|' || privilege_type
from information_schema.column_privileges
where table_schema = 'public' and grantee in ('anon', 'authenticated', 'service_role')
  and privilege_type in ('SELECT', 'INSERT', 'UPDATE', 'DELETE')
order by 1;

-- Function EXECUTE grants: a `security definer` helper that PostgREST can reach
-- as an RPC is the Gotcha 3 failure, so who may execute what is load-bearing.
select 'fngrant|' || p.proname || '|' || p.pronargs || '|' || a.grantee
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) ax
join lateral (select pg_get_userbyid(ax.grantee) as grantee) a on true
where n.nspname = 'public'
  and ax.privilege_type = 'EXECUTE'
  and a.grantee in ('anon', 'authenticated', 'service_role', 'public')
  and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
order by 1;

-- Indexes: Gotcha 4's "a new FK column needs its own index, in the same change"
select 'index|' || tablename || '|' || indexname
from pg_indexes
where schemaname = 'public'
order by 1;

-- Triggers: the counters, the search vector and the version bump all live here
select 'trigger|' || c.relname || '|' || t.tgname
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and not t.tgisinternal
order by 1;

-- Constraints: name + type. Gotcha 5's constraint form means a widened `check`
-- under an existing name is a silent no-op, so the name alone is not enough --
-- but a MISSING constraint is exactly what this catches.
select 'constraint|' || c.relname || '|' || con.conname || '|' || con.contype::text
from pg_constraint con
join pg_class c on c.oid = con.conrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
order by 1;
