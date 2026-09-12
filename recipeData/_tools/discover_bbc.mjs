// Chef discovery for bbc.co.uk/food. Given chef slugs, reads each chef's index
// page and emits manifest entries: chef metadata plus their recipe URLs.
//
//   node recipeData/_tools/discover_bbc.mjs --check nigella_lawson rick_stein
//   node recipeData/_tools/discover_bbc.mjs --write 10 nigella_lawson rick_stein ...
//
// --check reports what each slug resolves to without writing anything.
// --write <n> appends/updates manifest.json with up to n recipes per chef.
import { readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { fetchHtml } from './extract.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const MANIFEST = resolve(HERE, 'manifest.json');
const BASE = 'https://www.bbc.co.uk';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const decode = (s) =>
  String(s)
    .replace(/&amp;/g, '&')
    .replace(/&#0?39;/g, "'")
    .replace(/&quot;/g, '"')
    .replace(/&nbsp;/g, ' ')
    .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(Number(d)));

const strip = (s) => decode(String(s).replace(/<[^>]+>/g, ' ')).replace(/\s+/g, ' ').trim();

export function parseChefPage(html) {
  // Slugs contain hyphens as well as underscores; matching only [a-z0-9_] here
  // truncated "no-churn-ice-cream" to "no" and produced 404s.
  const urls = [...new Set((html.match(/\/food\/recipes\/[a-z0-9_-]+/gi) || []))].map((p) => BASE + p);

  const h1 = html.match(/<h1[^>]*>([\s\S]*?)<\/h1>/i);
  const name = h1 ? strip(h1[1]) : null;

  const desc = html.match(/<meta\s+name="description"\s+content="([^"]*)"/i);
  const og = html.match(/<meta\s+property="og:image"\s+content="([^"]*)"/i);

  return {
    name,
    bio: desc ? decode(desc[1]).trim() : null,
    avatarUrl: og ? decode(og[1]).trim() : null,
    recipes: urls,
  };
}

export async function discoverChef(slug) {
  const url = BASE + '/food/chefs/' + slug;
  const res = await fetchHtml(url);
  if (res.status >= 400) return { slug, ok: false, status: res.status, url };
  const parsed = parseChefPage(res.html);
  return { slug, ok: parsed.recipes.length > 0, status: res.status, url, ...parsed };
}

async function main() {
  const argv = process.argv.slice(2);
  const mode = argv[0];
  let perChef = 10;
  let slugs = argv.slice(1);
  if (mode === '--write') {
    perChef = Number(argv[1]);
    slugs = argv.slice(2);
  }
  if (!slugs.length) throw new Error('usage: --check <slugs...> | --write <n> <slugs...>');

  const found = [];
  for (const slug of slugs) {
    const c = await discoverChef(slug);
    await sleep(1200);
    console.log(
      (c.ok ? 'ok   ' : 'FAIL ') + slug.padEnd(26) +
      'status=' + c.status + ' recipes=' + (c.recipes ? c.recipes.length : 0) +
      '  ' + (c.name || ''),
    );
    if (c.ok) found.push(c);
  }

  if (mode !== '--write') return;

  let manifest;
  try {
    manifest = JSON.parse(await readFile(MANIFEST, 'utf8'));
  } catch {
    manifest = { schemaVersion: 1, chefs: [] };
  }
  const bySlug = new Map(manifest.chefs.map((c) => [c.slug, c]));

  for (const c of found) {
    const slug = c.slug.replace(/_/g, '-');
    const existing = bySlug.get(slug);
    bySlug.set(slug, {
      // A stable id, not a database id: the app's chef is a profiles row created
      // later, and its uuid is recorded in chefs.json under appProfileId.
      id: 'chef_' + slug,
      slug,
      name: c.name,
      bio: c.bio,
      country: existing ? existing.country : null,
      homepage: c.url,
      avatarUrl: c.avatarUrl,
      source: 'bbc.co.uk/food',
      recipes: c.recipes.slice(0, perChef),
    });
  }

  manifest.chefs = [...bySlug.values()];
  await writeFile(MANIFEST, JSON.stringify(manifest, null, 2) + '\n', 'utf8');
  console.log('\nmanifest: ' + manifest.chefs.length + ' chefs, ' +
    manifest.chefs.reduce((a, c) => a + c.recipes.length, 0) + ' recipe urls');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}
