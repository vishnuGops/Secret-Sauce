import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final popularRecipesProvider = FutureProvider.autoDispose<List<Recipe>>((ref) {
  return ref.watch(discoverRepositoryProvider).popular();
});

final trendingRecipesProvider = FutureProvider.autoDispose<List<Recipe>>((ref) {
  return ref.watch(discoverRepositoryProvider).trending();
});

final recentRecipesProvider = FutureProvider.autoDispose<List<Recipe>>((ref) {
  return ref.watch(discoverRepositoryProvider).recent();
});

/// Current search query for Discover.
final searchQueryProvider = StateProvider.autoDispose<String>((ref) => '');

/// How long typing must pause before a search actually goes to the server.
///
/// The field writes `searchQueryProvider` on every `onChanged`, which
/// invalidates [searchResultsProvider] — so without this, typing "chicken"
/// issued seven `recipes_search` RPCs and threw six of them away (OPT-P8).
/// 300 ms is below the point where the delay reads as lag and above a fast
/// typist's inter-key gap.
const kSearchDebounce = Duration(milliseconds: 300);

final searchResultsProvider =
    FutureProvider.autoDispose<List<Recipe>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  // Matches `SupabaseDiscoverRepository.search`, which also short-circuits an
  // empty query — and skips the debounce wait when clearing the field.
  if (query.trim().isEmpty) return const <Recipe>[];

  // The next keystroke disposes this build; cancel the timer and bail rather
  // than letting a superseded query reach the network. `ref` must not be
  // touched after disposal, hence the early return instead of a `read`.
  var superseded = false;
  final debounce = Completer<void>();
  final timer = Timer(kSearchDebounce, () {
    if (!debounce.isCompleted) debounce.complete();
  });
  ref.onDispose(() {
    superseded = true;
    timer.cancel();
    if (!debounce.isCompleted) debounce.complete();
  });

  await debounce.future;
  if (superseded) return const <Recipe>[];

  return ref.read(discoverRepositoryProvider).search(query);
});
