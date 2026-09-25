import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'package:design_system/src/theme/app_theme.dart';

/// A small colored badge indicating recipe difficulty.
///
/// The colour is a hint; the word is the signal (color is never the only
/// signal). Colours come from [AppPalette] per brightness (B133 / UX-010: the
/// old `Colors.green.shade600` / `orange.shade700` measured 2.8 / 2.3:1 as
/// 11px text on their own wash, and `Hard` borrowed `scheme.error`).
class DifficultyBadge extends StatelessWidget {
  const DifficultyBadge({super.key, required this.difficulty});

  final Difficulty difficulty;

  @override
  Widget build(BuildContext context) {
    final color = context.palette.difficulty(difficulty);
    return Container(
      padding: AppInsets.badge,
      decoration: BoxDecoration(
        color: color.withValues(alpha: AppAlpha.badge),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_fire_department, size: AppIconSize.xs, color: color),
          const SizedBox(width: AppSpacing.xs),
          // Ellipsizes only when a caller places the badge under a tight
          // constraint (the RecipeCard metadata row); in a Wrap it is unbounded
          // and renders in full.
          Flexible(
            child: Text(
              difficulty.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
