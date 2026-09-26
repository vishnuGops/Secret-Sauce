# Rebuild log — Phase 36c (reference rebuild)

Phase 3 of the `ui-overhaul` skill. Inputs: [DESIGN.md](DESIGN.md) v1, [AUDIT.md](AUDIT.md) (the
Preserve list), and the owner's references. Each run appends a dated section; nothing is deleted.

## 2026-09-25 — intake

**References** (originals git-ignored under `.playwright-mcp/references/2026-09-25/`, written up in
[references/](references/)):

| # | Spec | Surface | Viewport / theme |
| --- | --- | --- | --- |
| 1 | [ref-1-bright-grid-web.md](references/ref-1-bright-grid-web.md) | Discover (web) | ~1440, light |
| 2, 3 | [ref-2-cream-editorial-web.md](references/ref-2-cream-editorial-web.md) | Discover (web) + footer | ~1440, light |
| 4 | [ref-4-dark-kitchen-phone.md](references/ref-4-dark-kitchen-phone.md) | Discover + detail (phone) | 390, dark |
| 5 | [ref-5-jamie-app-phone.md](references/ref-5-jamie-app-phone.md) | Detail + home + nav (phone) | 390, light |

**Owner's brief:** "I want the style to be something like this. Font is not important, use
something basic for now, we can change the font as needed later." No per-image note, so the
whole look is the point. The qualities the four sources share are the brief:

1. **Photo-first cards with no chrome** — a rounded photo, the title under it, small overlays on
   the photo (time, like, rank). No borders, no banners.
2. **Bright, neutral pages** — white or near-white, with one warm cream band for the hero (2), a
   cool grey page behind white sheets (5). The pink-tinted M3 tonal surfaces go.
3. **One saturated warm accent plus a deep ink** — tomato red (1), deep brown (2), orange (5).
4. **Playful colour blocks** — ref 1's yellow / coral / pink / brown category tiles.
5. **Accent kickers** (`RECIPE`, `LATEST VIDEOS`, `INGREDIENTS`) — our index line, now in colour.
6. **Pills** — pill buttons (2), filled pill tags (5).
7. **Recipe detail as a sheet over the photo** (5), with label-over-value facts, tag pills and
   nutrition summary cards.
8. **A neutral dark mode** (4) — near-black, the photos as the only colour.

**Seed-data fit (CLAUDE.md, mandatory).** These references are carried by food photography, and
the fixtures have none: **0 of 14 curated recipes has a cover** (`recipeData/` has no image field
in its authoring format at all), and the corpus's photos are hotlinks the rights position does not
cover (UX-029). Categories exist on every curated recipe (`Main` 7, `Dessert` 3, `Breakfast`,
`Appetizer`, `Salad`, `Drink` 1 each) and on the corpus, so category tiles have data. Tags: none.
**Decision needed before building — Q1.**

## Delta table (proposed; decisions marked → Qn wait on the owner)

Decision: **adopt** · **adapt** (how) · **reject** (which rule) · **→ Qn** (conflict, asked one at a time).

### Tokens
| Token | Current | Reference | Decision | Conf. | Cites |
| --- | --- | --- | --- | --- | --- |
| Font families | Newsreader (display) + Manrope (UI), bundled | "basic for now" | **→ Q2** | — | owner |
| `primary` (light) | fromSeed paprika → `#904B3B` (muted brick) | tomato `#E54A3A` (1) | adapt: **`#C8372A`** — same hue, 5.2:1 with white (the reference is 3.9:1) | M | ref-1 §4 |
| `surface` (light) | `#FFF8F6` (pink tint) | `#FDFDFD` / `#FFFFFF` (1, 2, 5) | adopt: neutral white | M | ref-1/2/5 §4 |
| `surfaceContainer*` (light) | pink tonal steps | neutral warm greys, `#F3F5F7` panels (5) | adopt: neutral steps | E | ref-5 §4 |
| Section band | — | cream `#FBF7F4` (2) | adopt: new `palette.surfaceWarm` | M | ref-2 §4 |
| Ink / `onSurface` | `#231917` | deep brown `#442418` for headings (2) | adapt: warm near-black ink stays for body; brown `#492511` as `secondary` (filled secondary button, footer) | M | ref-2 §4 |
| Accent (kickers, step numbers, nutrition figures) | primary | orange `#E98C3B` (5) — 2.5:1 on white | adapt: **`#B54E00`** text-safe orange (5.2:1); the bright orange only as a fill under dark ink | M | ref-5 §4 |
| Category colours | — | yellow `#FED801`, coral `#FF6449`, pink `#FDB5C0`, brown `#8C4411` (1) | adopt as `palette.category*` with an `on` colour each (dark ink on the first three, white on brown — all ≥ 5.8:1) | M | ref-1 §4 |
| Rank ribbon | — | `#F2CF3B` + dark ink (2) | adopt: `palette.rankRibbon` (11:1) | M | ref-2 §4 |
| Dark theme | brown-tinted `#1A110F` | neutral `#1A1A1A` (4) | **→ Q5** | M | ref-4 §4 |
| `AppRadii.button` | 12 | pill (2), ~10 (5), ~6 (1) | adapt: **pill** for buttons and chips (two of three sources pill their CTAs and tags) | E | |
| Photo radius | card 16 (whole tile) | ~12 on the photo itself (1, 2) | adopt: 16 on the photo, the tile has no chrome | E | |
| Sheet radius | — | ~28 top corners (5) | adopt: `AppRadii.dialog` 28 | E | ref-5 §5 |
| Card chrome | `outlineVariant` border + fill | none (1, 2, 4, 5) | adopt: no border, no fill — photo + text on the page | M | |
| Shadows | borders only | soft shadow on floating cards (5) | adapt: shadow only on overlays that float over a photo | E | DESIGN §3.5 |

