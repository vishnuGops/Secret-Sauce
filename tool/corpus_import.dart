// corpus_import.dart — the scraped corpus into the database (Phase 35c).
//
// This tool is a **JSON transformer and nothing else**. Every rule about what
// an import may write lives in `import_recipe(jsonb)` in
// `supabase/migrations/0001_init.sql`, next to the constraints that enforce it:
// the blocklist check, the idempotency key, the quality score, the deliberate
// omission of the publisher's prose. The same split `tool/recipes.dart` uses
// with `seed_recipe_v2`, and for the same reason — a rule written in Dart is a
// rule the database cannot see.
//
// Usage:
//
//   dart run tool/corpus_import.dart plan                 # what would be imported
//   dart run tool/corpus_import.dart plan --tier=all
//   dart run tool/corpus_import.dart gen --limit=20000    # -> corpus/_import/*.sql
//
// Applying the generated files is deliberately a separate, manual step. They
// are ordinary SQL and go through the documented psql path (see CLAUDE.md's
// "DB tasks" note — `psql` is not installed on the development machine, so the
// container form is the one that works):
//
//   docker cp corpus/_import/0001.sql supabase_db_secret-sauce:/tmp/i.sql
//   docker exec supabase_db_secret-sauce \
//     psql -U postgres -d postgres -v ON_ERROR_STOP=1 -1 -f /tmp/i.sql
//
// Nothing here connects to a database. That is not a limitation — it is what
// makes the transform testable offline and keeps a tool that reads 8.6 GB of
// scraped data away from anything holding a superuser credential (Gotcha 7).
import 'dart:convert';
import 'dart:io';

/// Sources whose `language` is set to anything other than English are excluded
/// from the default tier.
///
/// The owner's decision (2026-09-12) was a curated **English-first** tier, and
/// this is the whole of what that means mechanically. It is not squeamishness
/// about other languages: `recipe_search_tsv` hard-codes
/// `to_tsvector('english', …)`, so a Korean or Italian recipe imported today
/// would index as near-noise and be unfindable by the one surface that would
/// otherwise reach it. Importing them is a schema change (a `language` column
/// and a `regconfig` parameter) plus a re-index of every row, so it is a tier
/// decision rather than a filter to relax.
///
/// 484 of 592 sources leave `language` null — English blogs, overwhelmingly —
/// and 99 say `en` explicitly.
bool _isEnglishSource(Map<String, dynamic> source) {
  final lang = source['language'] as String?;
  return lang == null || lang.toLowerCase().startsWith('en');
}

/// The bar a capture has to clear to be worth a row.
///
/// Deliberately about the **record**, not the food: does it have a picture, a
/// serving count, a plausible number of ingredients and more than one step.
/// A capture that fails these is usually a parse fault or a category page that
/// looked like a recipe, and 558k rows is far more than enough to be choosy.
///
/// `import_recipe` scores the same dimensions into `quality_score`; this is the
/// floor, that is the ordering. They are separate on purpose — raising the bar
/// here changes what is imported, raising it there changes only what sorts
/// first.
class Gate {
  const Gate({
    this.requireCover = true,
    this.requireServings = true,
    this.minIngredients = 3,
    this.minSteps = 2,
  });

  final bool requireCover;
  final bool requireServings;
  final int minIngredients;
  final int minSteps;

  /// Everything the corpus holds, for a `--tier=all` plan. Still refuses a
  /// record with no ingredients or no steps, because `import_recipe` would
  /// decline it anyway and counting it here would overstate the tier.
  static const all = Gate(
    requireCover: false,
    requireServings: false,
    minIngredients: 1,
    minSteps: 1,
  );
}

class Stats {
  int seen = 0;
  int kept = 0;
  int noCover = 0;
  int noServings = 0;
  int thin = 0;
  int noUrl = 0;
  final Map<String, int> perSource = {};
}

