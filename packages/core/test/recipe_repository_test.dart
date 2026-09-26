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
  'nutrition': {'calories': 520, 'protein_g': 31.5},
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
        // Phase 35b: the identity RPC comes first now — the repository asks the
        // database which `profiles` row this account is rather than assuming it
        // is the auth uid.
        (200, jsonEncode(_uid)),
        (200, jsonEncode([_recipeRow()])),
      ]);
      await signInAs(client, _uid);

      await repo.listMine();

      final req = http.requests.last;
      expect(req.param('owner_id'), 'eq.$_uid');
      // OPT-P9: `id` after `updated_at` is what makes `offset` meaningful — two
      // recipes saved in the same second are free to swap without it.
      expect(req.order, 'updated_at.desc.nullslast,id.desc.nullslast');
      expect(req.param('limit'), '$kRecipePageSize');
      expect(req.param('offset'), '0');
    });

    test('a second page asks for the next window', () async {
      final (:http, :client, :repo) = _repo([
        (200, jsonEncode(_uid)),
        (200, jsonEncode(<Object>[])),
      ]);
      await signInAs(client, _uid);

      await repo.listMine(limit: kRecipePageSize, offset: kRecipePageSize);

      expect(http.requests.last.param('offset'), '20');
      expect(http.requests.last.param('limit'), '20');
    });

    test('signed out, it throws before reaching the network', () async {
      final (:http, :client, :repo) = _repo([]);

      await expectLater(repo.listMine(), throwsA(isA<StateError>()));
      expect(http.requests, isEmpty);
    });
  });

  // UX-020: the Saved tab. Paged over `recipe_saves`, so that table carries the
  // total order, and the embed is `!inner` so a saved recipe that has since
  // gone private drops out server-side instead of arriving as `null`.
  group('listSaved', () {
    test('pages recipe_saves in a total order, with an inner embed', () async {
      final (:http, :client, :repo) = _repo([
        (200, jsonEncode(_uid)),
        (
          200,
          jsonEncode([
            {'recipes': _recipeRow()},
          ]),
        ),
      ]);
      await signInAs(client, _uid);

      final saved = await repo.listSaved(offset: kRecipePageSize);

      final req = http.requests.last;
      expect(req.url.path, endsWith('/recipe_saves'));
      expect(req.param('user_id'), 'eq.$_uid');
      expect(req.param('select'), startsWith('recipes!inner('));
      expect(req.order, 'created_at.desc.nullslast,recipe_id.desc.nullslast');
      expect(req.param('offset'), '$kRecipePageSize');
      expect(req.param('limit'), '$kRecipePageSize');
      expect(saved.single.id, 'r1');
    });

    test('signed out, it throws before reaching the network', () async {
      final (:http, :client, :repo) = _repo([]);

      await expectLater(repo.listSaved(), throwsA(isA<StateError>()));
      expect(http.requests, isEmpty);
    });
  });

  // Phase 35b. `profiles.id` stopped being the auth uid for one person: a
  // member who has claimed an imported chef page. These pin the two properties
  // that make that person's writes land — the repository filters on the
  // RESOLVED id, and it resolves it once.
  group('profile identity (Phase 35b)', () {
    const claimedProfile = '22222222-2222-2222-2222-222222222222';

    test('writes key on the resolved profile id, not the auth uid', () async {
      final (:http, :client, :repo) = _repo([
        (200, jsonEncode(claimedProfile)),
        (200, jsonEncode(<Object>[])),
      ]);
      await signInAs(client, _uid);

      await repo.listMine();

      expect(http.requests.first.url.path, endsWith('/rpc/current_profile_id'));
      // The whole point: `_uid` would have been wrong here, and wrong in a way
      // RLS answers with zero rows rather than an error (Gotcha 2).
      expect(http.requests.last.param('owner_id'), 'eq.$claimedProfile');
    });

    test('resolves once per session and caches', () async {
      final (:http, :client, :repo) = _repo([
        (200, jsonEncode(claimedProfile)),
        (200, jsonEncode(<Object>[])),
        (200, jsonEncode(<Object>[])),
      ]);
      await signInAs(client, _uid);

      await repo.listMine();
      await repo.listMine();

      final rpcs = http.requests.where(
        (r) => r.url.path.endsWith('/rpc/current_profile_id'),
      );
      expect(rpcs, hasLength(1));
      expect(http.requests, hasLength(3));
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
          // Set on purpose: the payload assertion below is about a *non-null*
          // lineage being dropped, which is the B082 property. With null here
          // the keys would be absent for an uninteresting reason.
          forkedFromRecipeId: 'src1',
          forkedFromVersionId: 'srcv1',
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
                  foodId: 'greek-yogurt',
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
        // B082: lineage is server-owned. `save_recipe` ignores it on update and
        // rejects it on insert, so a client that still sends it is either
        // wasting a key or about to fail a create. The draft above carries a
        // non-null lineage, so this asserts the payload builder *drops* it
        // rather than merely echoing a null.
        expect(payload.keys, isNot(contains('forked_from_recipe_id')));
        expect(payload.keys, isNot(contains('forked_from_version_id')));

        // Content goes as arrays; position IS sort_order, so nothing sends one.
        final groups = body['p_ingredient_groups'] as List;
        expect(groups.single['name'], 'Marinade');
        expect((groups.single as Map).keys, isNot(contains('sort_order')));
        final ingredients = groups.single['ingredients'] as List;
        expect(ingredients.single['quantity'], 1.5);
        expect(ingredients.single['is_optional'], false);
        // Phase 29b: the registry link rides in the same payload — a key the
        // client drops here is a link the next save silently severs (the B035
        // shape, one layer down).
        expect(ingredients.single['food_id'], 'greek-yogurt');

        final steps = (body['p_step_groups'] as List).single['steps'] as List;
        expect(steps.single['text'], 'Marinate overnight');
        expect(steps.single['duration_minutes'], 480);

        expect(saved.title, 'Renamed');
      },
    );

    // Phase 28. The request-side half of what the RLS matrix proves on the
    // policy side: `nutrition` reaches `p_payload` as the label's own key set,
    // and the key is present-but-null when there is no label — that null is
    // what tells `save_recipe` to clear the column.
    test('nutrition rides in p_payload, and null is still sent', () async {
      final (:http, :client, :repo) = _repo([
        (200, jsonEncode('r1')),
        (200, jsonEncode(_recipeRow())),
        (200, jsonEncode('r1')),
        (200, jsonEncode(_recipeRow())),
      ]);
      await signInAs(client, _uid);

      await repo.update(
        const Recipe(
          id: 'r1',
          ownerId: _uid,
          title: 'With label',
          nutrition: RecipeNutrition(calories: 520, proteinG: 31.5),
        ),
      );
      final withLabel =
          http.requests.first.json['p_payload'] as Map<String, dynamic>;
      expect(withLabel['nutrition'], {'calories': 520.0, 'protein_g': 31.5});

      await repo.update(
        const Recipe(id: 'r1', ownerId: _uid, title: 'No label'),
      );
      final cleared =
          http.requests[2].json['p_payload'] as Map<String, dynamic>;
      expect(cleared.containsKey('nutrition'), isTrue);
      expect(cleared['nutrition'], isNull);
    });

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

  // UX-036: a fork names its parent. The parent is its own card-level read,
  // and a parent the reader cannot see (deleted, or private to its owner)
  // is no row at all under RLS — which must decode to null, not throw.
  group('findSummary', () {
    test('asks for one card-level row with the owner embed', () async {
      final row =
          _recipeRow()
            ..remove('ingredient_groups')
            ..remove('step_groups');
      final (:http, :client, :repo) = _repo([
        (200, jsonEncode([row])),
      ]);

      final parent = await repo.findSummary('r1');

      final req = http.requests.single;
      expect(req.param('id'), 'eq.r1');
      expect(req.select, contains('owner:profiles!recipes_owner_id_fkey'));
      // A lineage line needs a title and a byline, not the content.
      expect(req.select, isNot(contains('ingredient_groups')));
      expect(parent?.title, 'Chicken Tikka Masala');
    });

    test('a row RLS hides is null, not an error', () async {
      final (:http, :client, :repo) = _repo([(200, '[]')]);

      expect(await repo.findSummary('gone'), isNull);
    });
  });

  // UX-052: a version-history row opens that version. `versions()` never
  // ships `content_snapshot` (B065), so opening one is its own one-row read.
  group('versionContent', () {
    test('reads one snapshot and decodes it as a recipe', () async {
      final full = _recipeRow();
      final snapshot = {
        'recipe':
            Map.of(full)
              ..remove('ingredient_groups')
              ..remove('step_groups'),
        'ingredient_groups': full['ingredient_groups'],
        'step_groups': full['step_groups'],
      };
      final (:http, :client, :repo) = _repo([
        (
          200,
          jsonEncode([
            {'content_snapshot': snapshot},
          ]),
        ),
      ]);

      final recipe = await repo.versionContent('v2');

      final req = http.requests.single;
      expect(req.url.path, endsWith('/recipe_versions'));
      expect(req.select, 'content_snapshot');
      expect(req.param('id'), 'eq.v2');
      expect(recipe?.title, 'Chicken Tikka Masala');
      expect(
        recipe?.ingredientGroups.single.ingredients.single.name,
        'yoghurt',
      );
      expect(recipe?.stepGroups.single.steps.single.durationMinutes, 480);
    });

    test('an empty snapshot is null — the seeded fixtures write {}', () async {
      final (:http, :client, :repo) = _repo([
        (
          200,
          jsonEncode([
            {'content_snapshot': <String, dynamic>{}},
          ]),
        ),
      ]);

      expect(await repo.versionContent('v1'), isNull);
    });
  });

  // 32d5. OPT-S2's contract — the project's headline silent-failure class
  // (Gotcha 2) — had no test at all. `.delete()` matching zero rows is a
  // **success** at the PostgREST layer, so an RLS denial on these two paths is
  // indistinguishable from a write unless the repository checks the returned
  // rows, which is what these pin.
  group('denied writes (OPT-S2 / Gotcha 2)', () {
    test('delete returning no rows is WriteDeniedException', () async {
      final (:http, :client, :repo) = _repo([(200, jsonEncode(<Object>[]))]);
      await signInAs(client, _uid);

      await expectLater(
        repo.delete('r1'),
        throwsA(isA<WriteDeniedException>()),
      );
      // The `.select()` is what makes the check possible in the first place: a
      // bare delete returns nothing to count.
      expect(http.requests.single.select, 'id');
    });

    test('delete returning the row succeeds', () async {
      final (:http, :client, :repo) = _repo([
        (
          200,
          jsonEncode([
            {'id': 'r1'},
          ]),
        ),
      ]);
      await signInAs(client, _uid);

      await repo.delete('r1');

      expect(http.requests.single.param('id'), 'eq.r1');
    });

    test('unshare returning no rows is WriteDeniedException', () async {
      final (:http, :client, :repo) = _repo([(200, jsonEncode(<Object>[]))]);
      await signInAs(client, _uid);

      await expectLater(
        repo.unshare(recipeId: 'r1', userId: 'u2'),
        throwsA(isA<WriteDeniedException>()),
      );
      final req = http.requests.single;
      expect(req.select, 'recipe_id');
      expect(req.param('recipe_id'), 'eq.r1');
      expect(req.param('shared_with_user_id'), 'eq.u2');
    });

    test('unshare returning the row succeeds', () async {
      final (:http, :client, :repo) = _repo([
        (
          200,
          jsonEncode([
            {'recipe_id': 'r1'},
          ]),
        ),
      ]);
      await signInAs(client, _uid);

      await repo.unshare(recipeId: 'r1', userId: 'u2');

      expect(http.requests, hasLength(1));
    });
  });

  group('listByChef', () {
    test('filters to public rows, in a total order', () async {
      final (:http, :client, :repo) = _repo([
        (200, jsonEncode([_recipeRow()])),
      ]);

      await repo.listByChef('d1');

      final req = http.requests.single;
      expect(req.param('owner_id'), 'eq.d1');
      // Load-bearing, not a restatement of RLS: `recipes_select` lets a signed-in
      // user read their own private recipes, so without this a chef opening
      // their own page sees rows nobody else can — and the public-recipe count
      // in the header stops matching the grid under it.
      expect(
        req.param('visibility'),
        'eq.public',
        reason: 'the chef page must not leak the owner their own private rows',
      );
      expect(req.order, 'created_at.desc.nullslast,id.desc.nullslast');
      expect(req.param('limit'), '$kRecipePageSize');
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
