// tool/hosted_check.dart — has the target database drifted from this repo?
//
//   melos run db:hosted:check
//
// READ-ONLY with respect to the target. Safe against the hosted project, and
// the thing to run before and after `db:hosted:deploy`.
//
// ---------------------------------------------------------------------------
// Why a fingerprint diff and not a version number
// ---------------------------------------------------------------------------
// The hosted project has no `supabase_migrations.schema_migrations` table: it
// was applied by hand through psql, never by `supabase db push`. There is
// therefore nothing recording which version of `0001_init.sql` it carries, and
// Gotcha 5's warning ("an edited baseline is silently wrong once a database you
// do not control has it") has no tripwire behind it. This tool is that tripwire.
//
// ---------------------------------------------------------------------------
// Why the reference is a scratch database and not the local stack
// ---------------------------------------------------------------------------
// The obvious reference — "does hosted match my local stack?" — is wrong,
// because a local stack accumulates its own history. This machine's, for
// example, still holds `seed_recipe/17`, `seed_ratings`, `seed_chef_ids` and
// `seed_taster_ids`: function definitions left behind by a past `db:seed`,
// harmless (no rows, and `db:audit` is clean) but absent from a database built
// from the repo. Diffing against it would report four differences that are the
// LOCAL side's fault and train everyone to ignore the output.
//
// So the reference is built fresh into a throwaway database inside the local
// Supabase container, from exactly what `db:hosted:deploy` applies: every
// `supabase/migrations/*.sql`, then `nutrition_foods.sql`, then
// `seed_recipes.sql`. That is the repo's actual claim about what a deployed
// database should look like.
//
// The `auth` and `storage` schemas are cloned (structure only) from the running
// stack first, because `0001_init.sql` references `auth.users`, `auth.uid()` and
// `storage.buckets`, and a plain `create database` has none of them.
//
// ---------------------------------------------------------------------------
// The reference is built on a different Postgres major than the target
// ---------------------------------------------------------------------------
// The local stack serves **15.8** and the hosted project runs **17.6**, so every
// run of this tool compares a 15-built reference against a 17 target. That is
// only sound if the fingerprint is version-stable, which is not something to
// assume — a catalogue query can easily pick up a rename or a new column between
// majors and report drift that is really a version difference.
//
// Verified 2026-09-14 rather than argued: the same three files (0001,
// nutrition_foods, seed_recipes) were applied to a real `postgres:17-alpine`
// server and to the 15.8 stack, and the two fingerprints are **byte-identical at
// 1,199 objects**. Re-check this if either end moves a major — the cheap form is
// exactly that: stand up the new image, apply the three files, diff.

import 'dart:io';

const _container = 'supabase_db_secret-sauce';
const _refDb = 'ss_schema_ref';
const _fingerprint = 'supabase/scripts/schema_fingerprint.sql';

Future<ProcessResult> _docker(List<String> args) => Process.run(
  'docker',
  args,
  environment: {
    // MSYS/Git-Bash rewrites a container-absolute path like `/tmp/x.sql` into a
    // Windows one before docker ever sees it. Turning that off is what makes this
    // behave identically from PowerShell and from Bash.
    'MSYS_NO_PATHCONV': '1',
  },
  includeParentEnvironment: true,
);

/// `psql` inside the stack's container, against [db] on the local stack.
Future<ProcessResult> _localPsql(String db, List<String> args) =>
    _docker(['exec', _container, 'psql', '-U', 'postgres', '-d', db, ...args]);

/// `psql` from a pinned image against an arbitrary [url]. Used for the target,
/// which is normally hosted: the client major has to match the server (B079),
/// and the repo is mounted read-only so the SQL never passes through a shell
/// that could re-encode it (B074).
Future<ProcessResult> _imagePsql(String url, List<String> args) => _docker([
  'run',
  '--rm',
  if (_isLoopback(url)) '--add-host=host.docker.internal:host-gateway',
  '-v',
  '${Directory.current.absolute.path}:/repo:ro',
  'postgres:17-alpine',
  'psql',
  _dockerReachable(url),
  ...args,
]);