void main(List<String> args) {
  final command = args.isEmpty ? '' : args.first;
  final flags = <String, String>{};
  for (final arg in args.skip(1)) {
    final m = RegExp(r'^--([a-z-]+)(?:=(.*))?$').firstMatch(arg);
    if (m == null) _die('unrecognised argument: $arg');
    flags[m.group(1)!] = m.group(2) ?? 'true';
  }

  final tier = flags['tier'] ?? 'english';
  if (tier != 'english' && tier != 'all') {
    _die('--tier must be `english` or `all` (got "$tier")');
  }
  final gate = tier == 'all' ? Gate.all : const Gate();
  final limit = int.tryParse(flags['limit'] ?? '') ?? 0;
  final perSource = int.tryParse(flags['per-source'] ?? '') ?? 0;
  final batchSize = int.tryParse(flags['batch'] ?? '') ?? 500;
  final outDir = flags['out'] ?? 'corpus/_import';

  switch (command) {
    case 'plan':
      _run(tier: tier, gate: gate, limit: limit, perSource: perSource);
    case 'gen':
      _run(
        tier: tier,
        gate: gate,
        limit: limit,
        perSource: perSource,
        outDir: outDir,
        batchSize: batchSize,
      );
    default:
      stderr.writeln(
        'usage: dart run tool/corpus_import.dart <plan|gen> '
        '[--tier=english|all] [--limit=N] [--per-source=N] '
        '[--batch=N] [--out=DIR]',
      );
      exit(64);
  }
}

Never _die(String message) {
  stderr.writeln('✖ $message');
  exit(1);
}

void _run({
  required String tier,
  required Gate gate,
  required int limit,
  required int perSource,
  String? outDir,
  int batchSize = 500,
}) {
  final registry = File('corpus/sources.json');
  if (!registry.existsSync()) {
    _die('corpus/sources.json not found — run this from the repository root');
  }

  final sources =
      (jsonDecode(registry.readAsStringSync())
              as Map<String, dynamic>)['sources']
          as List<dynamic>;

  final eligible = <Map<String, dynamic>>[
    for (final s in sources.cast<Map<String, dynamic>>())
      if (tier == 'all' || _isEnglishSource(s)) s,
  ];

  final stats = Stats();
  final out = _BatchWriter(outDir, batchSize);

  // Breadth-first across sources, exactly as the harvester is: taking the first
  // 20,000 recipes in file order would import four community giants and call it
  // a corpus. `--per-source` is the cap that makes a tier wide rather than deep.
  for (final source in eligible) {
    final slug = source['slug'] as String?;
    if (slug == null) continue;
    final shard = File('corpus/recipes/$slug.jsonl');
    if (!shard.existsSync()) continue;

    var takenHere = 0;
    for (final line in shard.readAsLinesSync()) {
      if (line.trim().isEmpty) continue;
      if (limit > 0 && stats.kept >= limit) break;
      if (perSource > 0 && takenHere >= perSource) break;

      stats.seen++;
      final Map<String, dynamic> record;
      try {
        record = jsonDecode(line) as Map<String, dynamic>;
      } on FormatException {
        // A shard is append-only and a kill mid-write can leave a partial last
        // line. Skipping it is right; failing the whole import is not.
        continue;
      }

      final doc = _toImportDoc(record, source, gate, stats);
      if (doc == null) continue;

      stats.kept++;
      takenHere++;
      stats.perSource[slug] = (stats.perSource[slug] ?? 0) + 1;
      out.add(doc);
    }
    if (limit > 0 && stats.kept >= limit) break;
  }

  out.close();
  _report(tier, stats, out);
}

