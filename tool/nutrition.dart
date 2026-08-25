// tool/nutrition.dart — GEN: validate nutritionData/ and generate
// supabase/nutrition_foods.sql from foods.json + units.json.
//
// Usage (via melos):
//   melos run nutrition:validate   # parse + lint, write nothing
//   melos run nutrition:gen        # validate, then rewrite the .sql
//   melos run nutrition:check      # validate + fail if the .sql is stale (CI)
//
// Deliberately split from tool/fdc.dart (EXTRACT): this half reads the JSON
// alone — no CSV bundle in sight — so CI can check staleness offline, exactly
// like recipes:check. The generated SQL is committed; never hand-edit it.
//
// Precedence, restated from nutritionData/README.md: authored `per_100g`,
// `grams_per_ml`, and `portions` win over the machine-written `extracted`
// block — per whole map, per value, and per unit key respectively.

import 'dart:convert';
import 'dart:io';

const _foodsPath = 'nutritionData/foods.json';
const _unitsPath = 'nutritionData/units.json';
const _outPath = 'supabase/nutrition_foods.sql';

/// Dollar-quote tag for every string literal; the validator rejects content
/// containing it, so nothing needs escaping. Distinct from seed_recipes' $sr$.
const _tag = r'$nf$';

/// The registry's per-100 g columns — the label's 11 keys (CLAUDE.md, Phase 28)
/// in food-column order. `added_sugars_g` stays: always absent from FDC generic
/// foods, but an authored value is legal.
const _labelKeys = [
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
];

const _unitClasses = {'mass', 'volume', 'count'};

final _slugRe = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');

class _Fail {
  final errors = <String>[];
  final warnings = <String>[];
  void err(String m) => errors.add(m);
  void warn(String m) => warnings.add(m);
}

// ---------------------------------------------------------------------------
// Load + validate
// ---------------------------------------------------------------------------

({
  List<Map<String, dynamic>> foods,
  List<Map<String, dynamic>> units,
  _Fail log,
})
_load() {
  final log = _Fail();

  final foodsDoc =
      jsonDecode(File(_foodsPath).readAsStringSync()) as Map<String, dynamic>;
  final unitsDoc =
      jsonDecode(File(_unitsPath).readAsStringSync()) as Map<String, dynamic>;
  final foods = (foodsDoc['foods'] as List).cast<Map<String, dynamic>>();
  final units = (unitsDoc['units'] as List).cast<Map<String, dynamic>>();
  final unresolvable =
      ((unitsDoc['unresolvable'] as List?) ?? const []).cast<String>();

  // --- units.json -----------------------------------------------------------
  final unitKeys = <String>{};
  final spellings = <String>{};
  for (final u in units) {
    final key = u['key'] as String? ?? '';
    final klass = u['class'] as String? ?? '';
    if (!unitKeys.add(key)) log.err('units: duplicate key "$key"');
    if (!_unitClasses.contains(klass)) {
      log.err('units.$key: class must be one of $_unitClasses');
    }
    final factor = u['factor'];
    if (klass == 'count') {
      if (factor != null) log.err('units.$key: count units have factor null');
    } else if (factor is! num || factor <= 0) {
      log.err('units.$key: $klass unit needs a positive factor');
    }
    for (final s in (u['spellings'] as List? ?? const []).cast<String>()) {
      if (s != s.toLowerCase())
        log.err('units.$key: spelling "$s" not lowercase');
      if (!spellings.add(s)) log.err('units: duplicate spelling "$s"');
    }
  }
  for (final s in unresolvable) {
    if (spellings.contains(s)) {
      log.err('units: "$s" is both a spelling and unresolvable');
    }
  }

  // units.json strings are dollar-quoted too — same tag rule as the foods'.
  for (final u in units) {
    for (final s in [
      u['key'] as String? ?? '',
      u['class'] as String? ?? '',
      ...(u['spellings'] as List? ?? const []).cast<String>(),
    ]) {
      if (s.contains(_tag)) log.err('units: "$s" contains the $_tag quote tag');
    }
  }

  // --- foods.json -----------------------------------------------------------
  if (foods.isEmpty) {
    // The generator would otherwise emit `id not in ()` — invalid SQL that
    // only fails at apply time, in the middle of a db:reset.
    log.err('foods.json has no foods — the registry cannot be empty');
  }
  final slugs = <String>{};
  final aliases = <String>{};
  String? prevSlug;
  for (final f in foods) {
    final slug = f['slug'] as String? ?? '';
    final where = 'foods.$slug';
    if (!_slugRe.hasMatch(slug)) log.err('$where: slug not kebab-case');
    if (!slugs.add(slug)) log.err('$where: duplicate slug');
    if (prevSlug != null && slug.compareTo(prevSlug) < 0) {
      log.err(
        '$where: out of slug order (after $prevSlug) — keep the file sorted',
      );
    }
    prevSlug = slug;

    if ((f['display_name'] as String? ?? '').trim().isEmpty) {
      log.err('$where: display_name required');
    }

    for (final a in (f['aliases'] as List? ?? const []).cast<String>()) {
      if (a != a.toLowerCase()) log.err('$where: alias "$a" not lowercase');
      if (a.trim().isEmpty) log.err('$where: empty alias');
      if (!aliases.add(a))
        log.err('$where: alias "$a" duplicated across foods');
    }

    final merged = _merged(f);
    final per100 = merged.per100;
    if (per100.isEmpty) {
      log.err(
        '$where: no per-100 g values (run fdc:extract or author per_100g)',
      );
    }
    for (final e in per100.entries) {
      if (!_labelKeys.contains(e.key)) {
        log.err('$where: per_100g unknown field "${e.key}"');
      }
      if (e.value < 0) log.err('$where: per_100g.${e.key} negative');
    }
    if (per100.isNotEmpty && !per100.containsKey('calories')) {
      log.warn('$where: no calories value');
    }
    if (f['is_added_sugar'] == true && !per100.containsKey('total_sugars_g')) {
      log.warn('$where: is_added_sugar without total_sugars_g contributes 0');
    }

    final density = merged.gramsPerMl;
    if (density != null && density <= 0) log.err('$where: grams_per_ml <= 0');

    final seen = <String>{};
    for (final p in merged.portions) {
      final unit = p['unit'] as String? ?? '';
      final grams = p['grams'];
      if (!unitKeys.contains(unit)) {
        log.err('$where: portion unit "$unit" not in units.json');
      }
      if (!seen.add(unit)) log.err('$where: duplicate portion unit "$unit"');
      if (grams is! num || grams <= 0) {
        log.err('$where: portion $unit needs positive grams');
      }
    }

    // Everything the emitter dollar-quotes must be tag-free.
    for (final s in [
      slug,
      f['display_name'] as String? ?? '',
      ...(f['aliases'] as List? ?? const []).cast<String>(),
    ]) {
      if (s.contains(_tag)) log.err('$where: contains the $_tag quote tag');
    }
  }

  return (foods: foods, units: units, log: log);
}

