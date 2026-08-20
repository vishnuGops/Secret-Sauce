// tool/sim.dart — validate the simulation dish library in simData/dishes/ and
// generate supabase/sim/1_sim_dishes.sql from it.
//
// Usage (via melos):
//   melos run sim:validate   # parse + lint + coverage, write nothing
//   melos run sim:gen        # validate, then rewrite supabase/sim/1_sim_dishes.sql
//   melos run sim:check      # validate + fail if the .sql on disk is stale (CI)
//
// Same shape as tool/recipes.dart, and deliberately so — what counts as a valid
// recipe is defined once, in tool/recipe_format.dart, and shared by both. The
// difference is what each directory is FOR:
//
//   recipeData/  the Secret Sauce Kitchen's own recipes. Permanent content,
//                owned by one fixed account, carries `demo` engagement blocks.
//   simData/     an owner-agnostic LIBRARY. Nothing here is a recipe in the
//                database; supabase/sim/2_sim_generate.sql draws from it,
//                assigns an owner, applies a variant, and dates it. No `demo`
//                block — engagement is generated, never authored (docs/ROADMAP
//                Phase 24).
//
// A dish can be promoted into the curated set by moving the file and dropping
// its `sim` block, which is why the formats have to stay identical.

import 'dart:convert';
import 'dart:io';

// ignore: always_use_package_imports — `tool/` is loose scripts, not a package.
import 'recipe_format.dart';

const _dishesDir = 'simData/dishes';
const _outPath = 'supabase/sim/1_sim_dishes.sql';

/// Dollar-quote tag for every literal in the generated SQL. Distinct from
/// recipes.dart's `$sr$` so the two files can never be confused when read side
/// by side; the validator rejects content containing it.
const _tag = r'$sd$';

const _options = RecipeFormatOptions(
  allowDemo: false, // engagement is generated, never authored
  allowSim: true,
  dollarTag: _tag,
);

/// Keys allowed inside the optional `sim` block.
const _simKeys = {'weight', 'variant_titles'};

// ---------------------------------------------------------------------------
// Library-level rules
//
// These are properties of the DIRECTORY, not of one file, so they cannot live
// in recipe_format.dart. They exist because the generator's output is only as
// varied as its input: a library that is 90% mains produces a Discover page
// that is 90% mains, and no assertion downstream would notice.
// ---------------------------------------------------------------------------

/// Minimum distinct cuisines. The point of the library is breadth.
const _minCuisines = 24;

void _validateSimBlocks(List<AuthoredRecipe> dishes, List<String> errors) {
  for (final dish in dishes) {
    final sim = dish.json['sim'];
    if (sim == null) continue;
    if (sim is! Map<String, dynamic>) {
      errors.add('${dish.file}: sim must be an object');
      continue;
    }
    for (final key in sim.keys) {
      if (!_simKeys.contains(key)) {
        errors.add('${dish.file}: sim.$key is not a known field');
      }
    }
    final weight = sim['weight'];
    if (weight != null && (weight is! num || weight <= 0)) {
      errors.add('${dish.file}: sim.weight must be a positive number');
    }
    final variants = sim['variant_titles'];
    if (variants != null) {
      if (variants is! List) {
        errors.add('${dish.file}: sim.variant_titles must be an array');
      } else {
        for (var i = 0; i < variants.length; i++) {
          final t = variants[i];
          if (t is! String || t.trim().isEmpty) {
            errors.add('${dish.file}: sim.variant_titles[$i] must be a '
                'non-empty string');
          } else if (!t.contains('{title}')) {
            errors.add('${dish.file}: sim.variant_titles[$i] must contain '
                '"{title}" — it is a template, not a title');
          }
        }
      }
    }
  }
}

