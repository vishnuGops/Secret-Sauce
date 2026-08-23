// OPT-T2, second slice: the four Discover reads. Their contract is almost
// entirely *what gets sent* — three of them are RPCs whose ranking lives in
// SQL, so the client's whole job is passing the page through and asking for the
// owner embed.
import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_supabase.dart';

({RecordingHttpClient http, SupabaseDiscoverRepository repo}) _repo() {
  final http = RecordingHttpClient([(200, jsonEncode(<Object>[]))]);
  return (http: http, repo: SupabaseDiscoverRepository(fakeSupabase(http)));
}

void main() {
  test(
    'popular and trending pass the page to the RPC and ask for the embed',
    () async {
      for (final tab in ['popular', 'trending']) {
        final (:http, :repo) = _repo();

        if (tab == 'popular') {
          await repo.popular(limit: 20, offset: 40);
        } else {
          await repo.trending(limit: 20, offset: 40);
        }

        final req = http.requests.single;
        expect(req.url.path, endsWith('/rpc/recipes_$tab'));
        expect(req.json, {'p_limit': 20, 'p_offset': 40});
        // `setof recipes`, so the owner embedding rides along — the chef badge
        // ships with the list instead of costing a lookup per card.
        expect(req.select, contains('owner:profiles!recipes_owner_id_fkey'));
      }
    },
  );

  test('search sends the query and the page', () async {
    final (:http, :repo) = _repo();

    await repo.search('chicken', limit: 20, offset: 20);

    final req = http.requests.single;
    expect(req.url.path, endsWith('/rpc/recipes_search'));
    expect(req.json, {'p_query': 'chicken', 'p_limit': 20, 'p_offset': 20});
  });

  test('an empty query never reaches the network', () async {
    // The repository short-circuits and the provider's debounce matches it
    // (OPT-P8) — clearing the field must not cost a request.
    final (:http, :repo) = _repo();

    expect(await repo.search('   '), isEmpty);
    expect(http.requests, isEmpty);
  });

  test('each shelf calls its own RPC, with the embed (Phase 26)', () async {
    // The three shelves differ only in which ranking the server applies, so
    // the one thing a client test can get wrong is calling the wrong function —
    // and every shelf would still render recipes if it did.
    for (final (name, call)
        in <(String, Future<void> Function(SupabaseDiscoverRepository))>[
          ('recipes_quick', (r) => r.quick(limit: 12)),
          ('recipes_projects', (r) => r.projects(limit: 12)),
          ('recipes_most_forked', (r) => r.mostForked(limit: 12)),
        ]) {
      final (:http, :repo) = _repo();

      await call(repo);

      final req = http.requests.single;
      expect(req.url.path, endsWith('/rpc/$name'));
      expect(req.json, {'p_limit': 12, 'p_offset': 0});
      expect(req.select, contains('owner:profiles!recipes_owner_id_fkey'));
    }
  });

  test('publicCount asks for a count and no rows', () async {
    final http = RecordingHttpClient(
      [(200, jsonEncode(<Object>[]))],
      headers: const {'content-range': '*/1684'},
    );
    final repo = SupabaseDiscoverRepository(fakeSupabase(http));

    expect(await repo.publicCount(), 1684);

    final req = http.requests.single;
    // HEAD, not GET: the masthead wants the number in the `Content-Range`
    // header, and downloading every public recipe to call `.length` on it is
    // the shape this exists to avoid.
    expect(req.method, 'HEAD');
    expect(req.url.path, endsWith('/rest/v1/recipes'));
    expect(req.param('visibility'), 'eq.public');
    expect(req.headers['Prefer'], contains('count=exact'));
  });

  test('recent reads the table in a total order, one page at a time', () async {
    final (:http, :repo) = _repo();

    await repo.recent(limit: 20, offset: 20);

    final req = http.requests.single;
    expect(req.url.path, endsWith('/rest/v1/recipes'));
    expect(req.param('visibility'), 'eq.public');
    // `created_at` alone is not total — two recipes seeded in one statement
    // share it, and then page 2 can repeat one of page 1's rows.
    expect(req.order, 'created_at.desc.nullslast,id.desc.nullslast');
    expect(req.param('limit'), '20');
    expect(req.param('offset'), '20');
  });
}
