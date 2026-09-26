# UI/UX Audit — 2026-09-24

Phase 1 of the `ui-overhaul` skill (`.claude/skills/ui-overhaul/`). Read-only against code. Phase 2
(design system) reads this file; Phase 3 (reference rebuild) must keep everything under **Preserve**.

**Evaluation mode:** **live**. Two static release web builds (light, plus dark pinned then reverted —
`git diff apps/app/lib/main.dart` empty) served locally and captured with headless Chromium, plus a
static code sweep by three parallel reviewers. Every Critical and most Major findings were checked
again by hand against the source or the database.
**Signed-in surfaces (addendum, same day):** captured live with the local test account (credentials
in the git-ignored `env.test-account.local.json`). The account signs in through GoTrue's password
grant, and the session is injected into localStorage (`sb-127-auth-token`) before the app boots.
Owner views needed a recipe the account owns, so one curated recipe was forked through the real
`fork_recipe` RPC, captured, and **deleted afterwards** (0 rows left). Still code-only: the share
dialog and the version sheet (coordinate clicks on a canvas were not attempted).
2.0× text scale cannot be set from the browser; the widget-test envelope
suites stand in for it: `melos run test --no-select` → **SUCCESS** (core 167, design_system 172,
app 494 — all passed, 2026-09-24).
**Build / data:** commit `d32de8d`, local stack (`127.0.0.1:54621`): 14 curated recipes (**none has
a cover photo**), 21,314 imported corpus recipes, 1 member profile (Secret Sauce Kitchen), 1,279
imported profiles, **zero** likes, saves or ratings. So the chefs board and every engagement number
are empty *by design* (B113), and those surfaces are scored on their empty states.
**Captures:** `.playwright-mcp/captures/audit-2026-09-24/` (git-ignored). Light: 25 at
390/600/1000/1440. Dark: 10 at 390/1440.

## Scores

Calibration: 1–3 broken · 4–5 functional but templated · 6 decent, unremarkable · 7 solid junior ·
8 professional with rough edges · 9 senior, polished · 10 ship-grade and distinctive.

| # | Dimension | Score | Weight | Evidence (short) |
| --- | --- | --- | --- | --- |
| 1 | Recipe legibility | **6** | 2 | Quantity gutter, per-group numbering, check-off, scaled quantities all work well (recipe-tikka-*). Against that: step photos are never shown (UX-001), quantities print as decimals (UX-023), temperature/time are 11px in cook mode (UX-024), long units collide with names (UX-030) |
| 2 | Typography hierarchy | **4** | 1 | No `textTheme` and no font, so stock Roboto. 83 `FontWeight` overrides and 166 style `copyWith`s; w800 is the most common weight. 7 `TODO(fonts)` |
| 3 | Color system | **5** | 1 | Seed scheme is used well, but there is no `ThemeExtension`. The difficulty badge fails AA (2.3–2.8:1), rating stars are 1.9:1, and 58 raw color lines sit outside the theme |
| 4 | Spacing & layout rhythm | **6** | 1 | `AppSpacing` is used 485×, but 12/10/14/6 act as an unofficial second scale (~77 raw values). Wide screens leave dead space (chefs-1440, entity-1440) |
| 5 | Shape & depth | **5** | 0.5 | The border-not-shadow policy is good. There are 12 distinct raw radii, and button shapes are mixed within one row (UX-033) |
| 6 | Component consistency | **4** | 1 | 6 segmented/tab controls, 3 rank pills, 6 hand-rolled kickers, 2 Load-more buttons, 2 avatars (UX-032) |
| 7 | Responsive & envelope | **7** | 1.5 | No overflow in any capture at 390/600/1000/1440, and the envelope suites are broad. But the deep-linked desktop detail page has no exit (UX-005), and auth, profile and share dialog have no 2.0× suites |
| 8 | Dark mode | **6** | 0.5 | Mostly scheme-driven, and tier pairs are per-brightness. The RANK pill is ~1.5:1 in dark (UX-012), and the hero edge disappears in dark |
| 9 | Accessibility | **4** | 2 | Rating can't be done by keyboard or screen reader (UX-003). Only 3 `Semantics` widgets, 0 headings, 0 live regions; keyboard focus is invisible on cards; no autofill on auth (UX-013–016) |
| 10 | States & feedback | **5** | 1 | `friendlyError()` is used everywhere and the snackbars are good. But there is no way to delete a recipe (UX-037), the profile is inert (UX-038), `/auth` is a dead end (UX-002), a search miss shows the wrong copy (UX-022), the main grid error has no retry (UX-027), the Trending rail is an empty box, and there is developer copy on Explore |
| 11 | Motion | **3** | 0.5 | Three animations in the whole app, and reduced motion is never read. Cook-mode step changes cut hard |
| 12 | Identity (anti-slop) | **5** | 1 | Real seeds exist: numbered shelves, the foil spotlight, the FDA label, dark cook mode. Everything else is default M3 (only Card, FilledButton and Input are themed). The front door has no food photography (UX-034), and every card banner is the same solid brown |

**Weighted overall: 5.1 / 10** (66.5 / 13). It was 5.2 before the signed-in addendum lowered
States from 6 to 5. *Functional, carefully engineered, visually generic, and
behind on accessibility.* The layout engineering (envelopes, flowing grid, degradation order) scores
well above everything else.

