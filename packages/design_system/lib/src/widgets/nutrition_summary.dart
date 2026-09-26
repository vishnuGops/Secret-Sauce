import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'package:design_system/src/theme/app_theme.dart';

/// The per-serving headline numbers as a row of small cards — reference 5's
/// "Nutrition per serving" strip (Phase 36c). It sits **above** the full
/// [NutritionFactsLabel], which stays the authoritative panel (Preserve).
///
/// Calories, fat, carbohydrate, protein — whichever the label has. %DV is
/// printed only where the FDA label prints one: there is **no** %DV for
/// calories, so none is invented here (honest numbers, DESIGN §1). Values are
/// per serving and never scaled (SDS §3.2). A `Wrap`, so four cards that do
/// not fit a phone's width go to a second line instead of overflowing.
class NutritionSummary extends StatelessWidget {
  const NutritionSummary({super.key, required this.nutrition});

  final RecipeNutrition nutrition;

  /// Whether the summary would print anything — at least one of calories,
  /// fat, carbohydrate or protein. A label holding only, say, sodium is a
  /// real label with nothing for this strip; callers gate on this so no empty
  /// gap is left behind (36c review).
  static bool hasAny(RecipeNutrition? n) =>
      n != null &&
      (n.calories != null ||
          n.totalFatG != null ||
          n.totalCarbsG != null ||
          n.proteinG != null);

  @override
  Widget build(BuildContext context) {
    final n = nutrition;
    final items = <_Figure>[
      if (n.calories != null)
        _Figure('Calories', formatNutritionValue(n.calories!), null),
      if (n.totalFatG != null)
        _Figure(
          'Fat',
          '${formatNutritionValue(n.totalFatG!)}g',
          percentDailyValue(n.totalFatG, kDvTotalFatG),
        ),
      if (n.totalCarbsG != null)
        _Figure(
          'Carbs',
          '${formatNutritionValue(n.totalCarbsG!)}g',
          percentDailyValue(n.totalCarbsG, kDvTotalCarbsG),
        ),
      if (n.proteinG != null)
        _Figure(
          'Protein',
          '${formatNutritionValue(n.proteinG!)}g',
          percentDailyValue(n.proteinG, kDvProteinG),
        ),
    ];
    if (items.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [for (final item in items) _FigureCard(item: item)],
    );
  }
}

class _Figure {
  const _Figure(this.label, this.value, this.percent);

  final String label;
  final String value;
  final int? percent;
}

class _FigureCard extends StatelessWidget {
  const _FigureCard({required this.item});

  final _Figure item;

  /// Wide enough for `Calories` over a four-digit figure at 1.0×; the card
  /// grows with text scale rather than truncating a number.
  static const double _minWidth = 96;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final label =
        '${item.label}${item.percent == null ? '' : ', ${item.percent}% daily value'}';

    return Semantics(
      label: '$label: ${item.value}',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minWidth: _minWidth),
        padding: const EdgeInsets.all(AppSpacing.smPlus),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.label,
                  style: text.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (item.percent != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '${item.percent}%',
                    style: text.labelMedium?.tabular.copyWith(
                      color: scheme.onSurface,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              item.value,
              style: context.appText.statLarge.copyWith(color: scheme.tertiary),
            ),
          ],
        ),
      ),
    );
  }
}
