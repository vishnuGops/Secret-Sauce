// tool/db.dart — thin cross-platform wrapper around `psql` for DB tasks.
//
// Usage (via melos):
//   melos run db:create | db:seed | db:recipes | db:drop | db:clean | db:reset
//   melos run db:sim | db:sim:verify | db:sim:clean
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

/// Single-file steps, by name.
const _files = <String, String>{
  'create': 'supabase/migrations/0001_init.sql',
  'seed': 'supabase/seed.sql',
  // Generated from recipeData/recipes/*.json by tool/recipes.dart. Standalone
  // and order-independent with respect to `seed`: both bootstrap the same
  // Secret Sauce Kitchen account with conflict guards.
  'recipes': 'supabase/seed_recipes.sql',
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
};

/// Multi-step actions, in order.
const _pipelines = <String, List<String>>{
  // The sim is part of a reset on purpose. It is safe there because
  // sim.config.engage_existing is false by default, so simulated users engage
  // only with simulated recipes and every standing pinned in docs/SDS.md §10.7
  // survives byte-identical — only the RANKS move.
  'reset': ['drop', 'create', 'seed', 'recipes', 'sim'],
  'sim': ['sim:schema', 'sim:dishes', 'sim:generate', 'sim:verify'],
  'sim:clean': ['sim:teardown'],
};

/// Actions that destroy data and therefore require an explicit `--yes`.
const _destructive = {'sim:clean'};

Future<int> _psql(String url, List<String> args) async {
  final proc = await Process.start(
    'psql',
    [url, '-v', 'ON_ERROR_STOP=1', ...args],
    mode: ProcessStartMode.inheritStdio,
  );
  return proc.exitCode;
}

Future<int> _applyFile(String url, String step) async {
  final path = _files[step]!;
  if (!File(path).existsSync()) {
    stderr.writeln('Missing SQL file: $path');
    return 1;
  }
  stdout.writeln('▶ $step  ($path)');
  return _psql(url, ['-f', path]);
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

  create | seed | recipes | drop | clean   apply one SQL file
  reset                                    drop -> create -> seed -> recipes -> sim
  sim                                      schema -> dishes -> generate -> verify
  sim:verify                               assertions only, read-only
  sim:clean                                DESTRUCTIVE teardown (requires --yes)

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
    stderr.writeln('--preset must be one of ${presets.join(', ')} (got "$preset")');
    exit(64);
  }

  final steps = _pipelines[action] ??
      (_files.containsKey(action) ? [action] : const <String>[]);

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
      final code =
          await _configureSim(url, preset, seedOpt == null ? null : int.parse(seedOpt));
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
