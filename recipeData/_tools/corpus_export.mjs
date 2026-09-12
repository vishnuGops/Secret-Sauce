// corpus JSONL -> the app's own recipe shape (recipeData/schema.json).
//
//   node corpus_export.mjs --dry              # convert everything, write nothing, report
//   node corpus_export.mjs                    # -> corpus/export/<source>.jsonl
//   node corpus_export.mjs --only delish --files 5   # 5 sample files, human-readable
//
// The corpus keeps what the web published. The app needs what its own columns can
// hold, and the two disagree in ways that are *decisions*, not conversions — so each
// one is made here, once, and named:
//
//   difficulty     no source publishes it. Derived from size and time, and a
//                  derived value is marked in `attribution` so nobody mistakes it
//                  for the author's judgement.
//   servings       an int. "Serves 4-6" keeps the 4 and moves the phrase to the
//                  description, which is the rule recipeData/schema.json already
//                  states for the curated files.
//   quantity       a numeric, so "8-12" keeps 8 and says "8-12" in the note. A
//                  quantity of 0 is not allowed by the DB check (`null or > 0`),
//                  so a parsed 0 becomes null.
//   category       free text upstream, a 10-value repo convention here. Anything
//                  unrecognised becomes null rather than inventing an eleventh.
//   nutrition      schema.org strings ("12 g") -> numbers, and only the keys the
//                  app's label prints. `source` is deliberately NOT set: these are
//                  the publisher's numbers, not an estimate from our registry.
//
// Nothing here writes to supabase/. This is a staging format, and the export
// carries its credit line in `attribution` exactly so it cannot be laundered into
// seed data by accident.
import { createWriteStream } from 'node:fs';
import { readdir, mkdir, writeFile } from 'node:fs/promises';
import { dirname, resolve, basename } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readShard } from './corpus_stats.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const CORPUS = resolve(HERE, '../../corpus');
const IN = resolve(CORPUS, 'recipes');
const OUT = resolve(CORPUS, 'export');

const clampInt = (v, lo, hi) =>
  v == null || !Number.isFinite(Number(v)) ? null : Math.max(lo, Math.min(hi, Math.round(Number(v))));

const trim = (s, n) => {
  const t = String(s || '').replace(/\s+/g, ' ').trim();
  return t.length <= n ? t : t.slice(0, n - 1).replace(/\s\S*$/, '') + '…';
};

// ---------------------------------------------------------------- category map

const CATEGORY = [
  [/dessert|sweet|cake|cookie|pie|pudding|ice cream|baking|bake|pastry|candy|brownie/i, 'Dessert'],
  [/drink|beverage|cocktail|smoothie|juice|coffee|tea|mocktail/i, 'Drink'],
  [/breakfast|brunch|pancake|waffle|oatmeal|porridge/i, 'Breakfast'],
  [/appetizer|starter|nibble|hors|canape|dip|party food/i, 'Appetizer'],
  [/salad/i, 'Salad'],
  [/soup|stew|broth|chowder|bisque/i, 'Soup'],
  [/sauce|condiment|dressing|marinade|spice|seasoning|jam|preserve|chutney|pickle/i, 'Sauce'],
  [/snack|bar|granola|popcorn/i, 'Snack'],
  [/side|accompaniment|vegetable dish/i, 'Side'],
  [/main|dinner|lunch|entree|entrée|supper|pasta|curry|roast|grill|casserole|bowl/i, 'Main'],
];

function mapCategory(rec) {
  const hay = [...(rec.category || []), ...(rec.keywords || []).slice(0, 12), rec.title || ''].join(' | ');
  for (const [re, name] of CATEGORY) if (re.test(hay)) return name;
  return null;
}

// ---------------------------------------------------------------- difficulty

/**
 * No source in the corpus publishes a difficulty, and the app's column is not
 * nullable in practice (the editor always picks one). Size and time are the only
 * signals actually present on every record, so they are what it uses — and the
 * export says so, rather than passing a guess off as the author's word.
 */
