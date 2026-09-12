// BBC Food publishes more structure in its HTML than in its JSON-LD.
// JSON-LD flattens every ingredient into one list, so "For the almond paste
// filling" / "For the icing glaze" — which the app models as ingredient groups —
// would be lost by a JSON-LD-only capture. This recovers them from the page,
// plus the recipe tips and the chef link.
//
// Class names on bbc.co.uk are hashed (ssrcss-*) and change without notice, so
// nothing here keys on a class: it walks document order between the section
// headings instead.

const decodeEntities = (s) =>
  String(s)
    .replace(/&quot;/g, '"')
    .replace(/&#0?39;/g, "'")
    .replace(/&apos;/g, "'")
    .replace(/&nbsp;/g, ' ')
    .replace(/&#x([0-9a-f]+);/gi, (_, h) => String.fromCodePoint(parseInt(h, 16)))
    .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(Number(d)))
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&amp;/g, '&');

const text = (s) =>
  decodeEntities(String(s).replace(/<[^>]+>/g, ' ')).replace(/\s+/g, ' ').trim();

function sliceBetween(html, startRe, endRe) {
  const s = html.search(startRe);
  if (s < 0) return null;
  const rest = html.slice(s);
  const e = rest.slice(1).search(endRe);
  return e < 0 ? rest : rest.slice(0, e + 1);
}

/**
 * Ingredient group headings in document order, each with the ingredient lines
 * that follow it. Items before the first heading belong to an unnamed group.
 */
export function bbcIngredientGroups(html) {
  const region = sliceBetween(html, />Ingredients<\/h2>/i, />Method<\/h2>/i);
  if (!region) return null;

  const groups = [];
  let current = { name: null, lines: [] };
  const re = /<h3[^>]*>([\s\S]*?)<\/h3>|<li[^>]*>([\s\S]*?)<\/li>/gi;
  let m;
  while ((m = re.exec(region))) {
    if (m[1] != null) {
      const name = text(m[1]);
      if (!name) continue;
      if (current.lines.length) groups.push(current);
      current = { name, lines: [] };
    } else {
      const line = text(m[2]);
      if (line) current.lines.push(line);
    }
  }
  if (current.lines.length) groups.push(current);
  return groups.length ? groups : null;
}

/**
 * The "Recipe tips" block — chef-level advice the app can only store per step.
 * The region ends at the next <h2>, not at </section>: the surrounding section
 * also contains the "Related recipes" carousel, whose card captions otherwise
 * read as tips (one turkey recipe captured 47 of them, 46 of which were links).
 */
export function bbcRecipeTips(html) {
  const region = sliceBetween(html, />Recipe [Tt]ips?<\/h[23]>/, /<h2[\s>]/i);
  if (!region) return [];
  const out = [];
  const re = /<p[^>]*>([\s\S]*?)<\/p>/gi;
  let m;
  while ((m = re.exec(region))) {
    const t = text(m[1]);
    if (t && t.length > 3) out.push(t);
  }
  return out;
}

export function bbcChefSlug(html) {
  const m = html.match(/\/food\/chefs\/([a-z0-9_]+)/i);
  return m ? m[1] : null;
}

export function bbcDescription(html) {
  const m = html.match(/<meta\s+name="description"\s+content="([^"]*)"/i);
  return m ? decodeEntities(m[1]).trim() : null;
}

/**
 * Key for matching an HTML ingredient line against its JSON-LD twin. The two
 * differ cosmetically: BBC wraps ingredient names in links, so stripping tags
 * leaves "1 medium onion , diced" against the JSON-LD's "1 medium onion, diced".
 * Matching on the raw text treated 320 identical lines as unmatched and appended
 * them a second time, inflating ingredient counts. Compare on letters and digits
 * only — cosmetic differences vanish, real differences survive.
 */
const matchKey = (s) => String(s).toLowerCase().replace(/[^a-z0-9]/g, '');

/**
 * Re-group an already-extracted recipe using the page's own headings, and record
 * what the JSON-LD had lost. Matching is by the verbatim ingredient line, so a
 * line the HTML and JSON-LD disagree on is reported, never silently dropped.
 */
export function applyBbcEnrichment(recipe, html) {
  const notes = [];

  const htmlGroups = bbcIngredientGroups(html);
  if (htmlGroups && htmlGroups.length > 1) {
    const flat = recipe.ingredientGroups.flatMap((g) => g.items);
    const byRaw = new Map(flat.map((i) => [matchKey(i.raw), i]));
    const rebuilt = [];
    const used = new Set();

    for (const g of htmlGroups) {
      const items = [];
      for (const line of g.lines) {
        const key = matchKey(line);
        const hit = byRaw.get(key);
        if (hit) {
          items.push(hit);
          used.add(key);
        } else {
          // Present on the page but not in the JSON-LD: keep it, flagged.
          items.push({
            raw: line,
            quantity: null,
            quantityText: null,
            unit: null,
            name: line,
            note: null,
            isOptional: /\boptional\b/i.test(line),
            htmlOnly: true,
          });
          notes.push('ingredient-html-only: ' + line);
        }
      }
      if (items.length) rebuilt.push({ name: g.name, items });
    }

    const orphans = flat.filter((i) => !used.has(matchKey(i.raw)));
    if (orphans.length) {
      rebuilt.push({ name: null, items: orphans });
      notes.push('ingredient-jsonld-only: ' + orphans.length);
    }

    recipe.ingredientGroups = rebuilt;
    notes.push('regrouped-from-html: ' + htmlGroups.length + ' groups');
  }

  const tips = bbcRecipeTips(html);
  if (tips.length) {
    recipe.notes.chefTips = tips;
    notes.push('chef-tips: ' + tips.length);
  }

  const desc = bbcDescription(html);
  if (desc && (!recipe.description || desc.length > recipe.description.length)) {
    recipe.description = desc;
  }

  recipe.source.enrichment = { site: 'bbc.co.uk/food', notes };
  return recipe;
}
