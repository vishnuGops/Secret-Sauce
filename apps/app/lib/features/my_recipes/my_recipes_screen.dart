import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/features/my_recipes/my_recipes_providers.dart';
import 'package:app/routing/app_router.dart';
import 'package:app/widgets/recipe_async_grid.dart';
import 'package:app/widgets/recipe_grid.dart';

/// My Recipes with two tabs: recipes I own and recipes shared with me.
///
/// **Two chromes, on the shell's own split** (`context.isCompact`, the same
/// test `AppShell` uses to pick a bottom bar or the web top bar):
///
///  * **Compact** keeps an `AppBar`. There is no other bar on a phone — the
///    shell's bottom `NavigationBar` names the destination but nothing at the
///    top does — so the page has to title itself, and the toolbar is where the
///    tab strip lives.
///  * **Web** has no `AppBar` (Phase 21's carried-over item). The shell's
///    `TopNavBar` is already a toolbar over this page, and a second one under it
///    stacked two bars of chrome — two surfaces, two elevations, a repeated
///    "My Recipes" — before the first card. The page opens with an in-content
///    header instead, the way Discover opens with its masthead: the title and
///    the labelled `New recipe` button, then the tab strip, aligned with the
///    grid's first card rather than with the window edge.
class MyRecipesScreen extends ConsumerWidget {
  const MyRecipesScreen({super.key});

  /// The web header's labelled `New recipe` button. The empty state carries a
  /// button with the same label, so a test needs a way to tell them apart.
  static const newRecipeButtonKey = ValueKey('my-recipes-new-recipe');

  static const _tabs = [Tab(text: 'My Recipes'), Tab(text: 'Shared with me')];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grids = TabBarView(
      children: [
        RecipeAsyncGrid(
          provider: myRecipesProvider,
          showVisibility: true,
          // Every card here is mine — a repeated chef badge is noise, and it
          // would fight the public/private pill for cover space.
          showChef: false,
          empty: EmptyView(
            title: 'No recipes yet',
            message: 'Create your first recipe to start your vault.',
            icon: Icons.menu_book_outlined,
            action: FilledButton.icon(
              onPressed: () => context.go(Routes.newRecipe),
              icon: const Icon(Icons.add),
              label: const Text('New recipe'),
            ),
          ),
        ),
        RecipeAsyncGrid(
          provider: sharedWithMeProvider,
          empty: const EmptyView(
            title: 'Nothing shared yet',
            message: 'Recipes others share with you appear here.',
            icon: Icons.group_outlined,
          ),
        ),
      ],
    );

    if (context.isCompact) {
      return DefaultTabController(
        length: _tabs.length,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('My Recipes'),
            bottom: const TabBar(tabs: _tabs),
            actions: [
              // Icon only: the shell's FAB is already the labelled call to
              // action on a phone.
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'New recipe',
                  onPressed: () => context.go(Routes.newRecipe),
                ),
              ),
            ],
          ),
          body: grids,
        ),
      );
    }

    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Measured here, around the header, not inside it: the header is a
            // child of a `Column`, which is bounded in width, so this reads the
            // same extent the grid below is handed (Gotcha 25).
            LayoutBuilder(
              builder:
                  (context, constraints) => _WebHeader(
                    // The grid's default padding plus its centring gutter —
                    // exactly where its first card starts.
                    inset:
                        AppSpacing.md +
                        recipeGridMetrics(constraints.maxWidth).gutter,
                  ),
            ),
            Expanded(child: grids),
          ],
        ),
      ),
    );
  }
}

/// The web page header: title and `New recipe`, then the tab strip.
///
/// Every part of it is content-sized and none of it is a fixed-height toolbar,
/// so text scale grows it instead of clamping it — the old `AppBar` squeezed a
/// 68px labelled button into 56px at 2.0×. It is bounded by what it holds: one
/// headline, one button, one tab strip.
class _WebHeader extends StatelessWidget {
  const _WebHeader({required this.inset});

  /// Left/right inset that lines the header up with the grid's first card.
  final double inset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // A tab's label sits this far inside the tab (Material's default
    // `labelPadding`), so the strip starts that much earlier to put the first
    // label's text, not its hit area, on the grid's edge.
    const tabLabelPadding = 16.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(inset, AppSpacing.lg, inset, 0),
            // `Wrap` with `spaceBetween`, not `Row(Expanded(title), button)`:
            // at 600px and 2.0× the headline and the labelled button do not
            // share a line, and a `Wrap` puts the button under the title
            // instead of cutting either one (Gotcha 21).
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.sm,
              children: [
                Text('My Recipes', style: theme.textTheme.headlineMedium),
                // `New recipe` left the web top navigation and lives on the
                // page it belongs to (Phase 21).
                FilledButton.icon(
                  key: MyRecipesScreen.newRecipeButtonKey,
                  onPressed: () => context.go(Routes.newRecipe),
                  icon: const Icon(Icons.add),
                  label: const Text('New recipe'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TabBar(
            tabs: MyRecipesScreen._tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            // No divider of its own (the theme's TabBarThemeData clears it):
            // the box's bottom border is the rule, full width; the tab bar's
            // would stop at the strip's scrollable extent.
            padding: EdgeInsets.only(
              left: (inset - tabLabelPadding).clamp(0.0, double.infinity),
            ),
          ),
        ],
      ),
    );
  }
}
