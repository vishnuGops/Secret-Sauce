// OPT-T2's recording client, applied to the last untested repository — the item
// Phase 18 listed as "blocked with the other repositories" back when mocking
// `SupabaseClient` looked like the only way in. It is not: `fake_supabase.dart`
// goes under the HTTP layer, so every call here is asserted as a real request.
//
// All four methods are RPCs whose ranking lives in SQL, so the client's whole
// job is the function name, the params, and the decode. Two of those three have
// broken here before: `kRecipeSelect`'s FK hint (PGRST201 on every recipe query
// at once) and `numeric` arriving as an int (Gotcha 12).
import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_supabase.dart';

({RecordingHttpClient http, SupabaseChefRepository repo}) _repo([
  Object? reply,
]) {
  final http = RecordingHttpClient([(200, jsonEncode(reply ?? <Object>[]))]);
  return (http: http, repo: SupabaseChefRepository(fakeSupabase(http)));
}

/// One `chefs_leaderboard` / `chef_standing` row, as PostgREST sends it.
Map<String, dynamic> _row({
  int rank = 1,
  String id = 'd1',
  String tier = 'head_chef',
  Object score = 10197,
}) => {
  'chef_rank': rank,
  'id': id,
  'display_name': 'The Secret Sauce Kitchen',
  'avatar_url': null,
  'chef_tier': tier,
  'chef_score': score,
  'public_recipe_count': 14,
  'total_likes': 1980,
  'total_saves': 640,
  'total_views': 6035,
  'created_at': '2025-03-14T09:30:00+00:00',
};

/// One `chefs_leaderboard_windowed` row: the board's eleven columns plus the
/// six window ones, flat, the way the RPC returns them.
Map<String, dynamic> _windowRow({
  int rank = 1,
  String id = 'd1',
  Object windowScore = 312,
}) => {
  ..._row(rank: rank, id: id),
  'window_start': '2026-09-17T12:00:00.123456+00:00',
  'window_likes': 40,
  'window_saves': 30,
  'window_views': 60,
  'window_ratings': 2,
  'window_recipes': 1,
  'window_score': windowScore,
};

