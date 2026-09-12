// Corpus scraper. Reads a chef manifest, fetches every recipe URL, writes
// recipeData/recipes/<chefSlug>/<recipeSlug>.json and updates the resume state.
//
//   node recipeData/_tools/scrape.mjs                # all chefs in the manifest
//   node recipeData/_tools/scrape.mjs jamie-oliver   # one chef
//   node recipeData/_tools/scrape.mjs --probe <url>  # dry-run a single URL, write nothing
//
// Idempotent: a recipe file that already exists is skipped unless --force.
import { mkdir, readFile, writeFile, access } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { fetchHtml, jsonLdBlocks, findRecipeNode, toCorpusRecipe, pageTitleOf, titleOverlap, MIN_TITLE_OVERLAP } from './extract.mjs';
import { applyBbcEnrichment } from './enrich_bbc.mjs';
import { applyWprmEnrichment } from './enrich_wprm.mjs';
import { policyFor, delayFor } from './crawl_policy.mjs';

// Per-site enrichers recover structure the site publishes in HTML but omits from
// its JSON-LD. Keyed by hostname suffix.
const ENRICHERS = [
  [/(^|\.)bbc\.co\.uk$/, applyBbcEnrichment],
  [/(^|\.)mygreekdish\.com$/, applyWprmEnrichment],
  [/(^|\.)hungryhuy\.com$/, applyWprmEnrichment],
  [/(^|\.)feelgoodfoodie\.net$/, applyWprmEnrichment],
  [/(^|\.)cheflolaskitchen\.com$/, applyWprmEnrichment],
  [/(^|\.)easyanddelish\.com$/, applyWprmEnrichment],
];

function enricherFor(url) {
  const host = new URL(url).hostname;
  const hit = ENRICHERS.find(([re]) => re.test(host));
  return hit ? hit[1] : null;
}

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, '..');
const MANIFEST = resolve(HERE, 'manifest.json');
const STATE = resolve(ROOT, '_state/progress.json');
const CHEFS = resolve(ROOT, 'chefs.json');

// One request every DELAY_MS, so a 100-recipe run stays a polite trickle.
const DELAY_MS = 1500;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const exists = (p) => access(p).then(() => true, () => false);

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
    .slice(0, 80);
}

function slugFromUrl(url, title) {
  if (title) return slugify(title);
  const last = new URL(url).pathname.split('/').filter(Boolean).pop() || 'recipe';
  return slugify(last.replace(/\.(html?|php|aspx)$/i, ''));
}

/** Fetch + extract one URL. Never throws: failures come back as { ok: false }. */
export async function scrapeOne(url, chef) {
  const retrievedAt = new Date().toISOString();
  let res;
  try {
    res = await fetchHtml(url);
  } catch (e) {
    return { ok: false, url, reason: 'fetch-failed', detail: String(e.message) };
  }
  if (res.status >= 400) return { ok: false, url, reason: 'http-' + res.status };

  let titleWarning = null;
  const blocks = jsonLdBlocks(res.html);
  const pageTitle = pageTitleOf(res.html);
  const node = findRecipeNode(blocks, { pageTitle, pageUrl: res.finalUrl });
  if (!node) {
    return {
      ok: false,
      url,
      reason: 'no-recipe-jsonld',
      detail:
        'blocks=' + blocks.length + ' malformed=' + (blocks.malformed || []).length +
        ' pageTitle=' + JSON.stringify(pageTitle),
    };
  }

  // Last line of defence against capturing a sidebar recipe: the node's name has
  // to have something to do with the page it came from. Without this, ten URLs
  // can quietly yield ten copies of one dish, each file internally consistent.
  const nodeName = typeof node.name === 'string' ? node.name : '';
  if (pageTitle && nodeName) {
    const overlap = titleOverlap(nodeName, pageTitle);
    if (overlap < 0.15) {
      return {
        ok: false,
        url,
        reason: 'recipe-title-mismatch',
        detail:
          'overlap=' + overlap.toFixed(2) +
          ' node=' + JSON.stringify(nodeName) + ' page=' + JSON.stringify(pageTitle),
      };
    }
    // A partial disagreement is usually just the page title carrying the chef's
    // name or the site's. Record it rather than reject: "Lasagne al forno" against
    // "Mary Berry's lasagne" scores the same 0.33 as a genuine mismatch, so this
    // metric cannot be the thing that decides. The duplicate check below can.
    if (overlap < MIN_TITLE_OVERLAP) {
      titleWarning = 'title-overlap-' + overlap.toFixed(2) + ': page=' + JSON.stringify(pageTitle);
    }
  }

  const title = typeof node.name === 'string' ? node.name : null;
  const recipeSlug = slugFromUrl(res.finalUrl, title);
  const recipe = toCorpusRecipe({
    node,
    chefId: chef.id,
    chefName: chef.name,
    chefSlug: chef.slug,
    recipeSlug,
    sourceUrl: url,
    finalUrl: res.finalUrl,
    html: res.html,
    retrievedAt,
    blocks,
    pageTitle,
  });

  const enrich = enricherFor(res.finalUrl);
  if (enrich) enrich(recipe, res.html);

  // Stamp the site's own terms onto the row, so the constraint is visible where
  // the data is rather than only in the crawler's config.
  const policy = policyFor(res.finalUrl);
  recipe.source.rights = policy.rights || recipe.source.rights;
  if (policy.contentSignal) recipe.source.contentSignal = policy.contentSignal;
  if (policy.robots) recipe.source.robots = policy.robots;

  if (titleWarning) recipe.source.titleWarning = titleWarning;

  return { ok: true, url, recipe };
}

