import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:core/src/chef_scoring.dart';
import 'package:core/src/models/chef_standing.dart';

part 'chef_window.freezed.dart';
part 'chef_window.g.dart';

/// What one chef earned inside a time window — one row of
/// `chef_window_stats(p_days, p_since, p_chef)` (Phase 33).
///
/// Every number is counted from the dated engagement **logs**, not the lifetime
/// counters on `profiles`, and only over the chef's public recipes. [score] is
/// computed by the real `chef_score()` in SQL — this model never restates the
/// weights (Gotcha 19); the only arithmetic here is formatting.
///
/// [viewers] is distinct signed-in viewers per recipe, not view rows: anonymous
/// views are excluded and a reader counts once (B012 / Gotcha 10), so it is
/// always at most the view rows a chef could see in their own log.
///
/// [ratings] and [newRecipes] are reported **beside** the score and do not enter
/// it, because `chef_score()` has no term for either.
@freezed
class ChefWindowStats with _$ChefWindowStats {
  const ChefWindowStats._();

  const factory ChefWindowStats({
    required String id,

    /// The boundary the server actually used: `p_since` when one was passed,
    /// `now() - p_days` otherwise. Echoed back so a caller can say "since …".
    @JsonKey(name: 'window_start') required DateTime windowStart,
    @JsonKey(name: 'window_likes') @Default(0) int likes,
    @JsonKey(name: 'window_saves') @Default(0) int saves,
    @JsonKey(name: 'window_views') @Default(0) int viewers,
    @JsonKey(name: 'window_ratings') @Default(0) int ratings,
    @JsonKey(name: 'window_recipes') @Default(0) int newRecipes,
    // Postgres `numeric` — int or double on the wire (Gotcha 12).
    @JsonKey(name: 'window_score') @Default(0) double score,
  }) = _ChefWindowStats;

  factory ChefWindowStats.fromJson(Map<String, dynamic> json) =>
      _$ChefWindowStatsFromJson(json);

  /// Whether this chef gained any points in the window. The Momentum board and
  /// the windowed rails list only these: a quiet chef ranks last on the
  /// windowed RPC (every zero ties), and listing them would dress the all-time
  /// board up as "who moved".
  bool get moved => score > 0;

  /// Nothing at all happened: no points, no ratings, no new recipes. Stricter
  /// than `!moved` — a chef who published this week but has not been read yet
  /// did not move, but was not idle either.
  bool get isIdle => !moved && ratings == 0 && newRecipes == 0;

  /// `+312`, or `+0` for a quiet window. Grouped, no trailing `.0`.
  String get gainLabel => '+${ChefScoring.label(score)}';
}

/// One row of `chefs_leaderboard_windowed` — the all-time [standing] the row
/// shares with `chefs_leaderboard`, plus what the chef earned in the [window].
///
/// The RPC returns both halves flat in one row on purpose ("one client model
/// decodes both boards"), so this splits it rather than duplicating eleven
/// columns: the all-time half is exactly a [ChefStanding], which every chef
/// widget already takes.
///
/// **`standing.chefRank` is the rank in the window** — the RPC's `dense_rank()`
/// runs over `window_score`, so on a quiet week every chef shares the last rank.
@freezed
class ChefWindowStanding with _$ChefWindowStanding {
  const ChefWindowStanding._();

  const factory ChefWindowStanding({
    required ChefStanding standing,
    required ChefWindowStats window,
  }) = _ChefWindowStanding;

  /// Decodes one flat RPC row into its two halves.
  factory ChefWindowStanding.fromRow(Map<String, dynamic> row) =>
      ChefWindowStanding(
        standing: ChefStanding.fromJson(row),
        window: ChefWindowStats.fromJson(row),
      );

  String get id => standing.id;
}
