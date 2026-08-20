import 'dart:math' as math;

import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/features/auth/auth_controller.dart';
import 'package:app/routing/app_router.dart';
import 'package:app/routing/nav_destinations.dart';

/// Web top navigation: brand, a centred segmented pill of destinations, and
/// identity at the far right. Nothing else — `New recipe` lives on the page it
/// belongs to (the My Recipes header) and search lives in Discover's search
/// bar, which is what keeps the row down to ~470px at medium.
///
/// Three rules from the design that the layout has to honour:
///
/// * The pill is centred **on the bar**, not between the two clusters, so the
///   wider cluster's width is reserved on both sides ([_BarLayout]).
/// * Labels never wrap. When the pill cannot fit them on one line they drop to
///   icons — the active label last ([_LabelMode]).
/// * Profile is not a destination; it is the avatar, which carries a primary
///   ring and a tier dot so rank is readable at 34px.
class TopNavBar extends ConsumerWidget implements PreferredSizeWidget {
  const TopNavBar({
    super.key,
    required this.location,
    required this.height,
  });

  /// Current shell location, e.g. `/discover`.
  final String location;

  /// Bar height. Required, not defaulted to [kTopNavHeight]: a caller that
  /// forgets it would silently opt out of [heightFor]'s text scaling, which is
  /// the whole reason the bar is not a fixed 64px.
  final double height;

  /// The bar grows with the user's text scale, so a labelled destination is
  /// never squeezed out of a fixed 64px toolbar. Capped at 1.6x: past that the
  /// pill drops labels for icons instead of the chrome eating the page.
  static double heightFor(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return kTopNavHeight * scale.clamp(1.0, 1.6);
  }

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final expanded = context.isExpanded;
    final signedIn = ref.watch(currentUserIdProvider) != null;
    final destinations = webDestinations(signedIn: signedIn);
    final selected = destinations.indexWhere(
      (d) => location.startsWith(d.route),
    );

