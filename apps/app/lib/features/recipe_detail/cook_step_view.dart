import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/features/recipe_detail/cook_mode_model.dart';
import 'package:app/features/recipe_detail/cook_mode_providers.dart';
import 'package:app/features/recipe_detail/detail_chips.dart';
import 'package:app/features/recipe_detail/recipe_detail_providers.dart';

/// Width below which cook mode's web layout stacks its rail under the step
/// instead of beside it.
///
/// The canvas draws a 720px step column and a 400px rail, which needs 1152px
/// plus gutters — more than the 1000px where `context.isExpanded` starts. So the
/// two-column shape has its own threshold above the breakpoint, and between 1000
/// and here the web chrome keeps its top bar but the rail drops below. Gotcha 22:
/// a fixed-width region has to be bounded against the window it is in, not
/// against the breakpoint that chose it.
const double kCookTwoColumnMin = 1180;

/// Text scale above which the web layout also stacks — at 2.0× a 400px rail
/// holding a quantity gutter and ingredient names is a column of wrapped
/// fragments, and the step text it is stealing width from is the thing the cook
/// is actually reading.
const double kCookStackScale = 1.35;

/// One step of cook mode: the step the cook is on, its timer, and what it needs.
///
/// Compact and expanded are genuinely different layouts (canvas frames C/D and
/// H) rather than one reflow, because they answer different questions. On a
/// propped phone the step is all that fits, so the ingredients are a strip of
/// chips at the bottom and the advance button is a 52px target you can hit with
/// a knuckle. On a laptop across the counter the step is 40px type and the width
/// pays for a rail holding this step's ingredients and what is coming up — the
/// two things you otherwise crane at the phone for.
class CookStepView extends ConsumerWidget {
  const CookStepView({
    super.key,
    required this.recipe,
    required this.steps,
    required this.index,
    required this.onClose,
  });

  final Recipe recipe;
  final List<CookStep> steps;
  final int index;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = steps[index];
    final showGroup = steps.any((s) => s.groupIndex != 0);
    final allIngredients =
        recipe.ingredientGroups.expand((g) => g.ingredients).toList();
    final needed = stepIngredients(current.step, allIngredients);

    // Cook mode reads the *same* servings scaler the reading page writes, so a
    // recipe scaled to 8 before you started cooking says 8 here too. Two
    // surfaces printing different quantities for one ingredient is the B066
    // class of bug, and the provider is not autoDispose precisely so the choice
    // survives the navigation.
    final servings =
        ref.watch(selectedServingsProvider(recipe.id)) ?? recipe.servings;
    final factor = recipe.servings == 0 ? 1.0 : servings / recipe.servings;

    final stacked =
        MediaQuery.sizeOf(context).width < kCookTwoColumnMin ||
        context.textScale > kCookStackScale;

    return context.isExpanded
        ? _Wide(
          recipe: recipe,
          steps: steps,
          index: index,
          current: current,
          showGroup: showGroup,
          needed: needed,
          allCount: allIngredients.length,
          servings: servings,
          factor: factor,
          stacked: stacked,
          onClose: onClose,
        )
        : _Compact(
          recipe: recipe,
          steps: steps,
          index: index,
          current: current,
          showGroup: showGroup,
          needed: needed,
          factor: factor,
          onClose: onClose,
        );
  }
}

// ---------------------------------------------------------------------------
// compact (canvas frames C and D)
// ---------------------------------------------------------------------------

class _Compact extends ConsumerWidget {
  const _Compact({
    required this.recipe,
    required this.steps,
    required this.index,
    required this.current,
    required this.showGroup,
    required this.needed,
    required this.factor,
    required this.onClose,
  });

