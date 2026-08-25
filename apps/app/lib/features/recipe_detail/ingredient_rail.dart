import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/features/recipe_detail/detail_layout.dart';
import 'package:app/features/recipe_detail/recipe_detail_providers.dart';

/// The `Ingredients` pane: grouped check-off list with a fixed quantity
/// gutter, plus its heading and clear-checks footer.
///
/// Quantities live in their own column so the numbers scan vertically while
/// shopping; scaled quantities turn primary-coloured when servings differ from
/// the recipe's own, and times/temperatures never scale (same rule as v1).
/// Names are sentence-cased at render — the DB stores them lowercase, and in a
/// quantity/name grid the capital is the left edge of the scanned column.
///
/// **This is a pane, not a panel** (Phase 28). It no longer owns the servings
/// stepper (now [ServingsRow], hoisted so it stays visible on the Nutrition
/// tab), the card border, or the padding — all three moved up to `RailPanel`,
/// the host both detail layouts actually place. One widget for both layouts is
/// still the point: B066 was two copies of this list disagreeing.
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A Wrap for the same reason as the footer row below it: the gathered
        // counter is non-flex and therefore laid out unbounded (Gotcha 21), so
        // at 2.0× it overflowed the heading row by 9.5px — on **compact**,
        // where the rail is the 358px content box of a 390px phone rather than
        // the 493px column the expanded page gives it. The widget was correct
        // at every width it had been pumped at until compact v2 reused it.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            Text('Ingredients', style: textTheme.titleLarge),
            Text(
              '$gathered of ${all.length} gathered',
              style: textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
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
                                checkedIngredientsProvider(recipe.id).notifier,
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
