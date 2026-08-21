import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'package:design_system/src/theme/app_theme.dart';

/// Compact pill showing a chef's [ChefTier] — icon plus label.
///
/// Colors are resolved per [Brightness]: the light-mode shades are too dark to
/// read on a dark surface and vice versa, so each tier carries a pair. The tier
/// labels are fixed English strings from [ChefTier.label].
class TierChip extends StatelessWidget {
  const TierChip({
    super.key,
    required this.tier,
    this.dense = false,
    this.onImage = false,
  });

  final ChefTier tier;

  /// Drops the icon and tightens padding, for dense surfaces like a card
  /// overlay where horizontal space is the scarce resource.
  final bool dense;

  /// Set when the chip sits on a **dark scrim over a cover photo** rather than
  /// on a theme surface (B055).
  ///
  /// Without it the chip reads `theme.brightness` — which is the *page's*
  /// brightness, still light — and paints the light-mode shade, a dark colour
  /// chosen to contrast with a light background, at 14% alpha on top of black.
  /// The label all but disappeared: on the recipe card the chef's name was
  /// crisp white and the tier under it was dark purple on dark grey. Only a
  /// screenshot catches this; every layout test passed.
  final bool onImage;

  static IconData iconFor(ChefTier tier) => switch (tier) {
    ChefTier.homeCook => Icons.egg_outlined,
    ChefTier.lineCook => Icons.outdoor_grill_outlined,
    ChefTier.sousChef => Icons.restaurant_outlined,
    ChefTier.headChef => Icons.local_fire_department_outlined,
    ChefTier.masterChef => Icons.workspace_premium_outlined,
  };

  /// Accent color for [tier], readable on that brightness' surfaces.
  static Color colorFor(ChefTier tier, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return switch (tier) {
      ChefTier.homeCook =>
        dark ? const Color(0xFFB0BEC5) : const Color(0xFF546E7A), // slate
      ChefTier.lineCook =>
        dark ? const Color(0xFF80CBC4) : const Color(0xFF00695C), // teal
      ChefTier.sousChef =>
        dark ? const Color(0xFF90CAF9) : const Color(0xFF1565C0), // blue
      ChefTier.headChef =>
        dark ? const Color(0xFFCE93D8) : const Color(0xFF6A1B9A), // purple
      ChefTier.masterChef =>
        dark ? const Color(0xFFFFCC80) : const Color(0xFFB26500), // amber
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // On a scrim the surface is dark whatever the page's brightness is, so the
    // dark-surface half of each tier's colour pair is the correct one.
    final color = colorFor(tier, onImage ? Brightness.dark : theme.brightness);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : AppSpacing.sm,
        vertical: dense ? 1 : 2,
      ),
      decoration: BoxDecoration(
        // A heavier wash on a scrim: 14% of a pale colour over black is
        // indistinguishable from the scrim itself.
        color: color.withValues(alpha: onImage ? 0.28 : 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!dense) ...[
            Icon(iconFor(tier), size: 13, color: color),
            const SizedBox(width: 4),
          ],
          // Flexible so the chip degrades instead of overflowing when a caller
          // puts it in a tight row — the RecipeCard tile cannot grow
          // (B001/B002/B016).
          Flexible(
            child: Text(
              tier.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
