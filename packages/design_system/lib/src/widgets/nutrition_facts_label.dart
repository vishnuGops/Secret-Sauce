import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'package:design_system/src/layout/adaptive.dart';
import 'package:design_system/src/theme/app_theme.dart';

/// The nutrition panel, drawn like the label on a store product: heavy outer
/// rule, `Nutrition Facts` masthead, an oversized Calories row, per-nutrient
/// rows with a right-aligned `% Daily Value` column, and thick rules between
/// sections.
///
/// Lives in `design_system` (which already depends on `core`, so it takes a
/// [RecipeNutrition] directly) rather than in either detail layout, because the
/// two layouts must draw one label — the B066 discipline that produced the
/// shared ingredient rail.
///
/// Three things are deliberate:
///
///   * **No literal black.** A real label is black-on-white; this one is
///     `onSurface` on `surface`, so dark mode holds. The label's weight comes
///     from rule thickness and type weight, not from a hard-coded colour.
///   * **A row with no value does not render.** Every field is optional and a
///     cook who knows only the calories enters only that; printing `— g` for
///     the rest reads as data rather than as absence.
///   * **Values are per serving and are never multiplied.** [servings] and
///     [baseServings] move the two *lines* at the top — the serving count and
///     the batch total — not the numbers in the rows. Scaling 4 → 8 doubles the
///     batch and the servings, so one serving is unchanged.
class NutritionFactsLabel extends StatelessWidget {
  const NutritionFactsLabel({
    super.key,
    required this.nutrition,
    required this.servings,
    required this.baseServings,
  });

  final RecipeNutrition nutrition;

  /// The serving count currently selected by the stepper. Prints on the
  /// servings line and multiplies the calories on the batch line.
  final int servings;

  /// The recipe's own serving count — the basis the stored values are per.
  /// Shown only when the two differ, so the label says what it is a label *of*.
  final int baseServings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final ink = scheme.onSurface;
    final dim = scheme.onSurfaceVariant;

    final totalCalories =
        nutrition.calories == null ? null : nutrition.calories! * servings;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: ink, width: 2),
        borderRadius: BorderRadius.circular(AppRadii.button),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nutrition Facts',
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: ink,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${countOf(servings, 'servings')} per recipe',
            style: textTheme.bodyMedium?.copyWith(color: ink),
          ),
          Text(
            'Amount per serving',
            style: textTheme.bodySmall?.copyWith(color: dim),
          ),
          if (servings != baseServings)
            Text(
              'Per-serving values are unchanged — '
              'this recipe is written for $baseServings.',
              style: textTheme.bodySmall?.copyWith(color: dim),
            ),
          _Rule(color: ink, thickness: 8),
          if (nutrition.calories != null) ...[
            // The one row a real label sets in display type. `Wrap` rather than
            // `Row` for the usual reason (Gotcha 21): both children are
            // intrinsic, and at 2.0× on a 320px rail they do not fit beside
            // each other — the number drops to its own line instead of
            // overflowing.
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.sm,
                children: [
                  Text(
                    'Calories',
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: ink,
                    ),
                  ),
                  Text(
                    formatNutritionValue(nutrition.calories!),
                    style: textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: ink,
                    ),
                  ),
                ],
              ),
            ),
            // The one line the servings stepper actually moves. Grouped, so a
            // four-figure batch reads as `1,920` rather than `1920`.
            if (totalCalories != null)
              Text(
                '${countOf(servings, 'servings')} · '
                '${groupedScore(totalCalories)} kcal total',
                style: textTheme.bodySmall?.copyWith(color: dim),
              ),
          ],
          _Rule(color: ink, thickness: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '% Daily Value*',
              style: textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: ink,
              ),
            ),
          ),
          _Rule(color: scheme.outlineVariant, thickness: 1),
          _NutrientRow(
            label: 'Total Fat',
            value: nutrition.totalFatG,
            unit: 'g',
            dailyValue: kDvTotalFatG,
            bold: true,
          ),
          _NutrientRow(
            label: 'Saturated Fat',
            value: nutrition.saturatedFatG,
            unit: 'g',
            dailyValue: kDvSaturatedFatG,
            indent: 1,
          ),
          _NutrientRow(
            label: 'Trans Fat',
            value: nutrition.transFatG,
            unit: 'g',
            indent: 1,
          ),
          _NutrientRow(
            label: 'Cholesterol',
            value: nutrition.cholesterolMg,
            unit: 'mg',
            dailyValue: kDvCholesterolMg,
            bold: true,
          ),
          _NutrientRow(
            label: 'Sodium',
            value: nutrition.sodiumMg,
            unit: 'mg',
            dailyValue: kDvSodiumMg,
            bold: true,
          ),
          _NutrientRow(
            label: 'Total Carbohydrate',
            value: nutrition.totalCarbsG,
            unit: 'g',
            dailyValue: kDvTotalCarbsG,
            bold: true,
          ),
          _NutrientRow(
            label: 'Dietary Fiber',
            value: nutrition.dietaryFiberG,
            unit: 'g',
            dailyValue: kDvDietaryFiberG,
            indent: 1,
          ),
          _NutrientRow(
            label: 'Total Sugars',
            value: nutrition.totalSugarsG,
            unit: 'g',
            indent: 1,
          ),
          _NutrientRow(
            label: 'Includes Added Sugars',
            value: nutrition.addedSugarsG,
            unit: 'g',
            dailyValue: kDvAddedSugarsG,
            indent: 2,
          ),
          _NutrientRow(
            label: 'Protein',
            value: nutrition.proteinG,
            unit: 'g',
            dailyValue: kDvProteinG,
            bold: true,
          ),
          _Rule(color: ink, thickness: 4),
          Text(
            '* Percent Daily Values are based on a 2,000 calorie diet. '
            'Your daily values may be higher or lower depending on your '
            'calorie needs.',
            style: textTheme.bodySmall?.copyWith(color: dim),
          ),
        ],
      ),
    );
  }
}