**Slop tells present:** unmodified M3 defaults presented as the design (typography, chips, tabs,
app bars, dialogs, snackbars); identical banner-over-placeholder cards wherever curated content
appears; one hue family (paprika tints) across almost every surface. No gradients-as-decoration and
no glassmorphism — the one gradient (chefs hero) is deliberate.

## Top 10 fixes (user impact ÷ effort)

1. **UX-003** Make `StarRatingInput` keyboard- and screen-reader-operable. Nobody using assistive tech can rate today.
2. **UX-002 / UX-017** Give `/auth` a way back, and carry `?from=` through sign-in. The sign-up journey dead-ends and loses intent.
3. **UX-001** Render step photos in the method column and in cook mode. The editor accepts them, then hides them.
4. **UX-004 / UX-028** Clean the imported bylines (HTML, sentences) and hide the fake `medium` difficulty on imports.
5. **UX-010 / UX-011 / UX-012** Contrast fixes: difficulty badge, rating stars, dark RANK pill. These belong in Phase 2's color extension.
6. **UX-023 / UX-024** Show fractions for cooking units, and make temperature and time large in cook mode. This is the core product.
7. **UX-034** Give the 14 curated recipes cover photographs, or design a real no-photo card. The front door currently shows 14 placeholder icons.
8. **UX-013 / UX-014** Add heading, `checked` and `selected` semantics, and make card focus visible.
9. **UX-022 / UX-021** Build a proper search-miss state that offers Explore, and make search URL-addressable.
10. **UX-037 / UX-038** Let owners delete a recipe, and give the profile editing plus a link to the member's own chef page. Both are basic capabilities that are missing entirely.

(UX-031 / UX-032, type ramp and component consolidation, are not listed because Phase 2 does them anyway.)

## Findings

Format: `ID | severity | dim | evidence | mechanism → fix`. IDs stay the same across re-audits.

### Critical

- **UX-001 | Critical | 1** | `recipe_editor/steps_editor.dart:154-159` uploads `RecipeStep.imageUrl`, and there is no `.imageUrl` read anywhere under `features/recipe_detail/` except the cover (`recipe_detail_compact.dart:194`, `recipe_detail_expanded.dart:303`). A cook adds a photo to a step, saves, and never sees it again: on the detail page, in cook mode, anywhere. → Render it in the method step card and `cook_step_view.dart`. (B125)
- **UX-002 | Critical | 10** | `auth/auth_screen.dart:71` + `routing/app_router.dart` (every entry is `context.go(Routes.auth)`) · capture `auth-390-light`. `/auth` sits outside the shell and has no history, so the `AppBar` draws no back button and there is no nav bar. A signed-out phone user who taps Profile, the FAB, Like or Fork is stranded. → Add `leading` calling `popOrGo(context, Routes.discover)`. (B131)
- **UX-003 | Critical | 9** | `design_system/.../star_rating.dart:221-233`. `StarRatingInput` is a `GestureDetector` under `Semantics(slider: true)` with no `onIncrease`/`onDecrease` and no focus or key handling. Keyboard, VoiceOver and TalkBack users cannot rate (WCAG 2.1.1). → Add semantics increase/decrease in 0.5 steps, plus `FocusableActionDetector` with arrow keys. (B126)
- **UX-004 | Critical | 12** | DB: 14 imported `profiles.display_name` contain raw HTML (`Adapted from <a href="https://…`), and 50 are over 40 characters, i.e. sentences rather than names (`"Reprinted with permission from Jackie Sobon and Fair Winds Press…`). Capture `chef-imported-html-1440`: the markup is the page title, the "credit, not an account" body and the avatar initials. Credit is a product principle, and here it is illegible. → Sanitise in `import_recipe` (strip tags, split "adapted from") and re-apply; defensive `stripHtml` on render. (B127)

### Major

