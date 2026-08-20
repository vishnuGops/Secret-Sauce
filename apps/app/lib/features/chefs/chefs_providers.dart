import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How many chefs one page of the leaderboard holds — the panel's `TOP 25`.
const kLeaderboardPageSize = 25;

/// How many recipes the expanded chef card lists under "Top recipes".
const kChefTopRecipes = 3;

/// How many chefs each rail shows.
const kChefRailLength = 10;

/// How many pages of the board have been asked for. `Show all` bumps it.
///
/// A plain count rather than an accumulating list: the RPC ranks the whole table
/// and returns a prefix, so asking for more is a wider first page, not a second
/// one to stitch on. Re-reading 50 ranked rows costs less than the bookkeeping
/// to avoid it, and it cannot drift out of order the way a stitched list can.
final leaderboardPagesProvider = StateProvider.autoDispose<int>((ref) => 1);

/// The chefs leaderboard. Signed-out safe: `chefs_leaderboard` is granted to
/// `anon`, so this resolves without a session.
final chefsLeaderboardProvider =
    FutureProvider.autoDispose<List<ChefStanding>>((ref) {
  final pages = ref.watch(leaderboardPagesProvider);
  return ref
      .watch(chefRepositoryProvider)
      .leaderboard(limit: kLeaderboardPageSize * pages);
});

/// How many chefs sit on each tier — the five tiles across the hero.
///
/// Kept separate from [chefsLeaderboardProvider] rather than tallied from its
/// rows: the board is one page of the ranking, so counting tiers from it would
/// describe the top 25 while claiming to describe all 148.
final chefTierCountsProvider =
    FutureProvider.autoDispose<Map<ChefTier, int>>((ref) {
  return ref.watch(chefRepositoryProvider).tierCounts();
});

/// The board's three orderings. Only [BoardSort.score] has data behind it.
///
/// `momentum` needs a score delta over a window and `newest` needs the chef's
/// join date, neither of which `chefs_leaderboard` returns. Both are rendered
/// and disabled rather than hidden — the draft's board has three tabs, and a
/// control that is visibly not ready reads better than a feature that silently
/// does not exist.
// TODO(board): enable both once the windowed leaderboard RPC lands (see
// EXECUTION-PLAN Phase 23, D4).
enum BoardSort {
  score('Score', enabled: true),
  momentum('Momentum', enabled: false),
  newest('New', enabled: false);

  const BoardSort(this.label, {required this.enabled});

  final String label;
  final bool enabled;
}

/// The hero's time filter. Same story as [BoardSort]: the windows are real
/// queries, but nothing computes them yet.
// TODO(hero): enable `month` / `week` with the windowed leaderboard RPC.
enum ChefsWindow {
  allTime('All time', enabled: true),
  month('Month', enabled: false),
  week('Week', enabled: false);

  const ChefsWindow(this.label, {required this.enabled});

  final String label;
  final bool enabled;
}

final boardSortProvider =
    StateProvider.autoDispose<BoardSort>((ref) => BoardSort.score);

final chefsWindowProvider =
    StateProvider.autoDispose<ChefsWindow>((ref) => ChefsWindow.allTime);

/// Total chefs on the board — the denominator in "Rank 2 of 148".
///
/// Read with `valueOrNull` at the call site: the header drops to "Rank 2"
/// rather than blocking the whole card on a count.
final chefCountProvider = FutureProvider.autoDispose<int>((ref) {
  return ref.watch(chefRepositoryProvider).chefCount();
});

/// Everything the expanded chef card needs beyond the [ChefStanding] the board
/// already holds.
class ChefDetail {
  const ChefDetail({
    this.profile,
    this.topRecipes = const [],
    this.topRecipesFailed = false,
  });

  /// The chef's profile row, for the "joined" date. Null when the read finds
  /// nothing — the card simply omits that clause.
  final Profile? profile;

  /// Public recipes ordered by score contribution, from `chef_top_recipes`.
  final List<Recipe> topRecipes;

  /// True when the RPC itself failed. Kept separate from "no recipes" because
  /// the two need different copy — and because a database that has not had
  /// `0001_init.sql` re-applied has no `chef_top_recipes` at all.
  final bool topRecipesFailed;
}

/// Profile + top recipes for one chef, fetched together.
///
/// The recipe list is deliberately non-fatal: the rest of the card is derived
/// from data the board already has, so a missing RPC costs one section instead
/// of the whole dialog.
final chefDetailProvider =
    FutureProvider.autoDispose.family<ChefDetail, String>((ref, chefId) async {
  final chefs = ref.watch(chefRepositoryProvider);
  final profiles = ref.watch(profileRepositoryProvider);

  final profile = await profiles.getById(chefId);
  try {
    final recipes = await chefs.topRecipes(chefId, limit: kChefTopRecipes);
    return ChefDetail(profile: profile, topRecipes: recipes);
  } catch (_) {
    return ChefDetail(profile: profile, topRecipesFailed: true);
  }
});
