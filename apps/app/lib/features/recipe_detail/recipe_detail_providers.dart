import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Full recipe (with nested content) by id.
///
/// View logging deliberately does **not** live here (OPT-P7) — this provider is
/// invalidated by every like, save, rating and retry, so a visitor who liked and
/// rated one recipe appended three or four rows to the append-only
/// `recipe_views` log for a single visit. See [recipeViewLoggerProvider].
final recipeProvider = FutureProvider.autoDispose.family<Recipe, String>((
  ref,
  id,
) {
  return ref.watch(recipeRepositoryProvider).getById(id);
});

/// Logs exactly one view per screen visit (OPT-P7).
///
/// Separate from [recipeProvider] so that invalidating the recipe — which the
/// detail screen does on every engagement — does not re-log. `autoDispose`
/// gives the "per visit" part: it is disposed when the screen leaves and runs
/// again on the next entry.
///
/// `recipes.view_count` only counts a user's **first** row per recipe (B012), so
/// the extra rows never inflated the counter — but `recipe_views` is an
/// append-only log and the rows are real, so the waste was real too.
///
/// Never throws: view logging is best-effort and must not put the detail screen
/// into an error state.
final recipeViewLoggerProvider = FutureProvider.autoDispose
    .family<void, String>((ref, id) async {
      try {
        await ref.read(recipeRepositoryProvider).logView(id);
      } catch (_) {
        // Ignored on purpose — a failed view log is not worth a visible error.
      }
    });

/// Version history for a recipe, newest first.
final recipeVersionsProvider = FutureProvider.autoDispose
    .family<List<RecipeVersion>, String>((ref, id) {
      return ref.watch(recipeRepositoryProvider).versions(id);
    });

/// The signed-in user's own star rating for a recipe (null = not rated / signed out).
final myRatingProvider = FutureProvider.autoDispose.family<double?, String>((
  ref,
  id,
) {
  ref.watch(currentUserIdProvider);
  return ref.watch(recipeRepositoryProvider).myRating(id);
});

/// Whether the signed-in user has liked / saved this recipe (false = signed out).
/// Both watch [currentUserIdProvider] so signing in or out re-resolves them, the
/// same way [myRatingProvider] does.
final myLikedProvider = FutureProvider.autoDispose.family<bool, String>((
  ref,
  id,
) {
  ref.watch(currentUserIdProvider);
  return ref.watch(recipeRepositoryProvider).myLiked(id);
});

final mySavedProvider = FutureProvider.autoDispose.family<bool, String>((
  ref,
  id,
) {
  ref.watch(currentUserIdProvider);
  return ref.watch(recipeRepositoryProvider).mySaved(id);
});

/// Selected servings for the detail screen's scaler (defaults to recipe servings).
final selectedServingsProvider = StateProvider.autoDispose.family<int?, String>(
  (ref, id) => null,
);
