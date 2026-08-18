import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Full recipe (with nested content) by id.
final recipeProvider =
    FutureProvider.autoDispose.family<Recipe, String>((ref, id) async {
  final repo = ref.watch(recipeRepositoryProvider);
  final recipe = await repo.getById(id);
  // Fire-and-forget view logging for trending.
  unawaited(repo.logView(id));
  return recipe;
});

/// Version history for a recipe, newest first.
final recipeVersionsProvider =
    FutureProvider.autoDispose.family<List<RecipeVersion>, String>((ref, id) {
  return ref.watch(recipeRepositoryProvider).versions(id);
});

/// The signed-in user's own star rating for a recipe (null = not rated / signed out).
final myRatingProvider =
    FutureProvider.autoDispose.family<double?, String>((ref, id) {
  ref.watch(currentUserIdProvider);
  return ref.watch(recipeRepositoryProvider).myRating(id);
});

/// Selected servings for the detail screen's scaler (defaults to recipe servings).
final selectedServingsProvider =
    StateProvider.autoDispose.family<int?, String>((ref, id) => null);
