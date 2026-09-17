// Phase 2 — drive the real Flutter web UI with Playwright and add the corpus to
// the app, one chef and one recipe at a time.
//
//   node recipeData/_tools/ingest.mjs --chef nigella-lawson --limit 1 --headed
//   node recipeData/_tools/ingest.mjs                       # every chef in chefs.json
//
// Three things about this app shape the whole script, all learned the hard way:
//
//   1. Flutter web renders to canvas. There is no DOM until the accessibility
//      placeholder is clicked, and Flutter parks that placeholder outside the
//      viewport, so a real click times out. It has to be clicked via JS.
//   2. locator.fill() does not reach a Flutter text field. It sets the DOM input
//      value, the framework never sees it, and the field stays empty while
//      validation reports it as invalid. Everything here types key by key.
//   3. Semantics nodes exist only for what is on screen. A control below the fold
//      is not "hidden", it is absent, so locators have to scroll and retry.
import { chromium } from 'playwright';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, '..');
const BASE = process.env.APP_URL || 'http://localhost:5599';

// ---------------------------------------------------------------------------
// THIS HARNESS SIGNS IN AS ITSELF, NEVER AS THE CHEF (B114).
//
// It used to create one account per corpus chef — `nigella-lawson@corpus.invalid`
// and fourteen more — and post scraped recipes through it. The result was 15 real
// named people holding log-in-able `kind = 'member'` profiles, ranked on the chef
// leaderboard, each credited as the author of recipes they had not published
// here. Phase 35b exists specifically so a captured byline is `kind = 'imported'`
// with no account; this script was routing around that design.
//
// What the harness actually needs is A account to drive the editor with. Whose it
// is has no bearing on the round-trip diff it measures, and the chef's name is
// already carried where it belongs — into the recipe's `Attribution` field, a few
// hundred lines down. So there is one identity, it is obviously a robot, and it
// owns whatever this script creates.
const HARNESS_EMAIL = process.env.CORPUS_HARNESS_EMAIL || 'corpus-harness@secretsauce.local';
const HARNESS_NAME = 'Corpus Import Harness';

// And it may only ever point at a local stack. A schema-gap harness that types
// into the real editor has no business writing to a database anyone else reads:
// the 158 recipes it left behind were a byproduct of measuring the editor, not
// content, and on a shared database they are indistinguishable from content.
// `.invalid`/`localhost` checks are cheap; an accidental hosted run is not
// reversible on the free tier.
{
  const host = new URL(BASE).hostname;
  if (!['localhost', '127.0.0.1', '::1', '0.0.0.0'].includes(host)) {
    console.error(
      [
        'APP_URL points at "' + host + '", which is not a local stack.',
        '',
        'ingest.mjs types scraped recipes into the real editor and saves them. It',
        'is a schema-gap harness, not an importer — the rows it creates carry no',
        'provenance and cannot be told apart from real content afterwards (B114).',
        'The supported path from corpus/ to a database is `melos run',
        'corpus:import:gen`, which writes is_imported rows with their source URL',
        'attached.',
        '',
        'Run it against http://localhost:<port> or not at all.',
      ].join('\n'),
    );
    process.exit(2);
  }
}
// Never a literal (B018, and now B111). This script signs into the app as each
// chef account it creates, so a hard-coded value here is a working credential
// for every account it has ever made — and `ingest.mjs` drives whatever
// `APP_URL` points at, which is not necessarily a local stack. It is read from
// the environment with **no default**, so the failure is a refusal to start
// rather than a quiet fallback to a known string.
const PASSWORD = process.env.CORPUS_CHEF_PASSWORD;
if (!PASSWORD) {
  console.error(
    [
      'CORPUS_CHEF_PASSWORD is not set. This script creates and signs into chef',
      'accounts, so the password cannot have a default — a default is a',
      'credential in the repository (B018). Set it in the shell for this run:',
      '  $env:CORPUS_CHEF_PASSWORD = "<a fresh random string>"',
    ].join('\n'),
  );
  process.exit(1);
}
const STATE = resolve(ROOT, '_state/ingest.json');

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

