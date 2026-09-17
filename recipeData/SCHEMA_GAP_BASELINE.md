# Schema gap baseline — recipe corpus ingestion

**Phase 0 recon. Written before any scraping, and before any code.**
Date: 2026-09-10 · Method: read the SQL schema, the `core` models, and the recipe-editor UI.

This is the **hypothesis list**. Every row is a prediction about what the app will do to a
real-world recipe. Phase 2's round-trip diff either confirms or refutes each one, and the
refutations matter as much as the confirmations.

Sources read: [0001_init.sql](../supabase/migrations/0001_init.sql) ·
[schema.json](schema.json) · `packages/core/lib/src/models/` ·
`apps/app/lib/features/recipe_editor/` · [auth_screen.dart](../apps/app/lib/features/auth/auth_screen.dart)

---

## 1. The chef entity is not a chef table

There is no `chefs` table. **A chef is a `profiles` row**, and `profiles.id` is a foreign key to
`auth.users.id`. This has three consequences that shape the whole ingestion plan:

- **Creating a chef means creating a real auth account** — email, password, display name. There is
  no way to write a `profiles` row without one; the row is created by the `handle_new_user` trigger
  on `auth.users` insert, reading `display_name` out of the signup metadata.
- **`display_name` is not unique.** `ProfileRepository.searchByName` returns a *list*, and the
  comment says why: an exact-match lookup "silently picked one of the Daras". So "look up the chef,
  create only if absent" **cannot key on the chef's name**.

  > **The proposal this bullet used to make was the wrong answer, and it shipped (B114).** It was a
  > deterministic `<chefSlug>@corpus.invalid` account per chef, "safe by construction" for re-runs.
  > It *was* idempotent — and it also gave 15 real named people log-in-able `kind = 'member'`
  > profiles on the chef leaderboard, owning 158 provenance-less recipes credited as their own
  > work. The mistake was treating "a chef needs a stable key" as "a chef needs an account".
  >
  > Phase 35b is the real answer: a captured byline is a `kind = 'imported'` profile with
  > `auth_user_id` null, keyed by its source, holding no credential and ranked nowhere. The harness
  > signs in as **one** obviously-robotic identity and the chef's name goes into `attribution`.
  > Nothing here needs an address derived from a real person's name.
- **A chef carries almost no data**: `display_name` (≤80, silently clamped by the trigger),
  `avatar_url`, `bio` (≤500). That is the entire writable set. No website, no social handles, no
  restaurant, no credentials, no specialty. Everything else on a profile
  (`chef_score`, `chef_tier`, counters) is server-owned and recomputed by trigger.

The ground rule "never invent a chef to satisfy the constraint" is therefore satisfiable, but the
cost is one real account per chef. 10 chefs = 10 signups; 100 chefs = 100 accounts.

## 2. Source concept → app field

Legend: **yes** = round-trips intact · **partial** = lands somewhere lossy · **no** = nowhere to put it

### Recipe level

| Source concept | App field | Supported? | Note |
|---|---|---|---|
| title | `recipes.title` | yes | ≤200 chars |
| description | `recipes.description` | yes | ≤10000 chars |
| chefId | `recipes.owner_id` → `profiles.id` | partial | needs a real auth account (§1) |
| **sourceUrl** | `recipes.attribution` | **partial** | no dedicated column; free text ≤2000, shares the field with the cook's story; not machine-readable |
| **retrievedAt** | — | **no** | no column anywhere |
| **license / attribution** | `recipes.attribution` | **partial** | same single field as sourceUrl — three concepts, one text box |
| yield / servings | `recipes.servings` | partial | `int` only. "makes 12 muffins", "one 9-inch tart", "serves 4–6" have no home; repo convention pushes them into `description` |
| prep time | `recipes.prep_minutes` | yes | int minutes |
| cook time | `recipes.cook_minutes` | yes | int minutes |
| **total time** | — | **partial** | derived as prep+cook. A source total that includes resting/marinating cannot round-trip; convention puts unattended time on a step's `duration_minutes` |
| difficulty | `recipes.difficulty` | partial | enum `easy \| medium \| hard`. Sources with no difficulty, or a 5-point scale, get bucketed |
| cuisine | `recipes.cuisine` | yes | free text ≤80 |
| **course / category** | `recipes.category` | **no — data loss** | column exists; **the editor has no input for it**. See §4 |
| **tags / keywords** | `tags` + `recipe_tags` | **no** | both tables exist in the schema; **zero application code touches them** |
| **make-ahead notes** | — | **no** | no column |
| **storage** | — | **no** | no column |
| **substitutions** | — | **no** | no column |
| **variations** | — | **no** | no column |
| chef's tips (recipe level) | `steps.tip` | partial | per-step only; a recipe-level tip must be attached to some step or folded into `description` |
| nutrition | `recipes.nutrition` jsonb | partial | fixed 11-key FDA set + `source`. Per serving only. No micronutrients, no per-100g, no ranges |
| media URLs | `recipes.cover_image_url`, `steps.image_url` | partial | exactly one cover + one photo per step. No gallery, no video |
| **unmappedFields** | — | **no** | nothing in the app can hold it; it exists only in the corpus JSON |

