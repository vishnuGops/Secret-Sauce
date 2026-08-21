import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:app/features/auth/auth_screen.dart';
import 'package:app/features/chefs/chefs_screen.dart';
import 'package:app/features/discover/discover_screen.dart';
import 'package:app/features/my_recipes/my_recipes_screen.dart';
import 'package:app/features/profile/profile_screen.dart';
import 'package:app/features/recipe_detail/recipe_detail_screen.dart';
import 'package:app/features/recipe_editor/recipe_editor_screen.dart';
import 'package:app/routing/app_shell.dart';

/// Route path constants.
class Routes {
  Routes._();

  /// The bare root. **Not a page** — a redirect-only route that forwards to
  /// [discover], which is the front door on both chromes. The landing screen it
  /// used to serve was retired, so nothing should navigate *to* this constant;
  /// it exists because a bookmark, a hard refresh of `http://host/`, or a
  /// platform cold start still arrives here.
  static const root = '/';
  static const auth = '/auth';

  /// Same screen as [auth], opened on its sign-up tab — the top navigation
  /// offers both doors and they must not land on the same one.
  static const signUp = '/auth?mode=signup';
  static const discover = '/discover';
  static const chefs = '/chefs';
  static const myRecipes = '/my';
  static const profile = '/profile';
  static const newRecipe = '/recipe/new';
  static String recipe(String id) => '/recipe/$id';
  static String editRecipe(String id) => '/recipe/$id/edit';

  /// The two **patterns** go_router matches on, as opposed to the builders
  /// above that produce a concrete path. Both forms have to exist and they have
  /// to stay in step: `recipePattern` is what the route declares,
  /// [recipe] is what a caller navigates with, and a rename that touches only
  /// one of them compiles and 404s (OPT-A8 — they used to be literals in the
  /// route table, the one place a rename silently misses).
  static const recipePattern = '/recipe/:id';
  static const editRecipePattern = '/recipe/:id/edit';
}

final _rootKey = GlobalKey<NavigatorState>();
final _shellKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  final authRepo = ref.watch(authRepositoryProvider);
  final refresh = GoRouterRefreshStream(authRepo.authStateChanges());
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootKey,
    // Covers a cold start on mobile/desktop, where the platform reports no
    // route. Web reports `/`, and the redirect-only root route below is what
    // handles that — both are needed.
    initialLocation: Routes.discover,
    refreshListenable: refresh,
    redirect: (context, state) {
      final signedIn = authRepo.currentUserId != null;
      final loc = state.matchedLocation;
      final needsAuth =
          loc == Routes.myRecipes ||
          loc == Routes.profile ||
          loc == Routes.newRecipe ||
          loc.endsWith('/edit');
      if (!signedIn && needsAuth) return Routes.auth;
      if (signedIn && loc == Routes.auth) return Routes.discover;
      return null;
    },
    routes: [
      // Redirect-only: no builder, so `/` never renders anything. The
      // top-level redirect above runs first and passes it through (root is not
      // in `needsAuth`), then this forwards to Discover for signed-in and
      // signed-out visitors alike.
      GoRoute(path: Routes.root, redirect: (context, state) => Routes.discover),
      GoRoute(
        path: Routes.auth,
        builder:
            (context, state) => AuthScreen(
              startOnSignUp: state.uri.queryParameters['mode'] == 'signup',
            ),
      ),
      GoRoute(
        path: Routes.newRecipe,
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const RecipeEditorScreen(),
      ),
      GoRoute(
        path: Routes.editRecipePattern,
        parentNavigatorKey: _rootKey,
        builder:
            (context, state) =>
                RecipeEditorScreen(recipeId: state.pathParameters['id']),
      ),
      GoRoute(
        path: Routes.recipePattern,
        parentNavigatorKey: _rootKey,
        builder:
            (context, state) =>
                RecipeDetailScreen(recipeId: state.pathParameters['id']!),
      ),
      ShellRoute(
        navigatorKey: _shellKey,
        builder:
            (context, state, child) =>
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
