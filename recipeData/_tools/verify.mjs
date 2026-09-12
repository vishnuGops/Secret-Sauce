// Phase 2 round-trip diff. Reads back every ingested recipe from the database and
// compares it field by field against the corpus file it came from.
//
//   node recipeData/_tools/verify.mjs            # diff everything ingested so far
//   node recipeData/_tools/verify.mjs --chef mary-berry
//
// A green save proves nothing. This is the deliverable: what the app kept, what it
// changed, and what it silently dropped. Reads go through psql against the local
// container because `melos run db:*` needs a psql on PATH this machine does not have
// (B033).
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const exec = promisify(execFile);
const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, '..');
const CONTAINER = process.env.SS_DB_CONTAINER || 'supabase_db_secret-sauce';

const readJson = async (p, fallback) => {
  try {
    return JSON.parse(await readFile(p, 'utf8'));
  } catch {
    return fallback;
  }
};

async function psqlJson(sql) {
  const { stdout } = await exec(
    'docker',
    ['exec', CONTAINER, 'psql', '-U', 'postgres', '-d', 'postgres', '-tAc', sql],
    { env: { ...process.env, MSYS_NO_PATHCONV: '1' }, maxBuffer: 64 * 1024 * 1024 },
  );
  const t = stdout.trim();
  return t ? JSON.parse(t) : null;
}

/**
 * The recipe as the database holds it, shaped like the corpus file for comparison.
 *
 * Steps hang off `step_groups`, not off the recipe: the app models step sections
 * the same way it models ingredient groups. No `--` comments inside this SQL — it
 * is collapsed to a single line before being passed to psql, which would turn a
 * comment into "the rest of the query is commented out".
 */
export async function readBack(recipeId) {
  const sql = `
    select coalesce(json_agg(x)->0, 'null'::json)::text from (
      select
        r.id, r.title, r.description, r.servings, r.prep_minutes, r.cook_minutes,
        r.difficulty, r.cuisine, r.category, r.attribution, r.visibility,
        r.cover_image_url, r.nutrition, r.owner_id,
        p.display_name as owner_name,
        (select coalesce(json_agg(g order by g.sort_order), '[]'::json) from (
           select ig.name, ig.sort_order,
             (select coalesce(json_agg(i order by i.sort_order), '[]'::json) from (
                select ing.quantity, ing.unit, ing.name, ing.note, ing.is_optional, ing.sort_order
                from ingredients ing where ing.group_id = ig.id
             ) i) as items
           from ingredient_groups ig where ig.recipe_id = r.id
         ) g) as groups,
        (select coalesce(json_agg(s order by s.g_order, s.sort_order), '[]'::json) from (
           select st.text, st.duration_minutes, st.temperature, st.tip, st.image_url,
                  st.sort_order, sg.name as section, sg.sort_order as g_order
           from steps st join step_groups sg on sg.id = st.group_id
           where sg.recipe_id = r.id
         ) s) as steps,
        (select count(*) from step_groups sg where sg.recipe_id = r.id) as step_group_count
      from recipes r join profiles p on p.id = r.owner_id
      where r.id = '${recipeId}'
    ) x;`;
  return psqlJson(sql.replace(/\s+/g, ' '));
}

const norm = (s) => (s == null ? null : String(s).replace(/\s+/g, ' ').trim());
const numEq = (a, b) => (a == null && b == null) || Number(a) === Number(b);

