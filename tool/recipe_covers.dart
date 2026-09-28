// tool/recipe_covers.dart — generate a cover image for each of the Secret
// Sauce Kitchen's recipes (recipeData/recipes/*.json, top level only) with a
// Gemini image model, into recipeData/covers/.
//
// Usage (via melos):
//   melos run covers:gen                        # every recipe without a cover
//   melos run covers:gen -- --only=raspberry-brownies,tuna-fishcakes
//   melos run covers:gen -- --force             # regenerate even if present
//   melos run covers:gen -- --dry-run           # print the prompts; no key, no calls
//   melos run covers:gen -- --model=<id> --aspect=4:3 --size=2K
//   melos run covers:upload                     # put them in Storage (see below)
//
// The API key comes from $GEMINI_API_KEY, set by dot-sourcing the git-ignored
// gemini.local.ps1 (copy of gemini.example.ps1) — never a committed file, never
// a dart-define file (those are compiled into shipped builds, B034).
//
// What it writes:
//   recipeData/covers/<slug>.jpg     the cover, re-encoded (committed)
//   recipeData/covers/manifest.json  model, prompt and date per cover (committed)
//   recipeData/covers/_raw/<slug>.*  the model's original bytes (git-ignored)
//
// These are GENERATED illustrations, not photographs of anyone's cooking. The
// manifest is the provenance record, so a cover can always be traced back to
// the prompt and model that made it (DESIGN.md §2.2).
//
// Generating touches no database and no Storage. `--upload` is the separate
// step that does: every cover in the manifest goes to the `recipe-images`
// bucket at `ai/<slug>.jpg`, the key supabase/seed_recipes.sql points each
// recipe at (tool/recipes.dart). It targets SUPABASE_URL from
// apps/app/env.local.json — the same project the app is looking at — with the
// service-role key from $SUPABASE_SERVICE_ROLE_KEY (shell only: it bypasses
// every policy). Anything but the local stack also needs `--yes`.
//
// The prompt is built from the recipe itself — title, description, cuisine,
// category and its ingredient names — so the picture shows what the recipe
// makes rather than a generic dish of the same name.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

const _recipesDir = 'recipeData/recipes';
const _outDir = 'recipeData/covers';
const _rawDir = 'recipeData/covers/_raw';
const _manifestPath = 'recipeData/covers/manifest.json';

/// Default model — the newest non-preview image model the API listed on
/// 2026-09-27 (`gemini-2.5-flash-image`, `gemini-3.1-flash-image`,
/// `gemini-3-pro-image` …). Ids change often; override with `--model=`.
/// None of them has a free-tier quota: the key's project needs billing.
const _defaultModel = 'gemini-3.1-flash-image';

/// 4:3 is what the compact detail cover shows; the card band and the expanded
/// hero are wider and crop it with `BoxFit.cover`, centred — which is why the
/// prompt asks for margin around the dish.
const _defaultAspect = '4:3';

/// Longest edge written to recipeData/covers/. The expanded detail page tops
/// out at 1140px of content, so 2400 covers it at ~2× density; a larger model
/// output is scaled down, a smaller one is never scaled up.
const _maxEdge = 2400;
const _jpegQuality = 84;

/// Requested output resolution (`imageConfig.imageSize`). 1K came back at
/// 1200×896, soft on the 1140px expanded page at 2× density; 2K covers it.
const _defaultSize = '2K';

/// How many distinct ingredient names go into the prompt. Not the first ten:
/// a recipe that lists its sauce first (the teriyaki skewers' glaze) pushed
/// the pineapple itself past a cap of 10, and the prompt then told the model
/// to show "only these ingredients". Twenty covers every Kitchen recipe.
const _maxIngredients = 20;

/// Pause between calls, and the retry schedule for 429 / 5xx.
const _pause = Duration(seconds: 2);
const _retryDelays = [
  Duration(seconds: 10),
  Duration(seconds: 30),
  Duration(seconds: 60),
];