// ---------------------------------------------------------------- page helpers

/**
 * Flutter injects the accessibility placeholder after the page `load` event, so
 * its presence is the real "app has booted" signal. Waiting for it matters beyond
 * semantics: reloading while flutter_bootstrap.js is still fetching aborts the
 * boot and the app then never initialises at all.
 */
async function waitForBoot(page) {
  await page.waitForFunction(
    () => !!document.querySelector('flt-semantics-placeholder') || !!document.querySelector('flt-semantics'),
    null,
    { timeout: 30000 },
  );
}

/**
 * Clicking the placeholder removes it — Flutter swaps it for the live `flt-semantics`
 * tree. Every later route change in this app is a hash change on the *same* document,
 * so the placeholder never comes back and waiting for it again hangs forever. Check
 * for the enabled tree first.
 */
async function enableSemantics(page) {
  await waitForBoot(page);
  const already = await page.evaluate(() => !!document.querySelector('flt-semantics'));
  if (already) {
    await page.waitForTimeout(300);
    return;
  }
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder').click());
  await page.waitForTimeout(300);
}

async function goto(page, route) {
  await page.goto(BASE + '/#' + route);
  await enableSemantics(page);
}

/** Wheel the canvas. The page itself never scrolls; Flutter owns it. */
async function wheel(page, deltaY) {
  await page.evaluate((dy) => {
    const t = document.querySelector('flt-glass-pane') || document.body;
    t.dispatchEvent(
      new WheelEvent('wheel', { deltaY: dy, bubbles: true, cancelable: true, clientX: 400, clientY: 450 }),
    );
  }, deltaY);
  await page.waitForTimeout(90);
}

/**
 * Bring a locator into existence. Scrolls back to the top, then walks down until
 * the node appears in the semantics tree. Returns the locator, or throws with the
 * name so a failure says which control went missing.
 */
async function find(page, locator, label, maxSteps = 30) {
  // Existing is not the same as actionable: an off-screen semantics node is
  // present in the tree but has no box, so clicking or typing into it hangs
  // until the action timeout. Visibility is the condition that matters.
  const shown = async () => {
    try {
      if ((await locator.count()) === 0) return false;
      const box = await locator.boundingBox();
      return !!box && box.height > 0;
    } catch {
      return false;
    }
  };
  if (await shown()) return locator;

  // The form is filled top to bottom, so the next control is nearly always just
  // below the fold. Search downwards first, and only then rewind to the top.
  for (let i = 0; i < maxSteps; i++) {
    await wheel(page, 380);
    if (await shown()) return locator;
  }
  for (let i = 0; i < 14; i++) await wheel(page, -900);
  for (let i = 0; i < maxSteps * 2; i++) {
    if (await shown()) return locator;
    await wheel(page, 380);
  }
  const present = await page.evaluate(() => {
    const labels = [...document.querySelectorAll('[aria-label]')].map(
      (e) => e.tagName + ':' + e.getAttribute('aria-label'),
    );
    const buttons = [...document.querySelectorAll('[role="button"]')].map((e) =>
      (e.textContent || '').trim().slice(0, 28),
    );
    return { labels, buttons };
  });
  throw new Error(
    'control not found after scrolling: ' + label +
    '\n    labelled: ' + JSON.stringify(present.labels) +
    '\n    buttons:  ' + JSON.stringify(present.buttons),
  );
}

/**
 * Type into a Flutter text field, then read it back and retry until it matches.
 *
 * Two problems make the naive version wrong, and both corrupt data quietly:
 * `fill()` never reaches the framework at all, and typing immediately after a
 * click loses the leading characters — Flutter attaches its hidden input a beat
 * after focus, so "tsp" arrives as "sp". Verifying the field afterwards is what
 * keeps harness noise out of the round-trip diff: a mistyped field would
 * otherwise be indistinguishable from the app losing data.
 */