/// Authored-over-extracted merge for one food. The single place precedence
/// lives; the emitter and the validator both go through it.
({
  Map<String, num> per100,
  num? gramsPerMl,
  List<Map<String, dynamic>> portions,
})
_merged(Map<String, dynamic> f) {
  final extracted = (f['extracted'] as Map<String, dynamic>?) ?? const {};

  final per100 = <String, num>{
    ...((f['per_100g'] ?? extracted['per_100g']) as Map<String, dynamic>? ??
            const {})
        .map((k, v) => MapEntry(k, v as num)),
  };

  final gramsPerMl = (f['grams_per_ml'] ?? extracted['grams_per_ml']) as num?;

  final authored =
      ((f['portions'] as List?) ?? const []).cast<Map<String, dynamic>>();
  final authoredUnits = {for (final p in authored) p['unit'] as String};
  final portions = [
    ...authored,
    for (final p
        in ((extracted['portions'] as List?) ?? const [])
            .cast<Map<String, dynamic>>())
      if (!authoredUnits.contains(p['unit'] as String)) p,
  ]..sort((a, b) => (a['unit'] as String).compareTo(b['unit'] as String));

  return (per100: per100, gramsPerMl: gramsPerMl, portions: portions);
}

// ---------------------------------------------------------------------------
// Generate
// ---------------------------------------------------------------------------

String _lit(String s) => '$_tag$s$_tag';
String _num(num? v) => v == null ? 'null' : '$v';

