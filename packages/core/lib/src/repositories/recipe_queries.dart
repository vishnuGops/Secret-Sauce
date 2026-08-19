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
const kRecipeSelect =
    '*,owner:profiles!recipes_owner_id_fkey(id,display_name,avatar_url,chef_tier)';
