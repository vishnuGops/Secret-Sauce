// Phase 35a's recipe-detail attribution block, on both detail layouts.
//
// The rights position the app states — show the functional part of a recipe,
// link everything expressive, never re-host a photograph — only holds while the
// credit and the link travel with the content. So the properties worth pinning
// are not the pixels but the statements: who wrote it, who published it, where
// the original is, and on what terms it is shown here. And, just as much, that
// a member's own recipe carries none of it: a second credit line under an owner
// badge reads as a second author.
//
// Widths straddle the layout branch on purpose — 390 and 600 render
// `RecipeDetailCompact`, 1000 and 1440 `RecipeDetailExpanded` — so every group
// below proves both call sites (Gotcha 26: a second caller re-opens a widget's
// envelope, it does not inherit the first one's proof).
import 'package:app/features/recipe_detail/detail_provenance.dart';
import 'package:app/features/recipe_detail/recipe_detail_compact.dart';
import 'package:app/features/recipe_detail/recipe_detail_expanded.dart';
import 'package:app/features/recipe_detail/recipe_detail_screen.dart';
import 'package:app/routing/app_router.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/link.dart';

const _steps = [
  StepGroup(
    id: 'sg1',
    recipeId: 'r1',
    steps: [RecipeStep(id: 's1', groupId: 'sg1', text: 'Bread and fry.')],
  ),
];

const _ingredients = [
  IngredientGroup(
    id: 'g1',
    recipeId: 'r1',
    ingredients: [
      Ingredient(id: 'i1', groupId: 'g1', quantity: 2, name: 'chicken breasts'),
    ],
  ),
];

/// Shaped like a real corpus row (`recipes` on the local stack): an imported
/// byline as owner, a publisher that is an entity, an https source.
const _imported = Recipe(
  id: 'r1',
  ownerId: 'chef-1',
  title: 'Crispy Chicken Parmesan',
  servings: 4,
  visibility: RecipeVisibility.public,
  ingredientGroups: _ingredients,
  stepGroups: _steps,
  owner: Profile(
    id: 'chef-1',
    displayName: 'Karina Carrel',
    kind: ProfileKind.imported,
  ),
  isImported: true,
  sourceName: 'Cafe Delites',
  sourceUrl: 'https://www.cafedelites.com/crispy-chicken-parmesan/',
  sourceEntityId: 'ent-1',
);

/// The envelope's worst case: the longest `source_name` in the corpus is 46
/// characters and `display_name` is capped at 80, and a real host runs to ~40.
final _longest = _imported.copyWith(
  owner: const Profile(
    id: 'chef-1',
    displayName:
        'Maria-Josefina Albuquerque-Vandenberghe de la Cruz y Montenegro',
    kind: ProfileKind.imported,
  ),
  sourceName: 'The Healthy Seasonal Recipes Kitchen Collective',
  sourceUrl:
      'https://www.healthyseasonalrecipes-and-kitchen-notes.com/creamy-horseradish-potato-salad/',
);

/// A member's own recipe — no provenance at all.
const _member = Recipe(
  id: 'r1',
  ownerId: 'm1',
  title: 'Grandma’s Sunday Sauce',
  servings: 4,
  visibility: RecipeVisibility.public,
  ingredientGroups: _ingredients,
  stepGroups: _steps,
  owner: Profile(id: 'm1', displayName: 'Amara Baptiste'),
  attribution: 'From my grandmother, Naples, 1962.',
);

class _FakeAuth implements AuthRepository {
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

class _FakeRecipes implements RecipeRepository {
  _FakeRecipes(this.recipe);

  final Recipe recipe;

  @override
  Future<Recipe> getById(String id) async => recipe;

  @override
  Future<bool> myLiked(String recipeId) async => false;

  @override
  Future<bool> mySaved(String recipeId) async => false;

  @override
  Future<void> logView(String recipeId) async {}

  @override
  Future<double?> myRating(String recipeId) async => null;

