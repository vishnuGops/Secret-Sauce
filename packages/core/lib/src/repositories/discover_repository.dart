import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:core/src/models/recipe.dart';
import 'package:core/src/paging.dart';
import 'package:core/src/repositories/recipe_queries.dart';

/// Discover's six category tiles (Phase 36c, the owner's Q6), in display order.
///
/// `recipes.category` is **free text**, and the population does not agree with
/// itself: on the local stack `Dessert` has 3,129 public rows, `Main Course`
/// 2,078, `Dinner` 909, `Main` 395 — the curated recipes say `Main`, the corpus
/// says whatever its publisher said. A tile is therefore a **group** of raw
/// values, matched exactly ([DiscoverRepository.byCategories] sends them as one
/// `in.(…)` filter), and [rawValues] is the whole mapping — there is no fuzzy
/// match anywhere else. A spelling that is not listed here is simply not on a
/// tile; add it to the right group rather than lower-casing on the server.
///
/// Pure data on purpose: the tile's colour is `design_system`'s business
/// (`AppPalette.category`, keyed by the first raw value) and the URL slug is
/// [slug] — `/discover?category=mains`.
enum DiscoverCategory {
  mains('Mains', ['Main', 'Main Course', 'Mains', 'Dinner', 'Lunch', 'Entree']),
  breakfast('Breakfast', ['Breakfast', 'Brunch']),
  desserts('Desserts', ['Dessert', 'Desserts', 'Baking']),
  starters('Starters', [
    'Appetizer',
    'Appetizers',
    'Snack',
    'Snacks',
    'Side Dish',
    'Side',
  ]),
  salads('Salads', ['Salad', 'Salads']),
  drinks('Drinks', ['Drink', 'Drinks', 'Beverage', 'Cocktail']);

  const DiscoverCategory(this.label, this.rawValues);

  /// What the tile says: `Mains`.
  final String label;

  /// Every raw `recipes.category` value the tile stands for, exactly as stored.
  /// The first is the canonical spelling — the one the curated recipes use.
  final List<String> rawValues;

  /// The URL form: `mains` in `/discover?category=mains`.
  String get slug => name;

  /// The tile a URL names, or null for a missing or unknown slug — which the
  /// screen treats as "no filter" rather than an error, so a stale or mistyped
  /// link still lands on a working Discover.
  static DiscoverCategory? fromSlug(String? slug) {
    if (slug == null) return null;
    final key = slug.trim().toLowerCase();
    for (final c in values) {
      if (c.slug == key) return c;
    }
    return null;
  }
}

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

  /// Public recipes whose `category` is any of [categories] — one
  /// [DiscoverCategory] tile's [DiscoverCategory.rawValues] — newest first.
  ///
  /// The same read as [recent] with one `in.(…)` filter added, so it carries
  /// the same **total** order (`created_at desc, id desc` — Gotcha 24). An
  /// empty list never reaches the network: `in.()` matches nothing anyway.
  Future<List<Recipe>> byCategories(
    List<String> categories, {
    int limit,
    int offset,
  });
  Future<List<Recipe>> search(String query, {int limit, int offset});

  /// **01 · UNDER 30** — public recipes that take 1–30 minutes end to end,
  /// best-rated first (the same Bayesian prior [popular] uses).
  ///
  /// The floor is not a typo: a recipe with no timings has an *unknown*
  /// duration, and a shelf that promises half an hour cannot be half full of
  /// cards that render `—`.
  Future<List<Recipe>> quick({int limit, int offset});

  /// **02 · WEEKEND PROJECTS** — two hours or more, or the top difficulty rung,
  /// ranked by **saves**.
  ///
  /// Saves rather than rating on purpose: a save is "I will cook this when I
  /// have a day", which is the decision this shelf serves. A rating comes from
  /// whoever already got to the end.
  Future<List<Recipe>> projects({int limit, int offset});

  /// **03 · MOST FORKED** — public recipes ranked by how many *public* recipes
  /// descend from them.
  ///
  /// Public-only is what makes the rank the same number for every caller: these
  /// RPCs are invoker-rights, so an unqualified count would be RLS-filtered and
  /// a private fork would count for its owner alone.
  Future<List<Recipe>> mostForked({int limit, int offset});

  /// **The corpus** — public recipes captured from the web (Phase 35c).
  ///
  /// The one surface that shows imported content. Every shelf above filters it
  /// out, because it arrives with every counter at zero and a ranked list of
  /// 21,000 identical scores is not a ranking — so this orders by
  /// `quality_score`, which measures how complete the *capture* is and is not
  /// engagement by another name.
  ///
  /// `blocked` rows are excluded by the RPC, so a takedown is honoured on read
  /// as well as on import.
  Future<List<Recipe>> corpus({int limit, int offset, String? cuisine});

  /// How many imported recipes exist — the corpus page's one statistic, and
  /// the honest way to say how big this collection is.
  Future<int> corpusCount();

  /// How many public recipes exist — the masthead's one statistic.
  ///
  /// A `HEAD` request with an exact count: no rows cross the wire.
  Future<int> publicCount();
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
  Future<List<Recipe>> byCategories(
    List<String> categories, {
    int limit = kRecipePageSize,
    int offset = 0,
  }) async {
    if (categories.isEmpty) return const [];
    // [recent] plus the filter — including its `id` tie-break, without which a
    // page boundary between two rows seeded in one statement repeats or skips
    // one of them (Gotcha 24).
    final rows = await _client
        .from('recipes')
        .select(kRecipeSelect)
        .eq('visibility', 'public')
        .inFilter('category', categories)
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .range(offset, offset + limit - 1);
    return rows.map<Recipe>(Recipe.fromJson).toList();
  }

  // The three shelves (Phase 26). Same shape as the two RPC readers above —
  // they differ only in which ranking the server applies, which is the whole
  // point of putting each one in SQL rather than sorting on the client.
  @override
  Future<List<Recipe>> quick({int limit = kRecipePageSize, int offset = 0}) =>
      _shelf('recipes_quick', limit: limit, offset: offset);

  @override
  Future<List<Recipe>> projects({
    int limit = kRecipePageSize,
    int offset = 0,
  }) => _shelf('recipes_projects', limit: limit, offset: offset);

  @override
  Future<List<Recipe>> mostForked({
    int limit = kRecipePageSize,
    int offset = 0,
  }) => _shelf('recipes_most_forked', limit: limit, offset: offset);

  Future<List<Recipe>> _shelf(
    String rpc, {
    required int limit,
    required int offset,
  }) async {
    final rows = await _client
        .rpc(rpc, params: {'p_limit': limit, 'p_offset': offset})
        .select(kRecipeSelect);
    return (rows as List)
        .map((r) => Recipe.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<int> publicCount() => _client
      .from('recipes')
      .count(CountOption.exact)
      .eq('visibility', 'public');

  @override
  Future<List<Recipe>> corpus({
    int limit = kRecipePageSize,
    int offset = 0,
    String? cuisine,
  }) async {
    final rows = await _client
        .rpc(
          'recipes_corpus',
          params: {
            'p_limit': limit,
            'p_offset': offset,
            // Named explicitly rather than omitted: the RPC has three
            // parameters and PostgREST matches an overload by the names it is
            // given, so leaving it out would look for a two-argument
            // `recipes_corpus` that does not exist.
            'p_cuisine': cuisine,
          },
        )
        .select(kRecipeSelect);
    return (rows as List)
        .map((r) => Recipe.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<int> corpusCount() => _client
      .from('recipes')
      .count(CountOption.exact)
      .eq('visibility', 'public')
      .eq('is_imported', true);

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
