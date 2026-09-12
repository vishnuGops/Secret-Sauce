// Probe many candidate sources at once and print one line each.
//
//   node probe_batch.mjs candidates/tier1.json
//   node probe_batch.mjs candidates/tier1.json --only kingarthurbaking.com
//
// Concurrency is per HOST, never per path: six different domains at once is six
// sites each seeing one request at a time, which is the polite reading of a
// crawl-delay. The full result lands in _reports/probes/<file>.json; stdout stays
// one line per site so a 60-site sweep is readable.
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { dirname, resolve, basename } from 'node:path';
import { fileURLToPath } from 'node:url';
import { probeSite } from './probe_site.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, '..');

const CONCURRENCY = 6;

// A source with a 20-second Crawl-delay and forty sitemaps to walk can hold a worker
// for a quarter of an hour, and the batch writes nothing until every source returns —
// so one slow site made a 99-source sweep look hung and produced no report at all.
// Each source now gets a deadline and reports what it had.
const SOURCE_TIMEOUT_MS = 6 * 60 * 1000;

const withDeadline = (promise, ms, onTimeout) =>
  Promise.race([
    promise,
    new Promise((resolve) => setTimeout(() => resolve(onTimeout()), ms).unref?.()),
  ]);

/** Run `fn` over `items` with at most `n` in flight. Order of results is preserved. */
export async function mapLimit(items, n, fn) {
  const out = new Array(items.length);
  let next = 0;
  const workers = Array.from({ length: Math.min(n, items.length) }, async () => {
    for (;;) {
      const i = next++;
      if (i >= items.length) return;
      try {
        out[i] = await fn(items[i], i);
      } catch (e) {
        out[i] = { error: String(e && e.message ? e.message : e) };
      }
    }
  });
  await Promise.all(workers);
  return out;
}

const DEFAULT_EXCLUDE =
  /\/(about|contact|privacy|terms|disclosure|shop|store|subscribe|newsletter|search|tag|tags|category|categories|author|page|web-stories|wp-content|feed)(\/|$)|\.(jpg|png|pdf|webp)$/i;

function line(p) {
  if (p.error) return 'ERROR             ' + (p.homepage || '?') + '  ' + p.error;
  const cand = p.sitemap ? p.sitemap.candidates : 0;
  const hit = p.samples ? p.samples.filter((s) => s.matched).length + '/' + p.samples.length : '-';
  const delay = p.robots && p.robots.crawlDelayMs ? ' cd=' + p.robots.crawlDelayMs : '';
  const who = (p.publishers || []).slice(0, 1).concat((p.authors || []).slice(0, 1)).join(' | ');
  return (
    (p.verdict || '?').padEnd(17) +
    p.host.padEnd(32) +
    String(cand).padStart(6) + ' urls  ' +
    ('hit ' + hit).padEnd(9) +
    delay.padEnd(9) +
    who.slice(0, 48)
  );
}

async function main() {
  const argv = process.argv.slice(2);
  const file = argv.find((a) => !a.startsWith('--'));
  if (!file) {
    console.log('usage: node probe_batch.mjs <candidates.json> [--only <host-substr>] [--sample N]');
    process.exit(1);
  }
  const onlyIdx = argv.indexOf('--only');
  const only = onlyIdx >= 0 ? argv[onlyIdx + 1] : null;
  const sampleIdx = argv.indexOf('--sample');
  const sampleSize = sampleIdx >= 0 ? Number(argv[sampleIdx + 1]) : 3;

  const all = JSON.parse(await readFile(resolve(HERE, file), 'utf8'));
  const list = all.filter((c) => !only || c.homepage.includes(only));

  console.log('probing ' + list.length + ' sources, ' + CONCURRENCY + ' hosts at a time\n');

  const results = await mapLimit(list, CONCURRENCY, async (c) => {
    const p = await withDeadline(
      probeSite(c.homepage, {
        include: c.include ? new RegExp(c.include, 'i') : null,
        exclude: c.exclude ? new RegExp(c.exclude, 'i') : DEFAULT_EXCLUDE,
        sitemapInclude: c.sitemapInclude ? new RegExp(c.sitemapInclude, 'i') : null,
        sampleSize,
        limit: c.limit || 6000,
        maxSitemaps: c.maxSitemaps || 40,
      }),
      SOURCE_TIMEOUT_MS,
      () => ({ homepage: c.homepage, host: new URL(c.homepage).hostname, robots: {}, verdict: 'timeout' }),
    );
    p.candidate = c;
    console.log(line(p));
    return p;
  });

  const outFile = resolve(ROOT, '_reports/probes', basename(file));
  await mkdir(dirname(outFile), { recursive: true });
  await writeFile(outFile, JSON.stringify(results, null, 2) + '\n', 'utf8');

  const byVerdict = {};
  for (const r of results) byVerdict[r.verdict || 'error'] = (byVerdict[r.verdict || 'error'] || 0) + 1;
  const usable = results.filter((r) => r.verdict === 'ok' || r.verdict === 'partial');
  console.log(
    '\n' + JSON.stringify(byVerdict) +
    '\nusable=' + usable.length +
    ' candidateUrls=' + usable.reduce((a, r) => a + (r.sitemap ? r.sitemap.candidates : 0), 0),
  );
  console.log('written ' + outFile);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
