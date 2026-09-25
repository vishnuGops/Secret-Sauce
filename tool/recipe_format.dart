// tool/recipe_format.dart — THE definition of a valid authored recipe.
//
// Shared by the two generators that read authored recipe JSON:
//
//   tool/recipes.dart  recipeData/recipes/*.json -> supabase/seed_recipes.sql
//   tool/sim.dart      simData/dishes/*.json     -> supabase/sim/1_sim_dishes.sql
//
// It exists because those two directories hold the SAME format and must not
// drift into two different definitions of "valid". recipeData/schema.json is the
// prose version of these rules and is NOT read at runtime (the toolchain has no
// JSON Schema dependency), so a rule added there must be added HERE — one place
// now, rather than once per generator.
//
// The two directories differ in exactly one key now: simData allows a `sim`
// block (generation hints), recipeData allows nothing extra. recipeData's old
// `demo` block — authored engagement counters and taster ratings — is retired
// and actively refused; see `_retiredRecipeKeys` and B112.
//
// `tool/` is a folder of loose scripts, not a pub package, so this is a relative
// import at the call sites. `melos run analyze` runs per-package inside
// packages/** and apps/**, so it never reaches this file; the ignore below keeps
// an IDE analyzing the workspace root quiet about the same thing.

import 'dart:convert';
import 'dart:io';

/// One authored recipe file, as loaded. `file` is the bare filename
/// ("shirazi-salad.json"); the slug is the filename without its extension, and
/// is the recipe's repo-level identity.
class AuthoredRecipe {
  const AuthoredRecipe(this.file, this.json);

  final String file;
  final Map<String, dynamic> json;

  String get slug => file.substring(0, file.length - 5);
}

/// The two-key delta between recipeData and simData, plus the knobs a caller
/// might reasonably differ on.
class RecipeFormatOptions {
  const RecipeFormatOptions({
    this.allowSim = false,
    this.dollarTag = r'$sr$',
    this.foodSlugs,
    this.units,
  });

  /// `sim` — generation hints for the population seed. simData only.
  final bool allowSim;

  /// Every slug in nutritionData/foods.json (via [loadFoodSlugs]), so an
  /// ingredient's `food` link is checked against the registry it references —
  /// the generated SQL would otherwise die on the FK at apply time, per file
  /// applied rather than per slug typo'd. Null skips the existence check (the
  /// key is still type-checked); both generators pass it.
  final Set<String>? foodSlugs;

  /// The unit canon from nutritionData/units.json (via [loadUnitCanon]), so an
  /// ingredient's `unit` spelling is linted (BL-8). Null skips the lint (the
  /// key is still type-checked); both generators pass it.
  final UnitCanon? units;

  /// Every string literal in the generated SQL is dollar-quoted with this tag
  /// and never escaped, so content containing it would terminate the literal
  /// early and produce SQL that parses as something else.
  final String dollarTag;
}

/// The outcome of loading + validating a directory.
class RecipeSet {
  const RecipeSet(this.recipes, this.errors, this.warnings);

  final List<AuthoredRecipe> recipes;
  final List<String> errors;
  final List<String> warnings;

  bool get isValid => errors.isEmpty;
}

const _difficulties = {'easy', 'medium', 'hard'};
const _visibilities = {'public', 'private'};
const _categories = {
  'Appetizer',
  'Breakfast',
  'Main',
  'Side',
  'Salad',
  'Soup',
  'Dessert',
  'Drink',
  'Snack',
  'Sauce',
};

/// Every category the repo agrees on, exposed so a caller can assert coverage
/// across a whole directory (the sim library must span all of them).
Set<String> get recipeCategories => _categories;

const _baseRecipeKeys = {
  'slug',
  'title',
  'description',
  'cuisine',
  'category',
  'difficulty',
  'prep_minutes',
  'cook_minutes',
  'servings',
  'visibility',
  'attribution',
  'notes',
  'nutrition',
  'ingredient_groups',
  'step_groups',
};
const _requiredRecipeKeys = [
  'slug',
  'title',
  'description',
  'difficulty',
  'prep_minutes',
  'cook_minutes',
  'servings',
  'ingredient_groups',
  'step_groups',
];

