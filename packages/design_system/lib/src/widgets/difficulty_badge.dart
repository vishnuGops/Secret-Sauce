import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'package:design_system/src/theme/app_theme.dart';

/// A small colored badge indicating recipe difficulty.
class DifficultyBadge extends StatelessWidget {
  const DifficultyBadge({super.key, required this.difficulty});

  final Difficulty difficulty;

  Color _color(ColorScheme scheme) => switch (difficulty) {
    Difficulty.easy => Colors.green.shade600,
    Difficulty.medium => Colors.orange.shade700,
    Difficulty.hard => scheme.error,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _color(scheme);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_fire_department, size: 14, color: color),
          const SizedBox(width: 4),
          // Ellipsizes only when a caller places the badge under a tight
          // constraint (the RecipeCard metadata row); in a Wrap it is unbounded
          // and renders in full.
          Flexible(
            child: Text(
              difficulty.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
