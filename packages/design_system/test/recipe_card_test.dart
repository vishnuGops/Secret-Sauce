import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('RecipeCard shows title, description, time and difficulty',
      (tester) async {
    const recipe = Recipe(
      id: '1',
      ownerId: 'u1',
      title: 'Grandma Sauce',
      description: 'Slow-cooked Sunday sauce',
      difficulty: Difficulty.medium,
      prepMinutes: 15,
      cookMinutes: 45,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: Center(
            child: SizedBox(width: 320, child: RecipeCard(recipe: recipe)),
          ),
        ),
      ),
    );

    expect(find.text('Grandma Sauce'), findsOneWidget);
    expect(find.text('Slow-cooked Sunday sauce'), findsOneWidget);
    expect(find.text('1h'), findsOneWidget); // 60 minutes total
    expect(find.text('Medium'), findsOneWidget);
  });
}