/// The eleven label fields plus the `source` provenance stamp (Phase 29c) —
/// the authoring-side copy of `RecipeNutrition`. Postgres stores the value as
/// an unstructured `jsonb`, so a typo'd key would be accepted by the column,
/// saved, and then silently dropped on decode; this set is what turns that
/// into a build failure. `source` is the one non-numeric key: `'auto'` marks a
/// label the estimator computed (29d commits such fixtures), absent means
/// manual, and no other value exists.
const _nutritionKeys = {
  'calories',
  'total_fat_g',
  'saturated_fat_g',
  'trans_fat_g',
  'cholesterol_mg',
  'sodium_mg',
  'total_carbs_g',
  'dietary_fiber_g',
  'total_sugars_g',
  'added_sugars_g',
  'protein_g',
  'source',
};
const _ingredientKeys = {
  'quantity',
  'unit',
  'name',
  'note',
  'is_optional',
  'food',
};
const _stepKeys = {'text', 'duration_minutes', 'temperature', 'tip'};

/// Keys that were once authorable and are now refused outright, with the
/// reason a reader needs. `demo` compiled fabricated engagement counters and
/// taster ratings straight into `seed_recipes.sql`, so a curated recipe
/// shipped claiming 412 likes with zero `recipe_likes` rows behind it (B112).
/// Engagement is earned by real readers or generated by the sim into a
/// throwaway database — never authored into content.
///
/// A retired key is an ERROR, not an unknown field: the pointed message is the
/// whole value of keeping it listed after the support is gone.
const _retiredRecipeKeys = <String, String>{
  'demo':
      'demo is retired (B112) — authored engagement counters and taster '
      'ratings are no longer permitted in curated content. Delete the block; '
      'counters start at zero and are earned.',
};

/// Words too common to prove an ingredient is used by a step.
const _stopWords = {
  'and',
  'or',
  'of',
  'for',
  'the',
  'to',
  'with',
  'plus',
  'fresh',
  'organic',
  'large',
  'small',
  'whole',
  'ground',
  'chopped',
  'minced',
  'grated',
  'cold',
  'hot',
  'more',
  'taste',
  'serving',
  'garnish',
  'unbleached',
  'granulated',
};

/// Every food slug in nutritionData/foods.json, for [RecipeFormatOptions.foodSlugs].
///
/// Exits on a missing or malformed file rather than returning an empty set: an
/// empty set would fail every linked ingredient with "unknown slug", which
/// points the author at their recipe when the broken thing is the registry.
Set<String> loadFoodSlugs(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('Missing food registry: $path');
    exit(1);
  }
  final decoded = jsonDecode(file.readAsStringSync());
  final foods = decoded is Map<String, dynamic> ? decoded['foods'] : null;
  if (foods is! List) {
    stderr.writeln('$path: expected a top-level "foods" array');
    exit(1);
  }
  return {
    for (final f in foods)
      if (f is Map && f['slug'] is String) f['slug'] as String,
  };
}

/// One registry unit as an AUTHORED recipe must spell it.
class _CanonUnit {
  const _CanonUnit(this.display, this.plural);

  /// The singular, or the only form for an invariant unit (`tbsp`, `L`).
  final String display;

  /// The plural of a word unit (`cups`), null for an invariant one.
  final String? plural;
}

/// The unit canon (BL-8): which spellings an authored `unit` may use.
///
/// The app prints `unit` verbatim (`formatText` is `'$amount $unit'`), so the
/// spelling in a recipe file is the spelling a cook reads — and B094 showed it
/// drifts one recipe at a time once nothing checks it. The canon lives in
/// nutritionData/units.json beside the spellings it narrows, as `display` (+
/// `plural` for a word unit), because it cannot be derived from them: key `l`
/// displays as `L` (a lowercase l reads as a 1), and word units keep the
/// plural a reader expects (`3 cloves`, never `3 clove`).
///
/// Resolution stays case-insensitive — that is what the estimator does — so a
/// spelling can resolve and still be wrong: `Tbsp` resolves to `tbsp` and is
/// an error here, because it prints as `Tbsp`.
class UnitCanon {
  const UnitCanon._(this._bySpelling, this._unresolvable);

  /// Lowercased accepted spelling -> the unit it resolves to.
  final Map<String, _CanonUnit> _bySpelling;

  /// units.json `unresolvable`: spellings the estimator skips ON PURPOSE
  /// (`pinch`, `handful`). Known, so not warned about — but still lowercase.
  final Set<String> _unresolvable;
}