void main() {
  test('leaderboard passes the page through and decodes the rows', () async {
    final (:http, :repo) = _repo([
      _row(),
      _row(rank: 2, id: 'd2', tier: 'sous_chef', score: 1200),
    ]);

    final rows = await repo.leaderboard(limit: 20, offset: 40);

    final req = http.requests.single;
    expect(req.url.path, endsWith('/rpc/chefs_leaderboard'));
    expect(req.json, {'p_limit': 20, 'p_offset': 40});
    expect(rows.map((r) => r.chefRank), [1, 2]);
    expect(rows.first.chefTier, ChefTier.headChef);
    expect(rows.first.publicRecipeCount, 14);
  });

  test('chef_score survives arriving as an int (Gotcha 12)', () async {
    // Postgres `numeric` serializes without a fraction when it has none, so the
    // same column reaches Dart as `10197` on one row and `10197.4` on the next.
    // A bare `as double` on the first is a runtime type error, and this is the
    // shape that hides until a chef's views happen to be a multiple of five.
    final (:http, :repo) = _repo([
      _row(),
      _row(rank: 2, id: 'd2', score: 10197.4),
    ]);

    final rows = await repo.leaderboard();

    expect(rows.map((r) => r.chefScore), [10197.0, 10197.4]);
  });

  test('standing sends the chef id and decodes the one row', () async {
    final (:http, :repo) = _repo([_row(rank: 7, id: 'd4', tier: 'line_cook')]);

    final standing = await repo.standing('d4');

    final req = http.requests.single;
    expect(req.url.path, endsWith('/rpc/chef_standing'));
    expect(req.json, {'p_chef': 'd4'});
    expect(standing!.chefRank, 7);
    expect(standing.id, 'd4');
  });

  test('standing returns null for a profile that holds no rank', () async {
    // `chef_standing` carries the board's `public_recipe_count > 0` filter, so
    // the private-only chef d6 legitimately returns zero rows. `.single()` would
    // turn that into PGRST116 and the page would render an error instead of the
    // "not ranked yet" state it has (Phase 30).
    final (:http, :repo) = _repo();

    expect(await repo.standing('d6'), isNull);
    expect(http.requests.single.url.path, endsWith('/rpc/chef_standing'));
  });

  test('topRecipes asks for the owner embed with the FK hint', () async {
    final (:http, :repo) = _repo();

    await repo.topRecipes('d1', limit: 5, offset: 20);

    final req = http.requests.single;
    expect(req.url.path, endsWith('/rpc/chef_top_recipes'));
    // `p_offset` is Phase 31's addition — the Popular tab pages, and a page
    // window that never leaves the client is the failure this pins.
    expect(req.json, {'p_chef': 'd1', 'p_limit': 5, 'p_offset': 20});
    // `recipes` and `profiles` are related five ways, so the plain embed form
    // answers PGRST201 (Gotcha 17).
    expect(req.select, contains('owner:profiles!recipes_owner_id_fkey'));
  });

  test('trendingRecipes hits its own RPC, paged and embedded', () async {
    // Same shape, different ranking. Worth its own test rather than a parameter
    // on the one above: the two share a private call site, so a mix-up sends the
    // Trending tab to `chef_top_recipes` and every card still renders — the
    // order is simply the wrong one, which no widget test can see.
    final (:http, :repo) = _repo();

    await repo.trendingRecipes('d1', limit: 20, offset: 40);

    final req = http.requests.single;
    expect(req.url.path, endsWith('/rpc/chef_trending_recipes'));
    expect(req.json, {'p_chef': 'd1', 'p_limit': 20, 'p_offset': 40});
    expect(req.select, contains('owner:profiles!recipes_owner_id_fkey'));
  });

  test('leaderboard rows carry the join date (Phase 33)', () async {
    final (:http, :repo) = _repo([_row()]);

    final rows = await repo.leaderboard();

    expect(rows.single.createdAt, DateTime.utc(2025, 3, 14, 9, 30));
  });

  test('newest re-orders the whole ranked board, totally, and pages it', () async {
    // The `New` sort. `chefs_leaderboard` is called with NO inner limit, so its
    // `dense_rank()` still ranks everyone; the order and the page are applied by
    // PostgREST outside the function. `id` last is what makes the order total —
    // without it two chefs who joined in the same instant can swap between
    // page 1 and page 2 (Gotcha 24).
    final (:http, :repo) = _repo([_row(rank: 3)]);

    final rows = await repo.newest(limit: 25, offset: 50);

    final req = http.requests.single;
    expect(req.url.path, endsWith('/rpc/chefs_leaderboard'));
    expect(req.json, {'p_limit': null, 'p_offset': 0});
    expect(req.order, 'created_at.desc.nullslast,id.asc.nullslast');
    expect(req.param('offset'), '50');
    expect(req.param('limit'), '25');
    // The all-time rank survives the re-order.
    expect(rows.single.chefRank, 3);
  });

  test('windowedLeaderboard sends the window and splits each row', () async {
    final (:http, :repo) = _repo([
      _windowRow(),
      _windowRow(rank: 2, id: 'd2', windowScore: 12.4),
    ]);

    final rows = await repo.windowedLeaderboard(days: 7, limit: 25);

    final req = http.requests.single;
    expect(req.url.path, endsWith('/rpc/chefs_leaderboard_windowed'));
    // No `p_since` on a first page: the server anchors the window at now().
    expect(req.json, {'p_days': 7, 'p_limit': 25, 'p_offset': 0});

    final first = rows.first;
    expect(first.id, 'd1');
    expect(first.standing.chefRank, 1);
    expect(first.standing.totalLikes, 1980); // the all-time half
    expect(first.window.likes, 40); // the window half
    expect(first.window.viewers, 60);
    expect(first.window.newRecipes, 1);
    expect(first.window.score, 312.0); // an int on the wire (Gotcha 12)
    expect(rows.last.window.score, 12.4);
    expect(
      first.window.windowStart,
      DateTime.parse('2026-09-17T12:00:00.123456+00:00'),
    );
  });

  test('windowedLeaderboard pins the boundary with p_since', () async {
    // Every page after the first must send the same instant, or the window
    // moves between requests and `offset` lies.
    final (:http, :repo) = _repo();
    final since = DateTime.utc(2026, 9, 17, 12);

    await repo.windowedLeaderboard(
      days: 30,
      limit: 25,
      offset: 25,
      since: since,
    );

    expect(http.requests.single.json, {
      'p_days': 30,
      'p_limit': 25,
      'p_offset': 25,
      'p_since': '2026-09-17T12:00:00.000Z',
    });
  });

  test('windowStats asks for one chef and decodes the row', () async {
    final row = Map<String, dynamic>.of(_windowRow())
      ..removeWhere((k, _) => !k.startsWith('window_') && k != 'id');
    final (:http, :repo) = _repo([row]);

    final stats = await repo.windowStats('d1', days: 30);

    final req = http.requests.single;
    expect(req.url.path, endsWith('/rpc/chef_window_stats'));
    expect(req.json, {'p_days': 30, 'p_chef': 'd1'});
    expect(stats!.saves, 30);
    expect(stats.gainLabel, '+312');
  });

  test('windowStats is null for a profile that holds no rank', () async {
    // The function carries the board's population filter, so an imported or
    // private-only profile returns zero rows — a state, not an error.
    final (:http, :repo) = _repo();

    expect(await repo.windowStats('d6', days: 7), isNull);
  });

  test('tierCounts returns a complete map, empty tiers included', () async {
    // The hero draws a fixed five-tile row, so the RPC emits a row per tier and
    // the map must carry the zeros rather than leaving callers a null check.
    final (:http, :repo) = _repo([
      for (final tier in ChefTier.values)
        {'tier': tier.wireValue, 'chefs': tier == ChefTier.masterChef ? 0 : 3},
    ]);

    final counts = await repo.tierCounts();

    expect(http.requests.single.url.path, endsWith('/rpc/chefs_tier_counts'));
    expect(counts.keys, containsAll(ChefTier.values));
    expect(counts[ChefTier.masterChef], 0);
    expect(counts.values.reduce((a, b) => a + b), 12);
  });

  test('every method works signed out (Gotcha 9)', () async {
    // The board, the hero and `/chef/:id` are all reachable without an account.
    // Nothing here reads the current user today; a future edit that did would
    // throw `SupabaseRecipeRepository._uid`'s `StateError` and fail right here
    // rather than in production on an anonymous visitor.
    final http = RecordingHttpClient([
      (200, jsonEncode([_row()])),
      (200, jsonEncode([_row()])),
      (200, jsonEncode(<Object>[])),
      (200, jsonEncode(<Object>[])),
      (
        200,
        jsonEncode([
          {'tier': 'home_cook', 'chefs': 1},
        ]),
      ),
      (200, jsonEncode([_row()])),
      (200, jsonEncode([_windowRow()])),
      (200, jsonEncode(<Object>[])),
    ]);
    final client = fakeSupabase(http);
    final repo = SupabaseChefRepository(client);

    expect(client.auth.currentUser, isNull);
    await repo.leaderboard();
    await repo.standing('d1');
    await repo.topRecipes('d1');
    await repo.trendingRecipes('d1');
    await repo.tierCounts();
    await repo.newest();
    await repo.windowedLeaderboard(days: 7);
    await repo.windowStats('d1', days: 30);

    expect(http.requests, hasLength(8));
  });
}
