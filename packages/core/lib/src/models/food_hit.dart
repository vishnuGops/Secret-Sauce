import 'package:freezed_annotation/freezed_annotation.dart';

part 'food_hit.freezed.dart';
part 'food_hit.g.dart';

/// One `search_foods` result row — the ingredients editor's typeahead
/// (Phase 29b). The RPC returns id + display_name only: the editor needs
/// nothing else, and the food's nutrition columns are not this surface's
/// business.
@freezed
class FoodHit with _$FoodHit {
  const factory FoodHit({
    required String id,
    @JsonKey(name: 'display_name') required String displayName,
  }) = _FoodHit;

  factory FoodHit.fromJson(Map<String, dynamic> json) =>
      _$FoodHitFromJson(json);
}
