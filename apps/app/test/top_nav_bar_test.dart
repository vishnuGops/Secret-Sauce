import 'dart:ui' show Tristate;

import 'package:app/features/chefs/chef_page.dart';
import 'package:app/routing/app_router.dart';
import 'package:app/routing/nav_destinations.dart';
import 'package:app/routing/top_nav_bar.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

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
  Future<SignUpOutcome> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async => SignUpOutcome.signedIn;

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

  // Phase 33's board sorts and windowed rails. Empty is the honest answer for
  // a fake with no chefs; nothing here asserts on the board's contents.
  @override
  Future<List<ChefStanding>> newest({int limit = 50, int offset = 0}) async =>
      const [];

  @override
  Future<List<ChefWindowStanding>> windowedLeaderboard({
    required int days,
    int limit = 50,
    int offset = 0,
    DateTime? since,
  }) async => const [];

  @override
  Future<ChefWindowStats?> windowStats(
    String chefId, {
    required int days,
    DateTime? since,
  }) async => null;
}

/// Pumps the real router (so the shell picks the chrome) at [location], and
/// returns it so a test can read where a tap went.
Future<GoRouter> _pump(
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
  return router;
}

/// The router's current location, query included.
Uri _here(GoRouter router) => router.routerDelegate.currentConfiguration.uri;

/// Only text drawn inside the bar — the hosting screen has an app bar with the
/// same title, so an unscoped `find.text` would match either.
Finder _inBar(String text) =>
    find.descendant(of: find.byType(TopNavBar), matching: find.text(text));

SemanticsData _a11y(WidgetTester tester, Finder finder) =>
    tester.getSemantics(finder).getSemanticsData();

