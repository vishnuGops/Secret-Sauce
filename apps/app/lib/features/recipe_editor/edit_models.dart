import 'package:core/core.dart';
import 'package:flutter/widgets.dart';

/// Mutable, controller-backed editing models used by the recipe editor.
/// They convert to/from the immutable `core` models on load and save.

class EditIngredient {
  EditIngredient({String quantity = '', String unit = '', String name = ''})
      : quantity = TextEditingController(text: quantity),
        unit = TextEditingController(text: unit),
        name = TextEditingController(text: name);

  factory EditIngredient.fromModel(Ingredient i) => EditIngredient(
        quantity: i.quantity?.toString() ?? '',
        unit: i.unit ?? '',
        name: i.name,
      );

  final TextEditingController quantity;
  final TextEditingController unit;
  final TextEditingController name;

  Ingredient toModel(int sortOrder) => Ingredient(
        id: '',
        groupId: '',
        quantity: double.tryParse(quantity.text.trim()),
        unit: unit.text.trim().isEmpty ? null : unit.text.trim(),
        name: name.text.trim(),
        sortOrder: sortOrder,
      );

  void dispose() {
    quantity.dispose();
    unit.dispose();
    name.dispose();
  }
}

class EditIngredientGroup {
  EditIngredientGroup({String name = '', List<EditIngredient>? ingredients})
      : name = TextEditingController(text: name),
        ingredients = ingredients ?? [EditIngredient()];

  factory EditIngredientGroup.fromModel(IngredientGroup g) =>
      EditIngredientGroup(
        name: g.name,
        ingredients: g.ingredients.map(EditIngredient.fromModel).toList(),
      );

  final TextEditingController name;
  final List<EditIngredient> ingredients;

  IngredientGroup toModel() => IngredientGroup(
        id: '',
        recipeId: '',
        name: name.text.trim(),
        ingredients: [
          for (var i = 0; i < ingredients.length; i++)
            ingredients[i].toModel(i),
        ].where((i) => i.name.isNotEmpty).toList(),
      );

  void dispose() {
    name.dispose();
    for (final i in ingredients) {
      i.dispose();
    }
  }
}

class EditStep {
  EditStep({String text = ''}) : text = TextEditingController(text: text);

  factory EditStep.fromModel(RecipeStep s) => EditStep(text: s.text);

  final TextEditingController text;

  RecipeStep toModel(int order) => RecipeStep(
        id: '',
        groupId: '',
        stepOrder: order,
        sortOrder: order,
        text: text.text.trim(),
      );

  void dispose() => text.dispose();
}

class EditStepGroup {
  EditStepGroup({String name = '', List<EditStep>? steps})
      : name = TextEditingController(text: name),
        steps = steps ?? [EditStep()];

  factory EditStepGroup.fromModel(StepGroup g) => EditStepGroup(
        name: g.name,
        steps: g.steps.map(EditStep.fromModel).toList(),
      );

  final TextEditingController name;
  final List<EditStep> steps;

  StepGroup toModel() => StepGroup(
        id: '',
        recipeId: '',
        name: name.text.trim(),
        steps: [
          for (var i = 0; i < steps.length; i++) steps[i].toModel(i),
        ].where((s) => s.text.isNotEmpty).toList(),
      );

  void dispose() {
    name.dispose();
    for (final s in steps) {
      s.dispose();
    }
  }
}
