import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:app/routing/app_router.dart';

/// A responsive grid of [RecipeCard]s that navigates to detail on tap.
class RecipeGrid extends StatelessWidget {
  const RecipeGrid({
    super.key,
    required this.recipes,
    this.padding = const EdgeInsets.all(AppSpacing.md),
  });

  final List<Recipe> recipes;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final cols = responsiveColumns(context);
    return GridView.builder(
      padding: padding,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: AppSpacing.md,
        crossAxisSpacing: AppSpacing.md,
        childAspectRatio: 0.82,
      ),
      itemCount: recipes.length,
      itemBuilder: (context, i) {
        final recipe = recipes[i];
        return RecipeCard(
          recipe: recipe,
          onTap: () => context.push(Routes.recipe(recipe.id)),
        );
      },
    );
  }
}
