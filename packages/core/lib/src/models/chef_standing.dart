import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:core/src/models/enums.dart';

part 'chef_standing.freezed.dart';
part 'chef_standing.g.dart';

/// One row of the `chefs_leaderboard(p_limit, p_offset)` RPC.
///
/// [chefRank] is a `dense_rank()` over `chef_score`, so tied chefs share a rank
/// and the sequence has no gaps. The board only lists chefs with at least one
/// public recipe; everyone else still has a [ChefTier] for badge purposes.
@freezed
class ChefStanding with _$ChefStanding {
  const ChefStanding._();

  const factory ChefStanding({
    @JsonKey(name: 'chef_rank') required int chefRank,
    required String id,
    @JsonKey(name: 'display_name') @Default('') String displayName,
    @JsonKey(name: 'avatar_url') String? avatarUrl,
    @JsonKey(name: 'chef_tier', unknownEnumValue: ChefTier.homeCook)
    @Default(ChefTier.homeCook)
    ChefTier chefTier,
    // Postgres `numeric` — arrives as a JSON number that may be int or double,
    // so this must stay `double` (json_serializable emits `as num).toDouble()`).
    @JsonKey(name: 'chef_score') @Default(0) double chefScore,
    @JsonKey(name: 'public_recipe_count') @Default(0) int publicRecipeCount,
    @JsonKey(name: 'total_likes') @Default(0) int totalLikes,
    @JsonKey(name: 'total_saves') @Default(0) int totalSaves,
    @JsonKey(name: 'total_views') @Default(0) int totalViews,
  }) = _ChefStanding;

  factory ChefStanding.fromJson(Map<String, dynamic> json) =>
      _$ChefStandingFromJson(json);

  /// Score without a trailing `.0` — the value is always a whole or one-decimal
  /// number in practice (views contribute 0.2 each).
  String get scoreLabel => chefScore == chefScore.roundToDouble()
      ? chefScore.toStringAsFixed(0)
      : chefScore.toStringAsFixed(1);
}
