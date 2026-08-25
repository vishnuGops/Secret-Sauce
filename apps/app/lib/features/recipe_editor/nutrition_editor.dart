import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import 'package:app/features/recipe_editor/edit_models.dart';

/// The nutrition half of the editor: a three-way **Automatic / Manual / None**
/// choice (Phase 29c). Automatic previews the label `estimate_nutrition`
/// computes from the linked ingredients — and lists, by name, every row that
/// contributed nothing; Manual is Phase 28's eleven optional numbers; None
/// saves `null`.
///
/// Same contract as the other panels — the draft, the mode, and all of the
/// estimate state live in `_RecipeEditorScreenState`, because a failed save
/// has to be able to open the panel back up and a mode switch has rules
/// (seeding, confirmation) only the screen can arbitrate. Everything here
/// renders state and reports taps.
class NutritionEditor extends StatelessWidget {
  const NutritionEditor({
    super.key,
    required this.mode,
    required this.onModeSelected,
    required this.nutrition,
    required this.expanded,
    required this.onToggle,
    required this.onChanged,
    required this.groups,
    required this.servings,
    required this.estimate,
    required this.estimateLoading,
    required this.estimateError,
    required this.suggestions,
    required this.onRefreshEstimate,
    required this.onPickSuggestion,
  });

  final EditNutritionMode mode;
  final ValueChanged<EditNutritionMode> onModeSelected;

  final EditNutrition nutrition;

  /// Collapsed when the recipe has no label, expanded when it does. Most
  /// recipes have none, and the whole panel between Attribution and
  /// Ingredients would push the parts of the form everyone uses off the first
  /// screen — but a recipe that already carries values must never hide them.
  final bool expanded;

  final VoidCallback onToggle;
  final VoidCallback onChanged;

  /// The live ingredient draft — the Auto pane's "not counted" list needs the
  /// rows themselves (their names, their local skip reasons, and somewhere to
  /// write a picked link).
  final List<EditIngredientGroup> groups;

  /// The draft's serving count, for the preview label's serving lines.
  final int servings;

  /// The last `estimate_nutrition` reply, or null before the first one lands.
  final NutritionEstimate? estimate;
  final bool estimateLoading;
  final String? estimateError;

  /// `match_foods` candidates keyed by ingredient name, for the unlinked rows
  /// in the not-counted list — the human-confirmed review flow. Empty when
  /// nothing is unlinked or the lookup failed (a hint surface, never a gate).
  final Map<String, List<FoodHit>> suggestions;

  final VoidCallback onRefreshEstimate;
  final void Function(EditIngredient row, FoodHit hit) onPickSuggestion;

  static const _helperText = {
    EditNutritionMode.auto:
        'Computed from the linked ingredients, per serving, and marked as an '
        'estimate. The saved label is recalculated on the server from the '
        'same ingredient list.',
    EditNutritionMode.manual:
        'Optional, and per serving — one serving of the count set above. '
        'Leave every box empty and the recipe shows no nutrition panel.',
    EditNutritionMode.none: 'The recipe shows no nutrition panel.',
  };

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
          _helperText[mode]!,
          style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.md),
        // `maintainState: true`, so collapsing takes the fields off screen but
        // NOT out of the Form. A `TextFormField` that leaves the tree also
        // leaves `Form.validate()`, which would let a half-typed `1/2` be
        // collapsed out of sight and then silently dropped by `tryParse` on
        // save — the B066 shape exactly (B072). The screen re-opens the panel
        // when a save is blocked, so a hidden error is never a dead end.
        Visibility(
          visible: expanded,
          maintainState: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ChoiceChips in a Wrap, not a SegmentedButton: a segmented
              // control is one intrinsic Row and three labels at 2.0× on a
              // 320px form do not fit side by side (Gotcha 21) — chips wrap.
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final (m, label) in const [
                    (EditNutritionMode.auto, 'Automatic'),
                    (EditNutritionMode.manual, 'Manual'),
                    (EditNutritionMode.none, 'None'),
                  ])
                    ChoiceChip(
                      label: Text(label),
                      selected: mode == m,
                      onSelected: (_) => onModeSelected(m),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              switch (mode) {
                EditNutritionMode.manual => _ManualFields(
                  nutrition: nutrition,
                  onChanged: onChanged,
                ),
                EditNutritionMode.auto => _AutoPane(
                  groups: groups,
                  servings: servings,
                  estimate: estimate,
                  loading: estimateLoading,
                  error: estimateError,
                  suggestions: suggestions,
                  onRefresh: onRefreshEstimate,
                  onPickSuggestion: onPickSuggestion,
                ),
                // None needs no body — the helper line above already says
                // what it means.
                EditNutritionMode.none => const SizedBox.shrink(),
              },
            ],
          ),
        ),
      ],
    );
  }
}

