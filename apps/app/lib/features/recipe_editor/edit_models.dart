import 'package:core/core.dart';
import 'package:flutter/widgets.dart';

/// Mutable, controller-backed editing models used by the recipe editor.
/// They convert to/from the immutable `core` models on load and save.
///
/// Every field the `core` model carries has to be represented here, even when
/// the editor has no input for it: `RecipeRepository.update()` deletes the
/// recipe's groups and re-inserts whatever these `toModel()` calls produce, so
/// a field these classes drop is a field the save silently erases (B035).

/// Trimmed text, or null when empty — the shape every optional column wants.
String? _orNull(TextEditingController c) {
  final text = c.text.trim();
  return text.isEmpty ? null : text;
}

class EditIngredient {
  EditIngredient({
    String quantity = '',
    String unit = '',
    String name = '',
    String note = '',
    this.isOptional = false,
  })  : quantity = TextEditingController(text: quantity),
        unit = TextEditingController(text: unit),
        name = TextEditingController(text: name),
        note = TextEditingController(text: note),
        showDetails = note.isNotEmpty || isOptional;

  factory EditIngredient.fromModel(Ingredient i) => EditIngredient(
        quantity: i.quantity?.toString() ?? '',
        unit: i.unit ?? '',
        name: i.name,
        note: i.note ?? '',
        isOptional: i.isOptional,
      );

  final TextEditingController quantity;
  final TextEditingController unit;
  final TextEditingController name;
  final TextEditingController note;

  bool isOptional;

  /// Whether the note/optional line is revealed. Starts open when the loaded
  /// ingredient already uses either, so an edit cannot hide existing content.
  bool showDetails;

  Ingredient toModel(int sortOrder) => Ingredient(
        id: '',
        groupId: '',
        quantity: double.tryParse(quantity.text.trim()),
        unit: _orNull(unit),
        name: name.text.trim(),
        note: _orNull(note),
        isOptional: isOptional,
        sortOrder: sortOrder,
      );

  void dispose() {
    quantity.dispose();
    unit.dispose();
    name.dispose();
    note.dispose();
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
  EditStep({
    String text = '',
    String duration = '',
    String temperature = '',
    String tip = '',
    this.imageUrl,
  })  : text = TextEditingController(text: text),
        duration = TextEditingController(text: duration),
        temperature = TextEditingController(text: temperature),
        tip = TextEditingController(text: tip),
        showDetails =
            duration.isNotEmpty || temperature.isNotEmpty || tip.isNotEmpty;

  factory EditStep.fromModel(RecipeStep s) => EditStep(
        text: s.text,
        duration: s.durationMinutes?.toString() ?? '',
        temperature: s.temperature ?? '',
        tip: s.tip ?? '',
        imageUrl: s.imageUrl,
      );

  final TextEditingController text;
  final TextEditingController duration;
  final TextEditingController temperature;
  final TextEditingController tip;

  /// Carried through untouched. There is no per-step image picker yet, but a
  /// step that already has an image must not lose it on save (B035).
  final String? imageUrl;

  /// Whether the time/temperature/tip block is revealed. Starts open when the
  /// loaded step already uses any of them.
  bool showDetails;

  /// True when this step carries anything beyond its text — drives the
  /// disclosure button's emphasis so collapsed detail is still discoverable.
  bool get hasDetails =>
      duration.text.trim().isNotEmpty ||
      temperature.text.trim().isNotEmpty ||
      tip.text.trim().isNotEmpty;

  RecipeStep toModel(int order) => RecipeStep(
        id: '',
        groupId: '',
        stepOrder: order,
        sortOrder: order,
        text: text.text.trim(),
        imageUrl: imageUrl,
        durationMinutes: int.tryParse(duration.text.trim()),
        temperature: _orNull(temperature),
        tip: _orNull(tip),
      );

  void dispose() {
    text.dispose();
    duration.dispose();
    temperature.dispose();
    tip.dispose();
  }
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
