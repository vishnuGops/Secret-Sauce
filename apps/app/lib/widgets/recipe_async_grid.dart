import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/widgets/recipe_grid.dart';

/// A paged recipe list rendered end to end: loading, error, empty, the grid,
/// and the `Load more` control (OPT-P9).
///
/// One widget for all six surfaces — Discover's four lists and My Recipes' two
/// tabs — because they had already grown two identical copies of the
/// AsyncValue → Loading/Error/Empty/`RecipeGrid` ladder, and pagination would
/// have made that three (OPT-A7's grid item).
///
/// Generic over the notifier so each screen can pass its own provider: Riverpod
/// provider types are invariant, so a plain
/// `AutoDisposeAsyncNotifierProvider<PagedRecipesNotifier, RecipePage>`
/// parameter would reject every concrete one.
class RecipeAsyncGrid<N extends PagedRecipesNotifier> extends ConsumerWidget {
  const RecipeAsyncGrid({
    super.key,
    required this.provider,
    required this.empty,
    this.showVisibility = false,
    this.showChef = true,
  });

  final AutoDisposeAsyncNotifierProvider<N, RecipePage> provider;

  /// Shown instead of the grid when the first page comes back with no rows.
  final Widget empty;

  final bool showVisibility;
  final bool showChef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(provider);
    return async.when(
      // A rebuild (a new search query) keeps the previous rows on screen until
      // the new ones arrive, instead of flashing a spinner between every
      // keystroke's worth of results.
      skipLoadingOnReload: true,
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(message: friendlyError(e)),
      data:
          (page) =>
              page.recipes.isEmpty
                  ? empty
                  : RecipeGrid(
                    recipes: page.recipes,
                    showVisibility: showVisibility,
                    showChef: showChef,
                    footer:
                        page.hasMore
                            ? _LoadMoreButton(
                              loading: page.loadingMore,
                              onPressed:
                                  () => ref.read(provider.notifier).loadMore(),
                            )
                            : null,
                  ),
    );
  }
}

/// The `Load more` control. A button rather than infinite scroll by product
/// decision: an explicit tap is the only version that works identically on a
/// phone flick and a desktop scrollbar, and it never fetches a page the reader
/// did not ask for.
class _LoadMoreButton extends StatelessWidget {
  const _LoadMoreButton({required this.loading, required this.onPressed});

  final bool loading;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        child: OutlinedButton.icon(
          onPressed:
              loading
                  ? null
                  : () async {
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      await onPressed();
                    } catch (e) {
                      // The rows already loaded survive a failed page (see
                      // `PagedRecipesNotifier.loadMore`), so this is a snackbar
                      // rather than an error screen.
                      messenger.showSnackBar(
                        SnackBar(content: Text(friendlyError(e))),
                      );
                    }
                  },
          icon:
              loading
                  ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Icon(Icons.expand_more),
          label: Text(loading ? 'Loading…' : 'Load more'),
        ),
      ),
    );
  }
}