/// Coverage across the whole library. Reported as warnings while the library is
/// still being written (a partial batch legitimately misses categories) and as
/// errors once it is big enough that a gap is a mistake rather than a to-do.
void _validateCoverage(
  List<AuthoredRecipe> dishes,
  List<String> errors,
  List<String> warnings,
) {
  if (dishes.isEmpty) return;

  // Below this the library is still being authored in batches, so a missing
  // category is expected. Above it, a gap is a defect.
  const gateAt = 100;
  final issues = dishes.length >= gateAt ? errors : warnings;
  final where = 'simData/dishes';

  final categories = <String>{};
  final cuisines = <String>{};
  final difficulties = <String>{};
  var noCook = 0;
  var overnight = 0;
  var multiGroup = 0;
  var minServings = 1 << 30;
  var maxServings = 0;

  for (final dish in dishes) {
    final r = dish.json;
    final category = r['category'];
    if (category is String) categories.add(category);
    final cuisine = r['cuisine'];
    if (cuisine is String) cuisines.add(cuisine);
    final difficulty = r['difficulty'];
    if (difficulty is String) difficulties.add(difficulty);

    if (r['cook_minutes'] == 0) noCook++;
    final servings = r['servings'];
    if (servings is int) {
      if (servings < minServings) minServings = servings;
      if (servings > maxServings) maxServings = servings;
    }

    final igroups = r['ingredient_groups'];
    if (igroups is List && igroups.length > 1) multiGroup++;

    final sgroups = r['step_groups'];
    if (sgroups is List) {
      for (final g in sgroups) {
        if (g is! Map) continue;
        final steps = g['steps'];
        if (steps is! List) continue;
        for (final s in steps) {
          if (s is Map && s['duration_minutes'] is int) {
            if ((s['duration_minutes'] as int) > 480) overnight++;
          }
        }
      }
    }
  }

  final missingCategories = recipeCategories.difference(categories);
  if (missingCategories.isNotEmpty) {
    issues.add('$where: no dish in ${missingCategories.length} categor'
        '${missingCategories.length == 1 ? 'y' : 'ies'} '
        '(${(missingCategories.toList()..sort()).join(', ')})');
  }
  if (cuisines.length < _minCuisines) {
    issues.add('$where: only ${cuisines.length} distinct cuisines, '
        'want at least $_minCuisines');
  }
  if (difficulties.length < 3) {
    issues.add('$where: difficulty spread is ${difficulties.length}/3 '
        '(${(difficulties.toList()..sort()).join(', ')})');
  }
  if (noCook == 0) {
    issues.add('$where: no no-cook dish (cook_minutes 0) — the detail screen '
        'renders a cook time of zero differently');
  }
  if (overnight == 0) {
    issues.add('$where: no dish with an unattended step over 8 hours — '
        'overnight timers are a distinct case (schema.json prep_minutes rule)');
  }
  if (multiGroup == 0) {
    issues.add('$where: no multi-group dish — grouped ingredients are the '
        'format\'s reason to exist (SDS §11.1)');
  }
  if (maxServings < 8) {
    issues.add('$where: largest dish serves $maxServings — the servings scaler '
        'needs a wide range to be worth testing');
  }
}

// ---------------------------------------------------------------------------
// Generate
// ---------------------------------------------------------------------------

/// Compact, key-ordered JSON so the generated SQL only changes when a dish
/// does — `sim:check` compares text, not meaning.
String _json(Object? value) => '$_tag${jsonEncode(value)}$_tag';

/// The dish as the generator consumes it: content normalised the same way
/// seed_recipe_v2 receives it, plus the fields the generator needs to pick and
/// vary a dish. `slug` stays out of the document — it is the primary key.
Map<String, dynamic> _document(AuthoredRecipe dish) {
  final r = dish.json;
  final sim = (r['sim'] as Map<String, dynamic>?) ?? const {};
  final notes = r['notes'] as String?;
  // `recipes` has no notes column, so a dish-level note is appended to the
  // description exactly as tool/recipes.dart does it. Same lossy-but-lossless
  // compromise, same reason.
  final description = notes == null || notes.trim().isEmpty
      ? r['description'] as String
      : '${r['description']}\n\n$notes';

  return {
    'title': r['title'],
    'description': description,
    'cuisine': r['cuisine'],
    'category': r['category'],
    'difficulty': r['difficulty'],
    'prep_minutes': r['prep_minutes'],
    'cook_minutes': r['cook_minutes'],
    'servings': r['servings'],
    'attribution': r['attribution'],
    'ingredient_groups':
        normaliseIngredientGroups(r['ingredient_groups'] as List),
    'step_groups': normaliseStepGroups(r['step_groups'] as List),
    'weight': sim['weight'] ?? 1,
    'variant_titles': sim['variant_titles'] ?? const <String>[],
  };
}