- **UX-005 | 7** | `recipe_detail/recipe_detail_expanded.dart:156` draws Back only `if (Navigator.of(context).canPop())` · capture `recipe-tikka-1440-light`. A shared or deep link opens a root route with no top bar and no back, so the only exit is the browser. → `popOrGo(context, Routes.discover)` as the compact page does. (B132)
- **UX-010 | 3,9** | `difficulty_badge.dart:13-14`. `Colors.green.shade600` / `orange.shade700` as 11px text on their own 12% tint measure **2.77:1 / 2.30:1** (AA needs 4.5). They ignore brightness, and `Hard` = `scheme.error` reads as an error state. → Brightness-aware semantic colors in a `ThemeExtension`. (B133)
- **UX-011 | 3,9** | `star_rating.dart:51,210`. `AppTheme.rating` #F2A93B on the light surface is **1.9:1**. Empty, half and full stars fail 1.4.11 (3:1 for UI). → A darker light-mode rating color. (B133)
- **UX-012 | 8** | `chef_spotlight_card.dart:501` (with `:98`) · capture `chefs-1440-dark`. In dark, the RANK pill is white at 92% with pastel tier text, ~1.4–1.8:1. → Resolve the pill text at light brightness, or use a dark pill.
- **UX-013 | 9** | `recipe_card.dart:181` (banner `:429`, cover `:557`), and the same in `chef_spotlight_card.dart:108`. The `InkWell` paints focus and hover on the `Card` material *under* the opaque banner and cover, so keyboard focus shows only on the footer strip (2.4.7). → Overlay an `InkWell` in a `Stack`, or add an explicit focus border.
- **UX-014 | 9** | Global. 0 `Semantics(header:)`; check-off rows (`ingredient_rail.dart:185`, `method_column.dart:220,261`) have no `checked:`; the selected sort, pill and nav items (`discover_screen.dart:291`, `chef_detail_common.dart:105`, `top_nav_bar.dart:343`) have no `selected:`. The brand `InkWell` at medium width (`top_nav_bar.dart:167`) is an unlabeled button. → The heading/checked/selected pattern already exists at `chefs_hero.dart:339`; copy it.
- **UX-015 | 9** | `auth_screen.dart:110-129`: no `AutofillGroup` or `autofillHints` (1.3.5), no `textInputAction`/`onFieldSubmitted`, so Enter doesn't submit on web.
- **UX-016 | 9** | `cook_mode_screen.dart:116-125`. `CallbackShortcuts` sits between the focused button and the app's `ActivateIntent`, so Space on a focused "Start timer" or "Reset" advances the step instead of pressing the button. → Drop Space, or skip it when a button has focus. (B130)
- **UX-017 | 10** | `app_router.dart:128`, `detail_chips.dart:139`, `fork_action.dart:25`, `cook_finish_view.dart:161`. Like, Fork, Rate and New recipe `go(/auth)`, and after sign-in the redirect lands on `/discover`, so the user's intent is dropped. → A `?from=` param honoured by the redirect.
- **UX-018 | 10** | `auth_screen.dart:59-62` + `core/.../auth_repository.dart:66-70`. `signUp` discards the returned session; the UI always `popOrGo`s. With email confirmation enabled (the hosted default; local `config.toml` leaves it off), the user lands signed out with no "check your inbox". → Return the session and show a confirm-email state.
- **UX-019 | 10** | `recipe_detail_screen.dart:37` (and `cook_finish_view.dart:73`). `isOwner` compares `currentUserIdProvider` (auth uid) with `recipe.ownerId` (a profile id). A member who has claimed an imported page gets Fork instead of Edit on their own recipes. CLAUDE.md requires `currentProfileIdProvider`. (B128)
- **UX-020 | 10** | `detail_chips.dart:98-115`, `nav_destinations.dart:52-68`, `my_recipes_screen.dart:34`. Save writes a bookmark that no screen lists. → A Saved tab on My Recipes.
- **UX-021 | 10** | `discover_screen.dart:124-127, 100-105`. The only `/explore` link sits *below* an infinite grid and is hidden while searching, so 21,314 recipes are effectively unreachable.
- **UX-022 | 10** | `discover_screen.dart:104, 362-366` + `app_router.dart:141` (only `mode` is read from the query). A search miss says "No matches / Public recipes will appear here" with no Clear and no route to Explore, and a search can't be linked (`/discover?q=` is ignored — capture `search-empty-1440` shows the unfiltered page).
- **UX-023 | 1** | `core/.../formatting.dart:107-113, 144`. `trimDecimal` prints `0.33 cup` and `0.75 tsp`; cooks read ⅓ and ¾. → A fraction formatter for volume and count units.
- **UX-024 | 1** | `detail_chips.dart:58` (`labelSmall` 11px) used at `cook_step_view.dart:327, 863` and `method_column.dart:285-292`. Oven temperature and step time are 11px beside 24–36px step text, in the one mode meant for arm's length.
- **UX-025 | 1** | `cook_step_view.dart:912, 979-981`. A timer running on another step is invisible until it rings. `cook_mode_providers.dart:311-314`: the session never resets, so cooking the same recipe again reopens the finish screen.
- **UX-026 | 10** | `recipe_detail/fork_action.dart:31`. There is no in-flight guard, so a double tap creates two forks. (B129)
- **UX-027 | 10** | `widgets/recipe_async_grid.dart:117`. `ErrorView` has no `onRetry` on Discover browse, My, Shared, Explore and chef grids; the only recovery is a reload.
- **UX-028 | 12** | DB: **all 21,314** imported recipes have `difficulty = medium` (the default), and every Explore card shows "Medium" as fact (captures `explore-*`). 2,486 imported titles carry scrape noise ("…Recipe + VIDEO"). Violates the honest-numbers rule (Gotcha 29 spirit). → Null or hide difficulty on imports; clean titles at import. (B134)
- **UX-029 | 12** | `explore-1440-light` vs `recipe-imported-1440-light`. Explore cards display publisher photographs by hotlink; the detail page shows none; the preamble says "we do not copy their photographs". The first card's hotlink failed (broken-image icon). → An owner/rights decision: either no images for imports, or show them on both surfaces and reword the copy.
- **UX-030 | 1** | `ingredient_rail.dart` gutter · capture `recipe-imported-1440`. Corpus units are not canonical (`tablespoon`, `teaspoon`; the B094 canon covers only `recipeData/`), so `3 tablespoon` fills the fixed quantity gutter and touches the name. → Canonicalise units at import; let the gutter wrap.
- **UX-031 | 2** | `app_theme.dart` (no `textTheme`); `discover_masthead.dart:51`, `chefs_hero.dart:127,145`, `card_rail.dart:322`, `chef_spotlight_card.dart:282,418,782` fake the drafts' display and mono faces with tracking and weight. → Phase 2 type decision.
- **UX-032 | 6** | Segmented controls: `ChefPillTabs` (`chef_detail_common:61`), `_WindowFilter` (`chefs_hero:319`, literal `0xFF2C1F1B`), `ChoiceChip` (`rail_panel:70`, `nutrition_editor:137`), `_SortLink` (`discover:275`), `TabBar` (`my_recipes:74`), `SegmentedButton` (`share_dialog:191`). Rank badges: 3 (`chef_spotlight_card:488`, `chef_standing_card:315`, `chefs_hero:172`). Kickers: 6. Load more: 2 (`recipe_async_grid:142`, `chefs_screen:444`). Avatar: `CircleAvatar` at `profile_screen:38` vs `ChefAvatar`.
- **UX-033 | 5** | `cook_step_view.dart:1096-1102`, `detail_provenance.dart:405-406`, and the detail action row (capture `recipe-tikka-1440`: filled + tonal + two outlined pills). Unthemed Outlined/Text buttons (stadium, 40px) sit beside the themed Filled (radius 12, ~48px). → Theme every button family.
- **UX-034 | 12** | DB: 14/14 curated recipes have `cover_image_url` null · capture `discover-1440`. The front door is a row of utensil placeholders under identical brown banners, and the principle "the photo carries the page" has nothing to carry. → Content (photograph the Kitchen's 14) and/or a designed no-photo card. Seed-data fit: `recipeData/` has no image field populated.
- **UX-035 | 1** | `steps_editor.dart:160-168`, `edit_models.dart:338`. The step timer is hidden behind a `tune` icon; `int.tryParse` silently drops `1h`; steps and ingredients cannot be reordered (no `Reorderable*`).
- **UX-036 | 1** | `detail_provenance.dart:24-51`. "Forked recipe" names neither the parent nor its author and doesn't link to it, though `forkedFromRecipeId` is on the model. Confirmed live: `recipe-owner-1440-signedin` shows plain "Forked recipe" text.
- **UX-037 | 10** | No UI calls `RecipeRepository.delete` (a grep of `apps/app/lib` for a delete caller finds nothing) · capture `recipe-owner-*-signedin`: the owner gets Share and Edit, never Delete. A recipe, including an accidental fork (see UX-026), can never be removed. → Delete in the owner's overflow and the editor, with a confirm (the repository already throws `WriteDeniedException` on an RLS miss).
- **UX-038 | 10** | `features/profile/profile_screen.dart` · captures `profile-{390,1440}-signedin`. The profile is an avatar, a name, "New recipe" and "Sign out", and nothing else: `ProfileRepository.updateMine` has **no caller**, so a member can't change name, bio or avatar; there are no stats; and nothing links to their own public `/chef/:id` (the avatar menu doesn't either). At 1440 the two buttons stretch the full 1392px, and the legal links render twice (page content + web chrome footer). → Edit profile, "View my chef page", constrain the width, and keep the page's legal links compact-only.
- **UX-039 | 1** | `recipe_editor/recipe_editor_screen.dart:877-912` · captures `editor-edit-*-signedin`. The order is **Nutrition → Ingredients → Steps**, so the full FDA label (≈540px) sits above the ingredients it is estimated from. A new recipe opens with Prep `0`, Cook `0`, Servings `1` and Difficulty **Easy** prefilled, so an untouched field saves a claim. On a phone each ingredient takes ~4 rows (qty/unit, name, food chip, note, Optional), and 10 ingredients is several screens. "Not counted" lists the same ingredient twice. → Ingredients → Steps → Nutrition; empty defaults with hint text; a collapsed ingredient row that expands on tap.

