import 'package:cached_network_image/cached_network_image.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/features/chefs/chef_detail_common.dart';
import 'package:app/features/chefs/chefs_providers.dart';
import 'package:app/routing/app_router.dart';

/// The right half of the expanded chef card: the chef's top recipes and the
/// totals they add up to (OPT-A8).

/// "Top recipes" plus the totals grid.
class ChefRecipesPanel extends StatelessWidget {
  const ChefRecipesPanel({
    super.key,
    required this.standing,
    required this.detail,
    required this.color,
  });

  final ChefStanding standing;
  final AsyncValue<ChefDetail> detail;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const ChefKicker(text: 'Top recipes'),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Ranked by points contributed, not by rating.',
          style:
              theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.md),
        detail.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => ChefNote(text: friendlyError(e)),
          data: (data) {
            if (data.topRecipesFailed) {
              return const ChefNote(
                text: 'Top recipes are unavailable right now.',
              );
            }
            if (data.topRecipes.isEmpty) {
              return const ChefNote(text: 'No public recipes yet.');
            }
            return Column(
              children: [
                for (final recipe in data.topRecipes) ...[
                  _TopRecipeRow(recipe: recipe),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ],
            );
          },
        ),
        const Divider(height: AppSpacing.xl),
        _Totals(standing: standing),
        const SizedBox(height: AppSpacing.md),
        Text(
          // The mockup said "recomputes nightly"; the build recomputes on every
          // like, save, view and visibility change, so the copy says that.
          'Score and rank update the moment a recipe gains a like, save, or '
          'view — there is no nightly job.',
          style:
              theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// One "Top recipes" row: thumbnail, title, rating, and what it contributed.
class _TopRecipeRow extends StatelessWidget {
  const _TopRecipeRow({required this.recipe});

  final Recipe recipe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final points = ChefScoring.score(
      likes: recipe.likeCount,
      saves: recipe.saveCount,
      views: recipe.viewCount,
    );

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          // Close the card first: the dialog would otherwise sit over the
          // recipe it just navigated to.
          Navigator.of(context).pop();
          context.push(Routes.recipe(recipe.id));
        },
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            children: [
              _Thumb(url: recipe.coverImageUrl),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      recipe.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (recipe.hasRatings)
                          RatingPill(
                            rating: recipe.ratingAvg,
                            count: recipe.ratingCount,
                          ),
                        Text(
                          '${groupedCount(recipe.likeCount)} likes · '
                          '${groupedCount(recipe.saveCount)} saves',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                groupedScore(points),
                maxLines: 1,
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(Icons.restaurant_menu, size: 20, color: scheme.onSurfaceVariant),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.sm),
      child: SizedBox(
        width: 56,
        height: 44,
        child: url == null || url!.isEmpty
            ? placeholder
            : CachedNetworkImage(
                imageUrl: url!,
                fit: BoxFit.cover,
                placeholder: (_, __) =>
                    Container(color: scheme.surfaceContainerHighest),
                errorWidget: (_, __, ___) => placeholder,
              ),
      ),
    );
  }
}

/// Recipes / likes / saves / views, the same four numbers the collapsed card
/// shows as chips — repeated here as the totals the breakdown above adds up to.
class _Totals extends StatelessWidget {
  const _Totals({required this.standing});

  final ChefStanding standing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget cell(int value, String label) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                groupedCount(value),
                maxLines: 1,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: cell(standing.publicRecipeCount, 'recipes')),
        Expanded(child: cell(standing.totalLikes, 'likes')),
        Expanded(child: cell(standing.totalSaves, 'saves')),
        Expanded(child: cell(standing.totalViews, 'views')),
      ],
    );
  }
}
