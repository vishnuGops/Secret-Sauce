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

  // Phase 29c. The estimate is preview-only — save_recipe recomputes — so the
  // thing worth pinning is that the RPC body carries the SAME tree encoding
  // the save path sends (content_payload.dart is shared by both).
  group('estimate', () {
    const groups = [
      IngredientGroup(
        id: 'g1',
        recipeId: 'r1',
        name: 'Main',
        ingredients: [
          Ingredient(
            id: 'i1',
            groupId: 'g1',
            quantity: 200,
            unit: 'g',
            name: 'flour',
            isOptional: false,
            sortOrder: 0,
            foodId: 'all-purpose-flour',
          ),
          Ingredient(
            id: 'i2',
            groupId: 'g1',
            name: 'a pinch of patience',
            isOptional: true,
            sortOrder: 1,
          ),
        ],
      ),
    ];

    test(
      'is one estimate_nutrition RPC carrying the save-path trees',
      () async {
        final http = RecordingHttpClient([
          (
            200,
            jsonEncode({
              'label': {'calories': 364, 'protein_g': 10.3, 'source': 'auto'},
              'counted': 1,
              'total': 2,
              'unmatched': ['a pinch of patience'],
            }),
          ),
        ]);
        final repo = SupabaseFoodRepository(fakeSupabase(http));

        final estimate = await repo.estimate(
          ingredientGroups: groups,
          servings: 4,
        );

        expect(http.requests, hasLength(1));
        final req = http.requests.single;
        expect(req.url.path, endsWith('/rpc/estimate_nutrition'));
        expect(req.json, {
          'p_ingredient_groups': [
            {
              'name': 'Main',
              'ingredients': [
                {
                  'quantity': 200.0,
                  'unit': 'g',
                  'name': 'flour',
                  'note': null,
                  'is_optional': false,
                  'food_id': 'all-purpose-flour',
                },
                {
                  'quantity': null,
                  'unit': null,
                  'name': 'a pinch of patience',
                  'note': null,
                  'is_optional': true,
                  'food_id': null,
                },
              ],
            },
          ],
          'p_servings': 4,
        });

        expect(estimate.label?.calories, 364.0);
        expect(estimate.label?.isEstimated, isTrue);
        expect(estimate.counted, 1);
        expect(estimate.total, 2);
        expect(estimate.unmatched, ['a pinch of patience']);
      },
    );

    test('a null label decodes as "nothing counted"', () async {
      final http = RecordingHttpClient([
        (
          200,
          jsonEncode({
            'label': null,
            'counted': 0,
            'total': 1,
            'unmatched': ['salt'],
          }),
        ),
      ]);
      final repo = SupabaseFoodRepository(fakeSupabase(http));

      final estimate = await repo.estimate(
        ingredientGroups: groups,
        servings: 1,
      );
      expect(estimate.hasLabel, isFalse);
    });
  });

  group('matchFoods', () {
    test('is one match_foods RPC; candidates decode per name', () async {
      final http = RecordingHttpClient([
        (
          200,
          jsonEncode({
            'plain flour': [
              {'id': 'all-purpose-flour', 'display_name': 'All-purpose flour'},
              {'id': 'bread-flour', 'display_name': 'Bread flour'},
            ],
            'mystery spice': <Object>[],
          }),
        ),
      ]);
      final repo = SupabaseFoodRepository(fakeSupabase(http));

      final matches = await repo.matchFoods(['plain flour', 'mystery spice']);

      expect(http.requests, hasLength(1));
      final req = http.requests.single;
      expect(req.url.path, endsWith('/rpc/match_foods'));
      expect(req.json, {
        'p_names': ['plain flour', 'mystery spice'],
      });

      expect(matches['plain flour']?.first.id, 'all-purpose-flour');
      // "Looked, found nothing" keeps its key — the review flow renders it.
      expect(matches['mystery spice'], isEmpty);
    });

    test('empty input makes no request', () async {
      final http = RecordingHttpClient([]);
      final repo = SupabaseFoodRepository(fakeSupabase(http));

      expect(await repo.matchFoods([]), isEmpty);
      expect(http.requests, isEmpty);
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