### Minor

- **UX-040** Avatar initials split on whitespace, so `Kannamma @kannammacooks.com` → **"K@"** (`chef_avatar.dart:60-67`; capture `recipe-imported-1440`).
- **UX-041** Brand spelled two ways: "Secret-Sauce" (auth app bar `auth_screen.dart:71`, footer, `MaterialApp.title`) vs "Secret Sauce" (top bar).
- **UX-042** Generic app-bar titles "Chef" / "Publisher" (`chef_page.dart:69`, `entity_page.dart:33`). An imported credit page says "joined Sep 2026" (capture `chef-imported-html`). The entity page says "Chef" three times (kind chip, roster heading, role).
- **UX-043** Durations in four formats: `1 h 10 m` (detail facts), `1h 10m` (card, `my-owned-1440-signedin`), `30 min`, `8 m` (`method_column.dart:243,287`, `cook_step_view.dart:749` vs `formatMinutes`).
- **UX-044** Cook mode prints "Step 1 of 6" twice (title + progress label); step 1's "You'll need" lists `1 tbsp Tikka spice blend` twice (word-match hint hits both groups).
- **UX-045** The Chefs "Trending chefs" rail with no data renders an empty bordered box with no text (capture `chefs-1440`). About 45% of the 1440 chefs page is empty to the right of the rails.
- **UX-046** Copy: Explore's empty state is developer copy (`explore_screen.dart:57-59`); nutrition copy says auto-calculation is not built, which Phase 29c made false (`nutrition_tab.dart:48-51,78-79`); "Ingredients" appears as both a chip and a heading (`rail_panel.dart:70` + `ingredient_rail.dart:64`); rating semantics says "1 ratings" (`star_rating.dart:42`).
- **UX-047** Three `IconButton`s lack a `tooltip` (`ingredients_editor.dart:50`, `steps_editor.dart:53`, `legal_screen.dart:34`). 10 image sites have neither `semanticLabel` nor `excludeFromSemantics`. `LoadingView` has no semantics label. The ringing-timer banner is not a `liveRegion` (`cook_step_view.dart:901-945`).
- **UX-048** Undersized targets: the version-history link is ~20px tall (`recipe_detail_expanded.dart:172`); pill segments are ~22px (`chef_detail_common.dart:110,120`).
- **UX-049** Proportional digits that jitter: servings `9→10` moves the stepper (`servings_row.dart:79`); ranks in `FittedBox` drift (`chef_standing_card.dart:382`). Selected items gain weight and push neighbours (`discover_screen.dart:317`, `top_nav_bar.dart:368`, `chefs_hero.dart:362`).
- **UX-050** Reduced motion is never read (`card_rail.dart:146`, `recipe_detail_compact.dart:81`); there are no transitions between cook steps.
- **UX-051** There is no per-route `Title`, so every web tab reads "Secret-Sauce" (`main.dart:21`).
- **UX-052** Deleting a whole group has no confirm or undo (`ingredients_editor.dart:50`, `steps_editor.dart:53`); version-history rows can't be opened (`version_history_sheet.dart:35-44`); Qty rejects `1/2` (`ingredients_editor.dart:173`) and its error clips at 2.0× (fixed 64px).
- **UX-053** `profile_screen.dart:43` `NetworkImage` has no error fallback (a broken URL gives a blank circle); `recipe_detail_screen.dart:27` loading `Scaffold` has no back.
- **UX-055** Signed-in chrome: My Recipes shows two "New recipe" buttons when empty (header + empty state), and three on compact with the FAB; the owner's Share and Edit are icon-only circles beside labelled pills (`recipe-owner-1440-signedin`); the desktop owner header has no Private badge (only the facts strip says it; compact shows the badge); the rating control sits at the very bottom under "No ratings yet" with no "Rate this" prompt (`recipe-nonowner-bottom-*`); step-card hover is a neutral grey overlay on the pink surface.
- **UX-054** Off-scale spacing and radii: 12/10/14/6 spacing and 12 distinct raw radii (`chef_spotlight_card.dart` ×13, `recipe_card.dart:235-435`, `method_column.dart`, `cook_step_view.dart`). The chefs hero edge disappears in dark (`chefs_hero.dart:26,56`).

