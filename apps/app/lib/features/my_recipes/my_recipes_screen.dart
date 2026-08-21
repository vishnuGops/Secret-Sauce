import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/features/my_recipes/my_recipes_providers.dart';
import 'package:app/routing/app_router.dart';
import 'package:app/widgets/recipe_async_grid.dart';

/// My Recipes with two tabs: recipes I own and recipes shared with me.
class MyRecipesScreen extends ConsumerWidget {
  const MyRecipesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Recipes'),
          bottom: const TabBar(
            tabs: [Tab(text: 'My Recipes'), Tab(text: 'Shared with me')],
          ),
          actions: [
            // `New recipe` left the web top navigation and lives on the page it
            // belongs to; compact keeps the icon because the shell's FAB is
            // already the labelled call to action there. The labelled button is
            // taller than `kToolbarHeight` at 2.0x text scale, but the toolbar
            // clamps it without a `RenderFlex` overflow — measured, not assumed
            // (`my_recipes_header_test.dart` pins 600–1400px at up to 2.0x).
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child:
                  context.isCompact
                      ? IconButton(
                        icon: const Icon(Icons.add),
                        tooltip: 'New recipe',
                        onPressed: () => context.go(Routes.newRecipe),
                      )
                      : FilledButton.icon(
                        onPressed: () => context.go(Routes.newRecipe),
                        icon: const Icon(Icons.add),
                        label: const Text(
                          'New recipe',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
            ),
          ],
        ),
        body: TabBarView(
          children: [
            RecipeAsyncGrid(
              provider: myRecipesProvider,
              showVisibility: true,
              // Every card here is mine — a repeated chef badge is noise, and
              // it would fight the public/private pill for cover space.
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
        ),
      ),
    );
  }
}
