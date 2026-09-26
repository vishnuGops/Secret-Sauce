import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/features/recipe_detail/cook_mode_model.dart';
import 'package:app/features/recipe_detail/cook_mode_providers.dart';
import 'package:app/features/recipe_detail/detail_chips.dart';
import 'package:app/features/recipe_detail/detail_layout.dart';
import 'package:app/features/recipe_detail/method_column.dart';
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

/// The canvas's step column (frame H) — the measure of 40px step text.
const double _kStepColumnMaxWidth = 720;

/// The canvas's rail beside it.
const double _kRailWidth = 400;

/// The compact advance target — big enough to hit with a knuckle.
const double _kAdvanceTarget = 52;

/// The wide layout's Previous / advance height.
const double _kWideActionHeight = 56;

/// The numbered disc in front of an upcoming step.
const double _kStepNumberDiameter = 30;

/// The progress bar's segments: thin on compact, thick on the web frame.
const double _kProgressThin = 4;
const double _kProgressThick = 6;
const double _kProgressRadius = 2;

/// The running timer's ring — smaller where it sits beside the controls.
const double _kRingSize = 150;
const double _kRingSizeWide = 132;
const double _kRingStroke = 12;

/// A step photo's height cap, as a fraction of the window's height (B125).
///
/// 4:3 at full column width is 268px on a 390px phone, which fits under the
/// step text, but 609px on an 844px-wide landscape phone and 540px in the web
/// frame's 720px column — either one pushes the timer and the advance buttons
/// below the fold. Capped, the width stays full and `BoxFit.cover` crops.
const double _kPhotoMaxViewportFraction = 0.4;

