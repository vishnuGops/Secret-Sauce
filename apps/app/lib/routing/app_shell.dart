import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/routing/app_router.dart';
import 'package:app/routing/nav_destinations.dart';
import 'package:app/routing/top_nav_bar.dart';

/// Responsive shell: bottom navigation on compact screens, the web
/// [TopNavBar] on wider ones. A single codebase serves both.
///
/// The two chromes carry different destination lists on purpose — see
/// [kMobileDestinations] and [webDestinations].
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  int get _index {
    final i =
        kMobileDestinations.indexWhere((d) => location.startsWith(d.route));
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = !context.isCompact;

    if (wide) {
      return Scaffold(
        appBar: TopNavBar(
          location: location,
          height: TopNavBar.heightFor(context),
        ),
        body: child,
      );
    }

    return Scaffold(
      body: child,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go(Routes.newRecipe),
        icon: const Icon(Icons.add),
        label: const Text('New recipe'),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => context.go(kMobileDestinations[i].route),
        destinations: [
          for (final d in kMobileDestinations)
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
