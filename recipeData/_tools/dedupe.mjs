// Rewrite each shard keeping one record per recipe.
//
//   node dedupe.mjs --dry      # report only
//   node dedupe.mjs            # rewrite in place, keeping the FIRST of each group
//
// Two kinds of duplicate show up in an append-only shard, and they have different
// causes:
//
//   same finalUrl     the harvester was killed between its last state flush and its
//                     last append, so the restart re-fetched a handful of URLs that
//                     were already on disk. Self-inflicted, bounded by the flush
//                     interval, and always safe to collapse.
//   same title        one dish published at two URLs — a `/recipe/x` and a
//                     `/2019/03/x`, or a site that reposts. Collapsed only within a
//                     source, never across: two sites publishing "Banana Bread" are
//                     two recipes, and merging them would be the wrong answer.
//
// The shard is rewritten through a temp file and renamed, so an interrupted dedupe
// leaves the original intact.
import { createReadStream, createWriteStream } from 'node:fs';
import { readdir, rename, stat, unlink } from 'node:fs/promises';
import { createInterface } from 'node:readline';
import { dirname, resolve, basename } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const DIR = resolve(HERE, '../../corpus/recipes');

const keyUrl = (r) =>
  String((r.source && (r.source.finalUrl || r.source.sourceUrl)) || '')
    .replace(/[#?].*$/, '')
    .replace(/\/$/, '')
    .toLowerCase();

const keyTitle = (r) =>
  String(r.title || '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();

async function dedupeFile(file, { dry }) {
  const src = resolve(DIR, file);
  const tmp = src + '.tmp';
  const seenUrl = new Set();
  const seenTitle = new Set();
  let total = 0;
  let dupUrl = 0;
  let dupTitle = 0;
  let kept = 0;

  const out = dry ? null : createWriteStream(tmp, { flags: 'w' });
  const rl = createInterface({ input: createReadStream(src, 'utf8'), crlfDelay: Infinity });
  for await (const line of rl) {
    if (!line.trim()) continue;
    let rec;
    try {
      rec = JSON.parse(line);
    } catch {
      continue; // a truncated final line is what an interrupted append looks like
    }
    total++;
    const u = keyUrl(rec);
    const t = keyTitle(rec);
    if (u && seenUrl.has(u)) {
      dupUrl++;
      continue;
    }
    if (t && seenTitle.has(t)) {
      dupTitle++;
      continue;
    }
    if (u) seenUrl.add(u);
    if (t) seenTitle.add(t);
    kept++;
    if (out) out.write(line + '\n');
  }
  if (out) await new Promise((r) => out.end(r));

  if (!dry && (dupUrl || dupTitle)) {
    await unlink(src);
    await rename(tmp, src);
  } else if (!dry) {
    await unlink(tmp);
  }
  return { file, total, kept, dupUrl, dupTitle };
}

async function main() {
  const dry = process.argv.includes('--dry');
  let files = [];
  try {
    files = (await readdir(DIR)).filter((f) => f.endsWith('.jsonl')).sort();
  } catch {
    console.log('no shards at ' + DIR);
    return;
  }
  let total = 0;
  let kept = 0;
  let du = 0;
  let dt = 0;
  for (const f of files) {
    const s = await stat(resolve(DIR, f));
    if (!s.size) continue;
    const r = await dedupeFile(f, { dry });
    total += r.total;
    kept += r.kept;
    du += r.dupUrl;
    dt += r.dupTitle;
    if (r.dupUrl || r.dupTitle) {
      console.log(
        basename(f, '.jsonl').padEnd(34) +
        String(r.total).padStart(6) + ' -> ' + String(r.kept).padStart(6) +
        '   dupUrl=' + r.dupUrl + ' dupTitle=' + r.dupTitle,
      );
    }
  }
  console.log(
    '\n' + (dry ? 'would keep ' : 'kept ') + kept + ' of ' + total +
    '  (same-url ' + du + ', same-title ' + dt + ')',
  );
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
