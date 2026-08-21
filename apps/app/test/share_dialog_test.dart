// OPT-A5: `display_name` is not unique. The old dialog took one text field,
// looked up an exact `ilike` with `limit(1)`, and shared with whichever row the
// database returned first — so "share with Dara" could hand your private recipe
// to the wrong Dara and report success.
//
// What these tests pin is the decision, not the layout: with more than one
// match the dialog must not write anything until a person is chosen.
import 'package:app/widgets/share_dialog.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _daraOne = Profile(
  id: 'dara-1',
  displayName: 'Dara Okonkwo',
  chefTier: ChefTier.sousChef,
);
const _daraTwo = Profile(
  id: 'dara-2',
  displayName: 'Dara Okonkwo',
  chefTier: ChefTier.lineCook,
);

class _FakeProfiles implements ProfileRepository {
  _FakeProfiles(this.results);

  final List<Profile> results;
  final List<String> queries = [];

  @override
  Future<List<Profile>> searchByName(String query, {int limit = 10}) async {
    queries.add(query);
    return results;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

class _RecordingRecipes implements RecipeRepository {
  final List<({String recipeId, String userId})> shares = [];

  @override
  Future<void> share({
    required String recipeId,
    required String userId,
    SharePermission permission = SharePermission.view,
  }) async {
    shares.add((recipeId: recipeId, userId: userId));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

Future<void> _pump(
  WidgetTester tester, {
  required _FakeProfiles profiles,
  required _RecordingRecipes recipes,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        profileRepositoryProvider.overrideWithValue(profiles),
        recipeRepositoryProvider.overrideWithValue(recipes),
        // Signed in as someone who is not in the results.
        currentUserIdProvider.overrideWithValue('me'),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: ShareDialog(recipeId: 'r1')),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Types a query and waits out the dialog's 300 ms debounce.
Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('two people with the same name are both offered', (tester) async {
    final profiles = _FakeProfiles([_daraOne, _daraTwo]);
    final recipes = _RecordingRecipes();
    await _pump(tester, profiles: profiles, recipes: recipes);

    await _search(tester, 'Dara');

    expect(find.byType(RadioListTile<String>), findsNWidgets(2));
    // The tier is what tells them apart.
    expect(find.text(ChefTier.sousChef.label), findsOneWidget);
    expect(find.text(ChefTier.lineCook.label), findsOneWidget);
  });

  testWidgets('Share stays disabled until one of them is picked',
      (tester) async {
    final profiles = _FakeProfiles([_daraOne, _daraTwo]);
    final recipes = _RecordingRecipes();
    await _pump(tester, profiles: profiles, recipes: recipes);
    await _search(tester, 'Dara');

    final share = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(share.onPressed, isNull, reason: 'ambiguous share was possible');

    await tester.tap(find.text(ChefTier.lineCook.label));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();

    expect(recipes.shares, [(recipeId: 'r1', userId: 'dara-2')]);
  });

  testWidgets('a single match is selected for you', (tester) async {
    final profiles = _FakeProfiles([_daraOne]);
    final recipes = _RecordingRecipes();
    await _pump(tester, profiles: profiles, recipes: recipes);
    await _search(tester, 'Dara O');

    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();

    expect(recipes.shares, [(recipeId: 'r1', userId: 'dara-1')]);
  });

  testWidgets('typing does not search until the pause', (tester) async {
    final profiles = _FakeProfiles([_daraOne]);
    final recipes = _RecordingRecipes();
    await _pump(tester, profiles: profiles, recipes: recipes);

    for (final q in ['D', 'Da', 'Dar', 'Dara']) {
      await tester.enterText(find.byType(TextField), q);
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(profiles.queries, isEmpty);

    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(profiles.queries, ['Dara']);
  });

  testWidgets('changing the query drops the previous selection',
      (tester) async {
    final profiles = _FakeProfiles([_daraOne]);
    final recipes = _RecordingRecipes();
    await _pump(tester, profiles: profiles, recipes: recipes);
    await _search(tester, 'Dara');

    // Selected by the single-match rule above; a new query must clear it, or
    // Share would write to someone who is no longer on screen.
    await tester.enterText(find.byType(TextField), 'Wei');
    await tester.pump();

    final share = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(share.onPressed, isNull);
  });

  testWidgets('you are never offered yourself', (tester) async {
    const me = Profile(id: 'me', displayName: 'Dara Okonkwo');
    final profiles = _FakeProfiles([me, _daraOne]);
    final recipes = _RecordingRecipes();
    await _pump(tester, profiles: profiles, recipes: recipes);

    await _search(tester, 'Dara');

    expect(find.byType(RadioListTile<String>), findsOneWidget);
  });
}
