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
// What counts as a valid recipe lives in tool/recipe_format.dart, shared with
// tool/sim.dart so the two authored-recipe directories cannot drift apart. This
// file is only the recipeData -> SQL emitter.
//
// recipeData/schema.json documents the input format. It is NOT read here — the
// toolchain has no JSON Schema dependency — so a rule added there must be added
// to tool/recipe_format.dart as well.

import 'dart:convert';
import 'dart:io';

// ignore: always_use_package_imports — `tool/` is loose scripts, not a package.
import 'recipe_format.dart';

const _recipesDir = 'recipeData/recipes';
const _outPath = 'supabase/seed_recipes.sql';

/// Fixed id of the "Secret Sauce Kitchen" system account that owns every
/// curated recipe. Must match `supabase/seed.sql`, which bootstraps the same
/// account — both use `on conflict do nothing`, so either may run first.
const _ownerId = '00000000-0000-0000-0000-0000000000aa';

/// Dollar-quote tag for every string literal in the generated SQL. Chosen so
/// nothing has to be escaped; the validator rejects content containing it.
const _tag = r'$sr$';

/// recipeData carries `demo` blocks and reaches seed.sql's 8 taster accounts.
const _options = RecipeFormatOptions(
  allowDemo: true,
  tasterCount: 8,
  dollarTag: _tag,
);

// ---------------------------------------------------------------------------
// Generate
// ---------------------------------------------------------------------------

String _lit(Object? value) => value == null ? 'NULL' : '$_tag$value$_tag';

/// Compact, key-ordered JSON so the generated SQL only changes when the
/// recipe does — `recipes:check` compares text, not meaning.
String _json(Object? value) => '$_tag${jsonEncode(value)}$_tag::jsonb';

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

String _generate(List<AuthoredRecipe> recipes) {
  final buf =
      StringBuffer()
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

  for (final recipe in recipes) {
    buf.write(_call(recipe));
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
-- that a plain re-apply never runs. Add each outgoing argument list below and
-- keep every earlier entry.
--
-- Phase 28 appended `p_nutrition jsonb`, so the 17-argument form is dropped
-- here. Without this line the upgrade path (old seed already applied, new file
-- layered on top — CLAUDE.md Gotcha 6) dies with `42725 … is not unique` while
-- a fresh reset and a re-apply both stay green.
drop function if exists seed_recipe_v2(uuid, text, text, text, text, difficulty, int, int, int, recipe_visibility, text, jsonb, jsonb, int, int, int, jsonb);
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
  p_ratings     jsonb default '[]'::jsonb,
  -- Appended LAST and defaulted, so an existing call site that predates it
  -- still compiles. Per-serving label; null for a recipe with no data.
  p_nutrition   jsonb default null
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
    like_count, save_count, view_count, nutrition
  ) values (
    p_owner, p_title, p_description, p_cuisine, p_category, p_difficulty,
    p_prep, p_cook, p_servings, p_visibility, p_attribution,
    p_likes, p_saves, p_views, p_nutrition
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
  execute 'revoke execute on function seed_recipe_v2(uuid, text, text, text, text, difficulty, int, int, int, recipe_visibility, text, jsonb, jsonb, int, int, int, jsonb, jsonb) from public';
  execute 'revoke execute on function seed_recipe_v2_ratings(uuid, jsonb) from public';
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke execute on function seed_recipe_v2(uuid, text, text, text, text, difficulty, int, int, int, recipe_visibility, text, jsonb, jsonb, int, int, int, jsonb, jsonb) from anon, authenticated';
    execute 'revoke execute on function seed_recipe_v2_ratings(uuid, jsonb) from anon, authenticated';
  end if;
end \$grants\$;
''';

String _call(AuthoredRecipe recipe) {
  final r = recipe.json;
  final demo = (r['demo'] as Map<String, dynamic>?) ?? const {};
  final notes = r['notes'] as String?;
  // `recipes` has no notes column, so a recipe-level note is appended to the
  // description rather than dropped. A real column is the proper fix.
  final description =
      notes == null || notes.trim().isEmpty
          ? r['description'] as String
          : '${r['description']}\n\n$notes';

  final ingredients = _json(
    normaliseIngredientGroups(r['ingredient_groups'] as List),
  );
  final steps = _json(normaliseStepGroups(r['step_groups'] as List));

  final buf =
      StringBuffer()
        ..writeln()
        ..writeln('  -- ${recipe.file}')
        ..writeln('  perform seed_recipe_v2(')
        ..writeln('    v_owner,')
        ..writeln('    ${_lit(r['title'])},')
        ..writeln('    ${_lit(description)},')
        ..writeln(
          '    ${_lit(r['cuisine'])}, ${_lit(r['category'])}, '
          "'${r['difficulty']}',",
        )
        ..writeln(
          '    ${r['prep_minutes']}, ${r['cook_minutes']}, ${r['servings']}, '
          "'${r['visibility'] ?? 'public'}',",
        )
        ..writeln('    ${_lit(r['attribution'])},')
        ..writeln('    $ingredients,')
        ..writeln('    $steps,')
        ..writeln(
          '    ${demo['like_count'] ?? 0}, ${demo['save_count'] ?? 0}, '
          '${demo['view_count'] ?? 0},',
        )
        ..writeln('    ${_json(demo['ratings'] ?? const [])},')
        // `null` and an absent key mean the same thing — no label — and the
        // column's check constraint rejects `'null'::jsonb`, so the SQL NULL
        // has to be a bare NULL and not a json one.
        ..writeln(
          '    ${r['nutrition'] == null ? 'NULL' : _json(r['nutrition'])}',
        )
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

  final set = loadAndValidate(_recipesDir, options: _options);

  for (final w in set.warnings) {
    stdout.writeln('  warning  $w');
  }
  for (final e in set.errors) {
    stderr.writeln('  error    $e');
  }
  if (!set.isValid) {
    stderr.writeln('✖ ${set.errors.length} error(s) in $_recipesDir');
    exit(1);
  }
  stdout.writeln(
    '✔ ${set.recipes.length} recipes valid'
    '${set.warnings.isEmpty ? '' : ' (${set.warnings.length} warning(s))'}',
  );

  if (action == 'validate') return;

  final sql = _generate(set.recipes);
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
