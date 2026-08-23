import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:app/routing/app_router.dart';

/// A responsive grid of [RecipeCard]s that navigates to detail on tap.
///
/// The column count comes from the width actually available, not from a
/// breakpoint: as many columns as can each hold `kRecipeCardMinWidth`, with
/// every card capped at `kRecipeCardMaxWidth` and the row centred once they
/// are. Widening the window therefore adds a column instead of stretching the
/// cards, and because the rule is a pure function of width
/// ([FlowGridMetrics.fit], recomputed on every layout) a drag-resize reflows
/// continuously rather than jumping at 600 and 1000.
/// [RecipeGrid] as a **sliver**, for pages that put a grid inside a scroll they
/// do not own — Discover, where three shelves and a masthead sit above it.
///
/// This is where the layout actually lives; `RecipeGrid` is the box-widget
/// wrapper around it. A grid cannot simply be dropped into a page's `ListView`:
/// `CustomScrollView` is a scrollable, and nesting one inside another either
/// takes an unbounded height or steals the drag.
///
/// Measures with a [SliverLayoutBuilder] — `crossAxisExtent` is the sliver
/// world's `maxWidth`, and the column count is a pure function of it exactly as
/// in the box version.
class SliverRecipeGrid extends StatelessWidget {
  const SliverRecipeGrid({
    super.key,
    required this.recipes,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.showVisibility = false,
    this.showChef = true,
    this.footer,
  });

  final List<Recipe> recipes;
  final EdgeInsets padding;
  final bool showVisibility;
  final bool showChef;

  /// Rendered below the last row, sharing the grid's gutter — see
  /// [RecipeGrid.footer].
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final metrics = FlowGridMetrics.fit(
          available: constraints.crossAxisExtent - padding.horizontal,
          minTileWidth: kRecipeCardMinWidth,
          maxTileWidth: kRecipeCardMaxWidth,
          spacing: AppSpacing.md,
        );
        // The gutter is what keeps the cards at their maximum width: the
        // delegate always divides the full cross-axis extent between the
        // columns, so the only way to cap a tile is to hand the grid less
        // width to divide.
        final gridPadding = padding.copyWith(
          left: padding.left + metrics.gutter,
          right: padding.right + metrics.gutter,
        );
        return SliverMainAxisGroup(
          slivers: [
            SliverPadding(
              padding: gridPadding,
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: metrics.columns,
                  mainAxisSpacing: AppSpacing.md,
                  crossAxisSpacing: AppSpacing.md,
                  // Fixed height, not a fixed aspect: the card is a
                  // fixed-height tile, so a wide window no longer leaves dead
                  // space under it.
                  mainAxisExtent: kRecipeCardHeight,
                ),
                itemCount: recipes.length,
                itemBuilder: (context, i) {
                  final recipe = recipes[i];
                  return RecipeCard(
                    recipe: recipe,
                    showVisibility: showVisibility,
                    showChef: showChef,
                    onTap: () => context.push(Routes.recipe(recipe.id)),
                  );
                },
              ),
            ),
            if (footer != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: gridPadding.left,
                    right: gridPadding.right,
                    bottom: padding.bottom,
                  ),
                  child: footer,
                ),
              ),
          ],
        );
      },
    );
  }
}

class RecipeGrid extends StatelessWidget {
  const RecipeGrid({
    super.key,
    required this.recipes,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.showVisibility = false,
    this.showChef = true,
    this.footer,
  });

  final List<Recipe> recipes;
  final EdgeInsets padding;

  /// Overlay a public/private badge on each card — for surfaces that mix both.
  final bool showVisibility;

  /// Overlay the owning chef on each card. Off on surfaces where every recipe
  /// has the same owner (My Recipes), where the badge is pure noise.
  final bool showChef;

  /// Rendered below the last row, inside the same scroll view — the `Load more`
  /// control (OPT-P9). It has to scroll **with** the grid: a fixed bar under it
  /// would cost every screen a strip of height whether or not there is another
  /// page, which is why this is a `CustomScrollView` rather than a `GridView`
  /// with something bolted underneath.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverRecipeGrid(
          recipes: recipes,
          padding: padding,
          showVisibility: showVisibility,
          showChef: showChef,
          footer: footer,
        ),
      ],
    );
  }
}
