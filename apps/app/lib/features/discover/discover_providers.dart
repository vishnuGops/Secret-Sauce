import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Discover's four lists are paged (OPT-P9): each starts at one
/// [kRecipePageSize] page and grows by one more per `Load more`. The heavy
/// lifting — offsets, de-duplication, the in-flight flag — is
/// [PagedRecipesNotifier] in `core`; these only say which repository call to
/// make.

class PopularRecipesNotifier extends PagedRecipesNotifier {
  @override
  Future<List<Recipe>> fetchPage({required int limit, required int offset}) {
    return ref
        .read(discoverRepositoryProvider)
        .popular(limit: limit, offset: offset);
  }
}

final popularRecipesProvider =
    AsyncNotifierProvider.autoDispose<PopularRecipesNotifier, RecipePage>(
      PopularRecipesNotifier.new,
    );

class TrendingRecipesNotifier extends PagedRecipesNotifier {
  @override
  Future<List<Recipe>> fetchPage({required int limit, required int offset}) {
    return ref
        .read(discoverRepositoryProvider)
        .trending(limit: limit, offset: offset);
  }
}

final trendingRecipesProvider =
    AsyncNotifierProvider.autoDispose<TrendingRecipesNotifier, RecipePage>(
      TrendingRecipesNotifier.new,
    );

class RecentRecipesNotifier extends PagedRecipesNotifier {
  @override
  Future<List<Recipe>> fetchPage({required int limit, required int offset}) {
    return ref
        .read(discoverRepositoryProvider)
        .recent(limit: limit, offset: offset);
  }
}

final recentRecipesProvider =
    AsyncNotifierProvider.autoDispose<RecentRecipesNotifier, RecipePage>(
      RecentRecipesNotifier.new,
    );

/// How many cards one shelf holds (Phase 26).
///
/// Not [kRecipePageSize]: a shelf is a *sample*, not a list — it scrolls
/// sideways, has no Load more, and everything past the first few cards is
/// already behind a drag. Twelve is four screens' worth of paging at three
/// cards a press and still one request.
const int kShelfLength = 12;

/// **01 · UNDER 30** — quick recipes, best-rated first.
final quickShelfProvider = FutureProvider.autoDispose<List<Recipe>>(
  (ref) => ref.watch(discoverRepositoryProvider).quick(limit: kShelfLength),
);

/// **02 · WEEKEND PROJECTS** — long or hard, most-saved first.
final projectsShelfProvider = FutureProvider.autoDispose<List<Recipe>>(
  (ref) => ref.watch(discoverRepositoryProvider).projects(limit: kShelfLength),
);

/// **03 · MOST FORKED** — ranked by public descendants.
final mostForkedShelfProvider = FutureProvider.autoDispose<List<Recipe>>(
  (ref) =>
      ref.watch(discoverRepositoryProvider).mostForked(limit: kShelfLength),
);

/// The masthead's one statistic. A `HEAD` request — no rows cross the wire.
final publicRecipeCountProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(discoverRepositoryProvider).publicCount(),
);

/// How the browse grid under the shelves is ordered.
///
/// These are Discover's three original tabs, demoted to a sort. The shelves
/// answer "what am I in the mood for"; this answers "show me everything", and
/// it is the same corpus either way — which is exactly why it stopped being a
/// tab bar competing with the shelves for the top of the page.
enum BrowseSort {
  topRated('Top rated'),
  trending('Trending'),
  newest('Newest');

  const BrowseSort(this.label);

  final String label;
}

final browseSortProvider = StateProvider.autoDispose<BrowseSort>(
  (ref) => BrowseSort.topRated,
);

/// Current search query for Discover.
final searchQueryProvider = StateProvider.autoDispose<String>((ref) => '');

/// How long typing must pause before a search actually goes to the server.
///
/// The field writes [searchQueryProvider] on every `onChanged`, which rebuilds
/// [searchResultsProvider] — so without this, typing "chicken" issued seven
/// `recipes_search` RPCs and threw six of them away (OPT-P8). 300 ms is below
/// the point where the delay reads as lag and above a fast typist's inter-key
/// gap.
const kSearchDebounce = Duration(milliseconds: 300);

class SearchRecipesNotifier extends PagedRecipesNotifier {
  /// The query this build is serving. Captured once so `Load more` cannot page
  /// one query's offsets against another query's results.
  String _query = '';

  @override
  Future<RecipePage> firstPage() async {
    // Synchronous, before any `await`: this is the build phase, and it is what
    // makes a new query a new build.
    _query = ref.watch(searchQueryProvider);

    // Matches `SupabaseDiscoverRepository.search`, which also short-circuits an
    // empty query — and skips the debounce wait when clearing the field.
    if (_query.trim().isEmpty) return const RecipePage();
    if (!await _waitForPause()) return const RecipePage();
    return super.firstPage();
  }

  @override
  Future<List<Recipe>> fetchPage({required int limit, required int offset}) {
    return ref
        .read(discoverRepositoryProvider)
        .search(_query, limit: limit, offset: offset);
  }

  /// Waits out [kSearchDebounce]. Returns false when the next keystroke
  /// disposed this build first — the superseded query then returns without
  /// touching the network, rather than arriving late over a newer result.
  Future<bool> _waitForPause() async {
    var superseded = false;
    final gate = Completer<void>();
    final timer = Timer(kSearchDebounce, () {
      if (!gate.isCompleted) gate.complete();
    });
    ref.onDispose(() {
      superseded = true;
      timer.cancel();
      if (!gate.isCompleted) gate.complete();
    });

    await gate.future;
    return !superseded;
  }
}

final searchResultsProvider =
    AsyncNotifierProvider.autoDispose<SearchRecipesNotifier, RecipePage>(
      SearchRecipesNotifier.new,
    );