/// One corpus record → one `import_recipe` document, or null when it does not
/// clear [gate].
Map<String, dynamic>? _toImportDoc(
  Map<String, dynamic> record,
  Map<String, dynamic> source,
  Gate gate,
  Stats stats,
) {
  final src = record['source'] as Map<String, dynamic>? ?? const {};
  final url = (src['finalUrl'] ?? src['sourceUrl']) as String?;
  final title = (record['title'] as String?)?.trim();
  if (url == null || url.isEmpty || title == null || title.isEmpty) {
    stats.noUrl++;
    return null;
  }

  final ingredientGroups = _ingredientGroups(record);
  final stepGroups = _stepGroups(record);
  final ingredientCount = ingredientGroups.fold<int>(
    0,
    (n, g) => n + (g['ingredients'] as List).length,
  );
  final stepCount = stepGroups.fold<int>(
    0,
    (n, g) => n + (g['steps'] as List).length,
  );
  if (ingredientCount < gate.minIngredients || stepCount < gate.minSteps) {
    stats.thin++;
    return null;
  }

  final media = record['media'] as Map<String, dynamic>? ?? const {};
  final covers = (media['coverImages'] as List<dynamic>? ?? const []);
  final cover = covers.isEmpty ? null : covers.first as String?;
  if (gate.requireCover && (cover == null || cover.isEmpty)) {
    stats.noCover++;
    return null;
  }

  final servings =
      (record['yield'] as Map<String, dynamic>?)?['servings'] as int?;
  if (gate.requireServings && (servings == null || servings <= 0)) {
    stats.noServings++;
    return null;
  }

  final timing = record['timing'] as Map<String, dynamic>? ?? const {};
  final prep = timing['prepMinutes'] as int? ?? 0;
  var cook = timing['cookMinutes'] as int? ?? 0;
  if (prep == 0 && cook == 0) {
    // A page that states only a total is common, and dropping the number
    // entirely would cost the card its time chip for no reason. Attributing it
    // to cooking rather than splitting it invents less.
    cook = timing['totalMinutes'] as int? ?? 0;
  }

  final entity = record['entity'] as Map<String, dynamic>? ?? const {};
  final attribution =
      record['attribution'] as Map<String, dynamic>? ?? const {};

  return {
    'source_url': url,
    // Only when it actually parses. A scraped `datePublished` is whatever the
    // page's attribute held, and across 21,000 records that includes
    // `Thu, 01/06/2022 - 15:47`. `import_recipe` defends against this too; the
    // filter is here as well because an unknown date is better represented by
    // its absence than by a string the database has to reject.
    'published_at': _isoOrNull(src['datePublished']),
    'entity_slug': entity['slug'] ?? source['slug'],
    'entity_name': entity['name'] ?? source['name'],
    'entity_kind': _entityKind(
      entity['kind'] as String? ?? source['kind'] as String?,
    ),
    'entity_homepage': entity['homepage'] ?? source['homepage'],
    'entity_country': entity['country'] ?? source['country'],
    // The person named on the page, never inferred from the publisher — the
    // two are recorded separately in the corpus for exactly this reason, and
    // `import_recipe` credits the publisher alone when this is null.
    'chef_name': attribution['chef'],
    'title': title,
    // `description` is deliberately absent. The captured one is the
    // publisher's editorial writing, which the rights position links rather
    // than reproduces (Phase 35a), and leaving it out of the document is
    // stronger than trusting every future caller to drop it.
    'cover_image_url': cover,
    'cuisine': _first(record['cuisine']),
    'category': _first(record['category']),
    'servings': servings,
    'prep_minutes': prep,
    'cook_minutes': cook,
    'ingredient_groups': ingredientGroups,
    'step_groups': stepGroups,
  };
}

/// `entity.kind` in the corpus is already the vocabulary the `entity_kind` enum
/// uses, with one exception: a personal blog is `chef` there and `chef_site`
/// here, because `chef` in this schema is a person and an entity is not one.
String _entityKind(String? kind) => switch (kind) {
  'restaurant' => 'restaurant',
  'brand' => 'brand',
  'community' => 'community',
  'chef' => 'chef_site',
  _ => 'publication',
};

String? _isoOrNull(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  return DateTime.tryParse(value.trim()) == null ? null : value.trim();
}

String? _first(Object? value) {
  if (value is List && value.isNotEmpty) {
    final v = value.first;
    return v is String && v.trim().isNotEmpty ? v.trim() : null;
  }
  if (value is String && value.trim().isNotEmpty) return value.trim();
  return null;
}

