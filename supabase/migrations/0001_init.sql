-- 0001_init.sql — Secret-Sauce schema BASELINE
--
-- Enums, tables, indexes, triggers, functions, Row-Level Security, storage
-- buckets, and the discovery / chefs / fork / save RPCs. Idempotent: this is
-- what a fresh database is built from, and re-running it is safe.
--
-- **FROZEN as of the OPT phase (OPT-A9).** This file is no longer where schema
-- changes go. `supabase/migrations/` is a numbered sequence now, and the next
-- change is `0002_<what_it_does>.sql` — because re-applying this file to push a
-- one-line change also re-runs its two whole-table backfills, and that cost
-- grows with the data forever.
--
-- The rules for the next file (numbering, guards, the B024 drop discipline,
-- grants-with-the-table, upgrade-path verification) are in
-- `supabase/migrations/README.md`. Read it before adding one.

-- ============================================================================
-- Extensions
-- ============================================================================
create extension if not exists "pgcrypto";      -- gen_random_uuid()

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
end $$;

-- ============================================================================
-- Tables
-- ============================================================================

-- profiles (1:1 with auth.users)
create table if not exists profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default '',
  avatar_url   text,
  bio          text,
  created_at   timestamptz not null default now()
);

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
create index if not exists profiles_leaderboard_idx
  on profiles (chef_score desc, public_recipe_count desc, display_name asc, id asc)
  where public_recipe_count > 0;

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