### Ingredient level

| Source concept | App field | Supported? | Note |
|---|---|---|---|
| **raw verbatim line** | — | **no** | the app stores only the parsed parts. The fidelity anchor the task requires has no column |
| quantity | `ingredients.quantity` | partial | `numeric`, DB check `> 0 or null`. Single decimal — no ranges ("2–3"), no fraction strings, no "to taste" carrying a number |
| unit | `ingredients.unit` | yes | free text |
| item | `ingredients.name` | yes | |
| prep note | `ingredients.note` | yes | |
| optional | `ingredients.is_optional` | yes | boolean |
| ingredientGroup | `ingredient_groups.name` | yes | ordered by `sort_order` |
| (bonus) food link | `ingredients.food_id` | n/a | FK into the food registry; editor typeahead. **Registry is currently empty on both DBs** |

### Step level

| Source concept | App field | Supported? | Note |
|---|---|---|---|
| text | `steps.text` | yes | |
| duration | `steps.duration_minutes` | yes | int minutes |
| temperature | `steps.temperature` | yes | free text, e.g. `180°C` |
| tip | `steps.tip` | yes | rendered as an aside |
| photo | `steps.image_url` | yes | one per step |
| **subSteps[]** | — | **no** | steps are flat. No parent/child column, no nesting |
| **utensils[]** | — | **no** | no column, no table |
| **ingredientRefs[]** | — | **no** | deliberately absent. Cook mode *derives* the "you'll need" list by word-matching ingredient names against step prose; CLAUDE.md explicitly says not to promote it without a real `step_ingredients` table |
| **technique** | — | **no** | no column |

### Equipment

| Source concept | App field | Supported? | Note |
|---|---|---|---|
| **equipment / utensils list** | — | **no** | no table, no column, at neither recipe nor step level |

---

## 3. Constraints that will clip real recipes

Enforced in Postgres (a violation is a failed save, not a warning):

- `recipes_text_lengths`: title ≤200, description ≤10000, attribution ≤2000, cuisine ≤80,
  category ≤80, cover_image_url ≤2048
- `ingredients_quantity_positive`: `quantity is null or quantity > 0`
- `profiles_text_lengths`: display_name ≤80, bio ≤500 (display_name is *clamped* at signup, not rejected)
- `difficulty` enum: `easy | medium | hard`
- `recipe_visibility` enum: `public | private`

Enforced only by the repo's own validator (`tool/recipe_format.dart`) and **not** by the database —
so the app will accept values the corpus tooling would reject: servings 1–100, prep/cook 0–1440,
step duration 1–2880.

## 4. Bug already confirmed during recon — before any scraping

**`recipes.category` is silently destroyed by every save through the editor.**

- The column exists and `save_recipe` writes it: `category = p_payload->>'category'`.
- `_writablePayload` sends `'category': recipe.category`.
- **The editor never reads it and never sets it.** There is no `_category` controller in
  `recipe_editor_screen.dart`; `_load()` does not restore it; the `Recipe` built in `_save` omits
  it, so it defaults to `null`.
- Net effect: open any categorized recipe in the editor, save, and its category becomes `null`.
  No error, no warning.
- **All 14 authored recipes carry a category** (7 Main, 3 Dessert, 1 each Salad / Drink /
  Breakfast / Appetizer), so every one of them is affected.

This is the B035 / Gotcha 20 failure mode — "a field the draft types drop is a field the next save
deletes" — but one level up: the miss is on the top-level `Recipe`, not on `edit_models.dart`, so
the existing round-trip test in `recipe_editor_test.dart` does not catch it.

Severity: **data-loss**. Fix is UI (add the field) plus a regression test. To be written up properly
in Phase 3; flagged here because it was found before Phase 1 began.

## 5. Clean DB reset — confirmed working

`melos run db:*` **does not work on this machine** (B033: no `psql` on PATH). The procedure
verified in this session, against the local container:

```bash
docker cp supabase/scripts/drop.sql supabase_db_secret-sauce:/tmp/drop.sql
MSYS_NO_PATHCONV=1 docker exec supabase_db_secret-sauce \
  psql -U postgres -d postgres -v ON_ERROR_STOP=1 -1 -f /tmp/drop.sql
# then: drop schema sim cascade; delete from auth.users;  (storage.objects rejects direct DELETE)
# then re-apply supabase/migrations/0001_init.sql
```

Current state of both databases: **completely empty** — 0 accounts, 0 recipes, 0 foods.
Schema verified sound by `rls_matrix.sql` (137/137) on local and hosted.

Two cautions for corpus runs:

- **Do not run `melos run db:reset`** — it is drop → create → nutrition → seed → recipes → sim, and
  would repopulate the very fixtures a clean corpus run is trying to exclude.
