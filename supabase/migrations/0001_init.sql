-- 0001_init.sql — Secret-Sauce schema BASELINE
--
-- Enums, tables, indexes, triggers, functions, Row-Level Security, storage
-- buckets, and the discovery / chefs / fork / save RPCs. Idempotent: this is
-- what a fresh database is built from, and re-running it is safe.
--
-- **Editable while the project is pre-release — owner's call, 2026-08-23.**
-- Nothing outside this machine depends on the schema yet, so a change goes
-- HERE, idempotently, rather than into a `0002_*.sql`. Phase 26's three Discover
-- shelves were folded back in on that basis. Every statement stays guarded
-- (`if not exists`, `create or replace`, `drop policy if exists`) because the
-- file is applied over itself constantly.
--
-- **This stops the moment the schema ships to a database that is not ours.**
-- Two things change on that day, and both bite silently:
--   1. The Supabase CLI records applied versions in
--      `supabase_migrations.schema_migrations` and NEVER re-runs a recorded one,
--      so an edit here would simply not reach that database — and the deploy
--      would report success.
--   2. Re-applying this file re-runs its two whole-table backfills (the
--      `profiles` B015 backfill and `recompute_all_chef_stats()` at the end),
--      which cost ~110 ms per 1,000 profiles here and grow with the table.
-- From then on the rule is the OPT-A9 one: a new `NNNN_*.sql` per change.
--
-- The rules for that file (numbering, guards, the B024 drop discipline,
-- grants-with-the-table, upgrade-path verification) are in
-- `supabase/migrations/README.md`.

-- ============================================================================
-- Extensions
-- ============================================================================
create extension if not exists "pgcrypto";      -- gen_random_uuid()
create extension if not exists "pg_trgm";       -- search_foods typeahead (Phase 29)

-- ============================================================================
-- Enums (guarded so the script can be re-run)
-- ============================================================================
do $$ begin
  if not exists (select 1 from pg_type where typname = 'difficulty') then
    create type difficulty as enum ('easy', 'medium', 'hard');
  end if;
  if not exists (select 1 from pg_type where typname = 'recipe_visibility') then
    create type recipe_visibility as enum ('private', 'public');
  end if;
  if not exists (select 1 from pg_type where typname = 'share_permission') then
    create type share_permission as enum ('view', 'edit');          -- 'edit' reserved
  end if;
  if not exists (select 1 from pg_type where typname = 'suggestion_status') then
    create type suggestion_status as enum ('open', 'accepted', 'rejected');
  end if;
  if not exists (select 1 from pg_type where typname = 'chef_tier') then
    create type chef_tier as enum
      ('home_cook', 'line_cook', 'sous_chef', 'head_chef', 'master_chef');
  end if;
  -- Phase 35b. A `profiles` row is no longer 1:1 with `auth.users`: an
  -- `imported` profile is a chef credited by the corpus who has never signed up
  -- and has no account to sign in with. `member` is everyone who did.
  if not exists (select 1 from pg_type where typname = 'profile_kind') then
    create type profile_kind as enum ('member', 'imported');
  end if;
  -- Phase 35b. The group that PUBLISHED a recipe, as opposed to the person who
  -- cooked it. This is Phase 25's `restaurants` generalised: the corpus needs an
  -- attribution entity for 560 publishers and the north star needs a restaurant
  -- entity, and they are the same table with a discriminator.
  if not exists (select 1 from pg_type where typname = 'entity_kind') then
    create type entity_kind as enum
      ('restaurant', 'brand', 'publication', 'community', 'chef_site');
  end if;
  -- Phase 35b. A real chef asking to take over the `imported` profile that
  -- credits them.
  if not exists (select 1 from pg_type where typname = 'claim_status') then
    create type claim_status as enum ('pending', 'approved', 'rejected');
  end if;
  -- Phase 35b. Who may act on an entity. Deliberately the same two values
  -- Phase 25 designed for `restaurant_role`, under the generalised name.
  if not exists (select 1 from pg_type where typname = 'entity_role') then
    create type entity_role as enum ('owner', 'chef');
  end if;
  -- Phase 35c. How much of an imported recipe may be shown, per row, so a
  -- publisher's objection is a data change rather than a deploy. `functional`
  -- is ingredients + steps + credit + link; `link_only` is the title and the
  -- link and nothing else; `blocked` is not rendered at all and exists so a
  -- takedown can be honoured without deleting the row that records it.
  if not exists (select 1 from pg_type where typname = 'rights_mode') then
    create type rights_mode as enum ('functional', 'link_only', 'blocked');
  end if;
  -- Phase 35c. Whether the cover may be shown from the publisher's own address.
  -- There is deliberately no `copy` or `proxy` value: a proxy is a copy on our
  -- infrastructure wearing a link's clothes, and an enum with no word for it is
  -- a decision enforced rather than remembered.
  if not exists (select 1 from pg_type where typname = 'image_mode') then
    create type image_mode as enum ('hotlink', 'none');
  end if;
end $$;

-- ============================================================================
-- Tables
-- ============================================================================

-- profiles — the ONE identity table. **No longer 1:1 with `auth.users`**
-- (Phase 35b).
--
-- It used to be: `id` was a foreign key to `auth.users(id)`, so a profile could
-- not exist without an account and every RLS policy in this file could compare
-- `owner_id = auth.uid()` directly. That equality is what had to give. The
-- corpus credits 19,681 named chefs who never signed up, and turning each into
-- an `auth.users` row would mint 19,681 accounts — with an email address, a
-- password-reset surface and a login — for people who did not ask for one.
--
-- The replacement is one nullable link, `auth_user_id`, and the migration is a
-- **no-op for every row that already exists**: the backfill below sets
-- `auth_user_id = id` for everyone, and `handle_new_user` keeps writing
-- `id = new.id` for real signups, so for a member the profile id and the auth
-- uid stay equal forever. Only imported profiles have an id that is not an auth
-- uid, and they have no `auth_user_id` at all.
--
-- The cascade moved with the link rather than being dropped: deleting an
-- `auth.users` row still deletes that member's profile and, through it, their
-- recipes. That is the promise the privacy policy makes (Phase 35a) and it
-- survives the decoupling unchanged. An imported profile has no auth row, so
-- nothing upstream can delete it — removal is a takedown, handled explicitly.
create table if not exists profiles (
  id           uuid primary key default gen_random_uuid(),
  display_name text not null default '',
  avatar_url   text,
  bio          text,
  created_at   timestamptz not null default now()
);

-- `default gen_random_uuid()` on an EXISTING database (B109). The create above
-- carries it, but `create table if not exists` does nothing when the table is
-- already there — so on every database built before Phase 35b, `profiles.id`
-- still has no default and any insert that does not name an id fails
-- `not-null`. Nothing noticed for two commits because every existing writer
-- supplies an id: `handle_new_user` writes the auth uid, the seed files write
-- fixed uuids, the sim writes `sim.uid(...)`. `import_recipe` is the first
-- caller that legitimately wants the database to mint one, and it failed on the
-- upgrade path while passing on a fresh one — Gotcha 6, exactly.
alter table profiles alter column id set default gen_random_uuid();

-- The Phase 35b columns, added via `alter` so a database built by an earlier
-- apply of this file picks them up on a re-run (Gotcha 5).
alter table profiles add column if not exists auth_user_id uuid;
alter table profiles add column if not exists kind profile_kind not null default 'member';
alter table profiles add column if not exists claimed_at timestamptz;
alter table profiles add column if not exists merged_into uuid;

-- Drop the old `profiles.id -> auth.users(id)` foreign key if this database
-- still has it. Guarded by catalogue lookup rather than name alone, because the
-- whole point is that the constraint must be GONE — a rename would not save us,
-- and unlike the `check` constraints below (Gotcha 5's constraint form) there is
-- no predicate here to widen, only a link to remove.
do $$
declare
  c record;
begin
  for c in
    select con.conname
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace nsp on nsp.oid = rel.relnamespace
    where nsp.nspname = 'public'
      and rel.relname = 'profiles'
      and con.contype = 'f'
      and con.conkey = array[
            (select attnum from pg_attribute
              where attrelid = con.conrelid and attname = 'id')
          ]::smallint[]
  loop
    execute format('alter table public.profiles drop constraint %I', c.conname);
  end loop;
end $$;

-- `auth_user_id` is the link, and `unique` on it is load-bearing twice over: it
-- is what `current_profile_id()` relies on to return exactly one row, and it is
-- what makes a half-finished claim merge impossible (`approve_profile_claim`
-- moves the link, and the second half of a merge cannot silently leave two
-- profiles pointing at one account).
do $$ begin
  if not exists (
    select 1 from pg_constraint where conname = 'profiles_auth_user_id_fkey'
  ) then
    alter table profiles
      add constraint profiles_auth_user_id_fkey
      foreign key (auth_user_id) references auth.users (id) on delete cascade;
  end if;
  if not exists (
    select 1 from pg_constraint where conname = 'profiles_merged_into_fkey'
  ) then
    alter table profiles
      add constraint profiles_merged_into_fkey
      foreign key (merged_into) references profiles (id) on delete set null;
  end if;
end $$;

-- Partial, because only members carry a link and `unique` would otherwise treat
-- every imported profile's null as distinct anyway — the partial index says so
-- out loud and stays small as the corpus grows.
create unique index if not exists profiles_auth_user_id_key
  on profiles (auth_user_id) where auth_user_id is not null;

-- A new FK column needs its own index in the same change (Gotcha 4). `kind` is
-- in the index because every ranked surface filters on it (Phase 35c) and every
-- claim lookup starts from it.
create index if not exists profiles_merged_into_idx
  on profiles (merged_into) where merged_into is not null;
create index if not exists profiles_kind_idx on profiles (kind);

-- Backfill the link for every profile that predates Phase 35b. Idempotent, and
-- the reason the decoupling is invisible to existing data: after this runs,
-- `current_profile_id()` returns for every signed-in user exactly the id that
-- `auth.uid()` used to return directly.
update profiles set auth_user_id = id
 where auth_user_id is null
   and kind = 'member'
   and exists (select 1 from auth.users u where u.id = profiles.id);

-- ----------------------------------------------------------------------------
-- current_profile_id() — the Phase 35b primitive
-- ----------------------------------------------------------------------------
-- Every policy in this file used to read `= auth.uid()`. They now read
-- `= current_profile_id()`, and this is the one place that knows how an account
-- maps to an identity.
--
-- Three properties, each of which a wrong answer breaks something different:
--
--   `security definer` — a policy on `profiles` cannot be allowed to decide
--   whether the caller may look up their own profile. Under invoker rights this
--   function would be filtered by `profiles_select`, which is `using (true)`
--   today and therefore fine — but the moment that policy is narrowed, every
--   other policy in the schema would start returning null for everybody, at
--   once, with no error anywhere. Definer rights make it independent of that.
--
--   `stable` — Postgres may then evaluate it once per statement instead of once
--   per row. On a `select` over a 500-row page, the difference is 1 lookup
--   against 500.
--
--   `set search_path = public` — mandatory on every definer function here
--   (Gotcha 3); without it the function resolves `profiles` against the
--   caller's search_path.
--
-- It returns null for an anonymous caller, which is exactly what `auth.uid()`
-- did, so every `x = current_profile_id()` predicate is false for `anon` the
-- same way it used to be. It also returns null for a member whose profile row
-- is missing — see the B015 backfill below, which is what stops that happening.
--
-- Deliberately left callable as an RPC (no revoke): it discloses the caller's
-- own profile id and nothing else, and the client has a legitimate use for it
-- once claiming exists.
create or replace function current_profile_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select p.id from profiles p where p.auth_user_id = auth.uid();
$$;

-- 32a2: `display_name` is embedded in `kRecipeSelect`, so it ships on every card
-- of every grid — an unbounded one is a payload amplifier aimed at every other
-- user. `handle_new_user` copies it out of unvalidated signup metadata, so the
-- bound has to live here rather than in the editor. Measured maxima over seed +
-- sim `medium` on 2026-08-26: display_name 51, bio 69.
--
-- Clamped **before** constraining, rather than added `not valid` the way
-- `recipes_text_lengths` is. The two tables get different treatment because
-- truncation costs different things: an over-long `display_name` predates
-- `handle_new_user`'s own `left(…, 80)` clamp, so shortening it is the same
-- decision that function already makes on every signup — while silently cutting
-- a cook's recipe prose is data loss, which is why that one is left unvalidated
-- instead. Idempotent: on a clean table it updates zero rows.
update public.profiles set display_name = left(display_name, 80)
 where char_length(display_name) > 80;
update public.profiles set bio = left(bio, 500)
 where bio is not null and char_length(bio) > 500;

do $$
begin
  -- Guarded by name, and therefore subject to the same trap `recipes_text_lengths`
  -- fell into: **changing this predicate later means dropping the constraint
  -- explicitly in this file**, or every database that already has it keeps the
  -- old rule silently. It is not dropped-and-re-added unconditionally the way
  -- that one is, because this constraint is `valid` and a re-add rescans every
  -- profile row on every apply — the cost OPT-A6 removed from the deferred FKs.
  if not exists (
    select 1 from pg_constraint where conname = 'profiles_text_lengths'
  ) then
    alter table profiles
      add constraint profiles_text_lengths
      check (char_length(display_name) <= 80
             and (bio is null or char_length(bio) <= 500));
  end if;
end $$;

-- Denormalized "chef" standing, maintained by on_recipe_stats_change over the
-- owner's *public* recipes. Server-owned — the client never writes these.
-- Added via `alter` so an already-deployed 0001 picks them up on re-run.
alter table profiles add column if not exists chef_score          numeric   not null default 0;
alter table profiles add column if not exists chef_tier           chef_tier not null default 'home_cook';
alter table profiles add column if not exists public_recipe_count int       not null default 0;

-- The three engagement totals the score is computed from (OPT-P5). The
-- recompute already summed them and threw them away, so `chefs_leaderboard` had
-- to re-aggregate every public recipe on every page just to show the numbers
-- beside the score. Persisting them makes the board a pure indexed read of
-- `profiles`. `bigint` for the same reason chef_score()'s arguments are:
-- view_count is unbounded.
alter table profiles add column if not exists total_likes bigint not null default 0;
alter table profiles add column if not exists total_saves bigint not null default 0;
alter table profiles add column if not exists total_views bigint not null default 0;

-- The leaderboard's exact ordering, as a partial index over exactly the rows it
-- ranks (OPT-P5). All four keys are here because `chefs_leaderboard` orders by
-- all four for a deterministic page boundary — a prefix-only index would leave
-- a sort on top, and a sort has to read every row before it can return the
-- first. Partial on `public_recipe_count > 0` because that is the board's own
-- "is a chef at all" filter, which excludes ~83% of profiles at sim `medium`.
--
-- Phase 35b narrowed the predicate to members, and did it under a NEW NAME
-- rather than editing this one. `create index if not exists` keys on the name,
-- so changing a partial index's predicate in place applies to a fresh database
-- and is a silent no-op on every database that already has it — Gotcha 5's
-- constraint trap, in its index form. Dropping the superseded name explicitly
-- is the fix, and `drop ... if exists` + `create ... if not exists` means a
-- re-apply pays for neither.
drop index if exists profiles_leaderboard_idx;
create index if not exists profiles_leaderboard_member_idx
  on profiles (chef_score desc, public_recipe_count desc, display_name asc, id asc)
  where public_recipe_count > 0 and kind = 'member';

-- Superseded by the partial index above: same leading columns, no filter, and
-- the only query that ever ordered by chef_score is the board. Dropped rather
-- than left in place so profile writes maintain one index instead of two.
drop index if exists profiles_chef_score_idx;

-- recipes
create table if not exists recipes (
  id                     uuid primary key default gen_random_uuid(),
  owner_id               uuid not null references profiles (id) on delete cascade,
  title                  text not null,
  description            text not null default '',
  cover_image_url        text,
  cuisine                text,
  category               text,
  difficulty             difficulty not null default 'easy',
  prep_minutes           int not null default 0,
  cook_minutes           int not null default 0,
  servings               int not null default 1,
  visibility             recipe_visibility not null default 'private',
  attribution            text,                                   -- legacy origin/story
  forked_from_recipe_id  uuid references recipes (id) on delete set null,
  forked_from_version_id uuid,                                   -- FK added after recipe_versions
  current_version_id     uuid,                                   -- FK added after recipe_versions
  like_count             int not null default 0,
  save_count             int not null default 0,
  view_count             int not null default 0,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

-- Denormalized rating aggregates, maintained by the recipe_ratings trigger.
-- Added via `alter` so an already-deployed 0001 picks them up on re-run.
alter table recipes add column if not exists rating_sum   numeric      not null default 0;
alter table recipes add column if not exists rating_count int          not null default 0;
alter table recipes add column if not exists rating_avg   numeric(3,2) not null default 0;

-- Nutrition facts (Phase 28). ONE nullable jsonb column, not eleven numerics:
-- the writable-recipe-column set is restated in ~13 places, so a column costs
-- each copy a line. `null` means "no info" and is the only representation of it
-- — an all-empty entry is normalized to null before it reaches the repository.
-- Postgres cannot type-check the interior, so the key set is pinned by
-- `RecipeNutrition` in core and by `tool/recipe_format.dart`; the constraint
-- below is the one thing the database itself can insist on.
alter table recipes add column if not exists nutrition jsonb;

create index if not exists recipes_owner_idx on recipes (owner_id);
create index if not exists recipes_forked_from_idx on recipes (forked_from_recipe_id);

-- 32b: the two columns of `recipes` that point INTO `recipe_versions`. Postgres
-- indexes the referenced side of a foreign key automatically and the
-- referencing side never — so deleting a version made the FK check seq-scan the
-- whole of `recipes`, twice, **per version row**. A recipe delete cascades all
-- of its versions, so a recipe with nine versions paid eighteen full scans of
-- the recipes table to disappear. Measured before adding these (sim `small`,
-- 455 recipes / 1,044 versions): the two triggers fired 9 times each on one
-- delete. This is the class the audit called delete amplification, and it grows
-- with the table rather than with the row being deleted.
--
-- The cost, since the benefit is stated: `current_version_id` was in no index
-- before, so `recipe_versions_set_current`'s update of it was HOT-eligible and
-- left no index churn. Every save now writes an index tuple and a dead one —
-- cheap against a delete that was scanning the table, but not free. Its
-- `is not null` predicate excludes nothing in practice (every recipe ends up
-- with a current version); it covers the window between insert and trigger, and
-- is not a space saving.
create index if not exists recipes_current_version_idx
  on recipes (current_version_id) where current_version_id is not null;
create index if not exists recipes_forked_from_version_idx
  on recipes (forked_from_version_id) where forked_from_version_id is not null;

-- Dropped, deliberately (32b). `visibility` is a two-value column whose common
-- value covers ~78% of the rows, so no reader is selective enough for an index
-- scan on it to win — and plenty of readers *do* test it as a plain qual
-- (`recipes_select`, the chef and shelf RPCs), which is the point: they test it
-- and still would not use this. Maintained on every insert and every publish,
-- chosen by nothing.
-- `rating_avg` likewise: nothing orders by it — Discover's Popular ranks on the
-- Bayesian expression, which no index on the raw average can serve — and it was
-- re-maintained on every rating write, which is one of the hottest paths here.
-- `drop index if exists` rather than a guard block: it is already idempotent,
-- and naming them keeps the removal visible to anyone re-reading this file.
drop index if exists recipes_visibility_idx;
drop index if exists recipes_rating_idx;
-- Discover's two date-ordered surfaces (OPT-P2). `recipes_trending` bounds its
-- window to the last 30 days and Discover **Recent** orders by `created_at`
-- desc; both filter to public, so a partial index on exactly that predicate
-- serves both and stays small (it indexes the public rows only). Partial on
-- `visibility` rather than a composite because every reader of it filters to
-- public — there is no "recent private recipes" surface.
create index if not exists recipes_public_created_idx
  on recipes (created_at desc) where visibility = 'public';

-- Discover's shelves (Phase 26). `recipes_quick` and `recipes_projects` filter
-- on the SUM of the two minute columns, which no other index can serve, and
-- `recipes_most_forked` groups forks by their source. Both are partial on
-- public rows: there is no "quick private recipes" surface, and a private fork
-- is deliberately not counted (see the RPC).
create index if not exists recipes_public_total_minutes_idx
  on recipes ((prep_minutes + cook_minutes))
  where visibility = 'public';
create index if not exists recipes_public_fork_source_idx
  on recipes (forked_from_recipe_id)
  where visibility = 'public' and forked_from_recipe_id is not null;

-- recipe_versions (git-like snapshots)
create table if not exists recipe_versions (
  id                uuid primary key default gen_random_uuid(),
  recipe_id         uuid not null references recipes (id) on delete cascade,
  version_number    int not null,
  parent_version_id uuid references recipe_versions (id) on delete set null,
  author_id         uuid not null references profiles (id) on delete cascade,
  change_summary    text not null default '',
  content_snapshot  jsonb not null,
  created_at        timestamptz not null default now(),
  unique (recipe_id, version_number)
);
-- No `(recipe_id)` index here: `unique (recipe_id, version_number)` above already
-- leads with `recipe_id`, so a plain one is a second copy of the same B-tree
-- prefix — maintained on every version insert and chosen by nothing (OPT-A6,
-- same reasoning as the `recipe_views_recipe_idx` precedent).
--
-- 32b: `parent_version_id` is the other direction and does need one. It is a
-- self-referencing FK with `on delete set null`, so deleting a version scans
-- this table for children — and a recipe delete cascades *every* version, which
-- makes it one scan per version. The lineage is a chain, so the vast majority of
-- rows have a parent; the partial predicate exists to skip the v1 rows rather
-- than to keep the index small.
create index if not exists recipe_versions_parent_idx
  on recipe_versions (parent_version_id) where parent_version_id is not null;
drop index if exists recipe_versions_recipe_idx;

-- Deferred FKs from recipes -> recipe_versions: they cannot be declared with the
-- table because `recipe_versions` does not exist yet.
--
-- Added only when missing (OPT-A6). The drop-and-re-add this replaced ran on
-- **every** apply, and adding a foreign key revalidates every existing row in
-- `recipes` — work that grows with the table and is pure waste when the
-- constraint is already there and unchanged. `if not exists` on the constraint
-- name is the guard; changing a constraint's definition means renaming it or
-- dropping it explicitly, exactly like the B024 rule for functions.
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'recipes_current_version_fk'
  ) then
    alter table recipes
      add constraint recipes_current_version_fk
      foreign key (current_version_id) references recipe_versions (id)
      on delete set null;
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'recipes_forked_from_version_fk'
  ) then
    alter table recipes
      add constraint recipes_forked_from_version_fk
      foreign key (forked_from_version_id) references recipe_versions (id)
      on delete set null;
  end if;

  -- `nutrition` is a label, i.e. a json OBJECT or nothing. A JSON scalar or
  -- array in that column would decode to garbage on the client with no error,
  -- so the shape is pinned here. Note this also rejects `'null'::jsonb` (whose
  -- jsonb_typeof is 'null', not 'object'), which is why both save_recipe
  -- branches wrap the payload extraction in `nullif(…, 'null'::jsonb)`.
  if not exists (
    select 1 from pg_constraint where conname = 'recipes_nutrition_is_object'
  ) then
    alter table recipes
      add constraint recipes_nutrition_is_object
      check (nutrition is null or jsonb_typeof(nutrition) = 'object');
  end if;

  -- 32a2: bounds on the client-writable numbers. RLS says *who* may write a
  -- column and the column grants say *which* columns; neither says anything
  -- about the value, so until now `servings = 0` and `prep_minutes = -5` were
  -- storable over PostgREST. `servings` is the one that bites hardest: the
  -- servings scaler divides by it and `estimate_nutrition` divides by
  -- `greatest(servings, 1)`, so a zero is a per-serving label computed against a
  -- recipe that claims to serve nobody.
  if not exists (
    select 1 from pg_constraint where conname = 'recipes_servings_positive'
  ) then
    alter table recipes
      add constraint recipes_servings_positive check (servings >= 1);
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'recipes_minutes_nonneg'
  ) then
    alter table recipes
      add constraint recipes_minutes_nonneg
      check (prep_minutes >= 0 and cook_minutes >= 0);
  end if;

  -- Length caps. **Every text column a client can write and everyone else
  -- downloads** — not just the obvious two: `kRecipeSelect` ships `title`,
  -- `description`, `attribution`, `cuisine`, `category` and `cover_image_url` on
  -- every row of every grid, and all six sit in both column-grant lists, so a
  -- cap that named only `title` would leave the same amplifier one column over.
  -- None had an upper bound at all, so one account could store a megabyte on a
  -- public recipe and make every visitor download it per card.
  --
  -- Bounds sit well above the real corpus (measured 2026-08-26 over seed + sim
  -- `medium`: title 58, description 319, attribution 51, cuisine 13, category 9,
  -- display_name 51, bio 69), because a check constraint is validated against
  -- existing rows and an apply that trips one aborts the whole file under
  -- `psql -1`.
  --
  -- **`not valid`, deliberately.** Every database this has been measured on is
  -- fixture-built, and the generators already enforce these bounds — so the
  -- measurement proves nothing about the rows that can actually violate: a
  -- description typed before the editor had a `maxLength`, or a display_name
  -- from a signup before `handle_new_user` clamped. Those exist only on a
  -- populated database, which is the one path nobody tests (Gotcha 6). A
  -- `not valid` constraint is enforced on every future insert and update — the
  -- whole point — and simply does not scan what is already there, so the first
  -- apply onto real data cannot roll back the schema. Promoting it is a separate,
  -- deliberate `alter table … validate constraint` once the table is known clean.
  -- **B024's rule, for constraints.** `if not exists` keys on the *name*, so a
  -- database that already holds an older definition under this name keeps it
  -- forever and the apply reports success — which is exactly what happened
  -- while this was being written: the first cut bounded `title` and
  -- `description` only, and re-applying the six-column version was a silent
  -- no-op until `rls_matrix.sql` B9h asked. So the superseded definition is
  -- dropped explicitly here, in the file that recreates it, rather than only in
  -- `drop.sql` (which a plain re-apply never runs). The drop costs nothing to
  -- repeat because the constraint is `not valid` — re-adding it scans no rows,
  -- unlike the FK re-add OPT-A6 removed for that reason.
  alter table recipes drop constraint if exists recipes_text_lengths;
  if not exists (
    select 1 from pg_constraint where conname = 'recipes_text_lengths'
  ) then
    alter table recipes
      add constraint recipes_text_lengths
      check (char_length(title) <= 200
             and char_length(description) <= 10000
             and (attribution     is null or char_length(attribution)     <= 2000)
             and (cuisine         is null or char_length(cuisine)         <= 80)
             and (category        is null or char_length(category)        <= 80)
             and (cover_image_url is null or char_length(cover_image_url) <= 2048))
      not valid;
  end if;