## Journeys

| Journey | Steps | Friction | Verdict |
| --- | --- | --- | --- |
| J1 Discover → recipe → scale → cook → timer → finish | 6 taps | 11px temp/time, decimals, other timers invisible, re-cook reopens finish, step photos missing | **Good, rough edges** |
| J2 Search → miss → recover | 2 | wrong copy, no Clear/Explore, not linkable | **Weak** |
| J3 Sign up → create (groups, timers, photo) → save | 9+ | `/auth` has no back, intent lost, silent unconfirmed sign-up, timer behind icon, no reorder, step photo never shown | **Broken** |
| J4 Fork → edit → history → attribution | 3 | double-fork, parent not linked, history rows inert | **Weak** |
| J5 Chefs → chef → tabs → entity | 4 | entity chips only if memberships exist; no entity directory; 22px pills | **OK** |
| J6 Signed-out phone → Privacy/Terms/Rights | 3 | only via Profile → `/auth` (dead end) → footer | **Weak** |

**Time-to-value** (cold start to the first full recipe): 1 tap, which is good. `/explore`: effectively
undiscoverable (UX-021). An imported recipe's credit (`SourceCredit`) is exemplary; `RecipeCard`
carries no imported marker.

## Static sweep (2026-09-24 baseline — re-audits report movement)

| Signal | Count | Worst files |
| --- | --- | --- |
| `Colors.` / `Color(0x` / alpha outside `src/theme/` | 58 lines | chef_spotlight_card 15, chefs_hero 11, tier_chip 6 |
| `FontWeight.` overrides | 83 (w800 36, w700 28) | cook_step_view, chef_spotlight_card |
| Text-style `copyWith` | 166 | cook_step_view 22, chef_spotlight_card 14, nutrition_facts_label 12 |
| Raw `fontSize` | 2 | — |
| Custom fonts / `TODO(fonts)` | 0 / 7 | — |
| `tabularFigures` | 1 (cook timer) | — |
| `ThemeExtension` | 0 | — |
| `AppSpacing` uses / raw SizedBox / raw EdgeInsets | 485 / ~38 / ~39 | chef_spotlight_card, recipe_card, method_column, cook_step_view |
| Raw `BorderRadius.circular(n)` | 15 (12 distinct values) | chef_spotlight_card, chefs_hero |
| `AppRadii` uses | card 26 · pill 22 · button 11 | — |
| Components themed in `ThemeData` | 3 (Card, FilledButton, Input) | — |
| Animations / reduced-motion checks | 3 / 0 | — |
| `IconButton` / without tooltip | 26 / 3 | editor ×2, legal |
| `Semantics` / `MergeSemantics` / `ExcludeSemantics` / header / liveRegion | 3 / 0 / 0 / 0 / 0 | — |
| Images with semantic label or excluded | 0 of 10 sites | — |
| `meetsGuideline` tests | 0 | — |

## Preserve (load-bearing — Phase 3 must not break)

