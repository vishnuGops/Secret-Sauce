// tool/recipes.dart — validate the authored recipes in recipeData/recipes/ and
// generate supabase/seed_recipes.sql from them.
//
// Usage (via melos):
//   melos run recipes:validate   # parse + lint, write nothing
//   melos run recipes:gen        # validate, then rewrite supabase/seed_recipes.sql
//   melos run recipes:check      # validate + fail if the .sql on disk is stale (CI)
//
// The generated SQL is committed. `recipes:check` is what stops it drifting from
// the JSON; without it a stale .sql would be applied to a database and nobody
// would notice, because the JSON is not read at runtime by anything.
//
// recipeData/schema.json documents the input format. It is NOT read here — the
// toolchain has no JSON Schema dependency — so a rule added there must be added
// to _validate() below as well.

import 'dart:convert';
import 'dart:io';

const _recipesDir = 'recipeData/recipes';
const _outPath = 'supabase/seed_recipes.sql';

/// Fixed id of the "Secret Sauce Kitchen" system account that owns every
/// curated recipe. Must match `supabase/seed.sql`, which bootstraps the same
/// account — both use `on conflict do nothing`, so either may run first.
const _ownerId = '00000000-0000-0000-0000-0000000000aa';

/// Dollar-quote tag for every string literal in the generated SQL. Chosen so
/// nothing has to be escaped; _validate() rejects content containing it.
const _tag = r'$sr$';

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

const _recipeKeys = {
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
  'demo',
};
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

final _errors = <String>[];
final _warnings = <String>[];

void _err(String where, String msg) => _errors.add('$where: $msg');
void _warn(String where, String msg) => _warnings.add('$where: $msg');

// ---------------------------------------------------------------------------
// Load + validate
// ---------------------------------------------------------------------------

/// Reads every recipe file, sorted by slug so the generated SQL is stable.
List<(String, Map<String, dynamic>)> _load() {
  final dir = Directory(_recipesDir);
  if (!dir.existsSync()) {
    stderr.writeln('Missing directory: $_recipesDir');
    exit(1);
  }
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final out = <(String, Map<String, dynamic>)>[];
  for (final file in files) {
    final name = file.uri.pathSegments.last;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map<String, dynamic>) {
        _err(name, 'top level must be an object, got ${decoded.runtimeType}');
        continue;
      }
      out.add((name, decoded));
    } on FormatException catch (e) {
      _err(name, 'invalid JSON — ${e.message}');
    }
  }
  return out;
}

