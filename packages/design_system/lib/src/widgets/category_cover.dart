import 'package:flutter/material.dart';

import 'package:design_system/src/layout/adaptive.dart';
import 'package:design_system/src/theme/app_theme.dart';

/// The cover a recipe gets when it has **no photograph** (Phase 36c, the
/// owner's Q1): a flat block in the recipe's category colour with the
/// category set large in the block's own ink — reference 1's colour tiles,
/// turned into a first-class state rather than a utensil glyph on grey
/// (UX-034). 0 of the 14 curated recipes has a cover, so this is what most
/// readers see today; a real photo replaces it wherever a recipe has one.
///
/// It names the **category, not the dish**: the dish name sits directly under
/// the cover on a card and beside it on the detail page, and printing it twice
/// one line apart is noise (a deliberate adaptation of the approved preview —
/// REBUILD-LOG 2026-09-25).
///
/// Decorative for assistive tech — the page or card holding it reads the
/// title — so it is excluded from semantics.
class CategoryCover extends StatelessWidget {
  const CategoryCover({super.key, this.category, this.large = false});

  /// Free-text category (`Main`, `Dessert`, …); picks the block colour via
  /// [AppPalette.category]. Null takes the default block and no label.
  final String? category;

  /// The detail page's hero rather than a card cover: bigger type, more inset.
  final bool large;

  // Line heights (logical px at 1.0×) of the label roles, so the cover can
  // tell — at any text scale — whether the label fits. A fixed-height card at
  // 3.0× squeezes its cover to ~40px (B049); below what the label needs the
  // cover is colour alone. A clipped half-line reads as a fault, not a design.
  static const double _labelLine = 28;
  static const double _largeLabelLine = 44;

  @override
  Widget build(BuildContext context) {
    final colors = context.palette.category(category);
    final text = Theme.of(context).textTheme;
    final pad = large ? AppSpacing.lg : AppSpacing.md;
    final label = category?.trim().toUpperCase();

    return ExcludeSemantics(
      child: ColoredBox(
        color: colors.background,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final needs =
                (large ? _largeLabelLine : _labelLine) * context.textScale;
            final fits = constraints.maxHeight - pad * 2 >= needs;
            if (label == null || label.isEmpty || !fits) {
              return const SizedBox.expand();
            }
            return Padding(
              padding: EdgeInsets.all(pad),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: (large ? text.displaySmall : text.titleLarge)
                      ?.copyWith(color: colors.foreground),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