List<Map<String, dynamic>> _ingredientGroups(Map<String, dynamic> record) {
  final groups = record['ingredientGroups'] as List<dynamic>? ?? const [];
  final out = <Map<String, dynamic>>[];
  for (final g in groups.cast<Map<String, dynamic>>()) {
    final items =
        (g['items'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
    final ingredients = <Map<String, dynamic>>[];
    for (final i in items) {
      final name = (i['name'] as String?)?.trim();
      // A line the parser could not name is a line a cook cannot read. The raw
      // text is the fallback rather than dropping the ingredient, because a
      // recipe missing an ingredient is worse than one with an unparsed line.
      final display =
          (name == null || name.isEmpty) ? (i['raw'] as String?)?.trim() : name;
      if (display == null || display.isEmpty) continue;
      ingredients.add({
        'quantity': i['quantity'],
        'unit': i['unit'],
        'name': display,
        'note': i['note'],
        'is_optional': i['isOptional'] ?? false,
      });
    }
    if (ingredients.isEmpty) continue;
    out.add({'name': (g['name'] as String?) ?? '', 'ingredients': ingredients});
  }
  return out;
}

/// The corpus stores steps flat, with a `stepGroup` label on each; the schema
/// stores them grouped. Grouping preserves first-appearance order rather than
/// sorting, because a page's section order is part of the method.
List<Map<String, dynamic>> _stepGroups(Map<String, dynamic> record) {
  final steps =
      (record['steps'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
  final order = <String>[];
  final byGroup = <String, List<Map<String, dynamic>>>{};

  for (final s in steps) {
    final text = (s['text'] as String?)?.trim();
    if (text == null || text.isEmpty) continue;
    final group = (s['stepGroup'] as String?)?.trim() ?? '';
    if (!byGroup.containsKey(group)) {
      byGroup[group] = [];
      order.add(group);
    }
    byGroup[group]!.add({
      'text': text,
      'image_url': s['imageUrl'],
      'duration_minutes': s['durationMinutes'],
      'temperature': s['temperature'],
      'tip': s['tip'],
    });
  }

  return [
    for (final g in order) {'name': g, 'steps': byGroup[g]!},
  ];
}

/// Writes `select import_recipe(...)` calls in fixed-size batches.
///
/// One file per batch, because a single 20,000-call script is one transaction
/// the size of the import: a failure at row 19,000 rolls back all of it, and
/// `psql -1` per file is the granularity that makes a resume mean something.
/// The idempotency key does the rest — re-running a file that already applied
/// inserts nothing.
class _BatchWriter {
  _BatchWriter(this.dir, this.batchSize);

  final String? dir;
  final int batchSize;

  int files = 0;
  final List<String> _buffer = [];

  void add(Map<String, dynamic> doc) {
    if (dir == null) return; // `plan` counts without writing.

    final json = jsonEncode(doc);
    // Dollar-quoting, so nothing in a scraped string needs escaping — and the
    // tag is checked rather than assumed, because a recipe page containing the
    // literal `$ci$` would otherwise end the quote early and turn the rest of
    // the document into SQL. Vanishingly unlikely; trivially checkable.
    var tag = 'ci';
    while (json.contains('\$$tag\$')) {
      tag = '${tag}x';
    }
    _buffer.add('select import_recipe(\$$tag\$$json\$$tag\$::jsonb);');
    if (_buffer.length >= batchSize) close();
  }

  /// Buffered and written synchronously rather than streamed through an
  /// `IOSink`: a batch is a few hundred calls and a few megabytes, and the
  /// async sink has to be awaited before the next file opens — which this tool
  /// has no `await` to do it in, and which fails as
  /// `StreamSink is bound to a stream` rather than as anything legible.
  void close() {
    if (dir == null || _buffer.isEmpty) return;
    files++;
    final directory = Directory(dir!)..createSync(recursive: true);
    final file = File(
      '${directory.path}/${files.toString().padLeft(4, '0')}.sql',
    );
    final header = [
      '-- GENERATED by tool/corpus_import.dart — do not hand-edit.',
      '-- Idempotent: re-applying inserts nothing (Phase 35c).',
      r'\set ON_ERROR_STOP on',
    ];
    file.writeAsStringSync('${[...header, ..._buffer].join('\n')}\n');
    _buffer.clear();
  }
}

void _report(String tier, Stats stats, _BatchWriter out) {
  final sources = stats.perSource.length;
  stdout.writeln('tier            $tier');
  stdout.writeln('records scanned ${stats.seen}');
  stdout.writeln('would import    ${stats.kept}  from $sources source(s)');
  stdout.writeln('skipped:');
  stdout.writeln('  no url/title  ${stats.noUrl}');
  stdout.writeln('  no cover      ${stats.noCover}');
  stdout.writeln('  no servings   ${stats.noServings}');
  stdout.writeln('  too thin      ${stats.thin}');
  if (out.files > 0) {
    stdout.writeln('wrote           ${out.files} batch file(s) to ${out.dir}');
  }

  final top =
      stats.perSource.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
  if (top.isNotEmpty) {
    stdout.writeln('largest sources:');
    for (final e in top.take(8)) {
      stdout.writeln('  ${e.value.toString().padLeft(7)}  ${e.key}');
    }
  }
}
