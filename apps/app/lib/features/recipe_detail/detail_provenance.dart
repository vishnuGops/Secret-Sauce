import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Where a recipe came from: the fork mark and the cook's own story.
///
/// Both layouts drew these themselves, a few pixels apart (32c5). They are the
/// same two statements about provenance, so they are one widget each here and
/// differ only in how the page around them frames them.

/// `⑂ Forked recipe` — the lineage mark above the title (canvas frame F).
///
/// It says what the row *knows*: `forked_from_recipe_id` is an id, and naming
/// the parent would need a second read neither layout makes.
class ForkedLabel extends StatelessWidget {
  const ForkedLabel({super.key, this.expand = false});

  /// Let the label take the row's free width. The compact page stacks it above
  /// the title in a full-width column, where an `Expanded` text can ellipsise;
  /// the expanded page sits it in a row of chips beside the back button, where
  /// it must size to its content.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = Text(
      'Forked recipe',
      style: Theme.of(
        context,
      ).textTheme.labelMedium?.copyWith(color: scheme.primary),
    );

    return Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      children: [
        Icon(Icons.call_split, size: 16, color: scheme.primary),
        const SizedBox(width: 4),
        if (expand) Expanded(child: label) else label,
      ],
    );
  }
}

/// The attribution / story block — the cook's own line about where the recipe
/// came from, which is the whole point of a family recipe vault.
class AttributionBlock extends StatelessWidget {
  const AttributionBlock({super.key, required this.text, this.boxed = false});

  final String text;

  /// Draw it as its own card. Compact does: on a phone the story follows the
  /// description with nothing else to separate them, so it needs an edge.
  /// The expanded header band already sits on `surfaceContainerLow` under a
  /// display-size title, where a second box would be one border too many — so
  /// there the text carries the distinction instead, in the secondary colour.
  final bool boxed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.auto_stories, size: 20, color: scheme.onSurfaceVariant),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            style:
                boxed
                    ? textTheme.bodyMedium
                    : textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
          ),
        ),
      ],
    );

    if (!boxed) return row;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: row,
    );
  }
}