function deriveDifficulty(rec, prep, cook) {
  const items = rec.ingredientGroups.reduce((a, g) => a + g.items.length, 0);
  const steps = rec.steps.length;
  const minutes = (prep || 0) + (cook || 0);
  const groups = rec.ingredientGroups.length + new Set(rec.steps.map((s) => s.stepGroup)).size;
  const score =
    (items > 18 ? 2 : items > 10 ? 1 : 0) +
    (steps > 14 ? 2 : steps > 7 ? 1 : 0) +
    (minutes > 180 ? 2 : minutes > 75 ? 1 : 0) +
    (groups > 3 ? 1 : 0);
  return score >= 4 ? 'hard' : score >= 2 ? 'medium' : 'easy';
}

// ---------------------------------------------------------------- nutrition

const NUTRI_MAP = {
  calories: 'calories',
  fatContent: 'total_fat_g',
  saturatedFatContent: 'saturated_fat_g',
  transFatContent: 'trans_fat_g',
  cholesterolContent: 'cholesterol_mg',
  sodiumContent: 'sodium_mg',
  carbohydrateContent: 'total_carbs_g',
  fiberContent: 'dietary_fiber_g',
  sugarContent: 'total_sugars_g',
  proteinContent: 'protein_g',
};

/** "12 g", "1,234 kcal", 18 -> a number; anything else -> null. */
function numberish(v) {
  if (typeof v === 'number') return Number.isFinite(v) ? v : null;
  if (typeof v !== 'string') return null;
  const m = v.replace(/,/g, '').match(/-?\d+(?:\.\d+)?/);
  if (!m) return null;
  const n = Number(m[0]);
  return Number.isFinite(n) && n >= 0 ? n : null;
}

function mapNutrition(rec) {
  if (!rec.nutrition) return null;
  const out = {};
  for (const [from, to] of Object.entries(NUTRI_MAP)) {
    const n = numberish(rec.nutrition[from]);
    if (n != null) out[to] = n;
  }
  return Object.keys(out).length ? out : null;
}

// ---------------------------------------------------------------- timing

function timing(rec) {
  const t = rec.timing || {};
  let prep = clampInt(t.prepMinutes, 0, 1440);
  let cook = clampInt(t.cookMinutes, 0, 1440);
  const total = clampInt(t.totalMinutes, 0, 1440);
  if (prep == null && cook == null && total != null) {
    // With only a total, all of it is hands-on as far as the app can tell. Guessing
    // a split would put invented numbers on the recipe card.
    prep = total;
    cook = 0;
  }
  if (prep == null) prep = total != null && cook != null ? Math.max(0, total - cook) : 0;
  if (cook == null) cook = total != null ? Math.max(0, total - prep) : 0;
  return { prep, cook };
}

// ---------------------------------------------------------------- ingredients

const UNIT_CANON = {
  tablespoon: 'tbsp', tablespoons: 'tbsp', tbsps: 'tbsp', tbs: 'tbsp',
  teaspoon: 'tsp', teaspoons: 'tsp', tsps: 'tsp',
  gram: 'g', grams: 'g', gr: 'g', kilogram: 'kg', kilograms: 'kg',
  milliliter: 'ml', millilitre: 'ml', milliliters: 'ml', millilitres: 'ml',
  liter: 'L', litre: 'L', liters: 'L', litres: 'L', l: 'L',
  ounce: 'oz', ounces: 'oz', pound: 'lb', pounds: 'lb', lbs: 'lb',
};

const canonUnit = (u) => {
  if (!u) return null;
  const k = String(u).toLowerCase().replace(/\.$/, '');
  return UNIT_CANON[k] || k;
};

function mapIngredient(i) {
  const notes = [];
  if (i.note) notes.push(i.note);
  // A range cannot survive a numeric column, so it survives in words.
  if (i.quantityText && /-|–|—|\bto\b|\bor\b/.test(i.quantityText)) {
    notes.push(i.quantityText + (i.unit ? ' ' + i.unit : ''));
  }
  if (i.metric) notes.push(i.metric.quantity + ' ' + i.metric.unit);
  const q = i.quantity != null && Number(i.quantity) > 0 ? Number(i.quantity) : null;
  return {
    quantity: q,
    unit: canonUnit(i.unit),
    name: trim(i.name || i.raw, 200).toLowerCase() || 'ingredient',
    note: notes.length ? trim(notes.join('; '), 300) : null,
    is_optional: !!i.isOptional,
  };
}

