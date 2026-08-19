import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:core/src/models/chef_standing.dart';

/// The chefs leaderboard.
///
/// Signed-out safe by construction: nothing here touches the current user, so
/// no call can throw the `StateError` that `SupabaseRecipeRepository._uid`
/// raises when signed out.
abstract interface class ChefRepository {
  /// Chefs ranked by `chef_score`, highest first. Only chefs with at least one
  /// public recipe appear.
  Future<List<ChefStanding>> leaderboard({int limit, int offset});
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
}
