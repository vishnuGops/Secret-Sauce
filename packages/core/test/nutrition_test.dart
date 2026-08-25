// Phase 28. Two things are pinned here and nothing else can pin them:
//
//   * the wire contract of `recipes.nutrition` — a jsonb object whose keys are
//     the label's field names, arriving as Postgres `numeric`, i.e. int OR
//     double (Gotcha 12), with every field optional;
//   * that `toJson` omits the fields nobody entered, which is what keeps the
//     stored json to what a cook actually typed.
//
// The %DV arithmetic is here too because the expanded chef card's lesson
// (Gotcha 19) applies in miniature: the label *explains* a number, so the
// number needs a test that fails when the constant moves.
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RecipeNutrition decoding', () {
    test('reads int and double alike (numeric is either on the wire)', () {
      final n = RecipeNutrition.fromJson(const {
        'calories': 520, // int
        'protein_g': 31.5, // double
      });
      expect(n.calories, 520.0);
      expect(n.proteinG, 31.5);
    });

    test('every field maps to its snake_case column key', () {
      final n = RecipeNutrition.fromJson(const {
        'calories': 1,
        'total_fat_g': 2,
        'saturated_fat_g': 3,
        'trans_fat_g': 4,
        'cholesterol_mg': 5,
        'sodium_mg': 6,
        'total_carbs_g': 7,
        'dietary_fiber_g': 8,
        'total_sugars_g': 9,
        'added_sugars_g': 10,
        'protein_g': 11,
      });
      expect(
        [
          n.calories,
          n.totalFatG,
          n.saturatedFatG,
          n.transFatG,
          n.cholesterolMg,
          n.sodiumMg,
          n.totalCarbsG,
          n.dietaryFiberG,
          n.totalSugarsG,
          n.addedSugarsG,
          n.proteinG,
        ],
        [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0],
      );
      // Round-trips whole, so a field cannot be lost between load and save.
      expect(n.toJson().keys, hasLength(11));
    });

    test('absent and explicit-null keys both decode to null', () {
      final absent = RecipeNutrition.fromJson(const {'calories': 100});
      final explicit = RecipeNutrition.fromJson(const {
        'calories': 100,
        'protein_g': null,
      });
      expect(absent.proteinG, isNull);
      expect(explicit.proteinG, isNull);
      expect(absent, explicit);
    });

    test('an empty object decodes, and knows it is empty', () {
      expect(RecipeNutrition.fromJson(const {}).isEmpty, isTrue);
      expect(const RecipeNutrition(calories: 0).isEmpty, isFalse);
      expect(const RecipeNutrition(calories: 0).isNotEmpty, isTrue);
    });

    test('toJson omits the fields with no value', () {
      const n = RecipeNutrition(calories: 520, proteinG: 31.5);
      expect(n.toJson(), {'calories': 520.0, 'protein_g': 31.5});
    });
  });

  group('Recipe.nutrition', () {
    Map<String, dynamic> row(Object? nutrition) => {
      'id': 'r1',
      'owner_id': 'u1',
      'title': 'Tikka',
      'nutrition': nutrition,
    };

    test('decodes the embedded object', () {
      final r = Recipe.fromJson(row(const {'calories': 520}));
      expect(r.nutrition?.calories, 520.0);
    });

    test('a null column is no label, not an empty one', () {
      expect(Recipe.fromJson(row(null)).nutrition, isNull);
      // The distinction the UI renders: null is "no info available"; an object
      // with no fields would print a label with no rows.
      expect(Recipe.fromJson(row(<String, dynamic>{})).nutrition, isNotNull);
    });

    test('rides in toJson so the save payload carries it', () {
      const r = Recipe(
        id: 'r1',
        ownerId: 'u1',
        title: 'Tikka',
        nutrition: RecipeNutrition(calories: 520),
      );
      expect(r.toJson()['nutrition'], {'calories': 520.0});
    });
  });

  group('percentDailyValue', () {
    test('rounds to a whole percent against the FDA reference', () {
      expect(percentDailyValue(78, kDvTotalFatG), 100);
      expect(percentDailyValue(10, kDvTotalFatG), 13); // 12.82 → 13
      expect(percentDailyValue(575, kDvSodiumMg), 25);
    });

    test('no value means no percentage — not zero', () {
      expect(percentDailyValue(null, kDvProteinG), isNull);
    });

    test('a non-positive daily value returns null rather than Infinity', () {
      expect(percentDailyValue(10, 0), isNull);
    });

    test('the constants are the published 2,000-calorie values', () {
      expect(
        [
          kDvTotalFatG,
          kDvSaturatedFatG,
          kDvCholesterolMg,
          kDvSodiumMg,
          kDvTotalCarbsG,
          kDvDietaryFiberG,
          kDvAddedSugarsG,
          kDvProteinG,
        ],
        [78.0, 20.0, 300.0, 2300.0, 275.0, 28.0, 50.0, 50.0],
      );
    });
  });

  group('formatNutritionValue', () {
    test('drops the decimal a numeric round-trip adds', () {
      expect(formatNutritionValue(10), '10');
      expect(formatNutritionValue(10.0), '10');
    });

    test('keeps a real fraction, trimmed', () {
      expect(formatNutritionValue(1.5), '1.5');
      expect(formatNutritionValue(0.25), '0.25');
      expect(formatNutritionValue(2.50), '2.5');
    });
  });
}