bool _isLoopback(String url) {
  try {
    final host = Uri.parse(url).host;
    return host == '127.0.0.1' || host == 'localhost';
  } on FormatException {
    return false;
  }
}

String _dockerReachable(String url) {
  try {
    final uri = Uri.parse(url);
    if (!_isLoopback(url)) return url;
    return uri.replace(host: 'host.docker.internal').toString();
  } on FormatException {
    return url;
  }
}

String _describeTarget(String url) {
  try {
    final uri = Uri.parse(url);
    return '${uri.host}:${uri.port}${uri.path}';
  } on FormatException {
    return '(unparseable connection string)';
  }
}

/// Builds the reference database from the repo and returns its fingerprint, or
/// null if the local stack is not available to build it in.
Future<String?> _referenceFingerprint() async {
  final up = await _docker(['inspect', '-f', '{{.State.Running}}', _container]);
  if (up.exitCode != 0 || !'${up.stdout}'.trim().startsWith('true')) {
    stderr.writeln(
      '✖ the local Supabase stack is not running, and the reference schema is\n'
      '  built inside it. Run `supabase start`, then retry.',
    );
    return null;
  }

  stdout.writeln('▶ building reference schema from the repo');
  // Recreated every run rather than reused: a reference that accumulates state
  // is the exact failure this tool exists to avoid.
  final drop = await _localPsql('postgres', [
    '-q',
    '-c',
    'drop database if exists $_refDb',
    '-c',
    'create database $_refDb',
  ]);
  if (drop.exitCode != 0) {
    stderr.writeln('✖ could not create $_refDb:\n${drop.stderr}');
    return null;
  }

  // `0001_init.sql` references auth.users / auth.uid() and storage.buckets.
  // Structure only — no rows are copied, so nothing about the local stack's
  // CONTENT can leak into the reference.
  for (final schema in ['auth', 'storage']) {
    final pg = await _docker([
      'exec',
      _container,
      'pg_dump',
      '-U',
      'postgres',
      '-d',
      'postgres',
      '--schema=$schema',
      '--schema-only',
      '--no-owner',
      '--no-privileges',
      '-f',
      '/tmp/${schema}_ref.sql',
    ]);
    if (pg.exitCode != 0) {
      stderr.writeln('✖ could not dump the $schema schema:\n${pg.stderr}');
      return null;
    }
    // ON_ERROR_STOP is deliberately OFF here: these dumps re-create roles and
    // grants that already exist at cluster level, and those notices are noise.
    await _localPsql(_refDb, ['-q', '-f', '/tmp/${schema}_ref.sql']);
  }

  // The reference is what `db:hosted:deploy` applies, not the migrations alone.
  // `seed_recipes.sql` defines `seed_recipe_v2`, and `nutrition_foods.sql`
  // defines its own loader helpers — both live on in any database that has ever
  // been seeded, which is every deployed one. Leaving them out of the reference
  // would report them as drift on every single run, forever.
  //
  // The corpus shards are NOT applied: they create no schema objects, they are
  // git-ignored so they may not exist, and 21k inserts to build a fingerprint
  // that ignores rows would be pure waste.
  final migrations =
      Directory('supabase/migrations')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sql'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  final files = <File>[
    ...migrations,
    File('supabase/nutrition_foods.sql'),
    File('supabase/seed_recipes.sql'),
  ];

  for (final file in files) {
    if (!file.existsSync()) {
      stderr.writeln('✖ missing reference input: ${file.path}');
      return null;
    }
    final name = file.uri.pathSegments.last;
    await _docker(['cp', file.path, '$_container:/tmp/ref_$name']);
    final applied = await _localPsql(_refDb, [
      '-v',
      'ON_ERROR_STOP=1',
      '-1',
      '-q',
      '-f',
      '/tmp/ref_$name',
    ]);
    if (applied.exitCode != 0) {
      stderr.writeln('✖ the repo\'s own schema failed to apply: $name');
      stderr.writeln(applied.stderr);
      return null;
    }
  }

  await _docker(['cp', _fingerprint, '$_container:/tmp/fingerprint.sql']);
  final fp = await _localPsql(_refDb, [
    '-t',
    '-A',
    '-f',
    '/tmp/fingerprint.sql',
  ]);
  if (fp.exitCode != 0) {
    stderr.writeln('✖ fingerprint failed on the reference:\n${fp.stderr}');
    return null;
  }
  return '${fp.stdout}';
}

