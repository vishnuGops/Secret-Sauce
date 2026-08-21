import 'package:flutter/material.dart';

import 'package:app/routing/app_router.dart';

/// One navigation destination: a shell route and how it is drawn.
@immutable
class NavDestination {
  const NavDestination({
    required this.route,
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final String route;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

const _discover = NavDestination(
  route: Routes.discover,
  icon: Icons.explore_outlined,
  selectedIcon: Icons.explore,
  label: 'Discover',
);

const _chefs = NavDestination(
  route: Routes.chefs,
  icon: Icons.emoji_events_outlined,
  selectedIcon: Icons.emoji_events,
  label: 'Chefs',
);

const _myRecipes = NavDestination(
  route: Routes.myRecipes,
  icon: Icons.menu_book_outlined,
  selectedIcon: Icons.menu_book,
  label: 'My Recipes',
);

const _profile = NavDestination(
  route: Routes.profile,
  icon: Icons.person_outline,
  selectedIcon: Icons.person,
  label: 'Profile',
);

/// Bottom navigation, compact widths. Profile is a destination here: a phone
/// has no room for an account menu in the chrome, and the bar is always four
/// slots so it does not reflow on sign-in.
const kMobileDestinations = <NavDestination>[
  _discover,
  _chefs,
  _myRecipes,
  _profile,
];

/// Top navigation, web/medium-and-up widths.
///
/// Profile is **not** here — it is the avatar at the far right, where it also
/// reads as "account". My Recipes only appears signed in: signed out it is a
/// destination that can only bounce to `/auth`.
List<NavDestination> webDestinations({required bool signedIn}) => [
  _discover,
  _chefs,
  if (signedIn) _myRecipes,
];