/// A control's own box is at least 48 × 48 — measured, not left to the
/// guideline, which can misjudge nodes near an edge (Gotcha 30).
void _expectTarget(WidgetTester tester, Finder finder, String what) {
  final size = tester.getSize(finder);
  expect(
    size.width >= kMinInteractiveDimension &&
        size.height >= kMinInteractiveDimension,
    isTrue,
    reason: '$what is $size, under 48 × 48',
  );
}

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

  testWidgets('36c look: white bar, tomato wordmark, tinted active pill', (
    tester,
  ) async {
    await _pump(tester, width: 1400, uid: 'user-1');
    final scheme = AppTheme.light().colorScheme;

    final bar = tester.widget<AppBar>(
      find.descendant(
        of: find.byType(TopNavBar),
        matching: find.byType(AppBar),
      ),
    );
    expect(bar.backgroundColor, scheme.surface);
    expect(
      tester.widget<Text>(_inBar('Secret Sauce')).style?.color,
      scheme.primary,
    );

    // The active destination (Chefs) sits on primaryContainer in its ink; the
    // others are unfilled.
    Material chipOf(String label) => tester.widget<Material>(
      find.ancestor(of: _inBar(label), matching: find.byType(Material)).first,
    );
    expect(chipOf('Chefs').color, scheme.primaryContainer);
    expect(
      tester.widget<Text>(_inBar('Chefs')).style?.color,
      scheme.onPrimaryContainer,
    );
    expect(chipOf('Discover').color, Colors.transparent);
  });

  testWidgets('the avatar opens the account menu', (tester) async {
    await _pump(tester, width: 1400, uid: 'user-1');

    await tester.tap(find.byType(ChefAvatar));
    await tester.pumpAndSettle();

    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('View my chef page'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.text('Sous Chef'), findsOneWidget); // tier in the menu header
  });

  // UX-038: nothing linked a member to their own public page.
  testWidgets('the account menu opens my chef page', (tester) async {
    await _pump(tester, width: 1400, uid: 'user-1');

    await tester.tap(find.byType(ChefAvatar));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View my chef page'));
    await tester.pumpAndSettle();

    // Pushed, so asserted on the page rather than the base location. The fake
    // profile echoes the id it was asked for, so this is the loaded
    // `profiles.id`, which is what `/chef/:id` takes (Phase 35b).
    expect(find.byType(ChefPage), findsOneWidget);
    expect(tester.widget<ChefPage>(find.byType(ChefPage)).chefId, 'user-1');
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

  // UX-017: every way into /auth from the chrome remembers the page the
  // visitor was on, so signing in brings them back to it.
  testWidgets('Sign in carries ?from= the current page', (tester) async {
    final router = await _pump(tester, width: 1400);

    await tester.tap(_inBar('Sign in'));
    await tester.pumpAndSettle();

    expect(_here(router).path, Routes.auth);
    expect(_here(router).queryParameters['from'], Routes.chefs);
    expect(_here(router).queryParameters['mode'], isNull);
  });

  testWidgets('Sign up carries ?from= as well as mode=signup', (tester) async {
    final router = await _pump(tester, width: 1400);

    await tester.tap(_inBar('Sign up'));
    await tester.pumpAndSettle();

    expect(_here(router).path, Routes.auth);
    expect(_here(router).queryParameters['mode'], 'signup');
    expect(_here(router).queryParameters['from'], Routes.chefs);
  });

  testWidgets('the medium login button carries ?from= too', (tester) async {
    final router = await _pump(tester, width: 760);

    await tester.tap(find.byTooltip('Sign in or sign up'));
    await tester.pumpAndSettle();

    expect(_here(router).path, Routes.auth);
    expect(_here(router).queryParameters['from'], Routes.chefs);
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

  // UX-048: every control in the web chrome is at least 48 × 48 (WCAG 2.5.8
  // via Flutter's Android guideline, the stricter of the two it ships) — the
  // brand, the pill's destinations, the account cluster and the legal bar,
  // signed in and out, with labels (1440) and as bare icons (800).
  for (final (width, uid) in <(double, String?)>[
    (1440, 'user-1'),
    (1440, null),
    (800, 'user-1'),
    (800, null),
  ]) {
    testWidgets('every tap target meets the 48dp guideline at ${width}px, '
        '${uid == null ? 'signed out' : 'signed in'}', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, width: width, uid: uid);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });
  }

  // Phase 39: the full envelope, both identity states. The signed-in bar at
  // 1000 × 2.0 is the tightest pill (three destinations beside the avatar);
  // signed out trades My Recipes for Sign in / Sign up, which at expanded are
  // two text buttons whose width grows with the scale — a different budget,
  // and one nothing pumped before. Beyond "no exception" each case asserts
  // what an overflow-free bar can still get wrong: a control shrunk under
  // 48dp, a clipped label, clusters painted over each other, and a control
  // pushed past the window's right edge.
  group('envelope', () {
    for (final (width, scale, uid) in <(double, double, String?)>[
      (600, 1.0, null),
      (600, 2.0, null),
      (1000, 1.0, null),
      (1000, 2.0, null),
      (1440, 2.0, null),
      (600, 1.0, 'user-1'),
      (600, 2.0, 'user-1'),
      (1000, 2.0, 'user-1'),
    ]) {
      final state = uid == null ? 'signed out' : 'signed in';
      testWidgets('$state at ${width}px, textScale $scale', (tester) async {
        final handle = tester.ensureSemantics();
        await _pump(tester, width: width, uid: uid, textScale: scale);
        final where = '$state, ${width}px @ ${scale}x';

        expect(tester.takeException(), isNull, reason: 'overflow: $where');

        final bar = find.byType(TopNavBar);
        Finder inBar(Finder f) => find.descendant(of: bar, matching: f);

        // Every destination is drawn, each in its own 48dp target (measured
        // directly — Gotcha 30).
        final destinations = webDestinations(signedIn: uid != null);
        final targets = <Rect>[];
        final shown = <String>{};
        for (final d in destinations) {
          final icon = inBar(
            find.byWidgetPredicate(
              (w) =>
                  w is Icon && (w.icon == d.icon || w.icon == d.selectedIcon),
            ),
          );
          expect(icon, findsOneWidget, reason: '${d.label} missing: $where');
          // The item's outer 48dp box — not the chip's InkWell, which builds
          // a GestureDetector of its own.
          final target = find.ancestor(
            of: icon,
            matching: find.byWidgetPredicate(
              (w) => w is GestureDetector && w.child is ConstrainedBox,
            ),
          );
          expect(target, findsOneWidget, reason: '${d.label}: $where');
          _expectTarget(tester, target, '${d.label} ($where)');
          targets.add(tester.getRect(target));
          if (_inBar(d.label).evaluate().isNotEmpty) shown.add(d.label);
        }

        // Labels degrade as a set, the active one last: all, the active
        // alone, or none — never some other subset.
        final labels = {for (final d in destinations) d.label};
        expect(
          shown.isEmpty ||
              shown.length == labels.length ||
              (shown.length == 1 && shown.single == 'Chefs'), // at /chefs
          isTrue,
          reason: 'labels shown $shown of $labels: $where',
        );

        // Identity: the avatar signed in; signed out, Sign in + Sign up at
        // expanded or the single login button below it.
        final Finder actions;
        if (uid != null) {
          actions = inBar(find.byWidgetPredicate((w) => w is PopupMenuButton));
          expect(actions, findsOneWidget, reason: 'avatar missing: $where');
          _expectTarget(tester, actions, 'avatar ($where)');
          // Its own button node, not merged into the AppBar title's header
          // node — which spans the bar, touches the window's edge, and is
          // therefore skipped by the guideline below (Phase 39).
          final avatar = _a11y(tester, actions);
          expect(avatar.flagsCollection.isButton, isTrue, reason: where);
          expect(avatar.flagsCollection.isHeader, isFalse, reason: where);
          // Named for the account, never by its initials (Phase 39 review).
          expect(avatar.label, contains('Amara Okonkwo'), reason: where);
          expect(avatar.label, isNot(contains('AO')), reason: where);
          expect(
            avatar.rect.width < width,
            isTrue,
            reason: 'the avatar node spans the bar: $where',
          );
        } else if (width >= 1000) {
          final signIn = inBar(find.widgetWithText(TextButton, 'Sign in'));
          final signUp = inBar(find.widgetWithText(FilledButton, 'Sign up'));
          expect(signIn, findsOneWidget, reason: 'Sign in missing: $where');
          expect(signUp, findsOneWidget, reason: 'Sign up missing: $where');
          _expectTarget(tester, signIn, 'Sign in ($where)');
          _expectTarget(tester, signUp, 'Sign up ($where)');
          // Side by side, in reading order.
          expect(
            tester.getRect(signIn).right,
            lessThanOrEqualTo(tester.getRect(signUp).left),
            reason: 'Sign in overlaps Sign up: $where',
          );
          actions = signUp;
        } else {
          actions = find.ancestor(
            of: inBar(find.byTooltip('Sign in or sign up')),
            matching: find.byType(IconButton),
          );
          expect(actions, findsOneWidget, reason: 'login missing: $where');
          _expectTarget(tester, actions, 'login button ($where)');
        }

        final brand =
            find
                .ancestor(
                  of: inBar(find.byIcon(Icons.restaurant_menu)),
                  matching: find.byType(InkWell),
                )
                .first;
        _expectTarget(tester, brand, 'brand ($where)');

        // The three clusters in order and apart: brand, pill, identity, all
        // inside the window.
        final pill = targets.reduce((a, b) => a.expandToInclude(b));
        final brandRect = tester.getRect(brand);
        final actionsRect = tester.getRect(actions);
        expect(brandRect.left, greaterThanOrEqualTo(0), reason: where);
        expect(
          brandRect.right,
          lessThanOrEqualTo(pill.left),
          reason: 'brand runs into the pill: $where',
        );
        expect(
          pill.right,
          lessThanOrEqualTo(actionsRect.left),
          reason: 'pill runs into the identity cluster: $where',
        );
        expect(
          actionsRect.right,
          lessThanOrEqualTo(width),
          reason: 'identity pushed off-screen: $where',
        );

        // No text in the bar is cut: every paragraph is at least as wide as
        // its one-line intrinsic width, so nothing is clipped (the pill's
        // labels are `softWrap: false` + clip, where `didExceedMaxLines` stays
        // false even when clipped) and nothing wraps (the buttons' labels).
        // A relation, not a pixel width — it survives the test font.
        for (final element in inBar(find.byType(RichText)).evaluate()) {
          final paragraph = element.renderObject! as RenderParagraph;
          final text = paragraph.text.toPlainText();
          expect(
            paragraph.size.width,
            greaterThanOrEqualTo(
              paragraph.getMaxIntrinsicWidth(double.infinity) - 0.5,
            ),
            reason: '"$text" is clipped or wrapped: $where',
          );
        }

        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        handle.dispose();
      });
    }
  });

  // Phase 37 wave C (UX-014).
  group('semantics', () {
    testWidgets('the current destination is selected, and only it', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, width: 1400, uid: 'user-1');

      Tristate selected(String label) =>
          _a11y(tester, _inBar(label)).flagsCollection.isSelected;
      expect(selected('Chefs'), Tristate.isTrue);
      expect(selected('Discover'), Tristate.isFalse);
      expect(selected('My Recipes'), Tristate.isFalse);
      expect(_a11y(tester, _inBar('Chefs')).flagsCollection.isButton, isTrue);
      handle.dispose();
    });

    testWidgets('an icon-only destination keeps its name', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, width: 700, uid: 'user-1');

      final discover = find.bySemanticsLabel('Discover');
      expect(discover, findsOneWidget);
      expect(
        _a11y(tester, discover).flagsCollection.isSelected,
        Tristate.isFalse,
      );
      handle.dispose();
    });

    for (final width in <double>[700, 1400]) {
      testWidgets('the brand is a labelled button at ${width}px', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await _pump(tester, width: width);

        final brand = find.bySemanticsLabel('Secret Sauce — Discover');
        expect(brand, findsOneWidget);
        final data = _a11y(tester, brand);
        expect(data.flagsCollection.isButton, isTrue);
        expect(data.hasAction(SemanticsAction.tap), isTrue);
        handle.dispose();
      });
    }

    testWidgets('the bare mark at medium has hover text too', (tester) async {
      await _pump(tester, width: 700);
      expect(find.byTooltip('Secret Sauce — Discover'), findsOneWidget);
    });
  });
}
