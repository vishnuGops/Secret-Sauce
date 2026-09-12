// The scale harvester. Turns `corpus/sources.json` into `corpus/recipes/<slug>.jsonl`.
//
//   node harvest.mjs --discover            # sitemap sweep for every source, cached
//   node harvest.mjs --discover --only kingarthurbaking
//   node harvest.mjs                       # fetch + extract everything pending
//   node harvest.mjs --only delish --limit 200
//   node harvest.mjs --status              # what is done, what is left
//
// Why this is not `scrape.mjs` with a bigger manifest:
//
//   - One file per recipe stops being free at ~40,000 recipes. Each source is one
//     append-only JSONL shard instead: resumable by construction, one open handle,
//     and it is the shape a loader would want anyway.
//   - Politeness is per HOST and enforced by a queue, not by a sleep in a loop.
//     Six sources run at once because they are six different hosts; two sources on
//     one host would still take turns.
//   - robots.txt decides, per URL, every time (see robots.mjs). A source whose
//     robots.txt becomes unreachable mid-run stops rather than continuing on the
//     copy it read an hour ago.
//
// Attribution is the point of the exercise, so every record carries both halves:
// `entity` is the group the recipe belongs to (brand, restaurant, publication,
// chef), and `attribution.chef` is the person named on that page when there is one.
// Neither is inferred from the other.
import { readFile, writeFile, mkdir, appendFile, stat } from 'node:fs/promises';
import { createWriteStream } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  fetchHtml, jsonLdBlocks, findRecipeNode, pageTitleOf, toCorpusRecipe, titleOverlap,
  decodeEntities,
} from './extract.mjs';
import { applyBbcEnrichment } from './enrich_bbc.mjs';
import { applyWprmEnrichment } from './enrich_wprm.mjs';
import { robotsFor } from './robots.mjs';
import { walkSitemaps, SITEMAP_FALLBACKS } from './sitemap.mjs';
import { detectBrands, isCopycat } from './brands.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, '../..');
const CORPUS = resolve(REPO, 'corpus');
const SOURCES = resolve(CORPUS, 'sources.json');

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const MIN_DELAY_MS = 900;

// ---------------------------------------------------------------- host queues

/**
 * One serial lane per host, each with its own delay. Two sources that share a host
 * share a lane, so "concurrency 8" never means eight requests at one domain.
 */
const LANES = new Map();
function lane(host) {
  if (!LANES.has(host)) LANES.set(host, { chain: Promise.resolve(), last: 0 });
  return LANES.get(host);
}
function schedule(host, delayMs, fn) {
  const l = lane(host);
  const run = l.chain.then(async () => {
    const wait = l.last + delayMs - Date.now();
    if (wait > 0) await sleep(wait);
    l.last = Date.now();
    return fn();
  });
  // Keep the chain alive even when a task rejects, or one failure stalls the host.
  l.chain = run.then(() => {}, () => {});
  return run;
}

// ------------------------------------------------------------------- plumbing

const readJson = async (p, fallback) => {
  try {
    return JSON.parse(await readFile(p, 'utf8'));
  } catch {
    return fallback;
  }
};

const writeJson = async (p, v) => {
  await mkdir(dirname(p), { recursive: true });
  await writeFile(p, JSON.stringify(v, null, 2) + '\n', 'utf8');
};

