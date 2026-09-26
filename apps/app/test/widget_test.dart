import 'dart:async';

import 'package:app/features/discover/discover_screen.dart';
import 'package:app/routing/app_router.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// `/` is no longer a page. The landing screen was retired and root is now a
/// redirect-only route onto `/discover`, which is the front door on both
/// chromes.
///
/// This used to be the HomeScreen widget test. It guards the replacement
/// instead, because the failure mode is silent: drop the root route and web
/// visitors hitting the bare origin get go_router's error page, while a
/// `builder` accidentally added back would resurrect a screen nothing links to.
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

/// Empty results are enough: this asserts where the router lands, not what
/// Discover renders. The screen falls back to its [EmptyView].
class _FakeDiscover implements DiscoverRepository {
  // Phase 35c: the corpus surface. Empty in every fixture here — these tests are
  // about Discover and the ranked shelves, which exclude imported content by
  // construction.
  @override
  Future<List<Recipe>> corpus({
    int limit = kRecipePageSize,
    int offset = 0,
    String? cuisine,
  }) async => const [];

  @override
  Future<int> corpusCount() async => 0;

  @override
  Future<List<Recipe>> popular({
    int limit = kRecipePageSize,
    int offset = 0,
  }) async => const [];

  @override
  Future<List<Recipe>> trending({
    int limit = kRecipePageSize,
    int offset = 0,
  }) async => const [];

  @override
  Future<List<Recipe>> recent({
    int limit = kRecipePageSize,
    int offset = 0,
  }) async => const [];

  // Phase 36c: the category filter. Empty, like every other read here.
  @override
  Future<List<Recipe>> byCategories(
    List<String> categories, {
    int limit = kRecipePageSize,
    int offset = 0,
  }) async => const [];

  @override
  Future<List<Recipe>> search(
    String query, {
    int limit = kRecipePageSize,
    int offset = 0,
  }) async => const [];

  @override
  Future<List<Recipe>> quick({
    int limit = kRecipePageSize,
    int offset = 0,
  }) async => const [];

  @override
  Future<List<Recipe>> projects({
    int limit = kRecipePageSize,
    int offset = 0,
  }) async => const [];

  @override
  Future<List<Recipe>> mostForked({
    int limit = kRecipePageSize,
    int offset = 0,
  }) async => const [];

  @override
  Future<int> publicCount() async => 0;
}

Future<GoRouter> _pumpAt(
  WidgetTester tester,
  String location, {
  String? uid,
}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(_FakeAuth(uid)),
      discoverRepositoryProvider.overrideWithValue(_FakeDiscover()),
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
  testWidgets('/ forwards a signed-out visitor to /discover', (tester) async {
    final router = await _pumpAt(tester, Routes.root);

    expect(_location(router), Routes.discover);
    expect(find.byType(DiscoverScreen), findsOneWidget);
  });

  testWidgets('/ forwards a signed-in visitor to /discover', (tester) async {
    final router = await _pumpAt(tester, Routes.root, uid: 'user-1');

    expect(_location(router), Routes.discover);
    expect(find.byType(DiscoverScreen), findsOneWidget);
  });

  testWidgets('the root landing is gone — / renders no page of its own', (
    tester,
  ) async {
    await _pumpAt(tester, Routes.root);

    // The retired landing's copy. Its absence is the assertion: a builder put
    // back on the root route would show it again and this would fail.
    expect(find.text('Your family recipe vault.'), findsNothing);
    // Discover sits inside the ShellRoute, so the nav chrome came with it.
    expect(find.text('Discover'), findsWidgets);
  });
}