  final Recipe recipe;
  final List<CookStep> steps;
  final int index;
  final CookStep current;
  final bool showGroup;
  final List<Ingredient> needed;
  final double factor;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final notifier = ref.read(cookSessionProvider(recipe.id).notifier);
    final isLast = index == steps.length - 1;

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.sm,
              AppSpacing.sm,
              0,
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Leave cook mode',
                  icon: const Icon(Icons.close),
                  onPressed: onClose,
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        recipe.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        current.headerLabel(showGroup: showGroup),
                        textAlign: TextAlign.center,
                        style: textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
                // Balances the close button so the title reads centred without
                // a Stack. Not an affordance — nothing to put here yet.
                const SizedBox(width: 48),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: _Progress(
              steps: steps,
              index: index,
              overallLabel: 'Step ${index + 1} of ${steps.length}',
            ),
          ),
          // The middle scrolls. At 2.0× the step text alone can be taller than a
          // phone viewport, and a fixed Column with a pinned bottom bar would
          // overflow rather than degrade (Gotcha 22).
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _RingingBanner(recipe: recipe, steps: steps),
                  Text(
                    current.step.text,
                    style: textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w500,
                      height: 1.32,
                    ),
                  ),
                  _StepChips(step: current.step),
                  _TimerPanel(recipe: recipe, step: current.step),
                  if (needed.isNotEmpty)
                    _NeededStrip(needed: needed, factor: factor),
                ],
              ),
            ),
          ),
          _BottomBar(
            recipe: recipe,
            canGoBack: index > 0,
            isLast: isLast,
            onPrevious: notifier.previous,
            onNext: () => notifier.next(steps.length),
          ),
        ],
      ),
    );
  }
}

/// The 52px advance target and its Previous twin.
///
/// `Expanded` around the advance button is load-bearing, not cosmetic: it is the
/// only thing giving that button a bounded width, and without it the label
/// "Done — next step" is laid out unbounded at 2.0× and overflows the bar
/// (Gotcha 21/B039). The label ellipsizes instead.
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.recipe,
    required this.canGoBack,
    required this.isLast,
    required this.onPrevious,
    required this.onNext,
  });

  final Recipe recipe;
  final bool canGoBack;
  final bool isLast;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        12,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            height: 52,
            child: IconButton.filledTonal(
              tooltip: 'Previous step',
              onPressed: canGoBack ? onPrevious : null,
              icon: const Icon(Icons.arrow_back),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: onNext,
                icon: Icon(isLast ? Icons.flag : Icons.check),
                label: Text(
                  isLast ? 'Finish cooking' : 'Done — next step',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The bottom strip of chips naming what this step calls for.
class _NeededStrip extends StatelessWidget {
  const _NeededStrip({required this.needed, required this.factor});

  final List<Ingredient> needed;
  final double factor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.md),
      padding: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'You’ll need',
            style: textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              for (final ing in needed)
                MetaChip(label: ingredientOneLine(ing, factor: factor)),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// expanded / web (canvas frame H)
// ---------------------------------------------------------------------------

class _Wide extends ConsumerWidget {
  const _Wide({
    required this.recipe,
    required this.steps,
    required this.index,
    required this.current,
    required this.showGroup,
    required this.needed,
    required this.allCount,
    required this.servings,
    required this.factor,
    required this.stacked,
    required this.onClose,
  });

  final Recipe recipe;
  final List<CookStep> steps;
  final int index;
  final CookStep current;
  final bool showGroup;
  final List<Ingredient> needed;
  final int allCount;
  final int servings;
  final double factor;
  final bool stacked;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final notifier = ref.read(cookSessionProvider(recipe.id).notifier);
    final isLast = index == steps.length - 1;

    final stepColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                current.headerLabel(showGroup: showGroup),
                style: textTheme.titleMedium?.copyWith(color: scheme.primary),
              ),
            ),
            Text(
              'Step ${index + 1} of ${steps.length}',
              style: textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _Progress(steps: steps, index: index, thick: true),
        const SizedBox(height: AppSpacing.lg),
        _RingingBanner(recipe: recipe, steps: steps),
        Text(
          current.step.text,
          // 40px in the canvas — readable from a metre away. Uses the theme's
          // displaySmall rather than a literal so it still scales with the
          // platform text setting.
          style: textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w500,
            height: 1.28,
          ),
        ),
        _StepChips(step: current.step),
        _TimerPanel(recipe: recipe, step: current.step, wide: !stacked),
        const SizedBox(height: AppSpacing.lg),
        _WideActions(
          canGoBack: index > 0,
          isLast: isLast,
          onPrevious: notifier.previous,
          onNext: () => notifier.next(steps.length),
        ),
      ],
    );

    final rail = _CookRail(
      steps: steps,
      index: index,
      needed: needed,
      allCount: allCount,
      servings: servings,
      factor: factor,
    );

    return Column(
      children: [
        _WideTopBar(recipe: recipe, onClose: onClose),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child:
                stacked
                    ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        stepColumn,
                        const SizedBox(height: AppSpacing.xl),
                        rail,
                      ],
                    )
                    : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 720),
                            child: stepColumn,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xl),
                        SizedBox(width: 400, child: rail),
                      ],
                    ),
          ),
        ),
      ],
    );
  }
}