async function typeInto(page, locator, label, value) {
  if (value == null || value === '') return;
  const want = String(value);
  let lastGot = null;

  for (let attempt = 0; attempt < 4; attempt++) {
    // Re-find every attempt. Flutter only builds semantics for on-screen widgets,
    // so a node located a moment ago can be gone by the time focus is attempted —
    // and a locator that resolves to nothing makes every later call a silent
    // no-op, which looks identical to a field that refuses input.
    const el = await find(page, locator, label);

    // focus(), not click(). Playwright's click hit-tests the point it is aiming
    // at, and Flutter's semantics nodes overlap enough that the test keeps
    // failing until the action times out. Worse, focusing a field makes Flutter
    // scroll it into view, so a click aimed before that scroll lands on a
    // neighbour and the keystrokes overwrite whatever that neighbour held — a
    // description silently replaced by an ingredient quantity. The semantics node
    // is a real <input>/<textarea>, so focusing it directly is both safe and exact.
    const isFocused = () =>
      el.evaluate((e) => e === document.activeElement).catch(() => false);

    // Escalate: a plain focus() is enough for most fields, but a field inside a
    // panel that has just expanded ignores it until the panel settles, and then
    // only a real click gets there. Each rung is tried in turn and confirmed.
    await el.evaluate((e) => e.focus()).catch(() => {});
    await page.waitForTimeout(120);
    if (!(await isFocused())) {
      await el.evaluate((e) => e.click()).catch(() => {});
      await page.waitForTimeout(200);
    }
    if (!(await isFocused())) {
      await el.click({ force: true, timeout: 5000 }).catch(() => {});
      await page.waitForTimeout(250);
    }
    if (!(await isFocused())) continue;

    await page.keyboard.press('ControlOrMeta+a');
    await page.keyboard.press('Delete');
    await page.waitForTimeout(40);
    // Real key events, not insertText: Flutter reads its hidden input the same
    // way it ignores fill(), so synthesised value changes do not reach the widget.
    await page.keyboard.type(want);
    await page.waitForTimeout(60);

    let got = null;
    try {
      got = await el.inputValue();
    } catch {
      return; // not a real <input>; nothing to verify against
    }
    if (got === want) return;
    lastGot = got;
  }
  throw new Error(
    'field never accepted its value: ' + label +
    '\n    want: ' + JSON.stringify(want) +
    '\n    got:  ' + JSON.stringify(lastGot),
  );
}

/**
 * Click through the DOM rather than through the mouse, for the same reason
 * typeInto focuses rather than clicks: Flutter listens for `click` on its
 * semantics elements, and dispatching it directly skips the hit-testing that
 * overlapping semantics nodes defeat.
 */
async function clickBtn(page, locator, label) {
  const el = await find(page, locator, label);
  let lastGot = null;
  await page.waitForTimeout(120);
  await el.evaluate((e) => e.click());
  await page.waitForTimeout(180);
}

// ---------------------------------------------------------------------- auth

async function signOutIfNeeded(page) {
  await page.goto(BASE + '/#/discover');
  await waitForBoot(page);
  await page.evaluate(() => {
    // Supabase persists the session in localStorage; clearing it is the fastest
    // reliable sign-out and does not depend on the profile menu's markup.
    for (const k of Object.keys(localStorage)) if (k.includes('auth-token')) localStorage.removeItem(k);
  });
  await page.reload();
  await waitForBoot(page);
}

/**
 * Load a route in a genuinely fresh document. Plain goto between two routes is a
 * hash change on the same document, which keeps the previous screen's form state —
 * typing then appends to whatever was already there.
 */
async function hardGoto(page, route) {
  await page.goto(BASE + '/#' + route);
  await page.reload();
  await enableSemantics(page);
}

/**
 * The auth screen carries a submit button and a mode-toggle button whose labels
 * overlap: "Sign in" and "Already have an account? Sign in". getByRole matches on
 * substring by default, so the non-exact locator resolves to the toggle and the
 * form is never submitted. Every auth button here is matched exactly.
 */