/// A stable, sorted line set — the fingerprint queries are individually ordered
/// but run as separate statements, so the concatenation is not globally sorted.
List<String> _lines(String raw) =>
    (raw
        .split('\n')
        .map((l) => l.trimRight())
        .where((l) => l.isNotEmpty)
        .toList()
      ..sort());

Future<void> main(List<String> args) async {
  final url = Platform.environment['SUPABASE_DB_URL'];
  if (url == null || url.isEmpty) {
    stderr.writeln(
      'SUPABASE_DB_URL is not set — there is no target to check.\n'
      'Dot-source db-url.local.ps1 in this shell first.',
    );
    exit(2);
  }

  stdout.writeln('target:    ${_describeTarget(url)}');
  stdout.writeln(
    'reference: migrations + nutrition + seed_recipes (built fresh)\n',
  );

  final reference = await _referenceFingerprint();
  if (reference == null) exit(1);

  stdout.writeln('▶ fingerprinting the target');
  final target = await _imagePsql(url, [
    '-t',
    '-A',
    '-f',
    '/repo/$_fingerprint',
  ]);
  if (target.exitCode != 0) {
    stderr.writeln('✖ could not fingerprint the target:\n${target.stderr}');
    exit(1);
  }

  final refLines = _lines(reference);
  final tgtLines = _lines('${target.stdout}');
  final refSet = refLines.toSet();
  final tgtSet = tgtLines.toSet();

  final missing = refLines.where((l) => !tgtSet.contains(l)).toList();
  final extra = tgtLines.where((l) => !refSet.contains(l)).toList();

  stdout.writeln(
    '\n================ SCHEMA DRIFT ================\n'
    'reference: ${refLines.length} objects\n'
    'target:    ${tgtLines.length} objects',
  );

  if (missing.isEmpty && extra.isEmpty) {
    stdout.writeln(
      '\n✔ IN SYNC — the target matches supabase/migrations/ exactly.',
    );
    return;
  }

  // Missing is the serious direction: the repo expects something the target
  // does not have, which is the app calling a function or column that is not
  // there. Extra is usually a leftover from an older schema — worth seeing,
  // not usually worth acting on, and never a reason to drop something on a
  // database holding real rows.
  if (missing.isNotEmpty) {
    stdout.writeln('\n-- MISSING on the target (${missing.length}) --');
    stdout.writeln(
      '   the repo expects these and the target does not have them.',
    );
    stdout.writeln('   fix: melos run db:hosted:deploy -- --docker --yes\n');
    for (final line in missing.take(60)) {
      stdout.writeln('   - $line');
    }
    if (missing.length > 60) {
      stdout.writeln('   ... and ${missing.length - 60} more');
    }
  }

  if (extra.isNotEmpty) {
    stdout.writeln('\n-- EXTRA on the target (${extra.length}) --');
    stdout.writeln(
      '   left over from an older schema. Re-applying does not remove',
    );
    stdout.writeln(
      '   these; dropping one is a deliberate, separate decision.\n',
    );
    for (final line in extra.take(60)) {
      stdout.writeln('   + $line');
    }
    if (extra.length > 60) {
      stdout.writeln('   ... and ${extra.length - 60} more');
    }
  }

  // Only a missing object is a failure. An extra one cannot break the app.
  exit(missing.isEmpty ? 0 : 1);
}
