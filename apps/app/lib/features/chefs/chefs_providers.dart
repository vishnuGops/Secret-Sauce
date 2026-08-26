import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How many chefs one page of the leaderboard holds — the panel's `TOP 25`.
const kLeaderboardPageSize = 25;

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
final chefsLeaderboardProvider = FutureProvider.autoDispose<List<ChefStanding>>(
  (ref) {
    final pages = ref.watch(leaderboardPagesProvider);
    return ref
        .watch(chefRepositoryProvider)
        .leaderboard(limit: kLeaderboardPageSize * pages);
  },
);

/// How many chefs sit on each tier — the five tiles across the hero.
///
/// Kept separate from [chefsLeaderboardProvider] rather than tallied from its
/// rows: the board is one page of the ranking, so counting tiers from it would
/// describe the top 25 while claiming to describe all 148.
final chefTierCountsProvider = FutureProvider.autoDispose<Map<ChefTier, int>>((
  ref,
) {
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

final boardSortProvider = StateProvider.autoDispose<BoardSort>(
  (ref) => BoardSort.score,
);

final chefsWindowProvider = StateProvider.autoDispose<ChefsWindow>(
  (ref) => ChefsWindow.allTime,
);

/// Total chefs on the board — the denominator in "Rank 2 of 148".
///
/// Derived from [chefTierCountsProvider] rather than fetched (OPT-P10): the
/// tier counts cover exactly the same population — profiles with at least one
/// public recipe — so the total is their sum, and asking the server for it
/// again was a sixth round trip for a number the first five already contained.
/// Four call sites share the one request.
///
/// Read with `valueOrNull` at the call site: the header drops to "Rank 2"
/// rather than blocking the whole card on a count.
final chefCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final counts = await ref.watch(chefTierCountsProvider.future);
  return counts.values.fold<int>(0, (sum, n) => sum + n);
});

/// Everything `/chef/:id` needs about the chef themself: the profile row and
/// the leaderboard standing, fetched together (Phase 30).
///
/// The two are deliberately separate reads with different failure meanings. The
/// **profile** is the page — without it there is no chef and the route is a 404.
/// The **standing** is null for a real profile that simply holds no rank
/// (private-only, brand-new, no public recipe), which is a state the page
/// renders rather than an error.
class ChefPageData {
  const ChefPageData({required this.profile, this.standing});

  final Profile profile;

  /// Null when this profile is not on the board — see [ChefRepository.standing].
  final ChefStanding? standing;
}

/// Profile + standing for one chef.
///
/// Both requests are started before either is awaited (the OPT-P10 shape) —
/// they are independent, so awaiting the profile first would cost the sum of two
/// round trips instead of the slower one.
///
/// Unlike the dialog this replaced, **neither read is swallowed**: the board
/// used to hand the card a `ChefStanding` it already had, so a failed fetch cost
/// one section; here the page has a uuid and nothing else, so a failure is a
/// failure and the screen shows a retry.
final chefPageProvider = FutureProvider.autoDispose.family<
  ChefPageData,
  String
>((ref, chefId) async {
  final profiles = ref.watch(profileRepositoryProvider);
  final chefs = ref.watch(chefRepositoryProvider);

  // `Future.wait`, not two sequential awaits over two started futures.
  // Starting both and awaiting them one after the other leaves the second
  // with **no handler attached** until the first completes, so a fast failure
  // there is delivered as an unhandled async error before anything can catch
  // it — the provider still reports it, and the app also logs a zone error
  // for the same exception. `Future.wait` subscribes to both up front and
  // rethrows the first failure, which keeps the parallelism without the
  // window.
  final results = await Future.wait<Object?>([
    profiles.getById(chefId),
    chefs.standing(chefId),
  ]);

  final profile = results[0] as Profile?;
  if (profile == null) {
    // The one genuine 404: a uuid with no profile behind it. A *null
    // standing* is not this — see [ChefPageData].
    throw StateError('No chef with id $chefId');
  }
  return ChefPageData(profile: profile, standing: results[1] as ChefStanding?);
});

/// Which chef `/chef/:id` is showing — the argument [ChefRecipesNotifier] pages
/// against. **Meant to be overridden**, never read at its default.
///
/// Not a `.family` on the notifier: a family notifier has to extend
/// `AutoDisposeFamilyAsyncNotifier`, which is not a [PagedRecipesNotifier], so
/// it could not use the shared `RecipeAsyncSliverGrid` ladder at all — and
/// re-implementing that ladder is what OPT-A7 consolidated away.
///
/// `ChefPage` supplies it by wrapping its subtree in a `ProviderScope` that
/// overrides this **and** [chefRecipesProvider], so each page gets its own
/// notifier bound to its own chef. The alternative — writing a `StateProvider`
/// from `initState` — throws `Tried to modify a provider while the widget tree
/// was building`, which is how this arrived at the scoped form.
///
/// The default is empty so a stray read fetches nothing rather than paging some
/// arbitrary chef, exactly as an empty search query does.
final viewedChefIdProvider = Provider<String>((ref) => '');

/// One chef's public recipes, paged — the grid on `/chef/:id`.
class ChefRecipesNotifier extends PagedRecipesNotifier {
  /// The chef this build is serving. Captured once, so `Load more` cannot page
  /// one chef's offsets against another chef's results.
  String _chefId = '';

  @override
  Future<RecipePage> firstPage() {
    // Synchronous, before any `await`: this is the build phase, and it is what
    // makes a new chef a new build.
    _chefId = ref.watch(viewedChefIdProvider);
    if (_chefId.isEmpty) return Future.value(const RecipePage());
    return super.firstPage();
  }

  @override
  Future<List<Recipe>> fetchPage({required int limit, required int offset}) {
    return ref
        .read(recipeRepositoryProvider)
        .listByChef(_chefId, limit: limit, offset: offset);
  }
}

final chefRecipesProvider =
    AsyncNotifierProvider.autoDispose<ChefRecipesNotifier, RecipePage>(
      ChefRecipesNotifier.new,
    );