- The food registry is empty, so the ingredient typeahead offers nothing and `food_id` will be null
  on every ingested ingredient. That is a *known* null, not a finding.

## 6. E2E auth — confirmed working

- Route `/auth`, with `?mode=signup` opening the sign-up side.
- Three fields: **Display name**, **Email**, **Password**.
- Local stack has **no `[auth.email]` section** in `config.toml`, so email confirmation is **off**:
  `POST /auth/v1/signup` returns an `access_token` immediately. Verified end to end this session —
  account created, session issued, `handle_new_user` fired, profile row written with
  `chef_tier = home_cook`.
- Mailpit (`http://127.0.0.1:54624`) is therefore **not** in the loop locally.
- Redirects: `/my`, `/profile`, `/recipe/new`, `*/edit` bounce to `/auth` when signed out. That is
  UX only — RLS is the real gate.

## 7. Phase 2 feasibility — VERIFIED WORKING

**Flutter web exposes no DOM until semantics are switched on.** A fresh page snapshot contains
exactly one node: `button "Enable accessibility"` — zero textboxes, zero links, zero headings.

This was the gate on Phase 1, and it has been **tested end to end and passes**. The working
sequence, verified 2026-09-10 against a release build served statically on a fresh port:

1. `flutter build web --release --dart-define-from-file=env.local.json`, then `npx serve -l <port> build/web`
2. Navigate to `http://localhost:<port>/#/<route>` — deep links are hashed
3. **Enable semantics via JS, not a click.** Flutter parks the placeholder outside the viewport, so
   Playwright's real click times out with `element is outside of the viewport`. This works:
   ```js
   document.querySelector('flt-semantics-placeholder').click()
   ```
4. Snapshot — the full labelled tree appears

Proven this way, in one pass: signed up a fresh account through `/auth?mode=signup`
(`textbox "Display name"`, `"Email"`, `"Password"`, `button "Sign up"`), landed on `/discover`, then
opened `/recipe/new` and read back every editor control as a labelled node —
`Title`, `Short description`, `Prep (min)`, `Cook (min)`, `Servings`, `Difficulty Easy`, `Cuisine`,
`switch "Public …"`, `Attribution / story (optional)`, the `Nutrition facts` group, and the
`Ingredients` group down to `Group name (optional)` / `Qty` / `Unit` / `Name` /
`Note & optional` / `Remove ingredient`.

So Playwright drives this app by role and label, exactly as it would a DOM app. No fallback to
`integration_test` + `flutter drive` is needed.

**Bonus confirmation of §4:** that live editor snapshot goes `Cuisine` → `Public` switch →
`Attribution`. There is **no Category control anywhere in the form** — the data-loss finding is now
confirmed in the running UI, not only in the source.

Still unverified: the Steps sub-editor was below the captured fold, and the dynamic
add/remove controls (`Add ingredient`, `Add ingredient group`, `Add step`, `Add section`) have not
been exercised. Those are the first thing Phase 1 should prove, since a corpus recipe needs ~10 of
each.

Two further constraints already documented in CLAUDE.md:

- The debug web server renders for **one client only** (B028) — a second page load is blank. Builds
  must be `flutter build web --release` and served statically.
- After a rebuild, serve on a **new port**, or the browser's HTTP cache serves the previous build.

Scale note: 10 chefs × 10 recipes, at roughly 10 ingredients and 10 steps each, is on the order of
**2,000+ individual field interactions** through a canvas-rendered UI. Worth a measured timing on
the first recipe before committing to the full batch.

## 8. Corpus layout vs. the existing `recipeData/` contract — checked, safe

`recipeData/recipes/` is not a free directory: `tool/recipes.dart` validates it and generates
`supabase/seed_recipes.sql` from it, and **CI runs `melos run recipes:check`** (ci.yml:54) which
fails on a stale file. Writing a 100-recipe corpus into that tree could plausibly have broken CI or,
worse, silently promoted scraped recipes into the seeded content of every database.

Checked: `_load()` in `tool/recipe_format.dart` uses `directory.listSync()` **without**
`recursive: true`, then `.whereType<File>()`. Subdirectories are ignored, not walked.

So the layout the task specifies is safe as written:

- `recipeData/recipes/<chefSlug>/<recipeSlug>.json` — invisible to the validator and the generator
- `recipeData/chefs.json`, `_state/`, `_reports/` — sit outside `recipes/`, also ignored

Two consequences to hold onto:

- **The corpus gets no validation from the existing tooling.** `melos run recipes:validate` will
  keep reporting "14 recipes valid" no matter how large the corpus grows. Corpus validation has to
  be its own thing.
- **This is one line away from breaking.** Anyone adding `recursive: true` to that loader would turn
  every scraped recipe into seeded content owned by the Secret Sauce Kitchen account. Worth a
  comment at the call site and a line in `recipeData/README.md` before the corpus lands.