create index if not exists recipes_owner_idx on recipes (owner_id);
create index if not exists recipes_visibility_idx on recipes (visibility);
create index if not exists recipes_forked_from_idx on recipes (forked_from_recipe_id);
create index if not exists recipes_rating_idx on recipes (rating_avg desc, rating_count desc);
-- Discover's two date-ordered surfaces (OPT-P2). `recipes_trending` bounds its
-- window to the last 30 days and Discover **Recent** orders by `created_at`
-- desc; both filter to public, so a partial index on exactly that predicate
-- serves both and stays small (it indexes the public rows only). Partial on
-- `visibility` rather than a composite because every reader of it filters to
-- public — there is no "recent private recipes" surface.
create index if not exists recipes_public_created_idx
  on recipes (created_at desc) where visibility = 'public';

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
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', ''))
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
insert into public.profiles (id, display_name)
select u.id, coalesce(u.raw_user_meta_data ->> 'display_name', '')
from auth.users u
left join public.profiles p on p.id = u.id
where p.id is null;

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
        or r.owner_id = auth.uid()
        or exists (
          select 1 from recipe_shares s
          where s.recipe_id = r.id and s.shared_with_user_id = auth.uid()
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
  select exists (select 1 from recipes r where r.id = p_recipe and r.owner_id = auth.uid());
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

-- profiles: world-readable, self-writable
drop policy if exists profiles_select on profiles;
create policy profiles_select on profiles for select using (true);
drop policy if exists profiles_update on profiles;
create policy profiles_update on profiles for update using (id = auth.uid());
drop policy if exists profiles_insert on profiles;
create policy profiles_insert on profiles for insert with check (id = auth.uid());

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
-- `shares_self_select` (`shared_with_user_id = auth.uid()`) is what keeps the
-- shares subquery working under invoker rights. `can_read_recipe(uuid)` stays for
-- the child tables, which pass a *parent* recipe id that genuinely needs a lookup.
drop policy if exists recipes_select on recipes;
create policy recipes_select on recipes for select using (
  visibility = 'public'
  or owner_id = auth.uid()
  or exists (
    select 1 from recipe_shares s
    where s.recipe_id = recipes.id and s.shared_with_user_id = auth.uid()
  )
);
drop policy if exists recipes_insert on recipes;
create policy recipes_insert on recipes for insert with check (owner_id = auth.uid());
drop policy if exists recipes_update on recipes;
create policy recipes_update on recipes for update using (owner_id = auth.uid());
drop policy if exists recipes_delete on recipes;
create policy recipes_delete on recipes for delete using (owner_id = auth.uid());

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
  using (shared_with_user_id = auth.uid());

-- likes / saves: user manages own rows; readable if recipe readable
drop policy if exists likes_select on recipe_likes;
create policy likes_select on recipe_likes for select using (can_read_recipe(recipe_id));
drop policy if exists likes_write on recipe_likes;
create policy likes_write on recipe_likes for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists saves_select on recipe_saves;
create policy saves_select on recipe_saves for select using (user_id = auth.uid());
drop policy if exists saves_write on recipe_saves;
create policy saves_write on recipe_saves for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ratings: readable with the recipe; a user writes only their own row, only for a
-- recipe they can read, and never for their own recipe (no self-rating).
drop policy if exists ratings_select on recipe_ratings;
create policy ratings_select on recipe_ratings for select using (can_read_recipe(recipe_id));
drop policy if exists ratings_write on recipe_ratings;
create policy ratings_write on recipe_ratings for all
  using (user_id = auth.uid())
  with check (
    user_id = auth.uid()
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
    and (user_id is null or user_id = auth.uid())
  );
drop policy if exists views_select on recipe_views;
create policy views_select on recipe_views for select using (owns_recipe(recipe_id));

-- suggestions (reserved): author or target-recipe owner can read; author can create
drop policy if exists suggestions_select on recipe_suggestions;
create policy suggestions_select on recipe_suggestions for select
  using (author_id = auth.uid() or owns_recipe(recipe_id));
drop policy if exists suggestions_insert on recipe_suggestions;
create policy suggestions_insert on recipe_suggestions for insert
  with check (author_id = auth.uid());
drop policy if exists suggestions_update on recipe_suggestions;
create policy suggestions_update on recipe_suggestions for update
  using (owns_recipe(recipe_id));

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
  grant insert (owner_id, title, description, cover_image_url, cuisine, category,
                difficulty, prep_minutes, cook_minutes, servings, visibility,
                attribution, forked_from_recipe_id, forked_from_version_id)
    on recipes to authenticated;
  grant update (title, description, cover_image_url, cuisine, category,
                difficulty, prep_minutes, cook_minutes, servings, visibility,
                attribution, forked_from_recipe_id, forked_from_version_id)
    on recipes to authenticated;

  -- profiles: NOT granted — chef_score, chef_tier, public_recipe_count,
  -- total_likes, total_saves, total_views, created_at. `id` is insert-only
  -- (`profiles_insert` pins it to auth.uid()).
  grant insert (id, display_name, avatar_url, bio) on profiles to authenticated;
  grant update (display_name, avatar_url, bio)     on profiles to authenticated;

  -- Signed-out visitors may log a view of a recipe they can read.
  grant insert on recipe_views to anon;
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
    and r.created_at > now() - interval '30 days'
  order by
    (r.like_count + r.view_count)::numeric
      / power(extract(epoch from (now() - r.created_at)) / 3600.0 + 2.0, 1.5) desc,
    r.created_at desc,
    r.id
  limit p_limit offset p_offset;
$$;

-- Popular: highest rated public recipes.
--
-- Straight AVG(rating) would put a single 5-star recipe above a 4.8 with 300
-- ratings, so the score is a Bayesian (weighted) average: each recipe starts
-- with `m` phantom ratings at the site-wide mean, and real ratings pull the
-- score away from that prior. Ties fall back to saves + likes, then recency,
-- then `id` — the last one exists so the order is total and `p_offset` (OPT-P9)
-- cannot show the same recipe on two pages. B024 drop as above.
drop function if exists recipes_popular(int);
create or replace function recipes_popular(p_limit int default 20, p_offset int default 0)
returns setof recipes
language sql
stable
as $$
  with prior as (
    select
      5::numeric as m,                                        -- prior weight (ratings)
      coalesce(sum(rating_sum) / nullif(sum(rating_count), 0), 3.5) as mean
    from recipes
    where visibility = 'public'
  )
  select r.*
  from recipes r cross join prior p
  where r.visibility = 'public'
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
-- window's ordering is a prefix of `profiles_leaderboard_idx`, so the plan
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
-- The drop is not currently load-bearing — the signature has never changed — but
-- it is where the drop has to live when it does (B024), and adding it after an
-- ambiguous-overload failure means editing a database that already has two
-- (OPT-A6). Note that a **return type** change needs this too, not just an
-- argument-list change: `create or replace` refuses both.
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
  total_views         bigint
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
      p.total_views         as pviews
    from profiles p
    -- Chefs with no public recipes (tasters, private-only accounts, brand-new
    -- signups) still *have* a tier for badge purposes; they just don't occupy
    -- leaderboard rows. Also the predicate of `profiles_leaderboard_idx`.
    where p.public_recipe_count > 0
  )
  select
    x.rnk, x.pid, x.pname, x.pavatar, x.ptier, x.pscore, x.pcount,
    x.plikes, x.psaves, x.pviews
  from ranked x
  -- Deterministic full ordering; dense_rank above lets tied scores share a rank.
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

