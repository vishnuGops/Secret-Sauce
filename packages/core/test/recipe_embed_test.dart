// OPT-P3: `getById` fetches a recipe and all of its grouped content in one
// nested PostgREST embed instead of 2 + G + S sequential round trips.
//
// That only works because `Recipe.ingredientGroups` / `stepGroups` carry
// `@JsonKey(name: 'ingredient_groups' / 'step_groups')`. Without the names,
// json_serializable looks for the *Dart* field names, finds nothing, and falls
// back to `@Default(<...>[])` — so a full recipe decodes as an **empty** one
// with no error anywhere. `update()` then re-persists what it read, which is
// how B035 destroyed content. Hence a test on the decode itself.
//
// The fixture is a trimmed real response from the local stack, keys and all.
import 'package:core/core.dart';
// `recipe_queries.dart` is internal to the package (not in the barrel), so the
// select constants are reached directly — same as chef_models_test.dart.
import 'package:core/src/repositories/recipe_queries.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _embedResponse() => {
      'id': 'r1',
      'owner_id': 'u1',
      'title': 'Peruvian Ceviche with Mango',
      'servings': 4,
      'difficulty': 'medium',
      'visibility': 'public',
      'rating_avg': 4, // numeric may arrive as int — see the numeric test below
      'ingredient_groups': [
        {
          'id': 'g1',
          'recipe_id': 'r1',
          'name': 'Cure',
          'sort_order': 0,
          'ingredients': [
            {
              'id': 'i1',
              'group_id': 'g1',
              'name': 'sea bass',
              'unit': 'g',
              'quantity': 500,
              'note': 'cut into 2cm cubes',
              'is_optional': false,
              'sort_order': 0,
            },
            {
              'id': 'i2',
              'group_id': 'g1',
              'name': 'limes',
              'unit': null,
              'quantity': 10.5,
              'note': null,
              'is_optional': true,
              'sort_order': 1,
            },
          ],
        },
        {
          'id': 'g2',
          'recipe_id': 'r1',
          'name': 'To serve',
          'sort_order': 1,
          'ingredients': <Map<String, dynamic>>[],
        },
      ],
      'step_groups': [
        {
          'id': 's1',
          'recipe_id': 'r1',
          'name': 'Method',
          'sort_order': 0,
          'steps': [
            {
              'id': 'st1',
              'group_id': 's1',
              'step_order': 0,
              'text': 'Cube the fish.',
              'image_url': null,
              'duration_minutes': null,
              'temperature': null,
              'tip': null,
              'sort_order': 0,
            },
            {
              'id': 'st2',
              'group_id': 's1',
              'step_order': 1,
              'text': 'Cure in lime juice.',
              'image_url': 'https://example.test/s.jpg',
              'duration_minutes': 12,
              'temperature': '4°C',
              'tip': 'Do not over-cure.',
              'sort_order': 1,
            },
          ],
        },
      ],
    };

void main() {
  group('nested embed decoding (OPT-P3)', () {
    test('ingredient_groups populates ingredientGroups, not the empty default',
        () {
      final r = Recipe.fromJson(_embedResponse());
      expect(
        r.ingredientGroups,
        hasLength(2),
        reason: 'a missing @JsonKey(name:) would silently yield []',
      );
      expect(r.ingredientGroups.first.name, 'Cure');
    });

    test('step_groups populates stepGroups', () {
      final r = Recipe.fromJson(_embedResponse());
      expect(r.stepGroups, hasLength(1));
      expect(r.stepGroups.first.name, 'Method');
    });

    test('doubly-nested children decode too', () {
      final r = Recipe.fromJson(_embedResponse());
      expect(r.ingredientGroups.first.ingredients, hasLength(2));
      expect(r.ingredientGroups.first.ingredients.first.name, 'sea bass');
      expect(r.stepGroups.first.steps, hasLength(2));
      expect(r.stepGroups.first.steps.last.text, 'Cure in lime juice.');
    });

    test('a group with no children decodes as empty, not null', () {
      final r = Recipe.fromJson(_embedResponse());
      expect(r.ingredientGroups[1].ingredients, isEmpty);
    });

    test('every step column survives the embed (B035)', () {
      final step = Recipe.fromJson(_embedResponse()).stepGroups.first.steps.last;
      expect(step.imageUrl, 'https://example.test/s.jpg');
      expect(step.durationMinutes, 12);
      expect(step.temperature, '4°C');
      expect(step.tip, 'Do not over-cure.');
      expect(step.stepOrder, 1);
    });

    test('every ingredient column survives the embed (B035)', () {
      final g = Recipe.fromJson(_embedResponse()).ingredientGroups.first;
      expect(g.ingredients.first.note, 'cut into 2cm cubes');
      expect(g.ingredients.first.unit, 'g');
      expect(g.ingredients.last.isOptional, isTrue);
    });

    test('quantity decodes whether Postgres numeric arrives int or double', () {
      final g = Recipe.fromJson(_embedResponse()).ingredientGroups.first;
      expect(g.ingredients.first.quantity, 500.0); // sent as int
      expect(g.ingredients.last.quantity, 10.5); // sent as double
    });

    // The embed must not leak into the version snapshot: `_appendVersion`
    // stores `{recipe: toJson(), ingredient_groups: [...], step_groups: [...]}`
    // and would double-encode the content if toJson started including it.
    test('toJson still excludes the content', () {
      final json = Recipe.fromJson(_embedResponse()).toJson();
      expect(json.containsKey('ingredient_groups'), isFalse);
      expect(json.containsKey('step_groups'), isFalse);
      expect(json.containsKey('ingredientGroups'), isFalse);
      expect(json.containsKey('stepGroups'), isFalse);
    });
  });

  group('kRecipeDetailSelect', () {
    test('asks for both content trees nested', () {
      expect(kRecipeDetailSelect, contains('ingredient_groups(*,ingredients(*))'));
      expect(kRecipeDetailSelect, contains('step_groups(*,steps(*))'));
    });

    test('still carries the owner FK hint from kRecipeSelect', () {
      expect(kRecipeDetailSelect, contains('owner:profiles!recipes_owner_id_fkey'));
    });
  });
}
