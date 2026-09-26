import 'package:flutter/material.dart';

import 'package:design_system/src/theme/app_theme.dart';

/// A filled pill naming something a recipe *is* — its cuisine, its category
/// (reference 5's orange tags, Phase 36c). Burnt-orange container with its own
/// ink (≥ 4.5:1, `theme_contrast_test`), never white on the bright orange the
/// reference used (2.5:1).
///
/// Informational, not a control: it has no tap target and reads as its label.
/// Ellipsizes rather than overflowing when a caller bounds its width; in a
/// `Wrap` (the intended parent) it renders in full.
class TagPill extends StatelessWidget {
  const TagPill({super.key, required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(
      context,
    ).textTheme.labelLarge?.copyWith(color: scheme.onTertiaryContainer);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.smPlus,
        vertical: AppSpacing.xsPlus,
      ),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: AppIconSize.sm, color: scheme.onTertiaryContainer),
            const SizedBox(width: AppSpacing.xs),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}
