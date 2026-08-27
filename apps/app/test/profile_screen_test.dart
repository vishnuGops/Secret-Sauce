// `/profile` had no test at all (32e1) — the only screen with a sign-out button
// on it, and the one place a wrong branch strands someone on a page the router
// then bounces to `/auth`.
//
// Driven through the real router and the real providers: the overrides swap the
// two **repositories**, so `myProfileProvider`'s own wiring (it watches
// `currentUserIdProvider`, which watches the auth stream) is exercised rather
// than stubbed out — the same choice `recipe_detail_test.dart` makes.
import 'dart:async';

import 'package:app/features/profile/profile_screen.dart';
import 'package:app/routing/app_router.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FakeAuth implements AuthRepository {
  _FakeAuth(this.uid);

  String? uid;
  int signOuts = 0;

  @override
  String? get currentUserId => uid;

  @override
  Stream<AuthState> authStateChanges() => const Stream.empty();

  @override
  Future<void> signOut() async {
    signOuts++;
    uid = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

class _FakeProfiles implements ProfileRepository {
  _FakeProfiles({this.profile, this.error, this.hang = false});

  final Profile? profile;
  final Object? error;

  /// Never completes — the loading state has to be reachable without a race.
  final bool hang;

  @override
  Future<Profile?> getById(String id) {
    if (hang) return Completer<Profile?>().future;
    if (error != null) return Future.error(error!);
    return Future.value(profile);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

Future<_FakeAuth> _pump(
  WidgetTester tester, {
  required _FakeProfiles profiles,
  String? uid = 'u1',
}) async {
  final auth = _FakeAuth(uid);
  final router = GoRouter(
    initialLocation: Routes.profile,
    routes: [
      GoRoute(path: Routes.profile, builder: (_, __) => const ProfileScreen()),
      GoRoute(
        path: Routes.discover,
        builder: (_, __) => const Scaffold(body: Text('DISCOVER')),
      ),
      GoRoute(
        path: Routes.auth,
        builder: (_, __) => const Scaffold(body: Text('AUTH SCREEN')),
      ),
      GoRoute(
        path: Routes.newRecipe,
        builder: (_, __) => const Scaffold(body: Text('NEW RECIPE')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        profileRepositoryProvider.overrideWithValue(profiles),
      ],
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ),
  );
  return auth;
}

void main() {
  testWidgets('shows a spinner while the profile is loading', (tester) async {
    await _pump(tester, profiles: _FakeProfiles(hang: true));
    await tester.pump();

    expect(find.byType(LoadingView), findsOneWidget);
    expect(find.text('Sign out'), findsNothing);
  });

  testWidgets('a failed read is an ErrorView, not an empty profile', (
    tester,
  ) async {
    await _pump(tester, profiles: _FakeProfiles(error: Exception('offline')));
    await tester.pumpAndSettle();

    expect(find.byType(ErrorView), findsOneWidget);
    // `friendlyError` is the only thing that renders a raw exception (OPT-A4),
    // so the screen must not be printing the object.
    expect(find.textContaining('Exception:'), findsNothing);
  });

  testWidgets('renders the profile it loaded', (tester) async {
    await _pump(
      tester,
      profiles: _FakeProfiles(
        profile: const Profile(
          id: 'u1',
          displayName: 'Amara Baptiste',
          bio: 'Sunday cook, weekday improviser.',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Amara Baptiste'), findsOneWidget);
    expect(find.text('Sunday cook, weekday improviser.'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
  });

  testWidgets('with no avatar it falls back to the first initial', (
    tester,
  ) async {
    await _pump(
      tester,
      profiles: _FakeProfiles(
        profile: const Profile(id: 'u1', displayName: 'amara'),
      ),
    );
    await tester.pumpAndSettle();

    // No seeded or simulated profile carries an `avatar_url` (a standing BL-5
    // limit), so this branch is the one every real render takes.
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('an unnamed cook still gets a name and a letter', (tester) async {
    await _pump(
      tester,
      profiles: _FakeProfiles(profile: const Profile(id: 'u1')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unnamed cook'), findsOneWidget);
    expect(find.text('?'), findsOneWidget);
  });

  testWidgets('signed out, it offers the way in rather than an empty page', (
    tester,
  ) async {
    await _pump(tester, profiles: _FakeProfiles(), uid: null);
    await tester.pumpAndSettle();

    expect(find.text('Not signed in'), findsOneWidget);
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('AUTH SCREEN'), findsOneWidget);
  });

  testWidgets('sign out lands on /discover, not on `/`', (tester) async {
    final auth = await _pump(
      tester,
      profiles: _FakeProfiles(
        profile: const Profile(id: 'u1', displayName: 'Amara'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(auth.signOuts, 1);
    // Staying on `/profile` would leave the redirect to bounce them to `/auth`,
    // and `/` is a redirect-only route with no screen behind it (the retired
    // home page) — Discover is the front door.
    expect(find.text('DISCOVER'), findsOneWidget);
  });

  testWidgets('New recipe goes to the editor', (tester) async {
    await _pump(
      tester,
      profiles: _FakeProfiles(
        profile: const Profile(id: 'u1', displayName: 'Amara'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('New recipe'));
    await tester.pumpAndSettle();

    expect(find.text('NEW RECIPE'), findsOneWidget);
  });
}
