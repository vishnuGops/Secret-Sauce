import 'dart:async';

import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/features/chefs/chefs_providers.dart';
import 'package:app/features/discover/discover_providers.dart';
import 'package:app/features/my_recipes/my_recipes_providers.dart';
import 'package:app/routing/app_router.dart';

/// True while a delete of this recipe is in flight (UX-037).
///
/// The confirm dialog closes on the first press, but the page under it stays
/// up until the RPC answers — so the owner can open the menu and confirm a
/// second time. [confirmAndDeleteRecipeById] refuses while this is set (the
/// guard, for every caller); the menus and the editor's Save watch it to render
/// disabled (the affordance). Not `autoDispose`, for `forkInFlightProvider`'s
/// reason: it is read and written with `ref.read`, and an unwatched
/// auto-disposed flag would be forgotten between the write and the next tap.
final deleteInFlightProvider = StateProvider.family<bool, String>(
  (ref, recipeId) => false,
);

/// The menu entry [RecipeOwnerMenu] carries. An enum rather than a bare
/// `String` so a second owner action (UX-037 is the first) is a new value, not
/// a new magic string.
enum RecipeOwnerAction { delete }

/// Confirm, then delete [recipe] and leave for My Recipes (UX-037).
Future<bool> confirmAndDeleteRecipe(
  BuildContext context,
  WidgetRef ref,
  Recipe recipe,
) => confirmAndDeleteRecipeById(
  context,
  ref,
  recipeId: recipe.id,
  title: recipe.title,
);

/// The one delete path — the reading page's overflow and the editor's both
/// come through here, so the two can never ask different questions or leave
/// different lists stale. Returns whether the recipe was deleted.
///
/// The editor calls this form because it holds a draft, not a [Recipe].
///
/// Authorization is not decided here: the menu is only drawn for the owner,
/// which is UX, and `recipes_delete` is the gate. A delete RLS refuses matches
/// zero rows and would report success (Gotcha 2), which is why the repository
/// asks for the row back and throws [WriteDeniedException] on an empty answer.
Future<bool> confirmAndDeleteRecipeById(
  BuildContext context,
  WidgetRef ref, {
  required String recipeId,
  required String title,
}) async {
  final inFlight = ref.read(deleteInFlightProvider(recipeId).notifier);
  if (inFlight.state) return false;

  final confirmed = await showDialog<bool>(
    context: context,
    // Gotcha 23: from a shell screen a default dialog attaches under the
    // chrome. The detail page and the editor are root routes today, but this
    // is a shared action and the next caller may not be.
    useRootNavigator: true,
    builder: (ctx) => _DeleteRecipeDialog(title: title),
  );
  if (confirmed != true || !context.mounted) return false;
  // Re-checked after the dialog: two confirm dialogs opened before either was
  // answered would otherwise both get this far.
  if (inFlight.state) return false;
  inFlight.state = true;

  // Captured before the await. The container rather than `ref`: `router.go`
  // below disposes the page that owns `ref`, and if the owner leaves while the
  // request is out, a `ref.invalidate` on the dead element throws.
  final messenger = ScaffoldMessenger.of(context);
  final router = GoRouter.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  try {
    await container.read(recipeRepositoryProvider).delete(recipeId);
    // Every list that could still be holding the row. Most of these are
    // `autoDispose` and are gone once `/my` replaces the page, but My
    // Recipes' tabs sit *under* a detail page opened from them and stay alive
    // — a deleted card on the tab you land on is the bug this avoids.
    // `recipeProvider(recipeId)` is deliberately **not** invalidated: the page
    // is still mounted, so it would refetch a row that no longer exists and
    // flash an error before the navigation lands. Leaving disposes it.
    // `categoryRecipesProvider` and `chefRecipesProvider` live in screen-level
    // `ProviderScope`s; from here the call reaches the root instance only,
    // which is a no-op when none exists (`invalidate` never creates one).
    for (final provider in <ProviderOrFamily>[
      myRecipesProvider,
      sharedWithMeProvider,
      savedRecipesProvider,
      popularRecipesProvider,
      trendingRecipesProvider,
      recentRecipesProvider,
      categoryRecipesProvider,
      searchResultsProvider,
      quickShelfProvider,
      projectsShelfProvider,
      mostForkedShelfProvider,
      publicRecipeCountProvider,
      chefRecipesProvider,
    ]) {
      container.invalidate(provider);
    }
    messenger.showSnackBar(const SnackBar(content: Text('Recipe deleted')));
    // Only if the caller is still on screen: an owner who walked away while
    // the request was out is not dragged back to My Recipes.
    if (context.mounted) router.go(Routes.myRecipes);
    return true;
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Could not delete — ${friendlyError(e)}')),
    );
    return false;
  } finally {
    // The notifier, not `ref` — the fork action's reason.
    inFlight.state = false;
  }
}

