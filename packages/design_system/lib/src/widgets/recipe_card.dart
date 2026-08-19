import 'package:cached_network_image/cached_network_image.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'package:design_system/src/theme/app_theme.dart';
import 'package:design_system/src/widgets/chef_badge.dart';
import 'package:design_system/src/widgets/difficulty_badge.dart';
import 'package:design_system/src/widgets/star_rating.dart';

/// Height of every [RecipeCard], in logical pixels.
///
/// The card is a **fixed-height** tile rather than a fixed-aspect one: the grid
/// passes this as `mainAxisExtent`, so a wide window no longer leaves dead
/// space under each card. The banner takes one or two lines and the cover gives
/// up the difference — the footer never moves.
const double kRecipeCardHeight = 352;

/// Narrowest width the card is designed for, and the width its layout tests
/// use as the worst realistic envelope.
///
/// A grid packs as many columns as can each hold this much (see
/// `FlowGridMetrics`). Nothing enforces it below one column — a phone narrower
/// than this gets a single card that degrades rather than overflows.
const double kRecipeCardMinWidth = 264;

/// Widest the card is ever laid out at.
///
/// The card does **not** clamp itself: a grid cell hands it tight constraints,
/// which win over any `ConstrainedBox` inside. The grid owns the cap — it turns
/// spare width into another column, and centres the row once the tiles are at
/// their maximum.
const double kRecipeCardMaxWidth = 340;

/// The primary recipe tile used on Discover and My Recipes (v2 layout).
///
/// Top to bottom: a **title banner** on `colorScheme.primary`, the cover image,
/// then a footer with the truncated description and the time / rating /
/// difficulty row. The name leads the card, so it never competes with the photo
/// and stays legible over a dark or busy cover.
///
/// Set [showVisibility] on surfaces that mix private and public recipes (My
/// Recipes) to add a lock/globe chip to the banner. When [Recipe.owner] is
/// embedded and [showChef] is true, the owning chef is drawn as an overlay on
/// the **cover image**, bottom-right.
///
/// The banner and footer are intrinsically sized and the cover is the only
/// flexible child, so text-scale growth eats cover height instead of
/// overflowing (B001/B002/B016 all came from a card row that could not shrink).
class RecipeCard extends StatelessWidget {
  const RecipeCard({
    super.key,
    required this.recipe,
    this.onTap,
    this.showVisibility = false,
    this.showChef = true,
  });

  final Recipe recipe;
  final VoidCallback? onTap;
  final bool showVisibility;

  /// Set false on surfaces where every card has the same owner (My Recipes),
  /// so the badge is not repeated on every tile.
  final bool showChef;

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

    return SizedBox(
      // Tight height so the cover's Expanded always has a bound, including in
      // tests and any caller that lays the card out with unbounded height.
      height: kRecipeCardHeight,
      child: Card(
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TitleBanner(
                title: recipe.title,
                visibility: showVisibility ? recipe.visibility : null,
              ),
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _CoverImage(url: recipe.coverImageUrl, scheme: scheme),
                    if (showChef && recipe.owner != null)
                      Positioned(
                        left: AppSpacing.sm,
                        right: AppSpacing.sm,
                        bottom: AppSpacing.sm,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: _ChefOverlay(owner: recipe.owner!),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recipe.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.only(top: 10),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: scheme.outlineVariant),
                        ),
                      ),
                      // The badge takes its intrinsic width, capped at half the
                      // row; the time + rating group takes everything left over
                      // and ellipsizes inside it. Two flex children instead
                      // (what this was) split the row 50/50 whatever the
                      // content, which truncated "4.9 (8)" to "4…" at
                      // one-column widths; a bare intrinsic badge overflows by
                      // 1px at 276 / 2.0x. The cap is what degrades in the
                      // right order and still fits "12h 45m" + "4.5 (1250)"
                      // there (B016).
                      child: LayoutBuilder(
                        builder: (context, constraints) => Row(
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
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: constraints.maxWidth / 2,
                              ),
                              child: DifficultyBadge(
                                difficulty: recipe.difficulty,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The recipe name as a banner across the top of the card.
///
/// Two lines maximum, then an ellipsis — a longer name eats cover height, it
/// never grows the card. [visibility] is null on surfaces that do not mix
/// private and public recipes.
class _TitleBanner extends StatelessWidget {
  const _TitleBanner({required this.title, this.visibility});

  final String title;
  final RecipeVisibility? visibility;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      color: scheme.primary,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                color: scheme.onPrimary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.16,
              ),
            ),
          ),
          if (visibility != null) ...[
            const SizedBox(width: AppSpacing.sm),
            _VisibilityBadge(visibility: visibility!, scheme: scheme),
          ],
        ],
      ),
    );
  }
}

/// The owning chef, drawn over the bottom-right of the cover image on a scrim.
///
/// `Positioned` with both `left` and `right` set gives this a bounded width, so
/// the badge's name and tier chip ellipsize instead of overflowing at the 276px
/// two-column width or at 2.0x text scale; the `Align` pulls it to the right
/// edge once it is narrower than that bound.
class _ChefOverlay extends StatelessWidget {
  const _ChefOverlay({required this.owner});

  final Profile owner;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        // Scrim: cover photos are arbitrary, so the badge carries its own
        // contrast rather than relying on the image being dark.
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: ChefBadge.fromProfile(owner, compact: true, onSurfaceImage: true),
    );
  }
}

/// Icon-only public/private chip, at the end of the title banner.
///
/// Icon-only on purpose: the banner already spends its width on the name, and a
/// "Private" label would be the first thing to overflow at large text scale.
/// The label survives as the tooltip, which is also what screen readers read.
class _VisibilityBadge extends StatelessWidget {
  const _VisibilityBadge({required this.visibility, required this.scheme});

  final RecipeVisibility visibility;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final isPublic = visibility.isPublic;
    return Tooltip(
      message: isPublic ? 'Public' : 'Private',
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xs),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Icon(
          isPublic ? Icons.public : Icons.lock_outline,
          size: 14,
          color: scheme.onSurfaceVariant,
        ),
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