/// The current step's photo, or nothing — shared by both layouts so the rights
/// rule and the cap cannot differ between them.
Widget _currentStepPhoto(
  BuildContext context,
  Recipe recipe,
  CookStep current,
) {
  final url = displayStepImageUrl(recipe, current.step);
  if (url == null) return const SizedBox.shrink();
  return StepPhoto(
    url: url,
    stepNumber: current.indexInGroup + 1,
    radius: AppRadii.card,
    maxHeight: MediaQuery.sizeOf(context).height * _kPhotoMaxViewportFraction,
  );
}

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
                const SizedBox(width: kMinInteractiveDimension),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            // The overall count only where it says something the title does
            // not: with one unnamed group the title already reads `Step 1 of
            // 6`, and printing it twice was UX-044.
            child: _Progress(
              steps: steps,
              index: index,
              showHint: true,
              overallLabel:
                  showGroup ? 'Step ${index + 1} of ${steps.length}' : null,
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
                    // Sans, not the serif headline: a step is something the
                    // cook acts on. The 1.32 leading is this frame's own.
                    style: context.appText.step.copyWith(height: 1.32),
                  ),
                  // After the text and inside the scroll, so the step itself is
                  // always the first thing on screen and a tall photo scrolls
                  // rather than overflowing the pinned bottom bar (B125).
                  _currentStepPhoto(context, recipe, current),
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
        AppSpacing.smPlus,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          SizedBox(
            width: _kAdvanceTarget,
            height: _kAdvanceTarget,
            child: IconButton.filledTonal(
              tooltip: 'Previous step',
              onPressed: canGoBack ? onPrevious : null,
              icon: const Icon(Icons.arrow_back),
            ),
          ),
          const SizedBox(width: AppSpacing.smPlus),
          Expanded(
            child: SizedBox(
              height: _kAdvanceTarget,
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
      padding: const EdgeInsets.only(top: AppSpacing.smPlus),
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
            // Same rule as compact (UX-044): only when the header names a
            // group, so the two counts differ.
            if (showGroup)
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
          // 40px in the canvas — readable from a metre away. Uses the stepLarge
          // role rather than a literal so it still scales with the platform
          // text setting; sans, like the compact step. 1.28 is this frame's
          // own leading.
          style: context.appText.stepLarge.copyWith(height: 1.28),
        ),
        _currentStepPhoto(context, recipe, current),
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
                            constraints: const BoxConstraints(
                              maxWidth: _kStepColumnMaxWidth,
                            ),
                            child: stepColumn,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xl),
                        SizedBox(width: _kRailWidth, child: rail),
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
        vertical: AppSpacing.smPlus,
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
      spacing: AppSpacing.smPlus,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          height: _kWideActionHeight,
          child: FilledButton.tonalIcon(
            onPressed: canGoBack ? onPrevious : null,
            icon: const Icon(Icons.arrow_back),
            label: const Text('Previous'),
          ),
        ),
        SizedBox(
          height: _kWideActionHeight,
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
                          // The reading rail's gutter, on the reading rail's
                          // terms (32c5): a bare 74 does not grow with the type,
                          // so `1 1⁄3 cup` at 2.0× wrapped onto three lines here
                          // while the same string sat on one line on the recipe
                          // page. One constant, one clamp, two surfaces.
                          width:
                              kIngredientQuantityGutter *
                              context.textScale.clamp(1.0, kDetailRailMaxScale),
                          child: Text(
                            ingredientQuantityLabel(ing, factor: factor),
                            style: context.appText.quantity,
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
                  width: _kStepNumberDiameter,
                  height: _kStepNumberDiameter,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${s.indexInGroup + 1}',
                    style: textTheme.titleSmall?.tabular,
                  ),
                ),
                const SizedBox(width: AppSpacing.smPlus),
                Expanded(
                  child: Text(
                    s.step.text,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium,
                  ),
                ),
                // The one duration format (UX-043); zero is no duration.
                if ((s.step.durationMinutes ?? 0) > 0) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    formatMinutes(s.step.durationMinutes!),
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
    this.showHint = false,
    this.thick = false,
  });

  final List<CookStep> steps;
  final int index;

  /// `Step 5 of 9` across every group, or null when the title already says it.
  final String? overallLabel;

  /// The `Keep this screen open` line under the bar (compact only — the web
  /// frame says it in the top bar).
  final bool showHint;
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
              if (i > 0) const SizedBox(width: AppSpacing.xs),
              Expanded(
                flex: segments[i].stepCount,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(_kProgressRadius),
                  child: SizedBox(
                    height: thick ? _kProgressThick : _kProgressThin,
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
        if (showHint || overallLabel != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child:
                    showHint
                        ? Text(
                          'Keep this screen open',
                          style: textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        )
                        : const SizedBox.shrink(),
              ),
              if (overallLabel != null)
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
///
/// The temperature is the [MetaChip.large] variant (UX-024): an oven setting
/// at the reading page's 11px beside 24–36px step text is unreadable from
/// arm's length, which is the one distance cook mode is for.
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
            MetaChip(
              icon: Icons.thermostat,
              label: step.temperature!,
              large: true,
            ),
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
                    size: AppIconSize.button,
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
          // A live region (UX-047): the banner appears while the cook is
          // looking at something else, and a screen reader announces it
          // instead of waiting for focus to wander onto it. The chime is the
          // audible half of the same alarm; this is the spoken half.
          Semantics(
            container: true,
            liveRegion: true,
            child: Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.sm,
              ),
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
                      style: textTheme.titleSmall?.copyWith(
                        color: scheme.onPrimaryContainer,
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
      padding: AppInsets.callout,
      child:
          timer == null
              ? Row(
                children: [
                  Icon(
                    Icons.timer_outlined,
                    size: AppIconSize.lg,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.smPlus),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          formatClock(total),
                          style: textTheme.titleMedium?.tabular,
                        ),
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
      width: wide ? _kRingSizeWide : _kRingSize,
      height: wide ? _kRingSizeWide : _kRingSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CircularProgressIndicator(
              value: timer.elapsedFraction,
              strokeWidth: _kRingStroke,
              backgroundColor: scheme.surfaceContainerHighest,
              color: timer.isDone ? scheme.tertiary : scheme.primary,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                formatClock(timer.remaining),
                style:
                    wide ? context.appText.clockSmall : context.appText.clock,
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
