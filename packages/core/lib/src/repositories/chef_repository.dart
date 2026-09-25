import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:core/src/models/chef_standing.dart';
import 'package:core/src/models/chef_window.dart';
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

  /// The same population and the same rows, **newest member first** — the
  /// board's `New` sort (Phase 33).
  ///
  /// A different ordering, so a different query rather than a tie-break bolted
  /// onto [leaderboard]'s (`0001_init.sql` says exactly that above
  /// `chefs_leaderboard`). It is still `chefs_leaderboard`, called with no inner
  /// limit so `dense_rank()` ranks the whole population, and re-ordered and
  /// paged by PostgREST **outside** the function: `created_at desc, id asc`.
  /// The trailing `id` is what makes that order total, so `offset` cannot show
  /// one chef twice (Gotcha 24). `chefRank` stays the all-time rank.
  Future<List<ChefStanding>> newest({int limit, int offset});

  /// Chefs ranked by what they earned in the last [days] days
  /// (`chefs_leaderboard_windowed`) — the `Momentum` board and the windowed
  /// rails. Every ranked chef is returned, zeros included, quiet ones last.
  ///
  /// **Pass [since] for every page after the first.** A window measured from
  /// `now()` moves between two requests, which makes `offset` lie even over the
  /// RPC's total order; `p_since` overrides [days] and holds the boundary still.
  Future<List<ChefWindowStanding>> windowedLeaderboard({
    required int days,
    int limit,
    int offset,
    DateTime? since,
  });

  /// One chef's window (`chef_window_stats` with `p_chef`) — the momentum line
  /// on `/chef/:id`. Null when the profile holds no rank, for the same reason
  /// [standing] is: the function carries the board's population filter.
  Future<ChefWindowStats?> windowStats(
    String chefId, {
    required int days,
    DateTime? since,
  });

  /// One chef's leaderboard row by id — score, tier, totals, and the `chef_rank`
  /// that `/chef/:id` cannot compute for itself.
  ///
  /// **Null means "this profile holds no rank"**, not "no such profile" and not
  /// an error: `chef_standing` carries the board's own `public_recipe_count > 0`
  /// filter, so a private-only or brand-new account returns zero rows while its
  /// `profiles` row exists and reads perfectly well. The page renders that as a
  /// state; only a missing *profile* is a 404.
  Future<ChefStanding?> standing(String chefId);

  /// A chef's public recipes, ordered by what each contributes to their score
  /// (`chef_top_recipes`) — `/chef/:id`'s **Popular** tab. Private recipes never
  /// appear, including for their own owner: the RPC filters visibility
  /// explicitly.
  ///
  /// Paged since Phase 31. `offset` is only meaningful because the RPC's
  /// `order by` is total (Gotcha 24) — it ends `created_at desc, id`.
  Future<List<Recipe>> topRecipes(String chefId, {int limit, int offset});

  /// The same recipes ranked by the engagement they earned in the **last seven
  /// days** — `likes × 2 + distinct signed-in viewers`, counted from
  /// `recipe_likes` / `recipe_views` rather than the undated lifetime counters
  /// (`chef_trending_recipes`).
  ///
  /// Never empty for a chef who has any public recipe: a week with no
  /// engagement scores every recipe 0 and the RPC falls through to newest-first.
  Future<List<Recipe>> trendingRecipes(String chefId, {int limit, int offset});

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
  Future<List<ChefStanding>> newest({int limit = 50, int offset = 0}) async {
    // `p_limit: null` is `limit null` inside the function — Postgres reads that
    // as LIMIT ALL — so the rank is computed over every chef and the page is cut
    // by the `limit`/`offset` PostgREST applies to the function's result.
    // Cost: the function ranks the whole member population per page, which is
    // a scan of the chefs, not of recipes.
    final rows = await _client
        .rpc('chefs_leaderboard', params: {'p_limit': null, 'p_offset': 0})
        .order('created_at', ascending: false)
        .order('id', ascending: true)
        .range(offset, offset + limit - 1);
    return (rows as List)
        .map((r) => ChefStanding.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<ChefWindowStanding>> windowedLeaderboard({
    required int days,
    int limit = 50,
    int offset = 0,
    DateTime? since,
  }) async {
    final rows = await _client.rpc(
      'chefs_leaderboard_windowed',
      params: {
        'p_days': days,
        'p_limit': limit,
        'p_offset': offset,
        if (since != null) 'p_since': since.toUtc().toIso8601String(),
      },
    );
    return (rows as List)
        .map((r) => ChefWindowStanding.fromRow(r as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<ChefWindowStats?> windowStats(
    String chefId, {
    required int days,
    DateTime? since,
  }) async {
    // `returns table`, so an array either way — zero rows is the legitimate
    // "not a ranked chef" answer, exactly as in [standing].
    final rows = await _client.rpc(
      'chef_window_stats',
      params: {
        'p_days': days,
        if (since != null) 'p_since': since.toUtc().toIso8601String(),
        'p_chef': chefId,
      },
    );
    final list = rows as List;
    if (list.isEmpty) return null;
    return ChefWindowStats.fromJson(list.first as Map<String, dynamic>);
  }

  @override
  Future<ChefStanding?> standing(String chefId) async {
    // The RPC returns at most one row, but it is `returns table`, so PostgREST
    // sends an array either way — `.single()` would turn the legitimate
    // "not a chef" answer into a PGRST116 exception, which is the one thing the
    // caller must be able to tell apart from a failure.
    final rows = await _client.rpc('chef_standing', params: {'p_chef': chefId});
    final list = rows as List;
    if (list.isEmpty) return null;
    return ChefStanding.fromJson(list.first as Map<String, dynamic>);
  }

  @override
  Future<List<Recipe>> topRecipes(
    String chefId, {
    int limit = 3,
    int offset = 0,
  }) {
    return _chefRecipes('chef_top_recipes', chefId, limit, offset);
  }

  @override
  Future<List<Recipe>> trendingRecipes(
    String chefId, {
    int limit = 20,
    int offset = 0,
  }) {
    return _chefRecipes('chef_trending_recipes', chefId, limit, offset);
  }

  /// Both chef-scoped rankings take the same three arguments and return
  /// `setof recipes`, so they share one call site — a second copy of the
  /// `kRecipeSelect` embed is a second place for the FK hint to go missing
  /// (Gotcha 17), and that failure is a `PGRST201` on every card at once.
  Future<List<Recipe>> _chefRecipes(
    String rpc,
    String chefId,
    int limit,
    int offset,
  ) async {
    // `setof recipes`, so the owner embedding rides along exactly as it does on
    // the Discover RPCs — one round-trip, no per-row profile lookup.
    final rows = await _client
        .rpc(
          rpc,
          params: {'p_chef': chefId, 'p_limit': limit, 'p_offset': offset},
        )
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
