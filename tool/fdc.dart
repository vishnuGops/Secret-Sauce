// tool/fdc.dart — EXTRACT: read the USDA FoodData Central CSV bundle and write
// per-100 g values + parsed portions into nutritionData/foods.json.
//
// Usage (via melos):
//   melos run fdc:extract -- --bundle="C:\path\to\FoodData_Central_csv_2026-04-30"
//
// The bundle (3.1 GB, public domain) is an AUTHORING-TIME input only — nothing
// in the repo, CI, or the app ever reads it. This tool's output is committed
// and human-reviewed, which is what lets the SR-Legacy portion parser below be
// imperfect: its mistakes surface in a readable diff, not in a label.
//
// What it writes: each food's `extracted` block — machine-owned; hand edits to
// it are lost on the next run. Authored fields (`grams_per_ml`, `portions`,
// `is_added_sugar`, notes) live at the entry's top level and are never touched.
//
// Nutrient ids (measured on the 2026-04-30 bundle before Phase 29 was planned):
// total sugars is 2000 (NOT the deprecated 1063), added sugars (1235) has zero
// generic rows and is never read, energy falls back 1008 -> 2047 -> 2048.

import 'dart:convert';
import 'dart:io';

const _foodsPath = 'nutritionData/foods.json';
const _unitsPath = 'nutritionData/units.json';

/// Label field -> FDC nutrient id. Energy is handled separately (fallbacks).
const _nutrientIds = <String, int>{
  'protein_g': 1003,
  'total_fat_g': 1004,
  'total_carbs_g': 1005,
  'sodium_mg': 1093,
  'saturated_fat_g': 1258,
  'trans_fat_g': 1257,
  'cholesterol_mg': 1253,
  'dietary_fiber_g': 1079,
  'total_sugars_g': 2000,
};

/// kcal, in preference order: 1008 (Atwater specific) is the SR-Legacy staple;
/// Foundation foods often carry only 2047/2048.
const _energyIds = [1008, 2047, 2048];

// ---------------------------------------------------------------------------
// Minimal quote-aware CSV
// ---------------------------------------------------------------------------

/// Splits one CSV line. Handles quoted fields with doubled quotes; the FDC
/// files carry no embedded newlines in the tables this tool reads.
List<String> _csv(String line) {
  final fields = <String>[];
  final buf = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < line.length && line[i + 1] == '"') {
          buf.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        buf.write(c);
      }
    } else if (c == '"') {
      inQuotes = true;
    } else if (c == ',') {
      fields.add(buf.toString());
      buf.clear();
    } else {
      buf.write(c);
    }
  }
  fields.add(buf.toString());
  return fields;
}

Stream<List<String>> _rows(String path) async* {
  final lines = File(
    path,
  ).openRead().transform(utf8.decoder).transform(const LineSplitter());
  var first = true;
  await for (final line in lines) {
    if (first) {
      first = false; // header
      continue;
    }
    if (line.isEmpty) continue;
    yield _csv(line);
  }
}

// ---------------------------------------------------------------------------
// Portion parsing
// ---------------------------------------------------------------------------

/// SR Legacy hides the real unit in the free-text `modifier` column
/// (`measure_unit_id` 9999): `cup, chopped`, `tbsp`, `medium (2-1/2" dia)`,
/// `fruit, without skin and seed`, `pie crust`. This normalizes one modifier to
/// a canonical portion key, or null when it should be skipped.
///
/// `eachWords` are food-specific: the tokens of the food's own display name
/// (so `leek`, `pepper`, `eggplant`, `pie crust` parse as "one of the food").
String? _portionKey(
  String modifier,
  Map<String, String> unitBySpelling,
  Set<String> eachWords,
) {
  var m = modifier.toLowerCase().trim();
  // Strip parentheticals: 'medium (2-1/2" dia)' -> 'medium'.
  m = m.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();
  // First comma-segment: 'cup, chopped' -> 'cup'.
  m = m.split(',').first.trim();
  if (m.isEmpty) return null;

  String? tryToken(String t) {
    final canonical = unitBySpelling[t];
    // Mass portions are pointless (mass units convert directly).
    if (canonical != null && canonical != 'g') return canonical;
    if (const {'each', 'whole', 'fruit'}.contains(t)) return 'each';
    if (const {
      'medium',
      'large',
      'small',
      'extra large',
      'jumbo',
    }.contains(t)) {
      return 'size:$t';
    }
    if (eachWords.contains(_singular(t))) return 'each';
    return null;
  }

  final whole = tryToken(m);
  if (whole != null) return whole;
  // 'tbsp chopped', 'cup chips' — retry on the first word alone.
  final firstWord = m.split(RegExp(r'\s+')).first;
  return tryToken(firstWord);
}

