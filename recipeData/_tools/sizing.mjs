// What would it cost to store this corpus properly?
//
//   node sizing.mjs            # relational + image sizing, from the real data
//   node sizing.mjs --probe 40 # also HEAD-sample N real image URLs for byte sizes
//
// Written because "can Supabase hold it" is a question with an arithmetic answer, and
// every estimate here comes from the corpus rather than from a rule of thumb. Postgres
// row overhead is taken as 24 bytes of tuple header + ~4 bytes line pointer + null
// bitmap rounding, which is the conservative end; indexes are estimated separately
// because they are usually the surprise, not the heap.
import { createReadStream } from 'node:fs';
import { createInterface } from 'node:readline';
import { readdir } from 'node:fs/promises';
import { dirname, resolve, basename } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readShard } from './corpus_stats.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const CORPUS = resolve(HERE, '../../corpus');

const TUPLE_OVERHEAD = 28; // 24-byte header + line pointer
const UUID = 16;
const num = (n) => Math.round(n).toLocaleString('en-US');
const mb = (b) => (b / 1e6).toFixed(0) + ' MB';
const gb = (b) => (b / 1e9).toFixed(2) + ' GB';

const utf8 = (s) => (s ? Buffer.byteLength(String(s), 'utf8') : 0);

async function main() {
  const probeN = Number((process.argv[process.argv.indexOf('--probe') + 1]) || 0);

  const files = (await readdir(resolve(CORPUS, 'recipes'))).filter((f) => f.endsWith('.jsonl')).sort();

  let recipes = 0;
  let ingredients = 0;
  let steps = 0;
  let ingredientGroups = 0;
  let stepGroups = 0;

  // Bytes of actual TEXT, which is what a Postgres varlena stores.
  let titleB = 0;
  let descB = 0;
  let ingB = 0;
  let stepB = 0;
  let nutritionB = 0;
  let rawB = 0;

  const chefs = new Set();
  const groups = new Set();

  // Images
  let withCover = 0;
  let coverUrlCount = 0;
  const imageUrls = new Set();
  const imageHosts = new Map();
  let stepImages = 0;
  const sampleUrls = [];

  for (const f of files) {
    for await (const r of readShard(resolve(CORPUS, 'recipes', f))) {
      recipes++;
      titleB += utf8(r.title);
      descB += utf8(r.description);
      if (r.nutrition) nutritionB += utf8(JSON.stringify(r.nutrition));
      if (r.rawJsonLd) rawB += utf8(JSON.stringify(r.rawJsonLd));

      ingredientGroups += r.ingredientGroups.length;
      for (const g of r.ingredientGroups) {
        ingB += utf8(g.name);
        for (const i of g.items) {
          ingredients++;
          ingB += utf8(i.name) + utf8(i.unit) + utf8(i.note);
        }
      }
      const sg = new Set();
      for (const s of r.steps) {
        steps++;
        stepB += utf8(s.text) + utf8(s.tip) + utf8(s.temperature);
        sg.add(s.stepGroup || '');
        if (s.imageUrl) stepImages++;
      }
      stepGroups += sg.size;

      const a = r.attribution || {};
      if (a.chef) chefs.add(a.chef);
      if (a.group) groups.add(a.group);

      const covers = (r.media && r.media.coverImages) || [];
      if (covers.length) {
        withCover++;
        coverUrlCount += covers.length;
        const u = covers[0];
        imageUrls.add(u);
        try {
          const h = new URL(u).hostname.replace(/^www\./, '');
          imageHosts.set(h, (imageHosts.get(h) || 0) + 1);
        } catch { /* malformed url */ }
        if (sampleUrls.length < 4000 && recipes % 97 === 0) sampleUrls.push(u);
      }
    }
  }

  // ------------------------------------------------------------- relational

  // recipes: id, owner, title, description, cuisine, category, difficulty,
  // prep/cook/servings, visibility, counters, timestamps, nutrition jsonb
  const recipesFixed = UUID + UUID + 4 * 4 + 8 * 2 + 4 * 6 + 2;
  const recipesHeap = recipes * (TUPLE_OVERHEAD + recipesFixed) + titleB + descB + nutritionB;
  const ingHeap = ingredients * (TUPLE_OVERHEAD + UUID + UUID + 8 + 4 + 1 + 8) + ingB;
  const stepHeap = steps * (TUPLE_OVERHEAD + UUID + UUID + 4 + 4) + stepB;
  const groupHeap = (ingredientGroups + stepGroups) * (TUPLE_OVERHEAD + UUID + UUID + 4 + 24);
  const profilesHeap = (chefs.size + groups.size) * (TUPLE_OVERHEAD + UUID + 400);

  const heap = recipesHeap + ingHeap + stepHeap + groupHeap + profilesHeap;
  // Every FK column needs an index (CLAUDE.md gotcha 4), plus the PKs and the
  // search_tsv GIN. B-tree on a uuid FK is ~40 bytes/row all-in.
  const btreeRows = recipes * 3 + ingredients * 2 + steps * 2 + (ingredientGroups + stepGroups) * 2;
  const btree = btreeRows * 40;
  const tsv = recipes * 450; // measured elsewhere in this repo: ~450 B/tsvector
  const indexes = btree + tsv;

  console.log('=== what is in the corpus ===');
  console.log('recipes            ' + num(recipes).padStart(12));
  console.log('ingredient rows    ' + num(ingredients).padStart(12));
  console.log('step rows          ' + num(steps).padStart(12));
  console.log('group rows         ' + num(ingredientGroups + stepGroups).padStart(12));
  console.log('distinct chefs     ' + num(chefs.size).padStart(12));
  console.log('distinct groups    ' + num(groups.size).padStart(12));

  console.log('\n=== Postgres, if loaded as-is ===');
  console.log('recipes heap       ' + mb(recipesHeap).padStart(12));
  console.log('ingredients heap   ' + mb(ingHeap).padStart(12));
  console.log('steps heap         ' + mb(stepHeap).padStart(12));
  console.log('groups heap        ' + mb(groupHeap).padStart(12));
  console.log('profiles heap      ' + mb(profilesHeap).padStart(12));
  console.log('indexes (est)      ' + mb(indexes).padStart(12));
  console.log('TOTAL              ' + gb(heap + indexes).padStart(12) +
    '   (+30% bloat/WAL headroom = ' + gb((heap + indexes) * 1.3) + ')');
  console.log('rawJsonLd, if kept ' + gb(rawB).padStart(12) + '   <- the thing NOT to load');

  console.log('\n=== images ===');
  console.log('recipes with a cover   ' + num(withCover) + '  (' + ((withCover * 100) / recipes).toFixed(1) + '%)');
  console.log('cover URLs total       ' + num(coverUrlCount) + '  (' + (coverUrlCount / withCover).toFixed(2) + ' per recipe)');
  console.log('distinct first-cover   ' + num(imageUrls.size));
  console.log('step images            ' + num(stepImages));
  const topHosts = [...imageHosts.entries()].sort((a, b) => b[1] - a[1]).slice(0, 8);
  console.log('top image hosts        ' + topHosts.map(([h, n]) => h + ' (' + num(n) + ')').join(', '));

  if (probeN > 0) {
    console.log('\n=== sampling ' + probeN + ' real images (HEAD) ===');
    const step = Math.max(1, Math.floor(sampleUrls.length / probeN));
    const picks = [];
    for (let i = 0; i < sampleUrls.length && picks.length < probeN; i += step) picks.push(sampleUrls[i]);
    const sizes = [];
    const types = new Map();
    let failed = 0;
    await Promise.all(picks.map(async (u) => {
      try {
        const res = await fetch(u, { method: 'HEAD', signal: AbortSignal.timeout(15000) });
        const len = Number(res.headers.get('content-length'));
        const ct = res.headers.get('content-type') || '?';
        if (res.ok && Number.isFinite(len) && len > 0) {
          sizes.push(len);
          types.set(ct, (types.get(ct) || 0) + 1);
        } else failed++;
      } catch {
        failed++;
      }
    }));
    sizes.sort((a, b) => a - b);
    if (sizes.length) {
      const sum = sizes.reduce((a, b) => a + b, 0);
      const mean = sum / sizes.length;
      const p50 = sizes[Math.floor(sizes.length / 2)];
      const p90 = sizes[Math.floor(sizes.length * 0.9)];
      console.log('sampled ok=' + sizes.length + ' failed=' + failed);
      console.log('mean ' + Math.round(mean / 1024) + ' KB   median ' + Math.round(p50 / 1024) +
        ' KB   p90 ' + Math.round(p90 / 1024) + ' KB   max ' + Math.round(sizes[sizes.length - 1] / 1024) + ' KB');
      console.log('types: ' + [...types.entries()].map(([t, n]) => t + '(' + n + ')').join(', '));
      console.log('\nif every cover were downloaded at the publisher\'s size:');
      console.log('  ' + num(imageUrls.size) + ' images x ' + Math.round(mean / 1024) + ' KB = ' +
        gb(imageUrls.size * mean));
      for (const [label, kb] of [['1600px webp q80', 180], ['800px webp q80', 60], ['400px thumb', 18]]) {
        console.log('  re-encoded ' + label.padEnd(18) + gb(imageUrls.size * kb * 1024));
      }
    } else {
      console.log('no sizes returned (failed=' + failed + ')');
    }
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