/// The Secret Sauce Kitchen house style — identical for every recipe, so the
/// covers read as one set. Everything a model would otherwise vary per dish
/// (surface, crockery, light, lens, grade) is pinned here; only the food
/// changes. Food only: a person, hands or text would all be inventions.
const _style = '''
Secret Sauce Kitchen house style — a premium editorial cookbook photograph.

Subject: the finished dish, one generous hero serving, plated with care and
ready to eat, as the recipe below describes it.

Set (identical for every image in this series): a warm cream travertine
surface with a faint natural texture; the dish on matte hand-thrown stoneware
in warm off-white or sand; a drink in clear, thin glassware of the kind its
recipe implies (served over ice → a short rocks glass), with no salt or sugar
rim unless salt or sugar for the rim is on the list. A food dish never has a
drink or an empty glass beside it — no water glass, no wine. One
folded natural linen napkin in soft terracotta at the edge of frame; at most
one other small prop — aged brass cutlery, or the dish's own hero ingredient
freshly cut (for example a halved lime, face up) if it is on the list below.
Nothing else: no scattered crumbs, no clutter, never more than these props.
The travertine fills the whole frame edge to edge: the camera looks down onto
the table, so its far edge is never in view, and the background is only the
same surface falling softly out of focus — no window, no wall, no room, no
horizon anywhere in the frame.

Light and camera: soft, diffused directional daylight from the upper left —
never a hard sun streak — with gentle, slightly deep, soft-edged shadows
falling to the lower right, giving a calm, quietly moody, high-end feel and a
subtle warm glow. Three-quarter view from about 35 degrees above the table,
85mm lens look, shallow depth of field (about f/2.8) with the front of the
dish tack-sharp and the background falling off softly.

Make it mouth-watering and true to life. Read the recipe's own description
of its texture (chunky, crisp, creamy, fluffy, charred …) and make that texture
the first thing the eye reads — distinct pieces rather than a uniform mass,
an irregular, freshly made surface. Glossy sauces that catch the light,
visible texture (crisp edges, a tender crumb, fresh herb leaves, flaky salt
where the recipe uses salt), gentle steam only if the dish is served hot —
a cold dish, a dip, a salad, a dessert or a drink shows no steam at all —
condensation on a cold glass. Natural colour with a warm, refined grade —
rich but never oversaturated, no HDR look, no plastic sheen.

Composition: dish slightly left of centre with generous empty cream margin
on every side, so it survives a crop to a wide banner or a near-square.

No text, no letters, no labels, no logos, no watermark, no hands, no people.''';

// ---------------------------------------------------------------------------

class _Recipe {
  _Recipe(this.slug, this.json);

  final String slug;
  final Map<String, dynamic> json;

  String get title => json['title'] as String;

  List<String> get ingredientNames {
    final seen = <String>{};
    final names = <String>[];
    for (final group in (json['ingredient_groups'] as List? ?? const [])) {
      for (final ing in ((group as Map)['ingredients'] as List? ?? const [])) {
        final name = ((ing as Map)['name'] as String?)?.trim();
        if (name == null || name.isEmpty) continue;
        if (seen.add(name.toLowerCase())) names.add(name);
      }
    }
    return names.take(_maxIngredients).toList();
  }

  String prompt() {
    final lines = <String>[
      _style,
      '',
      'The dish: ${json['title']}.',
      if (json['description'] case final String d when d.isNotEmpty) d,
      if (json['cuisine'] case final String c when c.isNotEmpty) 'Cuisine: $c.',
      if (json['category'] case final String c when c.isNotEmpty) 'Course: $c.',
      if (ingredientNames.isNotEmpty)
        'It is made with: ${ingredientNames.join(', ')}. Show only these '
            'ingredients — do not add garnishes or sides the recipe does not '
            'have.',
    ];
    return lines.join('\n');
  }
}

class _Args {
  Set<String>? only;
  bool force = false;
  bool dryRun = false;
  bool upload = false;
  bool yes = false;
  String model = _defaultModel;
  String aspect = _defaultAspect;
  String size = _defaultSize;
}