async function signUpOrIn(page) {
  await signOutIfNeeded(page);
  const email = HARNESS_EMAIL;

  // Sign in first: on a re-run most chefs already exist, and a failed signup
  // leaves an error banner that complicates the fallback.
  await hardGoto(page, '/auth');
  await typeInto(page, page.getByRole('textbox', { name: /^Email/ }), 'Email', email);
  await typeInto(page, page.getByRole('textbox', { name: /^Password/ }), 'Password', PASSWORD);
  await clickBtn(page, page.getByRole('button', { name: 'Sign in', exact: true }), 'Sign in');
  await page.waitForTimeout(2000);
  if (page.url().includes('/discover')) return { email, created: false };

  await hardGoto(page, '/auth?mode=signup');
  await typeInto(page, page.getByRole('textbox', { name: /^Display name/ }), 'Display name', HARNESS_NAME);
  await typeInto(page, page.getByRole('textbox', { name: /^Email/ }), 'Email', email);
  await typeInto(page, page.getByRole('textbox', { name: /^Password/ }), 'Password', PASSWORD);
  await clickBtn(page, page.getByRole('button', { name: 'Sign up', exact: true }), 'Sign up');
  await page.waitForTimeout(2500);
  if (!page.url().includes('/discover')) throw new Error('sign-up and sign-in both failed for ' + email);
  return { email, created: true };
}

// -------------------------------------------------------------------- editor

/**
 * Fill the editor from one corpus recipe and save.
 *
 * Deliberately literal: values go where the app models them and nowhere else.
 * A yield of "Serves 4-6" contributes 4 to `Servings` and the "-6" is NOT smuggled
 * into the description, and a "8-12" quantity enters as 8 with the range dropped.
 * Folding those into free text would hide exactly the gaps this run exists to find,
 * so the loss is left for the round-trip diff to report.
 */
