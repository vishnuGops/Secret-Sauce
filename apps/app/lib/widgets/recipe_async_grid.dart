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
class RecipeAsyncGrid<N extends PagedRecipesNotifier> extends StatelessWidget {
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
  Widget build(BuildContext context) {
    // The ladder itself lives in the sliver version — this is the same widget
    // with its own scroll view around it, for the five surfaces that fill a
    // screen with nothing above them.
    return CustomScrollView(
      slivers: [
        RecipeAsyncSliverGrid<N>(
          provider: provider,
          empty: empty,
          showVisibility: showVisibility,
          showChef: showChef,
        ),
      ],
    );
  }
}

/// [RecipeAsyncGrid] as a sliver, for a page that already owns its scroll.
///
/// Discover's browse section is one: a grid under a masthead and three shelves,
/// all in a single `CustomScrollView`. Every state becomes a sliver —
/// loading, error and empty go in a [SliverFillRemaining] so they still centre
/// in whatever viewport is left, exactly as they did when they had the screen
/// to themselves.
class RecipeAsyncSliverGrid<N extends PagedRecipesNotifier>
    extends ConsumerWidget {
  const RecipeAsyncSliverGrid({
    super.key,
    required this.provider,
    required this.empty,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.showVisibility = false,
    this.showChef = true,
  });

  final AutoDisposeAsyncNotifierProvider<N, RecipePage> provider;
  final Widget empty;

  /// Inset around the grid. A page with its own margin passes that margin here
  /// (B059): the default 16 is right for a grid that owns the screen and wrong
  /// for one sitting under a masthead and three shelves already inset by 32 —
  /// the cards would start half a gutter left of everything above them.
  final EdgeInsets padding;

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
      // `hasScrollBody: false` on all three: when the shelves above have
      // already filled the viewport there is no remaining extent to hand a
      // scroll body, and a spinner of height zero is a page that looks done.
      loading:
          () => const SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: LoadingView(),
            ),
          ),
      error:
          (e, _) => SliverFillRemaining(
            hasScrollBody: false,
            child: ErrorView(message: friendlyError(e)),
          ),
      data:
          (page) =>
              page.recipes.isEmpty
                  ? SliverFillRemaining(hasScrollBody: false, child: empty)
                  : SliverRecipeGrid(
                    recipes: page.recipes,
                    padding: padding,
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
