import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/routing/app_router.dart';

/// Responsive shell: bottom navigation on compact screens, a navigation rail on
/// wider screens (web/desktop/tablet). A single codebase serves both.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  static const _destinations = [
    _Dest(Routes.discover, Icons.explore_outlined, Icons.explore, 'Discover'),
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
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => _onSelect(context, i),
              extended: context.isExpanded,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: FloatingActionButton(
                  onPressed: () => context.go(Routes.newRecipe),
                  child: const Icon(Icons.add),
                ),
              ),
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: child),
          ],
        ),
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
