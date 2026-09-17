-- drop.sql — remove all Secret-Sauce app objects from the public schema.
-- Safe to run repeatedly. Does NOT touch auth.users accounts (only the
-- profile trigger). Use `db:create` afterwards to rebuild.

-- Trigger on auth.users that references our function.
drop trigger if exists on_auth_user_created on auth.users;

-- Tables (cascade clears dependent rows, FKs, indexes, policies).
-- The food registry (Phase 29a) drops with everything else — it is rebuilt by
-- `db:nutrition`, which `db:reset` runs right after `create`.
drop table if exists
  food_unit,
  food_portion,
  food_alias,
  food,
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
  -- Phase 35b. `profile_claims` and `entity_members` reference `profiles`, and
  -- `entity_signature_dishes` references `recipes`; `cascade` would take them
  -- anyway, but naming them keeps this list a readable inventory of what the
  -- schema contains rather than a list of roots.
  import_blocklist,
  profile_claims,
  entity_signature_dishes,
  entity_members,
  entities,
  profiles
cascade;

-- Functions.
drop function if exists handle_new_user() cascade;
drop function if exists bump_count(uuid, text, int) cascade;
drop function if exists on_like_change() cascade;
drop function if exists on_save_change() cascade;
drop function if exists on_view_insert() cascade;
drop function if exists on_rating_change() cascade;
drop function if exists on_version_insert() cascade;
drop function if exists recompute_recipe_rating(uuid) cascade;
drop function if exists touch_updated_at() cascade;
drop function if exists recipe_search_document(uuid) cascade;
drop function if exists recipe_search_tsv(uuid, text, text) cascade;
drop function if exists refresh_search_tsv(uuid[]) cascade;
drop function if exists on_recipe_search_change() cascade;
drop function if exists on_ingredients_search_change() cascade;
drop function if exists on_ingredient_groups_search_change() cascade;
drop function if exists on_recipe_tags_search_change() cascade;
drop function if exists on_tags_search_change() cascade;
drop function if exists can_read_recipe(uuid) cascade;
drop function if exists owns_recipe(uuid) cascade;
-- Phase 35b identity. `current_profile_id()` is referenced by every policy in
-- the schema, but a quoted SQL body records no dependency, so `drop table
-- ... cascade` above does not reach it (the B042 shape).
drop function if exists current_profile_id() cascade;
drop function if exists is_entity_member(uuid) cascade;
drop function if exists is_entity_owner(uuid) cascade;
drop function if exists approve_profile_claim(uuid) cascade;
drop function if exists reject_profile_claim(uuid, text) cascade;
-- Phase 35c.
drop function if exists recipes_corpus(int, int, text) cascade;
drop function if exists import_recipe(jsonb) cascade;
-- Food registry typeahead (Phase 29a).
drop function if exists search_foods(text, int) cascade;
-- Auto-nutrition estimator + batched link candidates (Phase 29c) and the
-- registry-refresh backfill over stored labels (Phase 29d).
drop function if exists estimate_nutrition(jsonb, int) cascade;
drop function if exists match_foods(text[]) cascade;
drop function if exists recompute_auto_nutrition() cascade;
-- Discovery RPC signatures, oldest first: OPT-P9 added `p_offset`, and Postgres
-- keys drops by argument list, so both overloads stay listed.
drop function if exists recipes_trending(int) cascade;
drop function if exists recipes_trending(int, int) cascade;
drop function if exists recipes_popular(int) cascade;
drop function if exists recipes_popular(int, int) cascade;
drop function if exists recipes_search(text, int) cascade;
drop function if exists recipes_search(text, int, int) cascade;
-- The three Discover shelves and the rating prior they share (Phase 26).
drop function if exists recipes_quick(int, int) cascade;
drop function if exists recipes_projects(int, int) cascade;
drop function if exists recipes_most_forked(int, int) cascade;
-- `recipes_popular` and `recipes_quick` cross-join this one, but a quoted SQL
-- function body records no dependency, so `cascade` does not reach them —
-- they are dropped by name above, and both are recreated by the migrations.
drop function if exists site_rating_prior() cascade;
drop function if exists fork_recipe(uuid) cascade;
drop function if exists save_recipe(uuid, jsonb, jsonb, jsonb, text) cascade;
drop function if exists recipe_snapshot(uuid) cascade;
-- Chefs / leaderboard (Phase 18).
drop function if exists on_recipe_stats_change() cascade;
drop function if exists recompute_chef_stats(uuid) cascade;
drop function if exists recompute_all_chef_stats() cascade;
drop function if exists chef_score(bigint, bigint, bigint) cascade;
drop function if exists chef_tier_for(numeric) cascade;
drop function if exists chefs_leaderboard(int, int) cascade;
drop function if exists chefs_tier_counts() cascade;
-- chef_top_recipes signatures, oldest first (B024): Phase 31 added `p_offset`.
drop function if exists chef_top_recipes(uuid, int) cascade;
drop function if exists chef_top_recipes(uuid, int, int) cascade;
drop function if exists chef_trending_recipes(uuid, int, int) cascade;
drop function if exists chef_standing(uuid) cascade;
-- Phase 23's windowed half. `chefs_leaderboard_windowed` first: it reads
-- `chef_window_stats`, and dropping the callee first would leave a function
-- whose body no longer resolves (harmless for a `language sql` string body,
-- but the order costs nothing and says what depends on what).
drop function if exists chefs_leaderboard_windowed(int, int, int, timestamptz) cascade;
drop function if exists chef_window_stats(int, timestamptz, uuid) cascade;
-- seed_recipe signatures, oldest first. Each parameter-list change leaves the
-- previous overload behind, so every historical signature stays listed here.
drop function if exists seed_recipe(uuid, text, text, text, text, difficulty, int, int, int, text, jsonb, jsonb, int, int, int) cascade;
drop function if exists seed_recipe(uuid, text, text, text, text, difficulty, int, int, int, text, jsonb, jsonb, int, int, int, jsonb) cascade;
drop function if exists seed_recipe(uuid, text, text, text, text, difficulty, int, int, int, text, jsonb, jsonb, int, int, int, jsonb, recipe_visibility) cascade;
drop function if exists seed_taster_ids() cascade;
drop function if exists seed_chef_ids() cascade;
drop function if exists seed_ratings(uuid, jsonb) cascade;
-- seed_recipe_v2 signatures (supabase/seed_recipes.sql — GENERATED by
-- tool/recipes.dart). Both are `language plpgsql`, so their bodies are opaque to
-- the dependency tracker and `drop table ... cascade` above does NOT take them:
-- without these lines they survive a `db:drop` as functions over dropped tables
-- (B042). Same rule as seed_recipe: every historical signature stays listed,
-- oldest first, because Postgres keys drops by argument list.
drop function if exists seed_recipe_v2(uuid, text, text, text, text, difficulty, int, int, int, recipe_visibility, text, jsonb, jsonb, int, int, int, jsonb) cascade;
-- + p_nutrition jsonb (Phase 28).
drop function if exists seed_recipe_v2(uuid, text, text, text, text, difficulty, int, int, int, recipe_visibility, text, jsonb, jsonb, int, int, int, jsonb, jsonb) cascade;
-- B112 removed the four engagement arguments (p_likes/p_saves/p_views/p_ratings),
-- taking the function to 14 arguments. Every earlier form stays listed: Postgres
-- keys a drop by argument list, so a missed one survives and re-introduces the
-- 42725 ambiguity the whole block exists to prevent.
drop function if exists seed_recipe_v2(uuid, text, text, text, text, difficulty, int, int, int, recipe_visibility, text, jsonb, jsonb, jsonb) cascade;
drop function if exists seed_recipe_v2_ratings(uuid, jsonb) cascade;

