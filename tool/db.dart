// tool/db.dart — thin cross-platform wrapper around `psql` for DB tasks.
//
// Usage (via melos):
//   melos run db:create | db:seed | db:recipes | db:drop | db:clean | db:reset
//   melos run db:sim | db:sim:verify | db:sim:clean
//   melos run db:rls
// Requires:
//   * `psql` on PATH (PostgreSQL client).
//   * SUPABASE_DB_URL env var — the connection string from the Supabase
//     dashboard (Project Settings -> Database -> Connection string -> URI).
//
// Example (PowerShell):
//   $env:SUPABASE_DB_URL = "postgresql://postgres:<pwd>@db.<ref>.supabase.co:5432/postgres"
//   melos run db:reset
//
// No `psql` installed? The Supabase CLI's local DB container ships one — see
// README.md, and docs/BUG-TRACKER.md B033 for the hosted-project form.

import 'dart:io';

/// Steps that apply **every** `.sql` file in a directory, in filename order.
///
/// `create` is one of these as of OPT-A9: `supabase/migrations/` is a numbered
/// sequence now, not a single file that gets edited forever. `0001_init.sql`
/// stays the idempotent baseline — it is what a fresh database is built from —
/// and every schema change after it is a **new** numbered file. See
/// `supabase/migrations/README.md` for the rules that keeps honest.
const _directories = <String, String>{'create': 'supabase/migrations'};

/// Single-file steps, by name.
const _files = <String, String>{
  'seed': 'supabase/seed.sql',
  // Generated from recipeData/recipes/*.json by tool/recipes.dart. Standalone
  // and order-independent with respect to `seed`: both bootstrap the same
  // Secret Sauce Kitchen account with conflict guards.
  'recipes': 'supabase/seed_recipes.sql',
  // Generated from nutritionData/ by tool/nutrition.dart. Reference data, not
  // demo data: `clean` leaves it alone. Ordered BEFORE `recipes` in `reset`
  // because Phase 29b gives ingredients a food_id FK into it.
  'nutrition': 'supabase/nutrition_foods.sql',
  'drop': 'supabase/scripts/drop.sql',
  'clean': 'supabase/scripts/clean.sql',
  // Simulation (docs/ROADMAP.md Phase 24). Split by lifecycle, not by taste:
  // the schema and the dish library are cheap and reusable, the generator is
  // the expensive part, and the teardown is destructive.
  'sim:schema': 'supabase/sim/0_sim_schema.sql',
  'sim:dishes': 'supabase/sim/1_sim_dishes.sql',
  'sim:generate': 'supabase/sim/2_sim_generate.sql',
  'sim:verify': 'supabase/sim/3_sim_verify.sql',
  'sim:teardown': 'supabase/sim/9_sim_teardown.sql',
  // The RLS acceptance matrix (docs/ROADMAP.md BL-7). Creates three throwaway
  // users and two recipes, re-runs the whole authorization matrix as each of
  // them under `set local role authenticated`, and ROLLS THE WHOLE THING BACK.
  // Exempt from `-1` below because it owns that transaction itself.
  'rls': 'supabase/tests/rls_matrix.sql',
};

/// Multi-step actions, in order.
const _pipelines = <String, List<String>>{
  // The sim is part of a reset on purpose. It is safe there because
  // sim.config.engage_existing is false by default, so simulated users engage
  // only with simulated recipes and every standing pinned in docs/SDS.md §10.7
  // survives byte-identical — only the RANKS move.
  'reset': ['drop', 'create', 'nutrition', 'seed', 'recipes', 'sim'],
  'sim': ['sim:schema', 'sim:dishes', 'sim:generate', 'sim:verify'],
  'sim:clean': ['sim:teardown'],
};

/// Actions that destroy data and therefore require an explicit `--yes`.
const _destructive = {'sim:clean'};

