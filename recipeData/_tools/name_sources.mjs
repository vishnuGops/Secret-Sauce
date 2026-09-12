// Give a source the name its own pages use.
//
//   node name_sources.mjs --dry
//   node name_sources.mjs
//
// Candidates generated from a bare domain list carry the domain as their name, and
// `promote.mjs` can only improve on that when the three sampled pages happened to
// declare a `publisher`. After a harvest there are hundreds of pages to ask instead
// of three, so this takes the majority answer and writes it back.
//
// It only overwrites a name that still *is* the domain — a hand-written name, or one
// a probe already resolved, is left alone. The registry is the source of truth for
// `entity.name`; `retag.mjs --refresh-entity` is what pushes a new name onto records
// already captured.
import { readdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve, basename } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readShard } from './corpus_stats.mjs';
import { decodeEntities } from './extract.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const CORPUS = resolve(HERE, '../../corpus');
const IN = resolve(CORPUS, 'recipes');

/** True when the registry name is still just the hostname. */
const isDomainName = (name, homepage) => {
  const n = String(name || '').toLowerCase().trim();
  if (!n) return true;
  if (/^[a-z0-9.-]+\.[a-z]{2,}$/.test(n)) return true;
  try {
    return n === new URL(homepage).hostname.replace(/^www\./, '');
  } catch {
    return false;
  }
};

// Names captured before the decoder was wired in are still entity-encoded on disk,
// so decode on the way out as well as on the way in.
const clean = (s) => decodeEntities(String(s || '')).replace(/\s+/g, ' ').trim();

async function main() {
  const dry = process.argv.includes('--dry');
  const regFile = resolve(CORPUS, 'sources.json');
  const reg = JSON.parse(await readFile(regFile, 'utf8'));
  const bySlug = new Map(reg.sources.map((s) => [s.slug, s]));

  let files = [];
  try {
    files = (await readdir(IN)).filter((f) => f.endsWith('.jsonl')).sort();
  } catch {
    console.log('no shards');
    return;
  }

  let renamed = 0;
  for (const f of files) {
    const slug = basename(f, '.jsonl');
    const src = bySlug.get(slug);
    if (!src || !isDomainName(src.name, src.homepage)) continue;

    const votes = new Map();
    let n = 0;
    let voted = 0;
    for await (const rec of readShard(resolve(IN, f))) {
      n++;
      // `siteName` is what the site calls itself; `publisher` is what the Recipe
      // node declares, which most personal blogs omit entirely.
      const p = clean((rec.source && (rec.source.siteName || rec.source.publisher)) || '');
      if (p) {
        votes.set(p, (votes.get(p) || 0) + 1);
        voted++;
      }
    }
    if (!votes.size) continue;
    const [best, count] = [...votes.entries()].sort((a, b) => b[1] - a[1])[0];
    // The majority is taken among the rows that actually declared a name, not among
    // all rows: `siteName` was added after most of the corpus was captured, so a
    // share-of-everything test would reject every source until it had been recrawled.
    if (count < 3 || count < voted * 0.6) continue;
    if (isDomainName(best, src.homepage)) continue;

    console.log(slug.padEnd(34) + JSON.stringify(src.name) + ' -> ' + JSON.stringify(best) + '  (' + count + '/' + voted + ' declared, ' + n + ' rows)');
    if (!dry) {
      src.nameWasDomain = src.name;
      src.name = best;
    }
    renamed++;
  }

  if (!dry && renamed) {
    reg.updatedAt = new Date().toISOString();
    await writeFile(regFile, JSON.stringify(reg, null, 2) + '\n', 'utf8');
  }
  console.log('\n' + (dry ? 'would rename ' : 'renamed ') + renamed + ' sources');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
