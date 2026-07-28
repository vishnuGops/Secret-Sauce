import 'package:freezed_annotation/freezed_annotation.dart';

part 'recipe_step.freezed.dart';
part 'recipe_step.g.dart';

@freezed
class RecipeStep with _$RecipeStep {
  const factory RecipeStep({
    required String id,
    @JsonKey(name: 'group_id') required String groupId,
    @JsonKey(name: 'step_order') @Default(0) int stepOrder,
    required String text,
    @JsonKey(name: 'image_url') String? imageUrl,
    @JsonKey(name: 'duration_minutes') int? durationMinutes,
    String? temperature,
    String? tip,
    @JsonKey(name: 'sort_order') @Default(0) int sortOrder,
  }) = _RecipeStep;

  factory RecipeStep.fromJson(Map<String, dynamic> json) =>
      _$RecipeStepFromJson(json);
}
