import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:core/src/models/enums.dart';
import 'package:core/src/models/ingredient_group.dart';
import 'package:core/src/models/profile.dart';
import 'package:core/src/models/step_group.dart';

part 'recipe.freezed.dart';
part 'recipe.g.dart';

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
    // Populated when a full recipe is loaded (not part of the base row).
    @JsonKey(includeToJson: false)
    @Default(<IngredientGroup>[])
    List<IngredientGroup> ingredientGroups,
    @JsonKey(includeToJson: false)
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
