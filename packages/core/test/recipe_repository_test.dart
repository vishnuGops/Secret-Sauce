// OPT-T2: the first repository tests. Gotcha 15 has said "every repository
// method is untested" since Phase 3, and the reason given was always mocking
// `SupabaseClient`. The way under it is `test/support/fake_supabase.dart` — the
// client takes an `httpClient`, so the request itself becomes assertable.
//
// These pin the read-path contracts that have actually broken here: the
// `kRecipeSelect` FK hint (drop it and every recipe query fails at once), B022's
// four explicit ascending orders, OPT-P3's one-request-per-open, OPT-P9's
// offsets and total ordering, and OPT-A1's single save RPC.
import 'dart:convert';

import 'package:core/core.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_supabase.dart';

const _uid = '11111111-1111-1111-1111-111111111111';

Map<String, dynamic> _recipeRow({
  String id = 'r1',
  String title = 'Chicken Tikka Masala',
}) => {
  'id': id,
  'owner_id': _uid,
  'title': title,
  'description': 'creamy',
  'cover_image_url': null,
  'cuisine': 'Indian',
  'category': 'Main',
  'difficulty': 'medium',
  'prep_minutes': 20,
  'cook_minutes': 40,
  'servings': 4,
  'visibility': 'public',
  'attribution': null,
  'forked_from_recipe_id': null,
  'forked_from_version_id': null,
  'current_version_id': 'v1',
  'like_count': 3,
  'save_count': 2,
  'view_count': 9,
  'created_at': '2026-08-01T10:00:00Z',
  'updated_at': '2026-08-02T10:00:00Z',
  'rating_sum': 9.0,
  'rating_count': 2,
  'rating_avg': 4.5,
  'ingredient_groups': [
    {
      'id': 'g1',
      'recipe_id': id,
      'name': 'Marinade',
      'sort_order': 0,
      'ingredients': [
        {
          'id': 'i1',
          'group_id': 'g1',
          'quantity': 1.5,
          'unit': 'cup',
          'name': 'yoghurt',
          'note': null,
          'is_optional': false,
          'sort_order': 0,
        },
      ],
    },
  ],
  'step_groups': [
    {
      'id': 's1',
      'recipe_id': id,
      'name': 'Cook',
      'sort_order': 0,
      'steps': [
        {
          'id': 'st1',
          'group_id': 's1',
          'step_order': 0,
          'text': 'Marinate overnight',
          'image_url': null,
          'duration_minutes': 480,
          'temperature': null,
          'tip': null,
          'sort_order': 0,
        },
      ],
    },
  ],
};

({
  RecordingHttpClient http,
  SupabaseClient client,
  SupabaseRecipeRepository repo,
})
_repo(List<(int, String)> responses) {
  final http = RecordingHttpClient(responses);
  final client = fakeSupabase(http);
  return (http: http, client: client, repo: SupabaseRecipeRepository(client));
}

