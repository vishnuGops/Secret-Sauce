import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/features/recipe_detail/detail_layout.dart';
import 'package:app/features/recipe_detail/recipe_detail_providers.dart';

/// The check-off box in front of each row.
const double _kCheckSize = 22;

/// Drops the box onto the first line's cap height.
const double _kCheckNudge = 1;

/// The unchecked box's outline.
const double _kCheckStroke = 2;

/// The `Ingredients` pane: grouped check-off list with a fixed quantity
/// gutter, plus its gathered counter and clear-checks footer.
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
        // The pane's title moved up to `RailPanel` in Phase 36c, as the panel's
        // `INGREDIENTS` kicker; the counter stays here beside the state it
        // counts. It is a lone `Text` now, so it wraps rather than overflowing
        // — the heading row it shared overflowed by 9.5px at 2.0× on compact
        // (B070) until it became a `Wrap`.
        Text(
          '$gathered of ${all.length} gathered',
          // Tabular: the count moves with every tap (UX-049).
          style: textTheme.labelMedium?.tabular.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        const Divider(height: 1),
        for (final group in recipe.ingredientGroups) ...[
          if (group.name.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(
                top: AppSpacing.smPlus,
                bottom: AppSpacing.xxs,
              ),
              // A heading to a screen reader too (UX-014).
              child: Semantics(
                header: true,
                child: Text(
                  group.name.toUpperCase(),
                  style: context.appText.overline.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
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
        const SizedBox(height: AppSpacing.smPlus),
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
    // Heavy and tabular, so the gutter scans as a column of numbers (UX-049).
    final qtyStyle = context.appText.quantity.copyWith(
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

    // One checkable node per row (UX-014): the quantity, name and note merge
    // into its label and `checked` carries the tick the box only draws.
    return MergeSemantics(
      child: Semantics(
        checked: done,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.md),
          // A 48dp target (UX-048): a one-line row was 35px tall. The row
          // centres in the extra height and a taller one grows past it.
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: kMinInteractiveDimension,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.xsPlus,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedContainer(
                      duration: AppMotion.of(context, AppMotion.fast),
                      width: _kCheckSize,
                      height: _kCheckSize,
                      margin: const EdgeInsets.only(top: _kCheckNudge),
                      decoration: BoxDecoration(
                        color: done ? scheme.primary : null,
                        border:
                            done
                                ? null
                                : Border.all(
                                  color: scheme.outline,
                                  width: _kCheckStroke,
                                ),
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                      ),
                      child:
                          done
                              ? Icon(
                                Icons.check,
                                size: AppIconSize.sm,
                                color: scheme.onPrimary,
                              )
                              : null,
                    ),
                    const SizedBox(width: AppSpacing.smPlus),
                    SizedBox(
                      // The gutter is what makes the numbers scan as a column, so it
                      // grows with the type rather than wrapping "1 1⁄3 cup" onto three
                      // lines. Same clamp as the rail that holds it.
                      width:
                          kIngredientQuantityGutter *
                          context.textScale.clamp(1.0, kDetailRailMaxScale),
                      child: Text(
                        ingredientQuantityLabel(ingredient, factor: factor),
                        // `1 1⁄3 cup` was read as "1 fraction slash 3"; the
                        // spoken form comes from the same chain, so it cannot
                        // disagree with the printed one (B066).
                        semanticsLabel: ingredientQuantitySpoken(
                          ingredient,
                          factor: factor,
                        ),
                        style: qtyStyle,
                      ),
                    ),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          text: sentenceCase(ingredient.name),
                          children: [
                            if (showNote)
                              TextSpan(
                                text: ' (${ingredient.note})',
                                style: noteStyle,
                              ),
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
            ),
          ),
        ),
      ),
    );
  }
}
