import 'package:flutter/material.dart';

import 'package:design_system/src/theme/app_theme.dart';

/// The small `AI` pill on a cover that was generated rather than photographed
/// (DESIGN §2.2, owner decision 2026-09-27). "AI", not "Illustration": the
/// slot is a corner of a 288px card, and the full sentence is one hover or
/// long-press away in the tooltip, and is what a screen reader hears.
///
/// On the same scrim as the card's chef badge — covers are arbitrary photos,
/// so the pill carries its own contrast.
class GeneratedImageTag extends StatelessWidget {
  const GeneratedImageTag({super.key});

  /// What the tag means, in words: the tooltip and the semantics label.
  static const String description = 'AI-generated image';

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Tooltip(
      message: description,
      child: Semantics(
        label: description,
        excludeSemantics: true,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: palette.scrim,
            shape: const StadiumBorder(),
          ),
          child: Padding(
            padding: AppInsets.badge,
            child: Text(
              'AI',
              maxLines: 1,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: palette.onImage),
            ),
          ),
        ),
      ),
    );
  }
}
