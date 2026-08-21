import 'package:cached_network_image/cached_network_image.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/features/chefs/chefs_providers.dart';

/// The expanded chef card: what the score is made of, how far the next tier is,
/// and which recipes got the chef there.
///
/// Two presentations of one body, per the design: a centred dialog capped at
/// 1152 × 720 from [Breakpoints.compact] up, and a near-full-height modal sheet
/// on a phone. Signed-out safe — every read behind it is `anon`-callable.
///
/// Deliberately **not** drawn from the mockup: the `Follow` button (there is no
/// follow model in the schema) and "View all N recipes" (there is no public
/// chef page). The top-recipe rows navigate to the recipe instead.
Future<void> showChefDetail(BuildContext context, ChefStanding standing) {
  if (context.isCompact) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      // The shell's `Scaffold` owns the bottom nav bar and the FAB, and a sheet
      // attached to the inner navigator renders *under* both — the FAB sat on
      // top of the card's content. The root navigator puts it above the chrome.
      useRootNavigator: true,
      // The design's sheet covers everything but a thin scrim strip. Without an
      // explicit constraint `showModalBottomSheet` caps itself at 9/16 of the
      // screen, which cuts the ladder off on every phone.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.94,
      ),
      builder: (_) => ChefDetailView(standing: standing),
    );
  }
  return showDialog<void>(
    context: context,
    // Same reason as the sheet: without this the scrim stops at the shell's
    // body and the top navigation bar stays undimmed above the dialog.
    useRootNavigator: true,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1152, maxHeight: 720),
        child: ChefDetailView(standing: standing),
      ),
    ),
  );
}

/// Body of the expanded chef card, hosted by either a dialog or a sheet.
class ChefDetailView extends ConsumerWidget {
  const ChefDetailView({super.key, required this.standing});

  final ChefStanding standing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final compact = context.isCompact;
    final detail = ref.watch(chefDetailProvider(standing.id));
    final total = ref.watch(chefCountProvider).valueOrNull;
    final tier = TierChip.colorFor(standing.chefTier, theme.brightness);

    final scorePanel = _ScorePanel(standing: standing, color: tier);
    final recipesPanel = _RecipesPanel(
      standing: standing,
      detail: detail,
      color: tier,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Header(
          standing: standing,
          color: tier,
          totalChefs: total,
          joined: detail.valueOrNull?.profile?.createdAt,
        ),
        Expanded(
          child: compact
              ? ListView(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  children: [
                    scorePanel,
                    const Divider(height: AppSpacing.xl),
                    recipesPanel,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border(
                            right: BorderSide(
                              color: theme.colorScheme.outlineVariant,
                            ),
                          ),
                        ),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: scorePanel,
                        ),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: recipesPanel,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.standing,
    required this.color,
    required this.totalChefs,
    required this.joined,
  });

  final ChefStanding standing;
  final Color color;
  final int? totalChefs;
  final DateTime? joined;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final compact = context.isCompact;

    // "Rank 2 of 148 · 14 public recipes · joined Mar 2025", minus whatever is
    // not known yet — the count and the profile load after the card opens.
    final facts = <String>[
      totalChefs == null
          ? 'Rank ${standing.chefRank}'
          : 'Rank ${standing.chefRank} of ${groupedCount(totalChefs!)}',
      '${groupedCount(standing.publicRecipeCount)} public '
          '${standing.publicRecipeCount == 1 ? 'recipe' : 'recipes'}',
      if (joined != null) 'joined ${monthYear(joined!)}',
    ];

