// Corpus extractor: URL -> full-fidelity recipe JSON.
// The verbatim JSON-LD node is the fidelity anchor; everything else is derived from it.
// Nothing is dropped: whatever we cannot map lands in `unmappedFields`.
import { createHash } from 'node:crypto';

const UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/131.0 Safari/537.36';

export const FETCH_TIMEOUT_MS = 30000;

export async function fetchHtml(url) {
  // Without a deadline one unresponsive host stalls its lane for the rest of the
  // run, and a lane is a whole source. `fetch` has no default timeout.
  const res = await fetch(url, {
    // Some servers answer 406 to a narrow Accept — 303 pages were refused that way
    // before the wildcard was added. A browser never sends a list this short.
    headers: {
      'user-agent': UA,
      accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'accept-language': 'en-US,en;q=0.9',
    },
    redirect: 'follow',
    signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
  });
  const html = await res.text();
  // `Retry-After` is the server telling the crawler how long to wait; honouring it
  // is the difference between backing off and being blocked. Seconds or an HTTP
  // date, per RFC 9110.
  const ra = res.headers.get('retry-after');
  let retryAfterMs = null;
  if (ra) {
    const secs = Number(ra);
    if (Number.isFinite(secs)) retryAfterMs = Math.round(secs * 1000);
    else {
      const when = Date.parse(ra);
      if (Number.isFinite(when)) retryAfterMs = Math.max(0, when - Date.now());
    }
  }
  return { status: res.status, finalUrl: res.url, html, retryAfterMs };
}

export const decodeEntities = (s) =>
  String(s)
    .replace(/&quot;/g, '"')
    .replace(/&#0?39;/g, "'")
    .replace(/&apos;/g, "'")
    .replace(/&nbsp;/g, ' ')
    .replace(/&deg;/g, '°')
    .replace(/&frac12;/g, '½')
    .replace(/&frac14;/g, '¼')
    .replace(/&frac34;/g, '¾')
    .replace(/&#x([0-9a-f]+);/gi, (_, h) => String.fromCodePoint(parseInt(h, 16)))
    .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(Number(d)))
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&amp;/g, '&');

// CRLF is transport noise, not content, and it does not survive a round trip:
// typing "\r\n" into a text field produces two newlines, so a captured "\r\n"
// reads as data loss in the diff when nothing was actually lost.
const stripTags = (s) =>
  decodeEntities(String(s).replace(/<br\s*\/?>/gi, '\n').replace(/<[^>]+>/g, ' '))
    .replace(/\r\n?/g, '\n')
    .replace(/[ \t]+/g, ' ')
    .replace(/ *\n */g, '\n')
    .trim();

/**
 * Real-world JSON-LD is routinely invalid: raw newlines and tabs inside string
 * literals, and trailing commas. Both are repairable without guessing at meaning,
 * so repair rather than discard — a dropped block is a dropped recipe.
 */
export function repairJson(raw) {
  let out = '';
  let inString = false;
  let escaped = false;
  for (const ch of raw) {
    if (escaped) {
      out += ch;
      escaped = false;
      continue;
    }
    if (ch === '\\') {
      out += ch;
      escaped = inString;
      continue;
    }
    if (ch === '"') {
      inString = !inString;
      out += ch;
      continue;
    }
    if (inString && (ch === '\n' || ch === '\r' || ch === '\t')) {
      out += ch === '\t' ? '\\t' : ch === '\r' ? '' : '\\n';
      continue;
    }
    if (inString && ch < ' ') continue; // other control chars have no legal meaning here
    out += ch;
  }
  return out.replace(/,\s*([}\]])/g, '$1');
}

/** Every <script type="application/ld+json"> block on the page, parsed. */
export function jsonLdBlocks(html) {
  const out = [];
  const malformed = [];
  const repaired = [];
  const re = /<script[^>]+type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi;
  let m;
  while ((m = re.exec(html))) {
    const raw = m[1].trim().replace(/^<!\[CDATA\[/, '').replace(/\]\]>$/, '');
    try {
      out.push(JSON.parse(raw));
    } catch (firstError) {
      try {
        out.push(JSON.parse(repairJson(raw)));
        repaired.push({ bytes: raw.length, error: String(firstError.message) });
      } catch (e) {
        malformed.push({ bytes: raw.length, error: String(e.message) });
      }
    }
  }
  out.malformed = malformed;
  out.repaired = repaired;
  return out;
}