/// Steps applied inside a **single transaction** (`psql -1`), so a failure
/// halfway through a file rolls the whole file back (OPT-T6).
///
/// `ON_ERROR_STOP=1` already stops the run at the first error, but without `-1`
/// everything before it has committed: a schema apply that dies two thirds of
/// the way through leaves two thirds of a schema, and the next run starts from
/// a state nothing describes.
///
/// The sim files are **exempt** and must stay that way — they open and close
/// their own transactions around the bulk load (and toggle triggers on the
/// tables they write), which `-1` would nest and break. `rls` is exempt for the
/// same reason and a sharper one: its `rollback` *is* the cleanup.
const _transactional = {'create', 'seed', 'recipes', 'nutrition', 'drop', 'clean'};

Future<int> _psql(
  String url,
  List<String> args, {
  bool singleTransaction = false,
}) async {
  final proc = await Process.start('psql', [
    url,
    '-v',
    'ON_ERROR_STOP=1',
    if (singleTransaction) '-1',
    ...args,
  ], mode: ProcessStartMode.inheritStdio);
  return proc.exitCode;
}

Future<int> _applyFile(String url, String step) async {
  final dir = _directories[step];
  if (dir != null) return _applyDirectory(url, step, dir);

  final path = _files[step]!;
  if (!File(path).existsSync()) {
    stderr.writeln('Missing SQL file: $path');
    return 1;
  }
  stdout.writeln('▶ $step  ($path)');
  return _psql(url, [
    '-f',
    path,
  ], singleTransaction: _transactional.contains(step));
}

/// Applies every `.sql` file in [dir], sorted by name — the same order the
/// Supabase CLI uses, so `melos run db:create` and `supabase db reset` cannot
/// disagree about what "the schema" is.
///
/// It applies **all** of them, including ones this database has already seen:
/// nothing here tracks migration history (the CLI's `schema_migrations` table
/// does that for `supabase db reset` / `db push`). That is why every migration
/// has to stay idempotent — see `supabase/migrations/README.md`. On a hosted
/// database with real data, prefer applying only the new file: re-running the
/// baseline is safe but re-runs its backfills, which is the cost OPT-A9 exists
/// to stop paying on every change.
Future<int> _applyDirectory(String url, String step, String dir) async {
  final directory = Directory(dir);
  if (!directory.existsSync()) {
    stderr.writeln('Missing SQL directory: $dir');
    return 1;
  }
  // Sorted by full path, which sorts by filename here because the directory
  // prefix is identical — that is what makes `0002_` follow `0001_`, and why
  // migrations are numbered rather than named.
  final files =
      directory
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.sql'))
          .map((f) => f.path)
          .toList()
        ..sort();

  if (files.isEmpty) {
    stderr.writeln('No .sql files in $dir');
    return 1;
  }

  // One transaction **per file**, not one across the directory: a migration is
  // the unit that has to be all-or-nothing, and 0002 failing must not undo 0001
  // on a database that had never seen either.
  for (final path in files) {
    stdout.writeln('▶ $step  ($path)');
    final code = await _psql(url, [
      '-f',
      path,
    ], singleTransaction: _transactional.contains(step));
    if (code != 0) return code;
  }
  return 0;
}

/// Writes the run's knobs into `sim.config` before the generator reads them.
/// The SQL deliberately reads its configuration from a table rather than from
/// psql `-v` variables, so that a hand-run file behaves the same as this
/// wrapper does.
Future<int> _configureSim(String url, String? preset, int? seed) async {
  final sets = <String>[
    if (preset != null) "('preset', '$preset')",
    if (seed != null) "('seed', '$seed')",
  ];
  if (sets.isEmpty) return 0;
  stdout.writeln('▶ sim:config  (${sets.join(', ')})');
  return _psql(url, [
    '-c',
    'insert into sim.config (key, value) values ${sets.join(', ')} '
        'on conflict (key) do update set value = excluded.value',
  ]);
}

