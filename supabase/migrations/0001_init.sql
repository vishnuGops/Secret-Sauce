-- 0001_init.sql — Secret-Sauce full schema (single source of truth)
--
-- One idempotent file: safe to re-run during early development. Contains enums,
-- tables, indexes, triggers, functions, Row-Level Security, storage buckets, and
-- the discovery/fork RPCs. Split into proper versioned migrations later, once
-- there is real data to preserve.

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
create index if not exists recipes_owner_idx on recipes (owner_id);
create index if not exists recipes_visibility_idx on recipes (visibility);
create index if not exists recipes_forked_from_idx on recipes (forked_from_recipe_id);

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
create index if not exists recipe_versions_recipe_idx on recipe_versions (recipe_id);

-- Deferred FKs from recipes -> recipe_versions (guarded)
alter table recipes drop constraint if exists recipes_current_version_fk;
alter table recipes
  add constraint recipes_current_version_fk
  foreign key (current_version_id) references recipe_versions (id) on delete set null;

alter table recipes drop constraint if exists recipes_forked_from_version_fk;
alter table recipes
  add constraint recipes_forked_from_version_fk
  foreign key (forked_from_version_id) references recipe_versions (id) on delete set null;

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

create table if not exists recipe_views (
  id        uuid primary key default gen_random_uuid(),
  recipe_id uuid not null references recipes (id) on delete cascade,
  user_id   uuid references profiles (id) on delete set null,
  viewed_at timestamptz not null default now()
);
create index if not exists recipe_views_recipe_idx on recipe_views (recipe_id);

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
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', ''));
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- Denormalized counters.
create or replace function bump_count(p_recipe uuid, p_col text, p_delta int)
returns void language plpgsql as $$
begin
  execute format('update recipes set %I = greatest(0, %I + $1) where id = $2', p_col, p_col)
    using p_delta, p_recipe;
end;
$$;

create or replace function on_like_change()
returns trigger language plpgsql as $$
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
returns trigger language plpgsql as $$
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

-- Full-text search document for a recipe (title/description/ingredients/tags).
create or replace function recipe_search_document(p_recipe uuid)
returns tsvector language sql stable as $$
  select
    setweight(to_tsvector('english', coalesce((select title from recipes where id = p_recipe), '')), 'A') ||
    setweight(to_tsvector('english', coalesce((select description from recipes where id = p_recipe), '')), 'B') ||
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
alter table recipe_suggestions  enable row level security;

-- profiles: world-readable, self-writable
drop policy if exists profiles_select on profiles;
create policy profiles_select on profiles for select using (true);
drop policy if exists profiles_update on profiles;
create policy profiles_update on profiles for update using (id = auth.uid());
drop policy if exists profiles_insert on profiles;
create policy profiles_insert on profiles for insert with check (id = auth.uid());

-- recipes
drop policy if exists recipes_select on recipes;
create policy recipes_select on recipes for select using (can_read_recipe(id));
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

-- tags: readable by all; any authenticated user may create
drop policy if exists tags_select on tags;
create policy tags_select on tags for select using (true);
drop policy if exists tags_insert on tags;
create policy tags_insert on tags for insert with check (auth.uid() is not null);

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

-- views: anyone who can read the recipe may log a view
drop policy if exists views_insert on recipe_views;
create policy views_insert on recipe_views for insert with check (can_read_recipe(recipe_id));
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

-- ============================================================================
-- Discovery ranking, search, and atomic fork RPCs
-- ============================================================================

-- Trending: recency-weighted popularity over public recipes.
create or replace function recipes_trending(p_limit int default 20)
returns setof recipes
language sql
stable
as $$
  select r.*
  from recipes r
  where r.visibility = 'public'
  order by
    (r.like_count + r.view_count)::numeric
      / power(extract(epoch from (now() - r.created_at)) / 3600.0 + 2.0, 1.5) desc
  limit p_limit;
$$;

-- Popular: all-time saves + likes over public recipes.
create or replace function recipes_popular(p_limit int default 20)
returns setof recipes
language sql
stable
as $$
  select r.*
  from recipes r
  where r.visibility = 'public'
  order by (r.save_count + r.like_count) desc, r.created_at desc
  limit p_limit;
$$;

-- Full-text search over public recipes (title/description/ingredients/tags).
create or replace function recipes_search(p_query text, p_limit int default 30)
returns setof recipes
language sql
stable
as $$
  select r.*
  from recipes r
  where r.visibility = 'public'
    and recipe_search_document(r.id) @@ websearch_to_tsquery('english', p_query)
  order by ts_rank(recipe_search_document(r.id), websearch_to_tsquery('english', p_query)) desc
  limit p_limit;
$$;

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

  -- initial version snapshot for the fork
  insert into recipe_versions (recipe_id, version_number, author_id, change_summary, content_snapshot)
  values (v_new_recipe, 1, auth.uid(), 'Forked from source recipe', '{}'::jsonb)
  returning id into v_version;

  update recipes set current_version_id = v_version where id = v_new_recipe;

  return v_new_recipe;
end;
$$;
