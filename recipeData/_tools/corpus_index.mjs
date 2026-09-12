// Roll the shards up into two directories that answer the question the corpus was
// collected to answer: who gets the credit.
//
//   node corpus_index.mjs
//     -> corpus/chefs.json        every named person, their groups, their recipes
//     -> corpus/restaurants.json  every chain named by a recipe, and by whom
//     -> corpus/groups.json       every publishing entity, with its chef roster
//
// These are derived files: delete them and re-run. They exist because "158 recipes
// from 15 chefs" was a sentence someone could hold in their head and "58,000 recipes
// from 164 sources" is not — the roster is the only way to see whether the corpus is
// one publisher wearing many hats or a genuinely wide set of cooks.
//
// A chef is keyed on their *name*, normalised. That is deliberately imperfect: two
// people called "Sarah" on two blogs collapse into one row, and a byline written
// "Nagi" on one page and "Nagi Maehashi" on another stays two. Both are visible in
// the output (`groups` with more than one entry, and near-duplicate names), which is
// better than a fuzzy match that silently merges strangers.
import { readdir, writeFile, readFile } from 'node:fs/promises';
import { createWriteStream } from 'node:fs';
import { dirname, resolve, basename } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readShard } from './corpus_stats.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const CORPUS = resolve(HERE, '../../corpus');
const IN = resolve(CORPUS, 'recipes');

// Keying on ASCII letters alone collapses every non-Latin byline into the SAME key:
// Korean, Cyrillic, Japanese and Chinese names all normalise to the empty string, so
// one row in chefs.json claimed recipes from a Korean community site and a Bulgarian
// dessert blog at once. Unicode letter/number classes keep the scripts apart.
const nameKey = (s) =>
  String(s || '')
    .normalize('NFKC')
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim();

// A slug has to stay URL-safe, so it drops to ASCII — but a name with no ASCII at all
// would then slug to nothing and collide with every other such name. Fall back to a
// short stable hash of the real key rather than letting them merge.
const slugOf = (s) => {
  const ascii = nameKey(s)
    .normalize('NFKD')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
  if (ascii) return ascii.slice(0, 80);
  let h = 0;
  for (const ch of nameKey(s)) h = (h * 31 + ch.codePointAt(0)) >>> 0;
  return 'chef-' + h.toString(36);
};