  @override
  Future<List<RecipeVersion>> versions(String recipeId) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

Future<void> _pump(
  WidgetTester tester,
  Recipe recipe, {
  double width = 1440,
  double height = 2400,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/recipe/r1',
    routes: [
      GoRoute(
        path: Routes.recipePattern,
        builder:
            (_, state) =>
                RecipeDetailScreen(recipeId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: Routes.chefPattern,
        builder:
            (_, state) =>
                Scaffold(body: Text('CHEF ${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: Routes.entityPattern,
        builder:
            (_, state) =>
                Scaffold(body: Text('ENTITY ${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: Routes.legalPattern,
        builder:
            (_, state) =>
                Scaffold(body: Text('LEGAL ${state.pathParameters['doc']}')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        recipeRepositoryProvider.overrideWithValue(_FakeRecipes(recipe)),
        authRepositoryProvider.overrideWithValue(_FakeAuth()),
      ],
      child: MaterialApp.router(
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

/// One narrow (compact layout) and one wide (expanded layout) width, so each
/// behaviour is asserted on both call sites.
const _layouts = <(String, double)>[('compact', 390), ('expanded', 1440)];

Finder _rich(String text) => find.text(text, findRichText: true);

void main() {
  group('an imported recipe', () {
    for (final (name, width) in _layouts) {
      // B134 / UX-028: the stored difficulty is the importer's default.
      testWidgets('states no difficulty it was never given ($name)', (
        tester,
      ) async {
        await _pump(tester, _imported, width: width);
        expect(find.byType(DifficultyBadge), findsNothing);
        expect(find.text('Medium'), findsNothing);
      });

      testWidgets('credits chef, publisher and the original ($name)', (
        tester,
      ) async {
        await _pump(tester, _imported, width: width);

        // The right layout actually rendered, or this proves one site twice.
        expect(
          find.byType(
            width < 1000 ? RecipeDetailCompact : RecipeDetailExpanded,
          ),
          findsOneWidget,
        );

        expect(find.text('FROM AROUND THE WEB'), findsOneWidget);
        expect(_rich('Recipe by Karina Carrel'), findsOneWidget);
        expect(_rich('Published by Cafe Delites'), findsOneWidget);
        // The link names where it goes, host only, `www.` dropped.
        expect(
          find.text('Read the original on cafedelites.com'),
          findsOneWidget,
        );
        expect(
          find.textContaining('we do not copy their photographs'),
          findsOneWidget,
        );
        expect(find.text('How we credit recipes'), findsOneWidget);

        // A real link to the exact captured address, opening a new tab.
        final link = tester.widget<Link>(find.byType(Link));
        expect(link.uri, Uri.parse(_imported.sourceUrl!));
        expect(link.target, LinkTarget.blank);
      });

      testWidgets('the chef line opens the chef page ($name)', (tester) async {
        await _pump(tester, _imported, width: width);

        await tester.tap(find.byKey(SourceCredit.chefLineKey));
        await tester.pumpAndSettle();

        expect(find.text('CHEF chef-1'), findsOneWidget);
      });

      testWidgets('the publisher line opens the entity page ($name)', (
        tester,
      ) async {
        await _pump(tester, _imported, width: width);

        await tester.tap(find.byKey(SourceCredit.publisherLineKey));
        await tester.pumpAndSettle();

        expect(find.text('ENTITY ent-1'), findsOneWidget);
      });

      testWidgets('the rights link opens /legal/rights ($name)', (
        tester,
      ) async {
        await _pump(tester, _imported, width: width);

        await tester.tap(find.text('How we credit recipes'));
        await tester.pumpAndSettle();

        expect(find.text('LEGAL rights'), findsOneWidget);
      });
    }
  });

  group('a member recipe', () {
    for (final (name, width) in _layouts) {
      testWidgets('shows no attribution block at all ($name)', (tester) async {
        await _pump(tester, _member, width: width);

        expect(find.text('FROM AROUND THE WEB'), findsNothing);
        expect(find.textContaining('Published by'), findsNothing);
        expect(find.textContaining('Read the original'), findsNothing);
        expect(find.text('How we credit recipes'), findsNothing);
        expect(find.byType(Link), findsNothing);
        // …while the cook's own story, the other kind of provenance, stays.
        expect(find.text(_member.attribution!), findsOneWidget);
      });
    }

    testWidgets('the widget itself renders nothing for one', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SourceCredit(recipe: _member))),
      );
      expect(
        tester.getSize(find.byType(SourceCredit)),
        Size.zero,
        reason: 'a non-imported recipe must not reserve even an empty box',
      );
    });
  });

  group('credits only what the row can stand behind', () {
    testWidgets('no byline: the publisher alone, no invented person', (
      tester,
    ) async {
      // The importer's publisher-as-author case: one imported profile per
      // entity, named after it (`import_recipe`, 0001).
      await _pump(
        tester,
        _imported.copyWith(
          sourceName: 'Mutti',
          owner: const Profile(
            id: 'p-mutti',
            displayName: 'Mutti',
            kind: ProfileKind.imported,
          ),
        ),
      );

      expect(find.byKey(SourceCredit.chefLineKey), findsNothing);
      expect(_rich('Published by Mutti'), findsOneWidget);
    });

    // `import_recipe` clamps the publisher profile's name to 80 characters but
    // keeps `source_name` whole, so a long publisher must still match itself.
    test('no byline survives the 80-character name clamp', () {
      final long = 'The ${'Very ' * 20}Long Publishing House';
      final recipe = _imported.copyWith(
        sourceName: long,
        owner: Profile(
          id: 'p-long',
          displayName: long.substring(0, 80),
          kind: ProfileKind.imported,
        ),
      );
      expect(long.length, greaterThan(80));
      expect(SourceCredit.creditedChef(recipe), isNull);
    });

    testWidgets('no entity: the publisher prints but does not link', (
      tester,
    ) async {
      final recipe = _imported.copyWith(sourceEntityId: null);
      await _pump(tester, recipe);

      final line = find.byKey(SourceCredit.publisherLineKey);
      expect(line, findsOneWidget);
      expect(
        find.descendant(of: line, matching: find.byType(InkWell)),
        findsNothing,
      );
      expect(
        find.descendant(of: line, matching: find.byIcon(Icons.chevron_right)),
        findsNothing,
      );
    });

    testWidgets('no publisher name: the host stands in', (tester) async {
      await _pump(tester, _imported.copyWith(sourceName: null));

      expect(_rich('Published by cafedelites.com'), findsOneWidget);
    });

    testWidgets('a non-web address prints and never becomes a link', (
      tester,
    ) async {
      await _pump(tester, _imported.copyWith(sourceUrl: 'javascript:alert(1)'));

      expect(find.byType(Link), findsNothing);
      expect(find.textContaining('Read the original'), findsNothing);
      expect(find.text('javascript:alert(1)'), findsOneWidget);
    });

    testWidgets('link-only: the method is on their page, and says so', (
      tester,
    ) async {
      await _pump(tester, _imported.copyWith(rightsMode: RightsMode.linkOnly));

      expect(
        find.textContaining('asked us to link rather than reproduce'),
        findsOneWidget,
      );
      // The link is the recipe now, so it is the filled button.
      expect(
        find.ancestor(
          of: find.text('Read the original on cafedelites.com'),
          matching: find.byType(FilledButton),
        ),
        findsOneWidget,
      );
    });
  });

  // The block is prose in a column on both pages, so its failure mode is a
  // `Row` of intrinsically-sized children at 2.0× on a phone (Gotcha 21) — the
  // label beside the name, the chevron beside the credit, the icon beside the
  // kicker. Pumped with the longest names the corpus holds.
  group('layout envelope', () {
    for (final width in [390.0, 600.0, 1000.0, 1440.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('no overflow at ${width}px, textScale $scale', (
          tester,
        ) async {
          await _pump(tester, _longest, width: width, textScale: scale);

          expect(tester.takeException(), isNull);
          expect(find.text('FROM AROUND THE WEB'), findsOneWidget);
          expect(
            find.textContaining('Read the original on', findRichText: true),
            findsOneWidget,
          );
        });
      }
    }
  });
}
