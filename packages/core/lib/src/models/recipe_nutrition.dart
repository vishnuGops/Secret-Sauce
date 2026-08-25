import 'package:freezed_annotation/freezed_annotation.dart';

part 'recipe_nutrition.freezed.dart';
part 'recipe_nutrition.g.dart';

/// The nutrition-facts label for one **serving** of a recipe, at the recipe's
/// own `servings` count.
///
/// Stored in the single nullable `recipes.nutrition` jsonb column rather than
/// eleven `numeric` columns: the writable-recipe-column set is restated in ~13
/// places across SQL, Dart, and the authoring tooling, so one column costs each
/// copy one line where eleven would cost eleven. Postgres can only check that
/// the value is an object (`recipes_nutrition_is_object`); **this class is what
/// pins the key set**, together with `tool/recipe_format.dart` on the authoring
/// side.
///
/// Every field is optional — a cook who knows the calories and nothing else
/// enters exactly that, and the label omits the rows with no value. All are
/// `double?` because Postgres `numeric` arrives as a JSON number that may be int
/// or double (CLAUDE.md Gotcha 12); `json_serializable` decodes them through
/// `num?.toDouble()`.
///
/// `includeIfNull: false` on every field keeps the stored json to the fields
/// actually entered. The consequence, accepted deliberately: a single field can
/// never be *cleared* through a partial update, because an omitted key reads as
/// "not set" rather than "set to null". Saves always write the whole object (or
/// SQL `NULL`), never a patch, so nothing relies on that distinction.
///
/// **Values are per serving and are never multiplied by the servings scaler.**
/// Scaling 4 → 8 doubles the batch *and* the servings, so one serving is
/// unchanged; what moves with the stepper is the batch total, which the label
/// prints as a separate line.
@freezed
class RecipeNutrition with _$RecipeNutrition {
  const RecipeNutrition._();

  const factory RecipeNutrition({
    @JsonKey(includeIfNull: false) double? calories,
    @JsonKey(name: 'total_fat_g', includeIfNull: false) double? totalFatG,
    @JsonKey(name: 'saturated_fat_g', includeIfNull: false)
    double? saturatedFatG,
    @JsonKey(name: 'trans_fat_g', includeIfNull: false) double? transFatG,
    @JsonKey(name: 'cholesterol_mg', includeIfNull: false)
    double? cholesterolMg,
    @JsonKey(name: 'sodium_mg', includeIfNull: false) double? sodiumMg,
    @JsonKey(name: 'total_carbs_g', includeIfNull: false) double? totalCarbsG,
    @JsonKey(name: 'dietary_fiber_g', includeIfNull: false)
    double? dietaryFiberG,
    @JsonKey(name: 'total_sugars_g', includeIfNull: false) double? totalSugarsG,
    @JsonKey(name: 'added_sugars_g', includeIfNull: false) double? addedSugarsG,
    @JsonKey(name: 'protein_g', includeIfNull: false) double? proteinG,

    /// Provenance (Phase 29c): `'auto'` when the label was computed from the
    /// ingredient list by `estimate_nutrition` — **absent means manual**, so
    /// every label saved before this field existed (and every sim-invented
    /// one) reads correctly with zero migration. A plain `String?`, not an
    /// enum (nothing in SQL switches on it) and not a nested model (B071
    /// stays un-re-armed). The label never renders the value itself; it
    /// drives the `Estimated from ingredients` footnote via [isEstimated].
    @JsonKey(includeIfNull: false) String? source,
  }) = _RecipeNutrition;

  factory RecipeNutrition.fromJson(Map<String, dynamic> json) =>
      _$RecipeNutritionFromJson(json);

  /// True when not one field carries a value.
  ///
  /// An all-empty entry is normalized to `null` **before** it reaches the
  /// repository, so "no nutrition info" has exactly one representation on the
  /// wire and in the column. This getter is how the editor and the fixtures
  /// decide that.
  ///
  /// [source] is deliberately ignored: `{source: 'auto'}` with no values is
  /// still no label — counting provenance as content would let an empty
  /// estimate survive normalization as a masthead with no rows.
  bool get isEmpty =>
      calories == null &&
      totalFatG == null &&
      saturatedFatG == null &&
      transFatG == null &&
      cholesterolMg == null &&
      sodiumMg == null &&
      totalCarbsG == null &&
      dietaryFiberG == null &&
      totalSugarsG == null &&
      addedSugarsG == null &&
      proteinG == null;

  bool get isNotEmpty => !isEmpty;

  /// Whether this label was computed from the ingredient list rather than
  /// entered by hand — drives the label's `Estimated from ingredients`
  /// footnote and the editor's mode detection on load.
  bool get isEstimated => source == 'auto';
}
