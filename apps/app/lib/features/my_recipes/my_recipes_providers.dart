import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Both My Recipes tabs are paged (OPT-P9). They used to be unbounded reads —
/// a vault with 400 recipes decoded all 400 on every visit — and they are the
/// two lists most likely to grow, since nothing about them is ranked or
/// windowed.

class MyRecipesNotifier extends PagedRecipesNotifier {
  @override
  Future<List<Recipe>> fetchPage({required int limit, required int offset}) {
    return ref
        .read(recipeRepositoryProvider)
        .listMine(limit: limit, offset: offset);
  }
}

final myRecipesProvider =
    AsyncNotifierProvider.autoDispose<MyRecipesNotifier, RecipePage>(
  MyRecipesNotifier.new,
);

class SharedWithMeNotifier extends PagedRecipesNotifier {
  @override
  Future<List<Recipe>> fetchPage({required int limit, required int offset}) {
    return ref
        .read(recipeRepositoryProvider)
        .listSharedWithMe(limit: limit, offset: offset);
  }
}

final sharedWithMeProvider =
    AsyncNotifierProvider.autoDispose<SharedWithMeNotifier, RecipePage>(
  SharedWithMeNotifier.new,
);