String _singular(String w) =>
    w.endsWith('es') && w.length > 3 && !w.endsWith('oes')
        ? w.substring(0, w.length - 1)
        : (w.endsWith('s') && w.length > 2 ? w.substring(0, w.length - 1) : w);

num _round2(num v) => (v * 100).round() / 100;

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

Future<void> main(List<String> args) async {
  String? bundle;
  for (final a in args) {
    if (a.startsWith('--bundle=')) bundle = a.substring('--bundle='.length);
  }
  if (args.isEmpty || bundle == null || bundle.isEmpty) {
    stdout.writeln(
      'usage: dart run tool/fdc.dart --bundle="<path to FoodData_Central_csv_*>"',
    );
    exit(64);
  }
  // The zip unpacks to a same-named inner directory; accept either level.
  var dir = Directory(bundle);
  if (!File('${dir.path}/food_nutrient.csv').existsSync()) {
    final inner = Directory(
      '${dir.path}/${dir.uri.pathSegments.where((s) => s.isNotEmpty).last}',
    );
    if (File('${inner.path}/food_nutrient.csv').existsSync()) dir = inner;
  }
  if (!File('${dir.path}/food_nutrient.csv').existsSync()) {
    stderr.writeln('✖ $bundle does not contain food_nutrient.csv');
    exit(1);
  }
  final source = dir.uri.pathSegments.where((s) => s.isNotEmpty).last;

  final foodsFile = File(_foodsPath);
  final doc = jsonDecode(foodsFile.readAsStringSync()) as Map<String, dynamic>;
  final foods = (doc['foods'] as List).cast<Map<String, dynamic>>();

  final unitsDoc =
      jsonDecode(File(_unitsPath).readAsStringSync()) as Map<String, dynamic>;
  final unitBySpelling = <String, String>{};
  for (final u in (unitsDoc['units'] as List).cast<Map<String, dynamic>>()) {
    for (final s in (u['spellings'] as List).cast<String>()) {
      if (s.isNotEmpty) unitBySpelling[s] = u['key'] as String;
    }
  }

  final wanted = <int, Map<String, dynamic>>{
    for (final f in foods)
      if (f['fdc_id'] != null) f['fdc_id'] as int: f,
  };
  final noId = foods.where((f) => f['fdc_id'] == null).length;
  final shared = foods.length - noId - wanted.length;
  stdout.writeln(
    '▶ extracting ${wanted.length} foods from $source'
    '${noId == 0 ? '' : ' ($noId entries have no fdc_id)'}'
    '${shared == 0 ? '' : ' ($shared entries share another entry\'s fdc_id)'}',
  );

  // --- nutrients: one streaming pass over the 1.7 GB file -------------------
  final nutrients = <int, Map<int, double>>{}; // fdc_id -> nutrient_id -> amt
  await for (final row in _rows('${dir.path}/food_nutrient.csv')) {
    final fdcId = int.tryParse(row[1]);
    if (fdcId == null || !wanted.containsKey(fdcId)) continue;
    final nutrientId = int.tryParse(row[2]);
    final amount = double.tryParse(row[3]);
    if (nutrientId == null || amount == null) continue;
    (nutrients[fdcId] ??= {})[nutrientId] = amount;
  }

  // --- measure units (Foundation portions use real ids, SR uses 9999) ------
  final measureNames = <String, String>{};
  await for (final row in _rows('${dir.path}/measure_unit.csv')) {
    measureNames[row[0]] = row[1];
  }

  // --- portions -------------------------------------------------------------
  // fdc_id -> canonical key -> (grams, from), first row (seq order) wins.
  final portions = <int, Map<String, (num, String)>>{};
  await for (final row in _rows('${dir.path}/food_portion.csv')) {
    final fdcId = int.tryParse(row[1]);
    if (fdcId == null || !wanted.containsKey(fdcId)) continue;
    final amount = double.tryParse(row[3]) ?? 1.0;
    final grams = double.tryParse(row[7]);
    if (grams == null || grams <= 0 || amount <= 0) continue;

    final food = wanted[fdcId]!;
    final eachWords = <String>{
      for (final w in '${food['display_name']} ${food['slug']}'
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z\s-]'), ' ')
          .split(RegExp(r'[\s-]+')))
        if (w.length > 2) _singular(w),
    };
    // The whole pre-parenthetical modifier too, for 'pie crust'.
    final modifier = row[6];
    final measureId = row[4];
    String? key;
    if (measureId != '9999' && measureNames.containsKey(measureId)) {
      key = _portionKey(measureNames[measureId]!, unitBySpelling, eachWords);
    } else {
      final wholePhrase =
          modifier
              .toLowerCase()
              .replaceAll(RegExp(r'\s*\([^)]*\)'), '')
              .split(',')
              .first
              .trim();
      if (eachWords.length > 1 &&
          wholePhrase == food['display_name'].toString().toLowerCase()) {
        key = 'each';
      }
      key ??= _portionKey(modifier, unitBySpelling, eachWords);
    }
    if (key == null) continue;
    final per = _round2(grams / amount);
    (portions[fdcId] ??= {}).putIfAbsent(key, () => (per, modifier));
  }

  // --- write back -----------------------------------------------------------
  var warned = 0;
  for (final food in foods) {
    final fdcId = food['fdc_id'] as int?;
    if (fdcId == null) continue;
    final n = nutrients[fdcId];
    if (n == null) {
      stderr.writeln(
        '  warning  ${food['slug']}: fdc $fdcId has no nutrient rows',
      );
      warned++;
      continue;
    }

    final per100 = <String, num>{};
    for (final id in _energyIds) {
      if (n.containsKey(id)) {
        per100['calories'] = _round2(n[id]!);
        break;
      }
    }
    _nutrientIds.forEach((field, id) {
      if (n.containsKey(id)) per100[field] = _round2(n[id]!);
    });
    if (per100.length < 8) {
      stdout.writeln(
        '  warning  ${food['slug']}: only ${per100.length}/10 fields present',
      );
      warned++;
    }

    final p = portions[fdcId] ?? {};
    // 'each' fallback: medium beats large beats small (an egg is 'large' by
    // baking convention, so large first would be tempting — but produce rows
    // define medium as the typical unit, and eggs carry their own large row
    // that authored data can override).
    if (!p.containsKey('each')) {
      for (final size in const ['size:medium', 'size:large', 'size:small']) {
        if (p.containsKey(size)) {
          p['each'] = p[size]!;
          break;
        }
      }
    }
    p.removeWhere((k, _) => k.startsWith('size:'));

    final extractedPortions = [
      for (final e in p.entries)
        {'unit': e.key, 'grams': e.value.$1, 'from': e.value.$2},
    ]..sort((a, b) => (a['unit']! as String).compareTo(b['unit']! as String));

    final extracted = <String, dynamic>{
      'source': source,
      'per_100g': per100,
      if (extractedPortions.isNotEmpty) 'portions': extractedPortions,
    };

    // Derived density, unless authored. Priority: the larger the measured
    // volume, the smaller the relative measurement error.
    if (food['grams_per_ml'] == null) {
      const volume = {
        'cup': 236.588,
        'fl-oz': 29.5735,
        'tbsp': 14.7868,
        'tsp': 4.92892,
      };
      for (final e in volume.entries) {
        final row = p[e.key];
        if (row != null) {
          extracted['grams_per_ml'] = _round2(row.$1 / e.value);
          extracted['grams_per_ml_from'] = e.key;
          break;
        }
      }
    }

    food['extracted'] = extracted;
  }

  const encoder = JsonEncoder.withIndent('  ');
  foodsFile.writeAsStringSync('${encoder.convert(doc)}\n');
  stdout.writeln(
    '✔ wrote $_foodsPath (${wanted.length} foods extracted'
    '${warned == 0 ? '' : ', $warned warning(s)'})',
  );
}
