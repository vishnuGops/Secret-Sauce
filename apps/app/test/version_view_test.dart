// Version history rows open a read-only view of that version (UX-052).
//
// The rows used to be inert: the sheet said version 3 existed and gave no way
// to see it. A row now opens `VersionView`, which fetches that ONE row's
// snapshot through `RecipeRepository.versionContent` — never through
// `versions()`, whose select leaves `content_snapshot` out on purpose (B065).
//
// The repository is swapped at `recipeRepositoryProvider`, so the wiring in
// recipe_detail_providers.dart (`versionContentProvider`) is exercised rather
// than stubbed out — the same seam recipe_detail_test.dart uses.
import 'package:app/features/recipe_detail/version_history_sheet.dart';
import 'package:app/features/recipe_detail/version_view.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _versions = [
  RecipeVersion(
    id: 'v2',
    recipeId: 'r1',
    versionNumber: 2,
    authorId: 'me',
    changeSummary: 'More lemon, less salt',
    createdAt: DateTime.utc(2026, 9, 20),
  ),
  RecipeVersion(
    id: 'v1',
    recipeId: 'r1',
    versionNumber: 1,
    authorId: 'me',
    createdAt: DateTime.utc(2025, 3, 4),
  ),
];

const _flour = Ingredient(
  id: 'i1',
  groupId: 'ig1',
  quantity: 1.25,
  unit: 'cup',
  name: 'wheat flour',
);

/// What version 2 looked like — deliberately not the live recipe's title, so
/// the view is visibly showing the snapshot.
const _snapshot = Recipe(
  id: 'r1',
  ownerId: 'me',
  title: 'Lemon Tart, the 2026 version',
  ingredientGroups: [
    IngredientGroup(
      id: 'ig1',
      recipeId: 'r1',
      name: 'Crust',
      ingredients: [_flour],
    ),
  ],
  stepGroups: [
    StepGroup(
      id: 'sg1',
      recipeId: 'r1',
      name: 'Crust',
      steps: [
        RecipeStep(id: 's1', groupId: 'sg1', text: 'Rub in the butter.'),
        RecipeStep(
          id: 's2',
          groupId: 'sg1',
          text: 'Chill the dough.',
          durationMinutes: 90,
        ),
      ],
    ),
    StepGroup(
      id: 'sg2',
      recipeId: 'r1',
      name: 'Filling',
      steps: [RecipeStep(id: 's3', groupId: 'sg2', text: 'Whisk the eggs.')],
    ),
  ],
);

class _FakeRecipes implements RecipeRepository {
  /// Every id `versionContent` was asked for, in order.
  final requested = <String>[];

  /// Thrown by the next `versionContent` call, then cleared.
  Object? failNext;

  @override
  Future<List<RecipeVersion>> versions(String recipeId) async => _versions;

  @override
  Future<Recipe?> versionContent(String versionId) async {
    requested.add(versionId);
    final error = failNext;
    if (error != null) {
      failNext = null;
      throw error;
    }
    // v2 has a snapshot; v1 is `{}`, like every seeded version.
    return versionId == 'v2' ? _snapshot : null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

Widget _app(_FakeRecipes repo, {double textScale = 1.0}) => ProviderScope(
  overrides: [recipeRepositoryProvider.overrideWithValue(repo)],
  child: MaterialApp(
    theme: AppTheme.light(),
    builder:
        (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
    home: Scaffold(
      body: Builder(
        builder:
            (context) => Center(
              child: FilledButton(
                onPressed: () => VersionHistorySheet.show(context, _versions),
                child: const Text('History'),
              ),
            ),
      ),
    ),
  ),
);

void _size(WidgetTester tester, double width, {double height = 1000}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _tapRow(WidgetTester tester, int number) async {
  final row = find.bySemanticsLabel(RegExp('^Open version $number'));
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  await tester.tap(row);
  await tester.pumpAndSettle();
}

Future<void> _openVersion(WidgetTester tester, int number) async {
  await tester.tap(find.text('History'));
  await tester.pumpAndSettle();
  await _tapRow(tester, number);
}

void main() {
  testWidgets('each row is a named button of at least 48dp', (tester) async {
    _size(tester, 390);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(_FakeRecipes()));
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    for (final n in [2, 1]) {
      final row = find.bySemanticsLabel(RegExp('^Open version $n'));
      expect(row, findsOneWidget);
      expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
    }
    handle.dispose();
  });

  testWidgets('a row opens that version, read-only', (tester) async {
    _size(tester, 390);
    final repo = _FakeRecipes();
    await tester.pumpWidget(_app(repo));
    await _openVersion(tester, 2);

    expect(find.byType(VersionView), findsOneWidget);
    // Only the tapped row's snapshot was fetched.
    expect(repo.requested, ['v2']);

    expect(find.text('Version 2'), findsOneWidget);
    expect(find.text('2026-09-20 · More lemon, less salt'), findsOneWidget);
    expect(find.text('Lemon Tart, the 2026 version'), findsOneWidget);
    // Through core's one quantity chain, never a second formatter (B066).
    expect(find.text(ingredientOneLine(_flour)), findsOneWidget);
    expect(find.text('Rub in the butter.'), findsOneWidget);
    expect(find.text('1 h 30 min'), findsOneWidget);
    // Numbered per group: both groups start at 1.
    expect(find.text('1.'), findsNWidgets(2));
    expect(find.text('2.'), findsOneWidget);
    // Read-only: nothing to tick off.
    expect(find.byType(Checkbox), findsNothing);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(VersionView), findsNothing);
    // Back on the history list.
    expect(find.text('More lemon, less salt'), findsOneWidget);
  });

  testWidgets('a version with no stored copy says so honestly', (tester) async {
    _size(tester, 390);
    final repo = _FakeRecipes();
    await tester.pumpWidget(_app(repo));
    await _openVersion(tester, 1);

    expect(repo.requested, ['v1']);
    expect(
      find.descendant(
        of: find.byType(VersionView),
        matching: find.text('Version 1'),
      ),
      findsOneWidget,
    );
    expect(find.text('Nothing saved for this version'), findsOneWidget);
    expect(find.textContaining('No copy of this version was kept'), findsOne);
  });

  testWidgets('a failed load shows a friendly error with Retry', (
    tester,
  ) async {
    _size(tester, 1000);
    final repo = _FakeRecipes()..failNext = Exception('socket closed');
    await tester.pumpWidget(_app(repo));
    await _openVersion(tester, 2);

    expect(find.byType(ErrorView), findsOneWidget);
    expect(find.textContaining('socket closed'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(repo.requested, ['v2', 'v2']);
    expect(find.text('Lemon Tart, the 2026 version'), findsOneWidget);
  });

  group('envelope', () {
    for (final width in [390.0, 1000.0, 1440.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('no overflow at ${width.toInt()}px @ ${scale}x', (
          tester,
        ) async {
          _size(tester, width, height: 900);
          final repo = _FakeRecipes();
          await tester.pumpWidget(_app(repo, textScale: scale));

          await tester.tap(find.text('History'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'history sheet');

          await _tapRow(tester, 2);
          expect(find.byType(VersionView), findsOneWidget);
          expect(tester.takeException(), isNull, reason: 'snapshot');

          await tester.tap(find.byTooltip('Close'));
          await tester.pumpAndSettle();
          await _tapRow(tester, 1);
          expect(tester.takeException(), isNull, reason: 'empty state');
        });
      }
    }
  });
}
