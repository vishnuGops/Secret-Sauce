// Enricher for WP Recipe Maker sites (justonecookbook.com, feelgoodfoodie.net,
// seonkyounglongest.com, cheflolaskitchen.com, easyanddelish.com and most of the
// WordPress recipe ecosystem).
//
// Batch 1 came entirely from bbc.co.uk/food, which publishes no step sections and
// no equipment at all — so the app's step-section support went untested and its
// missing equipment table stayed hypothetical. WPRM publishes both, in HTML, with
// stable class names:
//
//   wprm-recipe-ingredient-group-name    ingredient group headings
//   wprm-recipe-instruction-group-name   step section headings  <- new coverage
//   wprm-recipe-equipment-name           equipment list          <- new coverage
//
// Unlike BBC's hashed ssrcss-* classes these are part of the plugin's public
// markup contract, so keying on them is safe.

import { parseIngredient } from './extract.mjs';

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

// WPRM renders "1 ½ cups" where the JSON-LD says "1 1/2 cups". Stripping
// non-alphanumerics turns the first into `1cups` and the second into `112cups`, so the
// twin is never found and the line is captured a second time. Expand the glyphs first.
const VULGAR = { '½': '1/2', '⅓': '1/3', '⅔': '2/3', '¼': '1/4', '¾': '3/4', '⅕': '1/5', '⅖': '2/5', '⅗': '3/5', '⅘': '4/5', '⅙': '1/6', '⅚': '5/6', '⅛': '1/8', '⅜': '3/8', '⅝': '5/8', '⅞': '7/8' };

const matchKey = (s) =>
  String(s)
    .replace(/[¼-¾⅐-⅞]/g, (c) => VULGAR[c] || c)
    .toLowerCase()
    .replace(/[^a-z0-9]/g, '');

function allMatches(html, re) {
  const out = [];
  let m;
  while ((m = re.exec(html))) out.push(m);
  return out;
}

/** Equipment names, in page order. Often absent — WPRM equipment is opt-in. */
export function wprmEquipment(html) {
  const names = allMatches(
    html,
    /class="[^"]*wprm-recipe-equipment-name[^"]*"[^>]*>([\s\S]*?)<\/(?:span|div|a|h\d)>/gi,
  ).map((m) => text(m[1]));
  return [...new Set(names.filter(Boolean))];
}

/**
 * Step section headings, in page order. The JSON-LD carries these as HowToSection
 * names too, but only when the author used sections *and* the plugin emitted them;
 * reading the rendered headings catches the cases where it did not.
 */
export function wprmInstructionGroups(html) {
  return allMatches(
    html,
    /class="[^"]*wprm-recipe-instruction-group-name[^"]*"[^>]*>([\s\S]*?)<\/h\d>/gi,
  )
    .map((m) => text(m[1]))
    .filter(Boolean);
}

export function wprmIngredientGroups(html) {
  return allMatches(
    html,
    /class="[^"]*wprm-recipe-ingredient-group-name[^"]*"[^>]*>([\s\S]*?)<\/h\d>/gi,
  )
    .map((m) => text(m[1]))
    .filter(Boolean);
}

/**
 * Ingredient lines grouped under their headings, read from the rendered list.
 * Each `wprm-recipe-ingredient` <li> is assigned to the most recent heading.
 */
export function wprmGroupedIngredients(html) {
  const marker =
    /class="[^"]*wprm-recipe-ingredient-group-name[^"]*"[^>]*>([\s\S]*?)<\/h\d>|<li[^>]*class="[^"]*wprm-recipe-ingredient\b[^"]*"[^>]*>([\s\S]*?)<\/li>/gi;

  const groups = [];
  let current = { name: null, lines: [] };
  for (const m of allMatches(html, marker)) {
    if (m[1] != null) {
      const name = text(m[1]);
      if (!name) continue;
      if (current.lines.length) groups.push(current);
      current = { name, lines: [] };
    } else if (m[2] != null) {
      const line = text(m[2]);
      if (line) current.lines.push(line);
    }
  }
  if (current.lines.length) groups.push(current);
  return groups;
}

/**
 * Apply everything WPRM publishes that the JSON-LD dropped. As with the BBC
 * enricher, an HTML line that has no JSON-LD twin is kept and flagged rather than
 * silently merged, and ingredient counts are never allowed to drift.
 */
export function applyWprmEnrichment(recipe, html) {
  const notes = [];

  const equipment = wprmEquipment(html);
  if (equipment.length) {
    recipe.equipment = equipment;
    notes.push('equipment-from-html: ' + equipment.length);
  }

  // Step sections. Prefer whatever the JSON-LD already produced; fill in from the
  // rendered headings only when the parse found none.
  const haveSections = recipe.steps.some((s) => s.stepGroup);
  if (!haveSections) {
    const sections = wprmInstructionGroups(html);
    if (sections.length) {
      notes.push('step-sections-html-only: ' + sections.join(' | '));
    }
  }

  const htmlGroups = wprmGroupedIngredients(html);
  if (htmlGroups.length > 1) {
    const flat = recipe.ingredientGroups.flatMap((g) => g.items);
    const byRaw = new Map(flat.map((i) => [matchKey(i.raw), i]));
    const rebuilt = [];
    const used = new Set();

    for (const g of htmlGroups) {
      const items = [];
      for (const line of g.lines) {
        const k = matchKey(line);
        const hit = byRaw.get(k);
        if (hit) {
          items.push(hit);
          used.add(k);
        } else {
          // An HTML-only line is still an ingredient line; leaving it unparsed put
          // "1 1/2 cups whole milk" into the `name` field of 2.9% of every
          // ingredient captured. Parse it like any other line, and keep the flag.
          items.push({ ...parseIngredient(line), htmlOnly: true });
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

  recipe.source.enrichment = { site: 'wprm', notes };
  return recipe;
}
