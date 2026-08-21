import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:core/src/chef_scoring.dart';
import 'package:core/src/formatting.dart';
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

  /// Score, grouped and without a trailing `.0` — the value is always a whole
  /// or one-decimal number in practice (views contribute 0.2 each).
  String get scoreLabel => ChefScoring.label(chefScore);

  /// A podium row on the board (ranks 1–3), which the design gives a medal
  /// glyph instead of a numeral. Ties share a rank, so there can be more than
  /// three of these.
  bool get isPodium => chefRank <= 3;

  /// Progress through the current tier's band, 0..1 — the `% to next tier` the
  /// collapsed card shows. Derived from the score, not the stored tier.
  double get tierProgress => ChefScoring.progressToNext(chefScore);

  /// The rung above this chef's score, or null once Master Chef is reached.
  ChefTier? get nextTier =>
      ChefScoring.nextTier(ChefScoring.tierFor(chefScore));

  /// `27% to Master`, or null at the top tier — the line under the score.
  String? get nextTierLabel {
    final next = nextTier;
    if (next == null) return null;
    final pct = (tierProgress * 100).floor().clamp(0, 99);
    // "Master Chef" is too long for the score column at 2.0x scale; the rung
    // word alone is unambiguous next to a tier chip that spells it out.
    final rung = next.label.split(' ').first;
    return '$pct% to $rung';
  }

  /// Points still needed for the next tier, grouped — `9,811`. Null at the top.
  String? get pointsToNextLabel {
    final gap = ChefScoring.pointsToNext(chefScore);
    return gap == null ? null : groupedCount(gap.ceil());
  }
}