_Args _parse(List<String> argv) {
  final a = _Args();
  for (final arg in argv) {
    if (arg == '--force') {
      a.force = true;
    } else if (arg == '--dry-run') {
      a.dryRun = true;
    } else if (arg == '--upload') {
      a.upload = true;
    } else if (arg == '--yes') {
      a.yes = true;
    } else if (arg.startsWith('--only=')) {
      a.only = arg.substring(7).split(',').map((s) => s.trim()).toSet();
    } else if (arg.startsWith('--model=')) {
      a.model = arg.substring(8);
    } else if (arg.startsWith('--aspect=')) {
      a.aspect = arg.substring(9);
    } else if (arg.startsWith('--size=')) {
      a.size = arg.substring(7);
    } else {
      stderr.writeln('unknown argument: $arg');
      exit(64);
    }
  }
  return a;
}

List<_Recipe> _loadRecipes() {
  // Top level only: the subfolders hold other chefs' recipes, which the seed
  // generator does not read either (recipeData/README.md).
  final files =
      Directory(_recipesDir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return [
    for (final f in files)
      _Recipe(
        f.uri.pathSegments.last.replaceAll('.json', ''),
        jsonDecode(f.readAsStringSync()) as Map<String, dynamic>,
      ),
  ];
}

Map<String, dynamic> _readManifest() {
  final f = File(_manifestPath);
  if (!f.existsSync()) return {};
  return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
}

void _writeManifest(Map<String, dynamic> manifest) {
  final sorted = {
    for (final k in manifest.keys.toList()..sort()) k: manifest[k],
  };
  File(_manifestPath).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(sorted)}\n',
  );
}

/// One `generateContent` call. Returns the image bytes and their MIME type, or
/// throws with whatever the API said instead.
Future<(List<int>, String)> _generate(
  HttpClient http,
  String key,
  String model,
  String aspect,
  String size,
  String prompt,
) async {
  final uri = Uri.parse(
    'https://generativelanguage.googleapis.com/v1beta/models/'
    '$model:generateContent',
  );
  final body = jsonEncode({
    'contents': [
      {
        'parts': [
          {'text': prompt},
        ],
      },
    ],
    'generationConfig': {
      'responseModalities': ['IMAGE'],
      'imageConfig': {'aspectRatio': aspect, 'imageSize': size},
    },
  });

  for (var attempt = 0; ; attempt++) {
    final req = await http.postUrl(uri);
    req.headers
      ..contentType = ContentType.json
      // Header, not `?key=` — a query string ends up in proxy and error logs.
      ..set('x-goog-api-key', key);
    req.write(body);
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();

    if (res.statusCode != 200) {
      final error = _ApiError.parse(text);
      // A quota of **zero** is not a rate limit: the free tier grants image
      // models no requests at all, so waiting cannot help. Say so at once
      // instead of spending the whole retry schedule on it.
      if (res.statusCode == 429 && error.zeroQuota) {
        throw _FatalError(
          'this key has no quota for $model (free tier: limit 0). Image '
          'models need billing enabled on the key\'s Google Cloud project — '
          'https://aistudio.google.com/apikey → the project → Set up billing.',
        );
      }
      final retryable = res.statusCode == 429 || res.statusCode >= 500;
      if (retryable && attempt < _retryDelays.length) {
        // The API names its own wait (RetryInfo); prefer it to our schedule.
        final wait = error.retryDelay ?? _retryDelays[attempt];
        stdout.writeln(
          '    HTTP ${res.statusCode}; retrying in ${wait.inSeconds}s',
        );
        await Future<void>.delayed(wait);
        continue;
      }
      throw 'HTTP ${res.statusCode}: ${error.message ?? _short(text)}';
    }

    final json = jsonDecode(text) as Map<String, dynamic>;
    final candidates = json['candidates'] as List? ?? const [];
    if (candidates.isEmpty) {
      throw 'no candidates (promptFeedback: ${json['promptFeedback']})';
    }
    final candidate = candidates.first as Map<String, dynamic>;
    final parts = (candidate['content'] as Map?)?['parts'] as List? ?? const [];
    for (final part in parts.cast<Map<String, dynamic>>()) {
      // The REST API answers in camelCase; accept snake_case too.
      final inline = (part['inlineData'] ?? part['inline_data']) as Map?;
      if (inline == null) continue;
      final mime =
          (inline['mimeType'] ?? inline['mime_type']) as String? ?? 'image/png';
      return (base64Decode(inline['data'] as String), mime);
    }
    final said = parts
        .map((p) => (p as Map)['text'])
        .whereType<String>()
        .join(' ');
    throw 'no image returned (finishReason: ${candidate['finishReason']}'
        '${said.isEmpty ? '' : ', text: ${_short(said)}'})';
  }
}

