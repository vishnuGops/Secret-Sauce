// `profile_repository.dart` had no test file at all until 32d3, which is how
// B083 survived: the ranking that OPT-A5 exists for was applied to a window the
// server had already truncated, so at sim scale an exact match could not be
// promoted because it never arrived.
//
// Same harness as `recipe_repository_test.dart` — a recording `http.BaseClient`
// under a real `SupabaseClient`, so these assert the request the repository
// sends and the decode of a canned reply, never that Postgres agrees.
import 'dart:convert';

import 'package:core/core.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_supabase.dart';

Map<String, dynamic> _profileRow({required String id, required String name}) =>
    {
      'id': id,
      'display_name': name,
      'avatar_url': null,
      'bio': null,
      'chef_score': 0,
      'chef_tier': 'home_cook',
      'public_recipe_count': 0,
      'total_likes': 0,
      'total_saves': 0,
      'total_views': 0,
    };

({
  RecordingHttpClient http,
  SupabaseClient client,
  SupabaseProfileRepository repo,
})
_repo(List<(int, String)> responses) {
  final http = RecordingHttpClient(responses);
  final client = fakeSupabase(http);
  return (http: http, client: client, repo: SupabaseProfileRepository(client));
}

void main() {
  group('searchByName', () {
    test('over-fetches so the ranking has something to rank (B083)', () async {
      final (:http, :client, :repo) = _repo([(200, jsonEncode(<Object>[]))]);

      await repo.searchByName('dara', limit: 8);

      final req = http.requests.single;
      expect(req.param('display_name'), 'ilike.%dara%');
      // The window, not the page. With `limit(8)` the server picks the first
      // eight alphabetically and the client ranks those — so an exact "Dara"
      // behind eight "Darabont"s is unreachable however good the ranking is.
      expect(req.param('limit'), '24');
    });

    test('the over-fetch is capped', () async {
      final (:http, :client, :repo) = _repo([(200, jsonEncode(<Object>[]))]);

      await repo.searchByName('a', limit: 20);

      expect(
        http.requests.single.param('limit'),
        '$kProfileSearchMaxRows',
        reason: 'a one-letter query must not drag the whole table over',
      );
    });

    test('never asks for fewer rows than the caller wants', () async {
      final (:http, :client, :repo) = _repo([(200, jsonEncode(<Object>[]))]);

      await repo.searchByName('a', limit: 100);

      expect(http.requests.single.param('limit'), '100');
    });

    test('exact beats prefix beats contains, then name, then id', () async {
      // Deliberately handed back in the alphabetical order the server would
      // produce, which is the order the ranking has to overturn.
      final (:http, :client, :repo) = _repo([
        (
          200,
          jsonEncode([
            _profileRow(id: 'b', name: 'Darabont Cook'),
            _profileRow(id: 'a', name: 'Dara'),
            _profileRow(id: 'c', name: 'Amara Dara-Smith'),
          ]),
        ),
      ]);

      final found = await repo.searchByName('dara');

      expect(found.map((p) => p.id), ['a', 'b', 'c']);
    });

    test('ties on name break by id, so a page is stable', () async {
      final (:http, :client, :repo) = _repo([
        (
          200,
          jsonEncode([
            _profileRow(id: 'z', name: 'Dara'),
            _profileRow(id: 'a', name: 'Dara'),
          ]),
        ),
      ]);

      final found = await repo.searchByName('dara');

      // Two people really do share a display name — that is why OPT-A5 asks
      // which one — so the order between them has to come from somewhere fixed,
      // or the row under the reader's finger moves between keystrokes.
      expect(found.map((p) => p.id), ['a', 'z']);
    });

    test('cuts the ranked list back to the page size', () async {
      final (:http, :client, :repo) = _repo([
        (
          200,
          jsonEncode([
            for (var i = 0; i < 9; i++) _profileRow(id: 'p$i', name: 'Dara $i'),
          ]),
        ),
      ]);

      final found = await repo.searchByName('dara', limit: 3);

      expect(found, hasLength(3));
    });

    test('escapes LIKE wildcards in the query', () async {
      final (:http, :client, :repo) = _repo([(200, jsonEncode(<Object>[]))]);

      await repo.searchByName('100%_a\\b');

      // `%` matches anything and `_` matches any single character, so an
      // unescaped name would quietly match far more than was typed. Backslash is
      // the escape character, so it is doubled first.
      expect(
        http.requests.single.param('display_name'),
        r'ilike.%100\%\_a\\b%',
      );
    });

    test('an empty query never reaches the network', () async {
      final (:http, :client, :repo) = _repo([]);

      expect(await repo.searchByName('   '), isEmpty);
      expect(http.requests, isEmpty);
    });
  });

  group('updateMine', () {
    test('sends only the three columns a client may write', () async {
      final (:http, :client, :repo) = _repo([
        (200, jsonEncode(_profileRow(id: 'u1', name: 'Amara'))),
      ]);

      await repo.updateMine(
        const Profile(
          id: 'u1',
          displayName: 'Amara',
          bio: 'Sunday cook',
          chefScore: 4200,
          chefTier: ChefTier.headChef,
          publicRecipeCount: 12,
        ),
      );

      final req = http.requests.single;
      expect(req.json.keys.toSet(), {'display_name', 'avatar_url', 'bio'});
      // The documented invariant with no pin until now: `chef_score`,
      // `chef_tier`, `public_recipe_count` and the three `total_*` columns are
      // trigger-maintained aggregates. The column grants refuse them (B050), so
      // sending one turns every profile edit into a `42501` — a save that fails
      // for a field the screen does not even show. The model carries the first
      // three (the chef card reads them) and not the totals, so this asserts
      // the payload rather than the model.
      for (final owned in [
        'chef_score',
        'chef_tier',
        'public_recipe_count',
        'total_likes',
        'total_saves',
        'total_views',
      ]) {
        expect(req.json.containsKey(owned), isFalse, reason: owned);
      }
      expect(req.param('id'), 'eq.u1');
    });
  });
}
