import 'package:cached_network_image/cached_network_image.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'package:design_system/src/theme/app_theme.dart';
import 'package:design_system/src/widgets/difficulty_badge.dart';
import 'package:design_system/src/widgets/star_rating.dart';

/// The primary recipe tile used on Discover and My Recipes.
///
/// Shows cover image, name, short description, total cook time, average star
/// rating, and a difficulty badge. Set [showVisibility] on surfaces that mix
/// private and public recipes (My Recipes) to overlay a public/private badge.
class RecipeCard extends StatelessWidget {
  const RecipeCard({
    super.key,
    required this.recipe,
    this.onTap,
    this.showVisibility = false,
  });

  final Recipe recipe;
  final VoidCallback? onTap;
  final bool showVisibility;

  String get _timeLabel {
    final total = recipe.totalMinutes;
    if (total <= 0) return '—';
    if (total < 60) return '$total min';
    final h = total ~/ 60;
    final m = total % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 10,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _CoverImage(url: recipe.coverImageUrl, scheme: scheme),
                  if (showVisibility)
                    Positioned(
                      top: AppSpacing.sm,
                      right: AppSpacing.sm,
                      child: _VisibilityBadge(
                        visibility: recipe.visibility,
                        scheme: scheme,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recipe.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    recipe.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  // The badge keeps its intrinsic width; the time + rating group
                  // takes what's left and ellipsizes. Without this the row
                  // overflows on a rated recipe with a long time label (e.g.
                  // "12h 45m" + "4.5 (1250)") at the 2-column grid width.
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Icon(
                              Icons.schedule,
                              size: 15,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                _timeLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.labelMedium,
                              ),
                            ),
                            if (recipe.hasRatings) ...[
                              const SizedBox(width: AppSpacing.sm),
                              Flexible(
                                child: RatingPill(
                                  rating: recipe.ratingAvg,
                                  count: recipe.ratingCount,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(
                        child: DifficultyBadge(difficulty: recipe.difficulty),
                      ),
                    ],
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

/// Small "Public"/"Private" pill overlaid on the cover image.
class _VisibilityBadge extends StatelessWidget {
  const _VisibilityBadge({required this.visibility, required this.scheme});

  final RecipeVisibility visibility;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final isPublic = visibility.isPublic;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPublic ? Icons.public : Icons.lock_outline,
            size: 12,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            isPublic ? 'Public' : 'Private',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _CoverImage extends StatelessWidget {
  const _CoverImage({required this.url, required this.scheme});

  final String? url;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return Container(
        color: scheme.surfaceContainerHighest,
        child: Icon(
          Icons.restaurant_menu,
          size: 40,
          color: scheme.onSurfaceVariant,
        ),
      );
    }
    return CachedNetworkImage(
      imageUrl: url!,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(color: scheme.surfaceContainerHighest),
      errorWidget: (_, __, ___) => Container(
        color: scheme.surfaceContainerHighest,
        child: const Icon(Icons.broken_image_outlined),
      ),
    );
  }
}
