import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:core/src/models/recipe.dart';
import 'package:core/src/repositories/recipe_queries.dart';

/// Public discovery: popular, trending, recent, and search.
abstract interface class DiscoverRepository {
  Future<List<Recipe>> popular({int limit});
  Future<List<Recipe>> trending({int limit});
  Future<List<Recipe>> recent({int limit});
  Future<List<Recipe>> search(String query, {int limit});
}

class SupabaseDiscoverRepository implements DiscoverRepository {
  SupabaseDiscoverRepository(this._client);

  final SupabaseClient _client;

  // The RPCs return `setof recipes`, so PostgREST accepts the same owner
  // embedding on them as on the table itself — the chef badge ships with the
  // list instead of costing a lookup per card.
  @override
  Future<List<Recipe>> popular({int limit = 20}) async {
    final rows = await _client
        .rpc('recipes_popular', params: {'p_limit': limit})
        .select(kRecipeSelect);
    return (rows as List).map((r) => Recipe.fromJson(r as Map<String, dynamic>)).toList();
  }

  @override
  Future<List<Recipe>> trending({int limit = 20}) async {
    final rows = await _client
        .rpc('recipes_trending', params: {'p_limit': limit})
        .select(kRecipeSelect);
    return (rows as List).map((r) => Recipe.fromJson(r as Map<String, dynamic>)).toList();
  }

  @override
  Future<List<Recipe>> recent({int limit = 20}) async {
    final rows = await _client
        .from('recipes')
        .select(kRecipeSelect)
        .eq('visibility', 'public')
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map<Recipe>(Recipe.fromJson).toList();
  }

  @override
  Future<List<Recipe>> search(String query, {int limit = 30}) async {
    if (query.trim().isEmpty) return const [];
    final rows = await _client
        .rpc('recipes_search', params: {'p_query': query, 'p_limit': limit})
        .select(kRecipeSelect);
    return (rows as List).map((r) => Recipe.fromJson(r as Map<String, dynamic>)).toList();
  }
}