String _generate(List<AuthoredRecipe> dishes) {
  final buf = StringBuffer()..writeln('''
-- 1_sim_dishes.sql — GENERATED FILE. DO NOT EDIT BY HAND.
--
-- Source: simData/dishes/*.json  ·  Generator: tool/sim.dart
-- Regenerate with `melos run sim:gen`; `melos run sim:check` fails if this
-- file is stale.
--
-- Loads the authored dish LIBRARY into sim.dish. Nothing here becomes a
-- `recipes` row on its own — supabase/sim/2_sim_generate.sql draws from this
-- table, assigns an owner, applies a variant, and dates it.
--
-- Everything lives in schema `sim`, never `public`. Supabase exposes `public`
-- to PostgREST, so a helper placed there becomes a callable RPC by default
-- (B026); a separate schema makes that impossible by construction rather than
-- by remembering a `revoke`.
--
-- Standalone and idempotent: creates its own schema and table, and upserts by
-- slug, so re-running pushes content edits (unlike seed_recipe_v2, which
-- returns early — this is a library, not user data, so overwriting is right).
-- Contains no credentials and creates no accounts.

create schema if not exists sim;

create table if not exists sim.dish (
  slug text primary key,
  doc  jsonb not null
);

-- Belt and braces. `sim` is not in Supabase's exposed schema list, so PostgREST
-- cannot see it anyway; this makes that explicit rather than inherited.
do \$grants\$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on schema sim from anon, authenticated';
    execute 'revoke all on all tables in schema sim from anon, authenticated';
  end if;
end \$grants\$;
''')
    ..writeln('-- ${'-' * 74}')
    ..writeln('-- The dishes. ${dishes.length} of them, ordered by slug.')
    ..writeln('-- ${'-' * 74}');

  for (final dish in dishes) {
    buf
      ..writeln()
      ..writeln('-- ${dish.file}')
      ..writeln('insert into sim.dish (slug, doc) values (')
      ..writeln('  $_tag${dish.slug}$_tag,')
      ..writeln('  ${_json(_document(dish))}::jsonb')
      ..writeln(') on conflict (slug) do update set doc = excluded.doc;');
  }

  // A dish deleted from the library must disappear from the table too,
  // otherwise the generator keeps drawing a recipe whose source file is gone.
  final slugs = dishes.map((d) => '$_tag${d.slug}$_tag').join(',\n  ');
  buf
    ..writeln()
    ..writeln('-- Dishes removed from the library are removed from the table.')
    ..writeln('delete from sim.dish where slug <> all (array[')
    ..writeln('  $slugs')
    ..writeln(']::text[]);')
    ..writeln()
    ..writeln('do \$notice\$ begin')
    ..writeln("  raise notice 'Dish library loaded (% dishes)', "
        '(select count(*) from sim.dish);')
    ..writeln('end \$notice\$;')
    ..writeln();
  return buf.toString();
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

Future<void> main(List<String> args) async {
  final action = args.isEmpty ? 'help' : args.first;
  if (!const ['validate', 'gen', 'check'].contains(action)) {
    stdout.writeln('usage: dart run tool/sim.dart <validate|gen|check>');
    exit(action == 'help' ? 0 : 64);
  }

  final set = loadAndValidate(_dishesDir, options: _options);
  final errors = [...set.errors];
  final warnings = [...set.warnings];
  _validateSimBlocks(set.recipes, errors);
  _validateCoverage(set.recipes, errors, warnings);

  for (final w in warnings) {
    stdout.writeln('  warning  $w');
  }
  for (final e in errors) {
    stderr.writeln('  error    $e');
  }
  if (errors.isNotEmpty) {
    stderr.writeln('✖ ${errors.length} error(s) in $_dishesDir');
    exit(1);
  }
  stdout.writeln('✔ ${set.recipes.length} dishes valid'
      '${warnings.isEmpty ? '' : ' (${warnings.length} warning(s))'}');

  if (action == 'validate') return;

  final sql = _generate(set.recipes);
  final out = File(_outPath);
  out.parent.createSync(recursive: true);

  if (action == 'check') {
    final current = out.existsSync() ? out.readAsStringSync() : '';
    if (current.replaceAll('\r\n', '\n') != sql) {
      stderr.writeln('✖ $_outPath is stale — run `melos run sim:gen`');
      exit(1);
    }
    stdout.writeln('✔ $_outPath is up to date');
    return;
  }

  out.writeAsStringSync(sql);
  stdout.writeln('✔ wrote $_outPath (${sql.split('\n').length} lines)');
}