### Components
| Component | Current | Reference | Decision | Cites |
| --- | --- | --- | --- | --- |
| `RecipeCard` | banner title over a cover, fixed 352 tile | photo on top, title under it, overlays on the photo | adapt: photo first (the one flexible band), time pill + chef on the photo, title band **below** (still a fixed 65 × scale band), meta row. **Preserve kept:** fixed height, one flexible band, capped banner | Preserve · Gotcha 13 |
| `RecipeCard` without a photo | utensil icon on a flat surface | — (every reference has photos) | **→ Q1** | UX-034 |
| Rail card (shelves, compact) | same card | tall photo with the title on a scrim (4) | adapt: a `RecipeCard` variant for rails only; the grid keeps title-below | ref-4 §2 |
| Rank marker | none on cards | ribbon 1st / 2nd … (2) | adopt on the ranked shelf (`03 MOST FORKED`) | ref-2 §7 |
| Tag pills | none on cards; detail shows cuisine as text | filled accent pills (5) | adopt on detail (cuisine, category): accent-container fill + text-safe accent ink | ref-5 §8 |
| Nutrition summary | FDA label only | 3 summary cards (kcal, fat, protein + %DV) (5) | adopt: a summary row **above** the FDA label; the label stays (Preserve) | ref-5 §8 |
| Buttons | 12px rounded rect, ~48dp | pills | adopt via the button themes (one token) | |
| Bottom nav | M3 secondaryContainer pill | accent active colour (5) | adopt | ref-5 §8 |
| Top nav (web) | pill of destinations + identity | search field + links + CTA in the bar (1, 2) | reject search in the bar: Gotcha 18 — search lives in Discover's bar, and a wider row cost the other destinations their labels at medium. Adopt the look: white bar, tomato CTA pill | Gotcha 18 |
| Web footer | dense legal row | dark brown band with links (3) | adapt: brown-ink row, stays one line — it is chrome in `bottomNavigationBar`, a tall band eats the viewport | Gotcha 14 |

### Screens
| Screen | Decision | Cites |
| --- | --- | --- |
| Discover masthead | adapt ref 2's hero: cream band, large headline, strapline, pill search. The right-hand photo appears only when a featured recipe has a cover (no stock imagery) | ref-2 §2 |
| Discover categories | ref 1's colour-block tiles, one per category → **→ Q6** (new behaviour: filtering by category) | ref-1 §2 |
| Discover shelves | horizontal rails of photo cards (1, 4); `03 MOST FORKED` gets rank ribbons (2); headings keep the numbered index line, in the accent | ref-1/2/4 |
| Recipe detail (compact) | ref 5: photo full bleed, sheet with 28px top corners over it, accent kicker, title, label-over-value facts, tag pills, nutrition summary, method with accent step numbers. Ingredients and method → **→ Q4** | ref-5 §2 |
| Recipe detail (expanded) | the same language at 1140px: photo left, sheet-like header right, facts and tags; rail + method below | — |
| Cook mode | unchanged layout, always dark; picks up the neutral dark palette if Q5 says so | Preserve |
| Chefs, My Recipes, editor, auth, profile | inherit tokens + component themes; no bespoke redesign in this pass | — |

