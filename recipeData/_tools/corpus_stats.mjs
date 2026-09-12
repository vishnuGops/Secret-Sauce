// What is actually in the shards — as opposed to what the resume state claims.
//
//   node corpus_stats.mjs              # per-source table + totals
//   node corpus_stats.mjs --fields     # how often each field is populated
//   node corpus_stats.mjs --dupes      # titles captured more than once
//
// Reads line by line so a 2 GB shard costs one line of memory, not two gigabytes.
import { createReadStream } from 'node:fs';
import { readdir, readFile } from 'node:fs/promises';
import { createInterface } from 'node:readline';
import { dirname, resolve, basename } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const CORPUS = resolve(HERE, '../../corpus');

export async function* readShard(file) {
  const rl = createInterface({ input: createReadStream(file, 'utf8'), crlfDelay: Infinity });
  for await (const line of rl) {
    if (!line.trim()) continue;
    try {
      yield JSON.parse(line);
    } catch {
      /* a truncated final line is what an interrupted append looks like */
    }
  }
}

const pct = (n, d) => (d ? Math.round((n * 100) / d) + '%' : '-');

async function main() {
  const argv = process.argv.slice(2);
  const dir = resolve(CORPUS, 'recipes');
  let files = [];
  try {
    files = (await readdir(dir)).filter((f) => f.endsWith('.jsonl')).sort();
  } catch {
    console.log('no shards yet: ' + dir);
    return;
  }

  const reg = await readFile(resolve(CORPUS, 'sources.json'), 'utf8')
    .then((t) => JSON.parse(t))
    .catch(() => ({ sources: [] }));
  const kindOf = new Map(reg.sources.map((s) => [s.slug, s.kind]));

  const totals = {
    recipes: 0, ingredients: 0, steps: 0, withChef: 0, withGroup: 0, withImage: 0,
    withNutrition: 0, withCategory: 0, withCuisine: 0, withKeywords: 0, withServings: 0,
    withPrep: 0, withCook: 0, withEquipment: 0, withStepGroups: 0, withGroupedIngredients: 0,
    withMetric: 0, withVideo: 0, withRating: 0,
  };
  const chefs = new Set();
  const cuisines = new Map();
  const titles = new Map();
  const rows = [];

  for (const f of files) {
    const slug = basename(f, '.jsonl');
    const r = { slug, kind: kindOf.get(slug) || '?', n: 0, ing: 0, steps: 0, chefs: new Set() };
    for await (const rec of readShard(resolve(dir, f))) {
      r.n++;
      totals.recipes++;
      const ing = rec.ingredientGroups.reduce((a, g) => a + g.items.length, 0);
      r.ing += ing;
      r.steps += rec.steps.length;
      totals.ingredients += ing;
      totals.steps += rec.steps.length;
      const chef = rec.attribution && rec.attribution.chef;
      if (chef) {
        r.chefs.add(chef);
        chefs.add(chef);
        totals.withChef++;
      }
      if (rec.attribution && rec.attribution.group) totals.withGroup++;
      if (rec.media && rec.media.coverImages && rec.media.coverImages.length) totals.withImage++;
      if (rec.media && rec.media.video) totals.withVideo++;
      if (rec.nutrition && Object.keys(rec.nutrition).length) totals.withNutrition++;
      if (rec.category && rec.category.length) totals.withCategory++;
      if (rec.cuisine && rec.cuisine.length) {
        totals.withCuisine++;
        for (const c of rec.cuisine) cuisines.set(c, (cuisines.get(c) || 0) + 1);
      }
      if (rec.keywords && rec.keywords.length) totals.withKeywords++;
      if (rec.yield && rec.yield.servings != null) totals.withServings++;
      if (rec.timing && rec.timing.prepMinutes != null) totals.withPrep++;
      if (rec.timing && rec.timing.cookMinutes != null) totals.withCook++;
      if (rec.equipment && rec.equipment.length) totals.withEquipment++;
      if (rec.steps.some((s) => s.stepGroup)) totals.withStepGroups++;
      if (rec.ingredientGroups.length > 1 || rec.ingredientGroups.some((g) => g.name)) {
        totals.withGroupedIngredients++;
      }
      if (rec.ingredientGroups.some((g) => g.items.some((i) => i.metric))) totals.withMetric++;
      if (rec.unmappedFields && rec.unmappedFields.aggregateRating) totals.withRating++;
      if (argv.includes('--dupes')) {
        const k = (rec.title || '').toLowerCase().trim();
        titles.set(k, (titles.get(k) || 0) + 1);
      }
    }
    rows.push(r);
  }

  rows.sort((a, b) => b.n - a.n);
  for (const r of rows) {
    console.log(
      r.slug.padEnd(32) + r.kind.padEnd(13) +
      String(r.n).padStart(6) + ' recipes  ' +
      String(r.ing).padStart(7) + ' ing  ' +
      String(r.steps).padStart(7) + ' steps  ' +
      String(r.chefs.size).padStart(4) + ' chefs',
    );
  }

  const t = totals;
  console.log(
    '\n' + rows.length + ' sources  ' + t.recipes + ' recipes  ' +
    t.ingredients + ' ingredient lines  ' + t.steps + ' steps  ' +
    chefs.size + ' distinct named chefs',
  );

  if (argv.includes('--fields')) {
    console.log('\nfield coverage');
    const show = [
      ['named chef', t.withChef], ['group', t.withGroup], ['cover image', t.withImage],
      ['servings', t.withServings], ['prep time', t.withPrep], ['cook time', t.withCook],
      ['category', t.withCategory], ['cuisine', t.withCuisine], ['keywords', t.withKeywords],
      ['nutrition', t.withNutrition], ['equipment', t.withEquipment],
      ['grouped ingredients', t.withGroupedIngredients], ['step sections', t.withStepGroups],
      ['metric in parens', t.withMetric], ['video', t.withVideo], ['aggregateRating', t.withRating],
    ];
    for (const [label, n] of show) {
      console.log('  ' + label.padEnd(22) + String(n).padStart(7) + '  ' + pct(n, t.recipes));
    }
    const top = [...cuisines.entries()].sort((a, b) => b[1] - a[1]).slice(0, 20);
    console.log('\ntop cuisines: ' + top.map(([c, n]) => c + '(' + n + ')').join(', '));
  }

  if (argv.includes('--dupes')) {
    const dupes = [...titles.entries()].filter(([, n]) => n > 1).sort((a, b) => b[1] - a[1]);
    console.log(
      '\n' + dupes.length + ' titles captured more than once (' +
      dupes.reduce((a, [, n]) => a + n - 1, 0) + ' extra rows)',
    );
    for (const [k, n] of dupes.slice(0, 20)) console.log('  ' + String(n).padStart(3) + '  ' + k);
  }
}

// `readShard` is imported by corpus_export.mjs, so main() must not run on import.
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}
