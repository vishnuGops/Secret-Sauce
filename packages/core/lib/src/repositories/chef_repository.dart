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

  /// How many chefs sit on each rung — the five tiles across the chefs hero.
  ///
  /// Only profiles with at least one public recipe, matching the leaderboard's
  /// own filter: a profile with no public recipe is not a chef for ranking
  /// purposes. Every tier is present in the result, including the empty ones,
  /// so the hero renders a stable five-tile row instead of a row whose width
  /// depends on the data.
  ///
  /// The board's denominator — the "of 148" in "Rank 2 of 148" — is the **sum**
  /// of these, which is why there is no longer a separate `chefCount()`:
  /// it was a sixth request for a number this one already contains (OPT-P10).
  Future<Map<ChefTier, int>> tierCounts();
}

class SupabaseChefRepository implements ChefRepository {
  SupabaseChefRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<ChefStanding>> leaderboard({
    int limit = 50,
    int offset = 0,
  }) async {
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
  Future<Map<ChefTier, int>> tierCounts() async {
    // One `chefs_tier_counts()` call (OPT-P10). This used to be five exact-count
    // requests — PostgREST cannot express `group by`, but an RPC can, and the
    // hero's total is now the sum of these rather than a sixth request.
    // The RPC returns a row per tier even when the tier is empty, so the map is
    // always complete and callers can index it without a null check.
    final rows = await _client.rpc('chefs_tier_counts');
    return {
      for (final row in rows as List)
        ChefTier.fromWire((row as Map<String, dynamic>)['tier'] as String):
            (row['chefs'] as num).toInt(),
    };
  }
}