/// One nutrient line: `Total Fat 10 g` on the left, `13%` on the right.
///
/// Renders nothing at all when [value] is null — the omission IS the design.
class _NutrientRow extends StatelessWidget {
  const _NutrientRow({
    required this.label,
    required this.value,
    required this.unit,
    this.dailyValue,
    this.bold = false,
    this.indent = 0,
  });

  final String label;
  final double? value;
  final String unit;

  /// The FDA reference this nutrient is measured against, or null for the three
  /// a real label leaves blank (calories, trans fat, total sugars).
  final double? dailyValue;

  final bool bold;

  /// 0 = top level, 1 = under fat / carbs, 2 = under total sugars.
  final int indent;

  @override
  Widget build(BuildContext context) {
    if (value == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final ink = scheme.onSurface;
    final percent =
        dailyValue == null ? null : percentDailyValue(value, dailyValue!);

    final style = textTheme.bodyMedium?.copyWith(
      color: ink,
      fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
    );

    return Padding(
      // The indent scales with the type: at 2.0× a fixed 12px inset stops
      // reading as a hierarchy against a doubled line height.
      padding: EdgeInsets.only(
        left: indent * 12 * context.textScale.clamp(1.0, 2.0),
        top: 3,
        bottom: 3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A `Wrap`, not a `Row`: both children are intrinsic and the rail is
          // 320–493px wide, so at 2.0× a long label ("Includes Added Sugars")
          // and its percentage do not fit on one line (Gotcha 21). The
          // percentage drops below rather than the row overflowing.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            children: [
              Text.rich(
                TextSpan(
                  text: label,
                  children: [
                    TextSpan(
                      text: ' ${formatNutritionValue(value!)} $unit',
                      style: style?.copyWith(fontWeight: FontWeight.w400),
                    ),
                  ],
                ),
                style: style,
              ),
              if (percent != null)
                Text(
                  '$percent%',
                  style: textTheme.bodyMedium?.copyWith(
                    color: ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
        ],
      ),
    );
  }
}

/// A horizontal rule of a given weight — the label's section separators.
///
/// A `Container` with a height and no child, which takes `constraints.biggest`
/// in a bounded `Column` (B060). It is only ever used in one, never as a
/// non-flex child of a `Row`, where the same widget would be zero-width.
class _Rule extends StatelessWidget {
  const _Rule({required this.color, required this.thickness});

  final Color color;
  final double thickness;

  @override
  Widget build(BuildContext context) => Container(
    height: thickness,
    color: color,
    margin: const EdgeInsets.symmetric(vertical: 4),
  );
}
