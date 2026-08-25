import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/features/recipe_detail/recipe_detail_providers.dart';

/// The `Nutrition` pane: a [NutritionFactsLabel], or the empty state for a
/// recipe with no data.
///
/// Reads the **same** `selectedServingsProvider` the ingredient list and cook
/// mode read, and hands it to the label as the scaled count. The label does not
/// multiply its per-serving numbers by it — scaling 4 → 8 doubles the batch and
/// the servings, so a serving is unchanged — it prints the batch total instead.
///
/// `recipe.nutrition == null` is the ONE representation of "no info": an
/// all-empty entry is normalized to null in the editor, and the column's own
/// value is null. So this branch is the whole empty-state logic.
class NutritionTab extends ConsumerWidget {
  const NutritionTab({super.key, required this.recipe});

  final Recipe recipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nutrition = recipe.nutrition;
    // `isEmpty` as well as `null`: the normalizations upstream should make the
    // second unreachable, but a `{}` arriving from a hand-edited row must not
    // render a label with a masthead and no rows.
    if (nutrition == null || nutrition.isEmpty) return const _NoNutrition();

    final servings =
        ref.watch(selectedServingsProvider(recipe.id)) ?? recipe.servings;

    return NutritionFactsLabel(
      nutrition: nutrition,
      servings: servings,
      baseServings: recipe.servings,
    );
  }
}

/// What the tab says when there is nothing to draw.
///
/// Deliberately no "Add nutrition" button: auto-calculate is not built, and the
/// only way to add values is the editor, which the owner reaches from the page
/// chrome. A drawn-but-dead affordance is worse than absence — the Phase 27
/// rule.
class _NoNutrition extends StatelessWidget {
  const _NoNutrition();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: scheme.onSurfaceVariant),
          const SizedBox(height: AppSpacing.sm),
          Text('No nutrition info available', style: textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Nutrition facts are entered by whoever wrote the recipe, and '
            'this one has none yet.',
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