function mapIngredientGroups(rec) {
  return rec.ingredientGroups
    .map((g) => ({ name: g.name ? trim(g.name, 120) : '', ingredients: g.items.map(mapIngredient) }))
    .filter((g) => g.ingredients.length);
}

// ---------------------------------------------------------------- steps

function mapStepGroups(rec) {
  const groups = [];
  let current = null;
  for (const s of rec.steps) {
    const name = s.stepGroup ? trim(s.stepGroup, 120) : '';
    if (!current || current.name !== name) {
      current = { name, steps: [] };
      groups.push(current);
    }
    const text = trim(s.text, 4000);
    if (!text) continue;
    current.steps.push({
      text,
      duration_minutes: clampInt(s.durationMinutes, 1, 2880),
      temperature: s.temperature ? trim(s.temperature, 60) : null,
      tip: s.tip ? trim(s.tip, 600) : null,
    });
  }
  return groups.filter((g) => g.steps.length);
}

// ---------------------------------------------------------------- the record

export function toAppRecipe(rec) {
  const ingredient_groups = mapIngredientGroups(rec);
  const step_groups = mapStepGroups(rec);
  if (!ingredient_groups.length || !step_groups.length) return { ok: false, why: 'empty-content' };

  const slug = String(rec.slug || '').replace(/[^a-z0-9-]/g, '').replace(/^-+|-+$/g, '');
  if (!slug) return { ok: false, why: 'no-slug' };
  const title = trim(rec.title, 120);
  if (!title) return { ok: false, why: 'no-title' };

  const { prep, cook } = timing(rec);
  const a = rec.attribution || {};
  const yieldRaw = (rec.yield && rec.yield.raw) || [];
  const servings = clampInt(rec.yield && rec.yield.servings, 1, 100);

  // The description has to exist and has to carry what `servings` could not.
  const bits = [];
  if (rec.description) bits.push(trim(rec.description, 2000));
  const qualifier = yieldRaw.find((y) => /[a-z]/i.test(String(y)));
  if (qualifier && servings == null) bits.push('Yield: ' + trim(qualifier, 120) + '.');
  else if (qualifier && !/^\d+$/.test(String(qualifier).trim())) bits.push('Yield: ' + trim(qualifier, 120) + '.');
  if (!bits.length) bits.push(title + ' from ' + (a.group || 'the web') + '.');

  const credit =
    (a.chef ? a.chef + ' — ' : '') + (a.group || '') +
    (a.sourceUrl ? ' (' + a.sourceUrl + ')' : '');

  return {
    ok: true,
    recipe: {
      slug,
      title,
      description: trim(bits.join(' '), 8000),
      cuisine: (rec.cuisine && rec.cuisine[0]) ? trim(rec.cuisine[0], 60) : null,
      category: mapCategory(rec),
      difficulty: deriveDifficulty(rec, prep, cook),
      prep_minutes: prep,
      cook_minutes: cook,
      servings: servings == null ? 4 : servings,
      visibility: 'public',
      attribution: trim(credit + ' · difficulty derived, not stated by the source', 500),
      nutrition: mapNutrition(rec),
      ingredient_groups,
      step_groups,
    },
  };
}


// ---------------------------------------------------------------- validation

const CATEGORIES = new Set([
  'Appetizer', 'Breakfast', 'Main', 'Side', 'Salad', 'Soup', 'Dessert', 'Drink',
  'Snack', 'Sauce',
]);
const SLUG = /^[a-z0-9]+(-[a-z0-9]+)*$/;
const isInt = (v, lo, hi) => Number.isInteger(v) && v >= lo && v <= hi;

/**
 * The rules recipeData/schema.json states, checked here so "convertible" means
 * "would survive tool/recipe_format.dart" rather than "did not throw". Every one of
 * these is a real column constraint or a documented repo convention — the DB check
 * on `quantity` is `null or > 0`, `servings` is an int the detail screen divides by,
 * and `category` is a ten-value convention that exists to stop Mains/Main/main drift.
 */
