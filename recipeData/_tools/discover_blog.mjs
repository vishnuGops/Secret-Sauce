// Recipe-URL discovery for the WordPress recipe sites in batch 2.
//
//   node recipeData/_tools/discover_blog.mjs --check
//   node recipeData/_tools/discover_blog.mjs --write 10
//
// Each of these sites is one author, so chef parentage is the domain itself —
// cleaner than BBC, where a chef index page had to be crawled. Candidate URLs
// come from the sitemap; each is then verified to carry a Recipe node before it
// reaches the manifest, because a WordPress post sitemap is mostly articles.
import { readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { fetchHtml, jsonLdBlocks, findRecipeNode } from './extract.mjs';
import { delayFor } from './crawl_policy.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const MANIFEST = resolve(HERE, 'manifest.json');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export const CHEFS = [
  // Just One Cookbook was the first choice here — it is the one source found that
  // publishes instruction *sections* in its JSON-LD. It was dropped: every sitemap
  // path and the rendered recipe index both answer 403 to this client while the
  // same URLs load in a browser, which is WAF fingerprinting rather than a robots
  // rule (robots.txt says Allow: /). Getting past that means disguising the client,
  // and that is not something worth doing to a site that is signalling no.
  {
    slug: 'eli-giannopoulos',
    name: 'Eli K. Giannopoulos',
    country: 'Greece',
    bio: 'Traditional Greek cooking, My Greek Dish.',
    homepage: 'https://www.mygreekdish.com/',
    sitemaps: ['https://www.mygreekdish.com/sitemap_index.xml'],
    include: /mygreekdish\.com\/recipe\/[a-z0-9-]+\/?$/i,
  },
  // seonkyounglongest.com was here and had to be dropped: it emits nine Recipe
  // nodes on every page, all of them sidebar "popular recipe" cards, and none of
  // them the recipe the page is actually about. Ten URLs yielded ten copies of one
  // dish. No amount of parsing fixes a page that never publishes its own recipe.
  {
    slug: 'huy-vu',
    name: 'Huy Vu',
    country: 'Vietnam',
    bio: 'Vietnamese home cooking, Hungry Huy.',
    homepage: 'https://www.hungryhuy.com/',
    sitemaps: ['https://www.hungryhuy.com/sitemap_index.xml'],
    include: /hungryhuy\.com\/[a-z0-9-]+\/?$/i,
  },
  {
    slug: 'yumna-jawad',
    name: 'Yumna Jawad',
    country: 'Lebanon / USA',
    bio: 'Lebanese and Middle Eastern home cooking, Feel Good Foodie.',
    homepage: 'https://feelgoodfoodie.net/',
    sitemaps: ['https://feelgoodfoodie.net/wp-sitemap-posts-post-1.xml'],
    include: /feelgoodfoodie\.net\/recipe\/[a-z0-9-]+\/?$/i,
  },
  {
    slug: 'chef-lola',
    name: "Chef Lola",
    country: 'Nigeria',
    bio: 'West African and Nigerian cooking.',
    homepage: 'https://cheflolaskitchen.com/',
    sitemaps: ['https://cheflolaskitchen.com/wp-sitemap-posts-post-1.xml'],
    include: /cheflolaskitchen\.com\/[a-z0-9-]+\/?$/i,
  },
  {
    slug: 'denise-browning',
    name: 'Denise Browning',
    country: 'Brazil',
    bio: 'Brazilian and Latin American cooking, Easy and Delish.',
    homepage: 'https://www.easyanddelish.com/',
    sitemaps: ['https://www.easyanddelish.com/wp-sitemap-posts-post-1.xml'],
    include: /easyanddelish\.com\/[a-z0-9-]+\/?$/i,
  },
];

const SITEMAP_FALLBACKS = [
  '/wp-sitemap.xml',
  '/sitemap_index.xml',
  '/sitemap.xml',
  '/post-sitemap.xml',
  '/wp-sitemap-posts-post-1.xml',
];

function locs(xml) {
  const out = [];
  const re = /<loc>\s*([^<]+?)\s*<\/loc>/gi;
  let m;
  while ((m = re.exec(xml))) out.push(m[1].replace(/&amp;/g, '&'));
  return out;
}

