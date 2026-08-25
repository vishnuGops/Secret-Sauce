// Phase 29b: request assertions for the food registry reads, the OPT-T2 way.
// `search` pins the RPC name and body the editor's typeahead depends on;
// `displayNames` pins the two-column select and the empty-input short-circuit
// (no request at all — the round trip is the thing being saved).
import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_supabase.dart';

void main() {
  group('search', () {
    test('is one search_foods RPC carrying the query and the limit', () async {
      final http = RecordingHttpClient([
        (
          200,
          jsonEncode([
            {'id': 'all-purpose-flour', 'display_name': 'All-purpose flour'},
            {'id': 'bread-flour', 'display_name': 'Bread flour'},
          ]),
        ),
      ]);
      final repo = SupabaseFoodRepository(fakeSupabase(http));

      final hits = await repo.search('flou', limit: 8);

      expect(http.requests, hasLength(1));
      final req = http.requests.single;
      expect(req.url.path, endsWith('/rpc/search_foods'));
      expect(req.json, {'p_query': 'flou', 'p_limit': 8});

      expect(hits, hasLength(2));
      expect(hits.first.id, 'all-purpose-flour');
      expect(hits.first.displayName, 'All-purpose flour');
    });

    test('defaults the limit to 10', () async {
      final http = RecordingHttpClient([(200, jsonEncode(<Object>[]))]);
      final repo = SupabaseFoodRepository(fakeSupabase(http));

      await repo.search('flour');

      expect(http.requests.single.json['p_limit'], 10);
    });
  });

  group('displayNames', () {
    test('selects id + display_name filtered to the asked ids', () async {
      final http = RecordingHttpClient([
        (
          200,
          jsonEncode([
            {'id': 'butter', 'display_name': 'Butter'},
            {'id': 'garlic', 'display_name': 'Garlic'},
          ]),
        ),
      ]);
      final repo = SupabaseFoodRepository(fakeSupabase(http));

      final names = await repo.displayNames(['butter', 'garlic', 'gone']);

      expect(http.requests, hasLength(1));
      final req = http.requests.single;
      expect(req.url.path, endsWith('/food'));
      expect(req.select, 'id,display_name');
      expect(req.param('id'), 'in.("butter","garlic","gone")');

      // A retired id is simply absent — the editor falls back to 'Linked'.
      expect(names, {'butter': 'Butter', 'garlic': 'Garlic'});
    });

    test('empty input makes no request', () async {
      final http = RecordingHttpClient([]);
      final repo = SupabaseFoodRepository(fakeSupabase(http));

      expect(await repo.displayNames([]), isEmpty);
      expect(http.requests, isEmpty);
    });
  });
}