async function addRecipe(page, recipe) {
  await hardGoto(page, '/recipe/new');
  const notes = [];

  await typeInto(page, page.getByRole('textbox', { name: /^Title/ }), 'Title', recipe.title);
  await typeInto(page, page.getByRole('textbox', { name: /^Short description/ }), 'Short description', recipe.description);
  await typeInto(page, page.getByRole('textbox', { name: /^Prep \(min\)/ }), 'Prep (min)', recipe.timing.prepMinutes);
  await typeInto(page, page.getByRole('textbox', { name: /^Cook \(min\)/ }), 'Cook (min)', recipe.timing.cookMinutes);
  await typeInto(page, page.getByRole('textbox', { name: /^Servings/ }), 'Servings', recipe.yield.servings);
  await typeInto(page, page.getByRole('textbox', { name: /^Cuisine/ }), 'Cuisine', recipe.cuisine[0] || null);

  // Category only became fillable once F001 was fixed — before that the editor had
  // no control for it and all 158 recipes lost their category on save. Skipped
  // silently against an older build so the harness still runs there.
  const categoryField = page.getByRole('textbox', { name: /^Category/ });
  if (recipe.category.length && (await categoryField.count())) {
    await typeInto(page, categoryField, 'Category', recipe.category[0]);
  } else if (recipe.category.length) {
    notes.push('category-no-field: ' + recipe.category.join(', '));
  }

  const attribution = [recipe.chefName, recipe.source.publisher, recipe.source.sourceUrl]
    .filter(Boolean)
    .join(' · ');
  await typeInto(page, page.getByRole('textbox', { name: /^Attribution/ }), 'Attribution', attribution);

  // Public, so the recipe is reachable from Discover and by the round-trip read.
  const pub = await find(page, page.getByRole('switch'), 'Public switch');
  if ((await pub.getAttribute('aria-checked')) !== 'true') await pub.click();

  // -- ingredients ----------------------------------------------------------
  const groups = recipe.ingredientGroups;
  let row = 0;
  let expanded = 0;
  for (let g = 0; g < groups.length; g++) {
    if (g > 0) {
      await clickBtn(page, page.getByRole('button', { name: 'Add ingredient group', exact: true }), 'Add ingredient group');
    }
    const group = groups[g];
    if (group.name) {
      await typeInto(
        page,
        page.getByRole('textbox', { name: /^Group name/ }).nth(g),
        'Group name ' + g,
        group.name,
      );
    }

    for (let j = 0; j < group.items.length; j++) {
      if (j > 0) {
        await clickBtn(page, page.getByRole('button', { name: 'Add ingredient', exact: true }).nth(g), 'Add ingredient g' + g);
      }
      const item = group.items[j];

      if (item.quantity != null) {
        await typeInto(page, page.getByRole('textbox', { name: /^Qty/ }).nth(row), 'Qty ' + row, item.quantity);
        if (item.quantityText && /[-–—]|to|or/.test(item.quantityText)) {
          notes.push('range-quantity-truncated: "' + item.quantityText + '" -> ' + item.quantity);
        }
      } else if (item.quantityText) {
        notes.push('quantity-unparsed-dropped: "' + item.quantityText + '"');
      }
      await typeInto(page, page.getByRole('textbox', { name: /^Unit/ }).nth(row), 'Unit ' + row, item.unit);
      await typeInto(page, page.getByRole('textbox', { name: /^Name/ }).nth(row), 'Name ' + row, item.name);

      if (item.note || item.isOptional) {
        await clickBtn(page, page.getByRole('button', { name: 'Note & optional', exact: true }).nth(row), 'Note toggle ' + row);
        // Expanding a row adds exactly one Note field and one Optional checkbox,
        // in row order. Index by how many rows have been expanded so far — .last()
        // can resolve to an already-expanded row further up the form, which is
        // off-screen and never becomes actionable.
        if (item.note) {
          // The note field's accessible name is "Note\ne.g. finely chopped" — the
          // label plus its helper text — so an exact match on "Note" finds nothing.
          await typeInto(page, page.getByRole('textbox', { name: /^Note/ }).nth(expanded), 'Note ' + row, item.note);
        }
        if (item.isOptional) {
          await clickBtn(page, page.getByRole('checkbox').nth(expanded), 'Optional ' + row);
        }
        expanded++;
      }
      row++;
    }
  }

  // -- steps ----------------------------------------------------------------
  // Steps are grouped into sections exactly like ingredients are grouped, and the
  // app has one Section field per *section* — not per step. Indexing the section
  // field by step number worked only while every corpus recipe had a single
  // unnamed section, which is every BBC recipe; the first recipes with real
  // sections all failed on "Section 1" not existing.
  const stepGroups = [];
  for (const step of recipe.steps) {
    const name = step.stepGroup || null;
    const last = stepGroups[stepGroups.length - 1];
    if (last && last.name === name) last.steps.push(step);
    else stepGroups.push({ name, steps: [step] });
  }

  let stepRow = 0;
  for (let g = 0; g < stepGroups.length; g++) {
    if (g > 0) {
      await clickBtn(page, page.getByRole('button', { name: 'Add section', exact: true }), 'Add section ' + g);
    }
    const group = stepGroups[g];
    if (group.name) {
      await typeInto(
        page,
        page.getByRole('textbox', { name: /^Section name/ }).nth(g),
        'Section name ' + g,
        group.name,
      );
    }

    for (let j = 0; j < group.steps.length; j++) {
      if (j > 0) {
        await clickBtn(page, page.getByRole('button', { name: 'Add step', exact: true }).nth(g), 'Add step g' + g);
      }
      const step = group.steps[j];
      await typeInto(page, page.getByRole('textbox', { name: /^Step$/ }).nth(stepRow), 'Step ' + stepRow, step.text);
      if (step.subSteps.length) {
        notes.push('substeps-dropped: step ' + (stepRow + 1) + ' had ' + step.subSteps.length);
      }
      if (step.utensils.length) notes.push('utensils-dropped: step ' + (stepRow + 1));
      stepRow++;
    }
  }

  // -- things with nowhere to go -------------------------------------------
  if (recipe.keywords.length) notes.push('keywords-no-field: ' + recipe.keywords.length);
  if (recipe.notes.chefTips.length) notes.push('recipe-level-tip-no-field: ' + recipe.notes.chefTips.length);
  if (recipe.equipment.length) notes.push('equipment-no-field: ' + recipe.equipment.length);
  const yieldQualifier = recipe.yield.raw.find((y) => !/^\d+$/.test(y));
  if (yieldQualifier) notes.push('yield-qualifier-dropped: "' + yieldQualifier + '"');

  await clickBtn(page, page.getByRole('button', { name: 'Save', exact: true }), 'Save');

  // Wait for the save to actually land, rather than for a fixed interval. A large
  // recipe takes minutes to write, and a fixed wait caused two failures at once:
  // the run recorded a successful save as NOSAVE because the id was not in the URL
  // yet, and the app's late navigation to /recipe/<id> then overwrote the *next*
  // recipe's /recipe/new, so that one failed with "Title not found" while looking
  // at the previous recipe's detail page.
  const savedRe = /#\/recipe\/([0-9a-f-]{36})/i;
  await page
    .waitForFunction(() => /#\/recipe\/[0-9a-f-]{36}/i.test(window.location.href), null, {
      timeout: 180000,
    })
    .catch(() => {});
  await page.waitForTimeout(500);

  const url = page.url();
  const m = url.match(savedRe);
  return { savedUrl: url, recipeId: m ? m[1] : null, notes };
}

