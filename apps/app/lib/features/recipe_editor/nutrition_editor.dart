import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import 'package:app/features/recipe_editor/edit_models.dart';

/// The nutrition-facts half of the editor: eleven optional numbers, per
/// serving, entered by hand (Phase 28).
///
/// Same contract as the other two panels — the draft lives in
/// `_RecipeEditorScreenState`, and so does [expanded], because a failed save
/// has to be able to open the panel back up (see below). Every change calls
/// [onChanged] so the one `setState` that owns the form runs.
///
/// **Auto-calculate is not built and there is no button for it.** A
/// drawn-but-dead affordance is worse than absence (the Phase 27 rule); when it
/// lands it writes this same column.
class NutritionEditor extends StatelessWidget {
  const NutritionEditor({
    super.key,
    required this.nutrition,
    required this.expanded,
    required this.onToggle,
    required this.onChanged,
  });

  final EditNutrition nutrition;

  /// Collapsed when the recipe has no label, expanded when it does. Most
  /// recipes have none, and eleven empty boxes between Attribution and
  /// Ingredients would push the parts of the form everyone uses off the first
  /// screen — but a recipe that already carries values must never hide them.
  final bool expanded;

  final VoidCallback onToggle;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A Wrap, not a Row: the heading and the disclosure button are both
        // intrinsic, and at 2.0× on a 320px form they do not fit side by side
        // (Gotcha 21).
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            Text('Nutrition facts', style: textTheme.titleLarge),
            TextButton.icon(
              onPressed: onToggle,
              icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
              label: Text(expanded ? 'Hide' : 'Add'),
            ),
          ],
        ),
        Text(
          'Optional, and per serving — one serving of the count set above. '
          'Leave every box empty and the recipe shows no nutrition panel.',
          style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.md),
        // `maintainState: true`, so collapsing takes the fields off screen but
        // NOT out of the Form. A `TextFormField` that leaves the tree also
        // leaves `Form.validate()`, which would let a half-typed `1/2` be
        // collapsed out of sight and then silently dropped by `tryParse` on
        // save — the B066 shape exactly. The screen re-opens the panel when a
        // save is blocked, so a hidden error is never a dead end.
        Visibility(
          visible: expanded,
          maintainState: true,
          child: Column(
            children: [
              for (final field in [
                (nutrition.calories, 'Calories', 'kcal'),
                (nutrition.totalFat, 'Total fat', 'g'),
                (nutrition.saturatedFat, 'Saturated fat', 'g'),
                (nutrition.transFat, 'Trans fat', 'g'),
                (nutrition.cholesterol, 'Cholesterol', 'mg'),
                (nutrition.sodium, 'Sodium', 'mg'),
                (nutrition.totalCarbs, 'Total carbohydrate', 'g'),
                (nutrition.dietaryFiber, 'Dietary fiber', 'g'),
                (nutrition.totalSugars, 'Total sugars', 'g'),
                (nutrition.addedSugars, 'Added sugars', 'g'),
                (nutrition.protein, 'Protein', 'g'),
              ])
                _Field(
                  controller: field.$1,
                  label: field.$2,
                  unit: field.$3,
                  onChanged: onChanged,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One optional non-negative number.
///
/// The validator is the point: a non-parseable entry **blocks save** rather
/// than being silently dropped by `double.tryParse` on the way to the model.
class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.unit,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String unit;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label, suffixText: unit),
      onChanged: (_) => onChanged(),
      validator: (v) {
        final text = (v ?? '').trim();
        if (text.isEmpty) return null;
        final value = double.tryParse(text);
        if (value == null) return 'Numbers only — e.g. 12 or 1.5';
        if (value < 0) return 'Cannot be negative';
        return null;
      },
    ),
  );
}