const typesOf = (n) =>
  (Array.isArray(n && n['@type']) ? n['@type'] : [n && n['@type']]).filter(Boolean);

/** Every Recipe node on the page, in document order. */
export function allRecipeNodes(blocks) {
  const out = [];
  const seen = new Set();
  const walk = (n) => {
    if (!n || typeof n !== 'object' || seen.has(n)) return;
    seen.add(n);
    if (Array.isArray(n)) {
      n.forEach(walk);
      return;
    }
    if (typesOf(n).includes('Recipe')) out.push(n);
    for (const v of Object.values(n)) if (v && typeof v === 'object') walk(v);
  };
  walk(blocks);
  return out;
}

export const MIN_TITLE_OVERLAP = 0.34;

export const titleKey = (s) =>
  String(s || '')
    .toLowerCase()
    .replace(/&[a-z]+;/g, ' ')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();

// Words that carry no identity: site furniture and recipe boilerplate. A page
// title is "Mary Berry's Victoria sponge recipe - BBC Food" where the node is
// "Victoria sponge", and those two are the same dish.
const TITLE_NOISE = new Set([
  'recipe', 'recipes', 'video', 'written', 'the', 'a', 'an', 'and', 'or', 'with',
  'best', 'easy', 'quick', 'homemade', 'authentic', 'classic', 'traditional',
  'bbc', 'food', 'kitchen', 's',
]);

const titleTokens = (s) =>
  new Set(titleKey(s).split(' ').filter((w) => w && w.length > 1 && !TITLE_NOISE.has(w)));

/**
 * How much two titles agree, as a share of the smaller one. Substring containment
 * is too strict for real pages: "Dijon Grilled Chicken" and "Grilled Dijon Chicken"
 * are the same recipe and neither contains the other. Token overlap separates that
 * from "Spicy Enoki Mushroom" against "Pho Bo", which share nothing.
 */
export function titleOverlap(a, b) {
  const A = titleTokens(a);
  const B = titleTokens(b);
  if (A.size === 0 || B.size === 0) return 1; // nothing to disagree about
  let shared = 0;
  for (const w of A) if (B.has(w)) shared++;
  return shared / Math.min(A.size, B.size);
}

export function pageTitleOf(html) {
  const og = html.match(/<meta\s+property="og:title"\s+content="([^"]*)"/i);
  if (og) return decodeEntities(og[1]).trim();
  const t = html.match(/<title[^>]*>([\s\S]*?)<\/title>/i);
  return t ? decodeEntities(t[1]).trim() : null;
}

/**
 * The Recipe node that belongs to *this page*.
 *
 * Taking the first Recipe node found is wrong on any site that renders recipe
 * cards in a sidebar. seonkyounglongest.com emits nine Recipe nodes on every
 * page — all of them "popular recipe" widgets, none of them the page's own
 * recipe — so first-match silently captured the same dish ten times under ten
 * different URLs, each file internally valid and all of them wrong. Match on the
 * page's declared identity instead, and return nothing rather than a guess.
 */
