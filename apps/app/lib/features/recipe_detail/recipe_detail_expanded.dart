import 'package:cached_network_image/cached_network_image.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/features/recipe_detail/delete_action.dart';
import 'package:app/features/recipe_detail/detail_chips.dart';
import 'package:app/features/recipe_detail/detail_layout.dart';
import 'package:app/features/recipe_detail/detail_provenance.dart';
import 'package:app/features/recipe_detail/rail_panel.dart';
import 'package:app/features/recipe_detail/method_column.dart';
import 'package:app/features/recipe_detail/rating_section.dart';
import 'package:app/features/recipe_detail/recipe_detail_providers.dart';
import 'package:app/features/recipe_detail/version_history_sheet.dart';
import 'package:app/routing/app_router.dart';
import 'package:app/routing/pop_or_go.dart';
import 'package:app/widgets/share_dialog.dart';

/// The v2 reading page for expanded (web/desktop) windows — the "Recipe Detail
/// v2" canvas, frame A.
///
/// Content is measured: everything sits inside a [kDetailPageWidth] column, so
/// no ingredient line ever runs the full window again. The header band carries
/// identity (kicker, title, chef, rating, tags, facts, nutrition summary,
/// cover, actions); the two panels below carry the work — ingredients rail on
/// the left in reading order, method on the right. The rail is not sticky yet (a Flutter sticky sidebar needs real sliver
/// work); it scrolls with the page.
class RecipeDetailExpanded extends ConsumerWidget {
  const RecipeDetailExpanded({
    super.key,
    required this.recipe,
    required this.isOwner,
    required this.onFork,
    this.forking = false,
  });

  final Recipe recipe;
  final bool isOwner;
  final VoidCallback onFork;

