// tool/sim.dart — validate everything the simulated population is authored from
// and generate the loaders that put it in the database.
//
// THREE sources, three generated files, one command each way:
//
//   simData/dishes/*.json  ->  supabase/sim/1_sim_dishes.sql   (the dish library)
//   simData/people.json    ->  supabase/sim/1_sim_people.sql   (name + bio pools)
//   simData/vocab.json     ->  supabase/sim/1_sim_vocab.sql    (tags + titles)
//
// Usage (via melos):
//   melos run sim:validate   # parse + lint + coverage, write nothing
//   melos run sim:gen        # validate, then rewrite all three .sql files
//   melos run sim:check      # validate + fail if ANY of them is stale (CI)
//
// The people and vocab pools replaced literal arrays that used to sit inside
// supabase/sim/2_sim_generate.sql. Moving them out is not tidying: content in a
// `do $$ declare v_given text[] := array[…]` block cannot be validated, cannot
// be diffed usefully, and cannot be extended without editing the generator that
// draws from it.
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

const _peoplePath = 'simData/people.json';
const _peopleOut = 'supabase/sim/1_sim_people.sql';

const _vocabPath = 'simData/vocab.json';
const _vocabOut = 'supabase/sim/1_sim_vocab.sql';

/// Dollar-quote tag for every literal in the generated SQL. Distinct from
/// recipes.dart's `$sr$` so the two files can never be confused when read side
/// by side; the validator rejects content containing it.
const _tag = r'$sd$';

/// The same idea for the two pool files. A name or a bio containing its file's
/// tag would close the literal early and leave SQL that parses as something
/// else, so [_checkTag] rejects one rather than escaping it — there is no
/// escaping inside a dollar-quoted string.
const _peopleTag = r'$sp$';
const _vocabTag = r'$sv$';

/// Not const: `foodSlugs` is read from nutritionData/foods.json (Phase 29b).
/// No dish carries a `food` link yet — linking simData is 29d's optional
/// curation — but the validator accepts the key now so promotion to
/// recipeData never has to strip it.
// `demo` needs no flag any more: engagement is never authored in EITHER
// directory since B113, so the validator refuses the key outright for both.
final _options = RecipeFormatOptions(
  allowSim: true,
  dollarTag: _tag,
  foodSlugs: loadFoodSlugs('nutritionData/foods.json'),
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
            errors.add(
              '${dish.file}: sim.variant_titles[$i] must be a '
              'non-empty string',
            );
          } else if (!t.contains('{title}')) {
            errors.add(
              '${dish.file}: sim.variant_titles[$i] must contain '
              '"{title}" — it is a template, not a title',
            );
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
    issues.add(
      '$where: no dish in ${missingCategories.length} categor'
      '${missingCategories.length == 1 ? 'y' : 'ies'} '
      '(${(missingCategories.toList()..sort()).join(', ')})',
    );
  }
  if (cuisines.length < _minCuisines) {
    issues.add(
      '$where: only ${cuisines.length} distinct cuisines, '
      'want at least $_minCuisines',
    );
  }
  if (difficulties.length < 3) {
    issues.add(
      '$where: difficulty spread is ${difficulties.length}/3 '
      '(${(difficulties.toList()..sort()).join(', ')})',
    );
  }
  if (noCook == 0) {
    issues.add(
      '$where: no no-cook dish (cook_minutes 0) — the detail screen '
      'renders a cook time of zero differently',
    );
  }
  if (overnight == 0) {
    issues.add(
      '$where: no dish with an unattended step over 8 hours — '
      'overnight timers are a distinct case (schema.json prep_minutes rule)',
    );
  }
  if (multiGroup == 0) {
    issues.add(
      '$where: no multi-group dish — grouped ingredients are the '
      'format\'s reason to exist (SDS §11.1)',
    );
  }
  if (maxServings < 8) {
    issues.add(
      '$where: largest dish serves $maxServings — the servings scaler '
      'needs a wide range to be worth testing',
    );
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
  final description =
      notes == null || notes.trim().isEmpty
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
    'ingredient_groups': normaliseIngredientGroups(
      r['ingredient_groups'] as List,
    ),
    'step_groups': normaliseStepGroups(r['step_groups'] as List),
    'weight': sim['weight'] ?? 1,
    'variant_titles': sim['variant_titles'] ?? const <String>[],
  };
}