/// Reads nutritionData/units.json into a [UnitCanon] for
/// [RecipeFormatOptions.units].
///
/// Exits on a malformed registry for the same reason [loadFoodSlugs] does: a
/// unit with no `display` would turn every recipe that uses it into an error
/// that points at the recipe, when the broken thing is the registry.
UnitCanon loadUnitCanon(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('Missing unit registry: $path');
    exit(1);
  }
  final decoded = jsonDecode(file.readAsStringSync());
  final units = decoded is Map<String, dynamic> ? decoded['units'] : null;
  if (units is! List) {
    stderr.writeln('$path: expected a top-level "units" array');
    exit(1);
  }
  Never fail(String msg) {
    stderr.writeln('$path: $msg');
    exit(1);
  }

  final bySpelling = <String, _CanonUnit>{};
  for (final u in units) {
    if (u is! Map) fail('every unit must be an object');
    final key = u['key'];
    final spellings = u['spellings'];
    if (key is! String || spellings is! List) {
      fail('every unit needs a string "key" and a "spellings" array');
    }
    final forms = spellings.whereType<String>().toSet();
    // The bare-count marker: an authored unit is null there, never "", so
    // there is nothing to display and nothing to resolve.
    if (forms.every((s) => s.isEmpty)) continue;

    final display = u['display'];
    final plural = u['plural'];
    if (display is! String || display.isEmpty) {
      fail('units.$key has no "display" — the spelling authored recipes use');
    }
    if (plural != null && (plural is! String || plural.isEmpty)) {
      fail('units.$key: "plural" must be a non-empty string when present');
    }
    for (final form in [display, if (plural is String) plural]) {
      if (!forms.contains(form.toLowerCase())) {
        fail(
          'units.$key: display form "$form" does not resolve to one of its '
          'own spellings',
        );
      }
    }
    final canon = _CanonUnit(display, plural as String?);
    for (final s in forms) {
      if (s.isNotEmpty) bySpelling[s] = canon;
    }
  }

  final unresolvable = (decoded as Map<String, dynamic>)['unresolvable'];
  return UnitCanon._(bySpelling, {
    if (unresolvable is List) ...unresolvable.whereType<String>(),
  });
}

/// Loads every `*.json` in [dir], sorted by filename so generated SQL is stable,
/// then validates the lot. Exits the process if the directory is missing — that
/// is a broken checkout, not a content error worth reporting per-file.
RecipeSet loadAndValidate(
  String dir, {
  RecipeFormatOptions options = const RecipeFormatOptions(),
}) {
  final errors = <String>[];
  final warnings = <String>[];
  final recipes = _load(dir, errors);
  _validate(recipes, options, errors, warnings);
  return RecipeSet(recipes, errors, warnings);
}

List<AuthoredRecipe> _load(String dir, List<String> errors) {
  final directory = Directory(dir);
  if (!directory.existsSync()) {
    stderr.writeln('Missing directory: $dir');
    exit(1);
  }
  final files =
      directory
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  final out = <AuthoredRecipe>[];
  for (final file in files) {
    final name = file.uri.pathSegments.last;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map<String, dynamic>) {
        errors.add(
          '$name: top level must be an object, '
          'got ${decoded.runtimeType}',
        );
        continue;
      }
      out.add(AuthoredRecipe(name, decoded));
    } on FormatException catch (e) {
      errors.add('$name: invalid JSON — ${e.message}');
    }
  }
  return out;
}

void _validate(
  List<AuthoredRecipe> recipes,
  RecipeFormatOptions options,
  List<String> errors,
  List<String> warnings,
) {
  final v = _Validator(options, errors, warnings);
  final titles = <String, String>{};

  for (final recipe in recipes) {
    v.check(recipe, titles);
  }
}

/// Carries the option set and the two issue lists so the per-rule methods read
/// the way they did as top-level functions.
class _Validator {
  _Validator(this.options, this.errors, this.warnings);

  final RecipeFormatOptions options;
  final List<String> errors;
  final List<String> warnings;

  void _err(String where, String msg) => errors.add('$where: $msg');
  void _warn(String where, String msg) => warnings.add('$where: $msg');

  Set<String> get _recipeKeys => {
    ..._baseRecipeKeys,
    if (options.allowSim) 'sim',
  };

