import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Who this chef is, at the top of `/chef/:id` (Phase 30).
///
/// Moved out of `chef_detail_sheet.dart`'s private `_Header` when the dialog was
/// replaced by the page, with one substantive change: it is driven by a
/// [Profile] plus an **optional** [ChefStanding], where the dialog's version
/// required a standing outright. That is the whole shape of the phase — the
/// board always had a standing to hand its card, and a URL has neither.
///
/// So the name, avatar and tier come from the profile (which always exists on a
/// page that rendered at all), and only the rank line depends on the standing.
class ChefIdentityHeader extends StatelessWidget {
  const ChefIdentityHeader({
    super.key,
    required this.profile,
    required this.color,
    this.standing,
  });

  final Profile profile;

  /// Null when this chef holds no leaderboard row (private-only, or no public
  /// recipe yet) — the rank line is the only thing that depends on it.
  final ChefStanding? standing;

  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final compact = context.isCompact;
    final tier = standing?.chefTier ?? profile.chefTier;

    // "Rank 4 of 172 · 14 public recipes · joined Mar 2025", minus whatever
    // does not apply. An unranked chef says so in words rather than printing a
    // rank it does not have.
    final facts = <String>[
      if (standing != null) 'Rank ${standing!.chefRank}' else 'Not ranked yet',
      // From the profile row, not the standing: it is present either way, and
      // an unranked chef still gets an honest count rather than a hard zero.
      countOf(profile.publicRecipeCount, 'public recipes'),
      if (profile.createdAt != null) 'joined ${monthYear(profile.createdAt!)}',
    ];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.lg),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withValues(alpha: 0.10), scheme.surface),
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ChefAvatar(
            name: profile.displayName,
            avatarUrl: profile.avatarUrl,
            radius: compact ? 28 : 36,
            tier: tier,
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
                  // `display_name` defaults to '' rather than null, so an
                  // unnamed profile needs a visible fallback, not a blank line.
                  profile.displayName.isEmpty ? 'Chef' : profile.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: (compact
                          ? theme.textTheme.titleLarge
                          : theme.textTheme.headlineSmall)
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: AppSpacing.xs),
                // Wrap, not Row: the chip plus a three-clause fact line cannot
                // share one line on a phone at 2.0x text scale (inherited from
                // the dialog, where it was the fix for exactly that).
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TierChip(tier: tier),
                    Text(
                      facts.join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                if (profile.bio != null && profile.bio!.trim().isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    profile.bio!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
