import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/routing/app_router.dart';

/// Responsive shell: bottom navigation on compact screens, a fixed top
/// navigation bar on wider screens (web/desktop/tablet). A single codebase
/// serves both.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  static const _destinations = [
    _Dest(Routes.discover, Icons.explore_outlined, Icons.explore, 'Discover'),
    _Dest(Routes.chefs, Icons.emoji_events_outlined, Icons.emoji_events,
        'Chefs'),
    _Dest(Routes.myRecipes, Icons.menu_book_outlined, Icons.menu_book,
        'My Recipes'),
    _Dest(Routes.profile, Icons.person_outline, Icons.person, 'Profile'),
  ];

  int get _index {
    final i = _destinations.indexWhere((d) => location.startsWith(d.route));
    return i < 0 ? 0 : i;
  }

  void _onSelect(BuildContext context, int i) =>
      context.go(_destinations[i].route);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = context.isExpanded || context.screenSize == ScreenSize.medium;

    final fab = FloatingActionButton.extended(
      onPressed: () => context.go(Routes.newRecipe),
      icon: const Icon(Icons.add),
      label: const Text('New recipe'),
    );

    if (wide) {
      final theme = Theme.of(context);
      final expanded = context.isExpanded;
      return Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          titleSpacing: AppSpacing.lg,
          title: Row(
            children: [
              InkWell(
                onTap: () => context.go(Routes.discover),
                borderRadius: BorderRadius.circular(AppSpacing.sm),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.restaurant_menu,
                          color: theme.colorScheme.primary),
                      if (expanded) ...[
                        const SizedBox(width: AppSpacing.sm),
                        Text('Secret Sauce',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            )),
                      ],
                    ],
                  ),
                ),
              ),
              SizedBox(width: expanded ? AppSpacing.xl : AppSpacing.md),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < _destinations.length; i++)
                        _TopNavItem(
                          destination: _destinations[i],
                          selected: _index == i,
                          showLabel: expanded,
                          onTap: () => _onSelect(context, i),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: expanded
                  ? FilledButton.icon(
                      onPressed: () => context.go(Routes.newRecipe),
                      icon: const Icon(Icons.add),
                      label: const Text('New recipe'),
                    )
                  : IconButton.filled(
                      tooltip: 'New recipe',
                      onPressed: () => context.go(Routes.newRecipe),
                      icon: const Icon(Icons.add),
                    ),
            ),
          ],
        ),
        body: child,
      );
    }

    return Scaffold(
      body: child,
      floatingActionButton: fab,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => _onSelect(context, i),
        destinations: [
          for (final d in _destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
            ),
        ],
      ),
    );
  }
}

class _Dest {
  const _Dest(this.route, this.icon, this.selectedIcon, this.label);
  final String route;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class _TopNavItem extends StatelessWidget {
  const _TopNavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
    this.showLabel = true,
  });

  final _Dest destination;
  final bool selected;
  final bool showLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Tooltip(
        message: showLabel ? '' : destination.label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.sm),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: showLabel ? AppSpacing.md : AppSpacing.sm,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  color: color,
                  size: 20,
                ),
                if (showLabel) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    destination.label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: color,
                      fontWeight:
                          selected ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
