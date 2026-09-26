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
class CategoryTile extends StatelessWidget {
  const CategoryTile({
    super.key,
    required this.category,
    this.label,
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
  final bool selected;
  final VoidCallback? onTap;

  /// Width of the selected ring.
  static const double _ringWidth = 3;

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
          child: InkWell(
            onTap: onTap,
            child: Padding(
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
          ),
        ),
      ),
    );
  }
}
