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
///
/// Cook mode reads this same provider, so a recipe scaled to 8 says 8 on both
/// surfaces. Phase 28 added a third reader — the nutrition label's batch line —
/// on the same terms: one number, one source (B066).
final selectedServingsProvider = StateProvider.autoDispose.family<int?, String>(
  (ref, id) => null,
);

/// Which pane `RailPanel` is showing.
///
/// Lives here rather than beside the widget so the provider file stays the one
/// place the detail screen's state is declared, and so `RailPanel` and
/// `recipe_detail_compact.dart`'s jump-chip tear-off can both reach it without
/// importing each other.
enum RailTab { ingredients, nutrition }

/// The selected rail tab, per recipe.
///
/// `autoDispose`, so every visit starts on Ingredients — the ask names that as
/// the default, and a tab that remembered itself across visits would open a
/// recipe on a label the reader did not ask for. Family-keyed like its two
/// siblings above.
final railTabProvider = StateProvider.autoDispose.family<RailTab, String>(
  (ref, id) => RailTab.ingredients,
);

/// Ingredient ids the user has ticked off in the v2 rail, per recipe.
///
/// Deliberately **not** autoDispose: mid-cook you leave the screen (look
/// something up, answer a message) and come back — losing the checklist on
/// return would make it useless. Session-scoped for now; the design copy
/// promises device persistence, which needs a storage decision (BL: persist to
/// shared_preferences) before the label can claim it.
final checkedIngredientsProvider = StateProvider.family<Set<String>, String>(
  (ref, recipeId) => const {},
);

/// Step ids ticked off in the v2 method column, per recipe. Same lifetime
/// reasoning as [checkedIngredientsProvider].
final doneStepsProvider = StateProvider.family<Set<String>, String>(
  (ref, recipeId) => const {},
);
