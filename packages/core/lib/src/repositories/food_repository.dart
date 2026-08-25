import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:core/src/models/food_hit.dart';
import 'package:core/src/models/ingredient_group.dart';
import 'package:core/src/models/nutrition_estimate.dart';
import 'package:core/src/repositories/content_payload.dart';

/// Read-only access to the food registry (Phase 29).
///
/// Signed-in only by construction on the server: the registry's RLS select
/// policies require `auth.uid()` and all four RPCs here are revoked from
/// `anon` — an anonymous call errors rather than returning rows. That is
/// fine, because the only surface that reaches this is the recipe editor,
/// which sits behind the auth redirect.
abstract interface class FoodRepository {
  /// Typeahead matches for [query], ranked exact > prefix > trigram by the
  /// `search_foods` RPC. Empty for a blank query; capped at 25 server-side.
  Future<List<FoodHit>> search(String query, {int limit});

  /// `food.id -> display_name` for [ids], so the editor can label the link
  /// chips of a loaded recipe. Ids that no longer exist are simply absent from
  /// the result — the caller falls back to a generic label.
  Future<Map<String, String>> displayNames(List<String> ids);

  /// The `estimate_nutrition` RPC (Phase 29c): the per-serving label the
  /// current draft would get, plus counted/total/unmatched for the Auto
  /// pane's honesty lists. Preview only — `save_recipe` recomputes through
  /// the same SQL, so these numbers are never stored from here.
  Future<NutritionEstimate> estimate({
    required List<IngredientGroup> ingredientGroups,
    required int servings,
  });

  /// The `match_foods` RPC: top-3 link candidates per name, keyed by the
  /// name as given — the review flow for a recipe written before links
  /// existed. `[]` for a name with no candidates; empty input makes no
  /// request.
  Future<Map<String, List<FoodHit>>> matchFoods(List<String> names);
}

class SupabaseFoodRepository implements FoodRepository {
  SupabaseFoodRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<FoodHit>> search(String query, {int limit = 10}) async {
    final rows = await _client.rpc(
      'search_foods',
      params: {'p_query': query, 'p_limit': limit},
    );
    return (rows as List)
        .map((r) => FoodHit.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Map<String, String>> displayNames(List<String> ids) async {
    // Nothing linked — skip the round trip rather than sending `in.()`.
    if (ids.isEmpty) return const {};
    final rows = await _client
        .from('food')
        .select('id, display_name')
        .inFilter('id', ids);
    return {
      for (final row in rows)
        row['id'] as String: row['display_name'] as String,
    };
  }

  @override
  Future<NutritionEstimate> estimate({
    required List<IngredientGroup> ingredientGroups,
    required int servings,
  }) async {
    // The SAME encoder the save path uses (content_payload.dart) — the whole
    // point of a pure estimator is that it sees the trees the save will send.
    final result = await _client.rpc(
      'estimate_nutrition',
      params: {
        'p_ingredient_groups': ingredientGroupsPayload(ingredientGroups),
        'p_servings': servings,
      },
    );
    return NutritionEstimate.fromJson(result as Map<String, dynamic>);
  }

  @override
  Future<Map<String, List<FoodHit>>> matchFoods(List<String> names) async {
    if (names.isEmpty) return const {};
    final result = await _client.rpc('match_foods', params: {'p_names': names});
    return {
      for (final entry in (result as Map<String, dynamic>).entries)
        entry.key: [
          for (final hit in entry.value as List)
            FoodHit.fromJson(hit as Map<String, dynamic>),
        ],
    };
  }
}
