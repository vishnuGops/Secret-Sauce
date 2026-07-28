import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final myRecipesProvider = FutureProvider.autoDispose<List<Recipe>>((ref) {
  return ref.watch(recipeRepositoryProvider).listMine();
});

final sharedWithMeProvider = FutureProvider.autoDispose<List<Recipe>>((ref) {
  return ref.watch(recipeRepositoryProvider).listSharedWithMe();
});
