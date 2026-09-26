import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/features/recipe_detail/detail_chips.dart';
import 'package:app/features/recipe_detail/recipe_detail_providers.dart';
import 'package:app/routing/app_router.dart';

/// The v2 method column: tappable step rows that collapse when done, group
/// headers that keep per-group numbering visible, and the cook-mode teaser.
///
/// A done step shrinks to one dim line with its duration, so the next thing to
/// do is always the first full-size card on screen. Numbering restarts at 1 in
/// every group — that is how the data is authored (B022's ordering rules) and
/// flattening it to 1..N would lose the group identity.
class MethodColumn extends ConsumerWidget {
  const MethodColumn({super.key, required this.recipe});

  final Recipe recipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final allSteps = recipe.stepGroups.expand((g) => g.steps).toList();
    final done = ref.watch(doneStepsProvider(recipe.id));
    final doneCount = allSteps.where((s) => done.contains(s.id)).length;

    void toggle(String id) {
      final notifier = ref.read(doneStepsProvider(recipe.id).notifier);
      final next = Set<String>.of(notifier.state);
      if (!next.remove(id)) next.add(id);
      notifier.state = next;
    }

    final showGroupHeaders =
        recipe.stepGroups.length > 1 ||
        recipe.stepGroups.any((g) => g.name.isNotEmpty);

    // An open panel (the owner's Q4): reference 5's rounded, borderless
    // section, never collapsed — the rail beside or above it is the same.
    // A `Material`, not a decorated box, so the step rows' `InkWell` ink shows
    // (the same fix as RailPanel — 36c review).
    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'METHOD',
                  style: context.appText.kickerLarge.copyWith(
                    color: scheme.tertiary,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    '$doneCount of ${allSteps.length} done · '
                    'tap a step to tick it off',
                    textAlign: TextAlign.end,
                    // Tabular: the count moves with every tap (UX-049).
                    style: textTheme.labelMedium?.tabular.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.smPlus),
            for (final group in recipe.stepGroups) ...[
              if (showGroupHeaders)
                Padding(
                  padding: const EdgeInsets.only(
                    top: AppSpacing.xsPlus,
                    bottom: AppSpacing.smPlus,
                  ),
                  child: Row(
                    children: [
                      Text(
                        (group.name.isEmpty ? 'Steps' : group.name)
                            .toUpperCase(),
                        style: context.appText.overline.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      const Expanded(child: Divider(height: 1)),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        countOf(group.steps.length, 'steps'),
                        style: textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              for (var i = 0; i < group.steps.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.smPlus),
                  child: _StepCard(
                    step: group.steps[i],
                    number: i + 1,
                    done: done.contains(group.steps[i].id),
                    onTap: () => toggle(group.steps[i].id),
                  ),
                ),
            ],
            const SizedBox(height: AppSpacing.xs),
            _CookModeTeaser(recipeId: recipe.id),
          ],
        ),
      ),
    );
  }
}

/// The dashed "cook this hands-free" panel under the last step.
///
/// It stacks above [_kTeaserStackScale] rather than staying a row: the button
/// is the row's only non-flex child and "Start cooking" is ~390px wide at 2.0×
/// text scale, which is wider than the whole method column at the 1000px
/// window — a Row overflows there however flexible the copy beside it is
/// (Gotcha 21). Threshold rather than a measurement, the same shape `/chefs`
/// uses to drop to one column.
class _CookModeTeaser extends StatelessWidget {
  const _CookModeTeaser({required this.recipeId});

  final String recipeId;

  static const double _kTeaserStackScale = 1.3;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final stacked = context.textScale > _kTeaserStackScale;

    final icon = Icon(
      Icons.outdoor_grill,
      size: AppIconSize.lg,
      color: scheme.primary,
    );
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Cook this hands-free', style: textTheme.titleMedium),
        Text(
          'One step at a time, big type, timers you can start from the step.',
          style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
    final button = FilledButton(
      onPressed: () => context.push(Routes.cookRecipe(recipeId)),
      child: const Text('Start cooking'),
    );

    return Container(
      // The page surface inside the method panel: a lighter well rather than
      // an outline (36c — no borders on panels or cards).
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child:
          stacked
              ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      icon,
                      const SizedBox(width: AppSpacing.md),
                      Expanded(child: copy),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  button,
                ],
              )
              : Row(
                children: [
                  icon,
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: copy),
                  const SizedBox(width: AppSpacing.md),
                  button,
                ],
              ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.step,
    required this.number,
    required this.done,
    required this.onTap,
  });

  final RecipeStep step;
  final int number;
  final bool done;
  final VoidCallback onTap;

  /// The numbered disc (a check once done).
  static const double _kBadgeDiameter = 30;

  /// Gap between the disc and the step text.
  static const double _kBadgeGap = 14;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Reference 5's accent step numbers: a bare tabular figure in the
    // tertiary accent while the step is to do, a filled check once it is done.
    // The disc keeps its footprint either way so the text column never moves.
    final badge = Container(
      width: _kBadgeDiameter,
      height: _kBadgeDiameter,
      alignment: Alignment.center,
      decoration:
          done
              ? BoxDecoration(color: scheme.primary, shape: BoxShape.circle)
              : null,
      child:
          done
              ? Icon(
                Icons.check,
                size: AppIconSize.button,
                color: scheme.onPrimary,
              )
              : Text(
                '$number',
                style: textTheme.titleMedium?.tabular.copyWith(
                  color: scheme.tertiary,
                ),
              ),
    );

    if (done) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            children: [
              badge,
              const SizedBox(width: _kBadgeGap),
              Expanded(
                child: Text(
                  step.text,
                  style: textTheme.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (step.durationMinutes != null) ...[
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '${step.durationMinutes} min',
                  style: textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // No card: inside the method panel a step is a row, as in reference 5's
    // open method list. Transparent material so the ink still has a surface.
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              badge,
              const SizedBox(width: _kBadgeGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(step.text, style: textTheme.bodyLarge),
                    if (step.durationMinutes != null ||
                        (step.temperature?.isNotEmpty ?? false))
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.sm),
                        child: Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.xs,
                          children: [
                            if (step.durationMinutes != null)
                              MetaChip(
                                icon: Icons.timer_outlined,
                                label: '${step.durationMinutes} min',
                              ),
                            if (step.temperature?.isNotEmpty ?? false)
                              MetaChip(
                                icon: Icons.thermostat,
                                label: step.temperature!,
                              ),
                          ],
                        ),
                      ),
                    if (step.tip?.isNotEmpty ?? false)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.sm),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.lightbulb_outline,
                              size: AppIconSize.sm,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Expanded(
                              child: Text(
                                step.tip!,
                                style: textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
