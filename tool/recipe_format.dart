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
// The two directories differ in exactly two keys, both flags on
// RecipeFormatOptions: recipeData allows a `demo` block (fake engagement for a
// curated recipe) and simData allows a `sim` block (generation hints). Neither
// allows the other's.
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
    this.allowDemo = false,
    this.allowSim = false,
    this.tasterCount = 8,
    this.dollarTag = r'$sr$',
  });

  /// `demo` — fake engagement counters + taster ratings. recipeData only.
  final bool allowDemo;

  /// `sim` — generation hints for the population seed. simData only.
  final bool allowSim;

  /// How many seeded taster accounts exist, so a longer `demo.ratings` array can
  /// be rejected rather than silently truncated by seed_ratings().
  final int tasterCount;

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
const _ingredientKeys = {'quantity', 'unit', 'name', 'note', 'is_optional'};
const _stepKeys = {'text', 'duration_minutes', 'temperature', 'tip'};
const _demoKeys = {'like_count', 'save_count', 'view_count', 'ratings'};

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
  final files = directory
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
        errors.add('$name: top level must be an object, '
            'got ${decoded.runtimeType}');
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
        if (options.allowDemo) 'demo',
        if (options.allowSim) 'sim',
      };

  void check(AuthoredRecipe recipe, Map<String, String> titles) {
    final file = recipe.file;
    final r = recipe.json;
    final slug = recipe.slug;

    for (final key in r.keys) {
      if (!_recipeKeys.contains(key)) _err(file, 'unknown field "$key"');
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

    _validateIngredientGroups(file, r);
    _validateStepGroups(file, r);
    if (options.allowDemo) _validateDemo(file, r);
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
        if (item['unit'] != null && item['unit'] is! String) {
          _err(file, '$iat.unit must be a string or null');
        }
        if (item['note'] != null && item['note'] is! String) {
          _err(file, '$iat.note must be a string or null');
        }
        if (item['is_optional'] != null && item['is_optional'] is! bool) {
          _err(file, '$iat.is_optional must be a boolean');
        }
        // "(optional)" in the name defeats the is_optional flag the UI reads.
        if (name is String && name.toLowerCase().contains('optional')) {
          _warn(file, '$iat.name says "optional" — use "is_optional": true');
        }
      }
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

  void _validateDemo(String file, Map<String, dynamic> r) {
    final demo = r['demo'];
    if (demo == null) return;
    if (demo is! Map<String, dynamic>) {
      _err(file, 'demo must be an object');
      return;
    }
    for (final key in demo.keys) {
      if (!_demoKeys.contains(key)) _err(file, 'demo.$key is not a known field');
    }
    for (final key in const ['like_count', 'save_count', 'view_count']) {
      final v = demo[key];
      if (v != null && (v is! int || v < 0)) {
        _err(file, 'demo.$key must be a non-negative integer');
      }
    }
    final ratings = demo['ratings'];
    if (ratings == null) return;
    if (ratings is! List) {
      _err(file, 'demo.ratings must be an array');
      return;
    }
    // seed_taster_ids() holds a fixed pool and seed_ratings() stops at the end
    // of it, so an extra rating is silently dropped rather than applied.
    if (ratings.length > options.tasterCount) {
      _err(
          file,
          'demo.ratings has ${ratings.length} entries but only '
          '${options.tasterCount} taster accounts exist — the extras would be '
          'silently dropped');
    }
    for (var i = 0; i < ratings.length; i++) {
      final v = ratings[i];
      if (v is! num || v < 0.5 || v > 5.0 || (v * 2) % 1 != 0) {
        _err(
          file,
          'demo.ratings[$i] must be 0.5-5.0 in half-star steps (got $v)',
        );
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
Set<String> stems(String input) => input
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
            for (final i
                in (g['ingredients'] as List).cast<Map<String, dynamic>>())
              {
                'quantity': i['quantity'],
                'unit': i['unit'],
                'name': i['name'],
                'note': i['note'],
                'is_optional': i['is_optional'] ?? false,
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
