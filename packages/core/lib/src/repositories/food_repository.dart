import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:core/src/models/food_hit.dart';

/// Read-only access to the food registry (Phase 29).
///
/// Signed-in only by construction on the server: the registry's RLS select
/// policies require `auth.uid()` and `search_foods` is revoked from `anon` —
/// an anonymous call errors rather than returning rows. That is fine, because
/// the only surface that reaches this is the recipe editor, which sits behind
/// the auth redirect.
abstract interface class FoodRepository {
  /// Typeahead matches for [query], ranked exact > prefix > trigram by the
  /// `search_foods` RPC. Empty for a blank query; capped at 25 server-side.
  Future<List<FoodHit>> search(String query, {int limit});

  /// `food.id -> display_name` for [ids], so the editor can label the link
  /// chips of a loaded recipe. Ids that no longer exist are simply absent from
  /// the result — the caller falls back to a generic label.
  Future<Map<String, String>> displayNames(List<String> ids);
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
}