/// Phase 28's eleven optional numbers, unchanged.
class _ManualFields extends StatelessWidget {
  const _ManualFields({required this.nutrition, required this.onChanged});

  final EditNutrition nutrition;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => Column(
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
  );
}

/// The Automatic pane: the honesty header (counted of total, refresh), the
/// preview label, and the not-counted list with link suggestions.
class _AutoPane extends StatelessWidget {
  const _AutoPane({
    required this.groups,
    required this.servings,
    required this.estimate,
    required this.loading,
    required this.error,
    required this.suggestions,
    required this.onRefresh,
    required this.onPickSuggestion,
  });

  final List<EditIngredientGroup> groups;
  final int servings;
  final NutritionEstimate? estimate;
  final bool loading;
  final String? error;
  final Map<String, List<FoodHit>> suggestions;
  final VoidCallback onRefresh;
  final void Function(EditIngredient row, FoodHit hit) onPickSuggestion;

  /// The not-counted rows, with the reason each contributed nothing. The
  /// local facts (optional, unlinked, no quantity) are derived from the draft
  /// so the list is right even before the RPC answers; only "the registry
  /// cannot convert this unit for this food" needs the server's word, which
  /// is what [NutritionEstimate.unmatched] adds.
  List<(EditIngredient, String, String)> _uncounted() {
    final unmatched = {...?estimate?.unmatched};
    final rows = <(EditIngredient, String, String)>[];
    for (final g in groups) {
      for (final i in g.ingredients) {
        final name = i.name.text.trim();
        if (name.isEmpty) continue;
        final String? reason;
        if (i.isOptional) {
          reason = 'optional';
        } else if (i.foodId == null) {
          reason = 'not linked to a food';
        } else if (double.tryParse(i.quantity.text.trim()) == null) {
          reason = 'no quantity';
        } else if (unmatched.contains(name)) {
          reason = 'unit cannot be converted';
        } else {
          reason = null;
        }
        if (reason != null) rows.add((i, name, reason));
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    if (loading && estimate == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: LinearProgressIndicator(),
      );
    }
    if (error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Could not compute an estimate.\n$error',
            style: textTheme.bodySmall?.copyWith(color: scheme.error),
          ),
          TextButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      );
    }
    final data = estimate;
    if (data == null) return const SizedBox.shrink();

    final uncounted = _uncounted();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Counted-of-total + refresh. A Wrap for the usual reason (Gotcha 21).
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.sm,
          children: [
            Text(
              'Estimated from ${data.counted} of '
              '${countOf(data.total, 'ingredients')}',
              style: textTheme.titleSmall,
            ),
            IconButton(
              icon: const Icon(Icons.refresh, size: 18),
              tooltip: 'Recalculate estimate',
              onPressed: loading ? null : onRefresh,
            ),
          ],
        ),
        if (loading)
          const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.sm),
            child: LinearProgressIndicator(),
          ),
        if (!data.hasLabel)
          // The warned-about state: Automatic selected, nothing to compute.
          // Saving stores null (the server normalizes the same way), so say
          // that here rather than letting the mode collapse read as data loss.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(AppRadii.card),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: scheme.onSurfaceVariant),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Nothing to estimate from yet',
                  style: textTheme.titleSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Link ingredients to foods with the name suggestions below '
                  '(or in the ingredient list), and give them quantities in '
                  'convertible units. Saving now keeps the recipe without a '
                  'nutrition label.',
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          )
        else ...[
          NutritionFactsLabel(
            nutrition: data.label!,
            servings: servings,
            baseServings: servings,
            isEstimated: true,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Preview — the saved label is recalculated from the ingredient '
            'list when you save.',
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        if (uncounted.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text('Not counted', style: textTheme.titleSmall),
          Text(
            'These ingredients contribute nothing to the estimate.',
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          for (final (row, name, reason) in uncounted)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      text: name,
                      children: [
                        TextSpan(
                          text: ' — $reason',
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    style: textTheme.bodyMedium,
                  ),
                  // The review flow: top match_foods candidates for an
                  // unlinked name; a tap links the row — inference proposes,
                  // the human confirms, and only the confirmed link is
                  // stored. Chips wrap, and a long food name ellipsises
                  // inside its chip rather than overflowing (Gotcha 21).
                  if ((suggestions[name] ?? const []).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: [
                          for (final hit in suggestions[name]!)
                            ActionChip(
                              avatar: const Icon(Icons.link, size: 16),
                              visualDensity: VisualDensity.compact,
                              label: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 200,
                                ),
                                child: Text(
                                  hit.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              onPressed: () => onPickSuggestion(row, hit),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
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
