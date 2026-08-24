import 'package:cached_network_image/cached_network_image.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/widgets/share_dialog.dart';
import 'package:app/features/recipe_detail/detail_chips.dart';
import 'package:app/features/recipe_detail/rating_section.dart';
import 'package:app/features/recipe_detail/recipe_content_views.dart';
import 'package:app/features/recipe_detail/recipe_detail_expanded.dart';
import 'package:app/features/recipe_detail/recipe_detail_providers.dart';
import 'package:app/features/recipe_detail/version_history_sheet.dart';
import 'package:app/routing/app_router.dart';

class RecipeDetailScreen extends ConsumerWidget {
  const RecipeDetailScreen({super.key, required this.recipeId});

  final String recipeId;

  Future<void> _fork(BuildContext context, WidgetRef ref) async {
    try {
      final newId = await ref.read(recipeRepositoryProvider).fork(recipeId);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Forked to your recipes')));
        context.go(Routes.editRecipe(newId));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recipeProvider(recipeId));
    // One view per visit (OPT-P7). Watched, not read, so it stays alive for as
    // long as the screen does and is not re-run by the recipe invalidations
    // that every like/save/rating triggers.
    ref.watch(recipeViewLoggerProvider(recipeId));
    final currentUser = ref.watch(currentUserIdProvider);

    return Scaffold(
      body: async.when(
        loading: () => const Scaffold(body: LoadingView()),
        error:
            (e, _) => Scaffold(
              appBar: AppBar(),
              body: ErrorView(
                message: friendlyError(e),
                onRetry: () => ref.invalidate(recipeProvider(recipeId)),
              ),
            ),
        data: (recipe) {
          final isOwner = currentUser != null && currentUser == recipe.ownerId;
          // The v2 reading page (header band + ingredients rail / method) is
          // web-first: expanded windows only. Compact and medium keep the v1
          // hero layout until the compact redesign lands.
          if (context.isExpanded) {
            return RecipeDetailExpanded(
              recipe: recipe,
              isOwner: isOwner,
              onFork: () => _fork(context, ref),
            );
          }
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 240,
                pinned: true,
                actions: [
                  IconButton(
                    tooltip: 'Version history',
                    icon: const Icon(Icons.history),
                    onPressed: () async {
                      final versions = await ref.read(
                        recipeVersionsProvider(recipeId).future,
                      );
                      if (context.mounted) {
                        await VersionHistorySheet.show(context, versions);
                      }
                    },
                  ),
                  if (isOwner) ...[
                    IconButton(
                      tooltip: 'Share',
                      icon: const Icon(Icons.share),
                      onPressed: () => ShareDialog.show(context, recipeId),
                    ),
                    IconButton(
                      tooltip: 'Edit',
                      icon: const Icon(Icons.edit),
                      onPressed: () => context.go(Routes.editRecipe(recipeId)),
                    ),
                  ],
                ],
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(recipe.title),
                  background:
                      recipe.coverImageUrl == null
                          ? Container(
                            color:
                                Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                          )
                          : CachedNetworkImage(
                            imageUrl: recipe.coverImageUrl!,
                            fit: BoxFit.cover,
                          ),
                ),
              ),
              SliverToBoxAdapter(
                child: _Body(
                  recipe: recipe,
                  isOwner: isOwner,
                  onFork: () => _fork(context, ref),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.recipe,
    required this.isOwner,
    required this.onFork,
  });

  final Recipe recipe;
  final bool isOwner;
  final VoidCallback onFork;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servings =
        ref.watch(selectedServingsProvider(recipe.id)) ?? recipe.servings;
    final factor = recipe.servings == 0 ? 1.0 : servings / recipe.servings;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (recipe.isFork)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                children: [
                  const Icon(Icons.call_split, size: 16),
                  const SizedBox(width: 4),
                  Text('Forked recipe', style: textTheme.labelMedium),
                ],
              ),
            ),
          // The owning chef, directly under the title in the collapsing app
          // bar. Null whenever the recipe was loaded without the owner
          // embedding — render nothing rather than an empty badge.
          if (recipe.owner != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: ChefBadge.fromProfile(recipe.owner!),
            ),
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: StarRating(
              rating: recipe.ratingAvg,
              count: recipe.ratingCount,
              size: 20,
            ),
          ),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DifficultyBadge(difficulty: recipe.difficulty),
              MetaChip(
                icon: Icons.schedule,
                label: '${recipe.totalMinutes} min total',
              ),
              MetaChip(
                icon: Icons.timer_outlined,
                label: 'Prep ${recipe.prepMinutes}m',
              ),
              MetaChip(
                icon: Icons.local_fire_department,
                label: 'Cook ${recipe.cookMinutes}m',
              ),
              MetaChip(
                icon: recipe.visibility.isPublic ? Icons.public : Icons.lock,
                label: recipe.visibility.isPublic ? 'Public' : 'Private',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (recipe.description.isNotEmpty)
            Text(recipe.description, style: textTheme.bodyLarge),
          if (recipe.attribution != null && recipe.attribution!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadii.card),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_stories),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      recipe.attribution!,
                      style: textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              LikeSaveButtons(recipe: recipe),
              const Spacer(),
              if (!isOwner)
                FilledButton.tonalIcon(
                  onPressed: onFork,
                  icon: const Icon(Icons.call_split),
                  label: const Text('Fork'),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          RatingSection(recipe: recipe, isOwner: isOwner),
          const Divider(height: AppSpacing.xl),
          // Servings scaler
          Row(
            children: [
              Text('Ingredients', style: textTheme.titleLarge),
              const Spacer(),
              IconButton.filledTonal(
                icon: const Icon(Icons.remove),
                onPressed:
                    servings > 1
                        ? () =>
                            ref
                                .read(
                                  selectedServingsProvider(recipe.id).notifier,
                                )
                                .state = servings - 1
                        : null,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Text('$servings servings', style: textTheme.titleMedium),
              ),
              IconButton.filledTonal(
                icon: const Icon(Icons.add),
                onPressed:
                    () =>
                        ref
                            .read(selectedServingsProvider(recipe.id).notifier)
                            .state = servings + 1,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final group in recipe.ingredientGroups)
            IngredientGroupView(group: group, factor: factor),
          const Divider(height: AppSpacing.xl),
          Text('Instructions', style: textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          for (final group in recipe.stepGroups) StepGroupView(group: group),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}
