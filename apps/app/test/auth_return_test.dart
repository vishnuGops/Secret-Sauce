// UX-017: `?from=` carries a signed-out visitor back to where they were after
// signing in. It is attacker-controllable — anyone can mail a link to
// `/auth?from=…` — so these pin the one property that matters: nothing but a
// same-app path ever survives `safeReturnPath`.
import 'dart:async';

import 'package:app/routing/app_router.dart';
import 'package:app/routing/auth_return.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  group('safeReturnPath', () {
    test('keeps an in-app path, query and all', () {
      expect(safeReturnPath('/recipe/r1'), '/recipe/r1');
      expect(safeReturnPath('/discover?q=soup'), '/discover?q=soup');
      expect(safeReturnPath('/chef/abc?x=1#top'), '/chef/abc?x=1#top');
    });

    test('refuses anything that could leave the app', () {
      for (final raw in [
        'https://evil.test/',
        'http://evil.test',
        '//evil.test/recipe',
        r'/\evil.test',
        r'/recipe\..\evil',
        'javascript:alert(1)',
        'evil.test/recipe',
        'recipe/r1',
        '/recipe/r1\n',
        '',
        null,
      ]) {
        expect(safeReturnPath(raw), isNull, reason: '$raw');
      }
    });

    test('refuses /auth itself, which would loop', () {
      expect(safeReturnPath(Routes.auth), isNull);
      expect(safeReturnPath('${Routes.auth}?from=/x'), isNull);
    });
  });

  group('authLocation', () {
    test('carries a safe from', () {
      final uri = Uri.parse(authLocation(from: '/recipe/r1'));
      expect(uri.path, Routes.auth);
      expect(uri.queryParameters[kAuthFromParam], '/recipe/r1');
    });

    test('drops an unsafe from rather than passing it on', () {
      expect(authLocation(from: 'https://evil.test'), Routes.auth);
    });

    test('opens the sign-up side on request', () {
      final uri = Uri.parse(authLocation(from: '/my', signUp: true));
      expect(uri.queryParameters['mode'], 'signup');
      expect(uri.queryParameters[kAuthFromParam], '/my');
    });
  });

  // Phase 37 review: a recipe opened with `push` (every card does) left
  // `currentConfiguration.uri` on the page underneath, so `from=` pointed back
  // at Discover instead of the recipe the visitor tried to like.
  testWidgets('goToSignIn records a pushed page, not the one under it', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: Routes.discover,
      routes: [
        GoRoute(
          path: Routes.discover,
          builder: (_, __) => const Scaffold(body: Text('DISCOVER')),
        ),
        GoRoute(
          path: Routes.recipePattern,
          builder:
              (context, _) => Scaffold(
                body: TextButton(
                  onPressed: () => goToSignIn(context),
                  child: const Text('LIKE'),
                ),
              ),
        ),
        GoRoute(
          path: Routes.auth,
          builder: (_, __) => const Scaffold(body: Text('AUTH')),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    unawaited(router.push(Routes.recipe('r1')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('LIKE'));
    await tester.pumpAndSettle();

    final uri = router.routerDelegate.currentConfiguration.uri;
    expect(uri.path, Routes.auth);
    expect(uri.queryParameters[kAuthFromParam], '/recipe/r1');
  });
}