    return AppBar(
      automaticallyImplyLeading: false,
      toolbarHeight: height,
      titleSpacing: 0,
      backgroundColor: scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      shape: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      // AppBar hands its title unbounded height, and the layout below wants to
      // fill what it is given — so the toolbar height has to be restated here.
      title: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: CustomMultiChildLayout(
            delegate: _BarLayout(gap: AppSpacing.md),
            children: [
              LayoutId(
                id: _BarSlot.brand,
                child: _Brand(expanded: expanded),
              ),
              LayoutId(
                id: _BarSlot.nav,
                child: _NavPill(
                  destinations: destinations,
                  expanded: expanded,
                  // -1 (no match) means nothing is selected — /profile is a
                  // shell route that is not a destination, and highlighting
                  // Discover there would be a lie.
                  selectedIndex: selected < 0 ? null : selected,
                ),
              ),
              LayoutId(
                id: _BarSlot.actions,
                child: signedIn
                    ? _AccountMenu(expanded: expanded)
                    : _SignedOutActions(expanded: expanded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bar height at 1.0x text scale.
const double kTopNavHeight = 64;

const double _kIconSize = 20;
const double _kItemPadH = 14; // with a label
const double _kItemPadIconH = 10; // icon only
const double _kItemPadV = 8;
const double _kIconLabelGap = AppSpacing.sm;
const double _kTrackPad = 4;
const double _kItemGapLabelled = 4;
const double _kItemGapIcons = 2;
const double _kAvatarRadiusExpanded = 17; // 34px, per the design
const double _kAvatarRadiusMedium = 16;

enum _BarSlot { brand, nav, actions }

/// Lays the three clusters out with the pill centred on the **bar**.
///
/// A plain `Row(brand, Expanded(Center(pill)), actions)` centres the pill
/// between the clusters instead, which drifts it right by half the brand's
/// width. Reserving `max(brand, actions)` on both sides costs the pill a little
/// width and buys true centring; when that leaves too little, the pill degrades
/// its labels rather than overflowing.
class _BarLayout extends MultiChildLayoutDelegate {
  _BarLayout({required this.gap});

  final double gap;

  @override
  void performLayout(Size size) {
    final loose = BoxConstraints.loose(size);
    final brand = layoutChild(_BarSlot.brand, loose);
    final actions = layoutChild(_BarSlot.actions, loose);

    final side = math.max(brand.width, actions.width) + gap;
    final nav = layoutChild(
      _BarSlot.nav,
      BoxConstraints.loose(
        Size(math.max(0.0, size.width - side * 2), size.height),
      ),
    );

    positionChild(_BarSlot.brand, Offset(0, (size.height - brand.height) / 2));
    positionChild(
      _BarSlot.actions,
      Offset(size.width - actions.width, (size.height - actions.height) / 2),
    );
    positionChild(
      _BarSlot.nav,
      Offset((size.width - nav.width) / 2, (size.height - nav.height) / 2),
    );
  }

  @override
  bool shouldRelayout(_BarLayout oldDelegate) => oldDelegate.gap != gap;
}

class _Brand extends StatelessWidget {
  const _Brand({required this.expanded});

  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: () => context.go(Routes.discover),
      borderRadius: BorderRadius.circular(AppRadii.button),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.restaurant_menu, color: theme.colorScheme.primary),
            if (expanded) ...[
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Secret Sauce',
                maxLines: 1,
                softWrap: false,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// How many destination labels the pill can afford.
enum _LabelMode { all, activeOnly, none }

class _NavPill extends StatelessWidget {
  const _NavPill({
    required this.destinations,
    required this.selectedIndex,
    required this.expanded,
  });

  final List<NavDestination> destinations;
  final int? selectedIndex;

  /// 1000px and up. Below that the design already spends the row's width on
  /// the page rather than on labels, so only the active one is drawn.
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.titleSmall ?? const TextStyle(fontSize: 14);
    final scaler = MediaQuery.textScalerOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final mode = _fit(constraints.maxWidth, style, scaler);
        final gap =
            mode == _LabelMode.none ? _kItemGapIcons : _kItemGapLabelled;

        return Container(
          padding: const EdgeInsets.all(_kTrackPad),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < destinations.length; i++) ...[
                if (i > 0) SizedBox(width: gap),
                _NavItem(
                  destination: destinations[i],
                  selected: i == selectedIndex,
                  showLabel: switch (mode) {
                    _LabelMode.all => true,
                    _LabelMode.activeOnly => i == selectedIndex,
                    _LabelMode.none => false,
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// The most generous mode that fits [available], starting from the one the
  /// breakpoint asks for.
  ///
  /// Measured rather than guessed: the destination labels are fixed strings but
  /// the text scale is not, and an overflowing pill in fixed-height chrome is
  /// the same class of bug as B001/B002/B016.
  _LabelMode _fit(double available, TextStyle style, TextScaler scaler) {
    final wanted =
        expanded ? [_LabelMode.all, _LabelMode.activeOnly] : [_LabelMode.activeOnly];
    if (!available.isFinite) return wanted.first;

    const iconOnly = _kItemPadIconH * 2 + _kIconSize;
    double labelled(NavDestination d) =>
        _kItemPadH * 2 +
        _kIconSize +
        _kIconLabelGap +
        _measure(d.label, style, scaler);

    double total(_LabelMode mode) {
      final gap = mode == _LabelMode.none ? _kItemGapIcons : _kItemGapLabelled;
      var width = _kTrackPad * 2 + gap * (destinations.length - 1);
      for (var i = 0; i < destinations.length; i++) {
        final showLabel = mode == _LabelMode.all ||
            (mode == _LabelMode.activeOnly && i == selectedIndex);
        width += showLabel ? labelled(destinations[i]) : iconOnly;
      }
      return width;
    }

    for (final mode in wanted) {
      if (total(mode) <= available) return mode;
    }
    // Icons-only is the floor, and nothing below it degrades — a pill that
    // cannot fit even icons overflows silently, in fixed-height chrome. Today
    // three icons need ~132px against the ~460px the 600px bar leaves; a fourth
    // destination or a wider actions cluster is what would break it.
    assert(
      total(_LabelMode.none) <= available || !available.isFinite,
      'nav pill cannot fit ${destinations.length} icons in $available px — '
      'the bar has run out of room to degrade',
    );
    return _LabelMode.none;
  }

  /// Measured at the **selected** weight (w800) whatever the item's real
  /// weight, so the estimate is an upper bound and never under-reserves.
  ///
  /// Disposed on the spot: this runs inside `LayoutBuilder`, so a drag-resize
  /// calls it on every layout pass and a retained painter is a paragraph leak
  /// per frame.
  static double _measure(String text, TextStyle style, TextScaler scaler) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: style.copyWith(fontWeight: FontWeight.w800),
      ),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.showLabel,
  });

  final NavDestination destination;
  final bool selected;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;

    final item = Material(
      // The active chip lifts back to the bar's own colour out of the darker
      // track, with the design's 0 1px 2px shadow.
      color: selected ? scheme.surfaceContainerLowest : Colors.transparent,
      elevation: selected ? 1 : 0,
      shape: const StadiumBorder(),
      child: InkWell(
        onTap: () => context.go(destination.route),
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: showLabel ? _kItemPadH : _kItemPadIconH,
            vertical: _kItemPadV,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? destination.selectedIcon : destination.icon,
                size: _kIconSize,
                color: color,
              ),
              if (showLabel) ...[
                const SizedBox(width: _kIconLabelGap),
                Text(
                  destination.label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.clip,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: color,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    return showLabel
        ? item
        : Tooltip(message: destination.label, child: item);
  }
}

enum _AccountAction { profile, signOut }

/// Identity at the far right: the avatar is the account control, and the menu
/// behind it is where Profile and Sign out moved to.
class _AccountMenu extends ConsumerWidget {
  const _AccountMenu({required this.expanded});

  final bool expanded;

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    _AccountAction action,
  ) async {
    switch (action) {
      case _AccountAction.profile:
        context.go(Routes.profile);
      case _AccountAction.signOut:
        await ref.read(authControllerProvider.notifier).signOut();
        if (context.mounted) context.go(Routes.home);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // valueOrNull, not `when`: a slow or failed profile read must still leave a
    // usable account button rather than a spinner in the chrome.
    final profile = ref.watch(myProfileProvider).valueOrNull;
    final name = (profile?.displayName ?? '').isEmpty
        ? 'Account'
        : profile!.displayName;

    return PopupMenuButton<_AccountAction>(
      tooltip: name,
      position: PopupMenuPosition.under,
      onSelected: (action) async {
        await _run(context, ref, action);
      },
      itemBuilder: (context) => [
        if (profile != null)
          PopupMenuItem(
            enabled: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: AppSpacing.xs),
                TierChip(tier: profile.chefTier),
              ],
            ),
          ),
        if (profile != null) const PopupMenuDivider(),
        const PopupMenuItem(
          value: _AccountAction.profile,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.person_outline),
            title: Text('Profile'),
          ),
        ),
        const PopupMenuItem(
          value: _AccountAction.signOut,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout),
            title: Text('Sign out'),
          ),
        ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ChefAvatar(
            name: profile?.displayName ?? '',
            avatarUrl: profile?.avatarUrl,
            radius: expanded ? _kAvatarRadiusExpanded : _kAvatarRadiusMedium,
            tier: profile?.chefTier,
            ringColor: scheme.primary,
            surfaceColor: scheme.surfaceContainerLowest,
            backgroundColor: scheme.primaryContainer,
            foregroundColor: scheme.onPrimaryContainer,
          ),
          if (expanded)
            Icon(
              Icons.expand_more,
              size: _kIconSize,
              color: scheme.onSurfaceVariant,
            ),
        ],
      ),
    );
  }
}

class _SignedOutActions extends StatelessWidget {
  const _SignedOutActions({required this.expanded});

  final bool expanded;

  @override
  Widget build(BuildContext context) {
    if (!expanded) {
      // Two buttons do not fit beside a centred pill at medium; one filled
      // login button lands on the same screen.
      return IconButton.filled(
        tooltip: 'Sign in or sign up',
        onPressed: () => context.go(Routes.auth),
        icon: const Icon(Icons.login, size: _kIconSize),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed: () => context.go(Routes.auth),
          child: const Text('Sign in'),
        ),
        const SizedBox(width: AppSpacing.sm),
        FilledButton(
          onPressed: () => context.go(Routes.signUp),
          child: const Text('Sign up'),
        ),
      ],
    );
  }
}
