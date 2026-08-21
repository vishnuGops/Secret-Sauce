import 'package:cached_network_image/cached_network_image.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'package:design_system/src/layout/adaptive.dart';
import 'package:design_system/src/theme/app_theme.dart';
import 'package:design_system/src/widgets/chef_badge.dart';
import 'package:design_system/src/widgets/difficulty_badge.dart';
import 'package:design_system/src/widgets/star_rating.dart';

/// Height of every [RecipeCard], in logical pixels.
///
/// The card is a **fixed-height** tile rather than a fixed-aspect one: the grid
/// passes this as `mainAxisExtent`, so a wide window no longer leaves dead
/// space under each card. The banner is a fixed band of its own
/// (`kRecipeCardBannerHeight`) whatever the title's length, so at default text
/// scale nothing inside the card moves between one recipe and the next; the
/// cover is the band that gives up height when text scaling grows the other
/// two.
const double kRecipeCardHeight = 352;

/// Narrowest width the card is designed for, and the width its layout tests
/// use as the worst realistic envelope.
///
/// A grid packs as many columns as can each hold this much (see
/// `FlowGridMetrics`). Nothing enforces it below one column — a phone narrower
/// than this gets a single card that degrades rather than overflows.
///
/// **288, not 264**: this is the floor at which the whole time / rating /
/// difficulty row still fits with its longest labels, and *nothing in that row
/// may truncate*. At 264 a wide grid packed one more column by buying it out of
/// the footer — `4.9 (8)` ellipsized to fit. A column fewer is the cheaper
/// trade.
const double kRecipeCardMinWidth = 288;

/// Height of the title banner, before text scale.
///
/// Fixed, and two lines' worth: the title is vertically centred inside it, so a
/// one-line name and a two-line name give the **same** banner and every card in
/// a row lines its cover up with its neighbours'. A longer name clamps to two
/// lines with an ellipsis rather than growing the band.
///
/// Multiplied by `context.textScale` at build time (up to
/// [kRecipeCardBannerMaxScale]) — a fixed pixel height would clip two lines of
/// 2.0× text, and the point of the constant is that the two cases stay equal at
/// every scale the card is contracted to survive.
const double kRecipeCardBannerHeight = 65;

/// Ceiling on the text-scale factor the banner band is multiplied by.
///
/// The card's total height is fixed, so a band that keeps growing eventually
/// leaves the cover nothing and the column overflows — 65 × 3.0 is 195px of
/// banner against a 352px card whose footer alone wants ~190 at that scale
/// (a 48px overflow, measured). Past this ceiling the band stops growing and
/// the title's own two lines drive it, which is the pre-B047 behaviour and
/// still taller than the text needs: 130px holds two lines of 3.0× type with
/// room to spare, so the one-line/two-line match survives the clamp.
const double kRecipeCardBannerMaxScale = 2.0;

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
/// The banner is a fixed band and the footer is intrinsic; the cover is the
/// only flexible child, so text-scale growth eats cover height instead of
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
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
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
                      // 1px at the narrowest column / 2.0x. The cap is what
                      // degrades in the right order (B016) — and
                      // `kRecipeCardMinWidth` is set so that at default scale
                      // this row never has to degrade at all (B048).
                      child: LayoutBuilder(
                        builder:
                            (context, constraints) => Row(
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
///
/// The band is a **fixed** `kRecipeCardBannerHeight × textScale` with the title
/// centred in it, so one-line and two-line names produce identical banners and
/// the covers of neighbouring cards start at the same y. It is a *minimum*, not
/// a tight height: anything the text needs beyond it still grows the band (and
/// costs the cover) instead of overflowing.
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
      constraints: BoxConstraints(
        minHeight:
            kRecipeCardBannerHeight *
            context.textScale.clamp(1.0, kRecipeCardBannerMaxScale),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
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
/// the badge's name and tier chip ellipsize instead of overflowing at
/// `kRecipeCardMinWidth` or at 2.0x text scale; the `Align` pulls it to the
/// right edge once it is narrower than that bound.
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
      errorWidget:
          (_, __, ___) => Container(
            color: scheme.surfaceContainerHighest,
            child: const Icon(Icons.broken_image_outlined),
          ),
    );
  }
}
