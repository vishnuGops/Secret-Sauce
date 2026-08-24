import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/features/recipe_detail/detail_layout.dart';
import 'package:app/features/recipe_detail/recipe_detail_providers.dart';

/// The v2 ingredients panel: servings scaler, grouped check-off list with a
/// fixed quantity gutter, and a clear-checks footer.
///
/// Quantities live in their own column so the numbers scan vertically while
/// shopping; scaled quantities turn primary-coloured when servings differ from
/// the recipe's own, and times/temperatures never scale (same rule as v1).
/// Names are sentence-cased at render — the DB stores them lowercase, and in a
/// quantity/name grid the capital is the left edge of the scanned column.
class IngredientRail extends ConsumerWidget {
  const IngredientRail({super.key, required this.recipe});

  final Recipe recipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final servings =
        ref.watch(selectedServingsProvider(recipe.id)) ?? recipe.servings;
    final factor = recipe.servings == 0 ? 1.0 : servings / recipe.servings;
    final scaled = factor != 1.0;

    final all = recipe.ingredientGroups.expand((g) => g.ingredients).toList();
    final checked = ref.watch(checkedIngredientsProvider(recipe.id));
    final gathered = all.where((i) => checked.contains(i.id)).length;

    void toggle(String id) {
      final notifier = ref.read(checkedIngredientsProvider(recipe.id).notifier);
      final next = Set<String>.of(notifier.state);
      if (!next.remove(id)) next.add(id);
      notifier.state = next;
    }

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text('Ingredients', style: textTheme.titleLarge)),
              Text(
                '$gathered of ${all.length} gathered',
                style: textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // A Wrap, not a Row: the two icon buttons and the count are non-flex
          // and grow with text scale, so at 2.0× they are wider than the rail
          // and a Row overflows however flexible the label is (Gotcha 21). The
          // stepper drops to its own line instead.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              Text(
                'Servings',
                style: textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton.filledTonal(
                    tooltip: 'Fewer servings',
                    icon: const Icon(Icons.remove, size: 20),
                    onPressed:
                        servings > 1
                            ? () =>
                                ref
                                    .read(
                                      selectedServingsProvider(
                                        recipe.id,
                                      ).notifier,
                                    )
                                    .state = servings - 1
                            : null,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                    child: Text('$servings', style: textTheme.titleMedium),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'More servings',
                    icon: const Icon(Icons.add, size: 20),
                    onPressed:
                        () =>
                            ref
                                .read(
                                  selectedServingsProvider(recipe.id).notifier,
                                )
                                .state = servings + 1,
                  ),
                ],
              ),
            ],
          ),
          if (scaled) ...[
            const SizedBox(height: AppSpacing.xs),
            Text.rich(
              TextSpan(
                text: 'Scaled from ${recipe.servings} — quantities in ',
                children: [
                  TextSpan(
                    text: 'colour',
                    style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const TextSpan(
                    text: ' changed. Times and temperatures are unchanged.',
                  ),
                ],
              ),
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          const Divider(height: 1),
          for (final group in recipe.ingredientGroups) ...[
            if (group.name.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 2),
                child: Text(
                  group.name.toUpperCase(),
                  style: textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            for (final ing in group.ingredients)
              _IngredientRow(
                ingredient: ing,
                factor: factor,
                highlightScaled: scaled && ing.quantity != null,
                done: checked.contains(ing.id),
                onTap: () => toggle(ing.id),
              ),
          ],
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.xs),
          // Same reason as the servings row: the button is non-flex and is
          // wider than the rail at 2.0×, so the note wraps under it instead of
          // the row overflowing.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              TextButton(
                onPressed:
                    checked.isEmpty
                        ? null
                        : () =>
                            ref
                                .read(
                                  checkedIngredientsProvider(
                                    recipe.id,
                                  ).notifier,
                                )
                                .state = const {},
                child: const Text('Clear checks'),
              ),
              Text(
                'Checks last until you close the app',
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IngredientRow extends StatelessWidget {
  const _IngredientRow({
    required this.ingredient,
    required this.factor,
    required this.highlightScaled,
    required this.done,
    required this.onTap,
  });

  final Ingredient ingredient;
  final double factor;
  final bool highlightScaled;
  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final dimColor = scheme.onSurfaceVariant;
    final struck = done ? TextDecoration.lineThrough : null;
    final qtyStyle = textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w800,
      color:
          done
              ? dimColor
              : highlightScaled
              ? scheme.primary
              : null,
      decoration: struck,
    );
    final nameStyle = textTheme.bodyMedium?.copyWith(
      color: done ? dimColor : null,
      decoration: struck,
    );
    final noteStyle = textTheme.bodyMedium?.copyWith(
      color: dimColor,
      decoration: struck,
    );

    // The note doubles as the quantity when the gutter has nothing else to show
    // ("to taste"), and only then — otherwise it rides along with the name, so
    // a unit-without-quantity row keeps both halves. The chain itself lives in
    // core (B066) because cook mode's rail draws the same gutter, and two copies
    // of it is how the two sides of the 1000px branch disagreed in the first
    // place.
    final showNote =
        (ingredient.note ?? '').isNotEmpty &&
        !ingredientNoteIsQuantity(ingredient);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.button),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 22,
              height: 22,
              margin: const EdgeInsets.only(top: 1),
              decoration: BoxDecoration(
                color: done ? scheme.primary : null,
                border:
                    done ? null : Border.all(color: scheme.outline, width: 2),
                borderRadius: BorderRadius.circular(6),
              ),
              child:
                  done
                      ? Icon(Icons.check, size: 16, color: scheme.onPrimary)
                      : null,
            ),
            const SizedBox(width: 12),
            SizedBox(
              // The gutter is what makes the numbers scan as a column, so it
              // grows with the type rather than wrapping "1.25 cup" onto three
              // lines. Same clamp as the rail that holds it.
              width:
                  kIngredientQuantityGutter *
                  context.textScale.clamp(1.0, kDetailRailMaxScale),
              child: Text(
                ingredientQuantityLabel(ingredient, factor: factor),
                style: qtyStyle,
              ),
            ),
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: sentenceCase(ingredient.name),
                  children: [
                    if (showNote)
                      TextSpan(text: ' (${ingredient.note})', style: noteStyle),
                    if (ingredient.isOptional)
                      TextSpan(text: ' — optional', style: noteStyle),
                  ],
                ),
                style: nameStyle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
