import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'package:design_system/src/theme/app_theme.dart';
import 'package:design_system/src/widgets/chef_avatar.dart';
import 'package:design_system/src/widgets/tier_chip.dart';

/// Avatar + chef name with the [TierChip] **under** the name.
///
/// [compact] shrinks the avatar and drops the chip's icon, for dense surfaces
/// (a card cover overlay). Both variants keep the name on one line with an
/// ellipsis — the badge is used inside fixed-aspect tiles that cannot grow
/// (B001/B002/B016).
///
/// **Give this a bounded width.** The name column is `Flexible` so it can
/// ellipsize, which means an unbounded horizontal context (a bare child of a
/// horizontally-scrolling `SingleChildScrollView`, say) throws
/// `RenderFlex children have non-zero flex but incoming width constraints are
/// unbounded`. `Positioned(left:, right:)`, `Expanded`, and any `Column` are
/// all fine.
class ChefBadge extends StatelessWidget {
  const ChefBadge({
    super.key,
    required this.name,
    this.tier,
    this.avatarUrl,
    this.compact = false,
    this.onSurfaceImage = false,
    this.onTap,
  });

  /// Convenience: build from an embedded recipe owner.
  factory ChefBadge.fromProfile(
    Profile profile, {
    Key? key,
    bool compact = false,
    bool onSurfaceImage = false,
    VoidCallback? onTap,
  }) => ChefBadge(
    key: key,
    name: profile.displayName,
    // An imported chef is browsable, never ranked (Phase 35b), so it carries
    // no tier to print — `Home Cook` on a captured byline reads as a ranking
    // the leaderboard deliberately never gave it (B118).
    tier: profile.kind.isImported ? null : profile.chefTier,
    avatarUrl: profile.avatarUrl,
    compact: compact,
    onSurfaceImage: onSurfaceImage,
    onTap: onTap,
  );

  final String name;

  /// Null hides the chip: an imported chef has no standing (B118).
  final ChefTier? tier;
  final String? avatarUrl;
  final bool compact;

  /// Set when the badge sits on a cover photo rather than a theme surface, so
  /// the name is drawn in the scrim's foreground color instead of `onSurface`.
  final bool onSurfaceImage;

  final VoidCallback? onTap;

  /// Avatar radius, full and [compact].
  static const double _avatarRadius = 20;
  static const double _avatarRadiusCompact = 12;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = compact ? _avatarRadiusCompact : _avatarRadius;
    final nameColor =
        onSurfaceImage ? context.palette.onImage : scheme.onSurface;

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ChefAvatar(name: name, avatarUrl: avatarUrl, radius: radius),
        SizedBox(width: compact ? AppSpacing.sm : AppSpacing.md),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.isEmpty ? 'Unnamed chef' : name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: (compact
                        ? theme.textTheme.labelMedium
                        : theme.textTheme.titleMedium)
                    ?.copyWith(color: nameColor),
              ),
              // The tier sits under the name, per the product requirement.
              // `onSurfaceImage` has to reach the chip too (B055) — the badge
              // was passing it to the name only, so on a cover photo the name
              // went white and the tier stayed in its light-surface shade.
              if (tier case final tier?) ...[
                const SizedBox(height: AppSpacing.xxs),
                TierChip(tier: tier, dense: compact, onImage: onSurfaceImage),
              ],
            ],
          ),
        ),
      ],
    );

    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: content,
    );
  }
}
