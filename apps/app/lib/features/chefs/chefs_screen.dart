import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/features/chefs/chefs_providers.dart';

/// Chefs leaderboard — ranked by chef score over each chef's public recipes.
///
/// Signed-out safe, like Discover: the RPC is granted to `anon`, so this route
/// is deliberately absent from the router's `needsAuth` list.
class ChefsScreen extends ConsumerWidget {
  const ChefsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(chefsLeaderboardProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Chefs')),
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: e.toString(),
          onRetry: () => ref.invalidate(chefsLeaderboardProvider),
        ),
        data: (chefs) => chefs.isEmpty
            ? const EmptyView(
                title: 'No chefs yet',
                message: 'Publish a recipe and you will show up here.',
                icon: Icons.emoji_events_outlined,
              )
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(chefsLeaderboardProvider),
                child: _Board(chefs: chefs),
              ),
      ),
    );
  }
}

class _Board extends StatelessWidget {
  const _Board({required this.chefs});

  final List<ChefStanding> chefs;

  @override
  Widget build(BuildContext context) {
    // Cap the reading width on desktop the way a single-column list should,
    // rather than stretching rows across a 1600px window.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.md),
          itemCount: chefs.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (context, i) => _ChefRow(standing: chefs[i]),
        ),
      ),
    );
  }
}

class _ChefRow extends StatelessWidget {
  const _ChefRow({required this.standing});

  final ChefStanding standing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final compact = context.isCompact;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            _Rank(rank: standing.chefRank, tier: standing.chefTier),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ChefBadge(
                    name: standing.displayName,
                    tier: standing.chefTier,
                    avatarUrl: standing.avatarUrl,
                    compact: compact,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _Stats(standing: standing, compact: compact),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            // Bounded on purpose. An unconstrained Column takes its intrinsic
            // width, and at 2.0x text scale on a 320px phone that starved the
            // chef badge beside it until the badge's own row overflowed.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 96),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    standing.scoreLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    'score',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rank medallion. Ties share a rank (`dense_rank`), so two rows can both
/// read "4" — that is correct, not a rendering bug.
class _Rank extends StatelessWidget {
  const _Rank({required this.rank, required this.tier});

  final int rank;
  final ChefTier tier;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = TierChip.colorFor(tier, theme.brightness);
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      child: Text(
        '$rank',
        style: theme.textTheme.titleMedium
            ?.copyWith(color: color, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.standing, required this.compact});

  final ChefStanding standing;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // The label must be Flexible: a Wrap constrains each child to the Wrap's
    // width, and an intrinsically-sized Text in a Row has no way to degrade —
    // the same shape as B016. Large counts at 2.0x scale hit this immediately.
    Widget stat(IconData icon, int value, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: scheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                compact ? '$value' : '$value $label',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        );

    // Wrap, not Row: at 2.0x text scale on a narrow phone these four stats
    // cannot fit on one line, and a Row would overflow.
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      children: [
        stat(Icons.menu_book_outlined, standing.publicRecipeCount, 'recipes'),
        stat(Icons.favorite_outline, standing.totalLikes, 'likes'),
        stat(Icons.bookmark_outline, standing.totalSaves, 'saves'),
        stat(Icons.visibility_outlined, standing.totalViews, 'views'),
      ],
    );
  }
}