export function validateAppRecipe(r) {
  const bad = [];
  if (!SLUG.test(r.slug)) bad.push('slug');
  if (!r.title || r.title.length > 120) bad.push('title');
  if (!r.description || !r.description.trim()) bad.push('description');
  if (!['easy', 'medium', 'hard'].includes(r.difficulty)) bad.push('difficulty');
  if (!isInt(r.prep_minutes, 0, 1440)) bad.push('prep_minutes');
  if (!isInt(r.cook_minutes, 0, 1440)) bad.push('cook_minutes');
  if (!isInt(r.servings, 1, 100)) bad.push('servings');
  if (r.category !== null && !CATEGORIES.has(r.category)) bad.push('category');
  if (!Array.isArray(r.ingredient_groups) || !r.ingredient_groups.length) bad.push('ingredient_groups');
  else {
    for (const g of r.ingredient_groups) {
      if (typeof g.name !== 'string') bad.push('group.name');
      if (!g.ingredients.length) bad.push('group.empty');
      for (const i of g.ingredients) {
        if (!i.name || !i.name.trim()) bad.push('ingredient.name');
        if (i.quantity !== null && !(typeof i.quantity === 'number' && i.quantity > 0)) {
          bad.push('ingredient.quantity');
        }
      }
    }
  }
  if (!Array.isArray(r.step_groups) || !r.step_groups.length) bad.push('step_groups');
  else {
    for (const g of r.step_groups) {
      if (typeof g.name !== 'string') bad.push('stepGroup.name');
      if (!g.steps.length) bad.push('stepGroup.empty');
      for (const st of g.steps) {
        if (!st.text || !st.text.trim()) bad.push('step.text');
        if (st.duration_minutes !== null && !isInt(st.duration_minutes, 1, 2880)) {
          bad.push('step.duration_minutes');
        }
      }
    }
  }
  if (r.nutrition !== null && (typeof r.nutrition !== 'object' || !Object.keys(r.nutrition).length)) {
    bad.push('nutrition');
  }
  return [...new Set(bad)];
}

async function main() {
  const argv = process.argv.slice(2);
  const arg = (f) => {
    const i = argv.indexOf(f);
    return i >= 0 ? argv[i + 1] : null;
  };
  const dry = argv.includes('--dry');
  const only = arg('--only');
  const fileCount = Number(arg('--files')) || 0;

  let shards = [];
  try {
    shards = (await readdir(IN)).filter((f) => f.endsWith('.jsonl')).sort();
  } catch {
    console.log('no shards at ' + IN);
    return;
  }
  if (only) shards = shards.filter((f) => f.includes(only));

  await mkdir(OUT, { recursive: true });
  const validate = !argv.includes('--no-validate');
  let total = 0;
  let ok = 0;
  let badRecipes = 0;
  const why = {};
  const invalid = {};
  const badSamples = [];
  const samples = [];

  for (const f of shards) {
    const slug = basename(f, '.jsonl');
    const out = dry || fileCount ? null : createWriteStream(resolve(OUT, f), { flags: 'w' });
    let n = 0;
    for await (const rec of readShard(resolve(IN, f))) {
      total++;
      const r = toAppRecipe(rec);
      if (!r.ok) {
        why[r.why] = (why[r.why] || 0) + 1;
        continue;
      }
      const bad = validate ? validateAppRecipe(r.recipe) : [];
      if (bad.length) {
        for (const b of bad) invalid[b] = (invalid[b] || 0) + 1;
        badRecipes++;
        if (badSamples.length < 5) badSamples.push({ slug: r.recipe.slug, bad });
        continue;
      }
      ok++;
      n++;
      if (out) out.write(JSON.stringify(r.recipe) + '\n');
      if (fileCount && samples.length < fileCount) samples.push([slug, r.recipe]);
    }
    if (out) await new Promise((res) => out.end(res));
    if (n) console.log(slug.padEnd(34) + String(n).padStart(6) + ' exported');
  }

  for (const [slug, r] of samples) {
    const p = resolve(OUT, 'samples', slug, r.slug + '.json');
    await mkdir(dirname(p), { recursive: true });
    await writeFile(p, JSON.stringify(r, null, 2) + '\n', 'utf8');
    console.log('sample -> ' + p);
  }

  console.log(
    '\n' + ok + ' of ' + total + ' convertible' +
    (Object.keys(why).length ? '  rejected: ' + JSON.stringify(why) : ''),
  );
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
