import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How many chefs the leaderboard requests. Pagination is deferred — the RPC
/// already takes an offset, so it is a UI change when it is needed.
const kLeaderboardLimit = 50;

/// The chefs leaderboard. Signed-out safe: `chefs_leaderboard` is granted to
/// `anon`, so this resolves without a session.
final chefsLeaderboardProvider =
    FutureProvider.autoDispose<List<ChefStanding>>((ref) {
  return ref.watch(chefRepositoryProvider).leaderboard(limit: kLeaderboardLimit);
});