String _generate(List<AuthoredRecipe> dishes) {
  final buf =
      StringBuffer()
        ..writeln('''
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
    ..writeln(
      "  raise notice 'Dish library loaded (% dishes)', "
      '(select count(*) from sim.dish);',
    )
    ..writeln('end \$notice\$;')
    ..writeln();
  return buf.toString();
}

// ---------------------------------------------------------------------------
// The two pool files
//
// simData/people.json and simData/vocab.json are validated and generated here
// rather than by a second script, because they answer to this file's contract:
// ONE command validates every source the simulated population is authored
// from, and one `sim:check` fails on any stale output. Three sources, three
// generated files, one gate.
//
// Every rule below is also stated in the matching `*.schema.json`. There is no
// JSON Schema library in the toolchain, so those documents are prose for a
// human and this code is the enforcement — they are two copies and they have
// to move together. That is the same bargain `recipeData/schema.json` makes.
// ---------------------------------------------------------------------------

/// Reads one authored JSON object, reporting a parse failure as a validation
/// error rather than an exception: a trailing comma in a pool file should read
/// like every other authoring mistake, not like a crashed tool.
Map<String, dynamic>? _loadJsonObject(String path, List<String> errors) {
  final file = File(path);
  if (!file.existsSync()) {
    errors.add('$path: missing');
    return null;
  }
  final Object? parsed;
  try {
    parsed = jsonDecode(file.readAsStringSync());
  } on FormatException catch (e) {
    errors.add('$path: not valid JSON — ${e.message}');
    return null;
  }
  if (parsed is! Map<String, dynamic>) {
    errors.add('$path: top level must be an object');
    return null;
  }
  return parsed;
}

/// `{...}` placeholders in an authored template.
///
/// Anything the generator does not substitute reaches a profile screen or a
/// recipe title as literal braces, so an unknown placeholder is an error here
/// rather than a curiosity in production.
final _placeholder = RegExp(r'\{([a-z_]+)\}');

void _checkPlaceholders(
  String what,
  String template,
  Set<String> allowed,
  List<String> errors,
) {
  for (final m in _placeholder.allMatches(template)) {
    final name = m.group(1)!;
    if (!allowed.contains(name)) {
      errors.add(
        '$what: unknown placeholder {$name} in "$template" '
        '(only ${allowed.map((a) => '{$a}').join(', ')} is substituted)',
      );
    }
  }
}

/// Rejects content that would close its file's dollar-quoted literal early.
/// There is no escaping inside a dollar-quoted string, so the only safe answer
/// is to refuse — silently mangling it would produce SQL that parses as
/// something else entirely.
void _checkTag(String what, String value, String tag, List<String> errors) {
  if (value.contains(tag)) {
    errors.add('$what: contains the SQL quote tag $tag — "$value"');
  }
}

List<String> _stringList(
  Object? value,
  String what,
  int minItems,
  List<String> errors,
) {
  if (value is! List) {
    errors.add('$what: must be an array');
    return const [];
  }
  final out = <String>[];
  for (var i = 0; i < value.length; i++) {
    final entry = value[i];
    if (entry is! String || entry.trim().isEmpty) {
      errors.add('$what[$i]: must be a non-empty string');
      continue;
    }
    out.add(entry);
  }
  if (out.length < minItems) {
    errors.add('$what: needs at least $minItems entries, found ${out.length}');
  }
  final seen = <String>{};
  for (final entry in out) {
    if (!seen.add(entry)) errors.add('$what: duplicate entry "$entry"');
  }
  return out;
}

void _checkKeys(
  String what,
  Map<String, dynamic> doc,
  Set<String> allowed,
  List<String> errors,
) {
  for (final key in doc.keys) {
    if (!allowed.contains(key)) errors.add('$what: unknown key "$key"');
  }
}

/// Keys every pool file may carry for the reader's benefit and the generator
/// ignores.
const _proseKeys = {r'$schema', 'note'};

final _localeCode = RegExp(r'^[a-z][a-z0-9-]*$');
final _tagName = RegExp(r'^[a-z0-9][a-z0-9-]*$');

/// One naming tradition, as the generator consumes it.
class _Locale {
  _Locale(this.code, this.label, this.cuisine, this.given, this.family);

  final String code;
  final String label;
  final String cuisine;
  final List<String> given;
  final List<String> family;
}

class _People {
  _People(this.locales, this.bios);

  final List<_Locale> locales;
  final List<String> bios;
}

class _VocabTag {
  _VocabTag(this.name, this.categories);

  final String name;
  final List<String> categories;
}

class _Vocab {
  _Vocab(this.tags, this.titleVariants);

  final List<_VocabTag> tags;
  final List<String> titleVariants;
}

_People? _validatePeople(List<String> errors) {
  final doc = _loadJsonObject(_peoplePath, errors);
  if (doc == null) return null;
  _checkKeys(_peoplePath, doc, {..._proseKeys, 'locales', 'bios'}, errors);

  final locales = <_Locale>[];
  final rawLocales = doc['locales'];
  if (rawLocales is! List) {
    errors.add('$_peoplePath: `locales` must be an array');
  } else {
    if (rawLocales.length < 8) {
      errors.add(
        '$_peoplePath: needs at least 8 locales, found ${rawLocales.length}',
      );
    }
    final codes = <String>{};
    for (var i = 0; i < rawLocales.length; i++) {
      final raw = rawLocales[i];
      final where = '$_peoplePath locales[$i]';
      if (raw is! Map<String, dynamic>) {
        errors.add('$where: must be an object');
        continue;
      }
      _checkKeys(where, raw, {
        'code',
        'label',
        'cuisine',
        'given',
        'family',
      }, errors);

      final code = raw['code'];
      if (code is! String || !_localeCode.hasMatch(code)) {
        errors.add('$where: `code` must match ${_localeCode.pattern}');
        continue;
      }
      if (!codes.add(code)) errors.add('$where: duplicate code "$code"');

      final label = raw['label'];
      final cuisine = raw['cuisine'];
      if (label is! String || label.trim().isEmpty) {
        errors.add('$where: `label` must be a non-empty string');
      }
      if (cuisine is! String || cuisine.trim().isEmpty) {
        errors.add('$where: `cuisine` must be a non-empty string');
      }

      final given = _stringList(raw['given'], '$where given', 8, errors);
      final family = _stringList(raw['family'], '$where family', 8, errors);
      for (final name in [
        ...given,
        ...family,
        if (cuisine is String) cuisine,
      ]) {
        _checkTag(where, name, _peopleTag, errors);
      }
      if (label is String && cuisine is String) {
        locales.add(_Locale(code, label, cuisine, given, family));
      }
    }
  }

  final bios = _stringList(doc['bios'], '$_peoplePath bios', 8, errors);
  for (final bio in bios) {
    _checkPlaceholders('$_peoplePath bios', bio, const {'cuisine'}, errors);
    _checkTag('$_peoplePath bios', bio, _peopleTag, errors);
  }

  return _People(locales, bios);
}

_Vocab? _validateVocab(List<String> errors) {
  final doc = _loadJsonObject(_vocabPath, errors);
  if (doc == null) return null;
  _checkKeys(_vocabPath, doc, {
    ..._proseKeys,
    'tags',
    'title_variants',
  }, errors);

  final tags = <_VocabTag>[];
  final rawTags = doc['tags'];
  if (rawTags is! List) {
    errors.add('$_vocabPath: `tags` must be an array');
  } else {
    if (rawTags.length < 20) {
      errors.add(
        '$_vocabPath: needs at least 20 tags, found ${rawTags.length}',
      );
    }
    final names = <String>{};
    for (var i = 0; i < rawTags.length; i++) {
      final raw = rawTags[i];
      final where = '$_vocabPath tags[$i]';
      if (raw is! Map<String, dynamic>) {
        errors.add('$where: must be an object');
        continue;
      }
      _checkKeys(where, raw, {'name', 'categories'}, errors);

      final name = raw['name'];
      if (name is! String || !_tagName.hasMatch(name) || name.length > 32) {
        errors.add(
          '$where: `name` must match ${_tagName.pattern} and be <= 32 chars',
        );
        continue;
      }
      if (!names.add(name)) errors.add('$where: duplicate tag "$name"');
      _checkTag(where, name, _vocabTag, errors);

      final categories = <String>[];
      final rawCategories = raw['categories'];
      if (rawCategories != null) {
        if (rawCategories is! List || rawCategories.isEmpty) {
          errors.add('$where: `categories` must be a non-empty array');
        } else {
          for (final c in rawCategories) {
            if (c is! String || !recipeCategories.contains(c)) {
              errors.add(
                '$where: unknown category "$c" '
                '(${recipeCategories.join(', ')})',
              );
              continue;
            }
            // A category listed twice is not harmful, but it is authoring
            // noise the generated array would carry into the database.
            if (categories.contains(c)) {
              errors.add('$where: duplicate category "$c"');
              continue;
            }
            categories.add(c);
          }
        }
      }
      tags.add(_VocabTag(name, categories));
    }
  }

  final variants = _stringList(
    doc['title_variants'],
    '$_vocabPath title_variants',
    8,
    errors,
  );
  for (final template in variants) {
    if (!template.contains('{title}')) {
      errors.add(
        '$_vocabPath title_variants: "$template" has no {title} — a template '
        'without it is a fixed title, and every recipe drawing it collides',
      );
    }
    _checkPlaceholders('$_vocabPath title_variants', template, const {
      'title',
    }, errors);
    _checkTag('$_vocabPath title_variants', template, _vocabTag, errors);
  }

  return _Vocab(tags, variants);
}

/// A dollar-quoted SQL literal. Safe only because the validators above refused
/// every value containing [tag].
String _lit(String value, String tag) => '$tag$value$tag';

String _generatePeople(_People people) {
  final buf =
      StringBuffer()
        ..writeln('''
-- 1_sim_people.sql — GENERATED FILE. DO NOT EDIT BY HAND.
--
-- Source: simData/people.json  ·  Generator: tool/sim.dart
-- Regenerate with `melos run sim:gen`; `melos run sim:check` fails if this
-- file is stale.
--
-- The name and bio pools every simulated profile is drawn from. Given and
-- family names are drawn from the SAME locale for one actor, so a generated
-- name reads as a name rather than a two-culture collage, and a bio's
-- `{cuisine}` is filled from that same locale.
--
-- These rows used to be `array[…]` literals inside 2_sim_generate.sql. Moving
-- them out is not tidying: content inside a `do \$\$ declare` block cannot be
-- validated, cannot be diffed usefully, and cannot be extended without editing
-- the generator that draws from it.
--
-- Everything lives in schema `sim`, never `public` (B026). Standalone and
-- idempotent: it declares its own tables with `if not exists` — 0_sim_schema
-- declares them too, and whichever runs first wins — upserts by natural key so
-- a content edit propagates, and deletes what the source file no longer has.
-- Contains no credentials and creates no accounts.

create schema if not exists sim;

create table if not exists sim.locale (
  code         text primary key,
  n            int  not null,
  label        text not null,
  cuisine      text not null,
  given_count  int  not null,
  family_count int  not null
);

create table if not exists sim.person_name (
  locale text not null,
  kind   text not null check (kind in ('given', 'family')),
  n      int  not null,
  name   text not null,
  primary key (locale, kind, n)
);

create table if not exists sim.bio (
  n        int primary key,
  template text not null
);

do \$grants\$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on schema sim from anon, authenticated';
    execute 'revoke all on all tables in schema sim from anon, authenticated';
  end if;
end \$grants\$;
''')
        ..writeln('-- ${'-' * 74}')
        ..writeln(
          '-- ${people.locales.length} locales. `n` is the dense 1..L draw '
          'index, so an actor picks',
        )
        ..writeln('-- a tradition with one sim.rand_int() and no scan.')
        ..writeln('-- ${'-' * 74}')
        ..writeln();

  for (var i = 0; i < people.locales.length; i++) {
    final l = people.locales[i];
    buf
      ..writeln(
        'insert into sim.locale (code, n, label, cuisine, given_count, '
        'family_count) values',
      )
      ..writeln(
        '  (${_lit(l.code, _peopleTag)}, ${i + 1}, '
        '${_lit(l.label, _peopleTag)}, ${_lit(l.cuisine, _peopleTag)}, '
        '${l.given.length}, ${l.family.length})',
      )
      ..writeln('on conflict (code) do update set')
      ..writeln('  n = excluded.n, label = excluded.label,')
      ..writeln('  cuisine = excluded.cuisine,')
      ..writeln('  given_count = excluded.given_count,')
      ..writeln('  family_count = excluded.family_count;')
      ..writeln();
  }

  buf
    ..writeln('-- ${'-' * 74}')
    ..writeln('-- The names, dense 1..count within each (locale, kind).')
    ..writeln('-- ${'-' * 74}');

  for (final l in people.locales) {
    for (final kind in const ['given', 'family']) {
      final names = kind == 'given' ? l.given : l.family;
      if (names.isEmpty) continue;
      buf
        ..writeln()
        ..writeln('-- ${l.label} (${l.code}) — $kind')
        ..writeln('insert into sim.person_name (locale, kind, n, name) values');
      for (var i = 0; i < names.length; i++) {
        final last = i == names.length - 1;
        buf.writeln(
          '  (${_lit(l.code, _peopleTag)}, ${_lit(kind, _peopleTag)}, '
          '${i + 1}, ${_lit(names[i], _peopleTag)})${last ? '' : ','}',
        );
      }
      buf.writeln(
        'on conflict (locale, kind, n) do update '
        'set name = excluded.name;',
      );
    }
  }

  buf
    ..writeln()
    ..writeln('-- ${'-' * 74}')
    ..writeln(
      '-- ${people.bios.length} bio templates. `{cuisine}` is the only '
      'placeholder the',
    )
    ..writeln('-- generator substitutes; the validator rejects any other.')
    ..writeln('-- ${'-' * 74}')
    ..writeln('insert into sim.bio (n, template) values');
  for (var i = 0; i < people.bios.length; i++) {
    final last = i == people.bios.length - 1;
    buf.writeln(
      '  (${i + 1}, ${_lit(people.bios[i], _peopleTag)})${last ? '' : ','}',
    );
  }
  buf.writeln('on conflict (n) do update set template = excluded.template;');

  final codes = people.locales
      .map((l) => _lit(l.code, _peopleTag))
      .join(',\n  ');
  buf
    ..writeln()
    ..writeln('-- What the source file no longer holds leaves the table. The')
    ..writeln('-- locales go first, so the orphan check below catches their')
    ..writeln('-- names; the rest is a length trim, because every pool is')
    ..writeln('-- dense from 1 and the upserts above have already rewritten')
    ..writeln('-- every row that survived.')
    ..writeln('delete from sim.locale where code <> all (array[')
    ..writeln('  $codes')
    ..writeln(']::text[]);')
    ..writeln()
    ..writeln('delete from sim.person_name p')
    ..writeln(
      'where not exists (select 1 from sim.locale l '
      'where l.code = p.locale)',
    )
    ..writeln('   or p.n > (')
    ..writeln('        select case when p.kind = \'given\' then l.given_count')
    ..writeln('                    else l.family_count end')
    ..writeln('        from sim.locale l where l.code = p.locale)')
    ..writeln('   or p.kind not in (\'given\', \'family\');')
    ..writeln()
    ..writeln('delete from sim.bio where n > ${people.bios.length};')
    ..writeln()
    ..writeln('do \$notice\$ begin')
    ..writeln(
      "  raise notice 'Name pools loaded (% locales, % names, % bios)',",
    )
    ..writeln('  (select count(*) from sim.locale),')
    ..writeln('  (select count(*) from sim.person_name),')
    ..writeln('  (select count(*) from sim.bio);')
    ..writeln('end \$notice\$;')
    ..writeln();
  return buf.toString();
}

String _generateVocab(_Vocab vocab) {
  final buf =
      StringBuffer()
        ..writeln('''
-- 1_sim_vocab.sql — GENERATED FILE. DO NOT EDIT BY HAND.
--
-- Source: simData/vocab.json  ·  Generator: tool/sim.dart
-- Regenerate with `melos run sim:gen`; `melos run sim:check` fails if this
-- file is stale.
--
-- Two pools, both indexed by rank:
--
--   sim.vocab_tag      ARRAY ORDER IS RANK. 2_sim_generate.sql draws a rank
--                      with sim.rand_zipf(), so the head lands on a large
--                      fraction of the population and the tail on one or two
--                      recipes. There is deliberately no `weight` column —
--                      two ways to say how common a tag is would drift apart.
--   sim.title_variant  the generic title templates, appended after a dish's
--                      own `variant_titles` and de-duplicated against them.
--                      Indexed by an owner's occurrence of that dish, which is
--                      what keeps `(owner_id, title)` unique (SDS §11.2, D4).
--
-- Everything lives in schema `sim`, never `public` (B026). Standalone and
-- idempotent: own tables with `if not exists`, upsert by rank, and a trim of
-- whatever the source file no longer holds.

create schema if not exists sim;

create table if not exists sim.vocab_tag (
  n          int primary key,
  name       text not null,
  categories text[] not null default '{}'
);

create table if not exists sim.title_variant (
  n        int primary key,
  template text not null
);

do \$grants\$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on schema sim from anon, authenticated';
    execute 'revoke all on all tables in schema sim from anon, authenticated';
  end if;
end \$grants\$;
''')
        ..writeln('-- ${'-' * 74}')
        ..writeln(
          '-- ${vocab.tags.length} tags, in rank order. An empty `categories`',
        )
        ..writeln('-- means the tag may land on any recipe.')
        ..writeln('-- ${'-' * 74}')
        ..writeln('insert into sim.vocab_tag (n, name, categories) values');
  for (var i = 0; i < vocab.tags.length; i++) {
    final tag = vocab.tags[i];
    final last = i == vocab.tags.length - 1;
    final categories =
        tag.categories.isEmpty
            ? "'{}'"
            : 'array[${tag.categories.map((c) => _lit(c, _vocabTag)).join(', ')}]';
    buf.writeln(
      '  (${i + 1}, ${_lit(tag.name, _vocabTag)}, $categories::text[])'
      '${last ? '' : ','}',
    );
  }
  buf
    ..writeln('on conflict (n) do update set')
    ..writeln('  name = excluded.name, categories = excluded.categories;')
    ..writeln()
    ..writeln('-- ${'-' * 74}')
    ..writeln('-- ${vocab.titleVariants.length} generic title templates.')
    ..writeln('-- ${'-' * 74}')
    ..writeln('insert into sim.title_variant (n, template) values');
  for (var i = 0; i < vocab.titleVariants.length; i++) {
    final last = i == vocab.titleVariants.length - 1;
    buf.writeln(
      '  (${i + 1}, ${_lit(vocab.titleVariants[i], _vocabTag)})'
      '${last ? '' : ','}',
    );
  }
  buf
    ..writeln('on conflict (n) do update set template = excluded.template;')
    ..writeln()
    ..writeln('-- Both pools are dense from 1, so a shorter source file is a')
    ..writeln('-- trim and the upserts above have rewritten the rest.')
    ..writeln('delete from sim.vocab_tag where n > ${vocab.tags.length};')
    ..writeln(
      'delete from sim.title_variant where n > ${vocab.titleVariants.length};',
    )
    ..writeln()
    ..writeln('do \$notice\$ begin')
    ..writeln("  raise notice 'Vocabulary loaded (% tags, % title variants)',")
    ..writeln('  (select count(*) from sim.vocab_tag),')
    ..writeln('  (select count(*) from sim.title_variant);')
    ..writeln('end \$notice\$;')
    ..writeln();
  return buf.toString();
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

/// Writes [sql] to [path] for `gen`, or compares it for `check`.
///
/// Returns false when `check` found a stale file. The comparison normalises
/// CRLF, because git checks these files out with native line endings on
/// Windows and the generator always emits `\n` — without it every check on
/// this machine fails and every check in CI passes.
bool _emit(String action, String path, String sql) {
  final out = File(path);
  out.parent.createSync(recursive: true);

  if (action == 'check') {
    final current = out.existsSync() ? out.readAsStringSync() : '';
    if (current.replaceAll('\r\n', '\n') != sql) {
      stderr.writeln('✖ $path is stale — run `melos run sim:gen`');
      return false;
    }
    stdout.writeln('✔ $path is up to date');
    return true;
  }

  out.writeAsStringSync(sql);
  stdout.writeln('✔ wrote $path (${sql.split('\n').length} lines)');
  return true;
}

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

  // All three sources are validated on every run, whichever action was asked
  // for: they are loaded into one database by one pipeline, and a tool that
  // reported the dish library green while the tag vocabulary was malformed
  // would be telling half the truth.
  final people = _validatePeople(errors);
  final vocab = _validateVocab(errors);

  for (final w in warnings) {
    stdout.writeln('  warning  $w');
  }
  for (final e in errors) {
    stderr.writeln('  error    $e');
  }
  if (errors.isNotEmpty) {
    stderr.writeln('✖ ${errors.length} error(s) in simData/');
    exit(1);
  }
  stdout.writeln(
    '✔ ${set.recipes.length} dishes valid'
    '${warnings.isEmpty ? '' : ' (${warnings.length} warning(s))'}',
  );
  stdout.writeln(
    '✔ ${people!.locales.length} locales, '
    '${people.locales.fold<int>(0, (n, l) => n + l.given.length + l.family.length)} names, '
    '${people.bios.length} bios valid',
  );
  stdout.writeln(
    '✔ ${vocab!.tags.length} tags, ${vocab.titleVariants.length} title '
    'variants valid',
  );

  if (action == 'validate') return;

  // Every file is emitted before anything exits, so `check` reports ALL the
  // stale ones in one run rather than one per invocation.
  final ok = [
    _emit(action, _outPath, _generate(set.recipes)),
    _emit(action, _peopleOut, _generatePeople(people)),
    _emit(action, _vocabOut, _generateVocab(vocab)),
  ];
  if (ok.contains(false)) exit(1);
}
