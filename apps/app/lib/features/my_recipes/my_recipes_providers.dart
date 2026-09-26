import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Every My Recipes tab is paged (OPT-P9). They used to be unbounded reads —
/// a vault with 400 recipes decoded all 400 on every visit — and they are the
/// lists most likely to grow, since nothing about them is ranked or windowed.

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

/// The Saved tab (UX-020): recipes the reader bookmarked, newest save first.
/// Save used to write a `recipe_saves` row that no screen ever listed.
///
/// **Not refreshed by being revisited.** Recipe detail is pushed on the root
/// navigator *over* the shell, so this tab stays mounted — and this provider
/// stays alive — while the reader unsaves the recipe they opened from it. The
/// save toggle on the detail page therefore invalidates this provider itself.
class SavedRecipesNotifier extends PagedRecipesNotifier {
  @override
  Future<List<Recipe>> fetchPage({required int limit, required int offset}) {
    return ref
        .read(recipeRepositoryProvider)
        .listSaved(limit: limit, offset: offset);
  }
}

final savedRecipesProvider =
    AsyncNotifierProvider.autoDispose<SavedRecipesNotifier, RecipePage>(
      SavedRecipesNotifier.new,
    );
