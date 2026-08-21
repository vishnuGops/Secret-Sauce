import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/features/chefs/chef_recipes_panel.dart';
import 'package:app/features/chefs/chef_score_panel.dart';
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
    builder:
        (_) => Dialog(
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

    final scorePanel = ChefScorePanel(standing: standing, color: tier);
    final recipesPanel = ChefRecipesPanel(
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
          child:
              compact
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
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
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