  void check(AuthoredRecipe recipe, Map<String, String> titles) {
    final file = recipe.file;
    final r = recipe.json;
    final slug = recipe.slug;

    for (final key in r.keys) {
      final retired = _retiredRecipeKeys[key];
      if (retired != null) {
        _err(file, retired);
      } else if (!_recipeKeys.contains(key)) {
        _err(file, 'unknown field "$key"');
      }
    }
    for (final key in _requiredRecipeKeys) {
      if (!r.containsKey(key)) _err(file, 'missing required field "$key"');
    }

    // Identity. The filename is the real key — a mismatch means one of the two
    // is a typo, and which one is not knowable from here.
    if (r['slug'] != slug) {
      _err(file, 'slug "${r['slug']}" does not match the filename ("$slug")');
    }
    if (!RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$').hasMatch(slug)) {
      _err(file, 'filename is not a kebab-case slug');
    }

    final title = r['title'];
    if (title is! String || title.trim().isEmpty) {
      _err(file, 'title must be a non-empty string');
    } else if (titles.containsKey(title)) {
      // seed_recipe_v2 dedupes on (owner_id, title), so two files with the same
      // title silently collapse into one row on import instead of erroring.
      _err(file, 'duplicate title "$title" (also in ${titles[title]})');
    } else {
      titles[title] = file;
    }

    _requireString(file, r, 'description', required: true);
    _requireString(file, r, 'cuisine');
    _requireString(file, r, 'attribution');
    _requireString(file, r, 'notes');

    final category = r['category'];
    if (category != null && !_categories.contains(category)) {
      _err(
        file,
        'category "$category" is not in the agreed vocabulary '
        '(${_categories.join(', ')})',
      );
    }
    if (!_difficulties.contains(r['difficulty'])) {
      _err(file, 'difficulty must be one of ${_difficulties.join(', ')}');
    }
    final visibility = r['visibility'] ?? 'public';
    if (!_visibilities.contains(visibility)) {
      _err(file, 'visibility must be one of ${_visibilities.join(', ')}');
    }

    _requireInt(file, r, 'prep_minutes', min: 0, max: 1440);
    _requireInt(file, r, 'cook_minutes', min: 0, max: 1440);
    _requireInt(file, r, 'servings', min: 1, max: 100);

    _validateNutrition(file, r);
    _validateIngredientGroups(file, r);
    _validateStepGroups(file, r);
    _lintUnusedIngredients(file, r);

    // Every literal is dollar-quoted with the tag and never escaped, so the tag
    // appearing in content would terminate the literal early and produce SQL
    // that either fails to parse or, worse, parses as something else.
    forEachString(r, (path, value) {
      if (value.contains(options.dollarTag)) {
        _err(file, 'string at $path contains "${options.dollarTag}"');
      }
    });
  }

  void _requireString(
    String file,
    Map<String, dynamic> r,
    String key, {
    bool required = false,
  }) {
    final v = r[key];
    if (v == null) {
      if (required) _err(file, '$key is required');
      return;
    }
    if (v is! String) {
      _err(file, '$key must be a string or null');
    } else if (required && v.trim().isEmpty) {
      _err(file, '$key must not be empty');
    }
  }

  void _requireInt(
    String file,
    Map<String, dynamic> r,
    String key, {
    required int min,
    required int max,
  }) {
    final v = r[key];
    if (v is! int) {
      _err(file, '$key must be an integer');
    } else if (v < min || v > max) {
      _err(file, '$key must be between $min and $max (got $v)');
    }
  }