-- The RLS matrix's helper (supabase/tests/rls_matrix.sql). It is created inside
-- that file's transaction and dropped before its `rollback`, so it should never
-- exist here — this is the third lock, after the arming check in its body and
-- that drop. It executes an arbitrary string and Postgres exposes every function
-- in `public` as a PostgREST RPC, so a copy that somehow reached a committed
-- schema is exactly the surface Gotcha 3 is about.
drop function if exists rls_matrix_do(text) cascade;

-- The same three-lock arrangement for the per-persona RLS smoke's helper
-- (supabase/sim/4_sim_rls_smoke.sql). Separate name on purpose: both files are
-- created inside a transaction that rolls back, so neither may depend on — or
-- redefine — the other's copy.
drop function if exists sim_rls_do(text) cascade;

-- Enums.
drop type if exists difficulty cascade;
drop type if exists recipe_visibility cascade;
drop type if exists share_permission cascade;
drop type if exists suggestion_status cascade;
drop type if exists chef_tier cascade;
-- Phase 35b.
drop type if exists profile_kind cascade;
drop type if exists entity_kind cascade;
drop type if exists entity_role cascade;
drop type if exists claim_status cascade;
-- Phase 35c.
drop type if exists rights_mode cascade;
drop type if exists image_mode cascade;