/** One recipe's differences. Each entry says field, expected, actual, severity. */
export function diffRecipe(corpus, db) {
  const d = [];
  const add = (field, severity, expected, actual, note) =>
    d.push({ field, severity, expected, actual, ...(note ? { note } : {}) });

  if (!db) {
    add('recipe', 'blocker', corpus.title, null, 'not found in database');
    return d;
  }

  if (norm(db.title) !== norm(corpus.title)) add('title', 'data-loss', corpus.title, db.title);
  if (norm(db.description) !== norm(corpus.description)) {
    add('description', 'data-loss', norm(corpus.description), norm(db.description));
  }
  if (!numEq(db.prep_minutes, corpus.timing.prepMinutes)) {
    add('prep_minutes', 'data-loss', corpus.timing.prepMinutes, db.prep_minutes);
  }
  if (!numEq(db.cook_minutes, corpus.timing.cookMinutes)) {
    add('cook_minutes', 'data-loss', corpus.timing.cookMinutes, db.cook_minutes);
  }
  if (!numEq(db.servings, corpus.yield.servings)) {
    add('servings', 'data-loss', corpus.yield.servings, db.servings);
  }
  if (norm(db.cuisine) !== norm(corpus.cuisine[0] || null)) {
    add('cuisine', 'data-loss', corpus.cuisine[0] || null, db.cuisine);
  }
  if (corpus.category.length && !db.category) {
    add('category', 'data-loss', corpus.category.join(', '), null, 'the editor has no category control');
  }
  if (corpus.source.sourceUrl && !(db.attribution || '').includes(corpus.source.sourceUrl)) {
    add('attribution.sourceUrl', 'data-loss', corpus.source.sourceUrl, db.attribution);
  }

  // -- ingredients ----------------------------------------------------------
  const cGroups = corpus.ingredientGroups;
  const dGroups = db.groups || [];
  if (cGroups.length !== dGroups.length) {
    add('ingredient_groups.count', 'data-loss', cGroups.length, dGroups.length);
  }
  const cItems = cGroups.flatMap((g) => g.items);
  const dItems = dGroups.flatMap((g) => g.items);
  if (cItems.length !== dItems.length) {
    add('ingredients.count', 'data-loss', cItems.length, dItems.length);
  }

  for (let i = 0; i < Math.min(cGroups.length, dGroups.length); i++) {
    const want = norm(cGroups[i].name);
    const got = norm(dGroups[i].name);
    if (want == null && got === '') {
      // An unnamed group is stored as '' rather than NULL. Nothing is lost, but
      // the two representations of "no group name" are now both in the table.
      add('ingredient_groups[' + i + '].name', 'cosmetic', null, '', 'empty string stored instead of NULL');
    } else if (want !== got) {
      add('ingredient_groups[' + i + '].name', 'data-loss', cGroups[i].name, dGroups[i].name);
    }
  }
  for (let i = 0; i < Math.min(cItems.length, dItems.length); i++) {
    const c = cItems[i];
    const x = dItems[i];
    if (norm(c.name) !== norm(x.name)) add('ingredients[' + i + '].name', 'data-loss', c.name, x.name);
    if (norm(c.unit) !== norm(x.unit)) add('ingredients[' + i + '].unit', 'data-loss', c.unit, x.unit);
    if (!numEq(c.quantity, x.quantity)) {
      add('ingredients[' + i + '].quantity', 'data-loss', c.quantity, x.quantity);
    } else if (c.quantityText && /[-–—]|\bto\b|\bor\b/.test(c.quantityText)) {
      add('ingredients[' + i + '].quantityRange', 'modeling-gap', c.quantityText, x.quantity,
        'quantity is a single numeric; the range cannot be stored');
    }
    if (norm(c.note) !== norm(x.note)) add('ingredients[' + i + '].note', 'data-loss', c.note, x.note);
    if (!!c.isOptional !== !!x.is_optional) {
      add('ingredients[' + i + '].isOptional', 'data-loss', c.isOptional, x.is_optional);
    }
  }

  // -- steps ----------------------------------------------------------------
  const dSteps = db.steps || [];
  if (corpus.steps.length !== dSteps.length) {
    add('steps.count', 'data-loss', corpus.steps.length, dSteps.length);
  }
  for (let i = 0; i < Math.min(corpus.steps.length, dSteps.length); i++) {
    if (norm(corpus.steps[i].text) !== norm(dSteps[i].text)) {
      add('steps[' + i + '].text', 'data-loss', norm(corpus.steps[i].text), norm(dSteps[i].text));
    }
  }

  // -- things with nowhere to go -------------------------------------------
  if (corpus.keywords.length) {
    add('keywords', 'modeling-gap', corpus.keywords.length + ' keywords', null, 'tags tables exist, no app code writes them');
  }
  if (corpus.notes.chefTips.length) {
    add('chefTips', 'modeling-gap', corpus.notes.chefTips.length + ' recipe-level tips', null, 'app has per-step tips only');
  }
  const qualifier = corpus.yield.raw.find((y) => !/^\d+$/.test(y));
  if (qualifier) {
    add('yield.raw', 'modeling-gap', qualifier, db.servings, 'servings is an int; the qualifier has no column');
  }
  if (corpus.media.coverImages.length && !db.cover_image_url) {
    add('coverImage', 'modeling-gap', corpus.media.coverImages[0], null, 'the editor uploads a file; it cannot take a URL');
  }
  if (corpus.nutrition && !db.nutrition) {
    add('nutrition', 'modeling-gap', Object.keys(corpus.nutrition).join(','), null, 'not entered by this harness');
  }
  if (corpus.unmappedFields && corpus.unmappedFields.video) {
    add('video', 'modeling-gap', 'source has video', null, 'no column');
  }
  return d;
}

async function main() {
  const argv = process.argv.slice(2);
  const i = argv.indexOf('--chef');
  const onlyChef = i >= 0 ? argv[i + 1] : null;

  const state = await readJson(resolve(ROOT, '_state/ingest.json'), { chefs: {} });
  const results = [];

  for (const [slug, cs] of Object.entries(state.chefs)) {
    if (onlyChef && slug !== onlyChef) continue;
    for (const [file, rec] of Object.entries(cs.recipes)) {
      if (!rec.recipeId) continue;
      const corpus = await readJson(resolve(ROOT, 'recipes', file), null);
      if (!corpus) continue;
      const db = await readBack(rec.recipeId);
      const diffs = diffRecipe(corpus, db);
      results.push({ chef: slug, file, recipeId: rec.recipeId, title: corpus.title, diffs, ingestNotes: rec.notes || [] });
      const bad = diffs.filter((x) => x.severity === 'data-loss' || x.severity === 'blocker').length;
      console.log(
        (bad ? 'DIFF  ' : 'clean ') + file +
        '  loss=' + bad + ' gaps=' + diffs.filter((x) => x.severity === 'modeling-gap').length,
      );
    }
  }

  const out = resolve(ROOT, '_reports/roundtrip.json');
  await mkdir(dirname(out), { recursive: true });
  await writeFile(out, JSON.stringify({ generatedAt: new Date().toISOString(), results }, null, 2) + '\n');

  const all = results.flatMap((r) => r.diffs);
  const byField = {};
  for (const d of all) {
    const key = d.field.replace(/\[\d+\]/g, '[]');
    byField[key] = byField[key] || { severity: d.severity, count: 0, recipes: new Set() };
    byField[key].count++;
  }
  console.log('\n' + results.length + ' recipes verified, ' + all.length + ' differences');
  for (const [k, v] of Object.entries(byField).sort((a, b) => b[1].count - a[1].count)) {
    console.log('  ' + String(v.count).padStart(5) + '  ' + v.severity.padEnd(13) + k);
  }
  console.log('\nwrote ' + out);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}