  /// `nutrition` is optional and **never required** — most recipes have no
  /// label, and the format spells the absence out as an explicit `null` rather
  /// than an omitted key, so both forms are accepted here.
  ///
  /// An empty object is rejected: `null` is the one representation of "no
  /// info" everywhere else in this feature (the model normalizes to it, the
  /// column stores it, the UI branches on it), and a second spelling of the
  /// same state is how two surfaces start disagreeing.
  void _validateNutrition(String file, Map<String, dynamic> r) {
    if (!r.containsKey('nutrition') || r['nutrition'] == null) return;
    final n = r['nutrition'];
    if (n is! Map<String, dynamic>) {
      _err(file, 'nutrition must be an object or null');
      return;
    }
    if (n.isEmpty) {
      _err(file, 'nutrition is an empty object — use null for "no info"');
      return;
    }
    if (n.keys.every((k) => k == 'source')) {
      // Provenance is not content: `{source: 'auto'}` would decode to an
      // empty label (isEmpty ignores source) and normalize away on the first
      // edit — the fixture should say null and mean it.
      _err(file, 'nutrition carries only "source" — use null for "no info"');
      return;
    }
    for (final key in n.keys) {
      if (!_nutritionKeys.contains(key)) {
        _err(file, 'nutrition unknown field "$key"');
      }
    }
    for (final entry in n.entries) {
      final v = entry.value;
      // The provenance stamp (29c) is the one non-numeric key, and 'auto' is
      // its only value — manual is spelled by absence, never 'manual'.
      if (entry.key == 'source') {
        if (v != 'auto') {
          _err(file, "nutrition.source must be 'auto' (absent means manual)");
        }
        continue;
      }
      // Zero is legitimate on a label (0 g trans fat is a printed row), so the
      // bound is non-negative, unlike `quantity`'s.
      if (v is! num || v < 0) {
        _err(file, 'nutrition.${entry.key} must be a non-negative number');
      }
    }
  }

