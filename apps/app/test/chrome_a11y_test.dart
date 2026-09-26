// Phase 37 wave C — the chrome's semantics outside recipe detail (UX-014,
// UX-047, UX-048, UX-051).
//
// None of this is visible in a screenshot, which is why it went missing: a
// heading drawn in a heading's type is still read as body text, a selected
// segment drawn with a fill is still announced as just "button", and a tab
// titled "Secret-Sauce" on every page looks fine until there are four of them.
import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:app/features/chefs/chef_detail_common.dart';
import 'package:app/features/discover/discover_shelf.dart';
import 'package:app/features/legal/legal_document.dart';
import 'package:app/features/legal/legal_screen.dart';
import 'package:app/features/recipe_editor/edit_models.dart';
import 'package:app/features/recipe_editor/ingredients_editor.dart';
import 'package:app/features/recipe_editor/steps_editor.dart';
import 'package:app/routing/app_router.dart';
import 'package:app/routing/app_shell.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _SignedOut implements AuthRepository {
  @override
  String? get currentUserId => null;

  @override
  Future<String?> currentProfileId() async => null;

  @override
  Stream<AuthState> authStateChanges() => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

void _size(WidgetTester tester, double width, [double height = 900]) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

SemanticsData _data(WidgetTester tester, Finder finder) =>
    tester.getSemantics(finder).getSemanticsData();

bool _isHeader(WidgetTester tester, Finder finder) =>
    _data(tester, finder).flagsCollection.isHeader;

Tristate _selected(WidgetTester tester, Finder finder) =>
    _data(tester, finder).flagsCollection.isSelected;