async function main() {
  let files = [];
  try {
    files = (await readdir(IN)).filter((f) => f.endsWith('.jsonl')).sort();
  } catch {
    console.log('no shards at ' + IN);
    return;
  }

  const reg = await readFile(resolve(CORPUS, 'sources.json'), 'utf8')
    .then(JSON.parse)
    .catch(() => ({ sources: [] }));
  const srcBySlug = new Map(reg.sources.map((s) => [s.slug, s]));

  const chefs = new Map();
  const groups = new Map();
  const chains = new Map();
  let recipes = 0;

  // A one-line-per-recipe table of contents. The shards are the data; this is the
  // thing a person can actually open — 50,000 recipes is not a directory listing you
  // can read, and every question starts with "what is in here".
  const toc = createWriteStream(resolve(CORPUS, 'index.jsonl'), { flags: 'w' });

  for (const f of files) {
    const sourceSlug = basename(f, '.jsonl');
    const src = srcBySlug.get(sourceSlug) || {};
    for await (const rec of readShard(resolve(IN, f))) {
      recipes++;
      const a = rec.attribution || {};
      const e = rec.entity || {};

      const g = groups.get(sourceSlug) || {
        slug: sourceSlug,
        name: e.name || src.name || sourceSlug,
        kind: e.kind || src.kind || 'publication',
        homepage: e.homepage || src.homepage || null,
        country: e.country ?? src.country ?? null,
        recipes: 0,
        chefs: new Set(),
        sample: [],
      };
      g.recipes++;
      if (g.sample.length < 3) g.sample.push(rec.title);
      groups.set(sourceSlug, g);

      if (a.chef) {
        const key = nameKey(a.chef);
        g.chefs.add(key);
        const c = chefs.get(key) || {
          slug: slugOf(a.chef),
          name: a.chef,
          recipes: 0,
          groups: new Set(),
          kinds: new Set(),
          bylineFrom: new Set(),
          sample: [],
        };
        c.recipes++;
        c.groups.add(e.name || sourceSlug);
        if (e.kind) c.kinds.add(e.kind);
        if (a.chefSource) c.bylineFrom.add(a.chefSource);
        if (c.sample.length < 3) c.sample.push({ title: rec.title, url: a.sourceUrl });
        chefs.set(key, c);
      }

      toc.write(JSON.stringify({
        slug: rec.slug,
        title: rec.title,
        chef: a.chef || null,
        group: e.name || sourceSlug,
        kind: e.kind || null,
        source: sourceSlug,
        url: a.sourceUrl || (rec.source && rec.source.finalUrl) || null,
        cuisine: (rec.cuisine || [])[0] || null,
        category: (rec.category || [])[0] || null,
        servings: rec.yield ? rec.yield.servings : null,
        minutes: rec.timing ? (rec.timing.totalMinutes ?? null) : null,
        ingredients: rec.ingredientGroups.reduce((x, g2) => x + g2.items.length, 0),
        steps: rec.steps.length,
        image: (rec.media && rec.media.coverImages && rec.media.coverImages[0]) || null,
        copycat: !!a.isCopycat,
        chains: (a.restaurantMentioned || []).map((m) => m.name),
      }) + '\n');

      for (const m of a.restaurantMentioned || []) {
        const key = nameKey(m.name);
        const r = chains.get(key) || {
          name: m.name,
          slug: slugOf(m.name),
          recipes: 0,
          highConfidence: 0,
          namedBy: new Set(),
          sample: [],
        };
        r.recipes++;
        if (m.confidence === 'high') r.highConfidence++;
        r.namedBy.add(e.name || sourceSlug);
        if (r.sample.length < 3) r.sample.push({ title: rec.title, url: a.sourceUrl });
        chains.set(key, r);
      }
    }
  }

  await new Promise((r) => toc.end(r));

  const chefList = [...chefs.values()]
    .map((c) => ({
      slug: c.slug,
      name: c.name,
      recipes: c.recipes,
      groups: [...c.groups],
      groupKinds: [...c.kinds],
      bylineFrom: [...c.bylineFrom],
      sample: c.sample,
    }))
    .sort((a, b) => b.recipes - a.recipes);

  const groupList = [...groups.values()]
    .map((g) => ({
      slug: g.slug,
      name: g.name,
      kind: g.kind,
      homepage: g.homepage,
      country: g.country,
      recipes: g.recipes,
      namedChefs: g.chefs.size,
      sample: g.sample,
    }))
    .sort((a, b) => b.recipes - a.recipes);

  const chainList = [...chains.values()]
    .map((r) => ({
      slug: r.slug,
      name: r.name,
      recipes: r.recipes,
      highConfidence: r.highConfidence,
      namedBy: [...r.namedBy],
      sample: r.sample,
    }))
    .sort((a, b) => b.recipes - a.recipes);

  const stamp = new Date().toISOString();
  await writeFile(
    resolve(CORPUS, 'chefs.json'),
    JSON.stringify({ generatedAt: stamp, recipes, chefs: chefList.length, entries: chefList }, null, 2) + '\n',
    'utf8',
  );
  await writeFile(
    resolve(CORPUS, 'groups.json'),
    JSON.stringify({ generatedAt: stamp, recipes, groups: groupList.length, entries: groupList }, null, 2) + '\n',
    'utf8',
  );
  await writeFile(
    resolve(CORPUS, 'restaurants.json'),
    JSON.stringify({ generatedAt: stamp, chains: chainList.length, entries: chainList }, null, 2) + '\n',
    'utf8',
  );

  console.log(
    'index.jsonl written\n' +
    recipes + ' recipes  ' + chefList.length + ' named chefs  ' +
    groupList.length + ' groups  ' + chainList.length + ' chains mentioned',
  );
  console.log('\ntop chefs');
  for (const c of chefList.slice(0, 12)) {
    console.log('  ' + String(c.recipes).padStart(5) + '  ' + c.name.padEnd(28) + c.groups.join(', ').slice(0, 44));
  }
  console.log('\ntop chains named');
  for (const r of chainList.slice(0, 12)) {
    console.log('  ' + String(r.recipes).padStart(5) + '  ' + r.name.padEnd(24) + 'high=' + r.highConfidence + '  by ' + r.namedBy.slice(0, 2).join(', ').slice(0, 40));
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