    return Container(
      padding: EdgeInsets.fromLTRB(
        compact ? AppSpacing.md : AppSpacing.lg,
        compact ? AppSpacing.md : AppSpacing.lg,
        AppSpacing.sm,
        compact ? AppSpacing.md : AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withValues(alpha: 0.10), scheme.surface),
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ChefAvatar(
            name: standing.displayName,
            avatarUrl: standing.avatarUrl,
            radius: compact ? 28 : 36,
            tier: standing.chefTier,
            ringColor: color,
            surfaceColor: scheme.surface,
            backgroundColor: Color.alphaBlend(
              color.withValues(alpha: 0.16),
              scheme.surfaceContainerHigh,
            ),
            foregroundColor: color,
          ),
          SizedBox(width: compact ? AppSpacing.md : AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  standing.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: (compact
                          ? theme.textTheme.titleLarge
                          : theme.textTheme.headlineSmall)
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: AppSpacing.xs),
                // Wrap, not Row: the chip plus a three-clause fact line cannot
                // share one line on a phone at 2.0x text scale.
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TierChip(tier: standing.chefTier),
                    Text(
                      facts.join(' · '),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

/// "Why this score" + the tier ladder.
class _ScorePanel extends StatelessWidget {
  const _ScorePanel({required this.standing, required this.color});

  final ChefStanding standing;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final breakdown = ChefScoring.breakdown(
      likes: standing.totalLikes,
      saves: standing.totalSaves,
      views: standing.totalViews,
    );
    final gap = standing.pointsToNextLabel;
    final next = standing.nextTier;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Kicker(text: 'Why this score'),
        const SizedBox(height: AppSpacing.xs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                standing.scoreLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800, color: color),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'points',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        for (final row in breakdown) ...[
          ScoreContributionBar(
            contribution: row,
            total: standing.chefScore,
            color: color,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Public recipes only. Private recipes never count toward score or '
          'rank.',
          style:
              theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const Divider(height: AppSpacing.xl),
        const _Kicker(text: 'Tier ladder'),
        const SizedBox(height: AppSpacing.md),
        TierLadder(score: standing.chefScore),
        const SizedBox(height: AppSpacing.md),
        if (gap == null || next == null)
          Text(
            'Master Chef is the top tier — there is nothing above this.',
            style: theme.textTheme.bodySmall,
          )
        else
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$gap points to ${next.label}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: ' — about ${_closingLine(standing)}.'),
              ],
            ),
            style: theme.textTheme.bodySmall,
          ),
      ],
    );
  }

  /// "1,962 more saves, or 3,270 more likes" — the gap expressed in the two
  /// inputs a chef can actually influence. Views are left out: they are not
  /// something a chef adds on purpose.
  static String _closingLine(ChefStanding standing) {
    final saves = ChefScoring.unitsToNext(standing.chefScore, ChefScoring.saveWeight);
    final likes = ChefScoring.unitsToNext(standing.chefScore, ChefScoring.likeWeight);
    return '${groupedCount(saves ?? 0)} more saves, '
        'or ${groupedCount(likes ?? 0)} more likes';
  }
}

/// "Top recipes" plus the totals grid.
class _RecipesPanel extends StatelessWidget {
  const _RecipesPanel({
    required this.standing,
    required this.detail,
    required this.color,
  });

  final ChefStanding standing;
  final AsyncValue<ChefDetail> detail;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Kicker(text: 'Top recipes'),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Ranked by points contributed, not by rating.',
          style:
              theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.md),
        detail.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => _Note(text: friendlyError(e)),
          data: (data) {
            if (data.topRecipesFailed) {
              return const _Note(
                text: 'Top recipes are unavailable right now.',
              );
            }
            if (data.topRecipes.isEmpty) {
              return const _Note(text: 'No public recipes yet.');
            }
            return Column(
              children: [
                for (final recipe in data.topRecipes) ...[
                  _TopRecipeRow(recipe: recipe),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ],
            );
          },
        ),
        const Divider(height: AppSpacing.xl),
        _Totals(standing: standing),
        const SizedBox(height: AppSpacing.md),
        Text(
          // The mockup said "recomputes nightly"; the build recomputes on every
          // like, save, view and visibility change, so the copy says that.
          'Score and rank update the moment a recipe gains a like, save, or '
          'view — there is no nightly job.',
          style:
              theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// One "Top recipes" row: thumbnail, title, rating, and what it contributed.
class _TopRecipeRow extends StatelessWidget {
  const _TopRecipeRow({required this.recipe});

  final Recipe recipe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final points = ChefScoring.score(
      likes: recipe.likeCount,
      saves: recipe.saveCount,
      views: recipe.viewCount,
    );

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          // Close the card first: the dialog would otherwise sit over the
          // recipe it just navigated to.
          Navigator.of(context).pop();
          context.push('/recipe/${recipe.id}');
        },
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            children: [
              _Thumb(url: recipe.coverImageUrl),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      recipe.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (recipe.hasRatings)
                          RatingPill(
                            rating: recipe.ratingAvg,
                            count: recipe.ratingCount,
                          ),
                        Text(
                          '${groupedCount(recipe.likeCount)} likes · '
                          '${groupedCount(recipe.saveCount)} saves',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                groupedScore(points),
                maxLines: 1,
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(Icons.restaurant_menu, size: 20, color: scheme.onSurfaceVariant),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.sm),
      child: SizedBox(
        width: 56,
        height: 44,
        child: url == null || url!.isEmpty
            ? placeholder
            : CachedNetworkImage(
                imageUrl: url!,
                fit: BoxFit.cover,
                placeholder: (_, __) =>
                    Container(color: scheme.surfaceContainerHighest),
                errorWidget: (_, __, ___) => placeholder,
              ),
      ),
    );
  }
}

/// Recipes / likes / saves / views, the same four numbers the collapsed card
/// shows as chips — repeated here as the totals the breakdown above adds up to.
class _Totals extends StatelessWidget {
  const _Totals({required this.standing});

  final ChefStanding standing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget cell(int value, String label) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                groupedCount(value),
                maxLines: 1,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: cell(standing.publicRecipeCount, 'recipes')),
        Expanded(child: cell(standing.totalLikes, 'likes')),
        Expanded(child: cell(standing.totalSaves, 'saves')),
        Expanded(child: cell(standing.totalViews, 'views')),
      ],
    );
  }
}

class _Kicker extends StatelessWidget {
  const _Kicker({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Text(
        text,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}