end $$;

-- ingredient groups + ingredients
create table if not exists ingredient_groups (
  id         uuid primary key default gen_random_uuid(),
  recipe_id  uuid not null references recipes (id) on delete cascade,
  name       text not null default '',
  sort_order int not null default 0
);
create index if not exists ingredient_groups_recipe_idx on ingredient_groups (recipe_id);

create table if not exists ingredients (
  id          uuid primary key default gen_random_uuid(),
  group_id    uuid not null references ingredient_groups (id) on delete cascade,
  quantity    numeric,
  unit        text,
  name        text not null,
  note        text,
  is_optional boolean not null default false,
  sort_order  int not null default 0
);
create index if not exists ingredients_group_idx on ingredients (group_id);

-- 32a2: a quantity is absent or it is a real amount. NULL is the "to taste"
-- case and stays legal; zero and negative are not, and the negative one is why
-- this is a constraint rather than a lint — B076 found that `estimate_nutrition`
-- would multiply it by the food's per-100 g values and *subtract* from the
-- label, which is a wrong number rather than a missing one. The estimator still
-- skips `quantity <= 0` defensively; this stops it being storable at all.
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'ingredients_quantity_positive'
  ) then
    alter table ingredients
      add constraint ingredients_quantity_positive
      check (quantity is null or quantity > 0);
  end if;
end $$;

-- step groups + steps
create table if not exists step_groups (
  id         uuid primary key default gen_random_uuid(),
  recipe_id  uuid not null references recipes (id) on delete cascade,
  name       text not null default '',
  sort_order int not null default 0
);
create index if not exists step_groups_recipe_idx on step_groups (recipe_id);

create table if not exists steps (
  id               uuid primary key default gen_random_uuid(),
  group_id         uuid not null references step_groups (id) on delete cascade,
  step_order       int not null default 0,
  text             text not null,
  image_url        text,
  duration_minutes int,
  temperature      text,
  tip              text,
  sort_order       int not null default 0
);
create index if not exists steps_group_idx on steps (group_id);

-- tags
create table if not exists tags (
  id   uuid primary key default gen_random_uuid(),
  name text not null unique
);

create table if not exists recipe_tags (
  recipe_id uuid not null references recipes (id) on delete cascade,
  tag_id    uuid not null references tags (id) on delete cascade,
  primary key (recipe_id, tag_id)
);
-- 32b: the PK leads with `recipe_id`, so nothing served a lookup **by tag** —
-- and three different things do one: the `tags_delete_orphan` policy's
-- `not exists` probe (evaluated for every candidate row of a tag delete),
-- `on_tags_search_change`'s join when a tag is renamed, and the FK check behind
-- deleting a tag at all.
create index if not exists recipe_tags_tag_idx on recipe_tags (tag_id);

-- sharing
create table if not exists recipe_shares (
  recipe_id          uuid not null references recipes (id) on delete cascade,
  shared_with_user_id uuid not null references profiles (id) on delete cascade,
  permission         share_permission not null default 'view',
  created_at         timestamptz not null default now(),
  primary key (recipe_id, shared_with_user_id)
);
create index if not exists recipe_shares_user_idx on recipe_shares (shared_with_user_id);

-- social: likes / saves / views
create table if not exists recipe_likes (
  user_id    uuid not null references profiles (id) on delete cascade,
  recipe_id  uuid not null references recipes (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, recipe_id)
);

create table if not exists recipe_saves (
  user_id    uuid not null references profiles (id) on delete cascade,
  recipe_id  uuid not null references recipes (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, recipe_id)
);

-- Both PKs lead with `user_id`, which serves the write paths ("did I like this",
-- "unlike this") but leaves every recipe-leading question a seq scan (OPT-P6).
-- `created_at` is the second column so the same index answers "who liked recipe
-- X, newest first" and the dated windows Phase 23's rails need — the engagement
-- log is what makes windowed queries possible at all (SDS §10.8), and it is only
-- useful if it can be read by recipe and by date.
create index if not exists recipe_likes_recipe_idx on recipe_likes (recipe_id, created_at desc);
create index if not exists recipe_saves_recipe_idx on recipe_saves (recipe_id, created_at desc);

-- Phase 23 (the windowed half): the two composites above lead with `recipe_id`,
-- so neither can serve "every like on the site in the last 7 days" — the shape
-- `chef_window_stats` reads. It aggregates the whole board in one pass rather
-- than one recipe at a time, so its scan is date-first; without these it is a
-- seq scan of the log on every request of an `anon`-callable page. `recipe_id`
-- rides along as the second key so the join back to the chef's public recipes
-- stays index-only. Cheap to maintain: unlike `recipe_views`, a like or a save
-- is one row per (user, recipe) for the life of the account.
create index if not exists recipe_likes_created_idx on recipe_likes (created_at desc, recipe_id);
create index if not exists recipe_saves_created_idx on recipe_saves (created_at desc, recipe_id);

create table if not exists recipe_views (
  id        uuid primary key default gen_random_uuid(),
  recipe_id uuid not null references recipes (id) on delete cascade,
  user_id   uuid references profiles (id) on delete set null,
  viewed_at timestamptz not null default now()
);
-- Backs the "has this user already viewed this recipe?" probe in on_view_insert().
-- (recipe_id) alone is a leftmost prefix of this, so the older recipe_views_recipe_idx
-- is redundant — dropped below to save a write per view on the busiest table here.
create index if not exists recipe_views_recipe_user_idx
  on recipe_views (recipe_id, user_id);
drop index if exists recipe_views_recipe_idx;

-- 32b: `chef_trending_recipes` (Phase 31) counts distinct signed-in viewers of
-- one chef's recipe **inside a seven-day window**, and the index above carries
-- no date — so every view row for the recipe was heap-fetched to read
-- `viewed_at`. The likes half of that same ranking got
-- `recipe_likes_recipe_idx (recipe_id, created_at desc)` for exactly this
-- reason and the views half was missed. Partial on `user_id is not null`
-- because the ranking excludes anonymous rows anyway (Gotcha 10 / B012) — note
-- that is ~81% of rows in the measured fixture, so it is a correctness match,
-- not a size trick.
--
-- Write cost, since `logView()` is the highest-volume insert in the schema: a
-- signed-in view now maintains four index entries instead of two. Measured at
-- 1,000 inserts, the difference is **below the noise floor** — `on_view_insert`
-- does a dedup probe, an advisory lock and a counter update per row, and that
-- dominates so completely that the same batch ranged 115–307 ms in both
-- configurations. Recorded as "not distinguishable", not as "free".
create index if not exists recipe_views_recipe_viewed_idx
  on recipe_views (recipe_id, viewed_at desc, user_id)
  where user_id is not null;

-- Phase 23: the same index rotated, because the windowed board asks the
-- transposed question. `chef_trending_recipes` starts from ONE recipe and wants
-- its last seven days, which the index above serves; `chef_window_stats` starts
-- from a DATE and wants every signed-in viewer after it, which that index
-- cannot serve at all — `recipe_id` leads it. Partial on `user_id is not null`
-- for the same reason as its twin: the window excludes anonymous rows anyway
-- (Gotcha 10 / B012), so this is a correctness match rather than a size trick,
-- and it keeps ~19% of the local fixture's 20,630 rows out of the index.
-- All three columns are here so the distinct-pair count is an index-only scan.
--
-- Write cost, since `logView()` is the highest-volume insert in the schema: a
-- signed-in view now maintains five index entries instead of four. 32b measured
-- the step from two to four as below the noise floor — `on_view_insert`'s dedup
-- probe, advisory lock and counter update dominate so completely that a
-- 1,000-row batch ranged 115-307 ms either way — and this adds a fifth to the
-- same budget. Recorded as "expected to be indistinguishable", NOT as measured:
-- the local fixture is a restored simulation and was not re-timed for it.
create index if not exists recipe_views_viewed_idx
  on recipe_views (viewed_at desc, recipe_id, user_id)
  where user_id is not null;

-- 32b: the FK that made deleting an account expensive. `user_id` is
-- `on delete set null`, and both composites above lead with `recipe_id`, so
-- neither can serve `user_id = $1` — removing one profile seq-scanned the
-- busiest table in the schema (20,630 rows at sim `small`, unbounded in
-- production). This is the GDPR-delete path.
create index if not exists recipe_views_user_idx
  on recipe_views (user_id) where user_id is not null;

-- ratings: one row per (user, recipe); 0.5 .. 5.0 in half-star steps.
create table if not exists recipe_ratings (
  user_id    uuid not null references profiles (id) on delete cascade,
  recipe_id  uuid not null references recipes (id) on delete cascade,
  rating     numeric(2,1) not null
             check (rating >= 0.5 and rating <= 5.0 and (rating * 2) = floor(rating * 2)),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, recipe_id)
);
create index if not exists recipe_ratings_recipe_idx on recipe_ratings (recipe_id);
-- Phase 23: `chef_window_stats` counts ratings RECEIVED in the window, and the
-- index above leads with `recipe_id`, so the date range had no support at all.
create index if not exists recipe_ratings_created_idx on recipe_ratings (created_at desc, recipe_id);

-- recipe_suggestions (RESERVED stub for future PR-like flow)
create table if not exists recipe_suggestions (
  id            uuid primary key default gen_random_uuid(),
  recipe_id     uuid not null references recipes (id) on delete cascade,   -- target
  from_recipe_id uuid references recipes (id) on delete set null,          -- fork source
  author_id     uuid not null references profiles (id) on delete cascade,
  status        suggestion_status not null default 'open',
  summary       text not null default '',
  payload       jsonb,
  created_at    timestamptz not null default now()
);
-- 32b: three FK columns, zero indexes — and the table's emptiness is not the
-- point. Its cascade fires on **every** recipe delete and its `set null` on
-- every profile delete, so an unindexed referencing side makes each of those a
-- seq scan of this table for as long as it stays empty and a growing one after.
create index if not exists recipe_suggestions_recipe_idx on recipe_suggestions (recipe_id);
create index if not exists recipe_suggestions_author_idx on recipe_suggestions (author_id);
create index if not exists recipe_suggestions_from_recipe_idx
  on recipe_suggestions (from_recipe_id) where from_recipe_id is not null;

-- ============================================================================
-- Food registry (Phase 29a) — reference data for auto nutrition
--
-- Populated by supabase/nutrition_foods.sql (GENERATED from nutritionData/ —
-- `melos run nutrition:gen`), read-only to every client role: RLS below is
-- select-only and the grants block revokes writes. `db:clean` does not touch
-- these tables (it truncates *recipe* data; this is reference data), which is
-- what keeps a post-clean `db:recipes` green now that ingredients.food_id
-- (29b, below) references `food`.
--
-- The 11 per-100 g columns are FDC's EAV flattened, named exactly as the
-- nutrition label's jsonb keys (Phase 28) so nothing translates between them.
-- ============================================================================

create table if not exists food (
  id              text primary key,             -- slug: 'all-purpose-flour'
  display_name    text not null,
  fdc_id          int,                          -- USDA source row; null = authored
  calories        numeric,
  total_fat_g     numeric,
  saturated_fat_g numeric,
  trans_fat_g     numeric,
  cholesterol_mg  numeric,
  sodium_mg       numeric,
  total_carbs_g   numeric,
  dietary_fiber_g numeric,
  total_sugars_g  numeric,
  added_sugars_g  numeric,
  protein_g       numeric,
  grams_per_ml    numeric,        -- null = volume units unresolvable for this food
  is_added_sugar  boolean not null default false
);

-- Lowercase, globally unique input spellings ('flour', '00 pizza flour').
create table if not exists food_alias (
  alias   text primary key,
  food_id text not null references food (id) on delete cascade
);
create index if not exists food_alias_food_idx on food_alias (food_id);

-- Grams for one named portion of one food ('clove' = 3 g, 'each' = 50 g).
create table if not exists food_portion (
  food_id  text not null references food (id) on delete cascade,
  unit_key text not null,
  grams    numeric not null check (grams > 0),
  primary key (food_id, unit_key)
);

-- The canonical unit registry (from nutritionData/units.json): one row per
-- accepted spelling. `factor` is grams per unit (mass) or ml per unit
-- (volume); null for count units, which resolve through food_portion.
-- Spelling '' is the bare-count marker ('2 eggs').
create table if not exists food_unit (
  spelling text primary key,
  unit_key text not null,
  class    text not null check (class in ('mass', 'volume', 'count')),
  factor   numeric check (factor is null or factor > 0)
);

-- Typeahead indexes: prefix matches use the PKs; these serve the trigram tail.
create index if not exists food_display_name_trgm_idx
  on food using gin (lower(display_name) gin_trgm_ops);
create index if not exists food_alias_trgm_idx
  on food_alias using gin (alias gin_trgm_ops);

-- The ingredient → food link (Phase 29b). A real nullable column, not a
-- name-keyed map in the nutrition jsonb, so the link survives renames,
-- duplicate names across groups, forks (the deep copy copies it), and the
-- editor's delete-and-reinsert save. `on delete set null`: retiring a registry
-- entry orphans links gracefully instead of blocking the delete.
--
-- An `alter` here rather than a column in the create above, because
-- `ingredients` is created before `food` exists in this file's apply order —
-- an inline `references food` would fail every fresh apply (the B045 class).
alter table ingredients add column if not exists food_id text
  references food (id) on delete set null;
-- Serves the FK's `on delete set null` scan and 29c's estimation join.
create index if not exists ingredients_food_idx on ingredients (food_id);

