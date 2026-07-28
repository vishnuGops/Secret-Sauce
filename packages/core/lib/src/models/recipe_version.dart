import 'package:freezed_annotation/freezed_annotation.dart';

part 'recipe_version.freezed.dart';
part 'recipe_version.g.dart';

@freezed
class RecipeVersion with _$RecipeVersion {
  const factory RecipeVersion({
    required String id,
    @JsonKey(name: 'recipe_id') required String recipeId,
    @JsonKey(name: 'version_number') required int versionNumber,
    @JsonKey(name: 'parent_version_id') String? parentVersionId,
    @JsonKey(name: 'author_id') required String authorId,
    @JsonKey(name: 'change_summary') @Default('') String changeSummary,
    @JsonKey(name: 'content_snapshot')
    @Default(<String, dynamic>{})
    Map<String, dynamic> contentSnapshot,
    @JsonKey(name: 'created_at') DateTime? createdAt,
  }) = _RecipeVersion;

  factory RecipeVersion.fromJson(Map<String, dynamic> json) =>
      _$RecipeVersionFromJson(json);
}
