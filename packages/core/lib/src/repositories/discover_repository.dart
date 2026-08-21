import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:core/src/models/recipe.dart';
import 'package:core/src/paging.dart';
import 'package:core/src/repositories/recipe_queries.dart';

/// Public discovery: popular, trending, recent, and search.
///
/// Every method is a page: `limit` rows starting at `offset` (OPT-P9). The
/// three RPCs take `p_offset` and order by a **total** key — score, then
/// `created_at`, then `id` — so consecutive pages cannot repeat or skip a row
/// the way an ambiguous order would.
abstract interface class DiscoverRepository {
  Future<List<Recipe>> popular({int limit, int offset});
  Future<List<Recipe>> trending({int limit, int offset});
  Future<List<Recipe>> recent({int limit, int offset});
  Future<List<Recipe>> search(String query, {int limit, int offset});
}

class SupabaseDiscoverRepository implements DiscoverRepository {
  SupabaseDiscoverRepository(this._client);

  final SupabaseClient _client;

  // The RPCs return `setof recipes`, so PostgREST accepts the same owner
  // embedding on them as on the table itself — the chef badge ships with the
  // list instead of costing a lookup per card.
  @override
  Future<List<Recipe>> popular({
    int limit = kRecipePageSize,
    int offset = 0,
  }) async {
    final rows = await _client
        .rpc('recipes_popular', params: {'p_limit': limit, 'p_offset': offset})
        .select(kRecipeSelect);
    return (rows as List)
        .map((r) => Recipe.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<Recipe>> trending({
    int limit = kRecipePageSize,
    int offset = 0,
  }) async {
    final rows = await _client
        .rpc('recipes_trending', params: {'p_limit': limit, 'p_offset': offset})
        .select(kRecipeSelect);
    return (rows as List)
        .map((r) => Recipe.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<Recipe>> recent({
    int limit = kRecipePageSize,
    int offset = 0,
  }) async {
    // `created_at` alone is not a total order — two recipes seeded in the same
    // statement share it — so `id` breaks the tie here exactly as it does inside
    // the three RPCs. `range` is inclusive at both ends.
    final rows = await _client
        .from('recipes')
        .select(kRecipeSelect)
        .eq('visibility', 'public')
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .range(offset, offset + limit - 1);
    return rows.map<Recipe>(Recipe.fromJson).toList();
  }

  @override
  Future<List<Recipe>> search(
    String query, {
    int limit = kRecipePageSize,
    int offset = 0,
  }) async {
    if (query.trim().isEmpty) return const [];
    final rows = await _client
        .rpc(
          'recipes_search',
          params: {'p_query': query, 'p_limit': limit, 'p_offset': offset},
        )
        .select(kRecipeSelect);
    return (rows as List)
        .map((r) => Recipe.fromJson(r as Map<String, dynamic>))
        .toList();
  }
}