- **Recipe card geometry:** fixed 352 tile, one flexible band (cover), fixed banner `65 × scale` capped at 2.0, description yields past 2.0× (Gotcha 13, B047/B049).
- **Flowing grid:** `FlowGridMetrics` 288–340 tiles, max 6 columns, left-aligned trailing slack (B123); `RecipeAsyncSliverGrid` is the only loading/error/empty/grid ladder (Gotcha 24).
- **Border-not-shadow card policy** (`app_theme.dart:25-32`); `AppRadii.pill` as the single pill constant.
- **Quantity gutter + one formatting chain:** `ingredientQuantityLabel` / `ingredientOneLine` shared by both rails and cook mode (B066); one `selectedServingsProvider`; the stepper is hoisted above the tabs.
- **Per-group step numbering** that restarts, and group-weighted cook progress (`cook_step_view.dart:773`).
- **Cook mode:** always dark; deadline timers + `cookClockProvider`, one ticker; alarm as state; tabular timer clock (`cook_step_view.dart:1076`); honest copy ("Keep this screen open"); keyboard shortcuts (after UX-016).
- **`SourceCredit`:** four statements, only http(s) links, no duplicate publisher-as-author, with the rights sentence.
- **`friendlyError()`** everywhere, and the messenger captured before `await`.
- **Legal links:** chrome on web, page content on compact (Phase 35a); `/` is a redirect only.
- **`popOrGo`** as the single "leave" rule; the jump bar resets the rail; "Ready to cook?" is pinned outside the scroll.
- **Tier colors per brightness** + `onImage` contrast override (`tier_chip.dart:46-66`); the top nav measures labels at worst-case weight (`top_nav_bar.dart:298-308`); underline as a border (B060).
- **Identity seeds worth growing:** numbered shelf headings (`discover_shelf.dart:168-186`), the foil trading-card spotlight, the dark chefs hero, the FDA-style nutrition label, the recipe-card title banner.
- **Shelf empty states that explain *why*** they are empty ("no public recipe runs to two hours…").

## Captures

| File (`…/audit-2026-09-24/`) | Surface | Width | Theme | Note |
| --- | --- | --- | --- | --- |
| discover-{390,600,1000,1440}-light | Discover | all | light | placeholders only (UX-034); 600 = icon-only nav, by design |
| discover-{390,1440}-dark | Discover | 390/1440 | dark | banner flips to salmon; fine |
| search-empty-1440-light | Discover `?q=` | 1440 | light | query ignored (UX-022) |
| explore-{390,1440}-{light,dark} | Explore | | | hotlinked photos, one broken; all "Medium" (UX-028/029) |
| chefs-{390,1440}-{light,dark} | Chefs | | | empty Trending box (UX-045); dark RANK pill (UX-012) |
| chef-kitchen-{390,1440}-light | `/chef/:id` member | | light | |
| chef-imported-html-1440-light | `/chef/:id` imported | 1440 | light | raw HTML name (UX-004) |
| entity-{390,1440}-{light,dark} | `/entity/:id` | | | "Chef" ×3 (UX-042) |
| recipe-tikka-{390,1000,1440}-light, -{390,1440}-dark | Recipe detail curated | | | 1440 has no back (UX-005) |
| recipe-imported-{390,1440}-light | Recipe detail imported | | light | "K@" (UX-040), unit collision (UX-030) |
| cook-tikka-{390,1440}-light | Cook mode | | always dark | "Step 1 of 6" ×2 (UX-044) |
| auth-{390,1440}-light | Auth | | light | no back (UX-002) |
| legal-{390,1440}-light | Legal | | light | |
| discover-{390,1440}-signedin | Discover, signed in | | light | avatar + My Recipes in the top bar |
| avatar-menu-1440-signedin | Account menu | 1440 | light | name + tier, Profile, Sign out; no link to own chef page |
| my-empty-{390,1440}-signedin, my-owned-{390,1440}-signedin | My Recipes | | light | duplicate CTAs (UX-055); `1h 10m` (UX-043) |
| profile-{390,1440}-signedin | Profile | | light | inert, full-width buttons, legal ×2 (UX-038) |
| editor-new-{390,1440}-signedin | New recipe | | light | 0/0/1/Easy prefilled (UX-039) |
| editor-edit-{top,mid,low}-1440-signedin, editor-edit-mid-390-signedin | Edit recipe (fork) | | light | nutrition above ingredients (UX-039) |
| recipe-owner-{390,1440}-signedin | Detail, owner (fork) | | light | no delete (UX-037), unlinked fork (UX-036) |
| recipe-nonowner-{390,1440}-signedin, -bottom-* | Detail, signed-in reader | | light | rating at the page bottom (UX-055) |

## Re-sweep — 2026-09-25 (after Phase 36b, design system)

**Mode: static + a live spot check.** The static sweep is now a script,
`.claude/skills/ui-overhaul/scripts/static_sweep.sh`, and both columns below come from it: "before"
ran against the pre-36b tree (`git archive ec959c8`) and "after" against the 36b branch. Its
patterns are stricter than the hand-run 2026-09-24 table above: comment lines are excluded, only
non-zero `EdgeInsets` numbers count, and raw numeric alpha is counted apart from `AppAlpha` tints.
So the "before" column restates the baseline under the new rules, and some of its numbers differ
from the hand-run table above. **Scores are not re-graded here.** The live
spot check was a release web build with **no local stack** (Docker was down), which covers only
chrome, static pages and error states: `.playwright-mcp/captures/design-2026-09-25/` (legal-1440,
chefs-1440, discover-390, all light). It confirms that Newsreader and Manrope load under CanvasKit
and that the button families share a corner. A full re-audit (Phase 1 again) belongs after 36c.

