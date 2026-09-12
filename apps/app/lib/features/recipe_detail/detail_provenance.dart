import 'package:core/core.dart';
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

/// Where an imported recipe came from (Phase 35c).
///
/// This is not decoration and it is not optional. The rights position the app
/// states — store and show the functional part of a recipe, link everything
/// expressive — only holds because the credit and the link travel with the
/// content. A captured recipe rendered without them is the same bytes making a
/// different, and indefensible, claim.
///
/// Rendered for imported recipes only. A member's own recipe is credited by its
/// owner badge like every other, and a second credit line under it would read
/// as a second author.
class SourceCredit extends StatelessWidget {
  const SourceCredit({super.key, required this.recipe});

  final Recipe recipe;

  @override
  Widget build(BuildContext context) {
    if (!recipe.isImported) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final publisher = recipe.sourceName;
    final url = recipe.sourceUrl;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.link, size: 20, color: scheme.onSurfaceVariant),
              const SizedBox(width: AppSpacing.sm),
              // The icon is the non-flex child and the text takes what is left
              // (Gotcha 21). A publisher name is unbounded, so nothing here may
              // be intrinsically sized beside it.
              Expanded(
                child: Text(
                  publisher == null || publisher.isEmpty
                      ? 'Published elsewhere'
                      : 'Published by $publisher',
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),
          if (url != null && url.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            // Printed rather than launched, for now. Which outbound links open
            // and how is a decision (target, `noopener`, whether a tap leaves
            // the app at all), and printing the address already does the job the
            // rights position needs: a reader can go and read the original.
            SelectableText(
              url,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          if (!recipe.showsContent) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'This publisher asked us to link rather than reproduce, so the '
              'method is on their page.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