// ----------------------------------------------------------------------- main

async function main() {
  const argv = process.argv.slice(2);
  const arg = (n, d) => {
    const i = argv.indexOf(n);
    return i >= 0 ? argv[i + 1] : d;
  };
  const onlyChef = arg('--chef', null);
  const limit = Number(arg('--limit', '9999'));
  const headed = argv.includes('--headed');

  const chefIndex = await readJson(resolve(ROOT, 'chefs.json'), { chefs: [] });
  const progress = await readJson(resolve(ROOT, '_state/progress.json'), { chefs: {} });
  const state = await readJson(STATE, { chefs: {} });

  const chefs = chefIndex.chefs.filter((c) => !onlyChef || c.slug === onlyChef);
  const browser = await chromium.launch({ headless: !headed });
  // A tall viewport is the fix for positional addressing. Flutter only builds
  // semantics for on-screen widgets, so .nth(6) over ingredient rows indexes the
  // built subset, not the real one, and silently targets the wrong row once the
  // form outgrows the window. Give the whole form room and nothing is culled.
  const page = await browser.newPage({ viewport: { width: 1400, height: 6000 } });
  page.setDefaultTimeout(45000);

  for (const chef of chefs) {
    const cs = (state.chefs[chef.slug] = state.chefs[chef.slug] || { account: null, recipes: {} });
    console.log('\n=== ' + chef.name + ' (' + chef.slug + ')');

    try {
      cs.account = await signUpOrIn(page);
      console.log('  account ' + cs.account.email + (cs.account.created ? ' (created)' : ' (existing)'));
    } catch (e) {
      console.log('  ACCOUNT FAIL ' + e.stack);
      await writeJson(STATE, state);
      continue;
    }

    const files = (progress.chefs[chef.slug] || { scraped: [] }).scraped.slice(0, limit);
    for (const entry of files) {
      if (cs.recipes[entry.file] && cs.recipes[entry.file].recipeId) {
        console.log('  skip  ' + entry.file);
        continue;
      }
      const recipe = await readJson(resolve(ROOT, 'recipes', entry.file), null);
      if (!recipe) continue;

      const started = Date.now();
      try {
        const out = await addRecipe(page, recipe);
        const secs = ((Date.now() - started) / 1000).toFixed(0);
        cs.recipes[entry.file] = { ...out, at: new Date().toISOString(), seconds: Number(secs) };
        console.log(
          (out.recipeId ? '  ok    ' : '  NOSAVE ') + entry.file + '  ' + secs + 's' +
          (out.recipeId ? '  ' + out.recipeId : '  url=' + out.savedUrl),
        );
      } catch (e) {
        cs.recipes[entry.file] = { error: e.message, at: new Date().toISOString() };
        console.log('  FAIL  ' + entry.file + '  ' + e.message);
      }
      await writeJson(STATE, state);
    }
  }

  await browser.close();
  const done = Object.values(state.chefs).reduce(
    (a, c) => a + Object.values(c.recipes).filter((r) => r.recipeId).length,
    0,
  );
  console.log('\ningested ' + done + ' recipes');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}
