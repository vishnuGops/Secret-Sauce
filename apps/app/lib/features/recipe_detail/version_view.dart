import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/features/recipe_detail/recipe_detail_providers.dart';

/// The widest the version view gets on a window wider than a phone — a
/// reading measure, the same order as the detail page's method column, so a
/// 1440px window does not stretch one ingredient line across the screen.
const double _kVersionViewMaxWidth = AppMeasure.reading;

/// A recipe as it stood at one version, read-only (UX-052).
///
/// History rows used to be inert: the list said a version existed and gave no
/// way to see it. This shows that version's own snapshot — title, ingredients,
/// steps — fetched on open through [versionContentProvider], never through the
/// history list, which leaves `content_snapshot` out on purpose (B065).
///
/// Read-only means read-only: no check-offs and no servings scaler, because
/// both are the *current* recipe's reading state (`checkedIngredientsProvider`,
/// `selectedServingsProvider`) and an old version must not write to either.
/// Quantities go through core's one chain (`ingredientOneLine`), so a version
/// prints `1¼ cup` exactly as the recipe page would have (B066).
class VersionView extends ConsumerWidget {
  const VersionView({super.key, required this.version});

  final RecipeVersion version;

  /// Opens the view over whatever is on screen — full screen on a phone, a
  /// measured dialog anywhere wider. Root navigator (Gotcha 23), so it sits
  /// above the history sheet and any shell chrome alike.
  static Future<void> show(BuildContext context, RecipeVersion version) {
    final compact = context.isCompact;
    return showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder:
          (_) =>
              compact
                  ? Dialog.fullscreen(child: VersionView(version: version))
                  : Dialog(
                    clipBehavior: Clip.antiAlias,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: _kVersionViewMaxWidth,
                      ),
                      child: VersionView(version: version),
                    ),
                  ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final content = ref.watch(versionContentProvider(version.id));
    final meta = [
      if (version.createdAt != null) isoDate(version.createdAt!),
      if (version.changeSummary.trim().isNotEmpty) version.changeSummary.trim(),
    ];

    return Column(
      // Min, with the body [Flexible]: the wide dialog is as tall as the
      // version, and scrolls only when the version is taller than the window.
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.sm,
            AppSpacing.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          'Version ${version.versionNumber}',
                          style: textTheme.titleLarge,
                        ),
                      ),
                      if (meta.isNotEmpty)
                        Text(
                          meta.join(' · '),
                          style: textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Flexible(
          child: switch (content) {
            AsyncData(value: final recipe?) => _Snapshot(recipe: recipe),
            // The two message states scroll: at 2.0x on a phone the
            // explanation alone is taller than what the header leaves.
            AsyncData() => const SingleChildScrollView(
              child: EmptyView(
                icon: Icons.history,
                title: 'Nothing saved for this version',
                message:
                    'This version was saved before Secret Sauce kept a copy '
                    'of each version, so there is nothing to show.',
              ),
            ),
            AsyncError(:final error) => SingleChildScrollView(
              child: ErrorView(
                message: friendlyError(error),
                onRetry:
                    () => ref.invalidate(versionContentProvider(version.id)),
              ),
            ),
            _ => const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: LoadingView(),
            ),
          },
        ),
      ],
    );
  }
}

/// The snapshot itself: title, then the ingredient groups, then the step
/// groups numbered per group — the detail page's reading order, without any
/// of its controls.
class _Snapshot extends StatelessWidget {
  const _Snapshot({required this.recipe});

  final Recipe recipe;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final muted = textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    Widget sectionHeading(String text) => Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.sm),
      child: Semantics(
        header: true,
        child: Text(text, style: textTheme.titleMedium),
      ),
    );

    Widget groupName(String name) => Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.xs),
      child: Text(name, style: textTheme.titleSmall),
    );

    final ingredientGroups =
        recipe.ingredientGroups.where((g) => g.ingredients.isNotEmpty).toList();
    final stepGroups =
        recipe.stepGroups.where((g) => g.steps.isNotEmpty).toList();

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text(recipe.title, style: textTheme.headlineSmall),
        sectionHeading('Ingredients'),
        if (ingredientGroups.isEmpty) Text('No ingredients.', style: muted),
        for (final group in ingredientGroups) ...[
          if (group.name.trim().isNotEmpty) groupName(group.name.trim()),
          for (final ingredient in group.ingredients)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
              child: Text(ingredientOneLine(ingredient)),
            ),
        ],
        sectionHeading('Steps'),
        if (stepGroups.isEmpty) Text('No steps.', style: muted),
        for (final group in stepGroups) ...[
          if (group.name.trim().isNotEmpty) groupName(group.name.trim()),
          for (var i = 0; i < group.steps.length; i++)
            _StepLine(number: i + 1, step: group.steps[i]),
        ],
      ],
    );
  }
}

/// One numbered step, with its time and temperature under it when it has
/// them — what the step said, not a timer to start.
class _StepLine extends StatelessWidget {
  const _StepLine({required this.number, required this.step});

  final int number;
  final RecipeStep step;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final minutes = step.durationMinutes;
    final temperature = step.temperature?.trim() ?? '';
    final details = [
      if (minutes != null && minutes > 0) formatMinutes(minutes),
      if (temperature.isNotEmpty) temperature,
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$number.', style: textTheme.titleSmall?.tabular),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.text),
                if (details.isNotEmpty)
                  Text(
                    details.join(' · '),
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