### Rejected outright (not our product)
Location picker, cart, "Order Now" (1); video, playlists, print (5); blog, tips, newsletter, social
links (2, 3). Floating square action buttons (5) become round over-photo buttons (like, save,
share) on compact detail.

## 2026-09-25 — conflicts resolved (owner, one at a time)

| Q | Conflict | Decision |
| --- | --- | --- |
| Q1 | Photo-led references vs 0/14 curated covers | **Designed colour-block cover**: a no-photo card/detail cover is a flat block from the recipe's category colour with the dish name set large; a real photo replaces it automatically |
| Q2 | Font | **Manrope for everything**; Newsreader removed from the bundle (headings get weight, not a second family). Revisit later — a family is one token |
| Q3 | Palette | **Tomato + brown + orange**: primary `#C8372A`, secondary `#492511`, text-safe accent `#B54E00` (bright `#E98C3B` only under dark ink), ref 1's category blocks, cream `#FBF7F4` hero band, white pages |
| Q4 | Detail accordions (ref 5) vs principle 1 | **Open panels in ref 5's styling**; jump bar and the pinned "Ready to cook?" bar stay (Preserve) |
| Q5 | Dark mode | **Neutral near-black** (ref 4); cook mode follows |
| Q6 | Category tiles | **Tiles + a real category filter** on Discover (`/discover?category=…`, paged, tie-broken, clear chip) |

Claude Design MCP reconnected after the owner's `/design-login` (2026-09-25): the three Secret Sauce
projects are readable. No writes without asking.

## 2026-09-25 — build

Layers in order, `melos run analyze` + `melos run test --no-select` green after each:

| Layer | Commit | What |
| --- | --- | --- |
| 1 Tokens | `4f24f09` | Explicit light/dark schemes, palette (hero band, category blocks, ribbon), Manrope only, pill buttons/chips, borderless tonal cards, tomato nav |
| 3 Primitives | `13cc6b5` | RecipeCard v3, CategoryCover, TagPill, NutritionSummary, CategoryTile |
| 4–5 Chrome + screens | `acb5693` | Discover (masthead, category filter, ranked shelf), Recipe detail (sheet over cover, panels), top bar / footer |
| Fidelity fix | `80fa803` | Card colour-block label to a corner (collided with the chef badge) |
| Review fixes | `b8d2792` | Paging generation guard (B135), description reservation, one category mapping, panel ink |

Contract changes (each commented at the test site): nav active colour is tomato; the card's title
band is measured from its own top (it moved under the cover); the 3.0× cover check measures the
colour block; RailPanel is a panel on compact too; the method heading is the `METHOD` kicker; the
detail kicker is always `RECIPE`; the compact detail test viewport is 390×1200 so below-the-fold
panels build under the test font; the Desserts / Starters / Salads groups gained spellings.

## 2026-09-25 — fidelity loop

Captures: `.playwright-mcp/captures/rebuild-2026-09-25/` (git-ignored), release web build against the
**local stack** (14 curated recipes, 0 covers, 21,314 corpus rows, zero engagement — B113).

| Surface | Iter. | Layout .30 | Type .20 | Colour .20 | Craft .20 | Behaviour .10 | Weighted | Gates |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Discover | 1 | 8.5 | 7.5 | 8.5 | 6.5 | 10 | 8.05 | fail: card label under the chef badge at 390 (`discover-390`) |
| Discover | 2 | 8.5 | 7.5 | 8.5 | 8 | 10 | **8.35** | green (`p2-discover-*`, dark included) |
| Recipe detail | 1 | 9 | 7.5 | 8.5 | 8 | 10 | **8.5** | green (`detail-390-full`, `detail-1440`, `p2-detail-390-dark`) |

Type is held at 7.5 by the owner's "basic for now" font call, not by a defect; the references set
display serifs. Cook mode (`p2-cook-390`) keeps its layout and picks up the neutral dark scheme.
Not captured: Chefs, My Recipes, editor, auth, profile — they inherit tokens and component themes
with no bespoke redesign in this pass.

## 2026-09-25 — Claude Design

Owner-approved writes: `_ds_bundle.css` (design-system project) regenerated from the v2 tokens;
`tokens.css` in both screens projects replaced by it; `Discover v3.dc.html` and
`Recipe Detail v3.dc.html` added to both (the v2 canvases stay as history). Discover v3 verified by
rendering it.