export function findRecipeNode(blocks, context = {}) {
  const nodes = allRecipeNodes(blocks);
  if (nodes.length === 0) return null;

  const { pageTitle, pageUrl } = context;

  if (pageUrl) {
    const want = String(pageUrl).replace(/[#?].*$/, '').replace(/\/$/, '');
    const byUrl = nodes.find((n) => {
      const cand = [n.url, n['@id'], n.mainEntityOfPage?.['@id'], n.mainEntityOfPage]
        .filter((v) => typeof v === 'string')
        .map((v) => v.replace(/[#?].*$/, '').replace(/\/$/, ''));
      return cand.includes(want);
    });
    if (byUrl) return byUrl;
  }

  if (pageTitle) {
    const scored = nodes
      .map((n) => ({ n, score: titleOverlap(textOfName(n), pageTitle) }))
      .sort((a, b) => b.score - a.score);
    if (scored.length && scored[0].score >= MIN_TITLE_OVERLAP) return scored[0].n;
    // A page that declares a title and offers several unrelated recipes is a
    // sidebar situation: refuse rather than capture the wrong dish.
    if (nodes.length > 1) return null;
  }

  return nodes[0];
}

const textOfName = (n) =>
  typeof n?.name === 'string' ? n.name : typeof n?.headline === 'string' ? n.headline : '';

/** ISO-8601 duration -> minutes. A bare "PT" is unknown, not zero. */
export function isoMinutes(v) {
  if (typeof v === 'number') return v;
  if (typeof v !== 'string') return null;
  const m = v.match(
    /^P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+(?:\.\d+)?)H)?(?:(\d+(?:\.\d+)?)M)?(?:(\d+(?:\.\d+)?)S)?)?$/,
  );
  if (!m) return null;
  const n = (x) => (x == null ? 0 : Number(x));
  const total = n(m[1]) * 10080 + n(m[2]) * 1440 + n(m[3]) * 60 + n(m[4]) + n(m[5]) / 60;
  return total > 0 ? Math.round(total) : null;
}

const asArray = (v) => (v == null ? [] : Array.isArray(v) ? v : [v]);

const textOf = (v) => {
  if (typeof v === 'string') return stripTags(v);
  if (typeof v === 'number') return String(v);
  if (v && typeof v.name === 'string') return stripTags(v.name);
  if (v && typeof v.text === 'string') return stripTags(v.text);
  return null;
};

/**
 * recipeInstructions is the messiest field in the wild: plain strings, HowToStep
 * objects, HowToSection with nested itemListElement, or one HTML blob. All four are
 * handled, and section nesting is kept as `stepGroup` rather than flattened away.
 */
export function parseInstructions(v) {
  const collected = [];
  const push = (node, group) => {
    const types = typesOf(node);
    if (types.includes('HowToSection')) {
      const name = textOf(node.name) || group;
      const kids = asArray(node.itemListElement);
      if (kids.length === 0) {
        if (name) collected.push({ text: name, group, subSteps: [], source: node });
        return;
      }
      for (const k of kids) push(k, name);
      return;
    }
    if (typeof node === 'string') {
      // One blob with newlines is many steps; a single line is one step.
      for (const p of stripTags(node).split(/\n+/).map((s) => s.trim()).filter(Boolean)) {
        collected.push({ text: p, group, subSteps: [], source: node });
      }
      return;
    }
    if (!node || typeof node !== 'object') return;
    const text = textOf(node.text) || textOf(node.name);
    if (!text) return;
    const subSteps = asArray(node.itemListElement)
      .map((k) => textOf(k && k.text) || textOf(k))
      .filter(Boolean);
    collected.push({ text, group, subSteps, source: node });
  };
  for (const n of asArray(v)) push(n, null);

  return collected.map((s, i) => {
    const src = typeof s.source === 'object' && s.source ? s.source : {};
    const temp = s.text.match(/\b\d{2,3}\s?(?:°|deg)\s?[CF]\b|\bgas mark \d\b/i);
    return {
      order: i + 1,
      text: s.text,
      stepGroup: s.group,
      subSteps: s.subSteps,
      durationMinutes: isoMinutes(src.totalTime || src.performTime),
      temperature: temp ? temp[0] : null,
      utensils: asArray(src.tool).map(textOf).filter(Boolean),
      imageUrl: imageUrls(src.image)[0] || null,
      tip: null,
      raw: s.source,
    };
  });
}

export function imageUrls(v) {
  const out = [];
  for (const i of asArray(v)) {
    if (typeof i === 'string') out.push(i);
    else if (i && typeof i.url === 'string') out.push(i.url);
    else if (i && Array.isArray(i.url)) out.push(...i.url.filter((u) => typeof u === 'string'));
  }
  return out;
}

// Ingredient lines stay verbatim in `raw`; the parse is an addition, never a
// replacement. Ranges and fractions survive in `quantityText` even when the
// numeric `quantity` has to pick one value.
const UNITS = [
  'tablespoons', 'tablespoon', 'teaspoons', 'teaspoon', 'tbsps', 'tbsp', 'tsps', 'tsp',
  'grams', 'gram', 'kilograms', 'kilogram', 'kg', 'g', 'milliliters', 'millilitres', 'ml',
  'liters', 'litres', 'ounces', 'ounce', 'oz', 'pounds', 'pound', 'lbs', 'lb',
  'cups', 'cup', 'cloves', 'clove', 'pinches', 'pinch', 'handfuls', 'handful',
  'sprigs', 'sprig', 'sticks', 'stick', 'cans', 'can', 'tins', 'tin', 'packets', 'packet',
  'slices', 'slice', 'bunches', 'bunch', 'pieces', 'piece', 'dashes', 'dash',
  'quarts', 'quart', 'pints', 'pint', 'gallons', 'gallon', 'sheets', 'sheet', 'knobs', 'knob',
];

const FRACTIONS = {
  '½': 0.5, '⅓': 1 / 3, '⅔': 2 / 3, '¼': 0.25, '¾': 0.75,
  '⅕': 0.2, '⅖': 0.4, '⅗': 0.6, '⅘': 0.8, '⅙': 1 / 6,
  '⅚': 5 / 6, '⅛': 0.125, '⅜': 0.375, '⅝': 0.625, '⅞': 0.875,
};

const FRACTION_CHARS = Object.keys(FRACTIONS).join('');

const PREP_WORDS =
  /\b(chopped|sliced|diced|minced|grated|melted|softened|beaten|peeled|crushed|torn|trimmed|drained|rinsed|halved|quartered|cubed|shredded|zested|juiced|sifted|toasted|warmed|chilled|thawed|defrosted|cooked|uncooked|cut into|plus extra|plus more|room temperature|to serve|to garnish|to taste|for serving|for garnish|for dusting|for frying|for greasing|optional|divided|finely|roughly|thinly|coarsely|separated|deseeded|seeded|stoned|pitted|husked|shelled|at room temperature|well shaken|packed|lightly packed|firmly packed)\b/i;


/** Index of the first comma not inside ( ), [ ] or { }; -1 when there is none. */
function firstTopLevelComma(s) {
  let depth = 0;
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (c === '(' || c === '[' || c === '{') depth++;
    else if (c === ')' || c === ']' || c === '}') depth = Math.max(0, depth - 1);
    else if (c === ',' && depth === 0) return i;
  }
  return -1;
}

export function parseIngredient(rawLine) {
  // WP Recipe Maker renders a checkbox glyph inside each ingredient <li>, and
  // reading the rendered list keeps it: "▢ 1 tablespoon Olive Oil" has no leading
  // digit, so the quantity and the unit both went unparsed and the glyph ended up
  // in the ingredient name. Strip list decoration before anything else looks at it.
  const line = stripTags(rawLine).replace(/^[■-◿•‣⁃☐-☒·\s]+/, '').trim();
  let rest = line;
  let quantity = null;
  let quantityText = null;
  let unit = null;

  // Order is load-bearing: alternation is first-match, not longest-match, so every
  // compound form has to come before the bare integer it starts with. With the
  // integer first, "3/4 cup water" parsed as quantity 3 and name "/4 cup water" —
  // silently, on every US-measure site in the corpus.
  const F = '[' + FRACTION_CHARS + ']';
  const num =
    '(?:\\d+\\s+\\d+\\/\\d+' +      // 1 1/2
    '|\\d+\\s*' + F +               // 1½
    '|\\d+\\/\\d+' +                // 3/4
    '|\\d+(?:[.,]\\d+)?' +          // 250  or  1.5
    '|' + F + ')';                  // ½
  const qm = rest.match(new RegExp('^\\s*(' + num + '(?:\\s*(?:-|–|—|to|or)\\s*' + num + ')?)\\s*'));
  if (qm) {
    quantityText = qm[1].trim();
    rest = rest.slice(qm[0].length);
    quantity = numericValue(quantityText);
  }

  const um = rest.match(new RegExp('^(' + UNITS.join('|') + ')\\b\\.?\\s*', 'i'));
  if (um) {
    unit = um[1].toLowerCase();
    rest = rest.slice(um[0].length);
  }

  // Several languages write the amount AFTER the ingredient — Italian "Carote viola
  // 40 g", Korean "식빵 1장" — so a leading-number parser finds nothing and the whole
  // line ends up in `name`. Measured on the corpus: the Italian and Korean sources
  // parsed 0 of their quantities until this existed.
  //
  // Deliberately narrow. The number must be preceded by whitespace, so "Vitamin B12"
  // is not a quantity of 12, and it must sit at the very end, optionally followed by
  // a short unit token — which covers both a spaced unit ("40 g") and a glued CJK
  // counter ("1장").
  if (quantity == null) {
    const tail = rest.match(/\s(\d+(?:[.,]\d+)?)\s*([^\s\d(){}[\],;.]{0,4})$/);
    if (tail) {
      const n = Number(tail[1].replace(',', '.'));
      // "Juice of 1 lime" would otherwise become quantity 1, unit "lime", name
      // "Juice of". A name left dangling on a preposition is a sentence cut in half,
      // not an ingredient — measured at 0.03% of parses, and this removes most of it.
      const head = rest.slice(0, tail.index).trim();
      const dangling = /\b(of|into|about|around|approx|plus|instead|for|to|with|and|or)$/i.test(head);
      if (!dangling && Number.isFinite(n) && n > 0) {
        quantity = n;
        quantityText = tail[1];
        if (!unit && tail[2]) unit = tail[2].toLowerCase();
        rest = rest.slice(0, tail.index).trim();
      }
    }
  }

  // US recipe sites routinely publish the weight alongside the volume —
  // "3/4 cup (198g) warm water". That parenthetical is the only unambiguous
  // quantity on the line (a "cup" of flour and a "cup" of water are not the same
  // mass), so it is captured rather than left inside the name, where it would read
  // as part of the ingredient.
  let name = rest.trim();
  let metric = null;
  const mm = name.match(
    /\(\s*(\d+(?:[.,]\d+)?)\s*(g|kg|ml|l|oz|lb|lbs|grams?|kilograms?|millilitres?|milliliters?|litres?|liters?|ounces?|pounds?)\s*\)/i,
  );
  if (mm) {
    metric = { quantity: Number(mm[1].replace(',', '.')), unit: mm[2].toLowerCase() };
    name = (name.slice(0, mm.index) + name.slice(mm.index + mm[0].length)).replace(/\s{2,}/g, ' ').trim();
  }

  // A trailing ", finely chopped" is a prep note, not part of the item name — but the
  // comma has to be OUTSIDE any bracket, or "peaches (peeled, pitted and sliced)" is
  // cut in half and the name keeps an unbalanced "((peeled".
  let note = null;
  const cut = firstTopLevelComma(name);
  if (cut > 0) {
    const head = name.slice(0, cut).trim();
    const tail = name.slice(cut + 1).trim();
    if (tail && PREP_WORDS.test(tail)) {
      name = head;
      note = tail;
    }
  }

  return {
    raw: line,
    quantity,
    quantityText,
    unit,
    name: name || line,
    note,
    metric,
    isOptional: /\boptional\b/i.test(line),
  };
}

function numericValue(t) {
  if (!t) return null;
  const first = String(t).split(/\s*(?:-|–|—|to|or)\s*/)[0].trim();

  const mixed = first.match(/^(\d+)\s*(\d+)\/(\d+)$/);
  if (mixed) return Number(mixed[1]) + Number(mixed[2]) / Number(mixed[3]);

  const frac = first.match(/^(\d+)\/(\d+)$/);
  if (frac) return Number(frac[1]) / Number(frac[2]);

  const mixedGlyph = first.match(new RegExp('^(\\d+)\\s*([' + FRACTION_CHARS + '])$'));
  if (mixedGlyph) return Number(mixedGlyph[1]) + FRACTIONS[mixedGlyph[2]];

  if (FRACTIONS[first] != null) return Number(FRACTIONS[first].toFixed(4));

  const n = Number(first.replace(',', '.'));
  return Number.isFinite(n) ? n : null;
}

/**
 * schema.org has no ingredient-group field, but many sites emit "For the sauce:"
 * as a bare line with no quantity. Those become group headers instead of items.
 */
export function groupIngredients(lines) {
  const groups = [];
  let current = { name: null, items: [] };
  for (const rawLine of lines) {
    const t = stripTags(rawLine);
    if (!t) continue;
    const isHeader = /^(for the .+|.+:)$/i.test(t) && !/\d/.test(t) && t.length < 60;
    if (isHeader) {
      if (current.items.length) groups.push(current);
      current = { name: t.replace(/:$/, '').trim(), items: [] };
      continue;
    }
    current.items.push(parseIngredient(rawLine));
  }
  if (current.items.length) groups.push(current);
  return groups;
}

const NUTRI_KEYS = [
  'calories', 'carbohydrateContent', 'cholesterolContent', 'fatContent', 'fiberContent',
  'proteinContent', 'saturatedFatContent', 'servingSize', 'sodiumContent', 'sugarContent',
  'transFatContent', 'unsaturatedFatContent',
];

// Fields the mapper deliberately consumes. Anything else on the node is unmapped,
// and unmapped means recorded, never discarded.
const CONSUMED = new Set([
  '@type', '@context', '@id', 'name', 'description', 'image', 'author', 'datePublished',
  'dateModified', 'prepTime', 'cookTime', 'totalTime', 'performTime', 'recipeYield', 'yield',
  'recipeCategory', 'recipeCuisine', 'recipeIngredient', 'ingredients', 'recipeInstructions',
  'keywords', 'nutrition', 'tool', 'supply', 'url', 'mainEntityOfPage', 'publisher',
  'isPartOf', 'headline', 'thumbnailUrl',
]);

export function toCorpusRecipe(opts) {
  const { node, chefId, chefName, chefSlug, recipeSlug, sourceUrl, finalUrl, html, retrievedAt, blocks, pageTitle } = opts;

  const ingredientLines = asArray(node.recipeIngredient || node.ingredients);
  const ingredientGroups = groupIngredients(ingredientLines);
  const steps = parseInstructions(node.recipeInstructions);

  const nutrition =
    node.nutrition && typeof node.nutrition === 'object'
      ? Object.fromEntries(Object.entries(node.nutrition).filter(([k]) => NUTRI_KEYS.includes(k)))
      : null;

  const unmappedFields = {};
  for (const [k, v] of Object.entries(node)) if (!CONSUMED.has(k)) unmappedFields[k] = v;

  const yieldRaw = asArray(node.recipeYield || node.yield).map(textOf).filter(Boolean);
  const servingsMatch = yieldRaw.join(' ').match(/\d+/);

  return {
    schemaVersion: 1,
    id: chefSlug + '/' + recipeSlug,
    slug: recipeSlug,
    chefId,
    chefSlug,
    chefName,
    title: textOf(node.name),
    description: textOf(node.description),
    source: {
      sourceUrl,
      finalUrl,
      retrievedAt,
      publisher: textOf(node.publisher && node.publisher.name),
      authorRaw: asArray(node.author).map(textOf).filter(Boolean),
      datePublished: node.datePublished || null,
      rights:
        'Recipe text belongs to the rights-holder. This corpus stores functional content ' +
        '(ingredients, quantities, steps) plus a link back to the source, for internal ' +
        'app testing only. Not for redistribution.',
      pageTitle: pageTitle || null,
      htmlSha256: createHash('sha256').update(html).digest('hex'),
      jsonLdBlockCount: blocks.length,
      malformedJsonLdBlocks: blocks.malformed || [],
    },
    yield: { raw: yieldRaw, servings: servingsMatch ? Number(servingsMatch[0]) : null },
    timing: {
      prepMinutes: isoMinutes(node.prepTime),
      cookMinutes: isoMinutes(node.cookTime),
      totalMinutes: isoMinutes(node.totalTime),
      performMinutes: isoMinutes(node.performTime),
    },
    difficulty: null,
    cuisine: asArray(node.recipeCuisine).map(textOf).filter(Boolean),
    category: asArray(node.recipeCategory).map(textOf).filter(Boolean),
    // Comma is the schema.org convention and nothing else honours it: King Arthur
    // joins on ";;", several WordPress plugins on "|", and a bare ";" is common.
    // Splitting on commas alone turns 3 tags into 1 tag 40 characters long.
    keywords: [
      ...new Set(
        asArray(node.keywords)
          .flatMap((k) => String(k).split(/;;|[,;|]/))
          .map((s) => stripTags(s))
          .filter(Boolean),
      ),
    ],
    ingredientGroups,
    steps,
    equipment: asArray(node.tool).map(textOf).filter(Boolean),
    supplies: asArray(node.supply).map(textOf).filter(Boolean),
    nutrition,
    media: { coverImages: imageUrls(node.image), video: node.video || null },
    notes: { makeAhead: null, storage: null, substitutions: [], variations: [], chefTips: [] },
    unmappedFields,
    rawJsonLd: node,
  };
}
