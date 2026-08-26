import 'package:app/routing/app_router.dart';
import 'package:app/routing/top_nav_bar.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The web top navigation is fixed-height chrome with a centred pill, which is
/// the same shape of problem as the recipe card (B001/B002/B016): the row
/// cannot grow, so it has to degrade. These pin down what the design fixes —
/// Profile is not a destination, signed-out has no My Recipes, labels drop to
/// icons rather than wrapping or overflowing.
class _FakeAuth implements AuthRepository {
  _FakeAuth(this.uid);

  final String? uid;

  @override
  String? get currentUserId => uid;

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

class _FakeProfiles implements ProfileRepository {
  // Echoes the requested id back, so a caller that looked up the wrong profile
  // would be visible rather than swallowed by a fixed row.
  @override
  Future<Profile?> getById(String id) async => Profile(
    id: id,
    displayName: 'Amara Okonkwo',
    chefTier: ChefTier.sousChef,
  );

  @override
  Future<List<Profile>> searchByName(String query, {int limit = 10}) async =>
      const [];

  @override
  Future<Profile> updateMine(Profile profile) async => profile;
}

class _FakeChefRepository implements ChefRepository {
  @override
  Future<List<ChefStanding>> leaderboard({
    int limit = 50,
    int offset = 0,
  }) async => const [];

  // These tests only exercise the nav chrome; an empty board never reaches a
  // chef page, which is the only caller of either method.
  @override
  Future<List<Recipe>> topRecipes(String chefId, {int limit = 3}) async =>
      const [];

  @override
  Future<ChefStanding?> standing(String chefId) async => null;

  @override
  Future<Map<ChefTier, int>> tierCounts() async => const {};
}

/// Pumps the real router (so the shell picks the chrome) at [location].
Future<void> _pump(
  WidgetTester tester, {
  required double width,
  String location = Routes.chefs,
  String? uid,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(_FakeAuth(uid)),
      profileRepositoryProvider.overrideWithValue(_FakeProfiles()),
      chefRepositoryProvider.overrideWithValue(_FakeChefRepository()),
    ],
  );
  addTearDown(container.dispose);

  final router = container.read(appRouterProvider);
  router.go(location);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.light(),
        routerConfig: router,
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Only text drawn inside the bar — the hosting screen has an app bar with the
/// same title, so an unscoped `find.text` would match either.
Finder _inBar(String text) =>
    find.descendant(of: find.byType(TopNavBar), matching: find.text(text));

void main() {
  testWidgets('expanded, signed in: destinations, no Profile, no New recipe', (
    tester,
  ) async {
    await _pump(tester, width: 1400, uid: 'user-1');

    expect(find.byType(TopNavBar), findsOneWidget);
    expect(_inBar('Discover'), findsOneWidget);
    expect(_inBar('Chefs'), findsOneWidget);
    expect(_inBar('My Recipes'), findsOneWidget);

    // Profile left the destination list for the avatar; New recipe left the
    // bar for the page it belongs to.
    expect(_inBar('Profile'), findsNothing);
    expect(_inBar('New recipe'), findsNothing);

    // Identity: the avatar, with initials when the profile has no photo.
    expect(
      find.descendant(
        of: find.byType(TopNavBar),
        matching: find.byType(ChefAvatar),
      ),
      findsOneWidget,
    );
    expect(_inBar('AO'), findsOneWidget);
  });

  testWidgets('the avatar opens the account menu', (tester) async {
    await _pump(tester, width: 1400, uid: 'user-1');

    await tester.tap(find.byType(ChefAvatar));
    await tester.pumpAndSettle();

    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.text('Sous Chef'), findsOneWidget); // tier in the menu header
  });

  testWidgets('signed out: Sign in / Sign up, and no My Recipes', (
    tester,
  ) async {
    await _pump(tester, width: 1400);

    expect(_inBar('Sign in'), findsOneWidget);
    expect(_inBar('Sign up'), findsOneWidget);
    // Signed out it could only bounce to /auth, so it is not offered.
    expect(_inBar('My Recipes'), findsNothing);
  });

  testWidgets('signed out at medium collapses to one login button', (
    tester,
  ) async {
    await _pump(tester, width: 760);

    expect(_inBar('Sign in'), findsNothing);
    expect(_inBar('Sign up'), findsNothing);
    expect(find.byTooltip('Sign in or sign up'), findsOneWidget);
  });

  testWidgets('labels drop to icons before they wrap — active label last', (
    tester,
  ) async {
    // Three destinations plus identity at a medium width: only the active
    // label survives, and the other two become tooltips.
    await _pump(tester, width: 700, uid: 'user-1');

    expect(_inBar('Chefs'), findsOneWidget); // active, at /chefs
    expect(_inBar('Discover'), findsNothing);
    expect(_inBar('My Recipes'), findsNothing);
    expect(find.byTooltip('Discover'), findsOneWidget);
    expect(find.byTooltip('My Recipes'), findsOneWidget);
  });

  // The reason `_BarLayout` exists: a plain Row + Expanded(Center(…)) centres
  // the pill *between* the clusters, which drifts it right by half the brand.
  // Nothing else in the suite would notice that regression.
  testWidgets('the pill is centred on the bar, not between the clusters', (
    tester,
  ) async {
    await _pump(tester, width: 1400, uid: 'user-1');

    final bar = tester.getRect(find.byType(TopNavBar));
    final pill = tester.getRect(
      find.descendant(
        of: find.byType(TopNavBar),
        matching: find.text('Chefs'), // the active destination's chip
      ),
    );
    // The active chip is the middle of three destinations, so its centre is the
    // pill's centre to within a chip's own asymmetry.
    expect(
      (pill.center.dx - bar.center.dx).abs(),
      lessThan(40),
      reason:
          'pill drifted ${pill.center.dx - bar.center.dx}px off the bar centre',
    );
  });

  testWidgets('Sign up opens the auth screen on its sign-up side', (
    tester,
  ) async {
    await _pump(tester, width: 1400);

    await tester.tap(_inBar('Sign up'));
    await tester.pumpAndSettle();

    // `/auth?mode=signup` — the sign-up form asks for a display name; the
    // sign-in form does not.
    expect(find.text('Create your account'), findsOneWidget);
    expect(find.text('Display name'), findsOneWidget);
  });

  testWidgets('Sign in opens the same screen on its sign-in side', (
    tester,
  ) async {
    await _pump(tester, width: 1400);

    await tester.tap(_inBar('Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Display name'), findsNothing);
  });

  testWidgets('tapping a destination navigates', (tester) async {
    await _pump(tester, width: 1400, uid: 'user-1');

    await tester.tap(_inBar('Discover'));
    await tester.pumpAndSettle();

    expect(find.byType(TopNavBar), findsOneWidget);
    expect(_inBar('Discover'), findsOneWidget);
  });

  // The envelope the chrome has to survive: the narrowest width that still
  // draws a top bar, the widest common desktop, and 2.0x accessibility text.
  for (final (width, scale) in <(double, double)>[
    (600, 1.0),
    (760, 1.0),
    (1000, 1.0),
    (1400, 1.0),
    (600, 2.0),
    (1000, 2.0),
    (1400, 2.0),
  ]) {
    testWidgets('fits at ${width}px, textScale $scale', (tester) async {
      await _pump(tester, width: width, uid: 'user-1', textScale: scale);
      expect(
        tester.takeException(),
        isNull,
        reason: 'overflow at ${width}px @ ${scale}x',
      );
    });
  }
}