/// The host being targeted, with any credential stripped. `db:*` fires at
/// whatever SUPABASE_DB_URL points at with no prod guard (CLAUDE.md Gotcha 7),
/// so the least this can do is say where.
String _describeTarget(String url) {
  try {
    final uri = Uri.parse(url);
    return '${uri.host}:${uri.port}${uri.path}';
  } on FormatException {
    return '(unparseable connection string)';
  }
}

void _usage() {
  stdout.writeln('''
usage: dart run tool/db.dart <action> [options]

  create                                   apply every supabase/migrations/*.sql, in order
  seed | recipes | nutrition | drop | clean  apply one SQL file
  reset                                    drop -> create -> nutrition -> seed -> recipes -> sim
  sim                                      schema -> dishes -> generate -> verify
  sim:verify                               assertions only, read-only
  sim:clean                                DESTRUCTIVE teardown (requires --yes)
  rls                                      the RLS matrix as a signed-in user (rolls back)

options:
  --preset=<tiny|small|medium|large>       sim size (default: whatever sim.config holds)
  --seed=<int>                             sim random seed
  --yes                                    confirm a destructive action
''');
}

Future<void> main(List<String> args) async {
  final url = Platform.environment['SUPABASE_DB_URL'];
  if (url == null || url.isEmpty) {
    stderr.writeln(
      'SUPABASE_DB_URL is not set.\n'
      'Get it from Supabase -> Project Settings -> Database -> Connection string (URI),\n'
      'then e.g.  \$env:SUPABASE_DB_URL = "postgresql://postgres:<pwd>@db.<ref>.supabase.co:5432/postgres"',
    );
    exit(2);
  }

  final positional = args.where((a) => !a.startsWith('--')).toList();
  final flags = args.where((a) => a.startsWith('--')).toList();
  final action = positional.isEmpty ? 'help' : positional.first;

  String? optionOf(String name) {
    final hit = flags.where((f) => f.startsWith('--$name=')).toList();
    return hit.isEmpty ? null : hit.first.substring(name.length + 3);
  }

  final preset = optionOf('preset');
  final seedOpt = optionOf('seed');
  final confirmed = flags.contains('--yes');

  if (seedOpt != null && int.tryParse(seedOpt) == null) {
    stderr.writeln('--seed must be an integer (got "$seedOpt")');
    exit(64);
  }
  const presets = {'tiny', 'small', 'medium', 'large'};
  if (preset != null && !presets.contains(preset)) {
    stderr.writeln(
      '--preset must be one of ${presets.join(', ')} (got "$preset")',
    );
    exit(64);
  }

  final steps =
      _pipelines[action] ??
      ((_files.containsKey(action) || _directories.containsKey(action))
          ? [action]
          : const <String>[]);

  if (action == 'help' || steps.isEmpty) {
    _usage();
    exit(action == 'help' ? 0 : 64);
  }

  if (_destructive.contains(action) && !confirmed) {
    stderr.writeln(
      '✖ $action deletes rows from auth.users on ${_describeTarget(url)}.\n'
      '  auth.users has no undo. Re-run with --yes to confirm.',
    );
    exit(3);
  }

  stdout.writeln('target: ${_describeTarget(url)}');

  // Flatten first: a pipeline entry may itself be a pipeline (`reset` contains
  // `sim`), and the sim:generate hook below has to see the real leaf rather
  // than the group that contains it.
  final leaves = <String>[
    for (final step in steps) ...(_pipelines[step] ?? [step]),
  ];

  for (final leaf in leaves) {
    // The generator reads its knobs from sim.config, so they have to be written
    // after the schema exists and before the generator runs.
    if (leaf == 'sim:generate') {
      final code = await _configureSim(
        url,
        preset,
        seedOpt == null ? null : int.parse(seedOpt),
      );
      if (code != 0) {
        stderr.writeln('✖ sim:config failed (exit $code)');
        exit(code);
      }
    }
    final code = await _applyFile(url, leaf);
    if (code != 0) {
      stderr.writeln('✖ $leaf failed (exit $code)');
      exit(code);
    }
  }
  stdout.writeln('✔ done');
}