| Signal | Before (`ec959c8`) | After (36b) | Remaining in |
| --- | --- | --- | --- |
| Colors.* (outside theme; `transparent` included) | 21 | 3 | top_nav_bar.dart:2 discover_screen.dart:1 |
| Color(0x… (outside theme) | 12 | 0 |  |
| Raw numeric alpha (outside theme) | 23 | 1 | chef_spotlight_card.dart:1 |
| FontWeight.* (outside theme) | 79 | 7 | nutrition_facts_label.dart:4 top_nav_bar.dart:2 chef_avatar.dart:1 |
| fontSize: (outside theme) | 2 | 1 | chef_avatar.dart:1 |
| letterSpacing: (outside theme) | 19 | 2 | recipe_card.dart:1 card_rail.dart:1 |
| Text-style copyWith (outside theme) | 168 | 102 | cook_step_view.dart:18 nutrition_facts_label.dart:7 nutrition_editor.dart:6 |
| Tabular-figure sites | 1 | 58 |  |
| ThemeExtension classes | 0 | 2 |  |
| AppSpacing uses | 471 | 547 |  |
| Raw non-zero EdgeInsets number (outside theme) | 39 | 0 |  |
| Raw SizedBox number (outside theme) | 38 | 0 |  |
| Raw (Border)Radius.circular(n) (outside theme) | 16 | 0 |  |
| AppRadii uses | 59 | 66 |  |
| Duration(milliseconds (outside theme) | 7 | 4 | share_dialog.dart:1 recipe_editor_screen.dart:1 ingredients_editor.dart:1 |
| Curves.* (outside theme) | 2 | 0 |  |
| AppMotion uses | 0 | 6 |  |
| Reduced-motion reads (disableAnimationsOf / AppMotion.of / animateScroll) | 0 | 3 |  |
| BoxShadow( | 2 | 2 |  |
| IconButton( (outside theme) | 28 | 28 |  |
| Semantics( | 3 | 3 |  |
| Button themes in ThemeData | 1 | 6 |  |
| Component themes in ThemeData | 3 | 15 |  |

**What the survivors are, each commented at its site:** 3 × `Colors.transparent` ("no colour"); the
spotlight caption's gradient end (`coverScrim` at alpha 0); 4 × w900 on the FDA nutrition label (the
label's own spec); the top nav's two weights (it measures labels at worst-case w800, so the heavier
selected label cannot move its neighbours — Preserve); the avatar's initials size and weight
(computed from the circle); the recipe-card banner's 0.16 tracking and the rail numeral's −0.5; four
debounces (behaviour, not motion). The ~102 remaining text-style `copyWith`s set colour or a
line height inside a fixed box, not weight or size.

**Findings closed by 36b** (static evidence plus the guard tests; visual confirmation waits for the
post-36c re-audit):

| ID | Status | Evidence |
| --- | --- | --- |
| UX-010, UX-011 (B133) | fixed | `AppPalette`; `theme_contrast_test.dart` (difficulty ≥ 5.0:1 on its wash, rating ≥ 3.75:1) |
| UX-012 | fixed | RANK pill ink resolved at light brightness; the contrast test covers the pill in both themes |
| UX-031 | fixed | The full `TextTheme` in bundled Newsreader + Manrope, plus `AppTextStyles`; `FontWeight` overrides 79 → 7 |
| UX-032 | partial | Kickers ×6 → `appText.kicker` / `kickerLarge`. Segmented controls, rank badges, Load more and avatars are carried to 36c (DESIGN.md §4) |
| UX-033 | fixed | One corner and one label weight for every button family; ~48dp container buttons (`theme_extensions_test.dart`) |
| UX-049 | fixed | Tabular-figure sites 1 → 58; the selected sort, window and pill labels keep one weight |
| UX-050 | fixed | `AppMotion.of` / `animateScroll` at every animation (3 sites); cook-step transitions remain a 36c design item |
| UX-054 | fixed | Raw insets, `SizedBox` numbers and radii → 0 (half-steps named; component geometry named per widget) |

## Re-sweep — 2026-09-25 (after Phase 36c, reference rebuild)

Same script (`static_sweep.sh`), 36b branch tip vs the 36c screens commit. The token discipline
held through a visual rebuild: no hex, radius, inset or `SizedBox` literal came back; tabular sites
and `AppSpacing`/`AppRadii` uses grew with the new surfaces. The one new `Colors.` hit is the
restored `dividerColor: Colors.transparent` on My Recipes' web tab bar (36b review). Scores are not
re-graded; the fidelity scores are in [REBUILD-LOG.md](REBUILD-LOG.md).

| Signal | After 36b | After 36c |
| --- | --- | --- |
| Colors.* (outside theme; `transparent` included) | 3 | 4 |
| Color(0x… (outside theme) | 0 | 0 |
| Raw numeric alpha (outside theme) | 1 | 1 |
| FontWeight.* (outside theme) | 7 | 7 |
| fontSize: (outside theme) | 1 | 1 |
| letterSpacing: (outside theme) | 2 | 1 |
| Text-style copyWith (outside theme) | 102 | 107 |
| Tabular-figure sites | 58 | 67 |
| ThemeExtension classes | 2 | 2 |
| AppSpacing uses | 547 | 579 |
| Raw non-zero EdgeInsets number (outside theme) | 0 | 0 |
| Raw SizedBox number (outside theme) | 0 | 0 |
| Raw (Border)Radius.circular(n) (outside theme) | 0 | 0 |
| AppRadii uses | 66 | 72 |
| Duration(milliseconds (outside theme) | 4 | 4 |
| Curves.* (outside theme) | 0 | 0 |
| AppMotion uses | 6 | 8 |
| Reduced-motion reads (disableAnimationsOf / AppMotion.of / animateScroll) | 3 | 4 |
| BoxShadow( | 2 | 2 |
| IconButton( (outside theme) | 28 | 27 |
| Semantics( | 3 | 6 |
| Button themes in ThemeData | 6 | 6 |
| Component themes in ThemeData | 15 | 16 |

## Findings closed — 2026-09-26 (Phase 37, UX remediation)

Branch `feat/phase-37-ux-remediation`, four commits (waves A–D). Every fix carries a regression test
checked by reverting it. Evidence is the named test plus a live pass on a release web build against
the local stack (`127.0.0.1:54621`, 1000 / 1040 / 1440 / 390 px, signed out and as the test account).
Scores are not re-graded here; a Phase 1 re-audit would. Static sweep, same script as above:

| Signal | After 36c | After 37 |
| --- | --- | --- |
| Colors.* (outside theme; `transparent` included) | 4 | 7 (all `transparent`, commented) |
| Color(0x… / raw insets / raw SizedBox / raw radii (outside theme) | 0 / 0 / 0 / 0 | 0 / 0 / 0 / 0 |
| FontWeight.* (outside theme) | 7 | 7 |
| Tabular-figure sites | 67 | 68 |
| AppSpacing uses | 579 | 598 |
| AppMotion uses / reduced-motion reads | 8 / 4 | 11 / 6 |
| Semantics( | 6 | 34 |
| IconButton( (outside theme) | 27 | 30 (every one with a tooltip) |

| ID | Status | Evidence |
| --- | --- | --- |
| UX-001 (B125) | fixed | `StepPhoto` in the method panel and cook mode; `step_photo_test`, `cook_mode_test` (fixture URL — no seeded step photo) |
| UX-002 (B131), UX-005 (B132) | fixed | `popOrGo` Back on `/auth` and the deep-linked expanded page; live capture `recipe-1440` |
| UX-003 (B126) | fixed | `star_rating_test` keyboard + semantics group |
| UX-013 | fixed | `InteractiveTile`; `recipe_card_test`, `chef_spotlight_card_test` |
| UX-014 | fixed | headings (kickers, rail titles, legal, entity, chef), `checked` check-offs, `selected` sort / pills / nav; `reading_a11y_test`, `chrome_a11y_test`, `card_rail_test` |
| UX-015 | fixed | `AutofillGroup`, hints, input actions, Enter submits; `auth_screen_test` |
| UX-016 (B130) | fixed | Space only on the page's own focus; `cook_mode_test` |
| UX-017, UX-018 | fixed | `goToSignIn` + `safeReturnPath` (no open redirect); `SignUpOutcome`; `auth_return_test`, `auth_screen_test` |
| UX-019 (B128) | fixed | profile-id ownership; claimed-member fixtures in `recipe_detail_test`, `cook_mode_test` |
| UX-020 | fixed | Saved tab over `listSaved` (`recipes!inner`); live stack returned a saved recipe |
| UX-021, UX-022 | fixed | `/discover?q=`, miss state with Clear + Explore, masthead link; live: typing replaces the history entry |
| UX-023 | fixed | fractions in the one chain (`formatQuantity`); thirds/eighths print flat — Manrope has no stacked glyphs for them |
| UX-024 | fixed | `MetaChip(large:)` in cook mode, ≥ 16px asserted |
| UX-026 (B129) | fixed | `forkInFlightProvider`; two tests (disabled chip; direct double call) |
| UX-027 | fixed | retry on every `RecipeAsyncSliverGrid` error; `paging_test`, `explore_screen_test` |
| UX-032 | fixed | `SegmentedTabs`, `RankBadge`, `LoadMoreButton`, `ChefAvatar` on profile |
| UX-037 | fixed | owner overflow + editor delete; `recipe_delete_test` |
| UX-038, UX-053 | fixed | edit profile, View my chef page, 560px measure, compact-only legal links; `profile_screen_test` |
| UX-041 | fixed | "Secret Sauce" in UI copy (the legal documents and the footer copyright keep the entity name) |
| UX-043, UX-044, UX-046 | fixed | one duration format (the card keeps `1h 10m` by width — the long form clipped at 288 × 1.0); step count once; deduped "you'll need"; `1 rating`; honest nutrition and Explore copy |
| UX-047 (partial), UX-048 (chef pill), UX-051 | fixed | tooltips + live ringing banner; 48px segments; `RouteTitle` on every page |
| UX-055 (partial) | fixed on web | one New recipe on web's empty My Recipes; compact still shows the AppBar icon, the empty state and the FAB |
| Chefs hero `MASTER CHEF` near 96px | no defect | captured at 1000 / 1040 px: sets whole |

| UX-004 (B127), UX-028 (B134) | fixed | import-time cleaning in `import_recipe` + backfill; imported difficulty not shown; `corpus_import_fixture.sql` §6 |

Still open from this audit: UX-025, UX-029 (owner),
UX-030, UX-034 (owner content), UX-035, UX-036, UX-039, UX-040, UX-042, UX-045, UX-047's image
labels and `LoadingView`, UX-049's remaining sites, UX-050's cook-step transitions, UX-052, UX-054's
dark hero edge, and UX-055's compact duplicates.
