import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// The two smallest pieces of the expanded chef card, shared by both panels:
/// the all-caps section kicker and the muted note an empty or failed section
/// falls back to (OPT-A8).

class ChefKicker extends StatelessWidget {
  const ChefKicker({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
      ),
    );
  }
}

class ChefNote extends StatelessWidget {
  const ChefNote({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
