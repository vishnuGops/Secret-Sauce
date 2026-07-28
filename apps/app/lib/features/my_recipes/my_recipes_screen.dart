import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/features/my_recipes/my_recipes_providers.dart';
import 'package:app/routing/app_router.dart';
import 'package:app/widgets/recipe_grid.dart';

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
            tabs: [
              Tab(text: 'My Recipes'),
              Tab(text: 'Shared with me'),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'New recipe',
              onPressed: () => context.go(Routes.newRecipe),
            ),
          ],
        ),
        body: TabBarView(
          children: [
            _Tab(
              provider: myRecipesProvider,
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
            _Tab(
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

class _Tab extends ConsumerWidget {
  const _Tab({required this.provider, required this.empty});

  final ProviderListenable<AsyncValue<List<Recipe>>> provider;
  final Widget empty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(provider);
    return async.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(message: e.toString()),
      data: (recipes) => recipes.isEmpty ? empty : RecipeGrid(recipes: recipes),
    );
  }
}
