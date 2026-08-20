import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:core/src/models/chef_standing.dart';
import 'package:core/src/models/enums.dart';
import 'package:core/src/models/recipe.dart';
import 'package:core/src/repositories/recipe_queries.dart';

/// The chefs leaderboard and the data behind one chef's expanded card.
///
/// Signed-out safe by construction: nothing here touches the current user, so
/// no call can throw the `StateError` that `SupabaseRecipeRepository._uid`
/// raises when signed out.
abstract interface class ChefRepository {
  /// Chefs ranked by `chef_score`, highest first. Only chefs with at least one
  /// public recipe appear.
  Future<List<ChefStanding>> leaderboard({int limit, int offset});

  /// A chef's public recipes, ordered by what each contributes to their score
  /// (`chef_top_recipes`). Private recipes never appear, including for their
  /// own owner — the RPC filters visibility explicitly.
  Future<List<Recipe>> topRecipes(String chefId, {int limit});

  /// How many chefs occupy the board — the denominator in "Rank 2 of 148".
  /// Matches the RPC's own filter: a profile with no public recipe is not a
  /// chef for ranking purposes.
  Future<int> chefCount();

  /// How many chefs sit on each rung — the five tiles across the chefs hero.
  ///
  /// Same population as [chefCount]: only profiles with at least one public
  /// recipe, so the five values sum to it. Every tier is present in the result,
  /// including the empty ones, so the hero renders a stable five-tile row
  /// instead of a row whose width depends on the data.
  Future<Map<ChefTier, int>> tierCounts();
}

class SupabaseChefRepository implements ChefRepository {
  SupabaseChefRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<ChefStanding>> leaderboard({int limit = 50, int offset = 0}) async {
    final rows = await _client.rpc(
      'chefs_leaderboard',
      params: {'p_limit': limit, 'p_offset': offset},
    );
    return (rows as List)
        .map((r) => ChefStanding.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<Recipe>> topRecipes(String chefId, {int limit = 3}) async {
    // `setof recipes`, so the owner embedding rides along exactly as it does on
    // the Discover RPCs — one round-trip, no per-row profile lookup.
    final rows = await _client
        .rpc('chef_top_recipes', params: {'p_chef': chefId, 'p_limit': limit})
        .select(kRecipeSelect);
    return (rows as List)
        .map((r) => Recipe.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<int> chefCount() async {
    // `count` respects the filters but ignores `limit`, so the `limit(1)` keeps
    // the body at one row while the header still carries the full total —
    // otherwise this would download every chef id to count them.
    final res = await _client
        .from('profiles')
        .select('id')
        .gt('public_recipe_count', 0)
        .limit(1)
        .count(CountOption.exact);
    return res.count;
  }

  @override
  Future<Map<ChefTier, int>> tierCounts() async {
    // Five exact counts rather than one `group by`: PostgREST cannot aggregate,
    // and the alternative — selecting every chef's tier and tallying on the
    // client — downloads a row per chef and grows without bound. Each of these
    // is the same bounded shape as `chefCount` (`limit(1)` body, exact count in
    // the header), and they go out together.
    final entries = await Future.wait(
      ChefTier.values.map((tier) async {
        final res = await _client
            .from('profiles')
            .select('id')
            .gt('public_recipe_count', 0)
            .eq('chef_tier', tier.wireValue)
            .limit(1)
            .count(CountOption.exact);
        return MapEntry(tier, res.count);
      }),
    );
    return Map.fromEntries(entries);
  }
}
