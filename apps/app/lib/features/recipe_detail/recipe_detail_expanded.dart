import 'package:cached_network_image/cached_network_image.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/features/recipe_detail/detail_chips.dart';
import 'package:app/features/recipe_detail/detail_layout.dart';
import 'package:app/features/recipe_detail/ingredient_rail.dart';
import 'package:app/features/recipe_detail/method_column.dart';
import 'package:app/features/recipe_detail/rating_section.dart';
import 'package:app/features/recipe_detail/recipe_detail_providers.dart';
import 'package:app/features/recipe_detail/version_history_sheet.dart';
import 'package:app/routing/app_router.dart';
import 'package:app/widgets/share_dialog.dart';

/// The v2 reading page for expanded (web/desktop) windows — the "Recipe Detail
/// v2" canvas, frame A.
///
/// Content is measured: everything sits inside a [kDetailPageWidth] column, so
/// no ingredient line ever runs the full window again. The header band carries
/// identity (title, chef, rating, cover, actions); the two columns below carry
/// the work — ingredients rail on the left in reading order, method on the
/// right. The rail is not sticky yet (a Flutter sticky sidebar needs real sliver
/// work); it scrolls with the page.
class RecipeDetailExpanded extends ConsumerWidget {
  const RecipeDetailExpanded({
    super.key,
    required this.recipe,
    required this.isOwner,
    required this.onFork,
  });