-- A chef's own recipes, ranked by what each one contributes to their score.
--
-- This is the "Top recipes" list in the expanded chef card, and the ordering is
-- the point: `chef_score(...)` per recipe is the same function the leaderboard
-- sums per chef, so the list cannot disagree with the number it explains.
-- PostgREST cannot `order` by that expression, which is why the client calls an
-- RPC instead of the table.
--
-- `setof recipes` like the three Discovery RPCs above, so the caller reuses
-- `kRecipeSelect` (the `recipes_owner_id_fkey` embedding) and the same `Recipe`
-- decode path. `stable`, invoker-rights, `anon`-callable — the card is
-- signed-out safe like the board.
--
-- `visibility = 'public'` is filtered **explicitly** rather than left to RLS:
-- under invoker rights the chef themself would otherwise see their own private
-- recipes here and read a different list than everyone else — the same trap
-- documented on `chefs_leaderboard`.
--
-- Every historical signature must be dropped in the file that recreates the
-- function (B024): `create or replace` cannot change a return type or an
-- argument list, and a survivor makes the call ambiguous (42725).
drop function if exists chef_top_recipes(uuid, int);
create or replace function chef_top_recipes(p_chef uuid, p_limit int default 3)
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
  limit p_limit;
$$;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'grant execute on function chef_top_recipes(uuid, int) to anon, authenticated';
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
begin
  -- Authentication first, and explicitly (OPT-S6). An anonymous call used to
  -- get as far as the INSERT and die on `owner_id`'s not-null constraint — an
  -- accident of the schema, not a guard, and one that reports itself as a
  -- constraint violation rather than an authorization failure. EXECUTE is also
  -- revoked from `anon` below, so this is the second of two locks.
  if auth.uid() is null then
    raise exception 'must be signed in to fork a recipe';
  end if;

  if not can_read_recipe(p_source) then
    raise exception 'not authorized to read source recipe';
  end if;

  select * into v_src from recipes where id = p_source;

  insert into recipes (
    owner_id, title, description, cover_image_url, cuisine, category, difficulty,
    prep_minutes, cook_minutes, servings, visibility, attribution,
    forked_from_recipe_id, forked_from_version_id
  ) values (
    auth.uid(), v_src.title, v_src.description, v_src.cover_image_url, v_src.cuisine,
    v_src.category, v_src.difficulty, v_src.prep_minutes, v_src.cook_minutes, v_src.servings,
    'private', v_src.attribution, v_src.id, v_src.current_version_id
  )
  returning id into v_new_recipe;

  -- copy ingredient groups + ingredients
  for v_ig in select * from ingredient_groups where recipe_id = p_source loop
    insert into ingredient_groups (recipe_id, name, sort_order)
    values (v_new_recipe, v_ig.name, v_ig.sort_order)
    returning id into v_new_ig;

    insert into ingredients (group_id, quantity, unit, name, note, is_optional, sort_order)
    select v_new_ig, quantity, unit, name, note, is_optional, sort_order
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
    v_new_recipe, 1, auth.uid(), 'Forked from source recipe',
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
  v_recipe uuid;
  v_next   int;
  v_parent uuid;
begin
  if auth.uid() is null then
    raise exception 'must be signed in to save a recipe' using errcode = '42501';
  end if;

  if p_recipe_id is null then
    insert into recipes (
      owner_id, title, description, cover_image_url, cuisine, category,
      difficulty, prep_minutes, cook_minutes, servings, visibility, attribution,
      forked_from_recipe_id, forked_from_version_id
    ) values (
      auth.uid(),
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
      (p_payload->>'forked_from_recipe_id')::uuid,
      (p_payload->>'forked_from_version_id')::uuid
    )
    returning id into v_recipe;
  else
    -- The authorization check the definer rights bypass. `owns_recipe` is the
    -- same predicate `recipes_update` uses, so this cannot drift from RLS.
    if not owns_recipe(p_recipe_id) then
      raise exception 'not authorized to save this recipe' using errcode = '42501';
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
      forked_from_recipe_id  = (p_payload->>'forked_from_recipe_id')::uuid,
      forked_from_version_id = (p_payload->>'forked_from_version_id')::uuid
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
  insert into ingredients (group_id, quantity, unit, name, note, is_optional, sort_order)
  select
    ins.id,
    (c.elem->>'quantity')::numeric,
    c.elem->>'unit',
    coalesce(c.elem->>'name', ''),
    c.elem->>'note',
    coalesce((c.elem->>'is_optional')::boolean, false),
    (c.ord - 1)::int
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
    auth.uid(),
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
