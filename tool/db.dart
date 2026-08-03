// tool/db.dart — thin cross-platform wrapper around `psql` for DB tasks.
//
// Usage (via melos): melos run db:create | db:seed | db:drop | db:clean | db:reset
// Requires:
//   * `psql` on PATH (PostgreSQL client).
//   * SUPABASE_DB_URL env var — the connection string from the Supabase
//     dashboard (Project Settings -> Database -> Connection string -> URI).
//
// Example (PowerShell):
//   $env:SUPABASE_DB_URL = "postgresql://postgres:<pwd>@db.<ref>.supabase.co:5432/postgres"
//   melos run db:reset

import 'dart:io';

const _files = <String, String>{
  'create': 'supabase/migrations/0001_init.sql',
  'seed': 'supabase/seed.sql',
  'drop': 'supabase/scripts/drop.sql',
  'clean': 'supabase/scripts/clean.sql',
};

Future<int> _apply(String url, String action) async {
  final path = _files[action]!;
  if (!File(path).existsSync()) {
    stderr.writeln('Missing SQL file: $path');
    return 1;
  }
  stdout.writeln('▶ db:$action  ($path)');
  final proc = await Process.start(
    'psql',
    [url, '-v', 'ON_ERROR_STOP=1', '-f', path],
    mode: ProcessStartMode.inheritStdio,
  );
  return proc.exitCode;
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

  final action = args.isEmpty ? 'help' : args.first;
  final order = switch (action) {
    'reset' => ['drop', 'create', 'seed'],
    'create' || 'seed' || 'drop' || 'clean' => [action],
    _ => <String>[],
  };

  if (order.isEmpty) {
    stdout
        .writeln('usage: dart run tool/db.dart <create|seed|drop|clean|reset>');
    exit(action == 'help' ? 0 : 64);
  }

  for (final step in order) {
    final code = await _apply(url, step);
    if (code != 0) {
      stderr.writeln('✖ db:$step failed (exit $code)');
      exit(code);
    }
  }
  stdout.writeln('✔ done');
}