  final Recipe recipe;
  final bool isOwner;
  final VoidCallback onFork;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _HeaderBand(recipe: recipe, isOwner: isOwner, onFork: onFork),
        ),
        SliverToBoxAdapter(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: kDetailPageWidth + 2 * AppSpacing.lg,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.xxl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FactsStrip(recipe: recipe),
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          // Bounded against text scale, not fixed: the rail's
                          // quantity gutter and stepper grow with the type, and
                          // a fixed 352px column turns every ingredient name
                          // into a three-line wrap at 2.0× (Gotcha 22). Capped
                          // so the method column keeps the wide side.
                          width:
                              kDetailRailWidth *
                              context.textScale.clamp(1.0, kDetailRailMaxScale),
                          child: IngredientRail(recipe: recipe),
                        ),
                        const SizedBox(width: AppSpacing.xl),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              MethodColumn(recipe: recipe),
                              const SizedBox(height: AppSpacing.md),
                              RatingSection(recipe: recipe, isOwner: isOwner),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HeaderBand extends ConsumerWidget {
  const _HeaderBand({
    required this.recipe,
    required this.isOwner,
    required this.onFork,
  });

  final Recipe recipe;
  final bool isOwner;
  final VoidCallback onFork;

  Future<void> _showVersions(BuildContext context, WidgetRef ref) async {
    final versions = await ref.read(recipeVersionsProvider(recipe.id).future);
    if (context.mounted) {
      await VersionHistorySheet.show(context, versions);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final latest =
        ref.watch(recipeVersionsProvider(recipe.id)).valueOrNull?.firstOrNull;

    final versionLabel =
        latest == null
            ? 'Version history'
            : 'Version ${latest.versionNumber}'
                '${latest.createdAt == null ? '' : ' · updated ${isoDate(latest.createdAt!)}'}';

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: kDetailPageWidth + 2 * AppSpacing.lg,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (Navigator.of(context).canPop())
                            Padding(
                              padding: const EdgeInsets.only(
                                right: AppSpacing.sm,
                              ),
                              child: IconButton(
                                tooltip: 'Back',
                                icon: const Icon(Icons.arrow_back),
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                            ),
                          if (recipe.isFork)
                            Padding(
                              padding: const EdgeInsets.only(
                                right: AppSpacing.md,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.call_split,
                                    size: 16,
                                    color: scheme.primary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Forked recipe',
                                    style: textTheme.labelMedium?.copyWith(
                                      color: scheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          InkWell(
                            borderRadius: BorderRadius.circular(
                              AppRadii.button,
                            ),
                            onTap: () => _showVersions(context, ref),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.history,
                                    size: 16,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    versionLabel,
                                    style: textTheme.labelMedium?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(recipe.title, style: textTheme.displaySmall),
                      if (recipe.description.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.md),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 620),
                          child: Text(
                            recipe.description,
                            style: textTheme.bodyLarge,
                          ),
                        ),
                      ],
                      if (recipe.attribution != null &&
                          recipe.attribution!.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.md),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 620),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.auto_stories,
                                size: 20,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  recipe.attribution!,
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      Wrap(
                        spacing: AppSpacing.md,
                        runSpacing: AppSpacing.sm,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (recipe.owner != null)
                            ChefBadge.fromProfile(recipe.owner!),
                          StarRating(
                            rating: recipe.ratingAvg,
                            count: recipe.ratingCount,
                            size: 20,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          FilledButton.icon(
                            onPressed:
                                () =>
                                    context.push(Routes.cookRecipe(recipe.id)),
                            icon: const Icon(Icons.outdoor_grill),
                            label: const Text('Start cooking'),
                          ),
                          if (!isOwner)
                            FilledButton.tonalIcon(
                              onPressed: onFork,
                              icon: const Icon(Icons.call_split),
                              label: const Text('Fork'),
                            ),
                          LikeSaveButtons(recipe: recipe),
                          if (isOwner) ...[
                            IconButton.outlined(
                              tooltip: 'Share',
                              icon: const Icon(Icons.share),
                              onPressed:
                                  () => ShareDialog.show(context, recipe.id),
                            ),
                            IconButton.outlined(
                              tooltip: 'Edit',
                              icon: const Icon(Icons.edit),
                              onPressed:
                                  () =>
                                      context.go(Routes.editRecipe(recipe.id)),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (recipe.coverImageUrl != null) ...[
                  const SizedBox(width: AppSpacing.xl),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    child: SizedBox(
                      width: 400,
                      height: 280,
                      child: CachedNetworkImage(
                        imageUrl: recipe.coverImageUrl!,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The labelled facts strip that replaces the v1 chip row on wide windows:
/// Total · Hands on · Cook · Difficulty · Longest wait · Visibility.
///
/// "Longest wait" is the longest single step duration — the number that decides
/// whether this is cookable tonight. `IntrinsicHeight` keeps the cell hairlines
/// full-height when a label wraps at large text scales.
class FactsStrip extends StatelessWidget {
  const FactsStrip({super.key, required this.recipe});

  final Recipe recipe;

  int get _longestStepMinutes {
    var longest = 0;
    for (final group in recipe.stepGroups) {
      for (final step in group.steps) {
        final d = step.durationMinutes ?? 0;
        if (d > longest) longest = d;
      }
    }
    return longest;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final cells = <Widget>[
      _FactCell(label: 'Total', value: formatMinutes(recipe.totalMinutes)),
      _FactCell(label: 'Hands on', value: formatMinutes(recipe.prepMinutes)),
      _FactCell(label: 'Cook', value: formatMinutes(recipe.cookMinutes)),
      _FactCell(
        label: 'Difficulty',
        child: DifficultyBadge(difficulty: recipe.difficulty),
      ),
      _FactCell(
        label: 'Longest wait',
        value: formatMinutes(_longestStepMinutes),
      ),
      _FactCell(
        label: 'Visibility',
        value: recipe.visibility.isPublic ? 'Public' : 'Private',
        dim: true,
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < cells.length; i++)
              Expanded(
                child: Container(
                  decoration:
                      i == 0
                          ? null
                          : BoxDecoration(
                            border: Border(
                              left: BorderSide(color: scheme.outlineVariant),
                            ),
                          ),
                  child: cells[i],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FactCell extends StatelessWidget {
  const _FactCell({
    required this.label,
    this.value,
    this.child,
    this.dim = false,
  });

  final String label;
  final String? value;
  final Widget? child;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label.toUpperCase(),
            style: textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          child ??
              Text(
                value!,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: dim ? scheme.onSurfaceVariant : null,
                ),
              ),
        ],
      ),
    );
  }
}