void main() {
  group('getById', () {
    test(
      'is ONE request carrying the embed and all four ascending orders',
      () async {
        final (:http, :client, :repo) = _repo([
          (200, jsonEncode(_recipeRow())),
        ]);

        final recipe = await repo.getById('r1');

        // OPT-P3: this used to be 2 + one per group.
        expect(http.requests, hasLength(1));
        final req = http.requests.single;

        // The FK hint (Gotcha 17) and the explicit column list (OPT-P1).
        expect(req.select, contains('owner:profiles!recipes_owner_id_fkey'));
        expect(req.select, contains('ingredient_groups(*,ingredients(*))'));
        expect(req.select, contains('step_groups(*,steps(*))'));
        expect(req.select, isNot(contains('search_tsv')));

        // B022: every nested level ordered, every one **ascending**.
        // postgrest-dart defaults to descending and `update()` re-persists what
        // it read, so a missing `ascending: true` writes the recipe back
        // reversed. All four, because PostgREST promises no order for an embedded
        // resource and drops nothing if you ask for less.
        expect(req.orderOn('ingredient_groups'), startsWith('sort_order.asc'));
        expect(
          req.orderOn('ingredient_groups.ingredients'),
          startsWith('sort_order.asc'),
        );
        expect(req.orderOn('step_groups'), startsWith('sort_order.asc'));
        expect(req.orderOn('step_groups.steps'), startsWith('step_order.asc'));

        // And it decodes — the `@JsonKey(name:)` OPT-P3 needed, without which the
        // content silently arrives empty.
        expect(
          recipe.ingredientGroups.single.ingredients.single.name,
          'yoghurt',
        );
        expect(recipe.ingredientGroups.single.ingredients.single.quantity, 1.5);
        expect(recipe.stepGroups.single.steps.single.durationMinutes, 480);
        expect(recipe.ratingAvg, 4.5);
      },
    );

    test('decodes a numeric that arrives as an int, not a double', () async {
      // Postgres `numeric` is a JSON number that may be either (Gotcha 12).
      // `rating_sum` is not on the model — the client reads the average.
      final row = _recipeRow()..['rating_avg'] = 5;
      final (:http, :client, :repo) = _repo([(200, jsonEncode(row))]);

      final recipe = await repo.getById('r1');

      expect(recipe.ratingAvg, 5.0);
    });
  });

  group('listMine', () {
    test('asks for one page in a total order', () async {
      final (:http, :client, :repo) = _repo([
        (200, jsonEncode([_recipeRow()])),
      ]);
      await signInAs(client, _uid);

      await repo.listMine();

      final req = http.requests.single;
      expect(req.param('owner_id'), 'eq.$_uid');
      // OPT-P9: `id` after `updated_at` is what makes `offset` meaningful — two
      // recipes saved in the same second are free to swap without it.
      expect(req.order, 'updated_at.desc.nullslast,id.desc.nullslast');
      expect(req.param('limit'), '$kRecipePageSize');
      expect(req.param('offset'), '0');
    });

    test('a second page asks for the next window', () async {
      final (:http, :client, :repo) = _repo([(200, jsonEncode(<Object>[]))]);
      await signInAs(client, _uid);

      await repo.listMine(limit: kRecipePageSize, offset: kRecipePageSize);

      expect(http.requests.single.param('offset'), '20');
      expect(http.requests.single.param('limit'), '20');
    });

    test('signed out, it throws before reaching the network', () async {
      final (:http, :client, :repo) = _repo([]);

      await expectLater(repo.listMine(), throwsA(isA<StateError>()));
      expect(http.requests, isEmpty);
    });
  });

  group('save', () {
    test(
      'update is one save_recipe call with the content in list order',
      () async {
        final (:http, :client, :repo) = _repo([
          (200, jsonEncode('r1')), // the RPC returns the id
          (
            200,
            jsonEncode(_recipeRow(title: 'Renamed')),
          ), // the getById after it
        ]);
        await signInAs(client, _uid);

        const draft = Recipe(
          id: 'r1',
          ownerId: _uid,
          title: 'Renamed',
          servings: 4,
          ingredientGroups: [
            IngredientGroup(
              id: 'g1',
              recipeId: 'r1',
              name: 'Marinade',
              sortOrder: 0,
              ingredients: [
                Ingredient(
                  id: 'i1',
                  groupId: 'g1',
                  quantity: 1.5,
                  unit: 'cup',
                  name: 'yoghurt',
                  sortOrder: 0,
                ),
              ],
            ),
          ],
          stepGroups: [
            StepGroup(
              id: 's1',
              recipeId: 'r1',
              name: 'Cook',
              sortOrder: 0,
              steps: [
                RecipeStep(
                  id: 'st1',
                  groupId: 's1',
                  stepOrder: 0,
                  text: 'Marinate overnight',
                  durationMinutes: 480,
                  sortOrder: 0,
                ),
              ],
            ),
          ],
        );

        final saved = await repo.update(draft, changeSummary: 'Renamed it');

        // OPT-A1: the call, then one read for the return value. Nothing else.
        expect(http.requests, hasLength(2));
        expect(http.requests.first.url.path, endsWith('/rpc/save_recipe'));

        final body = http.requests.first.json;
        expect(body['p_recipe_id'], 'r1');
        expect(body['p_change_summary'], 'Renamed it');

        // Only the writable columns — no counters, no timestamps, no owner_id.
        final payload = body['p_payload'] as Map<String, dynamic>;
        expect(payload['title'], 'Renamed');
        expect(payload.keys, isNot(contains('like_count')));
        expect(payload.keys, isNot(contains('rating_avg')));
        expect(payload.keys, isNot(contains('current_version_id')));
        expect(payload.keys, isNot(contains('owner_id')));

        // Content goes as arrays; position IS sort_order, so nothing sends one.
        final groups = body['p_ingredient_groups'] as List;
        expect(groups.single['name'], 'Marinade');
        expect((groups.single as Map).keys, isNot(contains('sort_order')));
        final ingredients = groups.single['ingredients'] as List;
        expect(ingredients.single['quantity'], 1.5);
        expect(ingredients.single['is_optional'], false);

        final steps = (body['p_step_groups'] as List).single['steps'] as List;
        expect(steps.single['text'], 'Marinate overnight');
        expect(steps.single['duration_minutes'], 480);

        expect(saved.title, 'Renamed');
      },
    );

    test('create sends a null recipe id', () async {
      final (:http, :client, :repo) = _repo([
        (200, jsonEncode('r-new')),
        (200, jsonEncode(_recipeRow(id: 'r-new'))),
      ]);
      await signInAs(client, _uid);

      await repo.create(const Recipe(id: '', ownerId: '', title: 'Fresh'));

      expect(http.requests.first.json['p_recipe_id'], isNull);
    });

    test('a 42501 from the RPC becomes WriteDeniedException', () async {
      // What the function raises when `owns_recipe` says no. The repository has
      // to keep OPT-S2's contract: a refusal is never mistaken for a save.
      final (:http, :client, :repo) = _repo([
        (
          403,
          jsonEncode({
            'code': '42501',
            'message': 'not authorized to save this recipe',
            'details': null,
            'hint': null,
          }),
        ),
      ]);
      await signInAs(client, _uid);

      await expectLater(
        repo.update(
          const Recipe(id: 'r1', ownerId: 'someone-else', title: 'x'),
        ),
        throwsA(isA<WriteDeniedException>()),
      );
      // It stopped at the RPC — no read of a recipe it did not save.
      expect(http.requests, hasLength(1));
    });
  });

  group('versions', () {
    test('does not ask for content_snapshot', () async {
      // The snapshot is a whole recipe as jsonb (~10 KB a version, nine on some
      // recipes) and nothing on the client reads it — but the v2 header band
      // watches this provider on every page open. A bare `select()` shipped all
      // of it, and no local run could show that: every seeded snapshot is `{}`.
      final (:http, :client, :repo) = _repo([
        (
          200,
          jsonEncode([
            {
              'id': 'v2',
              'recipe_id': 'r1',
              'version_number': 2,
              'parent_version_id': 'v1',
              'author_id': _uid,
              'change_summary': 'Hotter rub',
              'created_at': '2026-08-02T10:00:00Z',
            },
          ]),
        ),
      ]);

      final versions = await repo.versions('r1');

      final req = http.requests.single;
      expect(req.select, isNot(contains('content_snapshot')));
      expect(req.select, contains('version_number'));
      expect(req.select, contains('change_summary'));
      expect(req.order, 'version_number.desc.nullslast');
      // The column is gone from the wire, so the model falls back to its
      // `@Default({})` — decoding must not need the key.
      expect(versions.single.contentSnapshot, isEmpty);
      expect(versions.single.versionNumber, 2);
      expect(versions.single.changeSummary, 'Hotter rub');
    });
  });

  group('signed-out reads', () {
    test('myLiked answers false without a request (Gotcha 9)', () async {
      final (:http, :client, :repo) = _repo([]);

      expect(await repo.myLiked('r1'), isFalse);
      expect(await repo.mySaved('r1'), isFalse);
      expect(await repo.myRating('r1'), isNull);
      expect(http.requests, isEmpty);
    });

    test('logView sends a null user_id rather than failing', () async {
      final (:http, :client, :repo) = _repo([(201, '')]);

      await repo.logView('r1');

      expect(http.requests.single.json['user_id'], isNull);
      expect(http.requests.single.json['recipe_id'], 'r1');
    });
  });
}
