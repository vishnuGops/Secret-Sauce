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

  bool get _hasUnit => (ingredient.unit ?? '').isNotEmpty;

  bool get _hasNote => (ingredient.note ?? '').isNotEmpty;

  /// True when the gutter has nothing but the note to show, so the note is the
  /// quantity ("to taste") and must not also ride along with the name.
  bool get _noteIsQuantity =>
      ingredient.quantity == null && !_hasUnit && _hasNote;

  /// What goes in the gutter: `1.5 cup`, the bare unit, the note, or a dash —
  /// in that order.
  ///
  /// The unit fallback matters because `quantity` is nullable and the editor
  /// reaches that state by accident: type `1/2` in the quantity field, the
  /// parse fails, and the row saves with `unit: 'cup'` and no number. The v1
  /// renderer ([recipe_content_views.dart]) prints the unit either way, so
  /// without this the same row read differently on the two sides of the 1000px
  /// branch (B066). The unit outranks the note because a unit with no number is
  /// a data defect worth seeing, while a note is prose that reads fine beside
  /// the name.
  String get _quantityLabel {
    final quantity = ingredient.quantity;
    final unit = ingredient.unit;
    if (quantity == null) {
      if (_hasUnit) return unit!;
      return _hasNote ? ingredient.note! : '—';
    }
    final amount = _trim(quantity * factor);
    return _hasUnit ? '$amount $unit' : amount;
  }

  static String _trim(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  static String _sentenceCase(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

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
    // a unit-without-quantity row keeps both halves.
    final showNote = _hasNote && !_noteIsQuantity;

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
              child: Text(_quantityLabel, style: qtyStyle),
            ),
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: _sentenceCase(ingredient.name),
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