/** Candidate post URLs for a chef, from whichever sitemap actually resolves. */
export async function candidateUrls(chef, limit = 120) {
  const tried = [];
  const bases = [...chef.sitemaps, ...SITEMAP_FALLBACKS.map((p) => new URL(p, chef.homepage).href)];

  for (const sm of bases) {
    let res;
    try {
      res = await fetchHtml(sm);
    } catch {
      tried.push(sm + ' (error)');
      continue;
    }
    await sleep(delayFor(sm));
    if (res.status >= 400) {
      tried.push(sm + ' (' + res.status + ')');
      continue;
    }

    let urls = locs(res.html);

    // An index sitemap points at more sitemaps; follow the post ones.
    const children = urls.filter((u) => /\.xml$/i.test(u) && /post|recipe/i.test(u));
    if (children.length) {
      urls = [];
      for (const c of children.slice(0, 3)) {
        try {
          const r2 = await fetchHtml(c);
          await sleep(delayFor(c));
          if (r2.status < 400) urls.push(...locs(r2.html));
        } catch {
          /* a missing child sitemap is not fatal */
        }
      }
    }

    const matched = urls.filter((u) => chef.include.test(u));
    if (matched.length) return { urls: matched.slice(0, limit), sitemap: sm, tried };
  }

  // Fall back to the site's own rendered index for hosts that refuse sitemaps.
  const NON_RECIPE =
    /\/(recipes|categories|category|about|shop|cookbook|privacy|contact|subscribe|tag|author|blog|videos|pages|collection|comments|search|newsletter|\d{4})\/|404|agreement|terms|policy|disclosure/i;
  for (const page of chef.indexPages || []) {
    try {
      const res = await fetchHtml(page);
      await sleep(delayFor(page));
      if (res.status >= 400) {
        tried.push(page + ' (' + res.status + ')');
        continue;
      }
      const hrefs = [...new Set(res.html.match(/https?:\/\/[^"'\s<>]+/g) || [])]
        .map((u) => u.replace(/[)"'].*$/, ''))
        .filter((u) => chef.include.test(u) && !NON_RECIPE.test(u));
      if (hrefs.length) return { urls: hrefs.slice(0, limit), sitemap: page + ' (index)', tried };
    } catch {
      tried.push(page + ' (error)');
    }
  }
  return { urls: [], sitemap: null, tried };
}

/** Keep only URLs that really carry a Recipe node. Post sitemaps are mostly articles. */
async function confirmRecipes(chef, urls, want) {
  const good = [];
  for (const url of urls) {
    if (good.length >= want) break;
    try {
      const res = await fetchHtml(url);
      await sleep(delayFor(url));
      if (res.status >= 400) continue;
      if (findRecipeNode(jsonLdBlocks(res.html))) good.push(url);
    } catch {
      /* skip and continue */
    }
  }
  return good;
}

async function main() {
  const argv = process.argv.slice(2);
  const write = argv.includes('--write');
  const want = Number(argv[argv.indexOf('--write') + 1]) || 10;

  const onlyIdx = argv.indexOf('--only');
  const only = onlyIdx >= 0 ? argv[onlyIdx + 1] : null;

  const found = [];
  for (const chef of CHEFS) {
    if (only && chef.slug !== only) continue;
    const { urls, sitemap, tried } = await candidateUrls(chef);
    if (!urls.length) {
      console.log('FAIL ' + chef.slug.padEnd(22) + 'no sitemap matched  tried=' + tried.join(', '));
      continue;
    }
    // Sample more candidates than needed; many posts are not recipes.
    const recipes = await confirmRecipes(chef, urls.slice(0, want * 4), want);
    console.log(
      (recipes.length >= want ? 'ok   ' : 'thin ') + chef.slug.padEnd(22) +
      'candidates=' + urls.length + ' confirmed=' + recipes.length + '  ' + sitemap,
    );
    found.push({ chef, recipes });
  }

  if (!write) return;

  const manifest = JSON.parse(await readFile(MANIFEST, 'utf8'));
  const bySlug = new Map(manifest.chefs.map((c) => [c.slug, c]));
  for (const { chef, recipes } of found) {
    if (!recipes.length) continue;
    bySlug.set(chef.slug, {
      id: 'chef_' + chef.slug,
      slug: chef.slug,
      name: chef.name,
      bio: chef.bio,
      country: chef.country,
      homepage: chef.homepage,
      avatarUrl: null,
      source: new URL(chef.homepage).hostname,
      recipes,
    });
  }
  manifest.chefs = [...bySlug.values()];
  await writeFile(MANIFEST, JSON.stringify(manifest, null, 2) + '\n', 'utf8');
  console.log(
    '\nmanifest: ' + manifest.chefs.length + ' chefs, ' +
    manifest.chefs.reduce((a, c) => a + c.recipes.length, 0) + ' recipe urls',
  );
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}
