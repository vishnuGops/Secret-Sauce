import 'package:app/features/my_recipes/my_recipes_providers.dart';
import 'package:app/features/my_recipes/my_recipes_screen.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// `MyRecipesScreen`: the header the `New recipe` button moved onto (Phase 21)
/// and the two grids under it, whose per-tab flags are the screen's only other
/// wiring.
///
/// Both tabs are paged notifiers (OPT-P9), so the override supplies a page
/// rather than a future: `fetchPage` is the one seam, and stubbing it keeps the
/// repository (and any Supabase client) out of a chrome test entirely.
class _EmptyMine extends MyRecipesNotifier {
  @override
  Future<List<Recipe>> fetchPage({required int limit, required int offset}) =>
      Future.value(const []);
}

class _EmptyShared extends SharedWithMeNotifier {
  @override
  Future<List<Recipe>> fetchPage({required int limit, required int offset}) =>
      Future.value(const []);
}

/// A recipe with its owner embedded — the badge renders only when there is one,
/// so a card with no `owner` would pass a `showChef: false` assertion for the
/// wrong reason.
const _owned = Recipe(
  id: 'r1',
  ownerId: 'd1',
  title: 'Suya-Spiced Lamb Skewers',
  // Explicit, not defaulted: the visibility-pill assertion below reads this
  // value, and a model default is not a contract this suite gets to lean on.
  visibility: RecipeVisibility.private,
  owner: Profile(
    id: 'd1',
    displayName: 'Amara Baptiste',
    chefTier: ChefTier.masterChef,
  ),
);

class _OneMine extends MyRecipesNotifier {
  @override
  Future<List<Recipe>> fetchPage({required int limit, required int offset}) =>
      Future.value(offset == 0 ? const [_owned] : const []);
}

class _OneShared extends SharedWithMeNotifier {
  @override
  Future<List<Recipe>> fetchPage({required int limit, required int offset}) =>
      Future.value(offset == 0 ? const [_owned] : const []);
}

/// `New recipe` moved off the web top navigation and onto this page (Phase 21).
/// On web it sits in an in-content header — the page no longer stacks its own
/// `AppBar` under the shell's top bar — and on compact in the `AppBar`, which
/// is the only top chrome a phone has. The web header is content-sized, so text
/// scale grows it rather than clamping a 68px button into a 56px toolbar the
/// way the old web `AppBar` did; the envelope below keeps both chromes honest.
Future<void> _pump(
  WidgetTester tester, {
  required double width,
  double textScale = 1.0,
  bool populated = false,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // Empty by default: the chrome tests do not need cards, and the grid
        // has its own suite.
        myRecipesProvider.overrideWith(
          populated ? _OneMine.new : _EmptyMine.new,
        ),
        sharedWithMeProvider.overrideWith(
          populated ? _OneShared.new : _EmptyShared.new,
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 900),
            textScaler: TextScaler.linear(textScale),
          ),
          child: const MyRecipesScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Header only — the empty state under it has its own labelled `New recipe`
/// button, so an unscoped finder matches either one.
final _headerLabel = find.descendant(
  of: find.byKey(MyRecipesScreen.newRecipeButtonKey),
  matching: find.text('New recipe'),
);

void main() {
  testWidgets('web header carries the labelled New recipe button', (
    tester,
  ) async {
    await _pump(tester, width: 1400);

    expect(_headerLabel, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // Phase 21's carried-over item: on web the shell's top bar is already a
  // toolbar over this page, and a second one under it was two bars of chrome
  // before the first card.
  testWidgets('web stacks no AppBar under the shell top bar', (tester) async {
    await _pump(tester, width: 1400);

    expect(find.byType(AppBar), findsNothing);
    // The page still titles itself — in content, not in a toolbar — and the
    // tab strip survived the move. `My Recipes` is both the title and a tab.
    expect(find.text('My Recipes'), findsNWidgets(2));
    expect(find.byType(TabBar), findsOneWidget);
    expect(find.text('Shared with me'), findsOneWidget);
  });

  testWidgets('compact keeps its AppBar — a phone has no other top bar', (
    tester,
  ) async {
    await _pump(tester, width: 390);

    expect(find.byType(AppBar), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('My Recipes'),
      ),
      findsNWidgets(2), // title + first tab
    );
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.byType(TabBar)),
      findsOneWidget,
    );
  });

  testWidgets('compact keeps the icon — the FAB is the labelled action there', (
    tester,
  ) async {
    await _pump(tester, width: 390);

    expect(_headerLabel, findsNothing);
    expect(find.byTooltip('New recipe'), findsOneWidget);
  });

  // The header lines up with the grid's first card, not with the window —
  // pumped on a 4K window, past the six-column cap (B049), where the capped
  // block keeps its left edge and puts the slack on the right.
  testWidgets('web header aligns with the first card on a 4K window', (
    tester,
  ) async {
    await _pump(tester, width: 3840, populated: true);

    final card = tester.getRect(find.byType(RecipeCard).first);
    final title = tester.getRect(find.text('My Recipes').first);
    expect(title.left, closeTo(card.left, 0.001));
  });

  testWidgets('2.0x text scale keeps the label and does not overflow', (
    tester,
  ) async {
    await _pump(tester, width: 1400, textScale: 2.0);

    expect(_headerLabel, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // Phase 18 left this as "the widget flag is tested, the screen wiring is
  // not" — `RecipeCard(showChef: false)` had a test, the screen passing it did
  // not, and the two tabs disagree on purpose. Both flags fail *silently*: a
  // wrong `showChef` draws a badge nobody notices, a missing `showVisibility`
  // hides the private pill on the one surface that needs it.
  group('per-tab card flags', () {
    testWidgets('My Recipes: no chef badge, but the visibility pill', (
      tester,
    ) async {
      await _pump(tester, width: 1400, populated: true);

      // Every card here is mine, so naming me on each one is noise — and the
      // pill needs the cover space the badge would take.
      expect(find.byType(ChefBadge), findsNothing);
      expect(find.byTooltip('Private'), findsOneWidget);
    });

    testWidgets('Shared with me: the chef badge, no visibility pill', (
      tester,
    ) async {
      await _pump(tester, width: 1400, populated: true);

      await tester.tap(find.text('Shared with me'));
      await tester.pumpAndSettle();

      // Someone else's recipe, so who shared it is the point.
      expect(find.byType(ChefBadge), findsOneWidget);
      expect(find.text('Amara Baptiste'), findsOneWidget);
      expect(find.byTooltip('Private'), findsNothing);
    });
  });

  for (final (width, scale) in <(double, double)>[
    (600, 1.0),
    (700, 1.3),
    (1000, 2.0),
    (1400, 2.0),
    // Compact's AppBar, and web's header where the title and the button stop
    // sharing a line.
    (390, 1.0),
    (390, 2.0),
    (600, 2.0),
    (3840, 1.0),
  ]) {
    testWidgets('header fits at ${width}px, textScale $scale', (tester) async {
      await _pump(tester, width: width, textScale: scale);
      expect(
        tester.takeException(),
        isNull,
        reason: 'overflow at ${width}px @ ${scale}x',
      );
    });
  }
}
