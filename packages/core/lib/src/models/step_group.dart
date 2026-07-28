import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:core/src/models/recipe_step.dart';

part 'step_group.freezed.dart';
part 'step_group.g.dart';

@freezed
class StepGroup with _$StepGroup {
  const factory StepGroup({
    required String id,
    @JsonKey(name: 'recipe_id') required String recipeId,
    @Default('') String name,
    @JsonKey(name: 'sort_order') @Default(0) int sortOrder,
    @Default(<RecipeStep>[]) List<RecipeStep> steps,
  }) = _StepGroup;

  factory StepGroup.fromJson(Map<String, dynamic> json) =>
      _$StepGroupFromJson(json);
}
