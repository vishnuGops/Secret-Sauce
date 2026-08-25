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

/// The editor's three-way nutrition choice (Phase 29c).
///
/// What each saves: [auto] sends `{source: 'auto'}` and the server recomputes
/// the label from the ingredient trees inside `save_recipe` (client numbers
/// are preview-only and never stored); [manual] sends the typed values;
/// [none] sends null. None and an all-empty Manual collapse to the same
/// stored state on purpose — one representation of "no info".
enum EditNutritionMode { auto, manual, none }

/// The 11 nutrition-label fields as text controllers (Phase 28).
///
/// Field-for-field with `RecipeNutrition` — the B035 obligation applies here as
/// much as it does to ingredients and steps: `save_recipe` writes the whole
/// `nutrition` object, so a field this class drops is a field the next save
/// deletes from the label.
///
/// [toModel] returns **null** when every box is empty, never `{}`: `null` is
/// the one representation of "no nutrition info" — in the column, on the wire,
/// and in the detail screen's empty-state branch — and a second spelling of it
/// is how two surfaces start disagreeing.
class EditNutrition {
  EditNutrition({
    String calories = '',
    String totalFat = '',
    String saturatedFat = '',
    String transFat = '',
    String cholesterol = '',
    String sodium = '',
    String totalCarbs = '',
    String dietaryFiber = '',
    String totalSugars = '',
    String addedSugars = '',
    String protein = '',
  }) : calories = TextEditingController(text: calories),
       totalFat = TextEditingController(text: totalFat),
       saturatedFat = TextEditingController(text: saturatedFat),
       transFat = TextEditingController(text: transFat),
       cholesterol = TextEditingController(text: cholesterol),
       sodium = TextEditingController(text: sodium),
       totalCarbs = TextEditingController(text: totalCarbs),
       dietaryFiber = TextEditingController(text: dietaryFiber),
       totalSugars = TextEditingController(text: totalSugars),
       addedSugars = TextEditingController(text: addedSugars),
       protein = TextEditingController(text: protein);

  factory EditNutrition.fromModel(RecipeNutrition? n) =>
      EditNutrition()..load(n);

  /// Fills the existing controllers from [n] (or empties them for null).
  ///
  /// The editor creates its `EditNutrition` once, in a field initializer, and
  /// `_load()` runs afterwards — so this writes into the live controllers
  /// rather than handing back a second instance whose `dispose()` nobody wired
  /// up.
  void load(RecipeNutrition? n) {
    calories.text = _num(n?.calories);
    totalFat.text = _num(n?.totalFatG);
    saturatedFat.text = _num(n?.saturatedFatG);
    transFat.text = _num(n?.transFatG);
    cholesterol.text = _num(n?.cholesterolMg);
    sodium.text = _num(n?.sodiumMg);
    totalCarbs.text = _num(n?.totalCarbsG);
    dietaryFiber.text = _num(n?.dietaryFiberG);
    totalSugars.text = _num(n?.totalSugarsG);
    addedSugars.text = _num(n?.addedSugarsG);
    protein.text = _num(n?.proteinG);
  }

  /// A stored `numeric` round-trips as `10.0`; showing that in a box the user
  /// typed `10` into reads as the editor having changed their entry.
  static String _num(double? v) => v == null ? '' : formatNutritionValue(v);

  final TextEditingController calories;
  final TextEditingController totalFat;
  final TextEditingController saturatedFat;
  final TextEditingController transFat;
  final TextEditingController cholesterol;
  final TextEditingController sodium;
  final TextEditingController totalCarbs;
  final TextEditingController dietaryFiber;
  final TextEditingController totalSugars;
  final TextEditingController addedSugars;
  final TextEditingController protein;

  List<TextEditingController> get _all => [
    calories,
    totalFat,
    saturatedFat,
    transFat,
    cholesterol,
    sodium,
    totalCarbs,
    dietaryFiber,
    totalSugars,
    addedSugars,
    protein,
  ];

  /// True when at least one box has something in it. Drives whether the panel
  /// opens expanded — a recipe that already carries a label must not hide it
  /// behind a collapsed header.
  bool get hasValues => _all.any((c) => c.text.trim().isNotEmpty);

  /// True when a box holds something that is not a non-negative number — the
  /// entries `_Field`'s validator rejects and [toModel] would otherwise drop.
  ///
  /// Restates that validator's rule on purpose: the screen needs the answer
  /// *before* deciding whether a blocked save was the nutrition panel's fault,
  /// and `Form.validate()` only says that the form as a whole failed. Keep the
  /// two predicates in step — `recipe_editor_test.dart` fails if they drift.
  bool get hasInvalidEntry => _all.any((c) {
    final text = c.text.trim();
    if (text.isEmpty) return false;
    final value = double.tryParse(text);
    return value == null || value < 0;
  });

  RecipeNutrition? toModel() {
    final model = RecipeNutrition(
      calories: _parse(calories),
      totalFatG: _parse(totalFat),
      saturatedFatG: _parse(saturatedFat),
      transFatG: _parse(transFat),
      cholesterolMg: _parse(cholesterol),
      sodiumMg: _parse(sodium),
      totalCarbsG: _parse(totalCarbs),
      dietaryFiberG: _parse(dietaryFiber),
      totalSugarsG: _parse(totalSugars),
      addedSugarsG: _parse(addedSugars),
      proteinG: _parse(protein),
    );
    return model.isEmpty ? null : model;
  }

  static double? _parse(TextEditingController c) =>
      double.tryParse(c.text.trim());

  void dispose() {
    for (final c in _all) {
      c.dispose();
    }
  }
}

class EditIngredient {
  EditIngredient({
    String quantity = '',
    String unit = '',
    String name = '',
    String note = '',
    this.isOptional = false,
    this.foodId,
  }) : quantity = TextEditingController(text: quantity),
       unit = TextEditingController(text: unit),
       name = TextEditingController(text: name),
       note = TextEditingController(text: note),
       nameFocus = FocusNode(),
       showDetails = note.isNotEmpty || isOptional;

  factory EditIngredient.fromModel(Ingredient i) => EditIngredient(
    quantity: i.quantity?.toString() ?? '',
    unit: i.unit ?? '',
    name: i.name,
    note: i.note ?? '',
    isOptional: i.isOptional,
    foodId: i.foodId,
  );

  final TextEditingController quantity;
  final TextEditingController unit;
  final TextEditingController name;
  final TextEditingController note;

  /// For the name field's typeahead overlay (`RawAutocomplete` needs the node
  /// and the controller to come from the same owner).
  final FocusNode nameFocus;

  bool isOptional;

  /// The food-registry link (Phase 29b) — `food.id`, or null for free text.
  /// Set by picking a typeahead suggestion, cleared by the chip; deliberately
  /// NOT cleared when the name is retyped, because surviving a rename is the
  /// point of a per-row link (the cook's words stay theirs, the link stays
  /// linked until they say otherwise).
  String? foodId;

  /// Display name for the chip. Session-only — the database stores only the
  /// id — filled by a pick or by the editor's post-load lookup; null renders
  /// the generic label.
  String? foodLabel;

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
    foodId: foodId,
  );

  void dispose() {
    quantity.dispose();
    unit.dispose();
    name.dispose();
    note.dispose();
    nameFocus.dispose();
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
    ingredients:
        [for (var i = 0; i < ingredients.length; i++) ingredients[i].toModel(i)]
            .where((i) => i.name.isNotEmpty)
            .toList(),
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
  }) : text = TextEditingController(text: text),
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
    steps:
        [
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
