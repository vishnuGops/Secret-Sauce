import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// The two small controls the detail screen's header row is built from: a
/// read-only metadata chip and the like/save counter button (OPT-A8).

class MetaChip extends StatelessWidget {
  const MetaChip({super.key, required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class CountAction extends StatelessWidget {
  const CountAction({
    super.key,
    required this.icon,
    required this.activeIcon,
    required this.active,
    required this.count,
    required this.tooltip,
    required this.activeTooltip,
    required this.onTap,
  });

  final IconData icon;

  /// Filled variant, shown once the current user has liked/saved this recipe.
  /// This was a dead parameter until B051 gave the screen something to read.
  final IconData activeIcon;
  final bool active;
  final int count;
  final String tooltip;
  final String activeTooltip;

  /// Receives the state the button is currently in, so the handler can write
  /// the opposite of it.
  final void Function(bool active) onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: active ? activeTooltip : tooltip,
      child: OutlinedButton.icon(
        onPressed: () => onTap(active),
        icon: Icon(
          active ? activeIcon : icon,
          size: 18,
          color: active ? scheme.primary : null,
        ),
        // Grouped, like every other counter in the product (B031's family):
        // a recipe with 1,500 likes read `1500` here and `1,500` on the chef
        // card three taps away.
        label: Text(groupedCount(count)),
      ),
    );
  }
}