-- ----------------------------------------------------------------------------
-- Entities (Phase 35b) — the group that PUBLISHED a recipe
-- ----------------------------------------------------------------------------
-- Phase 25 designed a `restaurants` table. The corpus needs an attribution
-- entity for 560 publishers — brands, magazines, community sites, a handful of
-- actual restaurants — and the north star needs a restaurant entity. They are
-- the same table with a discriminator, and building both would mean writing the
-- directory page twice, so `restaurants` becomes `entities where kind =
-- 'restaurant'`.
--
-- An entity is **not a principal**, exactly as Phase 25 decided: nobody signs
-- in as one. It is a row managed by its `owner`-role members, so auth, RLS and
-- the engagement model are untouched. It also collects no engagement of its
-- own — it reads its numbers through its members and its signature dishes.
create table if not exists entities (
  id              uuid primary key default gen_random_uuid(),
  -- The stable identity. The corpus already keys every source on a slug
  -- (`corpus/sources.json`), so an import is idempotent on this column.
  slug            text not null unique,
  name            text not null,
  kind            entity_kind not null,
  homepage        text,
  country         text,
  description     text,
  cover_image_url text,
  -- Null for an imported entity: nobody on this service created it. `set null`
  -- rather than cascade, because deleting the member who registered a
  -- restaurant must not delete the restaurant.
  created_by      uuid references profiles (id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

-- Gotcha 4: Postgres indexes the referenced side of a foreign key and never the
-- referencing side, so every FK column below gets its own index in the same
-- change that creates it.
create index if not exists entities_created_by_idx
  on entities (created_by) where created_by is not null;
create index if not exists entities_kind_idx on entities (kind);

-- Same treatment as `profiles_text_lengths`: `name` is embedded wherever an
-- entity is credited, so an unbounded one is a payload amplifier. Guarded by
-- NAME, and therefore subject to Gotcha 5's constraint trap — widening this
-- predicate later means dropping the constraint explicitly in this file.
-- The importer's slug namespace (Phase 35c).
--
-- `entities.slug` is unique, and `import_recipe` finds-or-creates a publisher
-- by it. Without a reserved prefix, any signed-in member could create an entity
-- with the slug a publisher is going to need — `king-arthur` — and the
-- importer's `on conflict (slug) do nothing` would then attach that
-- publisher's recipes to a row a stranger created and still owns
-- (`entities_update` is `is_entity_owner`). Not hypothetical once an import
-- runs: it is a free land-grab on 560 names.
--
-- So imported entities live under `src:` and members may not write that prefix.
-- The slug never appears in a URL — `/entity/:id` takes the uuid — so the
-- namespace costs a reader nothing.
do $$ begin
  if not exists (
    select 1 from pg_constraint where conname = 'entities_slug_namespace'
  ) then
    alter table entities
      add constraint entities_slug_namespace
      check (created_by is null or slug not like 'src:%')
      not valid;
  end if;
end $$;

do $$ begin
  if not exists (
    select 1 from pg_constraint where conname = 'entities_text_lengths'
  ) then
    alter table entities
      add constraint entities_text_lengths
      check (char_length(name) <= 120
             and (description is null or char_length(description) <= 1000));
  end if;
end $$;

-- Association is optional by construction: a profile with zero rows here is the
-- normal case, and always will be.
create table if not exists entity_members (
  entity_id  uuid not null references entities (id) on delete cascade,
  profile_id uuid not null references profiles (id) on delete cascade,
  role       entity_role not null default 'chef',
  title      text,                                  -- free text, e.g. 'Head Chef'
  created_at timestamptz not null default now(),
  primary key (entity_id, profile_id)
);
-- The PK already serves `entity_id`; `profile_id` is the unindexed half.
create index if not exists entity_members_profile_idx on entity_members (profile_id);

-- Signature dishes point at existing recipes. No second recipe system.
create table if not exists entity_signature_dishes (
  entity_id  uuid not null references entities (id) on delete cascade,
  recipe_id  uuid not null references recipes (id) on delete cascade,
  sort_order int  not null default 0,
  created_at timestamptz not null default now(),
  primary key (entity_id, recipe_id)
);
create index if not exists entity_signature_recipe_idx
  on entity_signature_dishes (recipe_id);

-- ----------------------------------------------------------------------------
-- Provenance, and the imported flag (Phase 35c)
-- ----------------------------------------------------------------------------
-- `alter table` down here rather than columns in the `recipes` create above,
-- because `source_entity_id` references `entities` and `recipes` is created
-- some seven hundred lines earlier — an inline reference would fail every fresh
-- apply, which is the B045 trap `ingredients.food_id` already documents.
--
-- Every column here is **server-owned**. The importer writes them, no client
-- grant includes any of them (so a `PATCH` carrying one fails 42501 the way a
-- forged counter does), and `save_recipe` does not touch them — which is what
-- stops a member who has claimed an imported page from silently clearing its
-- credit by editing the recipe.
--
-- `is_imported` is a column rather than a join to `profiles.kind`, for two
-- reasons. Every ranked shelf filters on it on every page, and the alternative
-- is a join per shelf per page to answer something the row already knows. And
-- it is not the same question: a chef who claims their page becomes a `member`
-- while the recipes they were credited for stay imported.
alter table recipes add column if not exists is_imported boolean not null default false;

-- What corpus browsing orders by. 558k rows arrive with identical zero
-- counters, so there is **no total order** among them — and `offset` over a tie
-- shows one row twice and hides another, silently (Gotcha 24). Computed once at
-- import from field coverage (cover image, servings, times, a sane ingredient
-- count, steps, a named chef). Deliberately **not** engagement: nothing updates
-- it and nothing should, or it becomes a ranking by another name.
alter table recipes add column if not exists quality_score smallint;

alter table recipes add column if not exists source_url text;
alter table recipes add column if not exists source_name text;
alter table recipes add column if not exists source_entity_id uuid;
alter table recipes add column if not exists imported_at timestamptz;
alter table recipes add column if not exists rights_mode rights_mode not null default 'functional';
alter table recipes add column if not exists image_mode image_mode not null default 'hotlink';

do $$ begin
  if not exists (
    select 1 from pg_constraint where conname = 'recipes_source_entity_id_fkey'
  ) then
    alter table recipes
      add constraint recipes_source_entity_id_fkey
      foreign key (source_entity_id) references entities (id) on delete set null;
  end if;
  if not exists (
    select 1 from pg_constraint where conname = 'recipes_quality_score_range'
  ) then
    -- `not valid`: the table may already hold rows, and this is the cheap shape
    -- (no rescan) `recipes_text_lengths` uses for the same reason.
    alter table recipes
      add constraint recipes_quality_score_range
      check (quality_score is null or (quality_score between 0 and 100))
      not valid;
  end if;
end $$;

-- The importer's idempotency key: a re-run of a finished shard inserts nothing,
-- which is what makes an import resumable in the same sense the crawl is.
-- Partial, because every member-authored recipe has a null `source_url` and
-- there will always be more of those than the unique index needs to carry.
create unique index if not exists recipes_source_url_key
  on recipes (source_entity_id, source_url)
  where source_url is not null;

-- Gotcha 4: the referencing side of a foreign key is never indexed
-- automatically, so deleting an entity would seq-scan `recipes` once per
-- cascaded row.
create index if not exists recipes_source_entity_idx
  on recipes (source_entity_id) where source_entity_id is not null;

-- Corpus browsing's exact ordering over exactly its rows, and the complement
-- for the ranked shelves, which all filter `is_imported = false`. Two partial
-- indexes rather than one whole-table index because after an import the two
-- populations differ by three orders of magnitude, and each query wants only
-- its own side.
create index if not exists recipes_imported_quality_idx
  on recipes (quality_score desc, id)
  where is_imported and visibility = 'public';
create index if not exists recipes_not_imported_idx
  on recipes (created_at desc, id) where not is_imported;

-- ----------------------------------------------------------------------------
-- import_blocklist (Phase 35a's promise, kept in 35c)
-- ----------------------------------------------------------------------------
-- The Rights page says a removal is recorded permanently rather than simply
-- deleted, so a later crawl cannot quietly bring the same page back. This is
-- that record. It is keyed on the URL rather than on a recipe id because the
-- row it refers to is usually gone by the time anyone reads this table — the
-- point is to refuse the *next* import, not to describe the last one.
--
-- Not world-readable: it names who asked and why.
create table if not exists import_blocklist (
  url         text primary key,
  source_slug text,
  reason      text,
  created_at  timestamptz not null default now()
);
create index if not exists import_blocklist_source_idx
  on import_blocklist (source_slug) where source_slug is not null;

-- ----------------------------------------------------------------------------
-- profile_claims (Phase 35b) — a real chef asking for their imported page
-- ----------------------------------------------------------------------------
-- Approving a claim transfers ownership of every recipe on the claimed profile,
-- so it is never a self-service RLS write. A claimant may file and read; the
-- decision arrives through `approve_profile_claim()` / `reject_profile_claim()`,
-- which have EXECUTE revoked from the API roles.
--
-- `claimant_auth_user_id` is the AUTH id rather than a profile id on purpose:
-- the merge moves the claimant's link, so a profile id recorded here would be
-- pointing at a tombstone the moment the claim succeeded.
create table if not exists profile_claims (
  id                    uuid primary key default gen_random_uuid(),
  profile_id            uuid not null references profiles (id) on delete cascade,
  claimant_auth_user_id uuid not null references auth.users (id) on delete cascade,
  evidence_url          text,
  status                claim_status not null default 'pending',
  note                  text,
  created_at            timestamptz not null default now(),
  decided_at            timestamptz,
  decided_by            uuid references profiles (id) on delete set null
);
create index if not exists profile_claims_profile_idx on profile_claims (profile_id);
create index if not exists profile_claims_claimant_idx on profile_claims (claimant_auth_user_id);
create index if not exists profile_claims_decided_by_idx
  on profile_claims (decided_by) where decided_by is not null;
-- One live claim per claimant per profile. Partial, so a rejected claim can be
-- re-filed with better evidence instead of being blocked forever by its own
-- history.
create unique index if not exists profile_claims_one_pending_idx
  on profile_claims (profile_id, claimant_auth_user_id) where status = 'pending';

-- ============================================================================
-- Functions & triggers
-- ============================================================================

-- Auto-create a profile row when a new auth user is created.
create or replace function handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- `left(…, 80)` rather than letting `profiles_text_lengths` reject it: this
  -- runs inside the signup transaction, so a constraint violation here does not
  -- refuse a display name, it refuses the **account**. The metadata is
  -- unvalidated client input and 80 is far past any real name, so clamping is
  -- the honest failure mode — same spirit as the `on conflict do nothing` below.
  --
  -- `id = new.id` is kept deliberately after the Phase 35b decoupling. The FK is
  -- gone and `profiles.id` now defaults to a fresh uuid, so this could be any
  -- value — but writing the auth uid keeps `profiles.id = auth.uid()` true for
  -- every member, which is what makes the decoupling a no-op for existing data,
  -- existing URLs, existing fixtures and the storage-bucket policies (which
  -- still key folders on `auth.uid()`). Only imported profiles and claimed ones
  -- have an id that is not an auth uid.
  insert into public.profiles (id, auth_user_id, display_name, kind)
  values (
    new.id,
    new.id,
    left(coalesce(new.raw_user_meta_data ->> 'display_name', ''), 80),
    'member'
  )
  on conflict (id) do nothing;   -- never block a signup on an existing profile
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- Backfill profiles for auth users that predate the trigger (or that lost their
-- row to a `db:drop`, which drops `profiles` while auth.users survives). Without
-- this, such a user is signed in but has no profile, and every FK to profiles
-- fails: rating, saving, and even logging a view (B015).
--
-- **The test is `auth_user_id`, not `id`** (Phase 35b). Those were the same
-- question before the decoupling and are not any more: a member who has claimed
-- an imported chef page has their link on the CLAIMED profile, while the
-- original row survives as a `merged_into` tombstone still holding
-- `id = u.id`. Keying on `id` would find that tombstone, conclude the user has
-- an identity, and leave `current_profile_id()` returning null forever — B015
-- back again, wearing a shape the original fix does not cover.
--
-- The `case` in the id column is the other half of the same edge: if a tombstone
-- already occupies `u.id`, the new row takes a fresh uuid instead of colliding
-- with it. On every ordinary database that branch is never taken.
insert into public.profiles (id, auth_user_id, display_name, kind)
select
  case
    when exists (select 1 from public.profiles x where x.id = u.id)
      then gen_random_uuid()
    else u.id
  end,
  u.id,
  left(coalesce(u.raw_user_meta_data ->> 'display_name', ''), 80),
  'member'
from auth.users u
where not exists (
  select 1 from public.profiles p where p.auth_user_id = u.id
);

-- Denormalized counters.
--
-- The counter/aggregate trigger functions are `security definer`: they update a
-- recipe row the acting user does *not* own, and `recipes_update` (RLS) only
-- allows the owner. Without definer rights the UPDATE silently matches 0 rows,
-- so liking/saving/rating someone else's recipe would never move the counter.
-- Helpers (`bump_count`, `recompute_recipe_rating`) stay invoker-rights and have
-- EXECUTE revoked below, so they are not reachable as PostgREST RPCs.
create or replace function bump_count(p_recipe uuid, p_col text, p_delta int)
returns void language plpgsql as $$
begin
  execute format('update recipes set %I = greatest(0, %I + $1) where id = $2', p_col, p_col)
    using p_delta, p_recipe;
end;
$$;

create or replace function on_like_change()
returns trigger language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then perform bump_count(new.recipe_id, 'like_count', 1);
  elsif tg_op = 'DELETE' then perform bump_count(old.recipe_id, 'like_count', -1);
  end if;
  return null;
end;
$$;
drop trigger if exists recipe_likes_count on recipe_likes;
create trigger recipe_likes_count
  after insert or delete on recipe_likes
  for each row execute function on_like_change();

create or replace function on_save_change()
returns trigger language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then perform bump_count(new.recipe_id, 'save_count', 1);
  elsif tg_op = 'DELETE' then perform bump_count(old.recipe_id, 'save_count', -1);
  end if;
  return null;
end;
$$;
drop trigger if exists recipe_saves_count on recipe_saves;
create trigger recipe_saves_count
  after insert or delete on recipe_saves
  for each row execute function on_save_change();

-- View counts (B012). `recipe_views` stays an append-only log — every visit
-- inserts a row — but `recipes.view_count` counts *distinct signed-in viewers*:
--
--   * Anonymous views are logged and never counted. `anon` holds `insert` on this
--     table, so counting them would let an unauthenticated loop inflate
--     `recipes_trending` (which scores like_count + view_count) for free.
--   * Only the first row for a (recipe, user) pair bumps the counter, so a
--     refresh loop cannot inflate it either.
--
-- The counter is monotonic: nothing decrements it. `recipe_views.user_id` is
-- `on delete set null` (unlike recipe_likes/saves, which cascade and fire their
-- DELETE branch), so a deleted account leaves its contribution behind. Treat
-- `view_count` as an upper bound on distinct viewers, not an exact count.
--
-- Deliberately no unique index: PostgREST cannot express `on conflict` inference
-- against a *partial* index, so a duplicate would surface to the client as a
-- 23505 instead of being ignored. Deduping in the trigger keeps `logView()` a
-- plain insert and keeps the full view log for future analytics. The cost is
-- that the probe below is a read-then-write, so it takes a per-(recipe, user)
-- advisory lock — without it, two concurrent first-views from the same account
-- (two tabs, a double-tap) each miss the other's uncommitted row and both bump.
--
-- `security definer` is required for TWO independent reasons, and dropping it
-- fails silently on both counts:
--   1. B011: the trigger updates a `recipes` row the viewer does not own, and
--      `recipes_update` (RLS) only allows the owner — the UPDATE would match 0
--      rows with no error.
--   2. The dedup probe reads `recipe_views`, which `views_select` restricts to
--      `owns_recipe(recipe_id)`. Under invoker rights that probe returns 0 rows
--      for every non-owner, so `not exists` is always true and *every* view
--      would count.
create or replace function on_view_insert()
returns trigger language plpgsql
security definer
set search_path = public
as $$
begin
  if new.user_id is null then
    return null;
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(new.recipe_id::text || new.user_id::text, 0)
  );

  if not exists (
    select 1 from recipe_views
    where recipe_id = new.recipe_id
      and user_id = new.user_id
      and id <> new.id
  ) then
    perform bump_count(new.recipe_id, 'view_count', 1);
  end if;
  return null;
end;
$$;
drop trigger if exists recipe_views_count on recipe_views;
create trigger recipe_views_count
  after insert on recipe_views
  for each row execute function on_view_insert();

-- Rating aggregates. Recomputed from recipe_ratings (exact — never drifts).
create or replace function recompute_recipe_rating(p_recipe uuid)
returns void language sql as $$
  update recipes r
  set rating_count = s.cnt,
      rating_sum   = s.total,
      rating_avg   = case when s.cnt = 0 then 0 else round(s.total / s.cnt, 2) end
  from (
    select count(*)::int as cnt, coalesce(sum(rating), 0) as total
    from recipe_ratings where recipe_id = p_recipe
  ) s
  where r.id = p_recipe;
$$;

create or replace function on_rating_change()
returns trigger language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    perform recompute_recipe_rating(old.recipe_id);
  else
    perform recompute_recipe_rating(new.recipe_id);
    -- a moved rating (rare) has to fix up the old recipe too
    if tg_op = 'UPDATE' and old.recipe_id <> new.recipe_id then
      perform recompute_recipe_rating(old.recipe_id);
    end if;
  end if;
  return null;
end;
$$;
drop trigger if exists recipe_ratings_agg on recipe_ratings;
create trigger recipe_ratings_agg
  after insert or update or delete on recipe_ratings
  for each row execute function on_rating_change();

-- ----------------------------------------------------------------------------
-- Chef score & tier (Phase 18)
--
-- "Chef" is a presentation of `profiles`, not a second principal table. The two
-- functions below are the single source of truth for the formula and the
-- thresholds: changing either is a one-function edit plus the idempotent
-- backfill further down, which runs on every apply.
--
-- Only PUBLIC recipes count. Private-recipe engagement (reachable through
-- recipe_shares) must never leak into a world-readable number, so flipping a
-- recipe private or deleting it drops its contribution on the next recompute.
--
-- Sums are bigint: view_count in particular is unbounded, and int would
-- overflow long before numeric does.
-- ----------------------------------------------------------------------------
create or replace function chef_score(p_likes bigint, p_saves bigint, p_views bigint)
returns numeric language sql immutable as $$
  -- A save is the strongest intent signal, a like weaker, a view weakest (and
  -- view_count is already deduped + anon-excluded — B012 — so it is safe to
  -- include at a low weight). Ratings are deliberately out of the v1 formula.
  select 3 * coalesce(p_likes, 0)
       + 5 * coalesce(p_saves, 0)
       + 0.2 * coalesce(p_views, 0);
$$;

create or replace function chef_tier_for(p_score numeric)
returns chef_tier language sql immutable as $$
  select case
    when coalesce(p_score, 0) >= 20000 then 'master_chef'
    when coalesce(p_score, 0) >=  5000 then 'head_chef'
    when coalesce(p_score, 0) >=  1000 then 'sous_chef'
    when coalesce(p_score, 0) >=   100 then 'line_cook'
    else 'home_cook'
  end::chef_tier;
$$;

-- Recompute one chef's standing from scratch (never incremental), exactly the
-- recompute_recipe_rating pattern — the denormalized values cannot drift.
-- Invoker-rights with EXECUTE revoked below: PostgREST exposes every function in
-- `public` as an RPC, and this one writes other users' profile rows.
--
-- The `is distinct from` guard is load-bearing, not tidiness: the trigger also
-- watches rating_sum/rating_count (so a future rating term needs no trigger
-- change), but the v1 formula ignores them — so every rating anyone writes
-- would otherwise rewrite the owner's profile row with byte-identical values
-- and leave a dead tuple behind, on a table read by every leaderboard query
-- and every recipe embed.
-- The engagement totals are persisted alongside the score (OPT-P5), not just
-- fed to chef_score() and discarded: the leaderboard shows them next to the
-- score, and re-deriving them there meant a full aggregate over every public
-- recipe on every page of a board whose ranking column was already denormalized.
-- They are written by the same statement that writes the score, so the three
-- numbers and the score they explain can never disagree.
create or replace function recompute_chef_stats(p_chef uuid)
returns void language sql as $$
  update profiles p
  set public_recipe_count = s.cnt,
      total_likes         = s.likes,
      total_saves         = s.saves,
      total_views         = s.views,
      chef_score          = s.score,
      chef_tier           = chef_tier_for(s.score)
  from (
    select a.cnt, a.likes, a.saves, a.views,
           chef_score(a.likes, a.saves, a.views) as score
    from (
      select
        count(*)::int                          as cnt,
        coalesce(sum(like_count), 0)::bigint    as likes,
        coalesce(sum(save_count), 0)::bigint    as saves,
        coalesce(sum(view_count), 0)::bigint    as views
      from recipes
      where owner_id = p_chef and visibility = 'public'
    ) a
  ) s
  where p.id = p_chef
    and (p.public_recipe_count, p.total_likes, p.total_saves, p.total_views,
         p.chef_score, p.chef_tier)
        is distinct from (s.cnt, s.likes, s.saves, s.views,
                          s.score, chef_tier_for(s.score));
$$;

-- `security definer set search_path = public` is mandatory (B011 class): the
-- acting user is whoever liked/saved/viewed the recipe, and `profiles_update`
-- (RLS) is self-only — under invoker rights this UPDATE would match 0 rows for
-- every non-owner, silently, with no error.
--
-- No recursion: it writes `profiles`, never `recipes`.
--
-- rating_sum/rating_count are watched even though the v1 formula ignores them,
-- so adding a rating term later needs no trigger change.
create or replace function on_recipe_stats_change()
returns trigger language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    perform recompute_chef_stats(old.owner_id);
  elsif tg_op = 'INSERT' then
    perform recompute_chef_stats(new.owner_id);
  else
    perform recompute_chef_stats(new.owner_id);
    if old.owner_id <> new.owner_id then
      perform recompute_chef_stats(old.owner_id);   -- recipe changed hands
    end if;
  end if;
  return null;
end;
$$;

drop trigger if exists recipes_chef_stats on recipes;
create trigger recipes_chef_stats
  after insert or delete or update of
    like_count, save_count, view_count, rating_sum, rating_count,
    visibility, owner_id
  on recipes
  for each row execute function on_recipe_stats_change();

-- The whole-table form of recompute_chef_stats: one set-based pass over every
-- profile instead of one aggregate per chef.
--
-- It exists because three call sites need exactly this statement — the
-- idempotent backfill below, the sim's bulk load (`2_sim_generate.sql`, which
-- runs with `recipes_chef_stats` disabled) and the sim teardown
-- (`9_sim_teardown.sql`, which has just deleted rows behind the triggers'
-- backs). All three used to restate it, so OPT-P5's three new columns would
-- have had to be added in three places, and Gotcha 19 (never restate the
-- formula) was one copy-paste away from being violated.
--
-- Invoker-rights like recompute_chef_stats, with EXECUTE revoked below for the
-- same reason: it writes every profile row in the table.
create or replace function recompute_all_chef_stats()
returns void language sql as $$
  update profiles p
  set public_recipe_count = s.cnt,
      total_likes         = s.likes,
      total_saves         = s.saves,
      total_views         = s.views,
      chef_score          = s.score,
      chef_tier           = chef_tier_for(s.score)
  from (
    select a.id, a.cnt, a.likes, a.saves, a.views,
           chef_score(a.likes, a.saves, a.views) as score
    from (
      select
        pr.id,
        count(r.id)::int                         as cnt,
        coalesce(sum(r.like_count), 0)::bigint    as likes,
        coalesce(sum(r.save_count), 0)::bigint    as saves,
        coalesce(sum(r.view_count), 0)::bigint    as views
      from profiles pr
      left join recipes r
        on r.owner_id = pr.id and r.visibility = 'public'
      -- Phase 35b/c: members only. An imported chef's stat columns stay at
      -- their zero defaults — deliberately, and for two reasons that happen to
      -- agree. Product: the corpus arrives with no engagement, so any score
      -- computed over it is a score of zero dressed up as a measurement.
      -- Ethics: these are real named people who never signed up, and ranking
      -- them by engagement they never sought is not something to do by
      -- accident. It also keeps this whole-table pass proportional to the
      -- MEMBER count rather than to the corpus, which is what stops every
      -- apply of this file getting slower as the import grows.
      where pr.kind = 'member'
      group by pr.id
    ) a
  ) s
  where p.id = s.id
    and (p.public_recipe_count, p.total_likes, p.total_saves, p.total_views,
         p.chef_score, p.chef_tier)
        is distinct from (s.cnt, s.likes, s.saves, s.views,
                          s.score, chef_tier_for(s.score));
$$;

-- Idempotent backfill (B015 precedent): recompute every profile on every apply.
-- This is also how a formula or threshold change reaches existing rows.
select recompute_all_chef_stats();

-- updated_at maintenance.
create or replace function touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;
drop trigger if exists recipes_touch on recipes;
create trigger recipes_touch
  before update on recipes
  for each row execute function touch_updated_at();

drop trigger if exists recipe_ratings_touch on recipe_ratings;
create trigger recipe_ratings_touch
  before update on recipe_ratings
  for each row execute function touch_updated_at();

-- `recipes.current_version_id` is server-owned: the client appends a
-- `recipe_versions` row and the pointer follows here. That is what lets the
-- column stay out of the `authenticated` UPDATE grant below (B050) — before
-- this trigger the repository PATCHed it directly, so "trigger-maintained" was
-- only ever true on paper. `security definer` is required for the Gotcha 3
-- reason *and* a new one: under column-level grants an invoker-rights UPDATE of
-- a column the role does not hold fails outright rather than matching 0 rows.
-- Versions are append-only and the newest is always current, so last-in wins.
create or replace function on_version_insert()
returns trigger language plpgsql
security definer
set search_path = public
as $$
begin
  update recipes set current_version_id = new.id where id = new.recipe_id;
  return null;
end;
$$;
drop trigger if exists recipe_versions_set_current on recipe_versions;
create trigger recipe_versions_set_current
  after insert on recipe_versions
  for each row execute function on_version_insert();

-- Counter helpers are trigger-internal. PostgREST exposes every function in
-- `public` as an RPC, so drop EXECUTE for the API roles — otherwise any client
-- could call bump_count() directly and forge like/save counts.
do $$
begin
  execute 'revoke execute on function bump_count(uuid, text, int) from public';
  execute 'revoke execute on function recompute_recipe_rating(uuid) from public';
  execute 'revoke execute on function recompute_chef_stats(uuid) from public';
  execute 'revoke execute on function recompute_all_chef_stats() from public';
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke execute on function bump_count(uuid, text, int) from anon, authenticated';
    execute 'revoke execute on function recompute_recipe_rating(uuid) from anon, authenticated';
    execute 'revoke execute on function recompute_chef_stats(uuid) from anon, authenticated';
    execute 'revoke execute on function recompute_all_chef_stats() from anon, authenticated';
  end if;
end $$;

-- ============================================================================
-- Full-text search document (OPT-P1)
--
-- The document spans four tables — title, description, ingredient names, tag
-- names — so a Postgres GENERATED column cannot produce it (those may only
-- reference the row's own columns). It is therefore a plain column kept current
-- by triggers, which is the only shape that can be GIN-indexed.
--
-- Before this, `recipes_search` called `recipe_search_document(r.id)` — four
-- subqueries — once per public recipe in the WHERE and again per match in the
-- ORDER BY, with nothing indexable: 540 ms per search at 1,344 public recipes.
--
-- `search_tsv` is server-owned. It is deliberately absent from the column
-- grants in the block below, so the triggers that write it must be
-- `security definer` (same reason as `recipe_versions_set_current`).
-- ============================================================================
alter table recipes add column if not exists search_tsv tsvector;
create index if not exists recipes_search_tsv_idx on recipes using gin (search_tsv);

-- THE definition of the document, and the only one. Takes title/description as
-- arguments rather than reading them back by id, because the `recipes` trigger
-- below is a BEFORE trigger on a row that is not in the statement snapshot yet
-- — looking it up would return nothing on INSERT (the B053 trap).
create or replace function recipe_search_tsv(
  p_recipe uuid, p_title text, p_description text
)
returns tsvector language sql stable as $$
  select
    setweight(to_tsvector('english', coalesce(p_title, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(p_description, '')), 'B') ||
    setweight(to_tsvector('english', coalesce(
      (select string_agg(i.name, ' ')
       from ingredients i
       join ingredient_groups g on g.id = i.group_id
       where g.recipe_id = p_recipe), '')), 'C') ||
    setweight(to_tsvector('english', coalesce(
      (select string_agg(t.name, ' ')
       from recipe_tags rt join tags t on t.id = rt.tag_id
       where rt.recipe_id = p_recipe), '')), 'C');
$$;

-- Kept as the by-id form for backfills and ad-hoc checks; delegates so there is
-- exactly one definition of the document to keep in sync.
create or replace function recipe_search_document(p_recipe uuid)
returns tsvector language sql stable as $$
  select recipe_search_tsv(p_recipe, r.title, r.description)
  from recipes r where r.id = p_recipe;
$$;

-- The recipes half: BEFORE, so the value is written in the same row write with
-- no extra UPDATE and no recursion. Scoped to the two columns that matter, so a
-- counter bump or a `search_tsv` write does not re-fire it.
create or replace function on_recipe_search_change()
returns trigger language plpgsql as $$
begin
  new.search_tsv := recipe_search_tsv(new.id, new.title, new.description);
  return new;
end;
$$;
drop trigger if exists recipes_search_tsv on recipes;
create trigger recipes_search_tsv
  before insert or update of title, description on recipes
  for each row execute function on_recipe_search_change();

-- The child half. STATEMENT-level with transition tables, not row-level: one
-- editor save re-inserts every ingredient of the recipe, and the sim bulk-loads
-- tens of thousands of rows — per-row would mean one full document rebuild per
-- ingredient. `security definer` because these write `recipes.search_tsv`,
-- which no API role is granted, and because the acting user need not own the
-- recipe a tag rename touches.
create or replace function refresh_search_tsv(p_recipes uuid[])
returns void language sql security definer set search_path = public as $$
  update recipes r
     set search_tsv = recipe_search_tsv(r.id, r.title, r.description)
   where r.id = any(p_recipes);
$$;

create or replace function on_ingredients_search_change()
returns trigger language plpgsql
security definer set search_path = public as $$
begin
  -- Resolved through ingredient_groups, which still exists for a direct
  -- ingredient delete. A *group* delete cascades its ingredients away and is
  -- handled by the group trigger below instead, using the group's own recipe_id.
  if tg_op = 'DELETE' then
    perform refresh_search_tsv(array(
      select distinct g.recipe_id from oldtab o
      join ingredient_groups g on g.id = o.group_id));
  else
    perform refresh_search_tsv(array(
      select distinct g.recipe_id from newtab n
      join ingredient_groups g on g.id = n.group_id));
  end if;
  return null;
end;
$$;
drop trigger if exists ingredients_search_tsv_ins on ingredients;
create trigger ingredients_search_tsv_ins after insert on ingredients
  referencing new table as newtab
  for each statement execute function on_ingredients_search_change();
drop trigger if exists ingredients_search_tsv_upd on ingredients;
create trigger ingredients_search_tsv_upd after update on ingredients
  referencing new table as newtab
  for each statement execute function on_ingredients_search_change();
drop trigger if exists ingredients_search_tsv_del on ingredients;
create trigger ingredients_search_tsv_del after delete on ingredients
  referencing old table as oldtab
  for each statement execute function on_ingredients_search_change();

-- Group deletes: the cascade removes the ingredients first, so by the time the
-- ingredient trigger runs the group is gone and the join finds nothing. Catch
-- it here, where `recipe_id` is on the row itself.
create or replace function on_ingredient_groups_search_change()
returns trigger language plpgsql
security definer set search_path = public as $$
begin
  if tg_op = 'DELETE' then
    perform refresh_search_tsv(array(select distinct recipe_id from oldtab));
  else
    perform refresh_search_tsv(array(select distinct recipe_id from newtab));
  end if;
  return null;
end;
$$;
drop trigger if exists ig_search_tsv_del on ingredient_groups;
create trigger ig_search_tsv_del after delete on ingredient_groups
  referencing old table as oldtab
  for each statement execute function on_ingredient_groups_search_change();
drop trigger if exists ig_search_tsv_upd on ingredient_groups;
create trigger ig_search_tsv_upd after update on ingredient_groups
  referencing new table as newtab
  for each statement execute function on_ingredient_groups_search_change();

create or replace function on_recipe_tags_search_change()
returns trigger language plpgsql
security definer set search_path = public as $$
begin
  if tg_op = 'DELETE' then
    perform refresh_search_tsv(array(select distinct recipe_id from oldtab));
  else
    perform refresh_search_tsv(array(select distinct recipe_id from newtab));
  end if;
  return null;
end;
$$;
drop trigger if exists recipe_tags_search_tsv_ins on recipe_tags;
create trigger recipe_tags_search_tsv_ins after insert on recipe_tags
  referencing new table as newtab
  for each statement execute function on_recipe_tags_search_change();
drop trigger if exists recipe_tags_search_tsv_del on recipe_tags;
create trigger recipe_tags_search_tsv_del after delete on recipe_tags
  referencing old table as oldtab
  for each statement execute function on_recipe_tags_search_change();

-- Renaming a tag changes the document of every recipe carrying it. Postgres
-- rejects `update of name` alongside transition tables ("transition tables
-- cannot be specified for triggers with column lists"), so the trigger takes
-- every UPDATE and both transition tables, and the name comparison moves into
-- the body — which also keeps a no-op UPDATE from rebuilding documents.
create or replace function on_tags_search_change()
returns trigger language plpgsql
security definer set search_path = public as $$
begin
  perform refresh_search_tsv(array(
    select distinct rt.recipe_id
    from newtab n
    join oldtab o on o.id = n.id
    join recipe_tags rt on rt.tag_id = n.id
    where n.name is distinct from o.name));
  return null;
end;
$$;
drop trigger if exists tags_search_tsv_upd on tags;
create trigger tags_search_tsv_upd after update on tags
  referencing old table as oldtab new table as newtab
  for each statement execute function on_tags_search_change();

-- Backfill on every apply, for rows that predate the column. Bounded by the
-- `is null` guard so a re-apply is a no-op rather than a full rebuild.
update recipes
   set search_tsv = recipe_search_tsv(id, title, description)
 where search_tsv is null;

-- Trigger-internal; PostgREST exposes every public function as an RPC.
do $$
begin
  execute 'revoke execute on function refresh_search_tsv(uuid[]) from public';
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke execute on function refresh_search_tsv(uuid[]) from anon, authenticated';
  end if;
end $$;

-- ============================================================================
-- Row-Level Security
-- Authorization is enforced here; the client never bypasses these.
-- ============================================================================

-- Helper: can the current user read a given recipe?
create or replace function can_read_recipe(p_recipe uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from recipes r
    where r.id = p_recipe
      and (
        r.visibility = 'public'
        or r.owner_id = current_profile_id()
        or exists (
          select 1 from recipe_shares s
          where s.recipe_id = r.id and s.shared_with_user_id = current_profile_id()
        )
      )
  );
$$;

create or replace function owns_recipe(p_recipe uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from recipes r where r.id = p_recipe and r.owner_id = current_profile_id());
$$;

-- Enable RLS
alter table profiles            enable row level security;
alter table recipes             enable row level security;
alter table recipe_versions     enable row level security;
alter table ingredient_groups   enable row level security;
alter table ingredients         enable row level security;
alter table step_groups         enable row level security;
alter table steps               enable row level security;
alter table tags                enable row level security;
alter table recipe_tags         enable row level security;
alter table recipe_shares       enable row level security;
alter table recipe_likes        enable row level security;
alter table recipe_saves        enable row level security;
alter table recipe_views        enable row level security;
alter table recipe_ratings      enable row level security;
alter table recipe_suggestions  enable row level security;
alter table food                enable row level security;
alter table food_alias          enable row level security;
alter table food_portion        enable row level security;
alter table food_unit           enable row level security;
alter table entities                enable row level security;
alter table entity_members          enable row level security;
alter table entity_signature_dishes enable row level security;
alter table profile_claims          enable row level security;
alter table import_blocklist        enable row level security;

-- profiles: world-readable, self-writable
--
-- World-readable covers imported profiles too, and that is the intent: a chef
-- the corpus credits has a public page exactly like a member's, because the
-- credit is the whole reason the row exists (Phase 35a).
drop policy if exists profiles_select on profiles;
create policy profiles_select on profiles for select using (true);

-- `current_profile_id()`, not `auth.uid()` — so a member who has CLAIMED an
-- imported chef page edits that page, which is the point of claiming. An
-- imported profile has no `auth_user_id`, so `current_profile_id()` never
-- returns it and it is immutable by construction: no extra policy, no extra
-- predicate, nothing to forget.
drop policy if exists profiles_update on profiles;
create policy profiles_update on profiles for update using (id = current_profile_id());

-- Insert is the one identity predicate that CANNOT use `current_profile_id()`:
-- the row this statement is checking is the row that would make the lookup
-- succeed, so the function returns null and every insert would fail. It stays
-- on `auth.uid()` and pins the link in the same breath — a client may create
-- only its own self-linked `member` profile, and `unique(auth_user_id)` stops a
-- second one. `kind` is absent from the column grants, so it resolves to its
-- `member` default and the predicate re-states that rather than trusting it.
--
-- This path is vestigial in practice (`handle_new_user` and the B015 backfill
-- are the real writers) and is kept as the self-heal it has always been.
drop policy if exists profiles_insert on profiles;
create policy profiles_insert on profiles for insert
  with check (id = auth.uid() and auth_user_id = auth.uid() and kind = 'member');

-- recipes
--
-- This policy is deliberately NOT `can_read_recipe(id)` (B053). Postgres applies
-- the SELECT policy to the rows an `INSERT … RETURNING` gives back, and
-- `can_read_recipe` is `stable`, so it reads the *statement* snapshot — which
-- cannot contain the row that same statement is inserting. It returned false for
-- every create, and `create()` (`.insert(…).select().single()`, which PostgREST
-- sends as `INSERT … RETURNING`) failed with "new row violates row-level
-- security policy" before the owner test could ever pass. Comparing the row's own
-- columns has no such problem: `visibility` / `owner_id` resolve against the new
-- row directly. It is also cheaper — no `security definer` call per row scanned.
-- `shares_self_select` (`shared_with_user_id = current_profile_id()`) is what keeps the
-- shares subquery working under invoker rights. `can_read_recipe(uuid)` stays for
-- the child tables, which pass a *parent* recipe id that genuinely needs a lookup.
drop policy if exists recipes_select on recipes;
create policy recipes_select on recipes for select using (
  visibility = 'public'
  or owner_id = current_profile_id()
  or exists (
    select 1 from recipe_shares s
    where s.recipe_id = recipes.id and s.shared_with_user_id = current_profile_id()
  )
);
drop policy if exists recipes_insert on recipes;
create policy recipes_insert on recipes for insert with check (owner_id = current_profile_id());
drop policy if exists recipes_update on recipes;
create policy recipes_update on recipes for update using (owner_id = current_profile_id());
drop policy if exists recipes_delete on recipes;
create policy recipes_delete on recipes for delete using (owner_id = current_profile_id());

-- recipe_versions: readable if parent recipe readable; writable by owner
drop policy if exists versions_select on recipe_versions;
create policy versions_select on recipe_versions for select using (can_read_recipe(recipe_id));
drop policy if exists versions_insert on recipe_versions;
create policy versions_insert on recipe_versions for insert with check (owns_recipe(recipe_id));

-- child content tables (read follows recipe visibility; write requires ownership)
drop policy if exists ig_select on ingredient_groups;
create policy ig_select on ingredient_groups for select using (can_read_recipe(recipe_id));
drop policy if exists ig_write on ingredient_groups;
create policy ig_write  on ingredient_groups for all
  using (owns_recipe(recipe_id)) with check (owns_recipe(recipe_id));

drop policy if exists ing_select on ingredients;
create policy ing_select on ingredients for select
  using (can_read_recipe((select g.recipe_id from ingredient_groups g where g.id = group_id)));
drop policy if exists ing_write on ingredients;
create policy ing_write on ingredients for all
  using (owns_recipe((select g.recipe_id from ingredient_groups g where g.id = group_id)))
  with check (owns_recipe((select g.recipe_id from ingredient_groups g where g.id = group_id)));

drop policy if exists sg_select on step_groups;
create policy sg_select on step_groups for select using (can_read_recipe(recipe_id));
drop policy if exists sg_write on step_groups;
create policy sg_write  on step_groups for all
  using (owns_recipe(recipe_id)) with check (owns_recipe(recipe_id));

drop policy if exists steps_select on steps;
create policy steps_select on steps for select
  using (can_read_recipe((select g.recipe_id from step_groups g where g.id = group_id)));
drop policy if exists steps_write on steps;
create policy steps_write on steps for all
  using (owns_recipe((select g.recipe_id from step_groups g where g.id = group_id)))
  with check (owns_recipe((select g.recipe_id from step_groups g where g.id = group_id)));

-- tags: a shared, free-form namespace — readable by all, created by any signed-in
-- user, because a tag has to exist before the recipe that needs it can reference
-- it. That decision stands (OPT-A6); tags are not owned, so owner-curated tags
-- would mean a tag per owner and a discovery surface that cannot join them.
--
-- What was missing is a way **back out**. Insert-only meant one typo — `deserrt`
-- — was permanent, in a namespace every recipe shares. So:
--
--   * DELETE is allowed, but only for a tag **nothing references**. The
--     `not exists` is the whole safety property: removing a tag in use would
--     cascade `recipe_tags` rows out of other people's recipes and silently
--     rewrite their search documents.
--   * UPDATE stays closed. A rename changes the document of every recipe
--     carrying the tag (the `tags_search_tsv_upd` trigger exists for exactly
--     that), which is not something one user should do to another's recipe.
drop policy if exists tags_select on tags;
create policy tags_select on tags for select using (true);
drop policy if exists tags_insert on tags;
create policy tags_insert on tags for insert with check (auth.uid() is not null);
drop policy if exists tags_delete_orphan on tags;
create policy tags_delete_orphan on tags for delete
  using (
    auth.uid() is not null
    and not exists (select 1 from recipe_tags rt where rt.tag_id = tags.id)
  );

drop policy if exists recipe_tags_select on recipe_tags;
create policy recipe_tags_select on recipe_tags for select using (can_read_recipe(recipe_id));
drop policy if exists recipe_tags_write on recipe_tags;
create policy recipe_tags_write on recipe_tags for all
  using (owns_recipe(recipe_id)) with check (owns_recipe(recipe_id));

-- recipe_shares: owner manages; shared user can read own row
drop policy if exists shares_owner_all on recipe_shares;
create policy shares_owner_all on recipe_shares for all
  using (owns_recipe(recipe_id)) with check (owns_recipe(recipe_id));
drop policy if exists shares_self_select on recipe_shares;
create policy shares_self_select on recipe_shares for select
  using (shared_with_user_id = current_profile_id());

-- likes / saves: a user manages their own rows, and may only add one to a recipe
-- they can actually read.
--
-- The `can_read_recipe` half is in `with check` ONLY, and the split is the whole
-- point (B061). `with check` governs INSERT, so a signed-in user who guesses a
-- private recipe's uuid cannot like it into an inflated `like_count` that the
-- owner then publishes — the hole `ratings_write` and `views_insert` were already
-- closed against and these two were not. `using` governs SELECT/UPDATE/DELETE and
-- stays `user_id = current_profile_id()` alone, so an existing like can always be removed:
-- adding the read test there would strand every liker's row the moment an owner
-- flipped a recipe to private, and unliking would then match 0 rows and report
-- success (Gotcha 2).
drop policy if exists likes_select on recipe_likes;
create policy likes_select on recipe_likes for select using (can_read_recipe(recipe_id));
drop policy if exists likes_write on recipe_likes;
create policy likes_write on recipe_likes for all
  using (user_id = current_profile_id())
  with check (user_id = current_profile_id() and can_read_recipe(recipe_id));

drop policy if exists saves_select on recipe_saves;
create policy saves_select on recipe_saves for select using (user_id = current_profile_id());
drop policy if exists saves_write on recipe_saves;
create policy saves_write on recipe_saves for all
  using (user_id = current_profile_id())
  with check (user_id = current_profile_id() and can_read_recipe(recipe_id));

-- ratings: readable with the recipe; a user writes only their own row, only for a
-- recipe they can read, and never for their own recipe (no self-rating).
drop policy if exists ratings_select on recipe_ratings;
create policy ratings_select on recipe_ratings for select using (can_read_recipe(recipe_id));
drop policy if exists ratings_write on recipe_ratings;
create policy ratings_write on recipe_ratings for all
  using (user_id = current_profile_id())
  with check (
    user_id = current_profile_id()
    and can_read_recipe(recipe_id)
    and not owns_recipe(recipe_id)
  );

-- views: anyone who can read the recipe may log a view
-- A visitor may log a view of a recipe they can read, but only as themselves.
-- Without the user_id clause any client could attribute views to another user —
-- which now moves `recipes.view_count` via on_view_insert().
drop policy if exists views_insert on recipe_views;
create policy views_insert on recipe_views for insert
  with check (
    can_read_recipe(recipe_id)
    and (user_id is null or user_id = current_profile_id())
  );
drop policy if exists views_select on recipe_views;
create policy views_select on recipe_views for select using (owns_recipe(recipe_id));

-- suggestions (reserved): author or target-recipe owner can read; author can create
drop policy if exists suggestions_select on recipe_suggestions;
create policy suggestions_select on recipe_suggestions for select
  using (author_id = current_profile_id() or owns_recipe(recipe_id));
drop policy if exists suggestions_insert on recipe_suggestions;
create policy suggestions_insert on recipe_suggestions for insert
  with check (author_id = current_profile_id());
drop policy if exists suggestions_update on recipe_suggestions;
-- 32a3: `using` decides which rows an UPDATE may *touch*; `with check` decides
-- what they may be turned *into*, and this policy had only the first — so the
-- owner could re-point `recipe_id` at **any** recipe and carry someone's
-- suggestion onto it.
--
-- What actually stops that today is the **column grant** below, which does not
-- include `recipe_id`: a client attempt fails `42501` at the privilege check,
-- before RLS is consulted. So be honest about this clause — it is
-- belt-and-braces for the day that grant list widens, and **no check in
-- `rls_matrix.sql` can reach it**, because every column a client may write
-- (`status` alone) leaves `owns_recipe(recipe_id)` unchanged, which makes the
-- expression a tautology on every reachable path. It is kept for the same
-- reason `fork_recipe` keeps its `auth.uid() is null` guard beside its revoke:
-- two locks, and the grant is the one being tested.
--
-- Authorship is held by the column grant too, not by a policy — "this column
-- may not change" is a column statement, and expressing it here would mean a
-- `with check` subquery reading `recipe_suggestions` by its own id, the B053
-- shape in the one file whose job is to catch that.
create policy suggestions_update on recipe_suggestions for update
  using (owns_recipe(recipe_id))
  with check (owns_recipe(recipe_id));

-- food registry (Phase 29a): reference data, readable signed-in only, written
-- exclusively by nutrition_foods.sql running as postgres. Select-only policies
-- + zero write policies; the grants block below also revokes the write GRANTs,
-- so a client write fails 42501 at the grant layer before RLS is consulted.
-- `anon` gets no policy at all: the detail page reads the stored label, and
-- only the signed-in editor needs the registry (Gotcha 3's least-surface rule).
drop policy if exists food_select on food;
create policy food_select on food for select
  using (auth.uid() is not null);
drop policy if exists food_alias_select on food_alias;
create policy food_alias_select on food_alias for select
  using (auth.uid() is not null);
drop policy if exists food_portion_select on food_portion;
create policy food_portion_select on food_portion for select
  using (auth.uid() is not null);
drop policy if exists food_unit_select on food_unit;
create policy food_unit_select on food_unit for select
  using (auth.uid() is not null);

-- ----------------------------------------------------------------------------
-- entities / entity_members / entity_signature_dishes (Phase 35b)
-- ----------------------------------------------------------------------------
-- Membership predicates. `security definer` for the same reason
-- `can_read_recipe` is: a policy on `entity_members` must not decide whether
-- the caller may find out that they are a member. `stable` so Postgres
-- evaluates them once per statement, not once per row. Both are read-only and
-- disclose only the caller's own membership, so — like `can_read_recipe` —
-- EXECUTE is deliberately not revoked; the policies below need the API roles to
-- hold it.
create or replace function is_entity_member(p_entity uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from entity_members m
    where m.entity_id = p_entity and m.profile_id = current_profile_id()
  );
$$;

create or replace function is_entity_owner(p_entity uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from entity_members m
    where m.entity_id = p_entity
      and m.profile_id = current_profile_id()
      and m.role = 'owner'
  );
$$;

-- A public directory: world-readable, exactly like `profiles`.
drop policy if exists entities_select on entities;
create policy entities_select on entities for select using (true);

-- Anyone signed in may register an entity, and `created_by` is pinned so the
-- provenance cannot be forged. The creator does NOT become an owner by this
-- policy alone — `entity_members_insert` below is what seats them, and it is
-- deliberately written so the first seat on a brand-new entity is available to
-- its creator (otherwise no entity could ever gain its first owner).
drop policy if exists entities_insert on entities;
create policy entities_insert on entities for insert
  with check (created_by = current_profile_id());

drop policy if exists entities_update on entities;
create policy entities_update on entities for update
  using (is_entity_owner(id)) with check (is_entity_owner(id));

drop policy if exists entities_delete on entities;
create policy entities_delete on entities for delete using (is_entity_owner(id));

-- The roster is public: an entity that lists its chefs is the whole point.
drop policy if exists entity_members_select on entity_members;
create policy entity_members_select on entity_members for select using (true);

-- Two ways in, and the second is not a convenience: an entity with no members
-- has no owner, so without the bootstrap clause nobody could ever add one and
-- every newly created entity would be permanently unmanageable. The clause is
-- narrow — it applies only while the entity has zero members, and only to the
-- profile that created it.
drop policy if exists entity_members_insert on entity_members;
create policy entity_members_insert on entity_members for insert
  with check (
    is_entity_owner(entity_id)
    or (
      not exists (select 1 from entity_members m where m.entity_id = entity_members.entity_id)
      and profile_id = current_profile_id()
      and exists (
        select 1 from entities e
        where e.id = entity_members.entity_id and e.created_by = current_profile_id()
      )
    )
  );

-- Membership changes are an owner action. A member leaving is the one thing a
-- non-owner may do to this table, and it is a delete of their own row.
drop policy if exists entity_members_update on entity_members;
create policy entity_members_update on entity_members for update
  using (is_entity_owner(entity_id)) with check (is_entity_owner(entity_id));

drop policy if exists entity_members_delete on entity_members;
create policy entity_members_delete on entity_members for delete
  using (is_entity_owner(entity_id) or profile_id = current_profile_id());

-- Signature dishes are public, and a private recipe may never be one: the table
-- is world-readable, so listing a private recipe here would leak its existence
-- and its id to everybody. The `with check` says `public` explicitly rather
-- than leaning on `can_read_recipe`, which would be true for the owner.
drop policy if exists entity_signature_select on entity_signature_dishes;
create policy entity_signature_select on entity_signature_dishes for select using (true);

drop policy if exists entity_signature_write on entity_signature_dishes;
create policy entity_signature_write on entity_signature_dishes for all
  using (is_entity_member(entity_id))
  with check (
    is_entity_member(entity_id)
    and exists (
      select 1 from recipes r
      join entity_members m
        on m.entity_id = entity_signature_dishes.entity_id
       and m.profile_id = r.owner_id
      where r.id = entity_signature_dishes.recipe_id
        and r.visibility = 'public'
    )
  );

-- ----------------------------------------------------------------------------
-- profile_claims (Phase 35b)
-- ----------------------------------------------------------------------------
-- A claimant sees their own claims and nothing else. Claims are not public:
-- "who is trying to claim this chef" is not a fact the directory should publish
-- while it is still pending.
drop policy if exists claims_select on profile_claims;
create policy claims_select on profile_claims for select
  using (claimant_auth_user_id = auth.uid());

-- Filing a claim: for yourself, against an `imported` profile that nobody has
-- claimed yet. Both halves matter — without the `kind` test a user could file a
-- claim against another member's live profile, which is a phishing surface even
-- though approval is manual.
drop policy if exists claims_insert on profile_claims;
create policy claims_insert on profile_claims for insert
  with check (
    claimant_auth_user_id = auth.uid()
    and exists (
      select 1 from profiles p
      where p.id = profile_claims.profile_id
        and p.kind = 'imported'
        and p.auth_user_id is null
    )
  );

-- No update policy and no delete policy, deliberately. The decision is the
-- reviewer's and arrives through `approve_profile_claim()` /
-- `reject_profile_claim()`; a claimant who changes their mind files nothing,
-- and RLS with no policy default-denies.

-- ----------------------------------------------------------------------------
-- import_blocklist (Phase 35c)
-- ----------------------------------------------------------------------------
-- RLS on, and **no policy at all**, which default-denies every API role for
-- every command. That is the intent rather than an omission: the table records
-- who asked for something to be taken down and why, and it is read by the
-- importer running as `postgres`. Nothing on the client has any business
-- seeing it. The blanket grants below still apply, which is exactly why the
-- policy-free state matters — a grant without a policy returns empty, not an
-- error (Gotcha 4).

-- ============================================================================
-- Table grants for the PostgREST roles
--
-- RLS decides *which rows* a request may touch; GRANTs decide whether the role
-- may touch the table at all — both are required. Current Supabase images no
-- longer hand new tables blanket DML defaults, so a fresh project without this
-- block answers every API call with `permission denied for table ...` (B013).
-- Every table here has RLS enabled above, so the grants stay row-filtered.
--
-- RLS filters *rows*, never *columns* (a `with check` expression cannot say
-- "not this column"), so row-scoped policies alone let an owner PATCH any column
-- of a row they own — including `recipes.like_count` and
-- `profiles.chef_score`, which `recipes_chef_stats` then launders into the public
-- leaderboard (B050). Column-level grants are the only layer that can express
-- this, so `recipes` and `profiles` drop the blanket INSERT/UPDATE and get
-- explicit column lists mirroring `_writablePayload` (recipe_repository.dart)
-- and `ProfileRepository.updateMine`. Everything reached through a
-- `security definer` function (fork_recipe, handle_new_user, the counter
-- triggers) and everything run as `postgres` (seed, sim) is unaffected.
--
-- MAINTENANCE: a new client-writable column on either table must be added to
-- the matching list below, or the first save that sends it fails with 42501.
-- ============================================================================
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    return;   -- plain Postgres (no Supabase API roles) — nothing to grant
  end if;

  grant usage on schema public to anon, authenticated;

  -- Reads: RLS narrows anon to public recipes and their children.
  grant select on all tables in schema public to anon, authenticated;

  -- Writes: only signed-in users, still row-filtered by RLS.
  grant insert, update, delete on all tables in schema public to authenticated;

  -- Narrow the two tables that carry server-owned columns. The revoke must run
  -- *after* the blanket grant above, since a re-apply re-issues it; the column
  -- grants then run last so they survive either revoke semantics.
  revoke insert, update on recipes  from authenticated;
  revoke insert, update on profiles from authenticated;

  -- recipes: NOT granted — like_count, save_count, view_count, rating_sum,
  -- rating_count, rating_avg, current_version_id, created_at, updated_at (all
  -- trigger-maintained), plus `id` (defaulted) and, on UPDATE, `owner_id`, so a
  -- recipe cannot be reassigned out from under `recipes_update`.
  --
  -- **`forked_from_recipe_id` / `forked_from_version_id` are server-owned too
  -- (B082).** Lineage is a claim *about another user's recipe*, and
  -- `recipes_most_forked` ranks on it — so a client that can write it can mint
  -- forks that never happened and order a public shelf with them. The only
  -- writer is `fork_recipe`, which is `security definer` and therefore
  -- unaffected by this list; `save_recipe` refuses a forged claim on insert and
  -- preserves the stored values on update. Same shape as `current_version_id`:
  -- a column the client reads, and the server alone writes.
  grant insert (owner_id, title, description, cover_image_url, cuisine, category,
                difficulty, prep_minutes, cook_minutes, servings, visibility,
                attribution, nutrition)
    on recipes to authenticated;
  grant update (title, description, cover_image_url, cuisine, category,
                difficulty, prep_minutes, cook_minutes, servings, visibility,
                attribution, nutrition)
    on recipes to authenticated;

  -- profiles: NOT granted — chef_score, chef_tier, public_recipe_count,
  -- total_likes, total_saves, total_views, created_at. `id` is insert-only
  -- (`profiles_insert` pins both `id` and `auth_user_id` to auth.uid()).
  --
  -- Phase 35b adds four columns and grants exactly one of them, on insert only.
  -- `auth_user_id` is grantable there because `profiles_insert`'s `with check`
  -- pins it to `auth.uid()` in the same statement, so the worst a client can do
  -- is assert a link to its own account — and `profiles_auth_user_id_key` stops
  -- it asserting a second one. It is **not** grantable on update: an update
  -- grant would let a member re-point their profile at another account, or
  -- detach an imported profile from the member who claimed it. `kind`,
  -- `claimed_at` and `merged_into` are written only by
  -- `approve_profile_claim()`, which is `security definer`.
  grant insert (id, auth_user_id, display_name, avatar_url, bio) on profiles to authenticated;
  grant update (display_name, avatar_url, bio)                   on profiles to authenticated;

  -- entities (Phase 35b): a world-readable directory. Writes go through the
  -- member policies below, and the three server-owned columns (`slug` is
  -- identity, `created_by` is provenance, `created_at`) stay off the update
  -- list for the same reason `recipes.owner_id` does — a row must not be
  -- reassigned out from under the policy that admitted the write.
  revoke insert, update on entities from authenticated;
  grant insert (slug, name, kind, homepage, country, description, cover_image_url,
                created_by)
    on entities to authenticated;
  grant update (name, homepage, country, description, cover_image_url)
    on entities to authenticated;

  -- profile_claims: a claimant files one and reads their own. `status`,
  -- `decided_at`, `decided_by` and `note` are the reviewer's answer, not the
  -- claimant's, so nothing may update this table from a client at all — the
  -- decision arrives through `approve_profile_claim()` / `reject_profile_claim()`.
  revoke insert, update, delete on profile_claims from authenticated;
  grant insert (profile_id, claimant_auth_user_id, evidence_url)
    on profile_claims to authenticated;

  -- recipe_suggestions (32a3): the reserved PR-flow stub. A suggestion is a
  -- claim about **who** proposed **what** against **which** recipe, so the only
  -- thing an update may move is where it ends up — `status`, and *only* status.
  --
  -- `summary` and `payload` are deliberately NOT granted, and the reasoning is
  -- worth keeping because the first cut got it wrong: `suggestions_update` is
  -- `using (owns_recipe(recipe_id))`, so the only principal an update grant can
  -- empower is the **recipe's owner** — not the author. Granting the proposal's
  -- own text would therefore let the owner rewrite someone else's words under
  -- their name, which is the misattribution this band closed one column over.
  -- An author editing their own wording needs the *policy* to admit the author
  -- first; that is a different change, and `status` would have to leave the
  -- author's reach in the same breath.
  --
  -- `status` is likewise absent from the INSERT list: `suggestions_insert` pins
  -- the author but says nothing about status, so a blanket insert grant lets a
  -- proposer file their own suggestion pre-`accepted`. The column default
  -- (`'open'`) is the only way in.
  revoke insert, update on recipe_suggestions from authenticated;
  grant insert (recipe_id, from_recipe_id, author_id, summary, payload)
    on recipe_suggestions to authenticated;
  grant update (status) on recipe_suggestions to authenticated;

  -- Signed-out visitors may log a view of a recipe they can read.
  grant insert on recipe_views to anon;

  -- Food registry (Phase 29a): reference data — no client role writes it, and
  -- the RLS above narrows reads to signed-in users, so `anon`'s blanket select
  -- returns empty rather than erroring.
  revoke insert, update, delete on food, food_alias, food_portion, food_unit
    from authenticated;
end $$;

-- ============================================================================
-- Storage buckets + policies
-- ============================================================================
insert into storage.buckets (id, name, public)
values ('recipe-images', 'recipe-images', true)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

-- 32a4: what may be put in them. The policies below decide *who* writes and
-- *where*; until now nothing decided **what**, so a signed-in user could store
-- an object of **unbounded size** and of **any declared content type** — a zip,
-- a video, a 500 MB file — in a bucket that is world-readable by design.
-- Storage enforces these two columns itself and refuses the upload at the API
-- edge, which is the only layer that can: RLS sees an `objects` row, not the
-- bytes or the declared type.
--
-- **What this does not close:** object *count*. A per-object limit bounds one
-- upload, not a thousand of them, and nothing here caps per-user total bytes.
-- Say so rather than letting the quota question read as settled.
--
-- 5 MB and three image types. Note what the app actually sends, because it is
-- not what the allowlist implies: `StorageService` declares `image/jpeg` on
-- **every** upload (its `contentType` default, which no call site overrides),
-- and `uploadAvatar` has no callers at all — nothing in the app writes
-- `avatars`. So the MIME allowlist cannot break the app path, and by the same
-- token `image/png`/`image/webp` are entries for a client that does not exist
-- yet; the allowlist is a check on a client-supplied header. **The size limit is
-- the load-bearing half**, and it is reachable — `maxWidth` is honoured by the
-- mobile pickers but ignored outright by the desktop ones, so the editor guards
-- the byte count itself.
--
-- An `update`, not part of the insert: the buckets predate this and every
-- database that already has them would otherwise keep the unbounded version
-- (`on conflict do nothing`), which is the same silent-no-op shape 32a2's
-- constraint guard fell into.
update storage.buckets
   set file_size_limit    = 5242880,
       allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp']
 where id in ('recipe-images', 'avatars')
   and (file_size_limit is distinct from 5242880
        or allowed_mime_types is distinct from
           array['image/jpeg', 'image/png', 'image/webp']);

-- Anyone can read (public buckets); only authenticated users can write, and only
-- within a folder prefixed by their own user id (e.g. "<uid>/cover.jpg").
drop policy if exists "recipe images readable" on storage.objects;
create policy "recipe images readable"
  on storage.objects for select
  using (bucket_id = 'recipe-images');

drop policy if exists "recipe images writable by owner folder" on storage.objects;
create policy "recipe images writable by owner folder"
  on storage.objects for insert
  with check (
    bucket_id = 'recipe-images'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "recipe images updatable by owner folder" on storage.objects;
create policy "recipe images updatable by owner folder"
  on storage.objects for update
  using (
    bucket_id = 'recipe-images'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "recipe images deletable by owner folder" on storage.objects;
create policy "recipe images deletable by owner folder"
  on storage.objects for delete
  using (
    bucket_id = 'recipe-images'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "avatars readable" on storage.objects;
create policy "avatars readable"
  on storage.objects for select
  using (bucket_id = 'avatars');

drop policy if exists "avatars writable by owner folder" on storage.objects;
create policy "avatars writable by owner folder"
  on storage.objects for insert
  with check (
    bucket_id = 'avatars'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "avatars updatable by owner folder" on storage.objects;
create policy "avatars updatable by owner folder"
  on storage.objects for update
  using (
    bucket_id = 'avatars'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

-- Parity with recipe-images (OPT-A6): without a delete policy an avatar can be
-- replaced but never removed, so every superseded upload stays in a **public**
-- bucket at a guessable path for the life of the project. Same folder rule —
-- you may only delete under your own uid.
drop policy if exists "avatars deletable by owner folder" on storage.objects;
create policy "avatars deletable by owner folder"
  on storage.objects for delete
  using (
    bucket_id = 'avatars'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

-- ============================================================================
-- Discovery ranking, search, and atomic fork RPCs
-- ============================================================================

-- Trending: recency-weighted popularity over public recipes.
-- Trending = engagement decayed by age. The `now()` in the score makes the sort
-- key non-indexable by construction, so the only lever is how many rows have to
-- be scored at all (OPT-P2): bound the candidate set to the last 30 days, which
-- `recipes_public_created_idx` can serve directly.
--
-- The bound costs nothing in ranking terms — at 30 days the divisor is
-- (720h + 2)^1.5 ≈ 19,400, so a month-old recipe already scores under a
-- thousandth of a fresh one and could only surface if almost nothing else
-- existed. It does mean a project with **no public recipe created in 30 days**
-- gets an empty Trending tab; that is deliberate (a "trending" list of stale
-- recipes is a contradiction), and Popular and Recent still cover everything.
-- `seed.sql`/`seed_recipes.sql` create at `now()`, so a fresh install is never
-- in that state.
--
-- `p_offset` + the `created_at, id` tie-break are OPT-P9's half of Discover's
-- load-more. The tie-break is not cosmetic: `offset` only makes sense over a
-- total order, and two recipes with an equal decayed score would otherwise swap
-- places between the page-1 and page-2 queries — one row duplicated on the
-- second page, another never shown at all.
--
-- The old one-argument signature must be dropped here, in the file that
-- recreates the function (B024): `create or replace` cannot change an argument
-- list, and a surviving overload makes `recipes_trending(20)` ambiguous (42725).
drop function if exists recipes_trending(int);
create or replace function recipes_trending(p_limit int default 20, p_offset int default 0)
returns setof recipes
language sql
stable
as $$
  select r.*
  from recipes r
  where r.visibility = 'public'
    -- Phase 35c. Imported content is browsable and searchable; it is not
    -- RANKED. It arrives with every counter at zero, so a ranked shelf
    -- would order 558k identical rows by whatever the tie-break happens to
    -- be and bury the recipes people here actually wrote. `recipes_corpus`
    -- is the surface that does show it, ordered by something that is not
    -- engagement.
    and not r.is_imported
    and r.created_at > now() - interval '30 days'
  order by
    (r.like_count + r.view_count)::numeric
      / power(extract(epoch from (now() - r.created_at)) / 3600.0 + 2.0, 1.5) desc,
    r.created_at desc,
    r.id
  limit p_limit offset p_offset;
$$;

-- The Bayesian prior behind Popular and UNDER 30: `m` phantom ratings sitting at
-- the site-wide mean, so a single 5-star recipe cannot outrank a 4.8 with 300
-- ratings.
--
-- It is a function rather than a CTE inside one query because **two** rankings
-- need it (Phase 26 added `recipes_quick`), and a ranking formula written twice
-- is the bug class CLAUDE.md Gotcha 19 exists for.
--
-- Cross-joined, so it is evaluated ONCE PER QUERY. Written as a per-row scalar
-- — `bayes_score(rating_sum, rating_count)` — it would re-scan every public
-- recipe for every public recipe.
--
-- EXECUTE stays with `public` (the Postgres default), unlike the mutating
-- helpers revoked below: PostgREST exposes this as an RPC, and what it exposes
-- is one aggregate over rows `anon` can already read and sum for itself.
--
-- Must be created BEFORE its callers: Postgres validates a SQL function body at
-- creation, so a `recipes_popular` that cross-joins a not-yet-existing function
-- fails to create at all.
create or replace function site_rating_prior(out m numeric, out mean numeric)
returns record
language sql
stable
as $$
  select
    5::numeric,
    coalesce(sum(rating_sum) / nullif(sum(rating_count), 0), 3.5)
  from recipes
  where visibility = 'public';
$$;

-- Popular: highest rated public recipes.
--
-- Straight AVG(rating) would put a single 5-star recipe above a 4.8 with 300
-- ratings, so the score is the Bayesian (weighted) average above. Ties fall back
-- to saves + likes, then recency, then `id` — the last one exists so the order is
-- total and `p_offset` (OPT-P9) cannot show the same recipe on two pages. B024
-- drop as above.
drop function if exists recipes_popular(int);
create or replace function recipes_popular(p_limit int default 20, p_offset int default 0)
returns setof recipes
language sql
stable
as $$
  select r.*
  from recipes r cross join site_rating_prior() p
  where r.visibility = 'public'
    -- Phase 35c. Imported content is browsable and searchable; it is not
    -- RANKED. It arrives with every counter at zero, so a ranked shelf
    -- would order 558k identical rows by whatever the tie-break happens to
    -- be and bury the recipes people here actually wrote. `recipes_corpus`
    -- is the surface that does show it, ordered by something that is not
    -- engagement.
    and not r.is_imported
  order by
    ((r.rating_sum + p.m * p.mean) / (r.rating_count + p.m)) desc,
    r.rating_count desc,
    (r.save_count + r.like_count) desc,
    r.created_at desc,
    r.id
  limit p_limit offset p_offset;
$$;

-- Full-text search over public recipes (title/description/ingredients/tags).
-- Reads the trigger-maintained `search_tsv` (OPT-P1) instead of rebuilding the
-- document per row. The `@@` is now a GIN index probe and `ts_rank` runs only
-- over the matches, not the whole public corpus.
--
-- `ts_rank` ties are common — a one-word query over a corpus of similar recipes
-- produces long runs of identical rank — so the `created_at, id` tie-break
-- matters more here than on the other two: without it, `p_offset` (OPT-P9)
-- would reshuffle exactly the rows a second page is made of. B024 drop as above.
drop function if exists recipes_search(text, int);
create or replace function recipes_search(
  p_query text,
  p_limit int default 30,
  p_offset int default 0
)
returns setof recipes
language sql
stable
as $$
  select r.*
  from recipes r
  where r.visibility = 'public'
    and r.search_tsv @@ websearch_to_tsquery('english', p_query)
  order by ts_rank(r.search_tsv, websearch_to_tsquery('english', p_query)) desc,
           r.created_at desc,
           r.id
  limit p_limit offset p_offset;
$$;

-- ============================================================================
-- Discover's three shelves (Phase 26)
--
-- The tabs above answer "what is doing well". These answer "what am I in the
-- mood for", and each ranks on a DIFFERENT signal — that is the design, not an
-- accident of what was easy:
--
--   recipes_quick        01 UNDER 30          <= 30 min, best-RATED first
--   recipes_projects     02 WEEKEND PROJECTS  >= 120 min or 'hard', most-SAVED
--   recipes_most_forked  03 MOST FORKED       by public FORK count
--
-- A weeknight recipe is chosen on whether it is any good; a project on whether
-- it is worth a Saturday (you save a project, you rate what you already
-- cooked); a fork shelf can only rank on forks. Three shelves ordered by one
-- key would be one shelf shown three times.
--
-- Same contract as the three RPCs above: `setof recipes` so the caller reuses
-- `kRecipeSelect` and its owner embed, `stable`, invoker-rights, `anon`-callable,
-- and every order ends `created_at desc, id` because `offset` is meaningless
-- over a partial order (Gotcha 24).
-- ============================================================================

-- 01 · UNDER 30.
--
-- `between 1 and 30`, not `<= 30`: a recipe with no timings has an *unknown*
-- duration, not a zero one — `RecipeCard` renders exactly that case as `—`, and
-- a shelf promising half an hour cannot be half full of cards that decline to
-- say.
create or replace function recipes_quick(p_limit int default 20, p_offset int default 0)
returns setof recipes
language sql
stable
as $$
  select r.*
  from recipes r cross join site_rating_prior() p
  where r.visibility = 'public'
    -- Phase 35c. Imported content is browsable and searchable; it is not
    -- RANKED. It arrives with every counter at zero, so a ranked shelf
    -- would order 558k identical rows by whatever the tie-break happens to
    -- be and bury the recipes people here actually wrote. `recipes_corpus`
    -- is the surface that does show it, ordered by something that is not
    -- engagement.
    and not r.is_imported
    and r.prep_minutes + r.cook_minutes between 1 and 30
  order by
    ((r.rating_sum + p.m * p.mean) / (r.rating_count + p.m)) desc,
    r.rating_count desc,
    (r.save_count + r.like_count) desc,
    r.created_at desc,
    r.id
  limit p_limit offset p_offset;
$$;

-- 02 · WEEKEND PROJECTS.
--
-- Two hours of total time OR the top difficulty rung — the `or` is deliberate,
-- since a laminated dough is a project at 90 minutes and a stock is not at four
-- hours. The `> 0` floor applies to both branches for the reason above.
--
-- Ranked by SAVES: a save is the "I will cook this when I have a day" signal,
-- and far fewer people ever get far enough with a six-hour braise to rate it.
create or replace function recipes_projects(p_limit int default 20, p_offset int default 0)
returns setof recipes
language sql
stable
as $$
  select r.*
  from recipes r
  where r.visibility = 'public'
    -- Phase 35c. Imported content is browsable and searchable; it is not
    -- RANKED. It arrives with every counter at zero, so a ranked shelf
    -- would order 558k identical rows by whatever the tie-break happens to
    -- be and bury the recipes people here actually wrote. `recipes_corpus`
    -- is the surface that does show it, ordered by something that is not
    -- engagement.
    and not r.is_imported
    and r.prep_minutes + r.cook_minutes > 0
    and (r.prep_minutes + r.cook_minutes >= 120 or r.difficulty = 'hard')
  order by
    r.save_count desc,
    r.like_count desc,
    r.created_at desc,
    r.id
  limit p_limit offset p_offset;
$$;

-- 03 · MOST FORKED — the lineage shelf, and the one no other recipe app has.
--
-- **Only public forks count, and that is correctness, not a filter.** These
-- RPCs are invoker-rights, so an unqualified `count(*)` over `recipes` is
-- filtered by RLS: a private fork would count for its owner and for nobody
-- else, and the same recipe would hold a different rank depending on who asked.
-- Pinning the count to public rows makes the ranking identical for every caller
-- and leaks nothing about who forked what in private.
--
-- Aggregate first, then join back: the fork set is a small fraction of the
-- table and `recipes_public_fork_source_idx` covers exactly those rows. A
-- correlated `count(*)` per candidate would probe the fork index once per public
-- recipe instead of once. The join to the source row inside the CTE is by
-- primary key over that same small set, so it is still one pass.
--
-- **The unit is a distinct *other* cook, not a fork row (B082).** Grants stop a
-- client from writing lineage it did not earn, but they cannot stop the honest
-- path being farmed: `fork_recipe` will happily fork your own public recipe,
-- twenty times, and a raw `count(*)` would rank you first for it. So a fork
-- counts only when the forker is not the source's owner, and each forker counts
-- once — the same "distinct signed-in actor" rule `on_view_insert` applies to
-- `view_count` for exactly the same reason (Gotcha 10 / B012). Self-forks stay
-- in the data and still show their lineage on the recipe page; they just do not
-- rank.
--
-- Ties are the normal case early on (most forked recipes have been forked once),
-- so the tie-break carries real weight: saves + likes decide, which makes a tied
-- shelf read as "the most popular recipes anyone has rewritten".
create or replace function recipes_most_forked(p_limit int default 20, p_offset int default 0)
returns setof recipes
language sql
stable
as $$
  with forks as (
    select f.forked_from_recipe_id          as source_id,
           count(distinct f.owner_id)::int  as fork_count
    from recipes f
    join recipes s on s.id = f.forked_from_recipe_id
    where f.forked_from_recipe_id is not null
      and f.visibility = 'public'
      and s.visibility = 'public'
      and f.owner_id <> s.owner_id
    group by f.forked_from_recipe_id
  )
  select r.*
  from recipes r
  join forks on forks.source_id = r.id
  where r.visibility = 'public'
    -- Phase 35c. Imported content is browsable and searchable; it is not
    -- RANKED. It arrives with every counter at zero, so a ranked shelf
    -- would order 558k identical rows by whatever the tie-break happens to
    -- be and bury the recipes people here actually wrote. `recipes_corpus`
    -- is the surface that does show it, ordered by something that is not
    -- engagement.
    and not r.is_imported
  order by
    forks.fork_count desc,
    (r.save_count + r.like_count) desc,
    r.created_at desc,
    r.id
  limit p_limit offset p_offset;
$$;

-- EXECUTE on a new function goes to `public` by default rather than to the API
-- roles by name, so grant it explicitly the way `chefs_leaderboard` does (B013).
-- Guarded on `anon` existing, because a bare Postgres has no Supabase roles.
--
-- After applying this to a hosted project PostgREST has to learn the functions
-- exist; Supabase's DDL event trigger reloads the schema cache by itself. If a
-- shelf still answers `404 … not found in schema cache`, the manual form is
-- `notify pgrst, 'reload schema';`.
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'grant execute on function recipes_quick(int, int) to anon, authenticated';
    execute 'grant execute on function recipes_projects(int, int) to anon, authenticated';
    execute 'grant execute on function recipes_most_forked(int, int) to anon, authenticated';
    execute 'grant execute on function site_rating_prior() to anon, authenticated';
  end if;
end $$;

-- How many chefs sit in each tier (OPT-P10). The `/chefs` hero needs all five
-- counts plus the total; PostgREST cannot express `group by`, so the client was
-- issuing five exact-count requests, and a sixth for the total. An RPC can, so
-- it does — one round trip, and the total is the sum.
--
-- `unnest(enum_range(...))` + left join guarantees a row for every tier even
-- when nobody is in it, which is what the five separate counts produced and what
-- the hero renders. `public_recipe_count > 0` is the same "is a chef at all"
-- filter the leaderboard and the old counts used.
--
-- `stable`, invoker-rights, `anon`-callable: `/chefs` is signed-out safe.
-- Explicit drop first (B024): once a signature exists, `create or replace`
-- cannot change it, and the stale overload makes every call ambiguous (42725).
drop function if exists chefs_tier_counts();
create or replace function chefs_tier_counts()
returns table (tier chef_tier, chefs bigint)
language sql
stable
as $$
  select t.tier, count(p.id)
  from unnest(enum_range(null::chef_tier)) as t(tier)
  left join profiles p
    on p.chef_tier = t.tier
   and p.public_recipe_count > 0
   and p.kind = 'member'      -- the same population the board ranks (Phase 35b/c)
  group by t.tier
  order by t.tier;
$$;

-- Chefs leaderboard. Ranked by the denormalized profiles.chef_score, reading the
-- engagement totals denormalized beside it (OPT-P5) so the page needs one
-- round-trip and no aggregation at all.
--
-- It used to re-aggregate `recipes` per page — a full scan of every public
-- recipe to produce numbers `recompute_chef_stats` had already computed and
-- discarded (52 ms cold / 3.5 ms warm at sim `medium`, now 0.5 ms).
--
-- `dense_rank()` ranks over the whole filtered set rather than the page, which
-- is what makes rank 26 on page two say 26. It does not force a full read: the
-- window's ordering is a prefix of `profiles_leaderboard_member_idx`, so the plan
-- streams index scan → WindowAgg → incremental sort → limit and stops at
-- `p_offset + p_limit` rows. At sim `medium` the planner still picks a seq scan
-- (172 chefs in 26 pages — cheaper than random heap fetches); the index takes
-- over as `profiles` grows, which is the case that needed it.
--
-- `stable`, invoker-rights, and callable by `anon` — the leaderboard is
-- signed-out safe like Discover. Reading the totals off `profiles` also closes
-- the trap the old sums had to dodge by hand: they filtered `visibility =
-- 'public'` explicitly because under invoker rights a signed-in chef would
-- otherwise see their own private recipes folded into their totals and read
-- different numbers than everyone else. The persisted columns are public-only
-- by construction (recompute_chef_stats owns that filter), and `profiles` is
-- world-readable, so every caller now reads the same row.
--
-- Internal aliases deliberately avoid the RETURNS TABLE column names — in a
-- `language sql` function those names are in scope and would make `chef_score`
-- / `display_name` / `id` ambiguous against the tables being read.
--
-- **The drop is load-bearing as of Phase 23's windowed half.** It used to be
-- insurance — the argument list had never changed — but `created_at` was added
-- to the RETURNS TABLE below, and a **return type** change is exactly as
-- impossible for `create or replace` as an argument-list change is. Without
-- this line every database that already holds the ten-column version fails the
-- apply with `42P13 cannot change return type of existing function`, and the
-- one that does *not* hold it (a fresh `db reset`) succeeds — so the upgrade
-- path is the only place it shows (Gotcha 6). The drop keys on the ARGUMENT
-- list, `(int, int)`, which is unchanged and is what makes one line enough.
drop function if exists chefs_leaderboard(int, int);
create or replace function chefs_leaderboard(p_limit int default 50, p_offset int default 0)
returns table (
  chef_rank           bigint,
  id                  uuid,
  display_name        text,
  avatar_url          text,
  chef_tier           chef_tier,
  chef_score          numeric,
  public_recipe_count int,
  total_likes         bigint,
  total_saves         bigint,
  total_views         bigint,
  -- The profile's join date (Phase 23). Two client surfaces need it and neither
  -- can get it any other way without a second round trip: the board's `New`
  -- sort, and the `Joined <month year>` line on a chef card the board itself
  -- rendered. It is NOT part of the ordering here — see below.
  created_at          timestamptz
)
language sql
stable
as $$
  with ranked as (
    select
      dense_rank() over (order by p.chef_score desc) as rnk,
      p.id                  as pid,
      p.display_name        as pname,
      p.avatar_url          as pavatar,
      p.chef_tier           as ptier,
      p.chef_score          as pscore,
      p.public_recipe_count as pcount,
      p.total_likes         as plikes,
      p.total_saves         as psaves,
      p.total_views         as pviews,
      p.created_at          as pjoined
    from profiles p
    -- Chefs with no public recipes (tasters, private-only accounts, brand-new
    -- signups) still *have* a tier for badge purposes; they just don't occupy
    -- leaderboard rows. Also half the predicate of `profiles_leaderboard_member_idx`.
    where p.public_recipe_count > 0
      -- Phase 35b/c. Without this the board IS the corpus. Every imported chef
      -- ties at `chef_score = 0`, and the order below breaks that tie on
      -- `public_recipe_count desc` — so a 14,000-recipe publication byline
      -- would sit above every other zero-score chef, and 19,681 imported rows
      -- would fill the board behind the handful of real ones. An imported chef
      -- has a page and is browsable; they are not ranked.
      and p.kind = 'member'
  )
  select
    x.rnk, x.pid, x.pname, x.pavatar, x.ptier, x.pscore, x.pcount,
    x.plikes, x.psaves, x.pviews, x.pjoined
  from ranked x
  -- Deterministic full ordering; dense_rank above lets tied scores share a rank.
  -- `created_at` is deliberately NOT added here: this ordering is already total
  -- (it ends in the primary key) and it is the one `profiles_leaderboard_member_idx`
  -- was built to serve as an index scan, so a new sort key would put a sort back
  -- on top of it. A `New` board is a different ordering and therefore a
  -- different query, not a tie-break bolted onto this one.
  order by x.pscore desc, x.pcount desc, x.pname asc, x.pid asc
  limit p_limit offset p_offset;
$$;

-- The blanket grant block above runs before this function exists on a first
-- apply, and it only covers tables anyway — grant EXECUTE explicitly (B013).
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'grant execute on function chefs_leaderboard(int, int) to anon, authenticated';
  end if;
end $$;

-- ============================================================================
-- Windowed chef engagement (Phase 23's deferred half — SDS §10.8, ROADMAP
-- "Chefs windowed half").
-- ============================================================================
-- Everything on `/chefs` above this line is ALL-TIME. `profiles.chef_score` and
-- the three totals beside it are lifetime counters with no date on them, so
-- until now nothing in the schema could answer "who moved this month" — which
-- is why the `Momentum` sort and the hero's Month / Week toggle shipped drawn
-- and disabled. The engagement LOGS can answer it (`recipe_likes.created_at`,
-- `recipe_saves.created_at`, `recipe_views.viewed_at`,
-- `recipe_ratings.created_at`), so a windowed score is a query, not a new
-- snapshot table.
--
-- `chef_window_stats` is the ONLY place the window is computed.
-- `chefs_leaderboard_windowed` ranks what this returns and adds no arithmetic
-- of its own, so the Momentum board and any future per-chef momentum line
-- cannot drift apart the way two copies of a formula do (Gotcha 19's shape).
--
-- Five rules, each of which costs something real if broken:
--
--  1. **Anonymous views do not count, and a viewer counts once per recipe.**
--     `anon` holds `insert on recipe_views` (the grants block above, and
--     deliberately — a signed-out visitor reading a public recipe logs a view),
--     so an unauthenticated loop can add view rows at will. `on_view_insert`
--     refuses to move `recipes.view_count` for them (Gotcha 10 / B012) and this
--     window has to refuse the same way, or the inflation hole reopens inside a
--     ranking nobody is auditing. The clause is `where v.user_id is not null`
--     over a `select distinct pub.pid, v.recipe_id, v.user_id` — SDS §10.8's
--     rule 1 ("count distinct (recipe_id, user_id) where user_id is not null"),
--     verbatim. Measured on the local fixture: 3,878 of 20,630 view rows are
--     anonymous, and the 16,752 signed-in rows collapse to 10,083 distinct
--     pairs — so this is a 51% correction, not a rounding one.
--  2. **The points come from `chef_score()`**, never a restated `3 / 5 / 0.2`
--     (Gotcha 19, SDS §10.8 rule 2). A windowed board that weighted a save
--     differently from the all-time board would be two products on one page.
--  3. **Public recipes only, filtered explicitly.** This function is
--     `security definer`, so RLS is not in the loop at all — that filter is the
--     only thing keeping a private recipe's engagement out of a world-readable
--     number. It is the same claim `chefs_leaderboard` and `chef_top_recipes`
--     make, with the safety net removed.
--  4. **The window is `now()`-relative or caller-pinned — never a fixture
--     anchor.** `sim.epoch_end()` is a pinned instant (B044) and lives in schema
--     `sim`, which does not exist on a real deployment; keying off it would make
--     the board work only on machines that had run the simulator. The visible
--     consequence is that a simulated database whose anchor has gone stale
--     returns an EMPTY week — that is the data being old, not the query being
--     wrong, and it is why the client needs a real empty state here rather than
--     a spinner.
--  5. **Self-engagement is NOT excluded**, deliberately. `recompute_chef_stats`
--     does not exclude it either (SDS §10.8 lists it as an accepted v1 limit),
--     and a window that counted differently from the all-time score would put
--     two numbers on one card that measure different things. If that limit is
--     ever closed it has to close in both places, in one change.
--
-- **`security definer` is mandatory here, and not for the usual reason.** Three
-- of the four logs are not world-readable: `saves_select` is
-- `user_id = current_profile_id()` (you see your own saves and nobody else's) and
-- `views_select` is `owns_recipe(recipe_id)` (only a recipe's owner sees its
-- view log). Under invoker rights this function would therefore compute a
-- *different* window for every caller — zero saves and zero views for `anon`,
-- a chef's own numbers for that chef — which is the "one page, two answers"
-- defect `chefs_leaderboard`'s comment warns about, except silent, because an
-- under-count is indistinguishable from a quiet week. Definer rights are what
-- make every viewer read the same board.
--
-- Exposing a definer function to `anon` is safe here for reasons worth stating,
-- because they are what a future edit has to preserve: it takes no dynamic SQL,
-- writes nothing, pins `search_path`, returns COUNTS ONLY (never a user id,
-- never a recipe id), and aggregates only recipes whose lifetime counters are
-- already world-readable columns. A window is a strictly less revealing slice
-- of data the API already serves.
--
-- Population: the board's own `public_recipe_count > 0` filter, so a chef with
-- no public recipes holds no windowed row for the same reason they hold no rank
-- (F4/F5 below). Every *other* ranked chef gets a row, zeros included — a quiet
-- month is `0`, not a missing row, which is what lets the board rank the whole
-- population instead of only the chefs who happened to be busy.
--
-- `p_days` is the client's control (the hero's Month = 30 / Week = 7).
-- `p_since` overrides it with an explicit instant, for two reasons: a paged
-- Momentum board should pin its boundary once rather than let `now()` drift
-- between page 1 and page 2 (Gotcha 24's problem one level out — a moving
-- window makes `offset` lie even over a total order), and a test has to be able
-- to cross a fixture's stale anchor. `p_days` is clamped to 1..3650: zero or
-- negative would be a future window that reads as "nothing happened", and the
-- ceiling stops an anon caller from provoking an `interval` overflow.
--
-- New signatures, so there is no historical overload to drop yet — but the drop
-- is written now, for the exact current argument list, because that is where it
-- has to live the day the list changes (B024), and adding it after an
-- ambiguous-overload failure means editing a database that already has two
-- (OPT-A6). It also makes the next RETURN TYPE change free: `create or replace`
-- refuses those too, which is the trap `chefs_leaderboard` just walked into.
drop function if exists chef_window_stats(int, timestamptz, uuid);
create or replace function chef_window_stats(
  p_days  int         default 30,
  p_since timestamptz default null,
  p_chef  uuid        default null
)
returns table (
  id             uuid,
  window_start   timestamptz,
  window_likes   bigint,
  window_saves   bigint,
  window_views   bigint,
  window_ratings bigint,
  window_recipes bigint,
  window_score   numeric
)
language sql
stable
security definer
set search_path = public
as $$
  -- Internal aliases deliberately avoid every RETURNS TABLE column name: in a
  -- `language sql` body those names are in scope as OUT parameters, and a bare
  -- `id` would be ambiguous against four of the five tables read below. Same
  -- reasoning, and the same `p*` convention, as `chefs_leaderboard`.
  with bounds as (
    select coalesce(
             p_since,
             now() - make_interval(days => least(greatest(coalesce(p_days, 30), 1), 3650))
           ) as start_at
  ),
  chefs as (
    select p.id as pid
    from profiles p
    where p.public_recipe_count > 0
      and p.kind = 'member'        -- Phase 35b/c, as `chefs_leaderboard`
      and (p_chef is null or p.id = p_chef)
  ),
  -- Rule 3. Every aggregate below reaches the logs THROUGH this CTE, so there
  -- is exactly one `visibility = 'public'` filter to get wrong.
  pub as (
    select r.id as rid, r.owner_id as pid, r.created_at as made_at
    from recipes r
    join chefs c on c.pid = r.owner_id
    where r.visibility = 'public'
  ),
  likes as (
    select pub.pid, count(*)::bigint as n
    from recipe_likes l
    join pub on pub.rid = l.recipe_id
    cross join bounds b
    where l.created_at >= b.start_at
    group by pub.pid
  ),
  saves as (
    select pub.pid, count(*)::bigint as n
    from recipe_saves s
    join pub on pub.rid = s.recipe_id
    cross join bounds b
    where s.created_at >= b.start_at
    group by pub.pid
  ),
  -- Rule 1 — the single most important thing in this function. `select
  -- distinct` over the pair, not `count(*)` over the rows: `recipe_views` is an
  -- append-only log, so one enthusiastic reader would otherwise outrank a
  -- hundred. `user_id is not null` is what keeps `anon`'s insert grant from
  -- being a ranking lever (B012).
  viewers as (
    select d.pid, count(*)::bigint as n
    from (
      select distinct pub.pid, v.recipe_id, v.user_id
      from recipe_views v
      join pub on pub.rid = v.recipe_id
      cross join bounds b
      where v.user_id is not null
        and v.viewed_at >= b.start_at
    ) d
    group by d.pid
  ),
  -- `created_at`, not `updated_at`: this counts ratings *received* in the
  -- window, so re-scoring a recipe rated last year is not a new rating. The
  -- distinction is the reason `recipe_ratings` carries both columns.
  rated as (
    select pub.pid, count(*)::bigint as n
    from recipe_ratings rt
    join pub on pub.rid = rt.recipe_id
    cross join bounds b
    where rt.created_at >= b.start_at
    group by pub.pid
  ),
  fresh as (
    select pub.pid, count(*)::bigint as n
    from pub
    cross join bounds b
    where pub.made_at >= b.start_at
    group by pub.pid
  )
  select
    c.pid,
    b.start_at,
    coalesce(lk.n, 0),
    coalesce(sv.n, 0),
    coalesce(vw.n, 0),
    coalesce(rt.n, 0),
    coalesce(fr.n, 0),
    -- Rule 2. Ratings and new recipes are reported BESIDE the score and do not
    -- enter it: `chef_score()` has no term for either, and inventing one here
    -- would be exactly the second definition of the formula that rule exists to
    -- prevent. The windowed rank and the all-time rank weigh the same three
    -- signals over different spans, which is the only reason they can be shown
    -- next to each other.
    chef_score(coalesce(lk.n, 0), coalesce(sv.n, 0), coalesce(vw.n, 0))
  -- LEFT joins off `chefs`, so a chef with no activity comes back as zeros
  -- rather than vanishing. `bounds` is a one-row cross join purely so
  -- `window_start` can be echoed back to the caller.
  from chefs c
  cross join bounds b
  left join likes   lk on lk.pid = c.pid
  left join saves   sv on sv.pid = c.pid
  left join viewers vw on vw.pid = c.pid
  left join rated   rt on rt.pid = c.pid
  left join fresh   fr on fr.pid = c.pid;
$$;

-- The leaderboard ranked by window activity — the `Momentum` sort, and the
-- board behind the hero's Month / Week toggle.
--
-- Same row shape as `chefs_leaderboard` (including `created_at`, added in this
-- same change) plus the six window columns, so one client model decodes both
-- boards and Score / Momentum stay a re-sort rather than two screens.
--
-- All the arithmetic is `chef_window_stats`'; this function only ranks, orders
-- and pages. It is invoker-rights on purpose even though its input is a definer
-- function: everything IT reads is `profiles`, which is world-readable, so
-- there is nothing here to elevate.
--
-- **`dense_rank()` is computed over the whole population, and nothing is
-- filtered inside the window** — Phase 30's lesson (`chef_standing`, F3). There
-- is no id filter here at all, and `limit`/`offset` are applied in the OUTER
-- select, which is what makes rank 26 on page two say 26 instead of 1. Ties
-- share a rank exactly as on the all-time board; on a quiet week that means
-- every chef with no activity shares the last rank, which is the honest answer
-- and not a bug.
--
-- **The ordering is total** (Gotcha 24), and it has to be: this is a paged
-- surface, and the windowed keys are far more tie-prone than `chef_score` —
-- most of the board scores exactly 0 in any given week, so without a unique
-- tail `offset` would show one chef twice and hide another. The tail is
-- `chef_score desc, created_at desc, id`, and `id` (the `profiles` primary key)
-- is what actually makes it total; the two keys before it are there so the tie
-- is broken by something a reader can see. The all-time score coming *before*
-- the join date is deliberate: when nothing moved this week the Momentum board
-- degrades into the Score board, rather than into a list of new accounts.
--
-- Note the second half of Gotcha 24 that a *windowed* paged surface adds: a
-- window measured from `now()` is a MOVING boundary, so paging one is only
-- sound while the boundary holds still across the calls. `p_since` is how a
-- client pins it — fetch page 1, read `window_start` off any row, pass it back
-- as `p_since` for every later page.
--
-- `stable`, `anon`-callable: `/chefs` is signed-out safe like Discover, and a
-- windowed board is no more privileged than the all-time one.
-- First signature; the drop is written now for the reason given above (B024).
drop function if exists chefs_leaderboard_windowed(int, int, int, timestamptz);
create or replace function chefs_leaderboard_windowed(
  p_days   int         default 30,
  p_limit  int         default 50,
  p_offset int         default 0,
  p_since  timestamptz default null
)
returns table (
  chef_rank           bigint,
  id                  uuid,
  display_name        text,
  avatar_url          text,
  chef_tier           chef_tier,
  chef_score          numeric,
  public_recipe_count int,
  total_likes         bigint,
  total_saves         bigint,
  total_views         bigint,
  created_at          timestamptz,
  window_start        timestamptz,
  window_likes        bigint,
  window_saves        bigint,
  window_views        bigint,
  window_ratings      bigint,
  window_recipes      bigint,
  window_score        numeric
)
language sql
stable
as $$
  with ranked as (
    select
      dense_rank() over (order by w.window_score desc) as rnk,
      p.id                  as pid,
      p.display_name        as pname,
      p.avatar_url          as pavatar,
      p.chef_tier           as ptier,
      p.chef_score          as pscore,
      p.public_recipe_count as pcount,
      p.total_likes         as plikes,
      p.total_saves         as psaves,
      p.total_views         as pviews,
      p.created_at          as pjoined,
      w.window_start        as wstart,
      w.window_likes        as wlikes,
      w.window_saves        as wsaves,
      w.window_views        as wviews,
      w.window_ratings      as wratings,
      w.window_recipes      as wrecipes,
      w.window_score        as wscore
    -- No `p_chef`, so the CTE sees the whole ranked population — the input the
    -- window function has to have. The `public_recipe_count > 0` filter is not
    -- restated here: it lives in `chef_window_stats`, which makes this inner
    -- join complete by construction and leaves one definition of "is a chef".
    from chef_window_stats(p_days, p_since) w
    join profiles p on p.id = w.id
  )
  select
    x.rnk, x.pid, x.pname, x.pavatar, x.ptier, x.pscore, x.pcount,
    x.plikes, x.psaves, x.pviews, x.pjoined,
    x.wstart, x.wlikes, x.wsaves, x.wviews, x.wratings, x.wrecipes, x.wscore
  from ranked x
  order by x.wscore desc, x.wlikes desc, x.wsaves desc,
           x.pscore desc, x.pjoined desc, x.pid
  limit p_limit offset p_offset;
$$;

-- EXECUTE on a new function goes to `public` by default rather than to the API
-- roles by name, so grant it explicitly (B013), the same way `chefs_leaderboard`
-- does. Guarded on `anon` existing, because a bare Postgres has no Supabase
-- roles. No `revoke ... from public` on the definer function: it is read-only,
-- count-only and public-recipe-only (see its header), and every other
-- `anon`-callable read in this file follows the same grant-without-revoke shape
-- — the revokes here are for the functions that WRITE.
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'grant execute on function chef_window_stats(int, timestamptz, uuid) to anon, authenticated';
    execute 'grant execute on function chefs_leaderboard_windowed(int, int, int, timestamptz) to anon, authenticated';
  end if;
end $$;

-- One chef's leaderboard row, by id — what `/chef/:id` needs and the board
-- cannot supply (Phase 30).
--
-- The page is reachable by URL, so it starts with a uuid and nothing else, while
-- the board hands its rows a whole standing it already fetched. `chef_rank` is
-- the part that cannot be reconstructed client-side at any price: it is a
-- `dense_rank()` over every ranked profile, so a single `profiles` row does not
-- contain it and neither does any join that stops short of the full population.
--
-- **The filter is applied outside the window, not inside it.** Moving
-- `where p.id = p_chef` up into `ranked` would rank a one-row set and return
-- `chef_rank = 1` for every chef alive — and it would look right on the first
-- chef anyone tests, because the obvious test subject is the top of the board.
-- Postgres does not push an outer qual through a window function unless the qual
-- is on a PARTITION BY column, and there is no partition here, so the CTE is
-- evaluated over the whole table exactly as written.
--
-- A **new function**, not a `p_chef` argument bolted onto `chefs_leaderboard`:
-- adding one would leave the two-argument signature alive beside it and any call
-- matching both fails 42725 (B024). Deliberately the same return shape as the
-- board, so `ChefStanding` decodes from either without a second model.
--
-- Returns **zero rows** for a profile with no public recipes, matching the
-- board's own `public_recipe_count > 0` filter: the private-only seed chef `d6`
-- exists and owns a recipe with 5,000 likes, but holds no rank. The client turns
-- that into "this profile is not a chef yet", which is a page state, not a 404.
drop function if exists chef_standing(uuid);
create or replace function chef_standing(p_chef uuid)
returns table (
  chef_rank           bigint,
  id                  uuid,
  display_name        text,
  avatar_url          text,
  chef_tier           chef_tier,
  chef_score          numeric,
  public_recipe_count int,
  total_likes         bigint,
  total_saves         bigint,
  total_views         bigint,
  -- Added in lockstep with `chefs_leaderboard` (Phase 23), and the lockstep is
  -- the point: the two functions share a return shape precisely so one client
  -- model decodes either, and a column on one and not the other is how that
  -- stops being true. `/chef/:id` also renders the `Joined` line, so it needs
  -- the value regardless.
  created_at          timestamptz
)
language sql
stable
as $$
  with ranked as (
    select
      dense_rank() over (order by p.chef_score desc) as rnk,
      p.id                  as pid,
      p.display_name        as pname,
      p.avatar_url          as pavatar,
      p.chef_tier           as ptier,
      p.chef_score          as pscore,
      p.public_recipe_count as pcount,
      p.total_likes         as plikes,
      p.total_saves         as psaves,
      p.total_views         as pviews,
      p.created_at          as pjoined
    from profiles p
    -- Same population as `chefs_leaderboard`, and it has to be the same or the
    -- rank this returns would not match the board it is a row of (Phase 35b/c).
    -- An imported chef therefore gets ZERO ROWS here, which the client already
    -- renders as "not ranked yet" — the behaviour Phase 30 built for a profile
    -- with no public recipes, reused unchanged.
    where p.public_recipe_count > 0
      and p.kind = 'member'
  )
  select
    x.rnk, x.pid, x.pname, x.pavatar, x.ptier, x.pscore, x.pcount,
    x.plikes, x.psaves, x.pviews, x.pjoined
  from ranked x
  where x.pid = p_chef;
$$;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'grant execute on function chef_standing(uuid) to anon, authenticated';
  end if;
end $$;

-- A chef's own recipes, ranked by what each one contributes to their score.
--
-- This is `/chef/:id`'s **Popular** tab, and the ordering is the point:
-- `chef_score(...)` per recipe is the same function the leaderboard sums per
-- chef, so the list cannot disagree with the score panel sitting directly above
-- it. One formula, not a second definition of popular (Gotcha 19's rule applied
-- to a ranking rather than a constant). PostgREST cannot `order` by that
-- expression, which is why the client calls an RPC instead of the table.
--
-- `setof recipes` like the three Discovery RPCs above, so the caller reuses
-- `kRecipeSelect` (the `recipes_owner_id_fkey` embedding) and the same `Recipe`
-- decode path. `stable`, invoker-rights, `anon`-callable — the page is
-- signed-out safe like the board.
--
-- `visibility = 'public'` is filtered **explicitly** rather than left to RLS:
-- under invoker rights the chef themself would otherwise see their own private
-- recipes here and read a different list than everyone else — the same trap
-- documented on `chefs_leaderboard`.
--
-- `p_offset` (Phase 31) is what turned this from the dialog's fixed top-3 into a
-- pageable tab. It also makes the ordering's totality load-bearing rather than
-- cosmetic: `offset` over a partial order shows one recipe twice and hides
-- another (Gotcha 24), which a top-3 with no second page could never expose.
--
-- Every historical signature must be dropped in the file that recreates the
-- function (B024): `create or replace` cannot change a return type or an
-- argument list, and a survivor makes the call ambiguous (42725). The two-arg
-- form below is exactly that survivor — a 2-argument call now resolves to this
-- function through `p_offset`'s default, but only once the old one is gone.
drop function if exists chef_top_recipes(uuid, int);
create or replace function chef_top_recipes(
  p_chef uuid,
  p_limit int default 3,
  p_offset int default 0
)
returns setof recipes
language sql
stable
as $$
  select r.*
  from recipes r
  where r.owner_id = p_chef
    and r.visibility = 'public'
  -- Deterministic full ordering: two recipes with equal contribution would
  -- otherwise swap places between calls and make the list look unstable.
  order by chef_score(r.like_count, r.save_count, r.view_count) desc,
           r.save_count desc,
           r.like_count desc,
           r.created_at desc,
           r.id
  limit p_limit offset p_offset;
$$;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'grant execute on function chef_top_recipes(uuid, int, int) to anon, authenticated';
  end if;
end $$;

-- The same chef's recipes, ranked by the engagement they earned in the **last
-- seven days** — `/chef/:id`'s Trending tab (Phase 31).
--
-- Three deliberate differences from `recipes_trending`, and each one exists
-- because this ranks *one chef's* catalogue rather than the whole vault:
--
--  1. **No `created_at` window.** The global shelf only considers recipes
--     published in the last 30 days. A chef publishes across years — the sim
--     spreads a career over 24 months — so that filter would empty this tab for
--     most chefs on the board. The window here is on the *engagement*, not on
--     the recipe, which is the question the tab actually asks.
--  2. **Counted from the logs, not the counters.** `recipes.like_count` /
--     `view_count` are lifetime totals with no date on them, so a window has to
--     read `recipe_likes.created_at` and `recipe_views.viewed_at`. This is the
--     first ranking in the schema to do that; `recipe_likes_recipe_idx` is
--     `(recipe_id, created_at desc)` precisely for it.
--  3. **Anonymous views do not count, and a viewer counts once.**
--     `count(distinct v.user_id)` with `user_id is not null`, matching what
--     `on_view_insert` does to `recipes.view_count` (Gotcha 10 / B012). `anon`
--     holds `insert` on `recipe_views`, so counting raw rows would let an
--     unauthenticated loop rank any recipe first — the exact hole the counter
--     trigger was written to close, and re-opening it in a new ranking would
--     not show up as a regression anywhere.
--
-- Weighting is `likes × 2 + viewers`: a like is a deliberate act and a view is
-- ambient, so a handful of likes should outrank a wave of passers-by without
-- drowning them out entirely.
--
-- **The ranking never empties the tab.** A chef with no engagement this week
-- scores 0 on every recipe and falls through to `created_at desc, id` — their
-- catalogue, newest first, which is a truthful "nothing is moving right now"
-- rather than an empty state that reads like a broken page. That tie-break is
-- also the total order `p_offset` needs (Gotcha 24).
-- No B024 drop list yet — this signature is the first. Add one here the moment
-- the argument list changes.
-- **`security definer` (B092).** This function ranks on the LOGS, not on the
-- denormalized counters, and that makes it the only ranking RPC in this file
-- whose answer depended on who asked. `views_select` is `owns_recipe(recipe_id)`,
-- so under invoker rights the distinct-viewer term counted zero rows for `anon`
-- and for every signed-in non-owner: the ordering silently degraded to likes
-- alone for everybody except the chef, who saw a different Trending tab from
-- their own readers with no error raised anywhere. Shipped that way in Phase 31
-- and found in Phase 33 while building `chef_window_stats`, which hit the same
-- wall from the other side.
--
-- Safe to elevate for the same reasons `chef_window_stats` is, and they are
-- what a future edit must preserve: no dynamic SQL, no writes, a pinned
-- `search_path`, and — the load-bearing one — the `visibility = 'public'`
-- filter below is written out explicitly, so removing RLS from the loop removes
-- a safety net that was never the thing doing the filtering. The logs are read
-- for COUNTS only; no viewer id leaves this function.
--
-- `rls_matrix.sql` F20/F21 pin it: `anon` and the owner must get the SAME
-- order. The whole failure mode is that it looks correct from the one seat a
-- developer usually tests from.
create or replace function chef_trending_recipes(
  p_chef uuid,
  p_limit int default 20,
  p_offset int default 0
)
returns setof recipes
language sql
stable
security definer
set search_path = public
as $$
  select r.*
  from recipes r
  where r.owner_id = p_chef
    and r.visibility = 'public'
  order by (
      (select count(*) from recipe_likes l
        where l.recipe_id = r.id
          and l.created_at >= now() - interval '7 days') * 2
    + (select count(distinct v.user_id) from recipe_views v
        where v.recipe_id = r.id
          and v.user_id is not null
          and v.viewed_at >= now() - interval '7 days')
    ) desc,
    r.created_at desc,
    r.id
  limit p_limit offset p_offset;
$$;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'grant execute on function chef_trending_recipes(uuid, int, int) to anon, authenticated';
  end if;
end $$;

-- Atomic deep-copy fork. Returns the new recipe id.
create or replace function fork_recipe(p_source uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_new_recipe uuid;
  v_src recipes%rowtype;
  v_ig record;
  v_new_ig uuid;
  v_sg record;
  v_new_sg uuid;
  v_version uuid;
  v_me uuid;
begin
  -- Authentication first, and explicitly (OPT-S6). An anonymous call used to
  -- get as far as the INSERT and die on `owner_id`'s not-null constraint — an
  -- accident of the schema, not a guard, and one that reports itself as a
  -- constraint violation rather than an authorization failure. EXECUTE is also
  -- revoked from `anon` below, so this is the second of two locks.
  if auth.uid() is null then
    raise exception 'must be signed in to fork a recipe';
  end if;

  -- Phase 35b: the OWNER of the new recipe is a `profiles` id, and that is no
  -- longer the same value as `auth.uid()` for a member who has claimed an
  -- imported chef page. A signed-in caller always has one (`handle_new_user`
  -- plus the B015 backfill), so a null here means the database is in the broken
  -- state that backfill exists to repair — say so rather than failing later on
  -- a not-null constraint, which is the exact accident OPT-S6 removed above.
  v_me := current_profile_id();
  if v_me is null then
    raise exception 'no profile for the current account';
  end if;

  if not can_read_recipe(p_source) then
    raise exception 'not authorized to read source recipe';
  end if;

  select * into v_src from recipes where id = p_source;

  insert into recipes (
    owner_id, title, description, cover_image_url, cuisine, category, difficulty,
    prep_minutes, cook_minutes, servings, visibility, attribution,
    forked_from_recipe_id, forked_from_version_id, nutrition
  ) values (
    v_me, v_src.title, v_src.description, v_src.cover_image_url, v_src.cuisine,
    v_src.category, v_src.difficulty, v_src.prep_minutes, v_src.cook_minutes, v_src.servings,
    'private', v_src.attribution, v_src.id, v_src.current_version_id, v_src.nutrition
  )
  returning id into v_new_recipe;

  -- copy ingredient groups + ingredients
  for v_ig in select * from ingredient_groups where recipe_id = p_source loop
    insert into ingredient_groups (recipe_id, name, sort_order)
    values (v_new_recipe, v_ig.name, v_ig.sort_order)
    returning id into v_new_ig;

    insert into ingredients (group_id, quantity, unit, name, note, is_optional, sort_order, food_id)
    select v_new_ig, quantity, unit, name, note, is_optional, sort_order, food_id
    from ingredients where group_id = v_ig.id;
  end loop;

  -- copy step groups + steps
  for v_sg in select * from step_groups where recipe_id = p_source loop
    insert into step_groups (recipe_id, name, sort_order)
    values (v_new_recipe, v_sg.name, v_sg.sort_order)
    returning id into v_new_sg;

    insert into steps (group_id, step_order, text, image_url, duration_minutes, temperature, tip, sort_order)
    select v_new_sg, step_order, text, image_url, duration_minutes, temperature, tip, sort_order
    from steps where group_id = v_sg.id;
  end loop;

  -- copy tags
  insert into recipe_tags (recipe_id, tag_id)
  select v_new_recipe, tag_id from recipe_tags where recipe_id = p_source;

  -- Initial version snapshot for the fork. It used to be a literal `'{}'` —
  -- a version row that records nothing, so the fork's own first version could
  -- not be restored or diffed. `recipe_snapshot` (OPT-A1) is defined for exactly
  -- this shape. It is defined *below* this function, which is fine and not the
  -- B045 trap: plpgsql resolves names when the body runs, not when it is
  -- created, and no caller can reach `fork_recipe` before the apply finishes.
  insert into recipe_versions (recipe_id, version_number, author_id, change_summary, content_snapshot)
  values (
    v_new_recipe, 1, v_me, 'Forked from source recipe',
    recipe_snapshot(v_new_recipe)
  )
  returning id into v_version;

  update recipes set current_version_id = v_version where id = v_new_recipe;

  return v_new_recipe;
end;
$$;

-- Forking is a signed-in action, so `anon` has no business calling it (OPT-S6).
-- Postgres grants EXECUTE to `public` on every new function, which is how
-- PostgREST exposes it as an RPC — revoking from `public` is what actually
-- closes it, and `authenticated` then has to be granted back explicitly.
-- Belt and braces with the `auth.uid() is null` check inside the body: this
-- stops the call at the API edge, that stops it if the grant is ever widened.
do $$
begin
  execute 'revoke execute on function fork_recipe(uuid) from public';
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke execute on function fork_recipe(uuid) from anon';
    execute 'grant execute on function fork_recipe(uuid) to authenticated';
  end if;
end $$;

-- ============================================================================
-- Atomic recipe save (OPT-A1)
-- ============================================================================

-- The JSON a `recipe_versions` row stores as its snapshot.
--
-- Built here rather than in Dart (where it lived until OPT-A1) for two reasons:
-- the version row is now written inside the same transaction as the save, so
-- there is no post-save read to build it from; and `fork_recipe` used to store a
-- literal `'{}'` because assembling the same shape in SQL by hand was not worth
-- it. Both now call this.
--
-- `to_jsonb(r) - 'search_tsv'` rather than a column list on purpose: a snapshot
-- that silently drops a column added later is worse than one carrying a column
-- nobody reads. `search_tsv` is the one exclusion — a ~450-byte tsvector,
-- derived from the rest, that would otherwise be copied into every version row
-- forever.
--
-- Ordering is explicit at all four levels for the same reason the client read is
-- (B022): a snapshot is a restore point, and a reversed one restores a reversed
-- recipe.
drop function if exists recipe_snapshot(uuid);
create or replace function recipe_snapshot(p_recipe uuid)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'recipe', (select to_jsonb(r) - 'search_tsv' from recipes r where r.id = p_recipe),
    'ingredient_groups', (
      select coalesce(jsonb_agg(
        to_jsonb(g) || jsonb_build_object('ingredients', (
          select coalesce(jsonb_agg(to_jsonb(i) order by i.sort_order), '[]'::jsonb)
          from ingredients i where i.group_id = g.id
        ))
        order by g.sort_order
      ), '[]'::jsonb)
      from ingredient_groups g where g.recipe_id = p_recipe
    ),
    'step_groups', (
      select coalesce(jsonb_agg(
        to_jsonb(s) || jsonb_build_object('steps', (
          select coalesce(jsonb_agg(to_jsonb(st) order by st.step_order), '[]'::jsonb)
          from steps st where st.group_id = s.id
        ))
        order by s.sort_order
      ), '[]'::jsonb)
      from step_groups s where s.recipe_id = p_recipe
    )
  );
$$;

-- Create or update a recipe, replace its content, and append its version — in
-- **one transaction** (OPT-A1).
--
-- What this closes:
--
--   * **The data-loss window (Gotcha 11).** The client used to update the row,
--     delete both group trees, then re-insert them one group at a time. A
--     failure anywhere in the middle — a dropped connection, a closed laptop —
--     left the recipe with its title saved and its content gone, permanently.
--     Now the whole thing commits or none of it does.
--   * **The version_number race.** `version_number` was computed client-side by
--     reading `max(...)` and adding one, in a separate round trip from the
--     insert, so two saves of the same recipe could read the same maximum. Here
--     the `update recipes` below takes the row lock, so a second save waits and
--     then reads a maximum that includes the first.
--   * **The round trips.** A recipe with 3 ingredient groups and 4 step groups
--     cost 1 update + 2 deletes + 7 inserts + 1 read + 1 version insert. It is
--     now this call plus one read for the return value.
--
-- `security definer` because the delete-then-insert has to be one unit and the
-- version row is written on the caller's behalf, so it opens with its own
-- authorization check exactly like `fork_recipe`, and **only ever writes the
-- client-writable columns**.
--
-- MAINTENANCE: that column list is the third copy of the same set — the grants
-- block, `_writablePayload` in `recipe_repository.dart`, and here. A new
-- client-writable column has to reach all three; this is the copy that fails
-- quietly if you forget, because the column simply never saves.
--
-- Content arrives as JSON arrays in list order, and `sort_order` / `step_order`
-- are the array index — the same rule the client's `_persistContent` applied,
-- and what the editor's reordering relies on.
-- Both drops are the B024 discipline pre-armed (OPT-A6's reasoning): the day
-- either signature changes, the drop has to already live in the file that
-- recreates it, not be added after a `42725` on someone's database.
drop function if exists save_recipe(uuid, jsonb, jsonb, jsonb, text);
create or replace function save_recipe(
  p_recipe_id         uuid,
  p_payload           jsonb,
  p_ingredient_groups jsonb,
  p_step_groups       jsonb,
  p_change_summary    text default 'Updated'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_recipe    uuid;
  v_next      int;
  v_parent    uuid;
  v_servings  int;
  v_nutrition jsonb;
  v_me        uuid;
begin
  if auth.uid() is null then
    raise exception 'must be signed in to save a recipe' using errcode = '42501';
  end if;

  -- Phase 35b: `owner_id` and `author_id` are `profiles` ids, which stopped
  -- being `auth.uid()` the moment a member could claim an imported chef page.
  v_me := current_profile_id();
  if v_me is null then
    raise exception 'no profile for the current account' using errcode = '42501';
  end if;

  -- `->` (jsonb), never `->>` (text): there is no implicit text→jsonb cast,
  -- so the wrong arrow is a runtime error on the first save. The `nullif`
  -- is the JSON-null trap: a Dart map with a null value arrives as
  -- `'null'::jsonb`, which is NOT SQL NULL and fails the typeof check.
  v_nutrition := nullif(p_payload -> 'nutrition', 'null'::jsonb);

  if p_recipe_id is null then
    -- Phase 29c: a label claiming `source = 'auto'` is recomputed from the
    -- SAME trees this transaction persists — the client's numbers are
    -- preview-only and die here, which is what makes fabricated "estimates"
    -- impossible to store (the Gotcha 11 shape: the one gate that sees the
    -- content sees the label too). Manual labels (no `source`) and null pass
    -- through untouched. `estimate_nutrition` stamps `source` itself and
    -- returns a null label when nothing counted, so Auto-with-nothing stores
    -- SQL NULL, never an empty lie.
    if v_nutrition ->> 'source' = 'auto' then
      -- The `nullif` again, one layer deeper and for the same reason: a null
      -- `label` key is `'null'::jsonb`, which is NOT SQL NULL and fails
      -- `recipes_nutrition_is_object` with 23514. Found by BL-7's B22d.
      v_nutrition := nullif(
        estimate_nutrition(
          p_ingredient_groups,
          coalesce((p_payload->>'servings')::int, 1)
        ) -> 'label',
        'null'::jsonb
      );
    end if;

    -- Lineage is server-owned (B082) and `fork_recipe` is its only writer, so a
    -- create carrying one is a forged claim — the client's own `create()` path
    -- sends null here for every new recipe. Raising rather than ignoring,
    -- because on *this* branch a non-null value cannot have come from anywhere
    -- legitimate; the update branch takes the opposite call, and the comment
    -- there says why.
    if p_payload->>'forked_from_recipe_id' is not null
       or p_payload->>'forked_from_version_id' is not null then
      raise exception 'fork lineage is set by fork_recipe, not by save_recipe'
        using errcode = '42501';
    end if;

    insert into recipes (
      owner_id, title, description, cover_image_url, cuisine, category,
      difficulty, prep_minutes, cook_minutes, servings, visibility, attribution,
      nutrition
    ) values (
      v_me,
      p_payload->>'title',
      coalesce(p_payload->>'description', ''),
      p_payload->>'cover_image_url',
      p_payload->>'cuisine',
      p_payload->>'category',
      coalesce((p_payload->>'difficulty')::difficulty, 'easy'),
      coalesce((p_payload->>'prep_minutes')::int, 0),
      coalesce((p_payload->>'cook_minutes')::int, 0),
      coalesce((p_payload->>'servings')::int, 1),
      coalesce((p_payload->>'visibility')::recipe_visibility, 'private'),
      p_payload->>'attribution',
      v_nutrition
    )
    returning id into v_recipe;
  else
    -- The authorization check the definer rights bypass. `owns_recipe` is the
    -- same predicate `recipes_update` uses, so this cannot drift from RLS.
    if not owns_recipe(p_recipe_id) then
      raise exception 'not authorized to save this recipe' using errcode = '42501';
    end if;

    -- The insert branch's auto recompute (Phase 29c), against the EFFECTIVE
    -- serving count — the payload's when sent, the row's when omitted, the
    -- same coalesce the update below applies. `for update` takes the row lock
    -- a statement early so a concurrent save of the same recipe cannot read a
    -- servings value the other transaction is about to change.
    if v_nutrition ->> 'source' = 'auto' then
      select coalesce((p_payload->>'servings')::int, servings)
        into v_servings
        from recipes where id = p_recipe_id
        for update;
      -- `nullif` per the insert branch: a null label is `'null'::jsonb`.
      v_nutrition := nullif(
        estimate_nutrition(p_ingredient_groups, v_servings) -> 'label',
        'null'::jsonb
      );
    end if;

    -- Two rules, and the split is not arbitrary. A **not-null** column falls
    -- back to what the row already holds, because a key the payload omits must
    -- not silently reset it to a default — and it cannot mean "clear" either,
    -- since the column forbids null (clearing a text field is an explicit `""`,
    -- which `->>` returns as an empty string, not null). A **nullable** column
    -- is assigned straight through, because there null genuinely means clear and
    -- the client always sends every key (`_writablePayload`).
    update recipes set
      title                  = coalesce(p_payload->>'title', title),
      description            = coalesce(p_payload->>'description', description),
      cover_image_url        = p_payload->>'cover_image_url',
      cuisine                = p_payload->>'cuisine',
      category               = p_payload->>'category',
      difficulty             = coalesce((p_payload->>'difficulty')::difficulty, difficulty),
      prep_minutes           = coalesce((p_payload->>'prep_minutes')::int, prep_minutes),
      cook_minutes           = coalesce((p_payload->>'cook_minutes')::int, cook_minutes),
      servings               = coalesce((p_payload->>'servings')::int, servings),
      visibility             = coalesce((p_payload->>'visibility')::recipe_visibility, visibility),
      attribution            = p_payload->>'attribution',
      -- `forked_from_recipe_id` / `forked_from_version_id` are deliberately
      -- absent (B082): server-owned, so the row keeps what `fork_recipe` wrote.
      -- Ignored rather than rejected, unlike the insert branch — the client
      -- echoes the whole model back on every save (`_writablePayload`), so a
      -- fork's *legitimate* lineage arrives in the payload of every edit it
      -- ever gets, and raising here would make forked recipes unsaveable.
      -- Nullable, so it is assigned straight through like the other nullable
      -- columns; extracted (and possibly recomputed) at the top of the
      -- function — see the declaration for the `->` + `nullif` reasoning.
      nutrition              = v_nutrition
    where id = p_recipe_id;

    v_recipe := p_recipe_id;

    -- Wholesale replacement, as before — but inside the transaction, so the gap
    -- between the delete and the re-insert is neither observable nor
    -- interruptible. Children cascade.
    delete from ingredient_groups where recipe_id = v_recipe;
    delete from step_groups        where recipe_id = v_recipe;
  end if;

  with g as (
    select
      elem->>'name'                              as name,
      (ord - 1)::int                             as sort_order,
      coalesce(elem->'ingredients', '[]'::jsonb) as children
    from jsonb_array_elements(coalesce(p_ingredient_groups, '[]'::jsonb))
      with ordinality as t(elem, ord)
  ),
  ins as (
    insert into ingredient_groups (recipe_id, name, sort_order)
    select v_recipe, coalesce(g.name, ''), g.sort_order from g
    returning id, sort_order
  )
  insert into ingredients (group_id, quantity, unit, name, note, is_optional, sort_order, food_id)
  select
    ins.id,
    (c.elem->>'quantity')::numeric,
    c.elem->>'unit',
    coalesce(c.elem->>'name', ''),
    c.elem->>'note',
    coalesce((c.elem->>'is_optional')::boolean, false),
    (c.ord - 1)::int,
    -- Text slug; FK-checked. A key the payload omits (or a json null) arrives
    -- as SQL NULL — an unlinked ingredient, not an error.
    c.elem->>'food_id'
  from ins
  join g on g.sort_order = ins.sort_order
  cross join lateral jsonb_array_elements(g.children) with ordinality as c(elem, ord);

  with g as (
    select
      elem->>'name'                        as name,
      (ord - 1)::int                       as sort_order,
      coalesce(elem->'steps', '[]'::jsonb) as children
    from jsonb_array_elements(coalesce(p_step_groups, '[]'::jsonb))
      with ordinality as t(elem, ord)
  ),
  ins as (
    insert into step_groups (recipe_id, name, sort_order)
    select v_recipe, coalesce(g.name, ''), g.sort_order from g
    returning id, sort_order
  )
  insert into steps (
    group_id, step_order, text, image_url, duration_minutes, temperature, tip,
    sort_order
  )
  select
    ins.id,
    (c.ord - 1)::int,
    coalesce(c.elem->>'text', ''),
    c.elem->>'image_url',
    (c.elem->>'duration_minutes')::int,
    c.elem->>'temperature',
    c.elem->>'tip',
    (c.ord - 1)::int
  from ins
  join g on g.sort_order = ins.sort_order
  cross join lateral jsonb_array_elements(g.children) with ordinality as c(elem, ord);

  -- Read after the row lock above, which is what makes them safe against a
  -- concurrent save of the same recipe.
  select coalesce(max(version_number), 0) + 1 into v_next
  from recipe_versions where recipe_id = v_recipe;

  select id into v_parent
  from recipe_versions where recipe_id = v_recipe
  order by version_number desc limit 1;

  -- `current_version_id` follows via the recipe_versions_set_current trigger —
  -- never written from here, and not in the client's grant list either (B050).
  insert into recipe_versions (
    recipe_id, version_number, parent_version_id, author_id, change_summary,
    content_snapshot
  ) values (
    v_recipe,
    v_next,
    v_parent,
    v_me,
    coalesce(nullif(p_change_summary, ''), 'Updated'),
    recipe_snapshot(v_recipe)
  );

  return v_recipe;
end;
$$;

-- Same two locks as fork_recipe (OPT-S6): the body refuses an anonymous caller,
-- and EXECUTE is revoked from `public` — which is what PostgREST actually
-- exposes — then granted back to `authenticated` only. `recipe_snapshot` is
-- internal to these two functions and gets the full revoke: it is `stable` and
-- harmless, but every function in `public` is an RPC and this one has no reason
-- to be one.
do $$
begin
  execute 'revoke execute on function save_recipe(uuid, jsonb, jsonb, jsonb, text) from public';
  execute 'revoke execute on function recipe_snapshot(uuid) from public';
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke execute on function save_recipe(uuid, jsonb, jsonb, jsonb, text) from anon';
    execute 'revoke execute on function recipe_snapshot(uuid) from anon, authenticated';
    execute 'grant execute on function save_recipe(uuid, jsonb, jsonb, jsonb, text) to authenticated';
  end if;
end $$;

-- ============================================================================
-- search_foods — the ingredients editor's typeahead (Phase 29a)
--
-- Rank: exact alias/name match, then prefix, then trigram tail (pg_trgm `%`,
-- default 0.3 threshold — prefix LIKE carries queries too short to trigram).
-- Returns id + display_name only: the editor needs nothing else, and the row's
-- nutrition columns are not this surface's business.
--
-- Invoker-rights and `authenticated`-only, like the registry tables it reads:
-- only the signed-in editor links ingredients (Gotcha 3 — PostgREST exposes
-- every public function, so anon is revoked explicitly). Every order ends in
-- `f.id` because ties are otherwise free to swap (Gotcha 24 applies to any
-- limited read, not just paged ones).
-- ============================================================================
create or replace function search_foods(p_query text, p_limit int default 10)
returns table (id text, display_name text)
language sql
stable
as $$
  -- `term` feeds similarity(); `pat` is the LIKE prefix with the user's
  -- wildcards escaped, so a query of '%' cannot rank every food as a prefix
  -- match. The limit clamp coalesces first — `limit NULL` would mean no limit.
  with q as (
    select t.term,
           replace(replace(replace(t.term, '\', '\\'), '%', '\%'), '_', '\_')
             || '%' as pat
    from (select lower(trim(p_query)) as term) t
  )
  select f.id, f.display_name
  from food f
  cross join q
  left join food_alias a on a.food_id = f.id
  where q.term <> ''
    and (
      a.alias like q.pat
      or lower(f.display_name) like q.pat
      or a.alias % q.term
      or lower(f.display_name) % q.term
    )
  group by f.id, f.display_name, q.term, q.pat
  order by
    min(case
      when a.alias = q.term or lower(f.display_name) = q.term then 0
      when a.alias like q.pat
        or lower(f.display_name) like q.pat then 1
      else 2
    end),
    max(greatest(
      coalesce(similarity(a.alias, q.term), 0),
      similarity(lower(f.display_name), q.term)
    )) desc,
    f.display_name,
    f.id
  limit least(greatest(coalesce(p_limit, 10), 1), 25);
$$;

do $$
begin
  execute 'revoke execute on function search_foods(text, int) from public';
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke execute on function search_foods(text, int) from anon';
    execute 'grant execute on function search_foods(text, int) to authenticated';
  end if;
end $$;

-- ============================================================================
-- estimate_nutrition — the auto-nutrition arithmetic (Phase 29c)
--
-- Pure over its arguments plus the registry tables: it never reads `recipes`
-- or `ingredients`, so the editor can preview an UNSAVED draft with the same
-- trees the save path sends, and `save_recipe`'s auto branch recomputes
-- through this exact function — the arithmetic exists once, here, and there
-- is deliberately no Dart mirror (the Gotcha 19 two-implementations tax,
-- not bought when nothing needs per-keystroke recompute).
--
-- The grams ladder, first hit wins; anything that falls through contributes
-- NOTHING and is named in `unmatched` (the editor's "not counted" list —
-- honesty over coverage, and never a guessed density: a water default makes a
-- cup of flour 236 g instead of 120 g, which is worse than absence):
--
--   1. skip outright: `is_optional`, no/unknown `food_id`, `quantity` null
--   2. mass unit      → quantity × food_unit.factor (grams per unit)
--   3. volume unit    → quantity × factor (ml) × food.grams_per_ml
--                       (null grams_per_ml = unresolvable for this food)
--   4. count unit     → quantity × food_portion.grams for that unit_key
--                       ('' spelling is the bare-count marker → 'each')
--   5. unknown / unresolvable spelling → skip (units.json's `unresolvable`
--                       list is intent, not a gate — absence behaves the same)
--
-- Then Σ (grams × per-100 g ⁄ 100), ÷ servings. Added sugars can never come
-- from FDC data (measured at 0 rows across every generic food), so they are
-- rule-derived: the food's authored `added_sugars_g` when curated, else its
-- total sugars when `is_added_sugar`. A nutrient every counted food lacks
-- stays absent from the label rather than printing a false 0 — `sum()`
-- ignores nulls and `jsonb_strip_nulls` drops the key.
--
-- Returns `{label, counted, total, unmatched}`. `label` is null when nothing
-- counted (never an all-empty object — null is the one spelling of "no
-- info"), and otherwise carries `source: 'auto'` — the provenance stamp is
-- applied HERE so every consumer of the arithmetic stores the same shape.
-- Rounding: whole numbers for kcal and mg, one decimal for grams — inside
-- `formatNutritionValue`'s two-decimal ceiling. jsonb compares numbers as
-- numerics, so 10 and 10.0 stay equal in the fixture assertions.
--
-- Invoker-rights + `authenticated`-only like the registry it reads (Gotcha
-- 3); inside `save_recipe` it runs with definer rights, which also holds.
-- ============================================================================
create or replace function estimate_nutrition(
  p_ingredient_groups jsonb,
  p_servings          int
)
returns jsonb
language sql
stable
as $$
  with ing as (
    select
      coalesce(c.elem->>'name', '')                     as name,
      (c.elem->>'quantity')::numeric                    as quantity,
      lower(trim(coalesce(c.elem->>'unit', '')))        as unit,
      c.elem->>'food_id'                                as food_id,
      coalesce((c.elem->>'is_optional')::boolean, false) as is_optional
    from jsonb_array_elements(coalesce(p_ingredient_groups, '[]'::jsonb)) g(elem)
    cross join lateral
      jsonb_array_elements(coalesce(g.elem->'ingredients', '[]'::jsonb)) c(elem)
    -- Nameless rows are the editor's blank placeholders; the save path drops
    -- them too, so they must not pad `total`.
    where coalesce(c.elem->>'name', '') <> ''
  ),
  resolved as (
    select
      i.name,
      f.is_added_sugar,
      f.calories, f.total_fat_g, f.saturated_fat_g, f.trans_fat_g,
      f.cholesterol_mg, f.sodium_mg, f.total_carbs_g, f.dietary_fiber_g,
      f.total_sugars_g, f.added_sugars_g, f.protein_g,
      -- The ladder. A `case` with no `else` yields null for every fall-through
      -- (unknown spelling, volume without density, count without a portion),
      -- which is the single "not counted" marker everything below keys on.
      case
        -- `quantity <= 0` skips with the null case, not with the arithmetic: a
        -- negative row would *subtract* from the label, which is a wrong number
        -- rather than a missing one (B076). `ingredients_quantity_positive`
        -- (32a2) now makes it unstorable and the editor's Qty field says so
        -- first; this stays as the belt-and-braces guard for any row written
        -- before either existed.
        when i.is_optional or i.quantity is null or i.quantity <= 0
          or f.id is null then null
        when u.class = 'mass'   then i.quantity * u.factor
        when u.class = 'volume' then i.quantity * u.factor * f.grams_per_ml
        when u.class = 'count'  then i.quantity * p.grams
      end as grams
    from ing i
    left join food f       on f.id = i.food_id
    left join food_unit u  on u.spelling = i.unit
    left join food_portion p on p.food_id = f.id and p.unit_key = u.unit_key
  ),
  sums as (
    select
      count(*)                                  as total,
      count(*) filter (where grams is not null) as counted,
      coalesce(
        jsonb_agg(distinct name) filter (where grams is null),
        '[]'::jsonb
      )                                         as unmatched,
      sum(grams * calories        / 100) as calories,
      sum(grams * total_fat_g     / 100) as total_fat_g,
      sum(grams * saturated_fat_g / 100) as saturated_fat_g,
      sum(grams * trans_fat_g     / 100) as trans_fat_g,
      sum(grams * cholesterol_mg  / 100) as cholesterol_mg,
      sum(grams * sodium_mg       / 100) as sodium_mg,
      sum(grams * total_carbs_g   / 100) as total_carbs_g,
      sum(grams * dietary_fiber_g / 100) as dietary_fiber_g,
      sum(grams * total_sugars_g  / 100) as total_sugars_g,
      -- The added-sugars rule (see the header): authored value first, else
      -- total sugars for foods flagged as added sugar, else nothing.
      sum(grams * coalesce(
            added_sugars_g,
            case when is_added_sugar then total_sugars_g end
          ) / 100)                         as added_sugars_g,
      sum(grams * protein_g       / 100) as protein_g
    from resolved
  ),
  label as (
    select
      s.counted, s.total, s.unmatched,
      jsonb_strip_nulls(jsonb_build_object(
        'calories',        round(s.calories        / v.n, 0),
        'total_fat_g',     round(s.total_fat_g     / v.n, 1),
        'saturated_fat_g', round(s.saturated_fat_g / v.n, 1),
        'trans_fat_g',     round(s.trans_fat_g     / v.n, 1),
        'cholesterol_mg',  round(s.cholesterol_mg  / v.n, 0),
        'sodium_mg',       round(s.sodium_mg       / v.n, 0),
        'total_carbs_g',   round(s.total_carbs_g   / v.n, 1),
        'dietary_fiber_g', round(s.dietary_fiber_g / v.n, 1),
        'total_sugars_g',  round(s.total_sugars_g  / v.n, 1),
        'added_sugars_g',  round(s.added_sugars_g  / v.n, 1),
        'protein_g',       round(s.protein_g       / v.n, 1)
      )) as label
    from sums s
    cross join (select greatest(coalesce(p_servings, 1), 1)::numeric as n) v
  )
  select jsonb_build_object(
    'label', case
      when l.counted = 0 or l.label = '{}'::jsonb then null
      else l.label || jsonb_build_object('source', 'auto')
    end,
    'counted',   l.counted,
    'total',     l.total,
    'unmatched', l.unmatched
  )
  from label l;
$$;

do $$
begin
  execute 'revoke execute on function estimate_nutrition(jsonb, int) from public';
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke execute on function estimate_nutrition(jsonb, int) from anon';
    execute 'grant execute on function estimate_nutrition(jsonb, int) to authenticated';
  end if;
end $$;

-- ============================================================================
-- match_foods — batched link candidates for the editor's review flow (29c)
--
-- Top-3 `search_foods` candidates per distinct name, keyed by the name as
-- given, `[]` when nothing matches (the key stays, so the caller can tell
-- "looked, found nothing" from "never asked"). One call for a whole recipe's
-- unlinked names when an old recipe first switches to Automatic — inference
-- proposes, a human confirms, and only the confirmed link is ever stored
-- (matching is never re-run at save time; the link is a stored fact).
--
-- Capped at 100 names: no recipe has more, and this is an `authenticated`
-- RPC. Same lock shape as `search_foods`, which it wraps.
-- ============================================================================
create or replace function match_foods(p_names text[])
returns jsonb
language sql
stable
as $$
  select coalesce(
    jsonb_object_agg(n.name, coalesce(c.cands, '[]'::jsonb)),
    '{}'::jsonb
  )
  from (
    select distinct trim(t.name) as name
    from unnest(coalesce(p_names, '{}'::text[])) t(name)
    where coalesce(trim(t.name), '') <> ''
    order by 1
    limit 100
  ) n
  cross join lateral (
    select jsonb_agg(
      jsonb_build_object('id', s.id, 'display_name', s.display_name)
    ) as cands
    from search_foods(n.name, 3) s
  ) c;
$$;

do $$
begin
  execute 'revoke execute on function match_foods(text[]) from public';
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke execute on function match_foods(text[]) from anon';
    execute 'grant execute on function match_foods(text[]) to authenticated';
  end if;
end $$;

-- ============================================================================
-- recompute_auto_nutrition — the registry-refresh path (Phase 29d)
-- ============================================================================
-- An estimated label is a **stored snapshot**, not a live view: `save_recipe`
-- computes it once, at save time, and nothing reads it back through
-- `estimate_nutrition` again. That is the right trade for a value every recipe
-- card and detail page renders — but it means a change to `nutritionData/`
-- (a corrected gram weight, a new portion, a food that gained its saturated-fat
-- row) reaches only recipes saved *after* it. Every label already in the table
-- keeps the old arithmetic, silently and forever.
--
-- This is the same shape as `recompute_all_chef_stats()` and it is here for the
-- same reason (Gotcha 19's twin): the formula and its inputs live in one place,
-- so the way a change to them reaches existing rows is an idempotent whole-table
-- recompute on every apply, not a hand-written data migration per release.
--
-- Three properties this depends on:
--
--   * **Only `source = 'auto'` rows are touched.** A manual label is a number a
--     human typed and no registry edit may overwrite it; `source`'s absence is
--     what spells manual (29c), so the predicate is the whole safety argument.
--   * **`recipe_snapshot(id) -> 'ingredient_groups'` is the same tree shape the
--     editor sends** — `save_recipe` persists exactly what `recipe_snapshot`
--     reads back, so this recomputes from the identical input the save path
--     estimated from. Nothing here re-derives a tree by hand.
--   * **`is distinct from` makes it a no-op when nothing moved,** which is what
--     lets it run on every apply. `recipes_touch` is an unconditional
--     `before update` trigger, so without that guard every apply would bump
--     `updated_at` on every estimated recipe.
--
-- The `nullif` is B075 one more time: `-> 'label'` is `'null'::jsonb`, not SQL
-- NULL, when nothing counted. A recipe whose links all broke therefore drops to
-- `null` — "no info", the honest answer, and the same thing `save_recipe` stores
-- for Automatic-with-nothing-counted (B22d). Note this is **one-way**: a null
-- label carries no `source`, so the row leaves this function's `where` clause
-- and a later registry fix will not re-estimate it. Re-opening the recipe and
-- picking Automatic again is the recovery, and it is a cook's decision to make.
--
-- Invoker-rights, `execute` revoked below, exactly like `recompute_all_chef_stats`
-- (Gotcha 3): it writes rows the caller does not own, and PostgREST would
-- otherwise expose it as an RPC.
create or replace function recompute_auto_nutrition()
returns void
language plpgsql
as $$
begin
  -- An empty registry can only produce null labels, so a run that precedes the
  -- registry load would blank every estimated label in the database. That is
  -- reachable on two real paths, not a hypothetical: `db:reset` applies this
  -- file *before* `nutrition_foods.sql`, and so does the upgrade path in
  -- `database.yml`. Nothing to estimate with is not the same as nothing to
  -- estimate.
  if not exists (select 1 from food) then
    return;
  end if;

  update recipes r
  set nutrition = e.label
  from (
    select
      r2.id,
      nullif(
        estimate_nutrition(
          recipe_snapshot(r2.id) -> 'ingredient_groups',
          r2.servings
        ) -> 'label',
        'null'::jsonb
      ) as label
    from recipes r2
    where r2.nutrition ->> 'source' = 'auto'
  ) e
  where r.id = e.id
    and r.nutrition is distinct from e.label;
end;
$$;

do $$
begin
  execute 'revoke execute on function recompute_auto_nutrition() from public';
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke execute on function recompute_auto_nutrition() from anon, authenticated';
  end if;
end $$;

-- Idempotent backfill, the `recompute_all_chef_stats()` precedent: re-estimate
-- every stored auto label on every apply. A fresh database has no recipes yet
-- and an empty registry, so this is a no-op there and the committed
-- `seed_recipes.sql` labels stand — which is why those have to be regenerated
-- and committed alongside a `nutritionData/` change (recipeData/README.md).
select recompute_auto_nutrition();

-- ============================================================================
-- recipes_corpus (Phase 35c) — the surface imported content DOES appear on
-- ============================================================================
-- Everything ranked filters `is_imported` out, so this is the one query that
-- lets a reader at the corpus. Same contract as the shelves: `setof recipes` so
-- the caller reuses `kRecipeSelect` and its owner embed, `stable`,
-- invoker-rights, `anon`-callable.
--
-- **The ordering is the whole design problem.** Imported rows arrive with every
-- counter at zero and an `imported_at` that is the same minute for tens of
-- thousands of them, so there is no engagement to rank by and no meaningful
-- recency either. `quality_score` is what the importer computed once from field
-- coverage — does it have a cover image, a servings count, timings, a plausible
-- number of ingredients, steps, a named chef — and it is a property of the
-- *capture*, not of the dish or the cook. It ends in `id` because a score out of
-- 100 over 558k rows ties constantly, and `offset` over a tie shows one recipe
-- twice and hides another, silently (Gotcha 24).
--
-- `p_cuisine` is a filter rather than a second function: the alternative is one
-- RPC per facet, and each would restate this ordering.
create or replace function recipes_corpus(
  p_limit   int  default 20,
  p_offset  int  default 0,
  p_cuisine text default null
)
returns setof recipes
language sql
stable
as $$
  select r.*
  from recipes r
  where r.visibility = 'public'
    and r.is_imported
    -- A takedown is honoured on read as well as on import, so removing one
    -- recipe from view does not need a deploy or a delete.
    and r.rights_mode <> 'blocked'
    and (p_cuisine is null or r.cuisine = p_cuisine)
  order by r.quality_score desc nulls last, r.id
  limit greatest(p_limit, 0) offset greatest(p_offset, 0);
$$;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'grant execute on function recipes_corpus(int, int, text) to anon, authenticated';
  end if;
end $$;

-- ============================================================================
-- import_recipe (Phase 35c) — one captured recipe into the database
-- ============================================================================
-- The importer's whole write path, in SQL, so `tool/corpus_import.dart` is a
-- JSON transformer and nothing else. The same split `seed_recipe_v2` uses, and
-- for the same reason: the rules about what an import may write belong next to
-- the constraints that enforce them, not in a language that cannot see them.
--
-- Takes one normalised document and returns the recipe id, or **null** when it
-- declined — which it does for three reasons, all of them ordinary:
--
--   * the URL is on `import_blocklist` (a takedown, honoured on the way in);
--   * the recipe is already here (the unique index on
--     `(source_entity_id, source_url)` is the idempotency key, so re-running a
--     finished shard is free);
--   * the document has no ingredients or no steps, which a capture sometimes
--     produces and which is not worth a row.
--
-- Null rather than an exception for all three: an import of 40,000 recipes that
-- aborts on the first blocked URL is an import nobody can run.
--
-- `security definer` because it writes `profiles` and `entities` rows that no
-- caller owns, and EXECUTE is revoked from every API role below — this is an
-- administrative tool, not an endpoint. It is the Gotcha 3 pattern, with the
-- authorization check replaced by "only `postgres` can call it at all".
--
-- **What it deliberately does NOT write** (Phase 35a's position, in code):
--   * `description` — the publisher's editorial prose. Captured, never imported.
--   * any engagement counter, and no `recipe_versions` row. An imported recipe
--     arrives with no history and no numbers; 558k version snapshots of edits
--     nobody made would be a gigabyte of fiction.
--   * `nutrition` — the captured block is strings ("345 kcal") and the
--     estimator cannot read non-English ingredient names. Null is honest.
create or replace function import_recipe(p_doc jsonb)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entity   uuid;
  v_chef     uuid;
  v_recipe   uuid;
  v_published timestamptz;
  v_url      text := p_doc ->> 'source_url';
  v_slug     text := p_doc ->> 'entity_slug';
  v_chefname text := nullif(trim(coalesce(p_doc ->> 'chef_name', '')), '');
  v_quality  int;
  v_group    uuid;
  v_g        jsonb;
  v_i        jsonb;
  v_gord     int;
  v_iord     int;
begin
  if v_url is null or v_slug is null or (p_doc ->> 'title') is null then
    return null;
  end if;

  -- A takedown is honoured before anything is written, and the blocklist row
  -- outlives the recipe precisely so this check has something to read.
  if exists (select 1 from import_blocklist b where b.url = v_url) then
    return null;
  end if;

  -- A capture with no ingredients or no steps is not a recipe. Checked before
  -- the entity and the profile are created, so a shard of empty captures does
  -- not leave a directory full of publishers crediting nothing.
  if coalesce(jsonb_array_length(p_doc -> 'ingredient_groups'), 0) = 0
     or coalesce(jsonb_array_length(p_doc -> 'step_groups'), 0) = 0 then
    return null;
  end if;

  -- ---- the publisher -------------------------------------------------------
  -- `created_by` stays null: nobody on this service registered it, which is
  -- what `Entity.isImported` reads and what the page says out loud.
  -- `src:` namespaced, per `entities_slug_namespace` above: a member cannot
  -- have taken this name, so the find-or-create below cannot attach a
  -- publisher's catalogue to a squatter's row.
  v_slug := 'src:' || v_slug;

  insert into entities (slug, name, kind, homepage, country, created_by)
  values (
    v_slug,
    coalesce(nullif(p_doc ->> 'entity_name', ''), v_slug),
    coalesce((p_doc ->> 'entity_kind')::entity_kind, 'publication'),
    p_doc ->> 'entity_homepage',
    p_doc ->> 'entity_country',
    null
  )
  on conflict (slug) do nothing;
  select e.id into v_entity from entities e where e.slug = v_slug;

  -- ---- the chef ------------------------------------------------------------
  -- **Identity is scoped to the publisher, never global.** Two people called
  -- Sarah on two blogs are two chefs; the corpus roll-up keys on a normalised
  -- name globally and its own README flags that as deliberately imperfect.
  -- Collapsing two strangers into one identity is a far worse error than
  -- splitting one person into two rows, and only one of them is correctable
  -- later.
  --
  -- No byline means the recipe is credited to the publisher alone, which is the
  -- honest reading of a page that names nobody.
  if v_chefname is not null then
    select p.id into v_chef
    from profiles p
    join entity_members m on m.profile_id = p.id and m.entity_id = v_entity
    where p.kind = 'imported' and p.display_name = v_chefname
    limit 1;

    if v_chef is null then
      insert into profiles (display_name, kind)
      values (left(v_chefname, 80), 'imported')
      returning id into v_chef;

      insert into entity_members (entity_id, profile_id, role)
      values (v_entity, v_chef, 'chef')
      on conflict (entity_id, profile_id) do nothing;
    end if;
  else
    -- The publisher-as-author case. One profile per entity, reused.
    select p.id into v_chef
    from profiles p
    join entity_members m on m.profile_id = p.id and m.entity_id = v_entity
    where p.kind = 'imported'
      and p.display_name = coalesce(nullif(p_doc ->> 'entity_name', ''), v_slug)
    limit 1;

    if v_chef is null then
      insert into profiles (display_name, kind)
      values (left(coalesce(nullif(p_doc ->> 'entity_name', ''), v_slug), 80), 'imported')
      returning id into v_chef;

      insert into entity_members (entity_id, profile_id, role)
      values (v_entity, v_chef, 'chef')
      on conflict (entity_id, profile_id) do nothing;
    end if;
  end if;

  -- ---- the quality score ---------------------------------------------------
  -- Computed here rather than in Dart so there is one definition of it, and
  -- computed at all because 558k rows with identical zero counters have no
  -- total order — `offset` over a tie shows one row twice and hides another
  -- (Gotcha 24). It measures the CAPTURE, not the dish: how complete the record
  -- is, not how good the food is. Nothing updates it afterwards.
  v_quality :=
      case when nullif(p_doc ->> 'cover_image_url', '') is not null then 25 else 0 end
    + case when coalesce((p_doc ->> 'servings')::int, 0) > 0 then 15 else 0 end
    + case when coalesce((p_doc ->> 'prep_minutes')::int, 0)
               + coalesce((p_doc ->> 'cook_minutes')::int, 0) > 0 then 15 else 0 end
    + case when v_chefname is not null then 15 else 0 end
    + case when nullif(p_doc ->> 'cuisine', '') is not null then 5 else 0 end
    + case when nullif(p_doc ->> 'category', '') is not null then 5 else 0 end
    -- A recipe with two ingredients or ninety is usually a bad capture rather
    -- than an unusual dish, so the band is rewarded and the tails are not.
    + case when (
        select count(*) from jsonb_array_elements(p_doc -> 'ingredient_groups') g
        cross join jsonb_array_elements(g -> 'ingredients') i
      ) between 3 and 40 then 10 else 0 end
    + case when (
        select count(*) from jsonb_array_elements(p_doc -> 'step_groups') g
        cross join jsonb_array_elements(g -> 'steps') st
      ) between 2 and 40 then 10 else 0 end;

  -- A scraped `datePublished` is whatever the page put in the attribute, and at
  -- 21,000 records that includes `Thu, 01/06/2022 - 15:47`. The cast is
  -- therefore attempted and abandoned rather than trusted: an unparseable date
  -- is an unknown date, and one bad string must not abort a batch of 500 good
  -- recipes. `tool/corpus_import.dart` filters these out too — this is the
  -- second lock, for any other caller.
  begin
    v_published := (p_doc ->> 'published_at')::timestamptz;
  exception when others then
    v_published := null;
  end;

  -- ---- the recipe ----------------------------------------------------------
  -- `description` is absent on purpose (Phase 35a): the captured one is the
  -- publisher's editorial writing, which we link rather than reproduce.
  insert into recipes (
    owner_id, title, description, cover_image_url, cuisine, category,
    difficulty, prep_minutes, cook_minutes, servings, visibility,
    is_imported, quality_score, source_url, source_name, source_entity_id,
    imported_at, rights_mode, image_mode, created_at, updated_at
  ) values (
    v_chef,
    left(p_doc ->> 'title', 200),
    '',
    -- `recipes_text_lengths` caps the URL at 2048, and a truncated URL is a
    -- broken image rather than a shorter one — so an over-long cover is
    -- dropped, not trimmed. Cuisine and category ARE trimmed, because a
    -- scraped page occasionally puts a sentence in the field and the first 80
    -- characters of it are still the right answer.
    case
      when char_length(coalesce(p_doc ->> 'cover_image_url', '')) between 1 and 2048
        then p_doc ->> 'cover_image_url'
      else null
    end,
    left(nullif(p_doc ->> 'cuisine', ''), 80),
    left(nullif(p_doc ->> 'category', ''), 80),
    coalesce((p_doc ->> 'difficulty')::difficulty, 'medium'),
    greatest(coalesce((p_doc ->> 'prep_minutes')::int, 0), 0),
    greatest(coalesce((p_doc ->> 'cook_minutes')::int, 0), 0),
    greatest(coalesce((p_doc ->> 'servings')::int, 1), 1),
    'public',
    true,
    v_quality,
    v_url,
    coalesce(nullif(p_doc ->> 'entity_name', ''), v_slug),
    v_entity,
    now(),
    coalesce((p_doc ->> 'rights_mode')::rights_mode, 'functional'),
    coalesce((p_doc ->> 'image_mode')::image_mode, 'hotlink'),
    coalesce(v_published, now()),
    now()
  )
  on conflict (source_entity_id, source_url) where source_url is not null
  do nothing
  returning id into v_recipe;

  -- Already here. The unique index did its job and this run has nothing to do.
  if v_recipe is null then
    return null;
  end if;

  -- ---- content -------------------------------------------------------------
  -- Numbered from 0 WITHIN each group, matching `_persistContent` — numbering
  -- continuously across groups looks right until the first edit re-persists
  -- per group and silently renumbers everything (the B022 failure mode).
  v_gord := 0;
  for v_g in select * from jsonb_array_elements(p_doc -> 'ingredient_groups') loop
    insert into ingredient_groups (recipe_id, name, sort_order)
    values (v_recipe, coalesce(v_g ->> 'name', ''), v_gord)
    returning id into v_group;

    v_iord := 0;
    for v_i in select * from jsonb_array_elements(v_g -> 'ingredients') loop
      insert into ingredients (group_id, quantity, unit, name, note, is_optional, sort_order)
      values (
        v_group,
        -- A captured quantity is whatever the page said; a negative one is a
        -- parse fault, and `ingredients_quantity_positive` would abort the
        -- whole batch over it.
        nullif(greatest(coalesce((v_i ->> 'quantity')::numeric, 0), 0), 0),
        nullif(v_i ->> 'unit', ''),
        left(coalesce(nullif(v_i ->> 'name', ''), 'ingredient'), 200),
        left(nullif(v_i ->> 'note', ''), 500),
        coalesce((v_i ->> 'is_optional')::boolean, false),
        v_iord
      );
      v_iord := v_iord + 1;
    end loop;
    v_gord := v_gord + 1;
  end loop;

  v_gord := 0;
  for v_g in select * from jsonb_array_elements(p_doc -> 'step_groups') loop
    insert into step_groups (recipe_id, name, sort_order)
    values (v_recipe, coalesce(v_g ->> 'name', ''), v_gord)
    returning id into v_group;

    v_iord := 0;
    for v_i in select * from jsonb_array_elements(v_g -> 'steps') loop
      insert into steps (group_id, step_order, text, image_url, duration_minutes, temperature, tip, sort_order)
      values (
        v_group, v_iord,
        coalesce(nullif(v_i ->> 'text', ''), ''),
        nullif(v_i ->> 'image_url', ''),
        (v_i ->> 'duration_minutes')::int,
        nullif(v_i ->> 'temperature', ''),
        nullif(v_i ->> 'tip', ''),
        v_iord
      );
      v_iord := v_iord + 1;
    end loop;
    v_gord := v_gord + 1;
  end loop;

  return v_recipe;
end;
$$;

-- Gotcha 3: PostgREST exposes every function in `public` as an RPC, and this
-- one creates profiles and entities and writes provenance no client may touch.
-- `postgres` only.
do $$
begin
  execute 'revoke execute on function import_recipe(jsonb) from public';
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke execute on function import_recipe(jsonb) from anon, authenticated';
  end if;
end $$;

-- ============================================================================
-- Profile claims (Phase 35b) — a real chef taking over their imported page
-- ============================================================================
-- Approving a claim moves every recipe, every version, every like, save, rating
-- and share from the claimant's own profile onto the claimed one, then moves
-- the account link. It is the only operation in this schema that changes who
-- owns existing content, which is why it is a `security definer` function with
-- EXECUTE revoked from the API roles rather than anything RLS could express:
-- there is no set of row predicates that makes "transfer 3,000 recipes" safe to
-- offer as a PATCH.
--
-- Run by hand for now (`select approve_profile_claim('<claim uuid>')` as
-- `postgres`). An admin role and a review UI are a later change; the point of
-- landing the function now is that the claim story is *complete* — an imported
-- chef page is not a dead end with a promise attached.
--
-- Three things about the shape:
--
--   **The whole thing is one transaction, by construction.** A half-finished
--   merge would leave recipes on one profile and the account link on another,
--   and `unique(auth_user_id)` is what makes that impossible to persist rather
--   than merely unlikely.
--
--   **The stats trigger is parked for the duration.** `recipes_chef_stats`
--   fires `after update of ... owner_id`, and `on_recipe_stats_change` then
--   recomputes BOTH profiles — so moving 3,000 recipes would run 6,000
--   whole-catalogue aggregates. Disabling it and recomputing twice at the end
--   is the same pattern `2_sim_generate.sql` uses for its bulk load. The
--   `alter table` takes an ACCESS EXCLUSIVE lock on `recipes` until commit,
--   which is a real cost and the reason this is an administrative action rather
--   than something a user triggers from a button.
--
--   **Engagement rows are moved, not merged.** `recipe_likes`, `recipe_saves`
--   and `recipe_ratings` are all keyed `(user_id, recipe_id)`, so a row whose
--   target already exists cannot be moved — a person cannot like one recipe
--   twice. Those rows are dropped rather than duplicated, which is the only
--   answer the key allows and also the correct one.
create or replace function approve_profile_claim(p_claim uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_claim  profile_claims%rowtype;
  v_target profiles%rowtype;
  v_old    uuid;
begin
  select * into v_claim from profile_claims where id = p_claim for update;
  if v_claim.id is null then
    raise exception 'claim % not found', p_claim using errcode = '42704';
  end if;
  if v_claim.status <> 'pending' then
    raise exception 'claim % is already %', p_claim, v_claim.status using errcode = '42501';
  end if;

  select * into v_target from profiles where id = v_claim.profile_id for update;
  if v_target.id is null then
    raise exception 'claimed profile no longer exists' using errcode = '42704';
  end if;
  -- Re-checked here and not merely in `claims_insert`: that policy was
  -- evaluated when the claim was FILED, and two claims on one profile can both
  -- be pending at once.
  if v_target.auth_user_id is not null then
    raise exception 'profile % is already claimed', v_target.id using errcode = '42501';
  end if;

  -- The claimant's existing identity, if they have one. A claimant who has
  -- never signed in has no profile and there is nothing to merge.
  select p.id into v_old
  from profiles p where p.auth_user_id = v_claim.claimant_auth_user_id;

  if v_old is not null and v_old <> v_target.id then
    alter table recipes disable trigger recipes_chef_stats;

    update recipes            set owner_id  = v_target.id where owner_id  = v_old;
    update recipe_versions    set author_id = v_target.id where author_id = v_old;
    update recipe_suggestions set author_id = v_target.id where author_id = v_old;

    -- `(user_id, recipe_id)` primary keys: move what can move, drop the rest.
    update recipe_likes l set user_id = v_target.id
     where l.user_id = v_old
       and not exists (select 1 from recipe_likes x
                        where x.user_id = v_target.id and x.recipe_id = l.recipe_id);
    delete from recipe_likes where user_id = v_old;

    update recipe_saves s set user_id = v_target.id
     where s.user_id = v_old
       and not exists (select 1 from recipe_saves x
                        where x.user_id = v_target.id and x.recipe_id = s.recipe_id);
    delete from recipe_saves where user_id = v_old;

    update recipe_ratings rt set user_id = v_target.id
     where rt.user_id = v_old
       and not exists (select 1 from recipe_ratings x
                        where x.user_id = v_target.id and x.recipe_id = rt.recipe_id);
    delete from recipe_ratings where user_id = v_old;

    -- `(recipe_id, shared_with_user_id)`, same treatment.
    update recipe_shares sh set shared_with_user_id = v_target.id
     where sh.shared_with_user_id = v_old
       and not exists (select 1 from recipe_shares x
                        where x.recipe_id = sh.recipe_id
                          and x.shared_with_user_id = v_target.id);
    delete from recipe_shares where shared_with_user_id = v_old;
    -- A share of a recipe the target now owns is meaningless; owning it is
    -- strictly more than being shared it.
    delete from recipe_shares sh using recipes r
     where r.id = sh.recipe_id and r.owner_id = sh.shared_with_user_id;

    -- `recipe_views` is an append-only log with no uniqueness, so every row
    -- moves. Two rows for one (user, recipe) pair are fine there by design —
    -- `on_view_insert` only ever counted the first, and `view_count` is
    -- monotonic (Gotcha 10), so nothing downstream reads the log as a count.
    update recipe_views set user_id = v_target.id where user_id = v_old;

    update entity_members m set profile_id = v_target.id
     where m.profile_id = v_old
       and not exists (select 1 from entity_members x
                        where x.entity_id = m.entity_id and x.profile_id = v_target.id);
    delete from entity_members where profile_id = v_old;

    update entities set created_by = v_target.id where created_by = v_old;

    -- `ratings_write` forbids rating your own recipe. The merge can create one
    -- anyway — the claimant may have rated a recipe that is now theirs — and a
    -- self-rating would inflate the chef's own average, so it is removed here
    -- rather than left for a table constraint that does not exist.
    delete from recipe_ratings rt using recipes r
     where r.id = rt.recipe_id and r.owner_id = rt.user_id;

    -- The old profile becomes a TOMBSTONE, not a delete: its id is in URLs
    -- somebody has already shared, and `merged_into` is what lets a future
    -- redirect resolve them.
    update profiles
       set auth_user_id = null,
           merged_into  = v_target.id
     where id = v_old;

    alter table recipes enable trigger recipes_chef_stats;
  end if;

  update profiles
     set auth_user_id = v_claim.claimant_auth_user_id,
         kind         = 'member',
         claimed_at   = now()
   where id = v_target.id;

  update profile_claims
     set status = 'approved', decided_at = now()
   where id = p_claim;

  -- Any other pending claim on this profile is now unanswerable — the profile
  -- has an owner. Closed here rather than left pending forever.
  update profile_claims
     set status = 'rejected',
         decided_at = now(),
         note = concat_ws(' ', note, '(superseded: profile was claimed)')
   where profile_id = v_target.id and status = 'pending' and id <> p_claim;

  perform recompute_chef_stats(v_target.id);
  if v_old is not null and v_old <> v_target.id then
    perform recompute_chef_stats(v_old);
  end if;

  return v_target.id;
end;
$$;

create or replace function reject_profile_claim(p_claim uuid, p_note text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update profile_claims
     set status = 'rejected', decided_at = now(), note = coalesce(p_note, note)
   where id = p_claim and status = 'pending';
  if not found then
    raise exception 'no pending claim %', p_claim using errcode = '42704';
  end if;
end;
$$;

-- Gotcha 3: PostgREST exposes every function in `public` as an RPC, and these
-- two decide who owns content. Neither is callable by an API role.
do $$
begin
  execute 'revoke execute on function approve_profile_claim(uuid) from public';
  execute 'revoke execute on function reject_profile_claim(uuid, text) from public';
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke execute on function approve_profile_claim(uuid) from anon, authenticated';
    execute 'revoke execute on function reject_profile_claim(uuid, text) from anon, authenticated';
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- The pending-claim cap (Phase 35c)
-- ----------------------------------------------------------------------------
-- `profile_claims_one_pending_idx` stops one account filing the same claim
-- twice, and nothing stopped it filing against every imported profile there
-- is: a loop over `/chef/:id` could open a claim on each of the corpus's
-- bylines, and every one of them lands in a review queue that a person works
-- through by hand. So an account may hold at most `profile_claim_pending_cap()`
-- claims that are still PENDING. A decided claim — approved or rejected — frees
-- its slot, because the cap bounds the reviewer's queue, not a person's
-- history: a chef whose first claim was rejected for thin evidence has to be
-- able to file again.
--
-- **Why 5.** The legitimate reason to hold more than one is a real person who
-- appears under several bylines, and the corpus says how many that is: of the
-- imported profiles on the local stack (2026-09-24), the most any one display
-- name repeats is 4, and a named chef who writes for several publishers (one
-- appears under 3 of them) is the shape that matters. 5 covers that with a
-- spare, and turns "every imported profile" into five rows per account.
-- It is not a defence against an attacker with many accounts — signup is that
-- axis, and it is not this table's to close — it is what makes one account
-- unable to flood the queue.
--
-- **A trigger, not a clause in `claims_insert`,** for three reasons. A policy
-- refusal is an anonymous 42501, indistinguishable from "you may not claim
-- that profile", where this one has a reason a UI can show. A policy subquery
-- is racy: two concurrent inserts each count the other's row as invisible and
-- both pass. And an AFTER trigger fires only for a row that has already passed
-- `claims_insert`'s `with check` (Postgres enforces it before queueing after
-- triggers), so a refused insert — filing as somebody else, say — never
-- reaches the count, and the cap cannot be used to probe how many claims
-- ANOTHER account has open.
--
-- The advisory lock is keyed on the claimant, so it serialises one account's
-- filings against each other and nobody else's. Under READ COMMITTED (what
-- PostgREST runs) the count after the lock takes a fresh snapshot, so it sees
-- a concurrent filing that committed while this one waited.
--
-- `security definer` so the count reads every pending claim of the claimant's
-- whatever `claims_select` says: the cap must not quietly loosen the day that
-- policy is narrowed. It reads one account's rows and writes nothing.
create or replace function profile_claim_pending_cap()
returns int language sql immutable as $$ select 5 $$;

create or replace function on_profile_claim_cap()
returns trigger language plpgsql
security definer
set search_path = public
as $$
declare
  v_pending int;
begin
  perform pg_advisory_xact_lock(
    hashtextextended('profile_claims:' || new.claimant_auth_user_id::text, 0));

  select count(*) into v_pending
  from profile_claims
  where claimant_auth_user_id = new.claimant_auth_user_id
    and status = 'pending';

  -- `>`, not `>=`: this is an AFTER trigger, so the row being filed is already
  -- in the count.
  if v_pending > profile_claim_pending_cap() then
    raise exception 'profile claim limit reached'
      using errcode = 'P0001',
            detail  = format('An account may have at most %s pending profile claims at once.',
                             profile_claim_pending_cap()),
            hint    = 'Wait for one of your pending claims to be reviewed, then file again.';
  end if;
  return null;
end;
$$;

-- `update of status` as well as insert, so a reviewer re-opening a decided
-- claim by hand is held to the same cap as a new filing. The WHEN clause keeps
-- every approve/reject — the only other updates this table sees — out of it.
drop trigger if exists profile_claims_pending_cap on profile_claims;
create trigger profile_claims_pending_cap
  after insert or update of status on profile_claims
  for each row when (new.status = 'pending')
  execute function on_profile_claim_cap();
