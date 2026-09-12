// Reconcile the ingest state against what is actually in the database.
//
//   node recipeData/_tools/reconcile.mjs           # report only
//   node recipeData/_tools/reconcile.mjs --write   # repair _state/ingest.json
//
// Why this exists: the harness used to read the URL a fixed interval after Save.
// A large recipe takes minutes to write, so the id was not in the URL yet and a
// successful save was recorded as NOSAVE. Re-running would then create a second
// copy of a recipe that was already there. This matches saved recipes back to
// their corpus files by (owner, title) and restores the missing ids, and reports
// any duplicates so they can be removed deliberately rather than by guesswork.
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const exec = promisify(execFile);
const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, '..');
const CONTAINER = process.env.SS_DB_CONTAINER || 'supabase_db_secret-sauce';

const readJson = async (p, fallback) => {
  try {
    return JSON.parse(await readFile(p, 'utf8'));
  } catch {
    return fallback;
  }
};

async function psqlJson(sql) {
  const { stdout } = await exec(
    'docker',
    ['exec', CONTAINER, 'psql', '-U', 'postgres', '-d', 'postgres', '-tAc', sql],
    { env: { ...process.env, MSYS_NO_PATHCONV: '1' }, maxBuffer: 64 * 1024 * 1024 },
  );
  const t = stdout.trim();
  return t ? JSON.parse(t) : [];
}

const key = (s) => String(s || '').toLowerCase().replace(/[^a-z0-9]/g, '');

async function main() {
  const write = process.argv.includes('--write');

  const rows = await psqlJson(
    "select coalesce(json_agg(x), '[]'::json)::text from (" +
      'select r.id, r.title, p.display_name as owner, r.created_at ' +
      'from recipes r join profiles p on p.id = r.owner_id order by r.created_at' +
      ') x;',
  );

  const state = await readJson(resolve(ROOT, '_state/ingest.json'), { chefs: {} });
  const progress = await readJson(resolve(ROOT, '_state/progress.json'), { chefs: {} });

  // Every saved recipe, grouped by owner+title. More than one id in a bucket is
  // a duplicate that a re-run created.
  const byKey = new Map();
  for (const r of rows) {
    const k = key(r.owner) + '::' + key(r.title);
    if (!byKey.has(k)) byKey.set(k, []);
    byKey.get(k).push(r);
  }

  let repaired = 0;
  let stillMissing = 0;
  const duplicates = [];

  for (const [slug, cs] of Object.entries(state.chefs)) {
    const scraped = (progress.chefs[slug] || { scraped: [] }).scraped;
    for (const entry of scraped) {
      const rec = cs.recipes[entry.file];
      if (!rec || rec.recipeId) continue;

      const corpus = await readJson(resolve(ROOT, 'recipes', entry.file), null);
      if (!corpus) continue;

      const hits = byKey.get(key(corpus.chefName) + '::' + key(corpus.title)) || [];
      if (hits.length === 0) {
        stillMissing++;
        continue;
      }
      if (hits.length > 1) duplicates.push({ file: entry.file, ids: hits.map((h) => h.id) });

      cs.recipes[entry.file] = {
        recipeId: hits[0].id,
        savedUrl: null,
        notes: rec.notes || [],
        at: rec.at,
        reconciled: true,
      };
      repaired++;
      console.log('repaired  ' + entry.file + '  -> ' + hits[0].id);
    }
  }

  for (const [k, hits] of byKey) {
    if (hits.length > 1 && !duplicates.some((d) => d.ids.includes(hits[0].id))) {
      duplicates.push({ file: k, ids: hits.map((h) => h.id) });
    }
  }

  console.log(
    '\ndb rows=' + rows.length + '  repaired=' + repaired +
    '  still-missing=' + stillMissing + '  duplicate-titles=' + duplicates.length,
  );
  for (const d of duplicates) console.log('  DUPLICATE ' + d.file + '  ' + d.ids.join(' '));

  if (write) {
    await writeFile(resolve(ROOT, '_state/ingest.json'), JSON.stringify(state, null, 2) + '\n');
    console.log('\nwrote _state/ingest.json');
  } else {
    console.log('\n(report only — pass --write to repair)');
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}
