import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/features/recipe_detail/recipe_detail_providers.dart';

/// The servings stepper and its `Scaled from N` banner.
///
/// Extracted out of `IngredientRail` (Phase 28) and hoisted into `RailPanel`,
/// above the tab chips, so it stays on screen on **either** tab. Nutrition
/// depends on the serving count exactly as the ingredient list does — the
/// label's batch line is calories × the selected servings — and a stepper
/// trapped inside the Ingredients tab would leave that line unexplainable.
///
/// A second stepper inside the nutrition pane was the other option, and it is
/// B066 by construction: two controls writing what has to be one number.
class ServingsRow extends ConsumerWidget {
  const ServingsRow({super.key, required this.recipe});

  final Recipe recipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final servings =
        ref.watch(selectedServingsProvider(recipe.id)) ?? recipe.servings;
    // Same guard as `IngredientRail`'s `factor`, and it has to stay the same
    // guard. A recipe saved with `servings = 0` is reachable — the editor's box
    // is `int.tryParse(…) ?? 1`, `save_recipe` only coalesces a *null*, and the
    // column has no positive check — and the rail leaves such a recipe's
    // quantities unscaled. A banner promising a colour change here would then
    // describe one the list below does not make.
    final scaled = recipe.servings != 0 && servings != recipe.servings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
      ],
    );
  }
}
