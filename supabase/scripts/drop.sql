-- drop.sql — remove all Secret-Sauce app objects from the public schema.
-- Safe to run repeatedly. Does NOT touch auth.users accounts (only the
-- profile trigger). Use `db:create` afterwards to rebuild.

-- Trigger on auth.users that references our function.
drop trigger if exists on_auth_user_created on auth.users;

-- Tables (cascade clears dependent rows, FKs, indexes, policies).
drop table if exists
  recipe_suggestions,
  recipe_ratings,
  recipe_views,
  recipe_saves,
  recipe_likes,
  recipe_shares,
  recipe_tags,
  tags,
  steps,
  step_groups,
  ingredients,
  ingredient_groups,
  recipe_versions,
  recipes,
  profiles
cascade;

-- Functions.
drop function if exists handle_new_user() cascade;
drop function if exists bump_count(uuid, text, int) cascade;
drop function if exists on_like_change() cascade;
drop function if exists on_save_change() cascade;
drop function if exists on_rating_change() cascade;
drop function if exists recompute_recipe_rating(uuid) cascade;
drop function if exists touch_updated_at() cascade;
drop function if exists recipe_search_document(uuid) cascade;
drop function if exists can_read_recipe(uuid) cascade;
drop function if exists owns_recipe(uuid) cascade;
drop function if exists recipes_trending(int) cascade;
drop function if exists recipes_popular(int) cascade;
drop function if exists recipes_search(text, int) cascade;
drop function if exists fork_recipe(uuid) cascade;
drop function if exists seed_recipe(uuid, text, text, text, text, difficulty, int, int, int, text, jsonb, jsonb, int, int, int) cascade;
drop function if exists seed_recipe(uuid, text, text, text, text, difficulty, int, int, int, text, jsonb, jsonb, int, int, int, jsonb) cascade;
drop function if exists seed_taster_ids() cascade;
drop function if exists seed_ratings(uuid, jsonb) cascade;

-- Enums.
drop type if exists difficulty cascade;
drop type if exists recipe_visibility cascade;
drop type if exists share_permission cascade;
drop type if exists suggestion_status cascade;