/** Every fidelity problem worth knowing about before this recipe reaches the app. */
export function auditRecipe(r) {
  const warn = [];
  if (!r.title) warn.push('no-title');
  const items = r.ingredientGroups.flatMap((g) => g.items);
  if (items.length === 0) warn.push('no-ingredients');
  if (r.steps.length === 0) warn.push('no-steps');
  if (r.steps.length === 1 && r.steps[0].text.length > 600) warn.push('steps-may-be-one-blob');
  const unparsed = items.filter((i) => i.quantity == null && i.quantityText == null);
  if (unparsed.length) warn.push('unparsed-quantity:' + unparsed.length);
  const ranges = items.filter((i) => i.quantityText && /-|–|—|to|or/.test(i.quantityText));
  if (ranges.length) warn.push('range-quantity:' + ranges.length);
  if (r.yield.servings == null) warn.push('no-servings-int');
  if (r.timing.prepMinutes == null) warn.push('no-prep-time');
  if (r.timing.cookMinutes == null) warn.push('no-cook-time');
  if (Object.keys(r.unmappedFields).length) {
    warn.push('unmapped:' + Object.keys(r.unmappedFields).join('|'));
  }
  return warn;
}

async function main() {
  const argv = process.argv.slice(2);
  const force = argv.includes('--force');

  if (argv[0] === '--probe') {
    const url = argv[1];
    const out = await scrapeOne(url, { id: 'probe', name: 'Probe', slug: 'probe' });
    if (!out.ok) {
      console.log('FAIL', out.reason, out.detail || '');
      process.exitCode = 1;
      return;
    }
    const r = out.recipe;
    console.log(JSON.stringify({
      title: r.title,
      servings: r.yield,
      timing: r.timing,
      groups: r.ingredientGroups.map((g) => ({ name: g.name, n: g.items.length })),
      steps: r.steps.length,
      subSteps: r.steps.reduce((a, s) => a + s.subSteps.length, 0),
      stepGroups: [...new Set(r.steps.map((s) => s.stepGroup).filter(Boolean))],
      equipment: r.equipment,
      keywords: r.keywords.slice(0, 8),
      nutritionKeys: r.nutrition ? Object.keys(r.nutrition) : null,
      audit: auditRecipe(r),
      sampleIngredients: r.ingredientGroups[0]?.items.slice(0, 4),
      sampleStep: r.steps[0]?.text.slice(0, 160),
    }, null, 2));
    return;
  }

  // --verify refetches every stored recipe and checks that the node this page
  // really offers still matches what the file holds. Read-only on purpose: it can
  // run while an ingestion is reading the same corpus files.
  if (argv[0] === '--verify') {
    const progress = await readJson(STATE, { chefs: {} });
    let checked = 0;
    const bad = [];
    for (const [slug, cs] of Object.entries(progress.chefs)) {
      for (const entry of cs.scraped) {
        const stored = await readJson(resolve(ROOT, 'recipes', entry.file), null);
        if (!stored) continue;
        let res;
        try {
          res = await fetchHtml(entry.url);
        } catch {
          continue;
        }
        await sleep(delayFor(entry.url));
        checked++;
        if (res.status >= 400) {
          bad.push({ file: entry.file, why: 'http-' + res.status });
          continue;
        }
        const pageTitle = pageTitleOf(res.html);
        const overlap = titleOverlap(stored.title, pageTitle);
        if (overlap < MIN_TITLE_OVERLAP) {
          bad.push({
            file: entry.file,
            why: 'title-mismatch(' + overlap.toFixed(2) + ')',
            stored: stored.title,
            page: pageTitle,
          });
        }
      }
      console.log('checked ' + slug);
    }
    console.log('\nverified ' + checked + ' recipes, ' + bad.length + ' suspect');
    for (const b of bad) {
      console.log('  ' + b.why + '  ' + b.file + (b.page ? '\n      stored=' + JSON.stringify(b.stored) + '\n      page  =' + JSON.stringify(b.page) : ''));
    }
    return;
  }

  const manifest = await readJson(MANIFEST, null);
  if (!manifest) throw new Error('missing manifest: ' + MANIFEST);

  const only = argv.filter((a) => !a.startsWith('--'));
  const chefs = manifest.chefs.filter((c) => only.length === 0 || only.includes(c.slug));

  const state = await readJson(STATE, { startedAt: null, chefs: {} });
  state.startedAt = state.startedAt || new Date().toISOString();

  const chefIndex = await readJson(CHEFS, { schemaVersion: 1, chefs: [] });
  const byId = new Map(chefIndex.chefs.map((c) => [c.id, c]));

  for (const chef of chefs) {
    const cs = (state.chefs[chef.slug] = state.chefs[chef.slug] || { scraped: [], failed: [] });
    byId.set(chef.id, {
      id: chef.id,
      slug: chef.slug,
      name: chef.name,
      bio: chef.bio,
      country: chef.country,
      homepage: chef.homepage,
      corpusEmail: chef.slug + '@corpus.invalid',
      appProfileId: byId.get(chef.id)?.appProfileId ?? null,
    });

    for (const url of chef.recipes) {
      const already = cs.scraped.find((s) => s.url === url);
      if (already && !force && (await exists(resolve(ROOT, 'recipes', already.file)))) {
        console.log('skip  ' + chef.slug + '  ' + url);
        continue;
      }

      const out = await scrapeOne(url, chef);
      // Each site sets its own pace. seonkyounglongest.com declares
      // Crawl-delay: 30, so ten recipes there take five minutes, and that is the
      // correct speed rather than a problem to work around.
      await sleep(delayFor(url));

      if (!out.ok) {
        cs.failed = cs.failed.filter((f) => f.url !== url).concat([{ ...out, at: new Date().toISOString() }]);
        console.log('FAIL  ' + chef.slug + '  ' + out.reason + '  ' + url);
        continue;
      }

      const r = out.recipe;

      // seonkyounglongest.com emits nine Recipe nodes on every page, all of them
      // "popular recipe" widgets, so ten URLs produced ten copies of one dish —
      // each file internally valid, the whole chef wrong. Title overlap could not
      // tell that from a chef's name in a page title; this can.
      const clash = cs.scraped.find((s2) => s2.url !== url && s2.title === r.title);
      if (clash) {
        cs.failed = cs.failed.filter((f) => f.url !== url).concat([{
          ok: false,
          url,
          reason: 'duplicate-node-across-urls',
          detail: 'same recipe already captured from ' + clash.url,
          at: new Date().toISOString(),
        }]);
        console.log('FAIL  ' + chef.slug + '  duplicate-node-across-urls  ' + url);
        continue;
      }

      const rel = chef.slug + '/' + r.slug + '.json';
      r.audit = auditRecipe(r);
      await writeJson(resolve(ROOT, 'recipes', rel), r);

      cs.scraped = cs.scraped.filter((s) => s.url !== url).concat([
        { url, file: rel, title: r.title, at: r.source.retrievedAt, audit: r.audit },
      ]);
      cs.failed = cs.failed.filter((f) => f.url !== url);
      console.log(
        'ok    ' + chef.slug + '  ' + r.slug +
        '  ing=' + r.ingredientGroups.reduce((a, g) => a + g.items.length, 0) +
        ' steps=' + r.steps.length +
        (r.audit.length ? '  audit=' + r.audit.join(',') : ''),
      );
    }
    await writeJson(STATE, state);
    await writeJson(CHEFS, { schemaVersion: 1, chefs: [...byId.values()] });
  }

  const scraped = Object.values(state.chefs).reduce((a, c) => a + c.scraped.length, 0);
  const failed = Object.values(state.chefs).reduce((a, c) => a + c.failed.length, 0);
  console.log('\ntotal scraped=' + scraped + ' failed=' + failed);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}
