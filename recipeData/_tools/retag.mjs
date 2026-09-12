// Recompute the derived fields on already-harvested records, without refetching.
//
//   node retag.mjs --dry
//   node retag.mjs
//
// `attribution.restaurantMentioned` and `attribution.isCopycat` are derived from the
// title, description and keywords — all of which are stored — so a change to
// `brands.mjs` can be applied to the whole corpus for free. Refetching 60,000 pages
// to fix a word list would be the wrong trade, and it would also be rude.
//
// Only derived fields are touched. Anything that came off the page stays exactly as
// it was captured, so this can never turn a fetch into a rewrite of the source's
// words. Run it with the harvester STOPPED: it rewrites each shard through a temp
// file, and an appender holding the old handle would write into a file that no
// longer exists.
import { createReadStream, createWriteStream } from 'node:fs';
import { readdir, rename, unlink, stat } from 'node:fs/promises';
import { createInterface } from 'node:readline';
import { dirname, resolve, basename } from 'node:path';
import { fileURLToPath } from 'node:url';
import { detectBrands, isCopycat } from './brands.mjs';
import { parseIngredient } from './extract.mjs';
import { readFile as readFileP } from 'node:fs/promises';

const HERE = dirname(fileURLToPath(import.meta.url));
const DIR = resolve(HERE, '../../corpus/recipes');

const same = (a, b) => JSON.stringify(a || []) === JSON.stringify(b || []);

/**
 * An ingredient the WPRM enricher stored unparsed, before it learned to call the
 * parser (B101). Recognisable because the whole line is sitting in `name` with no
 * quantity beside it. `raw` is always the line as published, so the repair needs no
 * network — but it is opt-in (`--reparse`), because re-deriving a field the capture
 * produced is a bigger claim than recomputing one that was always derived.
 */
const looksUnparsed = (i) =>
  i && typeof i.raw === 'string' && i.raw.length > 0 &&
  i.quantity == null && i.unit == null &&
  (i.htmlOnly === true || i.name === i.raw);

async function retagFile(file, { dry, reparse, reparseAll, entity }) {
  const src = resolve(DIR, file);
  const tmp = src + '.tmp';
  const out = dry ? null : createWriteStream(tmp, { flags: 'w' });
  let total = 0;
  let changed = 0;
  let reparsed = 0;
  let gained = 0;
  let lost = 0;

  const rl = createInterface({ input: createReadStream(src, 'utf8'), crlfDelay: Infinity });
  for await (const line of rl) {
    if (!line.trim()) continue;
    let rec;
    try {
      rec = JSON.parse(line);
    } catch {
      continue;
    }
    total++;
    if (reparse || reparseAll) {
      for (const g of rec.ingredientGroups || []) {
        for (let k = 0; k < g.items.length; k++) {
          const it = g.items[k];
          if (!reparseAll && !looksUnparsed(it)) continue;
          if (!it || typeof it.raw !== 'string' || !it.raw) continue;
          const fresh = parseIngredient(it.raw);
          // In `--reparse` the bar is "strictly better"; in `--reparse-all` the parser
          // is simply re-run over every stored `raw`, which is what makes a corrected
          // rule (a new guard, a new unit) reach lines that already parsed — wrongly.
          if (!reparseAll && fresh.quantity == null && fresh.unit == null) continue;
          if (JSON.stringify(fresh) === JSON.stringify({ ...it, htmlOnly: undefined })) continue;
          g.items[k] = { ...fresh, htmlOnly: it.htmlOnly };
          reparsed++;
        }
      }
    }
    if (entity) {
      // `entity` is a projection of the registry, not something read off the page, so
      // a corrected source name belongs on records already captured. The page's own
      // fields (`source.publisher`, `source.siteName`) are never touched.
      const before = JSON.stringify(rec.entity || null);
      rec.entity = {
        ...(rec.entity || {}),
        slug: entity.slug,
        id: entity.id,
        name: entity.name,
        kind: entity.kind,
        homepage: entity.homepage,
        country: entity.country ?? null,
        language: entity.language || 'en',
      };
      if (JSON.stringify(rec.entity) !== before) changed++;
      const at = (rec.attribution = rec.attribution || {});
      if (at.group !== entity.name) {
        at.group = entity.name;
        changed++;
      }
      at.groupKind = entity.kind;
    }
    const a = (rec.attribution = rec.attribution || {});
    const before = a.restaurantMentioned;
    const now = detectBrands(rec.title, rec.description, (rec.keywords || []).join(' '));
    if (!same(before, now)) {
      changed++;
      gained += Math.max(0, now.length - (before || []).length);
      lost += Math.max(0, (before || []).length - now.length);
      a.restaurantMentioned = now;
    }
    // Counted, not just assigned: a shard is only rewritten when something changed,
    // so an uncounted field is a field that silently never lands on disk.
    const copy = isCopycat(rec.title, rec.description);
    if (a.isCopycat !== copy) {
      a.isCopycat = copy;
      changed++;
    }
    if (out) out.write(JSON.stringify(rec) + '\n');
  }
  if (out) await new Promise((r) => out.end(r));

  if (!dry) {
    if (changed || reparsed) {
      await unlink(src);
      await rename(tmp, src);
    } else {
      await unlink(tmp);
    }
  }
  return { file, total, changed, gained, lost, reparsed };
}

async function main() {
  const dry = process.argv.includes('--dry');
  const reparse = process.argv.includes('--reparse');
  const reparseAll = process.argv.includes('--reparse-all');
  const refreshEntity = process.argv.includes('--refresh-entity');
  let registry = new Map();
  if (refreshEntity) {
    const reg = JSON.parse(await readFileP(resolve(DIR, '../sources.json'), 'utf8'));
    registry = new Map(reg.sources.map((s2) => [s2.slug, s2]));
  }
  let files = [];
  try {
    files = (await readdir(DIR)).filter((f) => f.endsWith('.jsonl')).sort();
  } catch {
    console.log('no shards at ' + DIR);
    return;
  }
  let total = 0;
  let changed = 0;
  let gained = 0;
  let lost = 0;
  let reparsed = 0;
  for (const f of files) {
    const s = await stat(resolve(DIR, f));
    if (!s.size) continue;
    const r = await retagFile(f, {
      dry,
      reparse,
      reparseAll,
      entity: refreshEntity ? registry.get(basename(f, '.jsonl')) || null : null,
    });
    total += r.total;
    changed += r.changed;
    gained += r.gained;
    lost += r.lost;
    reparsed += r.reparsed;
    if (r.changed || r.reparsed) {
      console.log(
        basename(f, '.jsonl').padEnd(36) + String(r.changed).padStart(6) + ' of ' +
        String(r.total).padStart(6) + '  +' + r.gained + ' -' + r.lost +
        (r.reparsed ? '  reparsed=' + r.reparsed : ''),
      );
    }
  }
  console.log(
    '\n' + (dry ? 'would change ' : 'changed ') + changed + ' of ' + total +
    ' records  (mentions added ' + gained + ', removed ' + lost +
    ((reparse || reparseAll) ? ', ingredients reparsed ' + reparsed : '') + ')',
  );
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