  /// A fork is in flight: the Fork button renders disabled (B129).
  final bool forking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _HeaderBand(
            recipe: recipe,
            isOwner: isOwner,
            onFork: forking ? null : onFork,
          ),
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
                // Two open panels side by side — the same rail and method
                // column the compact page stacks (the owner's Q4).
                child: Row(
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
                      child: RailPanel(recipe: recipe),
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
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Identity, facts and actions on the left; the cover on the right.
///
/// Phase 36c carries reference 5's sheet language to the measured page: the
/// accent kicker over a bold title, tag pills, label-over-value facts and the
/// nutrition summary all live here now, so the band answers "what is this and
/// what will it take" before the two panels below say how.
class _HeaderBand extends ConsumerWidget {
  const _HeaderBand({
    required this.recipe,
    required this.isOwner,
    required this.onFork,
  });

  final Recipe recipe;
  final bool isOwner;

  /// Null while a fork is in flight, which disables the button (B129).
  final VoidCallback? onFork;

  /// The reading measure for the description and the credit blocks under it.
  static const double _kProseMeasure = 620;

  /// The header band's cover (canvas frame A): a photo, or the category's
  /// colour block when there is none (the owner's Q1).
  static const double _kCoverWidth = 400;
  static const double _kCoverHeight = 280;

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
    final nutrition = recipe.nutrition;
    // See `Recipe.displayCoverImageUrl` — Phase 35c's image policy, applied
    // once in the model rather than here.
    final coverUrl = recipe.displayCoverImageUrl;

    final versionLabel =
        latest == null
            ? 'Version history'
            : 'Version ${latest.versionNumber}'
                '${latest.createdAt == null ? '' : ' · updated ${isoDate(latest.createdAt!)}'}';

    return Padding(
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
                      // A Wrap: with the cover always present the column is
                      // 520px at a 1000px window, and the version line is a
                      // non-flex run of text beside two more (Gotcha 21).
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          // Always drawn (B132 / UX-005). It used to exist
                          // only `if (canPop())`, so a shared link — a root
                          // route with no top bar — had no exit but the
                          // browser. `popOrGo` is the compact page's rule.
                          IconButton(
                            tooltip: 'Back',
                            icon: const Icon(Icons.arrow_back),
                            onPressed: () => popOrGo(context, Routes.discover),
                          ),
                          if (recipe.isFork)
                            const Padding(
                              padding: EdgeInsets.only(right: AppSpacing.sm),
                              child: ForkedLabel(),
                            ),
                          InkWell(
                            borderRadius: BorderRadius.circular(AppRadii.md),
                            onTap: () => _showVersions(context, ref),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.xs,
                                vertical: AppSpacing.xxs,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.history,
                                    size: AppIconSize.sm,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: AppSpacing.xs),
                                  Flexible(
                                    child: Text(
                                      versionLabel,
                                      style: textTheme.labelMedium?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      DetailKicker(recipe: recipe),
                      const SizedBox(height: AppSpacing.xs),
                      Text(recipe.title, style: textTheme.displaySmall),
                      if (recipe.description.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.md),
                        ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: _kProseMeasure,
                          ),
                          child: Text(
                            recipe.description,
                            style: textTheme.bodyLarge?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                      // Same measure as the description above it: the credit
                      // is prose about the recipe, not a band across the page.
                      if (recipe.isImported) ...[
                        const SizedBox(height: AppSpacing.md),
                        ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: _kProseMeasure,
                          ),
                          child: SourceCredit(recipe: recipe),
                        ),
                      ],
                      if (recipe.attribution != null &&
                          recipe.attribution!.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.md),
                        ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: _kProseMeasure,
                          ),
                          child: AttributionBlock(text: recipe.attribution!),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      Wrap(
                        spacing: AppSpacing.md,
                        runSpacing: AppSpacing.sm,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (recipe.owner != null)
                            ChefBadge.fromProfile(
                              recipe.owner!,
                              onTap:
                                  () => context.push(
                                    Routes.chef(recipe.owner!.id),
                                  ),
                            ),
                          StarRating(
                            rating: recipe.ratingAvg,
                            count: recipe.ratingCount,
                            size: AppIconSize.md,
                          ),
                        ],
                      ),
                      if (DetailTags.hasAny(recipe)) ...[
                        const SizedBox(height: AppSpacing.md),
                        DetailTags(recipe: recipe),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      FactsStrip(recipe: recipe),
                      // Additive to the FDA label in the rail's Nutrition
                      // tab, which stays the authoritative panel (Preserve).
                      if (NutritionSummary.hasAny(nutrition)) ...[
                        const SizedBox(height: AppSpacing.lg),
                        NutritionSummary(nutrition: nutrition!),
                      ],
                      const SizedBox(height: AppSpacing.lg),
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
                            // UX-037: Delete, one step behind an overflow.
                            // Outlined like its two neighbours: the standard
                            // IconButton under a PopupMenuButton takes the
                            // outline from `side` and the icon colour from
                            // `foregroundColor` — the two things
                            // `IconButton.outlined` sets that the plain
                            // variant does not (PopupMenuButton would
                            // otherwise paint the ambient IconTheme colour).
                            RecipeOwnerMenu(
                              recipe: recipe,
                              style: IconButton.styleFrom(
                                foregroundColor: scheme.onSurfaceVariant,
                                side: BorderSide(color: scheme.outline),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xl),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.card),
                  child: SizedBox(
                    width: _kCoverWidth,
                    height: _kCoverHeight,
                    child:
                        coverUrl != null
                            ? CachedNetworkImage(
                              imageUrl: coverUrl,
                              fit: BoxFit.cover,
                            )
                            : CategoryCover(
                              category: recipe.category,
                              large: true,
                            ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The labelled facts: Total · Hands on · Cook · Difficulty · Longest wait ·
/// Visibility on a wide window, and a 2×2 quad of the four that matter on a
/// phone.
///
/// Label over value with no box and no hairlines — reference 5's `COOKS IN /
/// 30 min` columns (Phase 36c). "Longest wait" is the longest single step
/// duration — the number that decides whether this is cookable tonight.
class FactsStrip extends StatelessWidget {
  const FactsStrip({super.key, required this.recipe, this.quad = false});

  final Recipe recipe;

  /// Lay the cells out as a 2×2 grid instead of a single run (canvas frame B).
  ///
  /// Six cells across a 390px phone is 65px each — narrower than the word
  /// "Difficulty" — so compact keeps four and stacks them. Cook is dropped
  /// because Total and Hands on bound it, and Visibility because the tag row
  /// already carries a `Private` pill when a recipe is private.
  final bool quad;

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
    final total = _FactCell(
      label: 'Total',
      value: formatMinutes(recipe.totalMinutes),
    );
    final handsOn = _FactCell(
      label: 'Hands on',
      value: formatMinutes(recipe.prepMinutes),
    );
    // An imported recipe's difficulty is the importer's column default, not
    // the publisher's word (B134 / UX-028): it reads as unknown, not Medium.
    final difficulty =
        recipe.isImported
            ? const _FactCell(label: 'Difficulty', value: '—')
            : _FactCell(
              label: 'Difficulty',
              child: DifficultyBadge(difficulty: recipe.difficulty),
            );
    final longestWait = _FactCell(
      label: 'Longest wait',
      value: formatMinutes(_longestStepMinutes),
    );

    if (quad) {
      // Two equal columns, each cell free to wrap its label at 2.0× — the
      // cells are Expanded, so nothing here is laid out unbounded.
      Widget row(Widget left, Widget right) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Expanded(child: left), Expanded(child: right)],
      );
      return Column(
        children: [
          row(total, handsOn),
          const SizedBox(height: AppSpacing.md),
          row(difficulty, longestWait),
        ],
      );
    }

    // A Wrap rather than six Expanded cells: the band's left column is 520px
    // beside the cover at a 1000px window, and an equal sixth of that is
    // narrower than `LONGEST WAIT` at 2.0×. Each fact takes its own width and
    // the run breaks where it must.
    return Wrap(
      spacing: AppSpacing.xl,
      runSpacing: AppSpacing.md,
      children: [
        total,
        handsOn,
        _FactCell(label: 'Cook', value: formatMinutes(recipe.cookMinutes)),
        difficulty,
        longestWait,
        _FactCell(
          label: 'Visibility',
          value: recipe.visibility.isPublic ? 'Public' : 'Private',
          dim: true,
        ),
      ],
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
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: context.appText.overline.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          child ??
              Text(
                value!,
                // Tabular: times line up across the cells (UX-049).
                style: textTheme.titleMedium?.tabular.copyWith(
                  color: dim ? scheme.onSurfaceVariant : null,
                ),
              ),
        ],
      ),
    );
  }
}
