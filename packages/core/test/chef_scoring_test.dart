import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

/// These tests exist to catch a **one-sided edit**.
///
/// `ChefScoring` mirrors `chef_score()` and `chef_tier_for()` in
/// `supabase/migrations/0001_init.sql`, and the expanded chef card prints the
/// mirrored numbers back to the user. If the SQL weights or thresholds change
/// and this file is not changed with them, the card starts explaining a formula
/// the database does not use — a failure nothing else in the suite would see.
///
/// The literals below are transcribed from the SQL. Do not "fix" a failure by
/// editing them to match the Dart; check which side actually moved.
void main() {
  group('formula matches chef_score()', () {
    test('weights are 3 / 5 / 0.2', () {
      expect(ChefScoring.likeWeight, 3);
      expect(ChefScoring.saveWeight, 5);
      expect(ChefScoring.viewWeight, 0.2);
    });

    test('scores the seeded Kitchen row exactly', () {
      // 1980 likes, 780 saves, 1745 views — the values SDS §10.7 pins for the
      // Secret Sauce Kitchen, whose stored chef_score is 10189.
      expect(
        ChefScoring.score(likes: 1980, saves: 780, views: 1745),
        closeTo(10189, 1e-9),
      );
    });

    test('an empty chef scores zero', () {
      expect(ChefScoring.score(), 0);
    });
  });

  group('thresholds match chef_tier_for()', () {
    test('are 100 / 1000 / 5000 / 20000', () {
      expect(ChefScoring.thresholds[ChefTier.lineCook], 100);
      expect(ChefScoring.thresholds[ChefTier.sousChef], 1000);
      expect(ChefScoring.thresholds[ChefTier.headChef], 5000);
      expect(ChefScoring.thresholds[ChefTier.masterChef], 20000);
    });

    test('are inclusive lower bounds', () {
      expect(ChefScoring.tierFor(99.9), ChefTier.homeCook);
      expect(ChefScoring.tierFor(100), ChefTier.lineCook);
      expect(ChefScoring.tierFor(999.9), ChefTier.lineCook);
      expect(ChefScoring.tierFor(1000), ChefTier.sousChef);
      expect(ChefScoring.tierFor(4999.9), ChefTier.sousChef);
      expect(ChefScoring.tierFor(5000), ChefTier.headChef);
      expect(ChefScoring.tierFor(19999.9), ChefTier.headChef);
      expect(ChefScoring.tierFor(20000), ChefTier.masterChef);
      expect(ChefScoring.tierFor(0), ChefTier.homeCook);
    });
  });

  group('gap to the next tier', () {
    test('counts points from the score, not the tier', () {
      // Kitchen: Head Chef at 10189, Master at 20000.
      expect(ChefScoring.pointsToNext(10189), closeTo(9811, 1e-9));
    });

    test('is null at the top tier', () {
      expect(ChefScoring.pointsToNext(20000), isNull);
      expect(ChefScoring.nextTier(ChefTier.masterChef), isNull);
      expect(ChefScoring.progressToNext(21000), 1);
    });

    test('progress is a fraction of the current band, not of 20000', () {
      // Head Chef band is 5000..20000, so 12500 is exactly half way.
      expect(ChefScoring.progressToNext(12500), closeTo(0.5, 1e-9));
      // Home Cook band is 0..100.
      expect(ChefScoring.progressToNext(50), closeTo(0.5, 1e-9));
    });

    test('converts the gap into saves and likes, rounding up', () {
      // 9811 / 5 = 1962.2 saves, 9811 / 3 = 3270.3 likes.
      expect(ChefScoring.unitsToNext(10189, ChefScoring.saveWeight), 1963);
      expect(ChefScoring.unitsToNext(10189, ChefScoring.likeWeight), 3271);
      expect(ChefScoring.unitsToNext(20000, ChefScoring.saveWeight), isNull);
    });
  });

  group('breakdown', () {
    test('is ordered by points contributed, not by raw count', () {
      final rows = ChefScoring.breakdown(likes: 100, saves: 90, views: 5000);
      // 300 likes-points, 450 saves-points, 1000 views-points.
      expect(rows.map((r) => r.label).toList(), ['views', 'saves', 'likes']);
      expect(rows.first.points, 1000);
      expect(rows.first.weight, 0.2);
      expect(rows.last.count, 100);
    });

    test('sums back to the score', () {
      final rows = ChefScoring.breakdown(likes: 1980, saves: 780, views: 1745);
      final total = rows.fold<double>(0, (sum, r) => sum + r.points);
      expect(total, closeTo(ChefScoring.score(likes: 1980, saves: 780, views: 1745), 1e-9));
    });
  });

  group('formatting', () {
    test('groups thousands', () {
      expect(groupedCount(0), '0');
      expect(groupedCount(999), '999');
      expect(groupedCount(1980), '1,980');
      expect(groupedCount(10189), '10,189');
      expect(groupedCount(1234567), '1,234,567');
      expect(groupedCount(-1980), '-1,980');
    });

    test('keeps a score\'s single decimal but drops a trailing zero', () {
      expect(groupedScore(10189), '10,189');
      expect(groupedScore(10189.4), '10,189.4');
      // 0.2 * 3 is 0.6000000000000001 in binary floating point.
      expect(groupedScore(ChefScoring.score(views: 3)), '0.6');
      expect(ChefScoring.label(21000), '21,000');
    });

    // `1 recipes` shipped on the leaderboard's first render (B031). It is one
    // shared helper now precisely so it cannot be got wrong per widget.
    test('drops a plural\'s trailing s at exactly one', () {
      expect(pluralNoun(1, 'recipes'), 'recipe');
      expect(pluralNoun(0, 'recipes'), 'recipes');
      expect(pluralNoun(2, 'recipes'), 'recipes');
      expect(pluralNoun(1, 'likes'), 'like');
    });

    test('countOf groups the number and agrees with it', () {
      expect(countOf(1, 'recipes'), '1 recipe');
      expect(countOf(0, 'recipes'), '0 recipes');
      expect(countOf(1980, 'likes'), '1,980 likes');
    });
  });
}