void _validate(List<(String, Map<String, dynamic>)> recipes) {
  final titles = <String, String>{};

  for (final (file, r) in recipes) {
    final slug = file.substring(0, file.length - 5);

    for (final key in r.keys) {
      if (!_recipeKeys.contains(key)) _err(file, 'unknown field "$key"');
    }
    for (final key in const [
      'slug',
      'title',
      'description',
      'difficulty',
      'prep_minutes',
      'cook_minutes',
      'servings',
      'ingredient_groups',
      'step_groups',
    ]) {
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
    _validateDemo(file, r);
    _lintUnusedIngredients(file, r);

    // Every literal is dollar-quoted with _tag and never escaped, so the tag
    // appearing in content would terminate the literal early and produce SQL
    // that either fails to parse or, worse, parses as something else.
    _forEachString(r, (path, value) {
      if (value.contains(_tag)) _err(file, 'string at $path contains "$_tag"');
    });
  }
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
        if (!_ingredientKeys.contains(key))
          _err(file, '$iat unknown field "$key"');
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
  // seed_taster_ids() holds 8 accounts and seed_ratings() stops at the end of
  // the pool, so a 9th rating is silently dropped rather than applied.
  if (ratings.length > 8) {
    _err(
        file,
        'demo.ratings has ${ratings.length} entries but only 8 taster '
        'accounts exist — the extras would be silently dropped');
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

/// A step that sweeps up the rest of the list ("add all remaining ingredients").
/// Legitimate recipe writing, and it makes the unused-ingredient lint useless —
/// nearly everything is then "unmentioned".
final _catchAllStep = RegExp(
  r'\b(all|every|the rest of the|remaining)\b[^.]{0,40}\bingredients?\b',
  caseSensitive: false,
);

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
  final text = _stems(haystack.toString());

  for (final g in ingredientGroups) {
    if (g is! Map) continue;
    final items = g['ingredients'];
    if (items is! List) continue;
    for (final item in items) {
      if (item is! Map || item['name'] is! String) continue;
      final name = item['name'] as String;
      final tokens = _stems(name);
      if (tokens.isEmpty) continue;
      if (tokens.any(text.contains)) continue;
      _warn(file, 'ingredient "$name" is not mentioned by any step');
    }
  }
}

/// Lowercased word stems with stop words removed, so "limes" in the list
/// matches "lime juice" in a step.
///
/// Trailing "s" then trailing "e" are dropped, in that order — both sides go
/// through this, so what matters is that plural and singular land on the same
/// stem: limes -> lime -> lim and lime -> lim, tomatoes -> tomatoe -> tomato.
/// (Stripping "es" outright does not: it sends limes to "lim" but leaves lime
/// as "lime", so the pair no longer matches.)
Set<String> _stems(String input) => input
    .toLowerCase()
    .split(RegExp(r'[^a-zà-ÿ]+'))
    .where((w) => w.length > 2 && !_stopWords.contains(w))
    .map((w) => w.endsWith('s') ? w.substring(0, w.length - 1) : w)
    .map((w) => w.endsWith('e') ? w.substring(0, w.length - 1) : w)
    .where((w) => w.length > 2)
    .toSet();

/// Walks every string in the decoded JSON, reporting a JSON-pointer-ish path.
void _forEachString(
  Object? node,
  void Function(String path, String value) fn, [
  String path = '',
]) {
  if (node is String) {
    fn(path.isEmpty ? '<root>' : path, node);
  } else if (node is Map) {
    node.forEach((k, v) => _forEachString(v, fn, '$path.$k'));
  } else if (node is List) {
    for (var i = 0; i < node.length; i++) {
      _forEachString(node[i], fn, '$path[$i]');
    }
  }
}

// ---------------------------------------------------------------------------
// Generate
// ---------------------------------------------------------------------------

String _lit(Object? value) => value == null ? 'NULL' : '$_tag$value$_tag';

/// Compact, key-ordered JSON so the generated SQL only changes when the
/// recipe does — `recipes:check` compares text, not meaning.
String _json(Object? value) => '$_tag${jsonEncode(value)}$_tag::jsonb';

/// The ingredient/step arrays, normalised: every optional key made explicit so
/// the SQL helper never has to distinguish "absent" from "null".
List<Map<String, dynamic>> _normaliseIngredientGroups(List<dynamic> groups) => [
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

List<Map<String, dynamic>> _normaliseStepGroups(List<dynamic> groups) => [
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

const _rule =
    '-- ---------------------------------------------------------------------------';

String _header() => '''
-- seed_recipes.sql — GENERATED FILE. DO NOT EDIT BY HAND.
--
-- Source: recipeData/recipes/*.json  ·  Generator: tool/recipes.dart
-- Regenerate with `melos run recipes:gen`; `melos run recipes:check`
-- fails if this file is stale.
--
-- Standalone and idempotent: it bootstraps the Secret Sauce Kitchen
-- account itself, so it can be applied before or after supabase/seed.sql,
-- and survives that file being deleted when the demo data is retired.
-- Safe to paste into the hosted SQL editor. Contains no credentials —
-- the kitchen account gets a random password it is never signed in with
-- (B018: never put a literal credential in a file the README tells you
-- to run against production).
--
-- Re-running never edits an existing recipe: seed_recipe_v2 returns early
-- when (owner_id, title) already exists. To push a content change, delete
-- that recipe first — it is not an upsert.

create extension if not exists "pgcrypto";
''';

String _generate(List<(String, Map<String, dynamic>)> recipes) {
  final buf = StringBuffer()
    ..writeln(_header())
    ..writeln(_ownerBootstrap())
    ..writeln(_functionDdl())
    ..writeln()
    ..writeln(_rule)
    ..writeln('-- The recipes. ${recipes.length} of them, ordered by slug.')
    ..writeln(_rule)
    ..writeln('do \$seed\$')
    ..writeln('declare')
    ..writeln("  v_owner uuid := '$_ownerId';")
    ..writeln('begin');

  for (final (file, r) in recipes) {
    buf.write(_call(file, r));
  }

  final notice =
      "  raise notice 'Recipe seed complete (% authored recipes)', "
      '${recipes.length};';
  buf
    ..writeln(notice)
    ..writeln('end \$seed\$;')
    ..writeln();
  return buf.toString();
}

String _ownerBootstrap() => '''
-- The "Secret Sauce Kitchen" system account that owns every curated recipe, so
-- they never clutter a real user's "My Recipes". Same fixed id as
-- supabase/seed.sql uses; both inserts are conflict-guarded, so either file may
-- run first.
do \$owner\$
declare
  v_owner uuid := '$_ownerId';
begin
  insert into auth.users (
    instance_id, id, aud, role, email,
    encrypted_password, email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data,
    confirmation_token, recovery_token, email_change_token_new, email_change
  ) values (
    '00000000-0000-0000-0000-000000000000', v_owner, 'authenticated', 'authenticated',
    'kitchen@secretsauce.local', crypt(gen_random_uuid()::text, gen_salt('bf')),
    now(), now(), now(),
    '{"provider":"email","providers":["email"]}',
    '{"display_name":"Secret Sauce Kitchen"}',
    '', '', '', ''
  ) on conflict (id) do nothing;

  insert into profiles (id, display_name, bio)
  values (
    v_owner,
    'Secret Sauce Kitchen',
    'Curated classics from the Secret Sauce test kitchen.'
  )
  on conflict (id) do update
    set display_name = excluded.display_name, bio = excluded.bio;
end \$owner\$;
''';

String _functionDdl() => '''
-- ---------------------------------------------------------------------------
-- seed_recipe_v2 — insert a fully-structured recipe, groups and all.
--
-- Distinct from seed.sql's flat `seed_recipe`, which collapses everything into
-- one unnamed group. Both can coexist; neither overloads the other.
--
-- B024: `create or replace function` cannot change an argument list, so a
-- signature change leaves the OLD overload alive beside the new one and every
-- call then matches both (`42725 … is not unique`). Drops belong HERE, in the
-- file that recreates the function — drop.sql is a separate destructive script
-- that a plain re-apply never runs. There are no historical signatures to drop
-- yet; when this one changes, add its exact argument list below and keep every
-- earlier entry.
--
--   drop function if exists seed_recipe_v2(<the previous argument list>);
--
-- ---------------------------------------------------------------------------
create or replace function seed_recipe_v2(
  p_owner       uuid,
  p_title       text,
  p_description text,
  p_cuisine     text,
  p_category    text,
  p_difficulty  difficulty,
  p_prep        int,
  p_cook        int,
  p_servings    int,
  p_visibility  recipe_visibility,
  p_attribution text,
  p_ingredients jsonb,   -- [{"name":"Crust","ingredients":[{"quantity":1.25,"unit":"cup","name":"flour","note":null,"is_optional":false}]}]
  p_steps       jsonb,   -- [{"name":"Crust","steps":[{"text":"…","duration_minutes":60,"temperature":"350°F","tip":null}]}]
  p_likes       int   default 0,
  p_saves       int   default 0,
  p_views       int   default 0,
  p_ratings     jsonb default '[]'::jsonb
)
returns void
language plpgsql
as \$fn\$
declare
  v_recipe  uuid;
  v_group   uuid;
  v_grp     jsonb;
  v_item    jsonb;
  v_gidx    int;
  v_idx     int;
  v_version uuid;
begin
  select id into v_recipe from recipes where owner_id = p_owner and title = p_title;
  if v_recipe is not null then
    perform seed_recipe_v2_ratings(v_recipe, p_ratings);
    return;   -- content is left alone; this is not an upsert
  end if;

  insert into recipes (
    owner_id, title, description, cuisine, category, difficulty,
    prep_minutes, cook_minutes, servings, visibility, attribution,
    like_count, save_count, view_count
  ) values (
    p_owner, p_title, p_description, p_cuisine, p_category, p_difficulty,
    p_prep, p_cook, p_servings, p_visibility, p_attribution,
    p_likes, p_saves, p_views
  ) returning id into v_recipe;

  -- Groups and their children are numbered from 0 WITHIN each group, matching
  -- SupabaseRecipeRepository._persistContent. Numbering steps continuously
  -- across groups would work until the first edit re-persisted them per-group
  -- and silently renumbered every step (the B022 family of problem).
  v_gidx := 0;
  for v_grp in select * from jsonb_array_elements(p_ingredients) loop
    insert into ingredient_groups (recipe_id, name, sort_order)
    values (v_recipe, coalesce(v_grp ->> 'name', ''), v_gidx)
    returning id into v_group;

    v_idx := 0;
    for v_item in select * from jsonb_array_elements(coalesce(v_grp -> 'ingredients', '[]'::jsonb)) loop
      insert into ingredients (group_id, quantity, unit, name, note, is_optional, sort_order)
      values (
        v_group,
        (v_item ->> 'quantity')::numeric,
        v_item ->> 'unit',
        v_item ->> 'name',
        v_item ->> 'note',
        coalesce((v_item ->> 'is_optional')::boolean, false),
        v_idx
      );
      v_idx := v_idx + 1;
    end loop;
    v_gidx := v_gidx + 1;
  end loop;

  v_gidx := 0;
  for v_grp in select * from jsonb_array_elements(p_steps) loop
    insert into step_groups (recipe_id, name, sort_order)
    values (v_recipe, coalesce(v_grp ->> 'name', ''), v_gidx)
    returning id into v_group;

    v_idx := 0;
    for v_item in select * from jsonb_array_elements(coalesce(v_grp -> 'steps', '[]'::jsonb)) loop
      insert into steps (group_id, step_order, text, duration_minutes, temperature, tip, sort_order)
      values (
        v_group,
        v_idx,
        v_item ->> 'text',
        (v_item ->> 'duration_minutes')::int,
        v_item ->> 'temperature',
        v_item ->> 'tip',
        v_idx
      );
      v_idx := v_idx + 1;
    end loop;
    v_gidx := v_gidx + 1;
  end loop;

  perform seed_recipe_v2_ratings(v_recipe, p_ratings);

  insert into recipe_versions (recipe_id, version_number, author_id, change_summary, content_snapshot)
  values (v_recipe, 1, p_owner, 'Seeded recipe', '{}'::jsonb)
  returning id into v_version;

  update recipes set current_version_id = v_version where id = v_recipe;
end
\$fn\$;

-- Demo ratings are applied through supabase/seed.sql's taster accounts. That
-- file is scheduled for deletion, and this one has to keep working without it,
-- so the call is guarded on the helper still existing rather than declared as a
-- dependency. Also runs on the early-return path above, so a re-seed backfills
-- ratings onto already-seeded recipes (B014).
create or replace function seed_recipe_v2_ratings(p_recipe uuid, p_ratings jsonb)
returns void
language plpgsql
as \$fn\$
begin
  if p_ratings is null or jsonb_array_length(p_ratings) = 0 then
    return;
  end if;
  if to_regprocedure('seed_ratings(uuid, jsonb)') is null then
    raise notice 'seed_ratings() not present — skipping demo ratings for %', p_recipe;
    return;
  end if;
  execute 'select seed_ratings(\$1, \$2)' using p_recipe, p_ratings;
end
\$fn\$;

-- PostgREST exposes every function in `public` as an RPC, and both of these
-- write rows. Invoker-rights (so RLS still applies) AND execute revoked, per
-- the trigger-rights rule in CLAUDE.md.
do \$grants\$
begin
  execute 'revoke execute on function seed_recipe_v2(uuid, text, text, text, text, difficulty, int, int, int, recipe_visibility, text, jsonb, jsonb, int, int, int, jsonb) from public';
  execute 'revoke execute on function seed_recipe_v2_ratings(uuid, jsonb) from public';
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke execute on function seed_recipe_v2(uuid, text, text, text, text, difficulty, int, int, int, recipe_visibility, text, jsonb, jsonb, int, int, int, jsonb) from anon, authenticated';
    execute 'revoke execute on function seed_recipe_v2_ratings(uuid, jsonb) from anon, authenticated';
  end if;
end \$grants\$;
''';

String _call(String file, Map<String, dynamic> r) {
  final demo = (r['demo'] as Map<String, dynamic>?) ?? const {};
  final notes = r['notes'] as String?;
  // `recipes` has no notes column, so a recipe-level note is appended to the
  // description rather than dropped. A real column is the proper fix.
  final description = notes == null || notes.trim().isEmpty
      ? r['description'] as String
      : '${r['description']}\n\n$notes';

  final ingredients =
      _json(_normaliseIngredientGroups(r['ingredient_groups'] as List));
  final steps = _json(_normaliseStepGroups(r['step_groups'] as List));

  final buf = StringBuffer()
    ..writeln()
    ..writeln('  -- $file')
    ..writeln('  perform seed_recipe_v2(')
    ..writeln('    v_owner,')
    ..writeln('    ${_lit(r['title'])},')
    ..writeln('    ${_lit(description)},')
    ..writeln('    ${_lit(r['cuisine'])}, ${_lit(r['category'])}, '
        "'${r['difficulty']}',")
    ..writeln(
        '    ${r['prep_minutes']}, ${r['cook_minutes']}, ${r['servings']}, '
        "'${r['visibility'] ?? 'public'}',")
    ..writeln('    ${_lit(r['attribution'])},')
    ..writeln('    $ingredients,')
    ..writeln('    $steps,')
    ..writeln('    ${demo['like_count'] ?? 0}, ${demo['save_count'] ?? 0}, '
        '${demo['view_count'] ?? 0},')
    ..writeln('    ${_json(demo['ratings'] ?? const [])}')
    ..writeln('  );');
  return buf.toString();
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

Future<void> main(List<String> args) async {
  final action = args.isEmpty ? 'help' : args.first;
  if (!const ['validate', 'gen', 'check'].contains(action)) {
    stdout.writeln('usage: dart run tool/recipes.dart <validate|gen|check>');
    exit(action == 'help' ? 0 : 64);
  }

  final recipes = _load();
  _validate(recipes);

  for (final w in _warnings) {
    stdout.writeln('  warning  $w');
  }
  for (final e in _errors) {
    stderr.writeln('  error    $e');
  }
  if (_errors.isNotEmpty) {
    stderr.writeln('✖ ${_errors.length} error(s) in $_recipesDir');
    exit(1);
  }
  stdout.writeln('✔ ${recipes.length} recipes valid'
      '${_warnings.isEmpty ? '' : ' (${_warnings.length} warning(s))'}');

  if (action == 'validate') return;

  final sql = _generate(recipes);
  final out = File(_outPath);

  if (action == 'check') {
    final current = out.existsSync() ? out.readAsStringSync() : '';
    if (current.replaceAll('\r\n', '\n') != sql) {
      stderr.writeln('✖ $_outPath is stale — run `melos run recipes:gen`');
      exit(1);
    }
    stdout.writeln('✔ $_outPath is up to date');
    return;
  }

  out.writeAsStringSync(sql);
  stdout.writeln('✔ wrote $_outPath (${sql.split('\n').length} lines)');
}