export function slugify(s) {
  return String(s)
    .normalize('NFKD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 90);
}

const ENRICHERS = [
  [/(^|\.)bbc\.co\.uk$/, applyBbcEnrichment],
];

/** WP Recipe Maker markup is the same on every site that uses it; detect, don't list. */
function enrich(recipe, html, url) {
  const host = new URL(url).hostname;
  const hit = ENRICHERS.find(([re]) => re.test(host));
  if (hit) {
    hit[1](recipe, html);
    return 'bbc';
  }
  if (/wprm-recipe-(ingredient|instruction|equipment)/.test(html)) {
    applyWprmEnrichment(recipe, html);
    return 'wprm';
  }
  return null;
}

const asArray = (v) => (v == null ? [] : Array.isArray(v) ? v : [v]);
const nameOf = (v) => {
  for (const x of asArray(v)) {
    if (typeof x === 'string' && x.trim()) return x.trim();
    if (x && typeof x.name === 'string' && x.name.trim()) return x.name.trim();
  }
  return null;
};

// A CMS placeholder is not a chef. The bare words are rejected outright; the
// second half catches the site-branded variants ("100 Days Admin") that slipped
// through an exact match. `Editorial Team` and `... Kitchens` are deliberately
// kept: not a person, but a real byline the publisher chose.
const BAD_AUTHOR =
  /^(admin|administrator|editor|staff|team|guest|user|wordpress|author|no author)$/i;
const BAD_AUTHOR_WORD = /(^|[^a-z])(admin|administrator|webmaster|wordpress|guest (author|post))([^a-z]|$)/i;

/**
 * The person to credit, when the Recipe node itself names nobody.
 *
 * A great many WordPress recipe sites attach the byline to the *Article* or
 * *WebPage* node in the same `@graph` and leave `Recipe.author` off entirely —
 * copykat.com has no author on any of 169 recipes read that way. The byline is on
 * the page; it is just one node over. Order is most-specific first, and a generic
 * CMS placeholder ("admin") is treated as no author rather than as a chef.
 */
function authorFallback(blocks, html) {
  const wanted = new Set(['Article', 'BlogPosting', 'NewsArticle', 'WebPage', 'Recipe', 'HowTo']);
  const found = [];
  const seen = new Set();
  const walk = (n) => {
    if (!n || typeof n !== 'object' || seen.has(n)) return;
    seen.add(n);
    if (Array.isArray(n)) {
      n.forEach(walk);
      return;
    }
    const types = asArray(n['@type']);
    if (types.some((t) => wanted.has(t)) && n.author) {
      const name = nameOf(n.author);
      if (name) found.push(name);
    }
    if (types.includes('Person') && typeof n.name === 'string') found.push(n.name);
    for (const v of Object.values(n)) if (v && typeof v === 'object') walk(v);
  };
  walk(blocks);

  for (const c of found) {
    const t = c.trim();
    if (t && !BAD_AUTHOR.test(t) && !BAD_AUTHOR_WORD.test(t)) return t;
  }

  const html_ = String(html);
  const patterns = [
    /<meta[^>]+name=["']author["'][^>]+content=["']([^"']+)["']/i,
    /class="[^"]*wprm-recipe-author[^"]*"[^>]*>([^<]{2,60})</i,
    /rel=["']author["'][^>]*>([^<]{2,60})</i,
    /class="[^"]*author[^"]*name[^"]*"[^>]*>\s*(?:<[^>]+>\s*)*([^<]{2,60})</i,
  ];
  for (const re of patterns) {
    const m = html_.match(re);
    if (!m) continue;
    const t = m[1].replace(/\s+/g, ' ').trim();
    if (t && !BAD_AUTHOR.test(t) && !BAD_AUTHOR_WORD.test(t)) return t;
  }
  return null;
}

// Index pages a sitemap lists beside its posts: tag, category, author, paging,
// stories, feeds. They are not recipes and each one costs a request to find that
// out — archanaskitchen.com's sitemap is 10,603 URLs of which the great majority
// are `/tags/...`, and 450 requests into it the harvester had kept nothing. Applied
// to EVERY source in addition to its own `exclude`, because this is a property of
// how sitemaps are built rather than of any one site.
const INDEX_PAGE = new RegExp(
  '/(tag|tags|category|categories|cuisine|course|courses|topic|topics|collection|collections' +
  '|author|authors|profile|page|search|shop|store|product|products|cart|account' +
  '|about|contact|privacy|terms|disclosure|disclaimer|subscribe|newsletter|sitemap' +
  '|web-stories|stories|videos|video|gallery|feed|comments|wp-content|wp-json)(/|$)' +
  '|\.(jpe?g|png|gif|webp|svg|pdf|mp4|zip)$',
  'i',
);

/** `src.exclude` and the global index-page filter, as one thing walkSitemaps can call. */
function excluderFor(src) {
  const own = src.exclude ? new RegExp(src.exclude, 'i') : null;
  return { test: (u) => INDEX_PAGE.test(u) || (own ? own.test(u) : false) };
}


/**
 * What the site calls itself. Most personal food blogs publish no `publisher` on the
 * Recipe node at all, so a source promoted from a bare domain list keeps the domain
 * as its display name forever. `og:site_name` and the `WebSite`/`Organization` node
 * are where that name actually lives.
 */
function siteNameOf(blocks, html) {
  const og = String(html).match(/<meta[^>]+property=["']og:site_name["'][^>]+content=["']([^"']+)["']/i);
  // og:site_name arrives HTML-encoded: "Dianne&#039;s Vegan Kitchen".
  if (og && og[1].trim()) return decodeEntities(og[1]).replace(/\s+/g, ' ').trim();

  let found = null;
  const seen = new Set();
  const walk = (n) => {
    if (found || !n || typeof n !== 'object' || seen.has(n)) return;
    seen.add(n);
    if (Array.isArray(n)) {
      n.forEach(walk);
      return;
    }
    const types = asArray(n['@type']);
    if ((types.includes('WebSite') || types.includes('Organization')) && typeof n.name === 'string' && n.name.trim()) {
      found = decodeEntities(n.name).replace(/\s+/g, ' ').trim();
      return;
    }
    for (const v of Object.values(n)) if (v && typeof v === 'object') walk(v);
  };
  walk(blocks);
  return found;
}

// --------------------------------------------------------------- discovery

export async function discover(src, opts = {}) {
  const { limit = src.limit || 20000, maxSitemaps = src.maxSitemaps || 120 } = opts;
  const robots = await robotsFor(src.homepage);
  if (robots.fetchFailed) {
    return { urls: [], robots, error: 'robots-unreachable' };
  }
  const roots = [
    ...(src.sitemaps || []),
    ...robots.sitemaps,
    ...SITEMAP_FALLBACKS.map((p) => new URL(p, src.homepage).href),
  ];
  // A sitemap fetch is a request like any other, so it pays the site's crawl-delay.
  const delayMs = Math.max(robots.crawlDelayMs || 0, src.delayMs || 0, MIN_DELAY_MS);

  const walk = await walkSitemaps(roots, {
    include: src.include ? new RegExp(src.include, 'i') : null,
    exclude: excluderFor(src),
    sitemapInclude: src.sitemapInclude ? new RegExp(src.sitemapInclude, 'i') : null,
    limit,
    maxSitemaps,
    delayMs,
  });

  const allowed = walk.pages.filter((u) => robots.allows(u));
  return {
    urls: allowed,
    blockedByRobots: walk.pages.length - allowed.length,
    robots,
    tried: walk.tried,
  };
}

// ---------------------------------------------------------------- harvesting

/** Fetch one URL and turn it into a corpus record, or say why not. */
export async function harvestOne(url, src, robots) {
  const retrievedAt = new Date().toISOString();
  let res;
  try {
    res = await fetchHtml(url);
  } catch (e) {
    return { ok: false, url, reason: 'fetch-failed', detail: String(e.message) };
  }
  if (res.status >= 400) {
    return { ok: false, url, reason: 'http-' + res.status, retryAfterMs: res.retryAfterMs };
  }

  const blocks = jsonLdBlocks(res.html);
  const pageTitle = pageTitleOf(res.html);
  const node = findRecipeNode(blocks, { pageTitle, pageUrl: res.finalUrl });
  if (!node) return { ok: false, url, reason: 'no-recipe-jsonld' };

  const title = typeof node.name === 'string' ? node.name : null;
  if (!title) return { ok: false, url, reason: 'no-title' };

  // A node whose name has nothing to do with the page is a sidebar card.
  if (pageTitle && titleOverlap(title, pageTitle) < 0.15) {
    return { ok: false, url, reason: 'title-mismatch', detail: title + ' vs ' + pageTitle };
  }

  const recipeSlug = slugify(title) || slugify(new URL(res.finalUrl).pathname);
  const declared = nameOf(node.author);
  const usable_ = (v) => v && !BAD_AUTHOR.test(v) && !BAD_AUTHOR_WORD.test(v);
  const authorName = usable_(declared) ? declared : authorFallback(blocks, res.html);
  const publisherName = nameOf(node.publisher);

  const recipe = toCorpusRecipe({
    node,
    chefId: authorName ? 'chef_' + slugify(authorName) : src.id,
    chefName: authorName || src.name,
    chefSlug: authorName ? slugify(authorName) : src.slug,
    recipeSlug,
    sourceUrl: url,
    finalUrl: res.finalUrl,
    html: res.html,
    retrievedAt,
    blocks,
    pageTitle,
  });

  recipe.enrichedBy = enrich(recipe, res.html, res.finalUrl);

  // Both halves of the credit, neither inferred from the other.
  recipe.entity = {
    slug: src.slug,
    id: src.id,
    name: src.name,
    kind: src.kind,
    homepage: src.homepage,
    country: src.country || null,
    language: src.language || 'en',
  };
  // A restaurant named in the title is a *mention*, never the publisher: a copycat
  // Olive Garden soup is published by the blogger, not by Olive Garden.
  const mentioned = detectBrands(recipe.title, recipe.description, recipe.keywords.join(' '));
  recipe.attribution = {
    chef: authorName,
    chefSource: usable_(declared) ? 'jsonld-recipe-author'
      : authorName ? 'page-fallback' : null,
    group: src.name,
    groupKind: src.kind,
    publisher: publisherName || src.name,
    sourceUrl: res.finalUrl,
    restaurantMentioned: mentioned,
    isCopycat: isCopycat(recipe.title, recipe.description),
    credit:
      (authorName ? authorName + ' — ' : '') + src.name + ' (' + res.finalUrl + ')',
  };
  recipe.source.siteName = siteNameOf(blocks, res.html);
  recipe.source.robots = robots.summary;
  recipe.source.rights =
    src.rights ||
    'Recipe text belongs to ' + src.name + '. This corpus stores functional content ' +
      '(ingredients, quantities, steps) plus a link back to the source, for internal ' +
      'app testing only. Not for redistribution.';

  // The HTML hash is kept; the HTML is not. At 40,000 pages the body is the bulk.
  return { ok: true, url, recipe };
}

const countIngredients = (r) => r.ingredientGroups.reduce((a, g) => a + g.items.length, 0);

/** Cheap quality gate: a record with no ingredients or no steps is not a recipe. */
export function usable(r) {
  return countIngredients(r) > 0 && r.steps.length > 0;
}

async function harvestSource(src, opts) {
  const { limit = Infinity, keepRaw = true, onProgress, discoveredOnly = false } = opts;
  const stateFile = resolve(CORPUS, '_state', src.slug + '.json');
  const dataFile = resolve(CORPUS, 'recipes', src.slug + '.jsonl');
  const discFile = resolve(CORPUS, '_state/discovered', src.slug + '.json');

  const doneLog = resolve(CORPUS, '_state/done', src.slug + '.log');
  const state = await readJson(stateFile, {
    slug: src.slug,
    name: src.name,
    kind: src.kind,
    homepage: src.homepage,
    startedAt: new Date().toISOString(),
    done: [],
    kept: 0,
    failed: {},
    lastError: null,
  });
  const done = new Set(state.done);
  try {
    for (const line of (await readFile(doneLog, 'utf8')).split('\n')) {
      const u = line.trim();
      if (u) done.add(u);
    }
  } catch {
    /* no log yet */
  }

  let disc = await readJson(discFile, null);
  const robots = await robotsFor(src.homepage);
  if (robots.fetchFailed) {
    state.lastError = 'robots-unreachable';
    await writeJson(stateFile, state);
    return { slug: src.slug, kept: 0, skipped: 0, error: 'robots-unreachable' };
  }
  let delayMs = Math.max(robots.crawlDelayMs || 0, src.delayMs || 0, MIN_DELAY_MS);
  const host = new URL(src.homepage).hostname;

  if (!disc) {
    // Discovery is a serial sitemap walk paying the site's crawl-delay — up to two
    // minutes during which this worker fetches no recipes at all. With 244 of 397
    // sources undiscovered that is most of the fleet idling, so a separate
    // `--discover` process fills the cache while this one keeps harvesting.
    if (discoveredOnly) return { slug: src.slug, kept: 0, skipped: 0, error: 'not-discovered' };
    const d = await discover(src);
    disc = { at: new Date().toISOString(), count: d.urls.length, urls: d.urls, blockedByRobots: d.blockedByRobots };
    await writeJson(discFile, disc);
  }

  const pending = disc.urls.filter((u) => !done.has(u)).slice(0, limit === Infinity ? undefined : limit);
  if (!pending.length) return { slug: src.slug, kept: 0, skipped: 0, pending: 0 };

  await mkdir(dirname(dataFile), { recursive: true });
  const out = createWriteStream(dataFile, { flags: 'a' });
  // `state.done` is rewritten whole every N records, so a process killed between
  // flushes loses up to N answers and the next run re-fetches them — 251 duplicate
  // records across one restart, every restart. This log is appended per URL, which
  // is O(1) where rewriting the set is O(n), and it is read back at startup.
  await mkdir(dirname(doneLog), { recursive: true });
  const doneOut = createWriteStream(doneLog, { flags: 'a' });

  let kept = 0;
  let n = 0;
  let throttled = 0;
  const retry = [];

  // 429/503 is the site asking for a slower crawl, and the only correct response is
  // to give it one — for the WHOLE source, not just this URL. copykat.com answered
  // 114 of 400 requests with 429 at the 900 ms floor, and every one of those was a
  // recipe silently lost. A throttled URL is NOT marked done, so it stays pending
  // for a later run even if this pass gives up on it.
  const backOff = (retryAfterMs) => {
    throttled++;
    delayMs = Math.min(60000, Math.max(delayMs * 2, retryAfterMs || 0, 2000));
  };

  const processUrl = async (url, isRetry) => {
    if (!robots.allows(url)) {
      done.add(url);
      doneOut.write(url + '\n');
      state.failed['robots-disallow'] = (state.failed['robots-disallow'] || 0) + 1;
      return;
    }
    const res = await schedule(host, delayMs, () => harvestOne(url, src, robots));
    n++;
    if (!res.ok && (res.reason === 'http-429' || res.reason === 'http-503')) {
      backOff(res.retryAfterMs);
      if (!isRetry) retry.push(url);
      else state.failed[res.reason] = (state.failed[res.reason] || 0) + 1;
      return;
    }
    // A transport failure is not an answer about the page, so it does not close the
    // URL out. Marking these done is how 1,129 pages were silently written off in
    // the pre-backoff runs: a 429 is the site asking us to come back, and `done`
    // meant we never did.
    if (!res.ok && /^http-5|^fetch-failed$/.test(res.reason)) {
      state.failed[res.reason] = (state.failed[res.reason] || 0) + 1;
      return;
    }
    done.add(url);
    doneOut.write(url + '\n');
    if (!res.ok) {
      state.failed[res.reason] = (state.failed[res.reason] || 0) + 1;
    } else if (!usable(res.recipe)) {
      state.failed['empty-recipe'] = (state.failed['empty-recipe'] || 0) + 1;
    } else {
      const rec = res.recipe;
      if (!keepRaw) {
        delete rec.rawJsonLd;
        delete rec.unmappedFields;
      }
      out.write(JSON.stringify(rec) + '\n');
      kept++;
    }
  };

  // A source that has been asked 120 questions and answered none is not a recipe site
  // for our purposes, and every further request is one the site did not need to serve.
  // `prune.mjs` reaches the same conclusion, but only when someone runs it — one
  // source spent 930 requests on nothing while an unattended pass was in flight.
  const GIVE_UP_AFTER = 120;

  for (const url of pending) {
    if (n >= GIVE_UP_AFTER && kept === 0) {
      state.abandoned = 'no-recipes-in-' + n;
      console.log('give up ' + src.slug.padEnd(28) + 'no recipes in ' + n + ' pages');
      break;
    }
    await processUrl(url, false);
    if (n % 10 === 0) {
      state.done = [...done];
      state.kept = (state.kept || 0) + 0;
      await writeJson(stateFile, { ...state, kept: (state.keptTotal || 0) + kept, keptTotal: (state.keptTotal || 0) + kept });
      if (onProgress) onProgress({ slug: src.slug, n, kept, total: pending.length });
    }
  }

  // One retry pass at the backed-off pace, in the order they were refused.
  for (const url of retry) await processUrl(url, true);

  await new Promise((r) => out.end(r));
  await new Promise((r) => doneOut.end(r));
  state.throttled = (state.throttled || 0) + throttled;
  state.delayMs = delayMs;
  state.done = [...done];
  state.keptTotal = (state.keptTotal || 0) + kept;
  state.kept = state.keptTotal;
  state.updatedAt = new Date().toISOString();
  state.discovered = disc.urls.length;
  await writeJson(stateFile, state);
  return { slug: src.slug, kept, attempted: n, pending: disc.urls.length - done.size };
}

// -------------------------------------------------------------------- driver

async function mapLimit(items, n, fn) {
  const out = new Array(items.length);
  let next = 0;
  await Promise.all(
    Array.from({ length: Math.min(n, items.length) }, async () => {
      for (;;) {
        const i = next++;
        if (i >= items.length) return;
        try {
          out[i] = await fn(items[i], i);
        } catch (e) {
          out[i] = { slug: items[i].slug, error: String(e && e.message ? e.message : e) };
        }
      }
    }),
  );
  return out;
}

async function loadSources(only, batch) {
  const reg = await readJson(SOURCES, null);
  if (!reg) throw new Error('missing ' + SOURCES);
  let list = reg.sources.filter((s) => s.enabled !== false);
  if (batch) list = list.filter((s) => (s.batch || 'tier1') === batch);
  if (only) list = list.filter((s) => s.slug.includes(only) || s.homepage.includes(only));
  return list;
}

/**
 * One writer per shard. Two harvesters appending 15 KB JSON lines to the same file
 * is not safe — O_APPEND is atomic per write() only up to the pipe buffer — and the
 * corruption would be a half-line in the middle of a file nobody reads until later.
 */
async function withLock(slug, fn) {
  const lock = resolve(CORPUS, '_state/locks', slug + '.lock');
  const held = await readJson(lock, null);
  if (held && Date.now() - new Date(held.at).getTime() < 6 * 3600e3) {
    const alive = (() => {
      try {
        process.kill(held.pid, 0);
        return true;
      } catch {
        return false;
      }
    })();
    if (alive && held.pid !== process.pid) {
      return { slug, kept: 0, error: 'locked-by-pid-' + held.pid };
    }
  }
  await writeJson(lock, { pid: process.pid, at: new Date().toISOString() });
  try {
    return await fn();
  } finally {
    await writeJson(lock, { pid: null, at: new Date().toISOString(), releasedBy: process.pid });
  }
}

async function statusOf(src) {
  const state = await readJson(resolve(CORPUS, '_state', src.slug + '.json'), null);
  const disc = await readJson(resolve(CORPUS, '_state/discovered', src.slug + '.json'), null);
  let bytes = 0;
  try {
    bytes = (await stat(resolve(CORPUS, 'recipes', src.slug + '.jsonl'))).size;
  } catch { /* not started */ }
  return {
    slug: src.slug,
    kind: src.kind,
    discovered: disc ? disc.urls.length : 0,
    done: state ? state.done.length : 0,
    kept: state ? state.kept || 0 : 0,
    mb: +(bytes / 1e6).toFixed(1),
    failed: state ? state.failed : {},
  };
}

async function main() {
  const argv = process.argv.slice(2);
  const arg = (f, d = null) => {
    const i = argv.indexOf(f);
    return i >= 0 ? argv[i + 1] : d;
  };
  const only = arg('--only');
  const batch = arg('--batch');
  const sources = await loadSources(only, batch);

  if (argv.includes('--status')) {
    const rows = await Promise.all(sources.map(statusOf));
    rows.sort((a, b) => b.kept - a.kept);
    let kept = 0;
    let disc = 0;
    for (const r of rows) {
      kept += r.kept;
      disc += r.discovered;
      console.log(
        r.slug.padEnd(28) + r.kind.padEnd(13) +
        String(r.kept).padStart(6) + ' kept  ' +
        String(r.done).padStart(6) + '/' + String(r.discovered).padEnd(7) + ' done  ' +
        String(r.mb).padStart(6) + ' MB  ' +
        Object.entries(r.failed).map(([k, v]) => k + '=' + v).join(' '),
      );
    }
    console.log('\n' + rows.length + ' sources  kept=' + kept + '  discovered=' + disc);
    return;
  }

  if (argv.includes('--discover')) {
    const conc = Number(arg('--concurrency', 6));
    const res = await mapLimit(sources, conc, async (src) => {
      const f = resolve(CORPUS, '_state/discovered', src.slug + '.json');
      if (!argv.includes('--force') && (await readJson(f, null))) {
        const d = await readJson(f, null);
        console.log('cached  ' + src.slug.padEnd(28) + String(d.urls.length).padStart(6) + ' urls');
        return { slug: src.slug, urls: d.urls.length, cached: true };
      }
      const d = await discover(src);
      await writeJson(f, { at: new Date().toISOString(), count: d.urls.length, urls: d.urls, blockedByRobots: d.blockedByRobots });
      console.log(
        (d.urls.length ? 'ok      ' : 'EMPTY   ') + src.slug.padEnd(28) +
        String(d.urls.length).padStart(6) + ' urls' +
        (d.blockedByRobots ? '  robots-blocked=' + d.blockedByRobots : ''),
      );
      return { slug: src.slug, urls: d.urls.length };
    });
    console.log('\ntotal discovered ' + res.reduce((a, r) => a + (r.urls || 0), 0));
    return;
  }

  const conc = Number(arg('--concurrency', 6));
  const limit = arg('--limit') ? Number(arg('--limit')) : Infinity;
  const keepRaw = !argv.includes('--no-raw');
  const discoveredOnly = argv.includes('--discovered-only');

  console.log('harvesting ' + sources.length + ' sources, ' + conc + ' at a time, limit=' + limit + '\n');
  const started = Date.now();
  const res = await mapLimit(sources, conc, async (src) => {
    const r = await withLock(src.slug, () =>
      harvestSource(src, {
        limit,
        keepRaw,
        discoveredOnly,
        onProgress: (p) =>
          console.log('  ..' + p.slug.padEnd(26) + p.n + '/' + p.total + '  kept=' + p.kept),
      }));
    console.log(
      (r.error === 'not-discovered' ? 'wait ' : r.error ? 'ERR  ' : 'done ') + src.slug.padEnd(28) +
      'kept=' + String(r.kept).padStart(5) +
      ' attempted=' + String(r.attempted || 0).padStart(5) +
      ' left=' + (r.pending ?? '?') + (r.error ? '  ' + r.error : ''),
    );
    return r;
  });
  const mins = ((Date.now() - started) / 60000).toFixed(1);
  console.log('\nkept ' + res.reduce((a, r) => a + (r.kept || 0), 0) + ' recipes in ' + mins + ' min');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
