/// PostgREST `select()` fragments shared by the recipe-returning repositories.
///
/// Internal to `packages/core` — deliberately not exported from `core.dart`.
library;

/// Every recipe column plus the owning chef's badge data, so a list of cards
/// renders tiers with no extra round-trip.
///
/// The `!recipes_owner_id_fkey` hint is **mandatory**, not decoration. `recipes`
/// and `profiles` are related five ways — `recipes.owner_id`, plus many-to-many
/// through `recipe_likes`, `recipe_ratings`, `recipe_saves`, and
/// `recipe_shares` — so a bare `owner:profiles(...)` is rejected outright:
///
///     PGRST201: Could not embed because more than one relationship was found
///               for 'recipes' and 'profiles'
///
/// Adding any further FK between the two tables does not change this; removing
/// the hint breaks every recipe query at once. Verified against the local stack
/// on the `recipes` table, on all three Discover RPCs (`recipes_popular` /
/// `_trending` / `_search`, which return `setof recipes`), and nested inside a
/// `recipe_shares` select.
/// Columns are listed explicitly rather than `*` because `recipes.search_tsv`
/// (OPT-P1) is a ~450-byte `tsvector` the client never reads — `*` shipped
/// ~13 KB of dead weight on every 30-card Discover page. PostgREST has no
/// "everything except" syntax, so the list is the only way to drop it.
///
/// MAINTENANCE: a new column on `recipes` must be added here or it will not
/// reach the model — the same obligation as the column grant list in
/// `0001_init.sql`. Server-owned columns still belong here (the client *reads*
/// counters, it just may not write them); only genuinely internal ones like
/// `search_tsv` stay out.
const _kRecipeColumns = 'id,owner_id,title,description,cover_image_url,cuisine,'
    'category,difficulty,prep_minutes,cook_minutes,servings,visibility,'
    'attribution,forked_from_recipe_id,forked_from_version_id,'
    'current_version_id,like_count,save_count,view_count,created_at,updated_at,'
    'rating_sum,rating_count,rating_avg';

const kRecipeSelect = '$_kRecipeColumns,'
    'owner:profiles!recipes_owner_id_fkey(id,display_name,avatar_url,chef_tier)';