String _generate(
  List<Map<String, dynamic>> foods,
  List<Map<String, dynamic>> units,
) {
  final buf = StringBuffer('''
-- nutrition_foods.sql — GENERATED FILE. DO NOT EDIT BY HAND.
--
-- Source: nutritionData/{foods.json, units.json}  ·  Generator: tool/nutrition.dart
-- Regenerate with `melos run nutrition:gen`; `melos run nutrition:check`
-- fails if this file is stale.
--
-- DATA ONLY: the food / food_alias / food_portion / food_unit tables, their
-- RLS, grants, and the search_foods RPC live in supabase/migrations/0001_init.sql.
-- Idempotent: foods upsert by id and rows removed from the JSON are deleted
-- (ingredients.food_id — Phase 29b — is `on delete set null`, so retiring a
-- registry entry orphans links gracefully). Alias / portion / unit tables are
-- wiped and reloaded — they are leaves with no dependents.
-- Apply BEFORE seed_recipes.sql once 29b's FK exists; `melos run db:nutrition`
-- and config.toml's sql_paths both order it correctly.

-- Unit registry (from units.json). Spelling '' is the bare-count marker.
delete from food_unit;
insert into food_unit (spelling, unit_key, class, factor) values
''');

  final unitRows = <String>[];
  for (final u in units) {
    final key = u['key'] as String;
    final klass = u['class'] as String;
    final factor = u['factor'] as num?;
    for (final s in (u['spellings'] as List).cast<String>()) {
      unitRows.add(
        "  (${_lit(s)}, ${_lit(key)}, ${_lit(klass)}, ${_num(factor)})",
      );
    }
  }
  buf
    ..writeln('${unitRows.join(',\n')};')
    ..writeln();

  buf.writeln('-- The foods. ${foods.length} of them, ordered by slug.');
  for (final f in foods) {
    final slug = f['slug'] as String;
    final m = _merged(f);
    final p = m.per100;
    buf
      ..writeln('insert into food (id, display_name, fdc_id,')
      ..writeln('  calories, total_fat_g, saturated_fat_g, trans_fat_g,')
      ..writeln('  cholesterol_mg, sodium_mg, total_carbs_g, dietary_fiber_g,')
      ..writeln('  total_sugars_g, added_sugars_g, protein_g,')
      ..writeln('  grams_per_ml, is_added_sugar)')
      ..writeln(
        'values (${_lit(slug)}, ${_lit(f['display_name'] as String)}, '
        '${_num(f['fdc_id'] as num?)},',
      )
      ..writeln('  ${_labelKeys.map((k) => _num(p[k])).join(', ')},')
      ..writeln('  ${_num(m.gramsPerMl)}, ${f['is_added_sugar'] == true})')
      ..writeln('on conflict (id) do update set')
      ..writeln(
        '  display_name = excluded.display_name, fdc_id = excluded.fdc_id,',
      )
      ..writeln('  ${_labelKeys.map((k) => '$k = excluded.$k').join(', ')},')
      ..writeln('  grams_per_ml = excluded.grams_per_ml,')
      ..writeln('  is_added_sugar = excluded.is_added_sugar;');
  }

  buf.writeln('''

-- Remove foods no longer in the JSON, then reload the leaf tables.
delete from food where id not in (
${foods.map((f) => '  ${_lit(f['slug'] as String)}').join(',\n')}
);

delete from food_alias;
delete from food_portion;''');

  final aliasRows = <String>[];
  final portionRows = <String>[];
  for (final f in foods) {
    final slug = _lit(f['slug'] as String);
    for (final a in (f['aliases'] as List? ?? const []).cast<String>()) {
      aliasRows.add('  (${_lit(a)}, $slug)');
    }
    for (final p in _merged(f).portions) {
      portionRows.add('  ($slug, ${_lit(p['unit'] as String)}, ${p['grams']})');
    }
  }
  buf
    ..writeln('insert into food_alias (alias, food_id) values')
    ..writeln('${aliasRows.join(',\n')};')
    ..writeln()
    ..writeln('insert into food_portion (food_id, unit_key, grams) values')
    ..writeln('${portionRows.join(',\n')};')
    ..writeln()
    ..writeln(
      "do \$\$ begin raise notice "
      "'Food registry loaded (${foods.length} foods, "
      "${aliasRows.length} aliases, ${portionRows.length} portions)'; "
      'end \$\$;',
    );
  return buf.toString();
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

Future<void> main(List<String> args) async {
  final action = args.isEmpty ? 'help' : args.first;
  if (!const ['validate', 'gen', 'check'].contains(action)) {
    stdout.writeln('usage: dart run tool/nutrition.dart <validate|gen|check>');
    exit(action == 'help' ? 0 : 64);
  }

  final (:foods, :units, :log) = _load();
  for (final w in log.warnings) {
    stdout.writeln('  warning  $w');
  }
  for (final e in log.errors) {
    stderr.writeln('  error    $e');
  }
  if (log.errors.isNotEmpty) {
    stderr.writeln('✖ ${log.errors.length} error(s) in nutritionData/');
    exit(1);
  }
  stdout.writeln(
    '✔ ${foods.length} foods valid'
    '${log.warnings.isEmpty ? '' : ' (${log.warnings.length} warning(s))'}',
  );

  if (action == 'validate') return;

  final sql = _generate(foods, units);
  final out = File(_outPath);

  if (action == 'check') {
    final current = out.existsSync() ? out.readAsStringSync() : '';
    if (current.replaceAll('\r\n', '\n') != sql) {
      stderr.writeln('✖ $_outPath is stale — run `melos run nutrition:gen`');
      exit(1);
    }
    stdout.writeln('✔ $_outPath is up to date');
    return;
  }

  out.writeAsStringSync(sql);
  stdout.writeln('✔ wrote $_outPath (${sql.split('\n').length} lines)');
}
