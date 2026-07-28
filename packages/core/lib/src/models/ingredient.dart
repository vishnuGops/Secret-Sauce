import 'package:freezed_annotation/freezed_annotation.dart';

part 'ingredient.freezed.dart';
part 'ingredient.g.dart';

@freezed
class Ingredient with _$Ingredient {
  const factory Ingredient({
    required String id,
    @JsonKey(name: 'group_id') required String groupId,
    double? quantity,
    String? unit,
    required String name,
    String? note,
    @JsonKey(name: 'is_optional') @Default(false) bool isOptional,
    @JsonKey(name: 'sort_order') @Default(0) int sortOrder,
  }) = _Ingredient;

  factory Ingredient.fromJson(Map<String, dynamic> json) =>
      _$IngredientFromJson(json);
}
