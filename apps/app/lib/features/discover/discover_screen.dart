import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/features/discover/discover_providers.dart';
import 'package:app/widgets/recipe_grid.dart';

/// Public discovery: Popular / Trending / Recent tabs plus search.
class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchQueryProvider);
    final searching = query.trim().isNotEmpty;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Discover'),
          bottom: searching
              ? null
              : const TabBar(
                  tabs: [
                    Tab(text: 'Popular'),
                    Tab(text: 'Trending'),
                    Tab(text: 'Recent'),
                  ],
                ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: SearchBar(
                controller: _searchController,
                hintText: 'Search recipes, ingredients, tags…',
                leading: const Icon(Icons.search),
                trailing: [
                  if (searching)
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        ref.read(searchQueryProvider.notifier).state = '';
                      },
                    ),
                ],
                onChanged: (v) =>
                    ref.read(searchQueryProvider.notifier).state = v,
              ),
            ),
            Expanded(
              child: searching
                  ? _RecipeList(
                      provider: searchResultsProvider, emptyLabel: 'No matches')
                  : TabBarView(
                      children: [
                        _RecipeList(
                          provider: popularRecipesProvider,
                          emptyLabel: 'No popular recipes yet',
                        ),
                        _RecipeList(
                          provider: trendingRecipesProvider,
                          emptyLabel: 'Nothing trending yet',
                        ),
                        _RecipeList(
                          provider: recentRecipesProvider,
                          emptyLabel: 'No recipes yet',
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecipeList extends ConsumerWidget {
  const _RecipeList({required this.provider, required this.emptyLabel});

  final ProviderListenable<AsyncValue<List<Recipe>>> provider;
  final String emptyLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(provider);
    return async.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(message: e.toString()),
      data: (recipes) => recipes.isEmpty
          ? EmptyView(
              title: emptyLabel,
              icon: Icons.local_dining_outlined,
              message: 'Public recipes will appear here.',
            )
          : RecipeGrid(recipes: recipes),
    );
  }
}