  void _validateIngredientGroups(String file, Map<String, dynamic> r) {
    final groups = r['ingredient_groups'];
    if (groups is! List || groups.isEmpty) {
      _err(file, 'ingredient_groups must be a non-empty array');
      return;
    }
    for (var gi = 0; gi < groups.length; gi++) {
      final g = groups[gi];
      final at = 'ingredient_groups[$gi]';
      if (g is! Map<String, dynamic>) {
        _err(file, '$at must be an object');
        continue;
      }
      if (g['name'] is! String) _err(file, '$at.name must be a string');
      final items = g['ingredients'];
      if (items is! List || items.isEmpty) {
        _err(file, '$at.ingredients must be a non-empty array');
        continue;
      }
      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        final iat = '$at.ingredients[$i]';
        if (item is! Map<String, dynamic>) {
          _err(file, '$iat must be an object');
          continue;
        }
        for (final key in item.keys) {
          if (!_ingredientKeys.contains(key)) {
            _err(file, '$iat unknown field "$key"');
          }
        }
        final name = item['name'];
        if (name is! String || name.trim().isEmpty) {
          _err(file, '$iat.name must be a non-empty string');
        }
        final qty = item['quantity'];
        if (qty != null && (qty is! num || qty <= 0)) {
          _err(file, '$iat.quantity must be a positive number or null');
        }
        final unit = item['unit'];
        if (unit != null && unit is! String) {
          _err(file, '$iat.unit must be a string or null');
        } else if (unit is String) {
          _lintUnit(file, iat, unit, qty is num ? qty : null);
        }
        if (item['note'] != null && item['note'] is! String) {
          _err(file, '$iat.note must be a string or null');
        }
        if (item['is_optional'] != null && item['is_optional'] is! bool) {
          _err(file, '$iat.is_optional must be a boolean');
        }
        // `food` — the ingredient → registry link (Phase 29b). Optional; when
        // present it must name a slug foods.json actually has, because the
        // generated SQL carries it into a real FK column.
        final food = item['food'];
        if (food != null) {
          if (food is! String) {
            _err(file, '$iat.food must be a string or null');
          } else if (options.foodSlugs != null &&
              !options.foodSlugs!.contains(food)) {
            _err(
              file,
              '$iat.food "$food" is not a slug in nutritionData/foods.json',
            );
          }
        }
        // "(optional)" in the name defeats the is_optional flag the UI reads.
        if (name is String && name.toLowerCase().contains('optional')) {
          _warn(file, '$iat.name says "optional" — use "is_optional": true');
        }
      }
    }
  }

  /// The unit canon (BL-8). Two severities, on purpose:
  ///
  /// - ERROR: the spelling resolves to a registry unit but is not how this
  ///   repo prints it — `Tbsp`, `tablespoons`, `grams`, `l`, `lbs`, a word unit
  ///   whose number disagrees with the quantity (`3 clove`, `1 cups`), or an
  ///   empty string. Each has exactly one right answer, which the message names.
  /// - WARNING: the spelling is not in units.json at all (`sprigs`, `knob`).
  ///   That is usually a real authoring decision the registry has not caught up
  ///   with, and it costs the estimator nothing it was not already losing — so
  ///   blocking it would block content on a registry gap.
  ///
  /// Word-unit agreement: a quantity above 1 takes the plural, exactly 1 takes
  /// the singular, and below 1 or no quantity accepts either (`0.5 cup` and
  /// `0.5 cups` are both English). Nothing pluralises at render time
  /// (`formatText` is `'$amount $unit'`), so this is the only place it happens.
  void _lintUnit(String file, String iat, String unit, num? qty) {
    final canon = options.units;
    if (canon == null) return;
    final at = '$iat.unit "$unit"';

    if (unit.trim().isEmpty) {
      _err(file, '$iat.unit is blank — use null for a bare count ("2 eggs")');
      return;
    }
    if (unit != unit.trim()) {
      _err(file, '$at has leading or trailing whitespace');
      return;
    }

    final lower = unit.toLowerCase();
    final u = canon._bySpelling[lower];
    if (u == null) {
      if (canon._unresolvable.contains(lower)) {
        // Known and deliberately unresolved (`pinch`, `handful`) — only the
        // case can be wrong, since the app prints it as written.
        if (unit != lower) _err(file, '$at is not canonical — write "$lower"');
        return;
      }
      _warn(
        file,
        '$at is not in nutritionData/units.json — it prints as written and '
        'contributes nothing to an auto nutrition estimate (add it there if '
        'it is a real unit)',
      );
      return;
    }

    final plural = u.plural;
    if (plural == null) {
      // Invariant (abbreviations, `pkg`): one spelling at every quantity.
      if (unit != u.display) {
        _err(
          file,
          '$at is not canonical — write "${u.display}" (${u.display} is '
          'invariant: the same spelling at every quantity)',
        );
      }
      return;
    }

    // A word unit: the singular or the plural, agreeing with the quantity.
    final String want;
    if (qty != null && qty > 1) {
      want = plural;
    } else if (qty == 1) {
      want = u.display;
    } else {
      // No quantity, or a fraction below 1: either number is English, so keep
      // the one the author reached for and only fix its spelling.
      want = lower == plural.toLowerCase() ? plural : u.display;
    }
    if (unit == want) return;
    if (unit == u.display || unit == plural) {
      _err(
        file,
        '$at does not agree with quantity $qty — write "$want" '
        '(nothing pluralises a unit at render time)',
      );
    } else {
      _err(file, '$at is not canonical — write "$want"');
    }
  }

  void _validateStepGroups(String file, Map<String, dynamic> r) {
    final groups = r['step_groups'];
    if (groups is! List || groups.isEmpty) {
      _err(file, 'step_groups must be a non-empty array');
      return;
    }
    for (var gi = 0; gi < groups.length; gi++) {
      final g = groups[gi];
      final at = 'step_groups[$gi]';
      if (g is! Map<String, dynamic>) {
        _err(file, '$at must be an object');
        continue;
      }
      if (g['name'] is! String) _err(file, '$at.name must be a string');
      final steps = g['steps'];
      if (steps is! List || steps.isEmpty) {
        _err(file, '$at.steps must be a non-empty array');
        continue;
      }
      for (var i = 0; i < steps.length; i++) {
        final step = steps[i];
        final sat = '$at.steps[$i]';
        if (step is! Map<String, dynamic>) {
          _err(file, '$sat must be an object');
          continue;
        }
        for (final key in step.keys) {
          if (!_stepKeys.contains(key)) _err(file, '$sat unknown field "$key"');
        }
        final text = step['text'];
        if (text is! String || text.trim().isEmpty) {
          _err(file, '$sat.text must be a non-empty string');
        }
        final duration = step['duration_minutes'];
        if (duration != null &&
            (duration is! int || duration < 1 || duration > 2880)) {
          _err(file, '$sat.duration_minutes must be an integer 1-2880 or null');
        }
        for (final key in const ['temperature', 'tip']) {
          if (step[key] != null && step[key] is! String) {
            _err(file, '$sat.$key must be a string or null');
          }
        }
      }
    }
  }

  /// Warns about an ingredient no step mentions — the margarita's unused orange
  /// liqueur (B025). The reverse direction (a step naming an ingredient nobody
  /// listed) needs a lexicon and is still a manual read.
  void _lintUnusedIngredients(String file, Map<String, dynamic> r) {
    final groups = r['step_groups'];
    final ingredientGroups = r['ingredient_groups'];
    if (groups is! List || ingredientGroups is! List) return;

    final haystack = StringBuffer();
    for (final g in groups) {
      if (g is! Map) continue;
      final steps = g['steps'];
      if (steps is! List) continue;
      for (final s in steps) {
        if (s is Map && s['text'] is String) haystack.write(' ${s['text']}');
      }
    }
    if (_catchAllStep.hasMatch(haystack.toString())) return;
    final text = stems(haystack.toString());

    for (final g in ingredientGroups) {
      if (g is! Map) continue;
      final items = g['ingredients'];
      if (items is! List) continue;
      for (final item in items) {
        if (item is! Map || item['name'] is! String) continue;
        final name = item['name'] as String;
        final tokens = stems(name);
        if (tokens.isEmpty) continue;
        if (tokens.any(text.contains)) continue;
        _warn(file, 'ingredient "$name" is not mentioned by any step');
      }
    }
  }
}