class _WideTopBar extends StatelessWidget {
  const _WideTopBar({required this.recipe, required this.onClose});

  final Recipe recipe;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: 12,
      ),
      // The LayoutBuilder sits **outside** the Row on purpose. Inside it, as a
      // non-flex Row child, `constraints.maxWidth` is *infinity* — a non-flex
      // child is laid out with an unbounded main axis (Gotcha 21) — so a cap
      // computed there is `infinity / 3` and caps nothing. That is precisely the
      // overflow the envelope test found: 186px at 1000px × 2.0×, and green at
      // 1440 and at 1.0×, which is why one width or one scale proves nothing.
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Row(
            children: [
              IconButton(
                tooltip: 'Leave cook mode',
                icon: const Icon(Icons.close),
                onPressed: onClose,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cook mode',
                      style: textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      recipe.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              // The canvas puts "Screen stays awake" and "Alarms on" here.
              // Neither is true without a wakelock plugin and a notification
              // plugin, so the chips say what actually happens.
              //
              // Capped rather than flexible: `Expanded` on the title beside a
              // `Flexible` here would split the bar 50/50 whatever the content
              // says (B038). Non-flex inside a ConstrainedBox is the accepted
              // shape, and the chips wrap to a second line inside the cap.
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: constraints.maxWidth / 3),
                child: const Wrap(
                  alignment: WrapAlignment.end,
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    MetaChip(
                      icon: Icons.lightbulb_outline,
                      label: 'Keep this screen open',
                    ),
                    MetaChip(
                      icon: Icons.notifications_active_outlined,
                      label: 'Chime when a timer ends',
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Previous / advance, plus the keyboard hint the shortcuts earn.
class _WideActions extends StatelessWidget {
  const _WideActions({
    required this.canGoBack,
    required this.isLast,
    required this.onPrevious,
    required this.onNext,
  });

  final bool canGoBack;
  final bool isLast;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Wrap(
      spacing: 12,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          height: 56,
          child: FilledButton.tonalIcon(
            onPressed: canGoBack ? onPrevious : null,
            icon: const Icon(Icons.arrow_back),
            label: const Text('Previous'),
          ),
        ),
        SizedBox(
          height: 56,
          child: FilledButton.icon(
            onPressed: onNext,
            icon: Icon(isLast ? Icons.flag : Icons.check),
            label: Text(isLast ? 'Finish cooking' : 'Done — next step'),
          ),
        ),
        Text(
          'Space to advance · ← → to move · Esc to leave',
          style: textTheme.labelMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// The right rail: this step's ingredients, then what is coming up.
class _CookRail extends StatelessWidget {
  const _CookRail({
    required this.steps,
    required this.index,
    required this.needed,
    required this.allCount,
    required this.servings,
    required this.factor,
  });

  final List<CookStep> steps;
  final int index;
  final List<Ingredient> needed;
  final int allCount;
  final int servings;
  final double factor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final upcoming = steps.skip(index + 1).take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(AppRadii.card),
          ),
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('For this step', style: textTheme.titleMedium),
                  ),
                  Text(
                    needed.isEmpty
                        ? 'not named'
                        : countOf(needed.length, 'items'),
                    style: textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              if (needed.isEmpty)
                Text(
                  'This step doesn’t name an ingredient. The full list is '
                  'below.',
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                )
              else
                for (final ing in needed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 74,
                          child: Text(
                            ingredientQuantityLabel(ing, factor: factor),
                            style: textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            sentenceCase(ing.name),
                            style: textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
              const Divider(height: AppSpacing.lg),
              Text(
                'Quantities are for ${countOf(servings, 'servings')} — the '
                '${countOf(allCount, 'ingredients')} in full are on the '
                'recipe page.',
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Coming up', style: textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        if (upcoming.isEmpty)
          Text(
            'Nothing after this — the next thing is the finish screen.',
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          )
        else
          for (final s in upcoming) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${s.indexInGroup + 1}',
                    style: textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    s.step.text,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium,
                  ),
                ),
                if (s.step.durationMinutes != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '${s.step.durationMinutes} m',
                    style: textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
            const Divider(height: AppSpacing.lg),
          ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// shared pieces
// ---------------------------------------------------------------------------

/// The segmented progress bar: one bar per step group, weighted by step count.
///
/// Weighting matters — a 4-step crust and a 2-step bake are not halves of the
/// same job — and it is why this is a `Row` of `Expanded(flex: stepCount)`
/// rather than a `LinearProgressIndicator`.
class _Progress extends StatelessWidget {
  const _Progress({
    required this.steps,
    required this.index,
    this.overallLabel,
    this.thick = false,
  });

  final List<CookStep> steps;
  final int index;
  final String? overallLabel;
  final bool thick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final segments = cookSegments(steps, index);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 0; i < segments.length; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Expanded(
                flex: segments[i].stepCount,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: SizedBox(
                    height: thick ? 6 : 4,
                    child: LinearProgressIndicator(
                      value: segments[i].fill,
                      backgroundColor: scheme.surfaceContainerHighest,
                      color: scheme.primary,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        if (overallLabel != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Keep this screen open',
                  style: textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                overallLabel!,
                style: textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Temperature and tip as chips beside the step. A duration is deliberately
/// absent — it is the timer panel below, not a label.
class _StepChips extends StatelessWidget {
  const _StepChips({required this.step});

  final RecipeStep step;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasTemp = (step.temperature ?? '').isNotEmpty;
    final hasTip = (step.tip ?? '').isNotEmpty;
    if (!hasTemp && !hasTip) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasTemp)
            MetaChip(icon: Icons.thermostat, label: step.temperature!),
          // The canvas hides the tip behind a lightbulb toggle in the top bar.
          // Shown inline instead, and as a *row* rather than a chip: a tip is a
          // sentence, and a chip is a pill that cannot wrap — the one thing on a
          // step that stops you ruining it should not need a tap plus a state to
          // find, nor be truncated when found.
          if (hasTip)
            Padding(
              padding: EdgeInsets.only(top: hasTemp ? AppSpacing.sm : 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    size: 18,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      step.tip!,
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
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

/// A banner for any timer that has finished and not been acknowledged —
/// including one belonging to a step the cook has already walked past, which is
/// the whole point of letting timers outlive their step.
class _RingingBanner extends ConsumerWidget {
  const _RingingBanner({required this.recipe, required this.steps});

  final Recipe recipe;
  final List<CookStep> steps;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final session = ref.watch(cookSessionProvider(recipe.id));
    if (session.ringing.isEmpty) return const SizedBox.shrink();

    final notifier = ref.read(cookSessionProvider(recipe.id).notifier);
    return Column(
      children: [
        for (final stepId in session.ringing)
          Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.md),
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, 8, 8, 8),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(AppRadii.card),
            ),
            child: Row(
              children: [
                Icon(Icons.alarm_on, color: scheme.onPrimaryContainer),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    _label(stepId),
                    style: textTheme.bodyMedium?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => notifier.dismissAlarm(stepId),
                  child: const Text('Got it'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _label(String stepId) {
    final match = steps.where((s) => s.step.id == stepId).firstOrNull;
    if (match == null) return 'A timer finished.';
    return 'Time’s up — ${match.groupName} step ${match.indexInGroup + 1}.';
  }
}

/// The step timer: a panel with a Start button before it runs, a ring with
/// pause / +1 min / reset while it does.
///
/// A step with no `duration_minutes` gets nothing — inventing a default would
/// put a clock on "Serve with rice".
class _TimerPanel extends ConsumerWidget {
  const _TimerPanel({
    required this.recipe,
    required this.step,
    this.wide = false,
  });

  final Recipe recipe;
  final RecipeStep step;
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final minutes = step.durationMinutes ?? 0;
    if (minutes <= 0) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final session = ref.watch(cookSessionProvider(recipe.id));
    final notifier = ref.read(cookSessionProvider(recipe.id).notifier);
    final timer = session.timers[step.id];
    final total = Duration(minutes: minutes);

    final panel = Container(
      margin: const EdgeInsets.only(top: AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      padding: const EdgeInsets.all(14),
      child:
          timer == null
              ? Row(
                children: [
                  Icon(Icons.timer_outlined, size: 24, color: scheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(formatClock(total), style: textTheme.titleMedium),
                        Text(
                          'Timer for this step',
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton(
                    onPressed: () => notifier.startTimer(step.id, total),
                    child: const Text('Start'),
                  ),
                ],
              )
              : _RunningTimer(
                timer: timer,
                wide: wide,
                onPause: () => notifier.pauseTimer(step.id),
                onResume: () => notifier.startTimer(step.id, total),
                onAddMinute: () => notifier.addMinute(step.id),
                onReset: () => notifier.resetTimer(step.id),
              ),
    );
    return panel;
  }
}

class _RunningTimer extends StatelessWidget {
  const _RunningTimer({
    required this.timer,
    required this.wide,
    required this.onPause,
    required this.onResume,
    required this.onAddMinute,
    required this.onReset,
  });

  final CookTimer timer;
  final bool wide;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onAddMinute;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final ring = SizedBox(
      width: wide ? 132 : 150,
      height: wide ? 132 : 150,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CircularProgressIndicator(
              value: timer.elapsedFraction,
              strokeWidth: 12,
              backgroundColor: scheme.surfaceContainerHighest,
              color: timer.isDone ? scheme.tertiary : scheme.primary,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                formatClock(timer.remaining),
                style: (wide ? textTheme.titleLarge : textTheme.headlineSmall)
                    ?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
              Text(
                'of ${formatClock(timer.total)}',
                style: textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final controls = Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (!timer.isDone)
          FilledButton.tonalIcon(
            onPressed: timer.running ? onPause : onResume,
            icon: Icon(timer.running ? Icons.pause : Icons.play_arrow),
            label: Text(timer.running ? 'Pause' : 'Resume'),
          ),
        OutlinedButton.icon(
          onPressed: onAddMinute,
          icon: const Icon(Icons.add),
          label: const Text('1 min'),
        ),
        TextButton(onPressed: onReset, child: const Text('Reset')),
      ],
    );

    final caption = Text(
      timer.isDone
          ? 'Timer finished.'
          : timer.running
          ? 'Counting down. It keeps going if you move to the next step.'
          : 'Paused.',
      style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
    );

    // Wide puts the ring beside the controls; compact stacks, because a 150px
    // ring plus a three-button Wrap does not fit a 390px row at any text scale.
    return wide
        ? Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ring,
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Step timer', style: textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  caption,
                  const SizedBox(height: AppSpacing.sm),
                  controls,
                ],
              ),
            ),
          ],
        )
        : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: ring),
            const SizedBox(height: AppSpacing.md),
            Center(child: controls),
            const SizedBox(height: AppSpacing.sm),
            Center(child: caption),
          ],
        );
  }
}