String _short(String s) => s.length <= 300 ? s : '${s.substring(0, 300)}…';

/// An error that no other recipe in the run can get past (no quota, bad key),
/// so the loop stops rather than failing the same way fourteen times.
class _FatalError implements Exception {
  _FatalError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The parts of a Google API error body the retry decision needs.
class _ApiError {
  _ApiError({this.message, this.retryDelay, this.zeroQuota = false});

  factory _ApiError.parse(String body) {
    try {
      final error = (jsonDecode(body) as Map)['error'] as Map;
      final message = error['message'] as String?;
      Duration? delay;
      for (final d in (error['details'] as List? ?? const [])) {
        final detail = d as Map;
        if ('${detail['@type']}'.endsWith('RetryInfo')) {
          // "51.6s" — whole seconds, rounded up.
          final secs = double.tryParse(
            '${detail['retryDelay']}'.replaceAll('s', ''),
          );
          if (secs != null) delay = Duration(seconds: secs.ceil());
        }
      }
      return _ApiError(
        message: message,
        retryDelay: delay,
        zeroQuota: message?.contains('limit: 0') ?? false,
      );
    } catch (_) {
      return _ApiError();
    }
  }

  final String? message;
  final Duration? retryDelay;
  final bool zeroQuota;
}

/// Decode whatever the model returned, scale it down to [_maxEdge] if larger,
/// and re-encode as a baseline JPEG — a model PNG is several MB, the bucket
/// takes 5 MB at most, and every card would download it (BL-11).
List<int> _toJpeg(List<int> bytes) {
  final decoded = img.decodeImage(Uint8List.fromList(bytes));
  if (decoded == null) throw 'the returned image could not be decoded';
  var out = decoded;
  final edge = decoded.width > decoded.height ? decoded.width : decoded.height;
  if (edge > _maxEdge) {
    out =
        decoded.width >= decoded.height
            ? img.copyResize(
              decoded,
              width: _maxEdge,
              interpolation: img.Interpolation.cubic,
            )
            : img.copyResize(
              decoded,
              height: _maxEdge,
              interpolation: img.Interpolation.cubic,
            );
  }
  return img.encodeJpg(out, quality: _jpegQuality);
}

/// Put each listed recipe's cover (that the manifest records) in the
/// `recipe-images` bucket at `ai/<slug>.jpg`, overwriting. Idempotent.
Future<void> _upload(List<_Recipe> recipes, {required bool yes}) async {
  final env =
      jsonDecode(File('apps/app/env.local.json').readAsStringSync())
          as Map<String, dynamic>;
  final url = (env['SUPABASE_URL'] as String).replaceAll(RegExp(r'/$'), '');
  final key = Platform.environment['SUPABASE_SERVICE_ROLE_KEY'];
  if (key == null || key.isEmpty) {
    stderr.writeln(
      'SUPABASE_SERVICE_ROLE_KEY is not set. Local stack: the service_role key '
      'from `supabase status`; hosted: Dashboard → Project Settings → API. '
      r'Set it in this shell only ($env:SUPABASE_SERVICE_ROLE_KEY = "…").',
    );
    exit(64);
  }
  final local = RegExp(r'^http://(127\.0\.0\.1|localhost)').hasMatch(url);
  if (!local && !yes) {
    stderr.writeln(
      'refusing: apps/app/env.local.json points at $url, not the local stack. '
      'Re-run with --yes to upload there.',
    );
    exit(64);
  }

  final manifest = _readManifest();
  final http = HttpClient();
  var sent = 0;
  final failed = <String>[];
  try {
    for (final r in recipes) {
      final file = File('$_outDir/${r.slug}.jpg');
      if (!manifest.containsKey(r.slug) || !file.existsSync()) continue;
      final object = '${_bucket}/ai/${r.slug}.jpg';
      final req = await http.postUrl(
        Uri.parse('$url/storage/v1/object/$object'),
      );
      req.headers
        ..set('authorization', 'Bearer $key')
        ..set('apikey', key)
        ..set('x-upsert', 'true')
        ..set('cache-control', 'max-age=3600')
        ..contentType = ContentType('image', 'jpeg');
      req.add(file.readAsBytesSync());
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode == 200) {
        sent++;
        stdout.writeln('  ✔ ai/${r.slug}.jpg');
      } else {
        failed.add(r.slug);
        stderr.writeln(
          '  ✖ ai/${r.slug}.jpg — HTTP ${res.statusCode}: ${_short(body)}',
        );
      }
    }
  } finally {
    http.close();
  }
  stdout.writeln('\n$sent uploaded to $url, ${failed.length} failed');
  if (failed.isNotEmpty) exit(1);
}

