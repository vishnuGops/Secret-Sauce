import 'package:cached_network_image/cached_network_image.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'package:design_system/src/theme/app_theme.dart';
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
    required this.tier,
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
  }) =>
      ChefBadge(
        key: key,
        name: profile.displayName,
        tier: profile.chefTier,
        avatarUrl: profile.avatarUrl,
        compact: compact,
        onSurfaceImage: onSurfaceImage,
        onTap: onTap,
      );

  final String name;
  final ChefTier tier;
  final String? avatarUrl;
  final bool compact;

  /// Set when the badge sits on a cover photo rather than a theme surface, so
  /// the name is drawn in the scrim's foreground color instead of `onSurface`.
  final bool onSurfaceImage;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = compact ? 12.0 : 20.0;
    final nameColor = onSurfaceImage ? Colors.white : scheme.onSurface;

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Avatar(url: avatarUrl, name: name, radius: radius, scheme: scheme),
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
                    ?.copyWith(fontWeight: FontWeight.w700, color: nameColor),
              ),
              const SizedBox(height: 2),
              // The tier sits under the name, per the product requirement.
              TierChip(tier: tier, dense: compact),
            ],
          ),
        ),
      ],
    );

    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.button),
      child: content,
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.url,
    required this.name,
    required this.radius,
    required this.scheme,
  });

  final String? url;
  final String name;
  final double radius;
  final ColorScheme scheme;

  String get _initials {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: scheme.surfaceContainerHighest,
        child: Text(
          _initials,
          style: TextStyle(
            fontSize: radius * 0.8,
            fontWeight: FontWeight.w700,
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url!,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        placeholder: (_, __) => CircleAvatar(
          radius: radius,
          backgroundColor: scheme.surfaceContainerHighest,
        ),
        errorWidget: (_, __, ___) => CircleAvatar(
          radius: radius,
          backgroundColor: scheme.surfaceContainerHighest,
          child: Icon(Icons.person_outline, color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
