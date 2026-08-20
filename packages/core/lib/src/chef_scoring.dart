/// Client-side mirror of the chef score formula and the tier thresholds.
///
/// **`chef_score()` and `chef_tier_for()` in `supabase/migrations/0001_init.sql`
/// remain the single source of truth.** Every stored `profiles.chef_score` /
/// `chef_tier` and every leaderboard rank is decided by the server; nothing here
/// is ever written back. This exists only because the expanded chef card has to
/// *explain* a number the user is already looking at — "1,980 likes × 3 = 5,940",
/// and "9,811 points to Master Chef" — which is impossible without the weights
/// and thresholds on the client.
///
/// Changing the SQL therefore means changing this file in the same commit.
/// `packages/core/test/chef_scoring_test.dart` pins every weight and every
/// threshold boundary so a one-sided edit fails the suite rather than shipping a
/// card that quietly disagrees with the database.
library;

import 'package:core/src/formatting.dart';
import 'package:core/src/models/enums.dart';

/// One input to the score: its raw count, its multiplier, and what it is worth.
class ScoreContribution {
  const ScoreContribution({
    required this.label,
    required this.count,
    required this.weight,
    required this.points,
  });

  /// Plural noun for the input — `likes`, `saves`, `views`.
  final String label;

  /// The raw engagement count, summed over the chef's public recipes.
  final int count;

  /// The multiplier this input carries in the formula.
  final double weight;

  /// `count * weight`.
  final double points;
}

/// The formula, the thresholds, and the arithmetic the chef card shows.
abstract final class ChefScoring {
  /// Weights from `chef_score(p_likes, p_saves, p_views)`. A save is the
  /// strongest intent signal, a like weaker, a view weakest.
  static const double likeWeight = 3;
  static const double saveWeight = 5;
  static const double viewWeight = 0.2;

  /// Inclusive lower bound of each tier, from `chef_tier_for(p_score)`.
  /// `homeCook` is the floor and has no threshold of its own.
  static const Map<ChefTier, double> thresholds = {
    ChefTier.lineCook: 100,
    ChefTier.sousChef: 1000,
    ChefTier.headChef: 5000,
    ChefTier.masterChef: 20000,
  };

  /// The tiers that have a threshold, lowest first — the rungs of the ladder.
  static const List<ChefTier> ladder = [
    ChefTier.lineCook,
    ChefTier.sousChef,
    ChefTier.headChef,
    ChefTier.masterChef,
  ];

  /// `3*likes + 5*saves + 0.2*views`, matching `chef_score()`.
  static double score({int likes = 0, int saves = 0, int views = 0}) =>
      likeWeight * likes + saveWeight * saves + viewWeight * views;

  /// The tier a score falls in, matching `chef_tier_for()`. Thresholds are
  /// **inclusive**: exactly 100 is already a Line Cook.
  static ChefTier tierFor(double score) {
    if (score >= thresholds[ChefTier.masterChef]!) return ChefTier.masterChef;
    if (score >= thresholds[ChefTier.headChef]!) return ChefTier.headChef;
    if (score >= thresholds[ChefTier.sousChef]!) return ChefTier.sousChef;
    if (score >= thresholds[ChefTier.lineCook]!) return ChefTier.lineCook;
    return ChefTier.homeCook;
  }

  /// The rung above [tier], or null at the top.
  static ChefTier? nextTier(ChefTier tier) => switch (tier) {
        ChefTier.homeCook => ChefTier.lineCook,
        ChefTier.lineCook => ChefTier.sousChef,
        ChefTier.sousChef => ChefTier.headChef,
        ChefTier.headChef => ChefTier.masterChef,
        ChefTier.masterChef => null,
      };

  /// Points still needed to reach the next tier, or null once [ChefTier.masterChef]
  /// is reached. Derived from [score] rather than the stored tier, so a card
  /// cannot show "0 to go" while still displaying the lower tier.
  static double? pointsToNext(double score) {
    final next = nextTier(tierFor(score));
    if (next == null) return null;
    final target = thresholds[next]!;
    return (target - score).clamp(0, target).toDouble();
  }

  /// Progress through the *current* tier's band, 0..1. Returns 1 at the top
  /// tier. The band runs from the current tier's threshold (0 for Home Cook) to
  /// the next tier's, so it is a within-rung fraction, not a fraction of 20,000.
  static double progressToNext(double score) {
    final tier = tierFor(score);
    final next = nextTier(tier);
    if (next == null) return 1;
    final floor = thresholds[tier] ?? 0;
    final target = thresholds[next]!;
    final span = target - floor;
    if (span <= 0) return 1;
    return ((score - floor) / span).clamp(0, 1).toDouble();
  }

  /// How many more of one input would close the gap to the next tier — the
  /// "about 1,962 more saves" line. Null at the top tier.
  static int? unitsToNext(double score, double weight) {
    final gap = pointsToNext(score);
    if (gap == null || weight <= 0) return null;
    return (gap / weight).ceil();
  }

  /// The three inputs behind [score], largest contribution first, so the card's
  /// bars are ordered by what actually moved the number.
  static List<ScoreContribution> breakdown({
    int likes = 0,
    int saves = 0,
    int views = 0,
  }) {
    final rows = [
      ScoreContribution(
        label: 'likes',
        count: likes,
        weight: likeWeight,
        points: likes * likeWeight,
      ),
      ScoreContribution(
        label: 'saves',
        count: saves,
        weight: saveWeight,
        points: saves * saveWeight,
      ),
      ScoreContribution(
        label: 'views',
        count: views,
        weight: viewWeight,
        points: views * viewWeight,
      ),
    ]..sort((a, b) => b.points.compareTo(a.points));
    return rows;
  }

  /// A grouped score with no trailing `.0`. Views contribute 0.2 each, so a
  /// score can legitimately carry one decimal.
  static String label(double score) => groupedScore(score);
}
