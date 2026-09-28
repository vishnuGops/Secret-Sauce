import 'package:flutter/material.dart';

import 'package:design_system/src/layout/adaptive.dart';
import 'package:design_system/src/theme/app_theme.dart';

/// Height of a [CategoryTile] at 1.0× text scale; it grows with the scale so a
/// two-word category never clips (Gotcha 22).
const double kCategoryTileHeight = 88;

/// One of reference 1's colour-block category tiles (Phase 36c): the category
/// in large type on its own block colour ([AppPalette.category]), used as a
/// filter on Discover.
///
/// A control, so it carries button semantics and a visible selected state —
/// an inset ring in the block's ink — rather than relying on colour alone
/// (the block colours are not a state).
///
/// An optional [image] is a flat-lay photo shot on the block's own colour:
/// fitted to the tile's height and pinned right, so a wide tile shows the
/// whole dish with plain block to its left, and a narrow one crops the photo's
/// empty left edge first. The block colour stays underneath, so a photo that
/// is loading or missing leaves the plain tile rather than a hole.
class CategoryTile extends StatelessWidget {
  const CategoryTile({
    super.key,
    required this.category,
    this.label,
    this.image,
    this.selected = false,
    this.onTap,
  });

  /// Picks the block colour through [AppPalette.category] — a raw recipe
  /// category (`Main`, `Appetizer`) the palette knows.
  final String category;

  /// What the tile says and announces, when that is not [category] itself.
  /// Discover's tiles stand for a *group* of raw values (`Starters` covers
  /// `Appetizer`, `Snack`, `Side Dish` …), so the name on the tile and the key
  /// that picks its colour can differ. Defaults to [category].
  final String? label;

  /// Decorative photo behind the label; excluded from semantics (the label is
  /// the announcement). Its backdrop must be the block colour, or the seam
  /// where a wide tile runs past the photo's left edge shows.
  final ImageProvider? image;
  final bool selected;
  final VoidCallback? onTap;

  /// Width of the selected ring.
  static const double _ringWidth = AppStroke.medium;

  /// Reach of the label's scrim from the bottom-left corner, in multiples of
  /// the tile's height (a [RadialGradient] radius is a fraction of the
  /// shortest side). 1.4 heights reaches the end of `Breakfast` on the 140px
  /// phone tile, where the dish sits under the label, and leaves the dish's
  /// top-right in full colour; on a wide tile that corner is plain block
  /// already. Two heights at 0.9 washed out the whole phone tile.
  static const double _scrimRadius = 1.4;

  /// Opacity of the scrim at the corner and at 60% of its reach.
  static const double _scrimInner = 0.8;
  static const double _scrimMid = 0.5;

  @override
  Widget build(BuildContext context) {
    final colors = context.palette.category(category);
    final text = label ?? category;
    final radius = BorderRadius.circular(AppRadii.card);

    return Semantics(
      button: true,
      selected: selected,
      label: text,
      // The label is the whole announcement, so the subtree is excluded —
      // which also drops the InkWell's action, hence the explicit onTap.
      onTap: onTap,
      excludeSemantics: true,
      child: SizedBox(
        height:
            kCategoryTileHeight * context.textScale.clamp(1.0, double.infinity),
        child: Material(
          color: colors.background,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side:
                selected
                    ? BorderSide(color: colors.foreground, width: _ringWidth)
                    : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (image case final image?) ...[
                Image(
                  image: image,
                  fit: BoxFit.fitHeight,
                  alignment: Alignment.centerRight,
                  excludeFromSemantics: true,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.bottomLeft,
                      radius: _scrimRadius,
                      colors: [
                        colors.background.withValues(alpha: _scrimInner),
                        colors.background.withValues(alpha: _scrimMid),
                        colors.background.withValues(alpha: 0),
                      ],
                      stops: const [0, 0.6, 1],
                    ),
                  ),
                ),
              ],
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Text(
                    text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(color: colors.foreground),
                  ),
                ),
              ),
              // Ink on top: an opaque photo would hide a splash painted on
              // the Material underneath it.
              Material(
                type: MaterialType.transparency,
                child: InkWell(onTap: onTap),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