/// The bucket every stored cover key lives in (core's `MediaUrl.bucket`).
const _bucket = 'recipe-images';

String _ext(String mime) => switch (mime) {
  'image/jpeg' => 'jpg',
  'image/webp' => 'webp',
  _ => 'png',
};

Future<void> main(List<String> argv) async {
  final args = _parse(argv);
  var recipes = _loadRecipes();
  if (args.only case final only?) {
    final unknown = only.difference(recipes.map((r) => r.slug).toSet());
    if (unknown.isNotEmpty) {
      stderr.writeln('no such recipe: ${unknown.join(', ')}');
      exit(64);
    }
    recipes = recipes.where((r) => only.contains(r.slug)).toList();
  }

  if (args.upload) {
    await _upload(recipes, yes: args.yes);
    return;
  }

  if (args.dryRun) {
    for (final r in recipes) {
      stdout
        ..writeln('=== ${r.slug}')
        ..writeln(r.prompt())
        ..writeln();
    }
    stdout.writeln('${recipes.length} prompt(s); nothing sent.');
    return;
  }

  final key = Platform.environment['GEMINI_API_KEY'];
  if (key == null || key.isEmpty) {
    stderr.writeln(
      r'GEMINI_API_KEY is not set. In PowerShell: $env:GEMINI_API_KEY = "…" '
      '(this shell only).',
    );
    exit(64);
  }

  Directory(_rawDir).createSync(recursive: true);
  final manifest = _readManifest();
  final http = HttpClient();
  var made = 0, skipped = 0;
  final failed = <String>[];

  try {
    for (final r in recipes) {
      final out = File('$_outDir/${r.slug}.jpg');
      if (out.existsSync() && !args.force) {
        skipped++;
        continue;
      }
      stdout.writeln('→ ${r.slug}');
      final prompt = r.prompt();
      try {
        final (bytes, mime) = await _generate(
          http,
          key,
          args.model,
          args.aspect,
          args.size,
          prompt,
        );
        File('$_rawDir/${r.slug}.${_ext(mime)}').writeAsBytesSync(bytes);
        final jpeg = _toJpeg(bytes);
        out.writeAsBytesSync(jpeg);
        manifest[r.slug] = {
          'title': r.title,
          'model': args.model,
          'aspect': args.aspect,
          'size': args.size,
          'generated_at': DateTime.now().toUtc().toIso8601String(),
          'bytes': jpeg.length,
          'prompt': prompt,
        };
        _writeManifest(manifest); // after each one, so an abort keeps the rest
        made++;
        stdout.writeln('    ${(jpeg.length / 1024).round()} KB → ${out.path}');
      } on _FatalError catch (e) {
        failed.add(r.slug);
        stderr.writeln('    STOPPED: $e');
        break;
      } catch (e) {
        failed.add(r.slug);
        stderr.writeln('    FAILED: $e');
      }
      await Future<void>.delayed(_pause);
    }
  } finally {
    http.close();
  }

  stdout.writeln(
    '\n$made generated, $skipped already present (use --force to redo), '
    '${failed.length} failed${failed.isEmpty ? '' : ': ${failed.join(', ')}'}',
  );
  if (failed.isNotEmpty) exit(1);
}
