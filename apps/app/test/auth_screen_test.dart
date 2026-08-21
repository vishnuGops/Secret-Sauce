// OPT-T3's last gap: the auth screen had no test at all, on the one path where
// a wrong branch means someone cannot get into the app.
//
// Driven through the **real router**, because half of what matters here is the
// wiring: `?mode=signup` has to open the sign-up side (the top bar offers both
// doors and they must not land on the same one), and a successful submit has to
// leave the screen — `_submit` calls `context.canPop()`, which asserts without a
// GoRouter in the tree, so a test that pumps the widget bare cannot see that
// path at all.
import 'package:app/features/auth/auth_screen.dart';
import 'package:app/routing/app_router.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
// Directly, not through core's barrel: the barrel re-exports only the two auth
// *types* the UI renders, and this test needs the exception the repository
// throws.
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

class _FakeAuth implements AuthRepository {
  _FakeAuth({this.failWith});

  final Object? failWith;
  final List<String> calls = [];

  @override
  String? get currentUserId => null;

  @override
  Stream<AuthState> authStateChanges() => const Stream.empty();

  @override
  Future<void> signIn({required String email, required String password}) async {
    calls.add('signIn:$email');
    if (failWith != null) throw failWith!;
  }

  @override
  Future<void> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    calls.add('signUp:$email:$displayName');
    if (failWith != null) throw failWith!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

/// Discover is where a successful submit lands, so it has to resolve — with
/// nothing in it, since this test is about the door, not the room.
class _FakeDiscover implements DiscoverRepository {
  @override
  Future<List<Recipe>> popular({int limit = kRecipePageSize, int offset = 0}) async =>
      const [];

  @override
  Future<List<Recipe>> trending({int limit = kRecipePageSize, int offset = 0}) async =>
      const [];

  @override
  Future<List<Recipe>> recent({int limit = kRecipePageSize, int offset = 0}) async =>
      const [];

  @override
  Future<List<Recipe>> search(
    String query, {
    int limit = kRecipePageSize,
    int offset = 0,
  }) async =>
      const [];
}

Future<GoRouter> _pumpAt(
  WidgetTester tester,
  String location,
  _FakeAuth auth,
) async {
  tester.view.physicalSize = const Size(1000, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(auth),
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

Future<void> _fill(
  WidgetTester tester, {
  required String email,
  required String password,
  String? name,
}) async {
  if (name != null) {
    await tester.enterText(find.widgetWithText(TextFormField, 'Display name'), name);
  }
  await tester.enterText(find.widgetWithText(TextFormField, 'Email'), email);
  await tester.enterText(find.widgetWithText(TextFormField, 'Password'), password);
}

void main() {
  testWidgets('/auth opens the sign-in side', (tester) async {
    await _pumpAt(tester, Routes.auth, _FakeAuth());

    expect(find.byType(AuthScreen), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Display name'), findsNothing);
  });

  testWidgets('/auth?mode=signup opens the sign-up side', (tester) async {
    await _pumpAt(tester, Routes.signUp, _FakeAuth());

    expect(find.text('Create your account'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Display name'), findsOneWidget);
  });

  testWidgets('the toggle switches sides after the initial mode', (tester) async {
    await _pumpAt(tester, Routes.auth, _FakeAuth());

    await tester.tap(find.text("Don't have an account? Sign up"));
    await tester.pumpAndSettle();

    expect(find.text('Create your account'), findsOneWidget);
  });

  testWidgets('an invalid form never reaches the repository', (tester) async {
    final auth = _FakeAuth();
    await _pumpAt(tester, Routes.auth, auth);

    await _fill(tester, email: 'not-an-email', password: 'short');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(auth.calls, isEmpty);
    expect(find.text('Enter a valid email'), findsOneWidget);
    expect(find.text('Min 6 characters'), findsOneWidget);
  });

  testWidgets('a valid sign-up sends the display name and leaves the screen',
      (tester) async {
    final auth = _FakeAuth();
    final router = await _pumpAt(tester, Routes.signUp, auth);

    await _fill(
      tester,
      email: 'cook@example.test',
      password: 'good-password',
      name: 'Dara',
    );
    await tester.tap(find.text('Sign up'));
    await tester.pumpAndSettle();

    expect(auth.calls, ['signUp:cook@example.test:Dara']);
    expect(_location(router), Routes.discover);
  });

  testWidgets('a rejected sign-in shows the mapped message and stays put',
      (tester) async {
    final auth = _FakeAuth(failWith: const AuthException('Invalid login credentials'));
    final router = await _pumpAt(tester, Routes.auth, auth);

    await _fill(tester, email: 'cook@example.test', password: 'good-password');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Invalid login credentials'), findsOneWidget);
    expect(find.textContaining('AuthException'), findsNothing);
    expect(_location(router), Routes.auth, reason: 'a failed sign-in navigated');
  });
}
