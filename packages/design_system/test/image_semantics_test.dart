// UX-047: ten image sites had neither a semantic label nor an exclusion, and
// `LoadingView` was an unnamed progress bar. Decorative images (a card's
// cover beside its title, an avatar beside its name) are excluded; the
// spinner says what it is.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(
  theme: AppTheme.light(),
  home: Scaffold(body: Center(child: child)),
);

/// The network image sits under an [ExcludeSemantics] that excludes. A
/// structural check, because no image loads under `flutter test` — a
/// semantics-tree check would pass with or without the exclusion.
Finder _excludedImage() => find.ancestor(
  of: find.byType(CachedNetworkImage),
  matching: find.byWidgetPredicate((w) => w is ExcludeSemantics && w.excluding),
);

void main() {
  testWidgets('LoadingView names its spinner', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(const LoadingView()));
    expect(find.bySemanticsLabel('Loading'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a recipe card cover is not a second, unnamed node', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    const recipe = Recipe(
      id: '1',
      ownerId: 'u1',
      title: 'Tomato Soup',
      coverImageUrl: 'https://img.test/soup.jpg',
    );
    await tester.pumpWidget(
      _app(const SizedBox(width: 320, child: RecipeCard(recipe: recipe))),
    );
    await tester.pump();
    expect(_excludedImage(), findsWidgets);
    handle.dispose();
  });

  testWidgets('an avatar photo is decorative beside its name', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        const ChefAvatar(
          name: 'Amara Baptiste',
          avatarUrl: 'https://img.test/amara.jpg',
          radius: 20,
        ),
      ),
    );
    await tester.pump();
    expect(_excludedImage(), findsWidgets);
    handle.dispose();
  });
}
