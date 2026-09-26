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
///   * the **container lives here** — and so does the section heading (36c),
///     so switching panes happens inside one frame rather than swapping two
///     differently-framed boxes;
///   * the tabs are the design system's [SegmentedTabs] (UX-032, Phase 37),
///     **not** a `SegmentedButton`. Compact's content box is 358 px and a
///     `SegmentedButton` is one intrinsic `Row` with no reflow escape (Gotcha
///     21) — which is why this was two `ChoiceChip`s in a `Wrap`. The pill
///     sized to its labels has the escape built in: under a bounded width it
///     scrolls sideways rather than overflow, and two short labels never need
///     it at 358 px x 2.0.
class RailPanel extends ConsumerWidget {
  const RailPanel({super.key, required this.recipe, this.bordered = true});

  final Recipe recipe;

  /// Whether to draw the panel — a `surfaceContainerLow` fill with card
  /// corners and **no outline** (Phase 36c: reference 5's panels carry no
  /// borders).
  ///
  /// Both layouts draw it since the owner's Q4 made ingredients and method
  /// two open panels on compact as well as expanded; false leaves the bare
  /// content for a caller that frames it itself. Everything inside is
  /// identical either way.
  final bool bordered;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final tab = ref.watch(railTabProvider(recipe.id));

    // A `Material`, not a decorated box: the check-off rows are `InkWell`s, and
    // ink paints on the nearest Material *under* its children — an opaque
    // decorated box in between hides every ripple and focus highlight (36c
    // review).
    return Material(
      color: bordered ? scheme.surfaceContainerLow : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The panel's heading names what the panel is showing, so it follows
            // the tab — `INGREDIENTS` over a nutrition label would be the heading
            // lying about its section.
            // A heading to a screen reader as well (UX-014).
            Semantics(
              header: true,
              child: Text(
                switch (tab) {
                  RailTab.ingredients => 'INGREDIENTS',
                  RailTab.nutrition => 'NUTRITION',
                },
                style: context.appText.kickerLarge.copyWith(
                  color: scheme.tertiary,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.smPlus),
            ServingsRow(recipe: recipe),
            const SizedBox(height: AppSpacing.sm),
            SegmentedTabs<RailTab>(
              values: RailTab.values,
              selected: tab,
              labelOf:
                  (value) => switch (value) {
                    RailTab.ingredients => 'Ingredients',
                    RailTab.nutrition => 'Nutrition',
                  },
              onSelected:
                  (value) =>
                      ref.read(railTabProvider(recipe.id).notifier).state =
                          value,
            ),
            const SizedBox(height: AppSpacing.sm),
            switch (tab) {
              RailTab.ingredients => IngredientRail(recipe: recipe),
              RailTab.nutrition => NutritionTab(recipe: recipe),
            },
          ],
        ),
      ),
    );
  }
}
