import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:core/src/models/ingredient.dart';

part 'ingredient_group.freezed.dart';
part 'ingredient_group.g.dart';

@freezed
class IngredientGroup with _$IngredientGroup {
  const factory IngredientGroup({
    required String id,
    @JsonKey(name: 'recipe_id') required String recipeId,
    @Default('') String name,
    @JsonKey(name: 'sort_order') @Default(0) int sortOrder,
    @Default(<Ingredient>[]) List<Ingredient> ingredients,
  }) = _IngredientGroup;

  factory IngredientGroup.fromJson(Map<String, dynamic> json) =>
      _$IngredientGroupFromJson(json);
}
