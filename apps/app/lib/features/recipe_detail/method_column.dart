import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
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
                    photoUrl: displayStepImageUrl(recipe, group.steps[i]),
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
    required this.photoUrl,
    required this.onTap,
  });

  final RecipeStep step;
  final int number;
  final bool done;

  /// Already filtered through [displayStepImageUrl]; null means no photo.
  final String? photoUrl;
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
                    // Under the text, full width of its column (DESIGN §2.2).
                    // Only on a step still to do: a done step is one dim line,
                    // and a photo would undo the collapse that makes the next
                    // step the first full-size row on screen.
                    if (photoUrl != null)
                      StepPhoto(
                        url: photoUrl!,
                        stepNumber: number,
                        radius: AppRadii.md,
                      ),
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

/// The photo a step may show, or null (B125/UX-001).
///
/// The cover's rights rule applies to a step's photo too: an imported recipe
/// whose publisher asked for no images keeps the URLs the crawl captured and
/// must not render them (Phase 35c, `Recipe.displayCoverImageUrl`). Nothing
/// validates the scheme — the cover does not either, and `CachedNetworkImage`
/// failing on a bad URL is the same collapse as a 404. Blank counts as absent.
String? displayStepImageUrl(Recipe recipe, RecipeStep step) {
  final url = step.imageUrl?.trim();
  if (url == null || url.isEmpty || !recipe.imageMode.showsImage) return null;
  return url;
}

/// A step's photo: 4:3 at the full width of the step's text column, cropped to
/// cover, rounded, with the neutral inset hairline every photo gets (DESIGN
/// §2.2). Used by the reading page's [MethodColumn] and by cook mode.
///
/// The editor has uploaded `steps.image_url` since Phase 33 and nothing drew it
/// until B125. Two states only: a photo, or nothing at all — the placeholder
/// holds the space while it loads, and a failed load collapses the whole
/// widget, top gap included, rather than leaving an empty framed box or a
/// broken-image glyph where the cook expects a picture.
///
/// Labelled rather than excluded from semantics: the photo shows what the step
/// text cannot (the colour of a caramel, the texture of a dough), so a
/// screen-reader user is told a visual reference exists for this step.
class StepPhoto extends StatelessWidget {
  const StepPhoto({
    super.key,
    required this.url,
    required this.stepNumber,
    required this.radius,
    this.maxHeight = double.infinity,
  });

  final String url;

  /// The number the step is shown with — per group, as the list numbers it.
  final int stepNumber;

  /// `AppRadii.md` in the method list, `AppRadii.card` in cook mode.
  final double radius;

  /// Cook mode caps the height against the viewport so a landscape phone's
  /// 4:3 photo cannot be taller than the screen; the width stays full and
  /// `BoxFit.cover` crops.
  final double maxHeight;

  /// Width over height — DESIGN §2.2's step-photo ratio.
  static const double kAspectRatio = 4 / 3;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final outline = context.palette.imageOutline;
    final shape = BorderRadius.circular(radius);

    // The LayoutBuilder sits outside the image, not inside the frame: every
    // caller places this in a Column whose width is bounded, and measuring here
    // keeps the size independent of whatever `CachedNetworkImage` wraps its
    // builders in (Gotcha 25).
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = math.min(width / kAspectRatio, maxHeight);

        Widget frame(Widget child) => Padding(
          padding: const EdgeInsets.only(top: AppSpacing.smPlus),
          child: Semantics(
            image: true,
            label: 'Photo for step $stepNumber',
            child: Container(
              width: width,
              height: height,
              // Drawn over the photo, inside its edge: a pale plate on a pale
              // surface still has an edge.
              foregroundDecoration: BoxDecoration(
                borderRadius: shape,
                border: Border.all(color: outline),
              ),
              child: ClipRRect(borderRadius: shape, child: child),
            ),
          ),
        );

        return CachedNetworkImage(
          imageUrl: url,
          imageBuilder:
              (context, provider) => frame(
                Image(
                  image: provider,
                  fit: BoxFit.cover,
                  excludeFromSemantics: true,
                ),
              ),
          placeholder:
              (context, _) =>
                  frame(ColoredBox(color: scheme.surfaceContainerHigh)),
          errorWidget: (_, __, ___) => const SizedBox.shrink(),
        );
      },
    );
  }
}
