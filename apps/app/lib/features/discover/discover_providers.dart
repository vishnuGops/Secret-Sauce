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

final searchResultsProvider = FutureProvider.autoDispose<List<Recipe>>((ref) {
  final query = ref.watch(searchQueryProvider);
  return ref.watch(discoverRepositoryProvider).search(query);
});
