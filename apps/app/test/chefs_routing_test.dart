import 'dart:async';

import 'package:app/features/chefs/chefs_screen.dart';
import 'package:app/features/legal/legal_document.dart';
import 'package:app/features/legal/legal_screen.dart';
import 'package:app/routing/app_router.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// `/chefs` is signed-out safe by design, like Discover — it is deliberately
/// absent from the router's `needsAuth` list, and `chefs_leaderboard` is granted
/// to `anon` so the data is there without a session.
///
/// Nothing else in the suite pins that down. Adding `Routes.chefs` to
/// `needsAuth` (an easy mistake — the three routes around it are all guarded)
/// would bounce every signed-out visitor to `/auth` with no test failing, so
/// these assert both halves: the open route stays open, and the guarded routes
/// stay guarded.
class _FakeAuth implements AuthRepository {
  _FakeAuth(this.uid);

  final String? uid;

  @override
  String? get currentUserId => uid;

  // Phase 35b: `profiles.id` and the auth uid are the same value for a member,
  // which every fixture in this file is.
  @override
  Future<String?> currentProfileId() async => uid;

  @override
  Stream<AuthState> authStateChanges() => const Stream.empty();

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {}

  @override
  Future<void> signOut() async {}
}

class _FakeChefRepository implements ChefRepository {
  @override
  Future<List<ChefStanding>> leaderboard({
    int limit = 50,
    int offset = 0,
  }) async => const [
    ChefStanding(
      chefRank: 1,
      id: 'd1',
      displayName: 'Amara Okonkwo',
      chefTier: ChefTier.masterChef,
      chefScore: 21000,
      publicRecipeCount: 2,
    ),
  ];

  // Only reached from a chef page, which these routing tests never open.
  @override
  Future<List<Recipe>> topRecipes(
    String chefId, {
    int limit = 3,
    int offset = 0,
  }) async => const [];

  @override
  Future<List<Recipe>> trendingRecipes(
    String chefId, {
    int limit = 20,
    int offset = 0,
  }) async => const [];

  @override
  Future<ChefStanding?> standing(String chefId) async => null;

  @override
  Future<Map<ChefTier, int>> tierCounts() async => const {};
}

Future<GoRouter> _pumpAt(
  WidgetTester tester,
  String location, {
  String? uid,
}) async {
  // Wide enough for the top nav bar, so destination labels render.
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(_FakeAuth(uid)),
      chefRepositoryProvider.overrideWithValue(_FakeChefRepository()),
    ],
  );
  addTearDown(container.dispose);

  final router = container.read(appRouterProvider);
  router.go(location);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

String _location(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.path;

void main() {
  testWidgets('/chefs renders signed out — no redirect to /auth', (
    tester,
  ) async {
    final router = await _pumpAt(tester, Routes.chefs);

    expect(_location(router), Routes.chefs);
    expect(find.byType(ChefsScreen), findsOneWidget);
    // At 1400px this is the two-column page, so the chef is on the board panel
    // and again on the Popular rail's spotlight card.
    expect(find.text('Amara Okonkwo'), findsWidgets);
  });

  testWidgets('/chefs also renders signed in', (tester) async {
    final router = await _pumpAt(tester, Routes.chefs, uid: 'user-1');

    expect(_location(router), Routes.chefs);
    expect(find.byType(ChefsScreen), findsOneWidget);
  });

  testWidgets('the Chefs destination is in the shell nav', (tester) async {
    await _pumpAt(tester, Routes.chefs);

    // Sits inside the ShellRoute, so the nav chrome is present alongside it.
    expect(find.text('Chefs'), findsWidgets);
    expect(find.text('Discover'), findsWidgets);
  });

  // The other half: the guard still works, so a test that "passes" because
  // redirects were disabled outright would fail here. One test per route —
  // pumping two routers in a single test leaves the first one's timers running.
  for (final guarded in [Routes.myRecipes, Routes.profile, Routes.newRecipe]) {
    testWidgets('$guarded bounces a signed-out visitor to /auth', (
      tester,
    ) async {
      final router = await _pumpAt(tester, guarded);
      expect(_location(router), Routes.auth);
    });
  }

  testWidgets('a signed-in visitor reaches a guarded route', (tester) async {
    final router = await _pumpAt(tester, Routes.profile, uid: 'user-1');
    expect(_location(router), Routes.profile);
  });

  // Phase 35a. The web chrome carries the legal links in the shell's
  // `bottomNavigationBar`, and this file is the only place that pumps the real
  // shell at a wide width — `legal_screen_test.dart` opens the pages directly,
  // which exercises a different navigator entirely.
  //
  // The mechanism worth pinning is the `push` out of the shell: the legal route
  // declares `parentNavigatorKey: _rootKey`, so a tap inside the shell has to
  // cross from the shell navigator to the root one. That either works or it
  // does nothing at all, and nothing else here would notice.
  //
  // **These assert `state.matchedLocation`, not [_location].** An imperative
  // `push` layers a route on top without moving the *base* configuration, so
  // `currentConfiguration.uri` still reads `/chefs` while the pushed page is on
  // screen. `_location` is the right probe for the redirect tests above, which
  // are all declarative `go`s, and the wrong one here — it reports a pass as a
  // failure, which cost one debugging round to find.
  group('the legal footer in the web chrome (Phase 35a)', () {
    testWidgets('is present on a shell screen', (tester) async {
      await _pumpAt(tester, Routes.chefs);

      for (final doc in LegalDoc.values) {
        expect(
          find.text(doc.shortLabel),
          findsWidgets,
          reason: '${doc.shortLabel} missing from the chrome',
        );
      }
    });

    testWidgets('tapping it leaves the shell for the document', (tester) async {
      final router = await _pumpAt(tester, Routes.chefs);

      await tester.tap(find.text(LegalDoc.privacy.shortLabel).last);
      await tester.pumpAndSettle();

      expect(router.state.matchedLocation, Routes.legal(LegalDoc.privacy.slug));
      expect(find.byType(LegalScreen), findsOneWidget);
      // That the shell SURVIVES underneath is asserted by the back test below,
      // not here: the pushed route is opaque, so Flutter stops building the
      // route beneath it and a finder for `ChefsScreen` legitimately sees
      // nothing. Popping back is the observable form of the same claim.
    });

    testWidgets('and hands the reader back', (tester) async {
      // `push`, not `go`: the point of a chrome link is that reading the terms
      // does not cost you the page you were on.
      final router = await _pumpAt(tester, Routes.chefs);

      await tester.tap(find.text(LegalDoc.terms.shortLabel).last);
      await tester.pumpAndSettle();
      expect(router.state.matchedLocation, Routes.legal(LegalDoc.terms.slug));

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(router.state.matchedLocation, Routes.chefs);
      expect(find.byType(LegalScreen), findsNothing);
    });
  });
}