/// A step that refers to the list collectively rather than naming things —
/// "add all the remaining ingredients", "whisk the dry ingredients together".
/// Legitimate recipe writing, and it makes the unused-ingredient lint useless,
/// because nearly everything is then "unmentioned".
///
/// Deliberately just the noun, either number ("every remaining ingredient"):
/// trying to enumerate the qualifiers (all / remaining / dry / wet / …) only
/// produced false positives. The cost is that one collective step suppresses
/// the lint for the whole recipe — this is a warning, not a gate, and the
/// reverse direction was never checkable anyway.
final _catchAllStep = RegExp(r'\bingredients?\b', caseSensitive: false);

/// Lowercased word stems with stop words removed, so "limes" in the list
/// matches "lime juice" in a step.
///
/// Trailing "s" then trailing "e" are dropped, in that order — both sides go
/// through this, so what matters is that plural and singular land on the same
/// stem: limes -> lime -> lim and lime -> lim, tomatoes -> tomatoe -> tomato.
/// (Stripping "es" outright does not: it sends limes to "lim" but leaves lime
/// as "lime", so the pair no longer matches.)
Set<String> stems(String input) =>
    input
        .toLowerCase()
        .split(RegExp(r'[^a-zà-ÿ]+'))
        .where((w) => w.length > 2 && !_stopWords.contains(w))
        .map((w) => w.endsWith('s') ? w.substring(0, w.length - 1) : w)
        .map((w) => w.endsWith('e') ? w.substring(0, w.length - 1) : w)
        .where((w) => w.length > 2)
        .toSet();

/// Walks every string in the decoded JSON, reporting a JSON-pointer-ish path.
void forEachString(
  Object? node,
  void Function(String path, String value) fn, [
  String path = '',
]) {
  if (node is String) {
    fn(path.isEmpty ? '<root>' : path, node);
  } else if (node is Map) {
    node.forEach((k, v) => forEachString(v, fn, '$path.$k'));
  } else if (node is List) {
    for (var i = 0; i < node.length; i++) {
      forEachString(node[i], fn, '$path[$i]');
    }
  }
}

/// The ingredient/step arrays, normalised: every optional key made explicit so
/// the SQL helper never has to distinguish "absent" from "null".
List<Map<String, dynamic>> normaliseIngredientGroups(List<dynamic> groups) => [
  for (final g in groups.cast<Map<String, dynamic>>())
    {
      'name': g['name'],
      'ingredients': [
        for (final i in (g['ingredients'] as List).cast<Map<String, dynamic>>())
          {
            'quantity': i['quantity'],
            'unit': i['unit'],
            'name': i['name'],
            'note': i['note'],
            'is_optional': i['is_optional'] ?? false,
            // Authored as `food`, emitted as `food_id` — the column name, and
            // the same key the client's save payload uses.
            'food_id': i['food'],
          },
      ],
    },
];

List<Map<String, dynamic>> normaliseStepGroups(List<dynamic> groups) => [
  for (final g in groups.cast<Map<String, dynamic>>())
    {
      'name': g['name'],
      'steps': [
        for (final s in (g['steps'] as List).cast<Map<String, dynamic>>())
          {
            'text': s['text'],
            'duration_minutes': s['duration_minutes'],
            'temperature': s['temperature'],
            'tip': s['tip'],
          },
      ],
    },
];
