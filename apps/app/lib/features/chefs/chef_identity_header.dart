import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import 'package:app/widgets/route_title.dart';

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

  /// Avatar radius on a phone and from compact up.
  static const double _avatarRadiusCompact = 28;
  static const double _avatarRadius = 36;

  /// The name this page is titled with — the header's heading, the app bar
  /// and the browser tab all read it (UX-042). `display_name` defaults to ''
  /// rather than null, so an unnamed profile needs a visible fallback, not a
  /// blank line.
  static String nameOf(Profile profile) =>
      profile.displayName.isEmpty ? 'Chef' : profile.displayName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final compact = context.isCompact;
    // An imported chef is browsable, never ranked (Phase 35b), so it has no
    // tier to show — the column's `home_cook` default would read as a standing
    // the leaderboard deliberately never gave it (B118).
    final imported = profile.kind.isImported;
    final ChefTier? tier =
        imported ? null : standing?.chefTier ?? profile.chefTier;

    // "Rank 4 of 172 · 14 public recipes · joined Mar 2025", minus whatever
    // does not apply. An unranked chef says so in words rather than printing a
    // rank it does not have.
    final facts = <String>[
      if (standing != null)
        'Rank ${standing!.chefRank}'
      else if (imported)
        'Not ranked'
      else
        'Not ranked yet',
      // From the profile row, not the standing: it is present either way, and
      // an unranked chef still gets an honest count rather than a hard zero.
      countOf(profile.publicRecipeCount, 'public recipes'),
      // Members only (UX-042). An imported profile's `created_at` is when the
      // importer ran, not when a person joined anything — they never did, so
      // "joined Sep 2026" on a credit page is a claim about nobody.
      if (!imported && profile.createdAt != null)
        'joined ${monthYear(profile.createdAt!)}',
    ];

    final name = nameOf(profile);

    // The chef's name titles the browser tab (UX-051) — this header is the
    // one place on the page that always has the profile in hand.
    return RouteTitle(
      page: name,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.lg),
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            color.withValues(alpha: AppAlpha.wash),
            scheme.surface,
          ),
          border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ChefAvatar(
              name: profile.displayName,
              avatarUrl: profile.avatarUrl,
              radius: compact ? _avatarRadiusCompact : _avatarRadius,
              tier: tier,
              ringColor: color,
              surfaceColor: scheme.surface,
              backgroundColor: Color.alphaBlend(
                color.withValues(alpha: AppAlpha.tintStrong),
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
                  // The page's top heading (UX-014).
                  Semantics(
                    container: true,
                    header: true,
                    child: Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          compact
                              ? theme.textTheme.titleLarge
                              : theme.textTheme.headlineSmall,
                    ),
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
                      if (tier != null) TierChip(tier: tier),
                      Text(
                        facts.join(' · '),
                        // Rank and recipe count: tabular (UX-049).
                        style: theme.textTheme.bodySmall?.tabular.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  if (profile.bio != null &&
                      profile.bio!.trim().isNotEmpty) ...[
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
      ),
    );
  }
}
