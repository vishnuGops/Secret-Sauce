# Secret-Sauce Design Language & System — v2 (2026-09-25)

Phase 2 of the `ui-overhaul` skill. Reads [AUDIT.md](AUDIT.md) (2026-09-24, 5.1/10); Phase 3
(reference rebuild) reads this file and changes **token values** before it touches a screen.
Dart is the source of truth: `packages/design_system/lib/src/theme/`. Where this document and the
code disagree, the code wins and this file is wrong — fix it the same day.

Owner decisions — v1 (Phase 36b): Newsreader + Manrope bundled · paprika seed · tone "warm
editorial cookbook". **v2 (Phase 36c, reference rebuild, same day) supersedes them:** one bundled
family (**Manrope**, "basic for now") · **tomato / deep brown / burnt orange** on neutral white
pages · a **neutral near-black** dark mode · tone **bright, photo-first, modern recipe app** (five
owner references, [references/](references/), [REBUILD-LOG.md](REBUILD-LOG.md)). §1's principles
stand unchanged; where a v1 value below differs from §0, §0 and the code win.

## 0. v2 — the reference rebuild (Phase 36c)

What changed from v1, in the order a re-skin reads it. Everything is still one token away.

| Area | v2 value | Where |
| --- | --- | --- |
| Colour scheme | **Explicit** light and dark schemes (not `fromSeed` alone): light primary tomato `#BE3526` (5.6:1 with white), secondary deep brown `#492511`, tertiary burnt orange `#AD4A00` (kickers, step numbers, nutrition figures), surface `#FFFFFF`, neutral warm-grey containers (`#FAF8F6 … #ECE7E2`); dark surface `#161616`, neutral containers, lifted accents (`#FF8A78`, `#E9C4AE`, `#FFB77A`) | `app_theme.dart` `_lightScheme` / `_darkScheme` |
| Palette additions | `surfaceWarm` (the cream hero band, `#FBF7F4` / `#1E1B19`); six **category blocks** (coral, yellow, pink, brown, sage, sky) with their inks, read through `category(cat)`, which derives from core's `DiscoverCategory` so a cover's colour and the tile that filters it agree; `rankRibbon` + ink | `app_palette.dart` |
| Type | One family, **Manrope** (Newsreader removed from the bundle); display / headline / titleLarge **w700** with slight negative tracking; `appText.kickerLarge` is the section index line | `app_typography.dart` |
| Shape | Buttons and chips are **pills** (`AppRadii.button = pill`); `AppRadii.md` (12) takes inputs and 12px boxes; `AppRadii.sheet` (28) for the detail sheet; cards are **borderless tonal panels** (`surfaceContainerLow`) | `app_theme.dart` |
| Navigation | Active destination tomato (bottom bar: `primaryContainer` pill, `primary` icon + label; web: flat `primaryContainer` chip with `onPrimaryContainer` ink — `primary` on it is 3.8:1 in dark) | `app_theme.dart`, `top_nav_bar.dart` |
| Recipe card (v3) | **No chrome**: rounded cover first (the one flexible band), the fixed 65 × scale title band **under** it, the footer reserving two description lines so neighbours line up; visibility chip, chef badge and an optional **rank ribbon** on the cover | `recipe_card.dart` |
| No-photo state | `CategoryCover`: a flat category-colour block; on a card the category as a small index line in a corner, on the detail page set large bottom-left. Never the dish name (it is one line away) | `category_cover.dart` |
| New primitives | `TagPill` (cuisine / category), `NutritionSummary` (calories, fat, carbs, protein — %DV only where the FDA label prints one), `CategoryTile` (Discover's filter tiles) | `design_system/lib/src/widgets/` |
| Discover | Cream masthead band + pill search; **browse by category** (`/discover?category=<slug>`, a paged filter over a group of raw spellings); numbered shelves in the tertiary index line; `03 MOST FORKED` ranked | `features/discover/` |
| Recipe detail | Compact: cover + a sheet with 28px top corners over it; `RECIPE` kicker, bold title, tag pills, label-over-value facts, nutrition summary, Ingredients / Method as **open** tonal panels (owner's Q4). Expanded: the same language at 1140px | `features/recipe_detail/` |

The v1 contrast table in §3.1 and the token map in §7 were regenerated for v2 where values moved;
`theme_contrast_test.dart` asserts every pair (it grew the tertiary / secondary text pairs, the
hero band, the category blocks, the rank ribbon and the tag pill in 36c).

## 1. Direction

**Purpose.** Secret-Sauce is where a recipe is written down properly, followed at the stove, forked
into someone's own version, and credited back to where it came from. The interface's job is to make
a recipe's *structure* — groups, quantities, order, timers, lineage — effortless to read and to act on.

**Audience, and what each scans first.**

| Who | Doing | Scans first |
| --- | --- | --- |
| A browser (signed out, phone or desktop) | Discover, Explore, a chef page | The photo, then the title, then time and difficulty |
| A cook mid-recipe (phone propped up, hands wet) | Detail rail, cook mode | The next quantity, the current step, the running timer |
| An author (signed in, desktop more often) | Editor, My Recipes | Where they are in the form, what is unsaved, what will print |
| A curious reader | A fork, an imported recipe | Who made the original, and what changed |

**Tone.** *Warm editorial cookbook.* One primary register — a well-set cookbook: a serif display
face for names and headings, a clear sans for everything a cook acts on, generous but not airy
spacing, paper-warm surfaces, paprika used sparingly as the ink colour of emphasis. No accent
register beyond it: the second "colour" of the page is the food.

**Memorable detail.** *The index line.* The numbered shelf heading (`01 UNDER 30`) is the seed:
a small, tracked, tabular-figure kicker set above a serif title. It becomes the one typographic
signature — shelves, recipe-detail sections (`Ingredients`, `Method`), step groups, the chefs hero,
the rank on a spotlight card — built from a single `kicker` text role instead of today's six
hand-rolled versions (UX-032). A cookbook's contents page, carried through the app.

**Constraints.** Flutter M3, one adaptive codebase · breakpoints 600 / 1000, unchanged · the
2.0× text envelope and the 288px card floor (Gotchas 13, 21–27) · CanvasKit on web (no DOM, fonts
must be bundled or they flash) · light and dark · cook mode **always dark** · food photography
that is **usually missing** today (14/14 curated recipes have no cover — UX-034), so every image
slot has a designed no-photo state · the Preserve list in AUDIT.md.

### Principles (they decide arguments, in this order)

1. **The recipe is the interface.** Structure outranks decoration. A quantity, a step number or a
   timer is never smaller, fainter or lower on the page than something ornamental next to it.
   *Decides:* cook-mode temperature/time grow (UX-024); the quantity gutter stays; a banner never
   crowds the cover the card exists to show.
2. **Kitchen-proof.** Legible at arm's length, under bad light, with a thumb. 4.5:1 text, 3:1 UI,
   48dp targets, tabular figures anywhere a number changes, and no state carried by colour alone.
   *Decides:* B133's difficulty/rating contrast; UX-049's jitter; the difficulty badge keeps its word.
3. **Credit is visible.** Every fork names its parent, every imported recipe names its source,
   every chef page says whether it is a member or a credit. Lineage and attribution get real type,
   not a grey footnote. *Decides:* attribution block keeps its four statements (Preserve); the
   `kicker` role is available to label provenance as clearly as a shelf.
4. **Honest numbers, honest emptiness.** No engagement that was not earned; an empty board looks
   empty on purpose and says why, never broken and never padded. *Decides:* empty states explain
   (Preserve: shelf empties); no "Medium" or "0 ratings" shown as fact where nothing is known.
5. **The photo carries the page — and the page stands without it.** Chrome recedes into warm
   neutrals so food is the colour. When there is no photo, the slot is *typeset*, not iconed: the
   dish name in the serif on a quiet paper tone, not a utensil glyph on a brown band.
   *Decides:* the no-photo card is a first-class design state (UX-034, Phase 3), and chrome
   surfaces stay low-chroma.

## 2. Language

### 2.1 Voice & microcopy

- **Plain, direct, second person, sentence case.** "Save recipe", not "Save Recipe" or "Bookmark it!".
- **Numerals and correct plurals** — `1 recipe`, `2 recipes` (B031); `1 rating`, never `1 ratings` (UX-046).
- **Cooking units as a cook reads them** — the canon is `nutritionData/units.json`'s display form
  (B094); fractions for volume and count units are a Phase 3/behaviour item (UX-023), not copy.
- **Errors say what happened and what to do**, always through `friendlyError()`. Never "Oops",
  never an exception string, never blame.
- **Empty states explain why** and, when there is one, offer the next action (Preserve).
- **Honest capability copy** — "Keep this screen open", "chime when a timer ends" (cook mode) —
  never promise what a plugin we have not added would do.
- **One brand spelling in UI copy: "Secret Sauce"** (the product name as a reader says it);
  `Secret-Sauce` survives only as the repo name (UX-041 — a behaviour/copy fix, logged here as the rule).
- **Durations one way:** `1 h 10 min`, `45 min` (UX-043 — the rule; the unification is a copy fix).

### 2.2 Imagery

| Slot | Aspect | Crop | No-photo state |
| --- | --- | --- | --- |
| Recipe card cover | fills the one flexible band of the fixed 352 tile | `BoxFit.cover`, centre | Typeset: dish initial / name in the display serif on `surfaceContainer` (Phase 3) |
| Detail hero (expanded) | ~16:9, capped by the 1140px page | cover, centre | The flat no-image hero (`.hero.noimg`) — header band only, no placeholder |
| Detail cover (compact) | ~4:3 | cover, centre | Collapses; the title leads |
| Step photo | 4:3, full step-card width | cover | Absent — no placeholder (UX-001 is a behaviour fix) |
| Avatars | 1:1 circle | cover | Initials on a tier- or scheme-tinted disc (`ChefAvatar`) |

Every photo gets a **neutral inset hairline** (`AppPalette.imageOutline`, black/white at ~10%),
never brand-tinted, so a pale plate does not bleed into a pale surface. No stock imagery, no
illustration packs, no decorative blobs.

### 2.3 Iconography

- **Material Icons, one set.** Default (filled) weight for actions and navigation; the `_outlined`
  variant only for the *unselected* half of a toggle (like/save, nav destinations) — which is how
  it is used today (126 filled / 36 outlined / 5 rounded; the 5 rounded are migrated when touched).
- **Sizes are tokens** (`AppIconSize`, §3.8): `sm 16` inline with label text, `button 18` inside
  a button (M3's size), `md 20` chips and list glyphs, `lg 24` app bar, navigation and standalone
  `IconButton`s.
- **Icon + label** for any action a first-time reader must understand (Fork, Cook, Save); icon-only
  is allowed for universally-known actions and always carries a `tooltip` (UX-047).

### 2.4 Motion character

**Quick and quiet — motion confirms, it never performs.** Things arrive with a short ease-out, leave
faster than they came, and never bounce. Reduced motion (`MediaQuery.disableAnimationsOf`) wins over
everything: durations collapse to zero (UX-050). Cook-mode timers are clock reads, not animations.


## 3. Foundations

All foundations are Dart in `packages/design_system/lib/src/theme/`, exported from
`design_system.dart`. `app_theme.dart` re-exports the other three, so a `design_system` widget that
imports it sees every token.

### 3.1 Color

**Roles first.** `ColorScheme.fromSeed(seedColor: 0xFFD2492A)` (paprika, tonal spot) gives every M3
role; nothing hand-authors a scheme role. **What M3 has no role for is `AppPalette`**
(`app_palette.dart`), a `ThemeExtension` with a light and a dark instance, read as
`context.palette.<field>`:

| Group | Fields | Notes |
| --- | --- | --- |
| Rating | `rating` | Stars, rating pill. Light darkened for 3:1 (UX-011) |
| Difficulty | `difficultyEasy/Medium/Hard`, `difficulty(d)` | Text + icon; fill = colour at `AppAlpha.badge`. Hard is a chili red, no longer `scheme.error` (UX-010) |
| Tiers | `tierHomeCook … tierMasterChef`, `tier(t)` | Chip, ladder, spotlight. `TierChip.colorFor` delegates here |
| On a photo | `scrim`, `onImage`, `imageControl`, `imageOutline`, `coverScrim` | Brightness-independent where the surface is a photograph |
| Spotlight foil | `foilShade`, `foilHighlight`, `floatingShadow` | The trading card's frame and lift |
| Chefs hero | `heroStart/Mid/End`, `heroGradient`, `onHero`, `onHeroMuted`, `heroFill`, `heroFillSubtle`, `heroSelectedInk`, `heroShadow` | Dark in **both** themes |

`AppPalette.of(brightness)` resolves a colour at a brightness other than the page's — the three
places that need it are a tier chip on a photo scrim (dark), the always-dark hero (dark) and the
spotlight card's near-white RANK pill (light — UX-012).

`AppAlpha` names the tint steps (`faint .07`, `wash .10`, `badge .12`, `tint .14`, `tintStrong .16`,
`onImageTint .28`, `glow .30`, `rule .35`, `emphasis .45`, `muted .5`, `frosted .92`). A new tint
picks one; it does not invent a number.

**Contrast table** (generated from `AppTheme.light()` / `AppTheme.dark()` on 2026-09-25; a `Card` is
`surfaceContainerLow` — M3's default, the theme sets no card colour; asserted by
`packages/design_system/test/theme_contrast_test.dart`, which covers more pairs than are listed here):

| Pair | Light fg / bg | Light | Dark fg / bg | Dark | Min | |
| --- | --- | --- | --- | --- | --- | --- |
| onSurface / surface | #231917 / #FFF8F6 | 16.36 | #F1DFDB / #1A110F | 14.43 | 4.5 | pass |
| onSurfaceVariant / surface | #534340 / #FFF8F6 | 8.91 | #D8C2BD / #1A110F | 10.94 | 4.5 | pass |
| onSurfaceVariant / surfaceContainerHighest | #534340 / #F1DFDB | 7.27 | #D8C2BD / #3D3230 | 7.29 | 4.5 | pass |
| primary / surface | #904B3B / #FFF8F6 | 6.15 | #FFB4A3 / #1A110F | 10.88 | 4.5 | pass |
| onPrimary / primary | #FFFFFF / #904B3B | 6.45 | #561F12 / #FFB4A3 | 7.69 | 4.5 | pass |
| onPrimaryContainer / primaryContainer | #733426 / #FFDAD2 | 7.21 | #FFDAD2 / #733426 | 7.21 | 4.5 | pass |
| onSecondaryContainer / secondaryContainer | #5D3F39 / #FFDAD2 | 7.25 | #FFDAD2 / #5D3F39 | 7.25 | 4.5 | pass |
| onError / error | #FFFFFF / #BA1A1A | 6.46 | #690005 / #FFB4AB | 7.72 | 4.5 | pass |
| onInverseSurface / inverseSurface | #FFEDE9 / #392E2C | 11.58 | #392E2C / #F1DFDB | 10.19 | 4.5 | pass |
| outline / surface (UI) | #85736F / #FFF8F6 | 4.28 | #A08C88 / #1A110F | 5.84 | 3.0 | pass |
| rating / surface (UI) | #B7700A / #FFF8F6 | 3.75 | #F2A93B / #1A110F | 9.30 | 3.0 | pass |
| rating / surfaceContainerLowest (UI) | #B7700A / #FFFFFF | 3.94 | #F2A93B / #140C0A | 9.67 | 3.0 | pass |
| rating / Card (surfaceContainerLow, UI) | #B7700A / #FFF0ED | 3.55 | #F2A93B / #231917 | 8.60 | 3.0 | pass |
| difficulty easy / its 12% wash | #2A6E2E / #E5E7DE | 5.01 | #66BB6A / #23251A | 6.55 | 4.5 | pass |
| difficulty medium / its 12% wash | #8A4F00 / #F1E4D8 | 5.25 | #FFA726 / #352312 | 7.70 | 4.5 | pass |
| difficulty hard / its 12% wash | #9F2B26 / #F3DFDD | 5.78 | #FFB4A8 / #352521 | 8.60 | 4.5 | pass |
| tier homeCook / its 14% wash | #4A626D / #E6E3E3 | 5.05 | #B0BEC5 / #2F2928 | 7.48 | 4.5 | pass |
| tier homeCook / its 14% wash on a Card | #4A626D / #E6DCDB | 4.79 | #B0BEC5 / #37302F | 6.77 | 4.5 | pass |
| tier lineCook / its 14% wash | #00695C / #DBE4E0 | 5.10 | #80CBC4 / #282B28 | 7.67 | 4.5 | pass |
| tier sousChef / its 14% wash | #1360B5 / #DEE3ED | 4.83 | #90CAF9 / #2B2B30 | 8.07 | 4.5 | pass |
| tier headChef / its 14% wash | #6A1B9A / #EAD9E9 | 6.98 | #CE93D8 / #33232B | 6.19 | 4.5 | pass |
| tier masterChef / its 14% wash | #8F5000 / #EFE0D4 | 4.93 | #FFCC80 / #3A2B1F | 9.17 | 4.5 | pass |
| tier masterChef / its 14% wash on a Card | #8F5000 / #EFDACC | 4.69 | #FFCC80 / #423226 | 8.28 | 4.5 | pass |
| onImage / scrim over white | #FFFFFF / #737373 | 4.74 | #FFFFFF / #737373 | 4.74 | 4.5 | pass |
| onImage / imageControl over white (UI) | #FFFFFF / #8C8C8C | 3.36 | #FFFFFF / #8C8C8C | 3.36 | 3.0 | pass |
| onHeroMuted / hero end + heroFill | #D3CBC7 / #6D4F42 | 4.61 | #D3CBC7 / #6D4F42 | 4.61 | 4.5 | pass |

Deliberately not asserted: `outlineVariant` (1.6:1 light — card borders and dividers separate, they
do not identify; every bordered surface is also a tonal step or holds identifying content),
`imageOutline`, shadows, foil. **Cook mode** always renders `AppTheme.dark()`, so the dark column is
its contract.

### 3.2 Typography

Two bundled families (`packages/design_system/fonts/`, OFL 1.1, static cuts):
**Newsreader** 400/500/600/700 + italic 400, **Manrope** 400/500/600/700/800. `AppFonts.uiFamily` /
`displayFamily` are the resolved `packages/design_system/<family>` strings for APIs that take a bare
family (a `TextPainter`, `ThemeData.fontFamily`).

The ramp (`AppTypography.textTheme`) keeps **Material 3's sizes and line heights** — so every piece
of envelope arithmetic (`kRecipeCardBannerHeight`, the chefs page's height budget) is unchanged —
and sets family and weight:

| Role | Family | Size / line | Weight | Used for |
| --- | --- | --- | --- | --- |
| display L/M/S | Newsreader | 57/64 · 45/52 · 36/44 | 600 | Mastheads, the chefs hero title |
| headline L/M/S | Newsreader | 32/40 · 28/36 · 24/32 | 600 | Page and recipe titles, dialog titles |
| titleLarge | Newsreader | 22/28 | 600 | Section headings, app-bar titles |
| titleMedium / Small | Manrope | 16/24 · 14/20 | 700 | UI titles, emphasised row text, tabs |
| body L/M/S | Manrope | 16/24 · 14/20 · 12/16 | 400 | Running text |
| labelLarge / Medium | Manrope | 14/20 · 12/16 | 600 | Chips, secondary labels (buttons are 700 via the button themes) |
| labelSmall | Manrope | 11/16, +0.2 | 700 | Badges, counters — heavier than the mockups' 600 because it is the smallest text in the product |

`AppTextStyles` (`context.appText`) holds the roles M3 has no slot for — each replaces a repeated
override the audit counted (UX-031):

| Role | Spec | Replaces |
| --- | --- | --- |
| `kicker` | Manrope 11/16 w700, tracking 1.4, tabular | **The index line.** Six hand-rolled kickers (tracking 1.4–1.8) |
| `kickerLarge` | Manrope 14/20 w700, tracking 1.4, tabular | The index line at section level, where it *is* the heading: a shelf's `01 UNDER 30` (populated or empty), `EVERYTHING ELSE` |
| `overline` | Manrope 11/16 w700, tracking 0.8 | Small upper-case labels (tracking 0.6–1.0) |
| `stat` / `statLarge` | Manrope 16/24 · 22/28 w800, tabular | Scores, counts, ranks re-bolded to w800 |
| `quantity` | Manrope 14/20 w800, tabular | The ingredient rail's quantity gutter |
| `clock` / `clockSmall` | Manrope 24/32 · 22/28 w600, tabular | Cook-mode countdowns |
| `step` / `stepLarge` | Manrope 24/32 · 36/46 w500 | Cook-mode step text — sans, because at that size the M3 roles are the serif |

**Rules.** Call sites pick a role; they do not re-bold. A weight override that repeats is a missing
role — add it here, not at thirty call sites. Anything that changes while watched or lines up in a
column is tabular (`kTabularFigures`, `style.tabular` — UX-049). A selected state never changes weight
where the label's width is intrinsic: it moves its neighbours (UX-049).

### 3.3 Spacing and layout

`AppSpacing`: `xxs 2 · xs 4 · xsPlus 6 · sm 8 · smPlus 12 · md 16 · lg 24 · xl 32 · xxl 48`. The
three half-steps are the unofficial second scale the audit found (UX-054), made official and finite.
`AppInsets` names the padding of a shared shape: `button` (h20 v14), `badge` (h8 v2), `badgeDense`
(h6 v1), `pill` (h10 v4), `segmentTrack` (3), `segment` (h12 v5), `callout` (14). A number that is
none of these is **component geometry** and lives as a named `const` on the one widget it belongs
to, with a comment (the spotlight card's foil insets are the largest set).

Layout, **written down and not changed**: breakpoints `Breakpoints.compact 600` / `medium 1000`;
page gutters `AppSpacing.md` compact, `AppSpacing.lg` wider; the recipe detail page's measured
1140px column; the flowing card grid (`FlowGridMetrics.fit`: tiles 288–340, ≤ 6 columns,
column-cap slack on the right only — B123) behind `recipeGridMetrics()`; the fixed 352px
`RecipeCard` (Gotcha 13).

### 3.4 Shape

`AppRadii`: `sm 6` (a check box, an inner chip) · `chip 8` · `button 12` · `card 16` · `hero 26` ·
`dialog 28` · `pill 999`. **Concentric rule:** a rounded surface inside another has
`outer = inner + padding` (the spotlight card's 18 → 7 → 11); past about 16px of padding, treat them
as separate surfaces with their own radii.

### 3.5 Elevation and borders

**Borders separate; shadows float.** Cards are `elevation: 0` with an `outlineVariant` side
(`CardThemeData`). Shadow is reserved for layers above the page: menus, dialogs, sheets, the chefs
hero and the spotlight card (`palette.heroShadow`, `palette.floatingShadow`). Dark mode expresses
depth with the tonal `surfaceContainer*` steps.

### 3.6 Density and targets

`VisualDensity.adaptivePlatformDensity` (Flutter's default: compact on desktop/web, standard on
touch). Interactive targets are **48dp** minimum (`kMinInteractiveDimension`); Filled, Outlined and
Elevated buttons are ~48dp tall through `AppInsets.button`, and text buttons keep M3's padded tap
target.

### 3.7 Motion

`AppMotion`: `instant 80 · fast 150 · normal 250 · slow 320 · exit 120` ms; curves `emphasized`
(easeOutCubic), `decelerate` (easeOut), `standard` (easeInOutCubic), `exitCurve` (easeInCubic);
`pressScale 0.97`. **Every duration goes through `AppMotion.of(context, d)`**, which returns zero
under `MediaQuery.disableAnimationsOf` (UX-050); `AppMotion.animateScroll` jumps instead, because
`ScrollController.animateTo` asserts a non-zero duration. Debounces and the cook timer's
`Timer.periodic` are behaviour, not motion, and stay out of these tokens.

### 3.8 Iconography

`AppIconSize`: `xs 14 · sm 16 · button 18 · md 20 · lg 24 · xl 40 · xxl 56`. Material Icons; see §2.3.

## 4. Components

`design_system` widgets and the shared app widgets. **Envelope** = the widths × text scales a test
pumps it at (Gotcha 26: a new caller re-opens it).

| Component | File | Variants / states | Envelope tested | Tokens | Findings |
| --- | --- | --- | --- | --- | --- |
| `RecipeCard` (+ placeholder) | `recipe_card.dart` | cover / no-cover, banner, footer, chef badge on scrim | 264/288/340 × 1.0/2.0/3.0 | palette.scrim, AppAlpha.frosted, card theme | UX-013 focus hidden under the banner; UX-034 no-photo state is an icon |
| `DifficultyBadge` | `difficulty_badge.dart` | easy / medium / hard | via the card suite | palette.difficulty, AppInsets.badge | UX-010 fixed (B133) |
| `TierChip` | `tier_chip.dart` | normal / dense / onImage | via card + chef suites | palette.tier, AppInsets.badge(Dense), AppAlpha | B055; B133 tiers |
| `StarRating` / `RatingPill` / `StarRatingInput` | `star_rating.dart` | display, pill, input (enabled / disabled) | star_rating_test | palette.rating | UX-003 input not keyboard-operable (B126, open) |
| `ChefAvatar` | `chef_avatar.dart` | image / initials | chef suites | scheme | UX-040 initials; duplicated by `CircleAvatar` on profile (UX-032) |
| `ChefBadge` | `chef_badge.dart` | on surface / on image | chef_badge_test | palette.onImage | — |
| `ChefSpotlightCard` (+ placeholder) | `chef_spotlight_card.dart` | per tier, foil, RANK pill | chef_spotlight_card_test | palette foil / cover / shadow, local geometry consts | UX-012 fixed; UX-013 focus |
| `ChefStandingCard` | `chef_standing_card.dart` | ranked / unranked | chef_standing_card_test | stat roles | UX-049 ranks tabular |
| `CardRail` | `card_rail.dart` | paging, empty | card_rail_test | AppMotion.slow via animateScroll | UX-045 empty rail box; UX-050 fixed |
| `TierLadder`, `ScoreContributionBar` | `tier_ladder.dart`, `score_contribution_bar.dart` | — | tier_ladder_test | palette.tier | — |
| `NutritionFactsLabel` | `nutrition_facts_label.dart` | full / per serving | nutrition_facts_label_test | FDA label weights kept as the label's own spec | — |
| `SiteFooter` / `LegalFooter` | `site_footer.dart`, `apps/app/lib/widgets/legal_footer.dart` | dense (web chrome) / page | site_footer_test 360–1440 × 1.0–2.0 | — | — |
| `LoadingView` / `EmptyView` / `ErrorView` | `state_views.dart` | — | via the grid suites | — | UX-027 no retry on grids; UX-047 LoadingView unlabeled |
| `NotYetTooltip` | `not_yet_tooltip.dart` | — | — | — | — |
| `RecipeGrid` / `SliverRecipeGrid` | `apps/app/lib/widgets/recipe_grid.dart` | box / sliver | recipe_grid_test 2560/3840 | FlowGridMetrics | — |
| `RecipeAsyncGrid` / `…SliverGrid` | `apps/app/lib/widgets/recipe_async_grid.dart` | loading / error / empty / grid / load more | paging_test | state views | **The only ladder** (Gotcha 24); UX-027 |
| `ShareDialog` | `apps/app/lib/widgets/share_dialog.dart` | lookup / list | share_dialog_test | dialog theme | no 2.0× suite |

**Duplicates to consolidate** (UX-032 — survivor in bold; the consolidation itself is Phase 3 work):
segmented controls → **one pill `SegmentedTabs`** grown from `ChefPillTabs` (replaces
`_WindowFilter`, the `_SortLink` row and the rail panel's `ChoiceChip`s; `TabBar` and
`SegmentedButton` stay where they are the M3-correct control); rank badges ×3 → **one `RankBadge`**;
kickers ×6 → **`appText.kicker` / `kickerLarge`** (done in 36b); Load more ×2 → **the `RecipeAsyncSliverGrid`
footer**; avatars → **`ChefAvatar`**.

**States are part of the component.** Hover and focus on web are required, not polish: M3 buttons
and `InkWell` supply them; a custom tappable must too (UX-013 is the open instance).

## 5. Patterns

- **Chrome.** Web: `TopNavBar` (destinations + identity only — Gotcha 18) and `LegalFooter(dense:
  true)` in `bottomNavigationBar`. Compact: `NavigationBar` with four slots incl. Profile; legal links
  live on the profile screen and under the sign-up form. `/` is a redirect.
- **Page header.** Kicker (the index line) → serif headline → one line of body in
  `onSurfaceVariant`; left edge shared with the grid's first card (B059 / B123).
- **Shelves.** `NN TITLE` kicker + a rail; an empty shelf says *why* it is empty (Preserve).
- **Paged grid.** Always `RecipeAsyncSliverGrid` — loading / error / empty / grid / load more; never
  hand-rolled (Gotcha 24); every non-grid state in `SliverFillRemaining(hasScrollBody: false)`.
- **Forms.** The editor's grouped ingredient and step lists; validation copy says what to type, not
  what was wrong; errors through `friendlyError()`.
- **Dialogs and sheets.** `useRootNavigator: true` from any shell screen (Gotcha 23); the dialog
  theme gives the 28px corner and the serif title.
- **Attribution.** `SourceCredit`'s four statements, http(s)-only links, the rights sentence
  (Preserve); a fork names its parent (UX-036, open).
- **Cook mode.** Always dark; `appText.step` for the instruction, `appText.clock` for timers; one
  ticker; the alarm is state (CLAUDE.md "Cook mode").

## 6. Accessibility contract (WCAG 2.2 AA → Flutter)

| Criterion | Rule here | Guard |
| --- | --- | --- |
| 1.4.3 / 1.4.11 contrast | 4.5:1 text, 3:1 UI, light and dark | `theme_contrast_test.dart` |
| 1.4.1 colour not only | Difficulty and tier carry a word; errors carry text | review |
| 1.4.4 / 1.4.10 resize, reflow | 2.0× text, no overflow at 390 / 600 / 1000 / 1440 | the envelope suites |
| 2.5.8 target size | ≥ 48dp; container buttons ~48dp | component themes |
| 2.4.7 focus visible | M3 focus on buttons; custom tappables must draw focus (UX-013 open) | manual keyboard pass |
| 2.1.1 keyboard | every control operable (UX-003 / B126 open) | — |
| 4.1.2 name, role, value | `tooltip` on every `IconButton`; `semanticLabel` or `excludeFromSemantics` on images; heading / checked / selected semantics (UX-014, UX-047 open) | review |
| 2.3.3 motion | `AppMotion.of` everywhere; reduced motion collapses to zero | `theme_extensions_test.dart` |

## 7. Token ↔ code map

| Token | Dart symbol | File | Light | Dark |
| --- | --- | --- | --- | --- |
| Seed | `AppTheme.seed` | app_theme.dart | `#D2492A` | same |
| Surface / onSurface | `scheme.surface` / `onSurface` | `_lightScheme` / `_darkScheme` | `#FFFFFF` / `#1F1A17` | `#161616` / `#EDEAE7` |
| Primary / secondary / tertiary | `scheme.primary` / `secondary` / `tertiary` | explicit schemes | `#BE3526` / `#492511` / `#AD4A00` | `#FF8A78` / `#E9C4AE` / `#FFB77A` |
| Hero band / category blocks | `palette.surfaceWarm` / `palette.category(c)` | app_palette.dart | `#FBF7F4` / coral `#FF6449` yellow `#FED801` pink `#FDB5C0` brown `#8C4411` sage `#A8D08D` sky `#9FD3E6` | `#1E1B19` / same blocks |
| Rating | `palette.rating` | app_palette.dart | `#B7700A` | `#F2A93B` |
| Difficulty | `palette.difficultyEasy/Medium/Hard` | app_palette.dart | `#2A6E2E` `#8A4F00` `#9F2B26` | `#66BB6A` `#FFA726` `#FFB4A8` |
| Tiers | `palette.tierHomeCook…tierMasterChef` | app_palette.dart | `#4A626D` `#00695C` `#1360B5` `#6A1B9A` `#8F5000` | `#B0BEC5` `#80CBC4` `#90CAF9` `#CE93D8` `#FFCC80` |
| Photo scrim / control | `palette.scrim` / `imageControl` | app_palette.dart | black 55% / 45% | same |
| Hero | `palette.heroGradient`, `onHero`, `onHeroMuted` | app_palette.dart | `#241A17 → #3B2823 → #5C3B2D`, white, white 70% | same |
| Type ramp | `Theme.of(context).textTheme.*` | app_typography.dart | §3.2 | same |
| Extra type roles | `context.appText.*` | app_typography.dart | §3.2 | same |
| Spacing | `AppSpacing.*` | app_theme.dart | 2 4 6 8 12 16 24 32 48 | — |
| Component insets | `AppInsets.*` | app_theme.dart | §3.3 | — |
| Radii | `AppRadii.*` | app_theme.dart | 6 8 12 16 26 28 999 | — |
| Tints | `AppAlpha.*` | app_palette.dart | §3.1 | — |
| Motion | `AppMotion.*` | app_motion.dart | §3.7 | — |
| Icon sizes | `AppIconSize.*` | app_theme.dart | 14 16 18 20 24 40 56 | — |
| Fonts | `AppFonts.*` | app_typography.dart | Manrope (display resolves to it, v2) | — |

## 8. Do / Don't

**Do** pick a role, a palette field, a spacing step. **Do** check a new or re-used widget at 288px
and at 390 / 600 / 1000 / 1440 × 1.0 and 2.0 (Gotchas 13, 22, 25, 26). **Do** decide a row's
degradation order before writing flex weights (Gotcha 27). **Do** draw a label's underline as a
`BorderSide` (B060).

**Don't** hard-code a hex, a weight, a tracking, a duration or an off-scale number in a widget — pick
or add a token. **Don't** branch on `Brightness` to choose a colour in a widget — that is what
`AppPalette.of` is for. **Don't** put a flex child beside another and expect priority (Gotcha 21).
**Don't** stack a ripple and a press-scale on one control. **Anti-slop:** no default purple/blue
gradients, no glassmorphism, no cards inside cards, no rounded-everything, no decorative blobs, no
stock imagery, no generic centred hero copy, no unmodified M3 defaults presented as a design. The
food photograph carries the page; when there is none, the page is typeset.

## 9. Changelog

- **v1 — 2026-09-25 (Phase 36b).** Direction and principles (owner-approved). Token layer:
  `AppPalette`, `AppTextStyles`, the full `TextTheme` in bundled Newsreader + Manrope, `AppMotion`,
  `AppInsets`, `AppAlpha`, `AppIconSize`, `AppSpacing` half-steps, `AppRadii` additions; component
  themes for every button family, segmented button, FAB, chips, tabs, navigation bar, dialogs and
  snackbars. Fixes: B133 / UX-010 / UX-011 / UX-012 (contrast), UX-031 (type ramp), UX-033 (button
  families), UX-049 (tabular figures, weight jitter), UX-050 (reduced motion). Guards:
  `theme_contrast_test.dart`, `theme_extensions_test.dart`, `apps/app/test/theme_fonts_test.dart`.
  Code review (same day) caught three theme-level regressions before merge, fixed: a colourless
  `ChipThemeData.labelStyle` and `NavigationBarThemeData.labelTextStyle` *replaced* M3's
  state-resolved label colours (white chip labels on native); a theme-wide transparent tab divider
  also removed compact My Recipes' hairline; and light homeCook / masterChef measured 4.4:1 on a
  `Card` (`surfaceContainerLow`), a surface the first contrast test did not measure.

## 10. Drift against the Claude Design system (`_ds_bundle.css`, read 2026-09-25)

> **Resolved 2026-09-25 (Phase 36c, owner-approved write).** `_ds_bundle.css` in the design-system
> project was regenerated from the v2 tokens (explicit schemes, category blocks, Manrope, pills,
> the v3 card as the opt-in `.rcard.v3` beside the legacy v2 card rules so undrawn canvases keep
> rendering), copied into both screens projects' `tokens.css`, and `Discover v3.dc.html` +
> `Recipe Detail v3.dc.html` were drawn from the shipped app. The table below is the v1-era record.

A read-only comparison with the design-system project's `_ds_bundle.css`; nothing was written to
it. The bundle says it "mirrors packages/design_system" — as of this version it does not:

| Token | Repo (source of truth) | `_ds_bundle.css` | Why they differ |
| --- | --- | --- | --- |
| Scheme roles | `fromSeed` on the pinned Flutter 3.44.8: primary `#904B3B`, primaryContainer `#FFDAD2`, surfaceContainerLow `#FFF0ED` | `#8F4C38`, `#FFDBD1`, `#FFF1ED` | The bundle was generated by an older colour utility; 1–3 per channel |
| Card fill | M3 `Card` default, `surfaceContainerLow` | `.card` / `.rcard` on `surfaceContainerLowest` (white) | The bundle is wrong about the app |
| Rating (light) | `#B7700A` | `#F2A93B` in both | B133 / UX-011 |
| Difficulty (light) | `#2A6E2E` `#8A4F00` `#9F2B26` | `#43A047` `#F57C00` `#BA1A1A` | B133 / UX-010 |
| Tiers (light) | home `#4A626D`, sous `#1360B5`, master `#8F5000` | `#546E7A`, `#1565C0`, `#B26500` | B133 (the chip label on its wash) |
| labelSmall | 700, +0.2 | 600, +0.02em | Kitchen-proof: the smallest text in the product |
| Line heights | M3 (display-sm 44, headline-sm 32, title-md 24) | 1.14 / 1.25 / 1.4 (41 / 30 / 22.4px) | The repo keeps M3's so the envelope maths stays put |
| Mono face | none — `appText.kicker` stands in | `--font-mono` ui-monospace | Two bundled families only (owner decision) |
| Missing from the bundle | `AppSpacing` xxs / xsPlus / smPlus, `AppRadii` sm / chip / hero / dialog, `AppInsets`, `AppAlpha`, `AppMotion`, hero + foil palette, `appText` roles | — | New in 36b |

Updating the bundle to match is a separate, owner-approved write (a `DesignSync` plan), not part of
this phase.
- **v2 — 2026-09-25 (Phase 36c, reference rebuild: Discover, Recipe detail, chrome).** Five owner
  references (bright category grid, cream editorial home, dark kitchen phone, bright recipe app) →
  §0. Owner decisions Q1–Q6 in [REBUILD-LOG.md](REBUILD-LOG.md): colour-block no-photo cover,
  Manrope only, tomato + brown + orange, open detail panels, neutral dark, a real category filter.
  Fidelity loop: Discover 8.35, Recipe detail 8.5 (pass ≥ 8.0) after one fix (the card's colour-block
  label collided with the chef badge at 390px). Code review fixes: a stale-page race in
  `PagedRecipesNotifier` (B135), neighbouring card titles misaligned by the description's line
  count, one category mapping instead of two, panel ink restored.
