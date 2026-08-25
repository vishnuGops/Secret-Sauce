import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/features/recipe_detail/ingredient_rail.dart';
import 'package:app/features/recipe_detail/nutrition_tab.dart';
import 'package:app/features/recipe_detail/recipe_detail_providers.dart';
import 'package:app/features/recipe_detail/servings_row.dart';

/// The rail both detail layouts place: servings stepper on top, two tabs under
/// it, and the active pane below (Phase 28).
///
/// This is the host that used to be `IngredientRail` itself. The split matters
/// in three ways:
///
///   * the **stepper is above the tabs**, so it stays on screen on either one.
///     The nutrition label's batch line is calories × the selected servings, so
///     a control hidden behind the other tab would make that line
///     unexplainable — and a second stepper in the nutrition pane is B066 by
///     construction;
///   * the **container lives here**, so switching panes happens inside one
///     frame rather than swapping two differently-bordered boxes;
///   * the tabs are two [ChoiceChip]s in a [Wrap], **not** a `SegmentedButton`.
///     Compact's content box is 358 px and a segmented control is one intrinsic
///     `Row` with no reflow escape (Gotcha 21); chips wrap instead, which is the
///     move the three rows inside the ingredient pane already make.
class RailPanel extends ConsumerWidget {
  const RailPanel({super.key, required this.recipe, this.bordered = true});

  final Recipe recipe;

  /// Whether to draw the card border and background.
  ///
  /// True on the expanded page, where the rail is a column *beside* the method
  /// and needs an edge to be a column at all. False on compact, where it is a
  /// full-width section between two dividers and a border would be a box drawn
  /// round the whole screen. Everything inside is identical either way.
  final bool bordered;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final tab = ref.watch(railTabProvider(recipe.id));

    return Container(
      decoration:
          bordered
              ? BoxDecoration(
                color: scheme.surfaceContainerLowest,
                border: Border.all(color: scheme.outlineVariant),
                borderRadius: BorderRadius.circular(AppRadii.card),
              )
              : null,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ServingsRow(recipe: recipe),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              for (final entry
                  in const {
                    RailTab.ingredients: 'Ingredients',
                    RailTab.nutrition: 'Nutrition',
                  }.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: tab == entry.key,
                  onSelected:
                      (_) =>
                          ref.read(railTabProvider(recipe.id).notifier).state =
                              entry.key,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          switch (tab) {
            RailTab.ingredients => IngredientRail(recipe: recipe),
            RailTab.nutrition => NutritionTab(recipe: recipe),
          },
        ],
      ),
    );
  }
}