/// Every label `SystemChrome.setApplicationSwitcherDescription` was sent, in
/// order — on the web, that call is what sets `document.title`.
List<String> _recordTitles(WidgetTester tester) {
  final titles = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'SystemChrome.setApplicationSwitcherDescription') {
        titles.add((call.arguments as Map)['label'] as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return titles;
}

/// The real shell over placeholder screens, plus one root-navigator page that
/// titles itself (the legal screen), so a push and a pop can be observed.
Future<GoRouter> _pumpShell(
  WidgetTester tester, {
  required double width,
}) async {
  _size(tester, width);
  final router = GoRouter(
    initialLocation: Routes.discover,
    routes: [
      ShellRoute(
        builder:
            (context, state, child) =>
                AppShell(location: state.matchedLocation, child: child),
        routes: [
          for (final path in [
            Routes.discover,
            Routes.chefs,
            Routes.myRecipes,
            Routes.profile,
          ])
            GoRoute(
              path: path,
              builder: (_, __) => Scaffold(body: Text('page $path')),
            ),
        ],
      ),
      GoRoute(
        path: '/legal/:doc',
        builder:
            (_, state) => LegalScreen(
              doc: LegalDoc.fromSlug(state.pathParameters['doc'])!,
            ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(_SignedOut())],
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

enum _Opt { all, popular, trending }

Widget _pill({
  required _Opt selected,
  required ValueChanged<_Opt> onSelected,
  double textScale = 1.0,
  double width = 360,
}) => MaterialApp(
  theme: AppTheme.light(),
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    // A Column, as on both real pages: the painted segments centre their
    // labels with an `Align`, which fills a *bounded* height, so under a
    // `Center` the pill would stretch to the viewport and every size
    // assertion below would pass for the wrong reason.
    child: Scaffold(
      body: Column(
        children: [
          SizedBox(
            width: width,
            child: ChefPillTabs<_Opt>(
              options: _Opt.values,
              selected: selected,
              labelOf:
                  (o) => switch (o) {
                    _Opt.all => 'All',
                    _Opt.popular => 'Popular',
                    _Opt.trending => 'Trending',
                  },
              onSelected: onSelected,
            ),
          ),
        ],
      ),
    ),
  ),
);

void main() {
  group('tab titles (UX-051)', () {
    for (final width in <double>[390, 1400]) {
      testWidgets('each shell destination names the tab at ${width}px', (
        tester,
      ) async {
        final titles = _recordTitles(tester);
        final router = await _pumpShell(tester, width: width);
        expect(titles.last, 'Discover · Secret Sauce');

        for (final (path, name) in [
          (Routes.chefs, 'Chefs'),
          (Routes.myRecipes, 'My Recipes'),
          (Routes.profile, 'Profile'),
        ]) {
          router.go(path);
          await tester.pumpAndSettle();
          expect(titles.last, '$name · Secret Sauce', reason: path);
        }

        // And it is a `Title` in the tree, not only a platform call.
        expect(
          tester.widgetList<Title>(find.byType(Title)).map((t) => t.title),
          contains('Profile · Secret Sauce'),
        );
      });
    }

    testWidgets('a pushed page titles the tab, and popping it restores the '
        'shell title', (tester) async {
      final titles = _recordTitles(tester);
      final router = await _pumpShell(tester, width: 1400);
      router.go(Routes.chefs);
      await tester.pumpAndSettle();

      unawaited(router.push(Routes.legal('terms')));
      await tester.pumpAndSettle();
      expect(titles.last, '${LegalDoc.terms.title} · Secret Sauce');

      // The shell's title string never changed while it was covered, so a
      // bare `Title` would say nothing here and leave the tab on "Terms".
      router.pop();
      await tester.pumpAndSettle();
      expect(titles.last, 'Chefs · Secret Sauce');
    });
  });

  group('compact NavigationBar', () {
    testWidgets('marks the current destination selected, and only it', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final router = await _pumpShell(tester, width: 390);
      router.go(Routes.chefs);
      await tester.pumpAndSettle();

      Finder dest(String label) => find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      );
      expect(_selected(tester, dest('Chefs')), Tristate.isTrue);
      for (final other in ['Discover', 'My Recipes', 'Profile']) {
        expect(_selected(tester, dest(other)), isNot(Tristate.isTrue));
      }
      handle.dispose();
    });
  });

  group('ChefPillTabs (UX-014 / UX-048)', () {
    testWidgets('announces the selected segment, and only it', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _pill(selected: _Opt.popular, onSelected: (_) {}),
      );

      final popular = find.bySemanticsLabel('Popular');
      expect(popular, findsOneWidget, reason: 'announced once, not twice');
      expect(_selected(tester, popular), Tristate.isTrue);
      expect(_data(tester, popular).flagsCollection.isButton, isTrue);
      expect(_selected(tester, find.bySemanticsLabel('All')), Tristate.isFalse);
      expect(
        _selected(tester, find.bySemanticsLabel('Trending')),
        Tristate.isFalse,
      );
      handle.dispose();
    });

    testWidgets('every segment is a 48px target', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_pill(selected: _Opt.all, onSelected: (_) {}));

      for (final label in ['All', 'Popular', 'Trending']) {
        final rect = tester.getSemantics(find.bySemanticsLabel(label)).rect;
        expect(
          rect.height,
          greaterThanOrEqualTo(kMinInteractiveDimension),
          reason: label,
        );
      }
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('a tap in the margin above the paint still selects', (
      tester,
    ) async {
      final taps = <_Opt>[];
      await tester.pumpWidget(_pill(selected: _Opt.all, onSelected: taps.add));

      final pill = tester.getRect(find.byType(ChefPillTabs<_Opt>));
      final label = tester.getRect(find.text('Trending'));
      // The paint is still the slim pill — the target grew, the look did not.
      expect(label.height, lessThan(pill.height / 2));

      await tester.tapAt(Offset(label.center.dx, pill.top + 2));
      expect(taps, [_Opt.trending]);

      // And a tap on the paint itself still lands, once.
      await tester.tap(find.text('Popular'));
      expect(taps, [_Opt.trending, _Opt.popular]);
    });

    for (final width in <double>[390, 600, 1000, 1440]) {
      for (final scale in <double>[1.0, 2.0]) {
        testWidgets('fits at ${width}px, textScale $scale', (tester) async {
          _size(tester, width);
          await tester.pumpWidget(
            _pill(
              selected: _Opt.trending,
              onSelected: (_) {},
              textScale: scale,
              width: width - 32,
            ),
          );
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('headings (UX-014)', () {
    testWidgets("an empty Discover shelf's heading is a heading", (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final empty = FutureProvider.autoDispose<List<Recipe>>(
        (ref) async => const [],
      );
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: DiscoverShelf(
                index: '01',
                title: 'Under 30',
                subtitle: 'Quick',
                kicker: 'RANKED BY SAVES',
                accent: AppTheme.light().colorScheme.tertiary,
                provider: empty,
                emptyReason: 'Nothing under 30 minutes yet.',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(_isHeader(tester, find.text('UNDER 30')), isTrue);
      // The reason under it is body text, not a second heading.
      expect(
        _isHeader(tester, find.text('Nothing under 30 minutes yet.')),
        isFalse,
      );
      handle.dispose();
    });

    testWidgets('ChefKicker is a heading', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ChefKicker(text: 'Tier ladder')),
        ),
      );
      expect(_isHeader(tester, find.text('TIER LADDER')), isTrue);
      handle.dispose();
    });
  });

  group('icon buttons have names (UX-047)', () {
    testWidgets('the ingredient group delete', (tester) async {
      final groups = [EditIngredientGroup(), EditIngredientGroup()];
      addTearDown(() {
        for (final g in groups) {
          g.dispose();
        }
      });
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: IngredientsEditor(groups: groups, onChanged: () {}),
              ),
            ),
          ),
        ),
      );
      expect(find.byTooltip('Remove group'), findsNWidgets(2));
    });

    testWidgets('the step section delete', (tester) async {
      final groups = [EditStepGroup(), EditStepGroup()];
      addTearDown(() {
        for (final g in groups) {
          g.dispose();
        }
      });
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: StepsEditor(
                  groups: groups,
                  onChanged: () {},
                  onPickImage: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byTooltip('Remove section'), findsNWidgets(2));
    });
  });
}
