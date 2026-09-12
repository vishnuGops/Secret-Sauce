// Promote probe results into the harvester's source registry.
//
//   node promote.mjs _reports/probes/tier1-brands.json
//   node promote.mjs _reports/probes/tier1-brands.json --include-partial=false
//
// A probe says whether a site is reachable, allowed, and shaped like a recipe site.
// This is the step that turns that answer into a commitment to crawl it. Sources are
// keyed by slug and merged, so re-running after a better probe updates a row instead
// of duplicating it, and `enabled: false` set by hand is never overwritten.
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, '../..');
const SOURCES = resolve(REPO, 'corpus/sources.json');

const slugify = (s) =>
  String(s)
    .normalize('NFKD')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 60);

async function main() {
  const argv = process.argv.slice(2);
  const file = argv.find((a) => !a.startsWith('--'));
  const keepPartial = !argv.includes('--ok-only');
  const batchIdx = argv.indexOf('--batch');
  const batch = batchIdx >= 0 ? argv[batchIdx + 1] : null;
  const probes = JSON.parse(await readFile(resolve(HERE, file), 'utf8'));

  const reg = await readFile(SOURCES, 'utf8').then(JSON.parse).catch(() => ({
    schemaVersion: 1,
    note: 'Sources the corpus harvester is allowed to crawl. See corpus/README.md.',
    sources: [],
  }));
  const bySlug = new Map(reg.sources.map((s) => [s.slug, s]));

  let added = 0;
  let updated = 0;
  let skipped = 0;
  for (const p of probes) {
    const c = p.candidate || {};
    const ok = p.verdict === 'ok' || (keepPartial && p.verdict === 'partial');
    if (!ok || !p.sitemap || !p.sitemap.candidates) {
      skipped++;
      continue;
    }
    // A candidate generated from a bare domain list carries the domain as its name.
    // The page itself knows better: schema.org `publisher` is the site's own brand,
    // so prefer it when the candidate admits its name was generated.
    const discovered = (p.publishers || [])[0] || null;
    const name = c.nameAuto && discovered ? discovered : c.name || p.host;
    const slug = c.slug || slugify(name);
    const prev = bySlug.get(slug) || {};
    const row = {
      ...prev,
      id: prev.id || 'src_' + slug,
      slug,
      name,
      kind: c.kind || 'publication',
      // Which sweep this source arrived in. `harvest.mjs --batch <name>` uses it to
      // pick up newly promoted sources without touching shards an already-running
      // harvester has open.
      batch: batch || prev.batch || 'tier1',
      homepage: p.homepage,
      country: c.country ?? prev.country ?? null,
      // Labelled, never inferred: a non-English source is a deliberate inclusion and
      // anything downstream has to be able to filter it out.
      language: c.language ?? prev.language ?? 'en',
      include: c.include ?? prev.include ?? null,
      exclude: c.exclude ?? prev.exclude ?? null,
      sitemapInclude: c.sitemapInclude ?? prev.sitemapInclude ?? null,
      limit: c.limit ?? prev.limit ?? null,
      delayMs: c.delayMs ?? prev.delayMs ?? (p.robots && p.robots.crawlDelayMs) ?? null,
      enabled: prev.enabled !== undefined ? prev.enabled : true,
      probe: {
        at: new Date().toISOString().slice(0, 10),
        verdict: p.verdict,
        candidates: p.sitemap.candidates,
        sampleHit: p.samples ? p.samples.filter((s) => s.matched).length + '/' + p.samples.length : null,
        robots: p.robots ? p.robots.summary : null,
        publishers: p.publishers || [],
        authors: (p.authors || []).slice(0, 4),
        wprm: !!(p.samples || []).some((s) => s.wprm),
      },
    };
    if (bySlug.has(slug)) updated++;
    else added++;
    bySlug.set(slug, row);
  }

  reg.sources = [...bySlug.values()].sort((a, b) => a.slug.localeCompare(b.slug));
  reg.updatedAt = new Date().toISOString();
  await mkdir(dirname(SOURCES), { recursive: true });
  await writeFile(SOURCES, JSON.stringify(reg, null, 2) + '\n', 'utf8');

  console.log(
    'added=' + added + ' updated=' + updated + ' skipped=' + skipped +
    '  registry now ' + reg.sources.length + ' sources, ' +
    reg.sources.reduce((a, s) => a + (s.probe ? s.probe.candidates : 0), 0) + ' candidate urls',
  );
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
