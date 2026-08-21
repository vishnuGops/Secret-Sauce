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
