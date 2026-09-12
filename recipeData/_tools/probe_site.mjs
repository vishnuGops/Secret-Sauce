// Qualify a candidate source before it costs a crawl.
//
//   node probe_site.mjs https://www.kingarthurbaking.com/
//   node probe_site.mjs https://x.com/ --include "/recipes/[a-z0-9-]+$" --sample 4
//
// Answers, in one pass: does robots.txt allow us, what delay does it ask for, how
// many candidate URLs does the sitemap actually hold, and do those URLs carry a
// Recipe node with usable attribution. A site that fails any of those is cheaper to
// find out about here than 400 requests into a harvest.
import { robotsFor } from './robots.mjs';
import { walkSitemaps, SITEMAP_FALLBACKS } from './sitemap.mjs';
import { fetchHtml, jsonLdBlocks, findRecipeNode, pageTitleOf, allRecipeNodes } from './extract.mjs';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const asArray = (v) => (v == null ? [] : Array.isArray(v) ? v : [v]);
const nameOf = (v) => {
  const first = asArray(v)[0];
  if (typeof first === 'string') return first;
  if (first && typeof first.name === 'string') return first.name;
  return null;
};

/** Spread a sample across the list rather than taking the first N (often newest). */
function sample(arr, n) {
  if (arr.length <= n) return arr.slice();
  const step = arr.length / n;
  return Array.from({ length: n }, (_, i) => arr[Math.floor(i * step)]);
}

export async function probeSite(homepage, opts = {}) {
  const {
    include = null,
    exclude = null,
    sitemapInclude = null,
    sampleSize = 3,
    limit = 4000,
    maxSitemaps = 60,
  } = opts;

  const out = { homepage, host: new URL(homepage).hostname };

  const robots = await robotsFor(homepage);
  out.robots = {
    status: robots.status,
    summary: robots.summary,
    crawlDelayMs: robots.crawlDelayMs,
    sitemapsDeclared: robots.sitemaps.length,
    homepageAllowed: robots.allows('/'),
  };
  if (robots.fetchFailed) {
    out.verdict = 'robots-unreachable';
    return out;
  }

  const roots = [
    ...robots.sitemaps,
    ...SITEMAP_FALLBACKS.map((p) => new URL(p, homepage).href),
  ];
  const delayMs = Math.max(robots.crawlDelayMs || 0, 700);

  const walk = await walkSitemaps(roots, {
    include,
    exclude,
    sitemapInclude,
    limit,
    maxSitemaps,
    delayMs,
  });
  out.sitemap = {
    fetched: walk.sitemapsFetched,
    candidates: walk.pages.length,
    firstFew: walk.pages.slice(0, 3),
    tried: walk.tried.filter((t) => t.status !== 200).slice(0, 6),
  };

  if (!walk.pages.length) {
    out.verdict = 'no-candidates';
    return out;
  }

  const picks = sample(walk.pages, sampleSize).filter((u) => robots.allows(u));
  out.samples = [];
  for (const url of picks) {
    let res;
    try {
      res = await fetchHtml(url);
    } catch (e) {
      out.samples.push({ url, error: String(e.message) });
      continue;
    }
    await sleep(delayMs);
    if (res.status >= 400) {
      out.samples.push({ url, status: res.status });
      continue;
    }
    const blocks = jsonLdBlocks(res.html);
    const pageTitle = pageTitleOf(res.html);
    const nodes = allRecipeNodes(blocks);
    const node = findRecipeNode(blocks, { pageTitle, pageUrl: res.finalUrl });
    out.samples.push({
      url,
      status: res.status,
      recipeNodes: nodes.length,
      matched: !!node,
      title: node ? nameOf(node.name) : null,
      author: node ? nameOf(node.author) : null,
      publisher: node ? nameOf(node.publisher) : null,
      ingredients: node ? asArray(node.recipeIngredient || node.ingredients).length : 0,
      instructions: node ? asArray(node.recipeInstructions).length : 0,
      wprm: /wprm-recipe-ingredient/.test(res.html),
      tasty: /tasty-recipes-ingredients/.test(res.html),
      mv: /mv-create-ingredients/.test(res.html),
    });
  }

  const good = out.samples.filter((s) => s.matched && s.ingredients > 0 && s.instructions > 0);
  out.verdict =
    good.length === 0
      ? out.samples.some((s) => s.status >= 400) ? 'blocked' : 'no-recipe-jsonld'
      : good.length < out.samples.length
        ? 'partial'
        : 'ok';
  out.authors = [...new Set(out.samples.map((s) => s.author).filter(Boolean))];
  out.publishers = [...new Set(out.samples.map((s) => s.publisher).filter(Boolean))];
  return out;
}

function line(p) {
  const v = (p.verdict || '?').padEnd(18);
  const host = p.host.padEnd(30);
  const cand = String(p.sitemap ? p.sitemap.candidates : 0).padStart(6);
  const delay = p.robots.crawlDelayMs ? ' delay=' + p.robots.crawlDelayMs + 'ms' : '';
  return v + host + cand + ' candidates' + delay;
}

async function main() {
  const argv = process.argv.slice(2);
  const homepage = argv.find((a) => a.startsWith('http'));
  if (!homepage) {
    console.log('usage: node probe_site.mjs <homepage> [--include <re>] [--exclude <re>] [--sample N]');
    process.exit(1);
  }
  const arg = (flag) => {
    const i = argv.indexOf(flag);
    return i >= 0 ? argv[i + 1] : null;
  };
  const inc = arg('--include');
  const exc = arg('--exclude');
  const smi = arg('--sitemap-include');
  const p = await probeSite(homepage, {
    include: inc ? new RegExp(inc, 'i') : null,
    exclude: exc ? new RegExp(exc, 'i') : null,
    sitemapInclude: smi ? new RegExp(smi, 'i') : null,
    sampleSize: Number(arg('--sample')) || 3,
  });
  console.log(line(p));
  console.log(JSON.stringify(p, null, 2));
}

if (process.argv[1] && import.meta.url === new URL('file://' + process.argv[1].replace(/\\/g, '/')).href) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}
