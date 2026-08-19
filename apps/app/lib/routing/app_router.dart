import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/features/auth/auth_screen.dart';
import 'package:app/features/chefs/chefs_screen.dart';
import 'package:app/features/discover/discover_screen.dart';
import 'package:app/features/home/home_screen.dart';
import 'package:app/features/my_recipes/my_recipes_screen.dart';
import 'package:app/features/profile/profile_screen.dart';
import 'package:app/features/recipe_detail/recipe_detail_screen.dart';
import 'package:app/features/recipe_editor/recipe_editor_screen.dart';
import 'package:app/routing/app_shell.dart';

/// Route path constants.
class Routes {
  Routes._();
  static const home = '/';
  static const auth = '/auth';
  static const discover = '/discover';
  static const chefs = '/chefs';
  static const myRecipes = '/my';
  static const profile = '/profile';
  static const newRecipe = '/recipe/new';
  static String recipe(String id) => '/recipe/$id';
  static String editRecipe(String id) => '/recipe/$id/edit';
}

final _rootKey = GlobalKey<NavigatorState>();
final _shellKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  final authRepo = ref.watch(authRepositoryProvider);
  final refresh = GoRouterRefreshStream(authRepo.authStateChanges());
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: Routes.home,
    refreshListenable: refresh,
    redirect: (context, state) {
      final signedIn = authRepo.currentUserId != null;
      final loc = state.matchedLocation;
      final needsAuth = loc == Routes.myRecipes ||
          loc == Routes.profile ||
          loc == Routes.newRecipe ||
          loc.endsWith('/edit');
      if (!signedIn && needsAuth) return Routes.auth;
      if (signedIn && loc == Routes.auth) return Routes.discover;
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.home,
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: Routes.auth,
        builder: (context, state) => const AuthScreen(),
      ),
      GoRoute(
        path: '/recipe/new',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const RecipeEditorScreen(),
      ),
      GoRoute(
        path: '/recipe/:id/edit',
        parentNavigatorKey: _rootKey,
        builder: (context, state) =>
            RecipeEditorScreen(recipeId: state.pathParameters['id']),
      ),
      GoRoute(
        path: '/recipe/:id',
        parentNavigatorKey: _rootKey,
        builder: (context, state) =>
            RecipeDetailScreen(recipeId: state.pathParameters['id']!),
      ),
      ShellRoute(
        navigatorKey: _shellKey,
        builder: (context, state, child) =>
            AppShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(
            path: Routes.discover,
            builder: (context, state) => const DiscoverScreen(),
          ),
          // Signed-out safe, like Discover — deliberately absent from the
          // `needsAuth` list above.
          GoRoute(
            path: Routes.chefs,
            builder: (context, state) => const ChefsScreen(),
          ),
          GoRoute(
            path: Routes.myRecipes,
            builder: (context, state) => const MyRecipesScreen(),
          ),
          GoRoute(
            path: Routes.profile,
            builder: (context, state) => const ProfileScreen(),
          ),
        ],
      ),
    ],
  );
});

/// Bridges a [Stream] to a [Listenable] so GoRouter re-evaluates redirects.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _sub = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