/// "Delete this recipe?" — the copy states what `0001_init.sql` does.
///
/// Versions, likes, saves, ratings, shares and views are `on delete cascade`
/// and go with it. Forks are other cooks' recipes and stay:
/// `forked_from_recipe_id` / `forked_from_version_id` are `on delete set
/// null`, so they survive and lose only their link back here — which is the
/// sentence the second paragraph says.
class _DeleteRecipeDialog extends StatelessWidget {
  const _DeleteRecipeDialog({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Delete this recipe?'),
      // Scrollable: at 2.0× on a phone the two paragraphs outgrow the dialog.
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '“$title” and its version history, ratings, likes and saves '
              'will be deleted. This cannot be undone.',
            ),
            const SizedBox(height: AppSpacing.smPlus),
            const Text(
              'Forks other cooks made of it are theirs and are kept, but they '
              'will no longer link back to this recipe.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    );
  }
}

/// The owner's overflow ("More") on the reading page — UX-037's Delete lives
/// here rather than beside Share and Edit, so a destructive action is always
/// one deliberate step further away than the everyday ones.
///
/// [style] lets each layout dress the trigger as its neighbours: outlined in
/// the expanded header band, the scrim button on the compact cover.
class RecipeOwnerMenu extends ConsumerWidget {
  const RecipeOwnerMenu({super.key, required this.recipe, this.style});

  final Recipe recipe;
  final ButtonStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deleting = ref.watch(deleteInFlightProvider(recipe.id));
    return PopupMenuButton<RecipeOwnerAction>(
      tooltip: 'More',
      icon: const Icon(Icons.more_vert),
      style: style,
      // Gotcha 23, as for the dialog.
      useRootNavigator: true,
      onSelected: (action) {
        switch (action) {
          case RecipeOwnerAction.delete:
            unawaited(confirmAndDeleteRecipe(context, ref, recipe));
        }
      },
      itemBuilder:
          (context) => [deleteRecipeMenuItem(context, enabled: !deleting)],
    );
  }
}

/// The error-coloured "Delete recipe" entry, shared by [RecipeOwnerMenu] and
/// the editor's app-bar overflow so both read the same.
PopupMenuItem<RecipeOwnerAction> deleteRecipeMenuItem(
  BuildContext context, {
  bool enabled = true,
}) {
  final scheme = Theme.of(context).colorScheme;
  return PopupMenuItem(
    value: RecipeOwnerAction.delete,
    enabled: enabled,
    child: Row(
      children: [
        Icon(Icons.delete_outline, color: scheme.error),
        const SizedBox(width: AppSpacing.smPlus),
        // Flexible: a menu is at most 280px wide, and "Delete recipe" at 2.0×
        // is close to that on its own (Gotcha 21's unbounded-child rule).
        Flexible(
          child: Text('Delete recipe', style: TextStyle(color: scheme.error)),
        ),
      ],
    ),
  );
}
