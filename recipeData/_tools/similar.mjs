// The same dish, cooked by different people.
//
//   node similar.mjs                     # dishes with the most distinct chefs
//   node similar.mjs --min-chefs 8
//   node similar.mjs --dish "banana bread"   # every capture of one dish
//   node similar.mjs --summary           # how much of the corpus overlaps at all
//
// This is the question the corpus was collected to be able to answer: a recipe vault
// whose whole point is forking and version history needs to know whether real cooks
// publish the same dish differently, and how differently.
//
// Two titles are the same dish when their *content words* match as a set. Site
// furniture is stripped first — "Easy", "Best", "Homemade", "Recipe", "(Video)",
// "in 30 Minutes" — because those are the blogger's SEO, not the dish. Word ORDER is
// ignored, so "Grilled Dijon Chicken" and "Dijon Grilled Chicken" are one dish, which
// is the same judgement `titleOverlap` makes in the scraper.
//
// It deliberately does NOT cluster loosely. "Chocolate Chip Cookies" and "Brown
// Butter Chocolate Chip Cookies" stay two dishes, because the second is a different
// recipe that a cook would choose between — merging them would overstate the overlap
// and hide exactly the variation this is meant to measure.
import { createReadStream } from 'node:fs';
import { createInterface } from 'node:readline';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const INDEX = resolve(HERE, '../../corpus/index.jsonl');

// Words that say nothing about which dish this is.
const NOISE = new Set([
  'recipe', 'recipes', 'easy', 'best', 'the', 'a', 'an', 'and', 'or', 'with', 'for',
  'homemade', 'simple', 'quick', 'classic', 'authentic', 'traditional', 'perfect',
  'ultimate', 'my', 'our', 'your', 'how', 'to', 'make', 'making', 'video', 'gluten',
  'free', 'vegan', 'keto', 'healthy', 'low', 'carb', 'in', 'minutes', 'minute', 'of',
  'style', 'super', 'delicious', 'amazing', 'favorite', 'favourite', 'better', 'than',
  'от', 'new', 'old', 'fashioned', 'real', 'great', 'good', 'moist', 'crispy', 'creamy',
  'from', 'scratch', 'one', 'pot', 'pan', 'sheet', 'instant', 'air', 'fryer', 'slow',
  'cooker', 'crockpot', 'no', 'bake', 'baked', 'copycat',
]);

const dishKey = (title) => {
  const words = String(title || '')
    .normalize('NFKC')
    .toLowerCase()
    .replace(/\([^)]*\)/g, ' ')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .split(' ')
    .filter((w) => w && w.length > 1 && !NOISE.has(w));
  // A set, so word order does not make two captures of one dish look like two dishes.
  return [...new Set(words)].sort().join(' ');
};

const arg = (f) => {
  const i = process.argv.indexOf(f);
  return i >= 0 ? process.argv[i + 1] : null;
};

async function main() {
  const minChefs = Number(arg('--min-chefs')) || 6;
  const wanted = arg('--dish');
  const summary = process.argv.includes('--summary');
  const limit = Number(arg('--limit')) || 25;

  const dishes = new Map();
  let total = 0;

  const rl = createInterface({ input: createReadStream(INDEX, 'utf8'), crlfDelay: Infinity });
  for await (const line of rl) {
    if (!line.trim()) continue;
    let r;
    try {
      r = JSON.parse(line);
    } catch {
      continue;
    }
    total++;
    const key = dishKey(r.title);
    if (!key || key.split(' ').length < 2) continue; // one content word is not a dish
    let d = dishes.get(key);
    if (!d) {
      d = { key, title: r.title, titles: new Map(), n: 0, chefs: new Set(), groups: new Set(), rows: [] };
      dishes.set(key, d);
    }
    d.n++;
    // Label the cluster with its most common title. Taking the first capture made the
    // chocolate-chip-cookie cluster read as "Gluten-free Chocolate Chip Cookies",
    // which is one member's framing presented as the dish's name.
    d.titles.set(r.title, (d.titles.get(r.title) || 0) + 1);
    if (r.chef) d.chefs.add(r.chef);
    if (r.group) d.groups.add(r.group);
    if (d.rows.length < 400) d.rows.push(r);
  }

  if (wanted) {
    const key = dishKey(wanted);
    const d = dishes.get(key);
    if (!d) {
      console.log('no dish matching ' + JSON.stringify(wanted) + ' (key: ' + JSON.stringify(key) + ')');
      return;
    }
    console.log(d.n + ' captures of "' + d.title + '" from ' + d.chefs.size + ' chefs / ' + d.groups.size + ' groups\n');
    for (const r of d.rows.slice(0, limit)) {
      console.log(
        (r.chef || '—').slice(0, 26).padEnd(28) +
        (r.group || '').slice(0, 26).padEnd(28) +
        String(r.ingredients).padStart(3) + ' ing  ' +
        String(r.steps).padStart(3) + ' steps  ' +
        (r.minutes != null ? String(r.minutes).padStart(4) + ' min  ' : '   —  min  ') +
        (r.url || ''),
      );
    }
    return;
  }

  const all = [...dishes.values()];
  const shared = all.filter((d) => d.chefs.size >= 2);

  if (summary) {
    const rowsInShared = shared.reduce((a, d) => a + d.n, 0);
    const buckets = { '2-3 chefs': 0, '4-7': 0, '8-15': 0, '16+': 0 };
    for (const d of shared) {
      const c = d.chefs.size;
      if (c <= 3) buckets['2-3 chefs']++;
      else if (c <= 7) buckets['4-7']++;
      else if (c <= 15) buckets['8-15']++;
      else buckets['16+']++;
    }
    console.log('indexed recipes           ' + total.toLocaleString('en-US'));
    console.log('distinct dishes           ' + all.length.toLocaleString('en-US'));
    console.log('dishes with 2+ chefs      ' + shared.length.toLocaleString('en-US'));
    console.log('recipes in those dishes   ' + rowsInShared.toLocaleString('en-US') +
      '  (' + ((rowsInShared * 100) / total).toFixed(1) + '% of the corpus)');
    console.log('\ndishes by how many chefs cooked them');
    for (const [k, v] of Object.entries(buckets)) console.log('  ' + k.padEnd(12) + v.toLocaleString('en-US'));
    return;
  }

  for (const d of shared) {
    d.title = [...d.titles.entries()].sort((a, b) => b[1] - a[1] || a[0].length - b[0].length)[0][0];
  }
  shared.sort((a, b) => b.chefs.size - a.chefs.size || b.n - a.n);
  console.log('dish'.padEnd(46) + 'chefs  groups  captures   spread of ingredient counts');
  for (const d of shared.slice(0, limit)) {
    const ing = d.rows.map((r) => r.ingredients).sort((a, b) => a - b);
    const lo = ing[0];
    const hi = ing[ing.length - 1];
    const mid = ing[Math.floor(ing.length / 2)];
    console.log(
      d.title.slice(0, 44).padEnd(46) +
      String(d.chefs.size).padStart(5) + String(d.groups.size).padStart(8) +
      String(d.n).padStart(10) + '   ' + lo + '–' + hi + ' (median ' + mid + ')',
    );
  }
  console.log('\n' + shared.length.toLocaleString('en-US') + ' dishes have been cooked by 2 or more chefs (min shown: ' + minChefs + ')');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
