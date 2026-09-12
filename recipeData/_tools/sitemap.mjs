// Sitemap walker. Turns a site into a list of candidate recipe URLs.
//
// Batch 2's discovery read at most three child sitemaps and stopped at 120 URLs,
// which is the right shape for "ten recipes per chef" and the wrong one for "every
// recipe this site has". This walks the whole index, follows nested indexes, and
// handles the two things that break a naive reader:
//
//   - `.xml.gz` bodies. Node's fetch decompresses `Content-Encoding: gzip`, but a
//     gzip *file* served as application/gzip arrives as bytes; `res.text()` on that
//     yields mojibake and zero <loc> matches, which reads as "empty sitemap".
//   - Index-vs-urlset. A <sitemapindex> holds sitemaps, a <urlset> holds pages, and
//     plenty of sites nest an index inside an index.
import { gunzipSync, inflateSync } from 'node:zlib';

const UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/131.0 Safari/537.36';

/** Fetch a sitemap body as text, transparently gunzipping a `.gz` payload. */
export async function fetchXml(url) {
  // A sitemap can be tens of megabytes, so this deadline is longer than a page's —
  // but there has to be one, or a stalled index hangs the whole discovery pass.
  const res = await fetch(url, {
    headers: { 'user-agent': UA, accept: 'application/xml,text/xml,*/*' },
    redirect: 'follow',
    signal: AbortSignal.timeout(60000),
  });
  if (res.status >= 400) return { status: res.status, finalUrl: res.url, xml: '' };
  const buf = Buffer.from(await res.arrayBuffer());
  let xml;
  const looksGzip = buf.length > 2 && buf[0] === 0x1f && buf[1] === 0x8b;
  if (looksGzip) {
    try {
      xml = gunzipSync(buf).toString('utf8');
    } catch {
      try {
        xml = inflateSync(buf).toString('utf8');
      } catch {
        xml = buf.toString('utf8');
      }
    }
  } else {
    xml = buf.toString('utf8');
  }
  return { status: res.status, finalUrl: res.url, xml };
}

const unescapeXml = (s) =>
  s
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#0?39;/g, "'")
    .replace(/&apos;/g, "'");

/** Every <loc> in document order. */
export function locs(xml) {
  const out = [];
  const re = /<loc>\s*([\s\S]*?)\s*<\/loc>/gi;
  let m;
  while ((m = re.exec(xml))) out.push(unescapeXml(m[1].trim()));
  return out;
}

export const isIndex = (xml) => /<sitemapindex[\s>]/i.test(xml);

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/**
 * Walk sitemaps breadth-first and return the page URLs.
 *
 * `include` / `exclude` filter page URLs only — never the child sitemaps, or a
 * `/recipe/` include would reject `post-sitemap2.xml` and the walk would end at
 * the index. `sitemapInclude` is the separate knob for that.
 */
export async function walkSitemaps(roots, opts = {}) {
  const {
    include = null,
    exclude = null,
    sitemapInclude = null,
    sitemapExclude = /(image|video|news|author|category|tag|taxonomy|product)[-_]?sitemap|sitemap[-_]?(image|video|news|author|category|tag)/i,
    limit = Infinity,
    maxSitemaps = 200,
    delayMs = 400,
    onSitemap = null,
  } = opts;

  const queue = [...roots];
  const seenSitemaps = new Set();
  const pages = [];
  const seenPages = new Set();
  const tried = [];
  let fetched = 0;

  while (queue.length && pages.length < limit && fetched < maxSitemaps) {
    const sm = queue.shift();
    if (!sm || seenSitemaps.has(sm)) continue;
    seenSitemaps.add(sm);

    let res;
    try {
      res = await fetchXml(sm);
    } catch (e) {
      tried.push({ sm, status: 'error', detail: String(e.message) });
      continue;
    }
    fetched++;
    await sleep(delayMs);

    if (res.status >= 400 || !res.xml) {
      tried.push({ sm, status: res.status || 'empty' });
      continue;
    }

    const found = locs(res.xml);
    const index = isIndex(res.xml);
    if (onSitemap) onSitemap({ sm, status: res.status, index, count: found.length });
    tried.push({ sm, status: res.status, index, count: found.length });

    if (index) {
      for (const child of found) {
        if (sitemapExclude && sitemapExclude.test(child)) continue;
        if (sitemapInclude && !sitemapInclude.test(child)) continue;
        queue.push(child);
      }
      continue;
    }

    for (const u of found) {
      if (pages.length >= limit) break;
      if (/\.xml(\.gz)?$/i.test(u)) {
        queue.push(u);
        continue;
      }
      if (include && !include.test(u)) continue;
      if (exclude && exclude.test(u)) continue;
      const key = u.replace(/[#?].*$/, '').replace(/\/$/, '');
      if (seenPages.has(key)) continue;
      seenPages.add(key);
      pages.push(u);
    }
  }

  return { pages, tried, sitemapsFetched: fetched };
}

export const SITEMAP_FALLBACKS = [
  '/sitemap_index.xml',
  '/wp-sitemap.xml',
  '/sitemap.xml',
  '/sitemap-index.xml',
  '/post-sitemap.xml',
  '/recipe-sitemap.xml',
  '/sitemap/sitemap-index.xml',
];
