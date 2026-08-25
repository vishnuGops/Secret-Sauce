import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:core/src/models/enums.dart';
import 'package:core/src/models/ingredient_group.dart';
import 'package:core/src/models/profile.dart';
import 'package:core/src/models/recipe_nutrition.dart';
import 'package:core/src/models/step_group.dart';

part 'recipe.freezed.dart';
part 'recipe.g.dart';

Map<String, dynamic>? _nutritionToJson(RecipeNutrition? n) => n?.toJson();

@freezed
class Recipe with _$Recipe {
  const Recipe._();

  const factory Recipe({
    required String id,
    @JsonKey(name: 'owner_id') required String ownerId,
    required String title,
    @Default('') String description,
    @JsonKey(name: 'cover_image_url') String? coverImageUrl,
    String? cuisine,
    String? category,
    @Default(Difficulty.easy) Difficulty difficulty,
    @JsonKey(name: 'prep_minutes') @Default(0) int prepMinutes,
    @JsonKey(name: 'cook_minutes') @Default(0) int cookMinutes,
    @Default(1) int servings,
    @Default(RecipeVisibility.private) RecipeVisibility visibility,
    String? attribution,
    @JsonKey(name: 'forked_from_recipe_id') String? forkedFromRecipeId,
    @JsonKey(name: 'forked_from_version_id') String? forkedFromVersionId,
    @JsonKey(name: 'current_version_id') String? currentVersionId,
    @JsonKey(name: 'like_count') @Default(0) int likeCount,
    @JsonKey(name: 'save_count') @Default(0) int saveCount,
    @JsonKey(name: 'view_count') @Default(0) int viewCount,
    // Denormalized rating aggregates, maintained server-side by trigger.
    @JsonKey(name: 'rating_avg') @Default(0) double ratingAvg,
    @JsonKey(name: 'rating_count') @Default(0) int ratingCount,
    @JsonKey(name: 'created_at') DateTime? createdAt,
    @JsonKey(name: 'updated_at') DateTime? updatedAt,
    // Per-serving nutrition label, or null for "no info" — the ONE
    // representation of the empty state (an all-empty entry is normalized to
    // null before it reaches the repository). Client-writable, so it is in
    // `_writablePayload`, both column grant lists, and `save_recipe`.
    //
    // The explicit `toJson:` is not decoration. `explicitToJson` is off for
    // this package, and every other nested model on `Recipe` is
    // `includeToJson: false`, so this is the first field whose value has to be
    // flattened — without it the generator emits the object itself and
    // `jsonEncode(recipe.toJson())` throws at the call site rather than here.
    @JsonKey(toJson: _nutritionToJson) RecipeNutrition? nutrition,
    // Populated when a full recipe is loaded (not part of the base row).
    //
    // The `name:` is load-bearing (OPT-P3): `getById` now fetches the content as
    // a nested PostgREST embed, which arrives under the **table** names, and
    // without these the groups would silently decode to their empty defaults —
    // an empty recipe, and `update()` re-persists what it read (B035's family).
    // `includeToJson: false` stays, so `toJson()` remains the base row only and
    // the version snapshot keeps its existing `{recipe, ingredient_groups,
    // step_groups}` shape.
    @JsonKey(name: 'ingredient_groups', includeToJson: false)
    @Default(<IngredientGroup>[])
    List<IngredientGroup> ingredientGroups,
    @JsonKey(name: 'step_groups', includeToJson: false)
    @Default(<StepGroup>[])
    List<StepGroup> stepGroups,
    // The owning chef, embedded by PostgREST via kRecipeSelect. Null on any
    // query that does not ask for the embedding — surfaces render no badge
    // rather than failing.
    @JsonKey(includeToJson: false) Profile? owner,
  }) = _Recipe;

  factory Recipe.fromJson(Map<String, dynamic> json) => _$RecipeFromJson(json);

  /// Total time to cook (prep + cook), in minutes.
  int get totalMinutes => prepMinutes + cookMinutes;

  bool get isFork => forkedFromRecipeId != null;

  /// Whether anyone has rated this recipe yet.
  bool get hasRatings => ratingCount > 0;

  /// Average rating rounded to one decimal, e.g. `4.5`.
  String get ratingLabel => ratingAvg.toStringAsFixed(1);
}
