import 'package:cached_network_image/cached_network_image.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'package:design_system/src/widgets/tier_chip.dart';

/// Circular chef avatar: the profile photo when there is one, the chef's
/// initials when there is not.
///
/// Two optional decorations, both used by the web top navigation, where the
/// avatar *is* the account control and has to carry identity at 34px:
///
/// * [ringColor] draws a [surfaceColor] gap and then a ring — the design's
///   `0 0 0 2px surface, 0 0 0 3.5px primary` pair of shadows — marking "this
///   is you".
/// * [tier] adds the rank dot at the bottom-right, so the tier stays readable
///   where a [TierChip] would not fit.
///
/// The ring grows the widget past `radius * 2`: it is drawn outside the circle,
/// as in the design, not inset into it.
class ChefAvatar extends StatelessWidget {
  const ChefAvatar({
    super.key,
    required this.name,
    this.avatarUrl,
    this.radius = 20,
    this.tier,
    this.ringColor,
    this.surfaceColor,
    this.backgroundColor,
    this.foregroundColor,
  });

  /// Display name — the source of the initials fallback.
  final String name;

  final String? avatarUrl;
  final double radius;

  /// Non-null draws the tier dot at the bottom-right.
  final ChefTier? tier;

  /// Non-null draws the ring around the avatar.
  final Color? ringColor;

  /// The colour behind the avatar, used for the ring's gap and the tier dot's
  /// border so both read as cut-outs. Defaults to `surfaceContainerLowest`,
  /// the top navigation's background.
  final Color? surfaceColor;

  /// Fill and text colour of the initials circle. Default to
  /// `surfaceContainerHighest` / `onSurfaceVariant`.
  final Color? backgroundColor;
  final Color? foregroundColor;

  static const double _ringGap = 2;
  static const double _ringWidth = 1.5;

  /// One letter from a single-word name, two from a longer one.
  static String initialsFor(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final surface = surfaceColor ?? scheme.surfaceContainerLowest;

    Widget avatar = _circle(scheme);

    if (ringColor != null) {
      avatar = Container(
        padding: const EdgeInsets.all(_ringGap),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: surface,
          border: Border.all(color: ringColor!, width: _ringWidth),
        ),
        child: avatar,
      );
    }

    if (tier == null) return avatar;

    final dot = (radius * 0.75).clamp(9.0, 16.0);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: 0,
          bottom: 0,
          child: Tooltip(
            message: tier!.label,
            child: Container(
              width: dot,
              height: dot,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: TierChip.colorFor(tier!, theme.brightness),
                border: Border.all(color: surface, width: 2),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _circle(ColorScheme scheme) {
    final background = backgroundColor ?? scheme.surfaceContainerHighest;
    final foreground = foregroundColor ?? scheme.onSurfaceVariant;

    if (avatarUrl == null || avatarUrl!.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: background,
        child: Text(
          initialsFor(name),
          style: TextStyle(
            fontSize: radius * 0.8,
            fontWeight: FontWeight.w700,
            color: foreground,
          ),
        ),
      );
    }

    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: avatarUrl!,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        placeholder: (_, __) => CircleAvatar(
          radius: radius,
          backgroundColor: background,
        ),
        errorWidget: (_, __, ___) => CircleAvatar(
          radius: radius,
          backgroundColor: background,
          child: Icon(Icons.person_outline, color: foreground),
        ),
      ),
    );
  }
}
