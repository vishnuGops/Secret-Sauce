# Reference 4 — dark kitchen, phone (2026-09-25)

**Source:** pasted by the owner; original (git-ignored) `.playwright-mcp/references/2026-09-25/4.png`
(630 × 616, two phones). **Surfaces:** Discover (compact) and Recipe detail (compact).
**Theme:** dark. **State:** populated.

## 1. Scale anchor
Each phone screen ≈ 262 image px wide ↔ 390 logical → ratio ≈ 1.49 (**E**).

## 2. Skeleton
Home: wordmark (2 lines, serif) + text nav → per-category **horizontal rails** ("Main Dish",
"Side Dish", "Wine Pairings"), each a row of tall photo cards (~3:4) with the **title set over the
photo** on a bottom gradient, plus a one-line tag/meta under it.
Detail: full-bleed photo (radius ~8 inside the frame) with Save / Share over its bottom-left →
centred serif title (2 lines) → tag line → author row (avatar, name, bio) → `DESCRIPTION` →
`INGREDIENTS` bulleted list.

## 3. Type
| Role seen | Class | Size (E) | Weight | Maps to |
| --- | --- | --- | --- | --- |
| Wordmark / detail title | didone serif | ~28 / ~22 | 400 | `headlineMedium` / `headlineSmall` |
| Rail heading | sans | ~13 | 500 | `titleSmall` |
| Card title over photo | serif | ~15 | 600 | `titleMedium`, on scrim |
| Section kicker `INGREDIENTS` | sans caps, tracked ~1.5 | ~12 | 700 | `appText.kicker` — **our index line, already built** |
| Body / ingredients | serif body | ~13 | 400 | `bodyMedium` |

## 4. Color
| Sample | Value | Tag | Maps to |
| --- | --- | --- | --- |
| Page | `#1A1A1A` (detail), `#161618` (outer) | M | dark `surface` → **neutral** near-black |
| Text | off-white | E | dark `onSurface` |
| Divider under title | ~`#444` hairline | E | `outlineVariant` |

No accent colour at all: the photographs are the colour.

## 5–7. Shape, density, imagery
Cards radius ~8, no borders; photo scrim gradient from the bottom. Dense rails (card ~120 × 160
logical, gap ~10). Outline icons.

## 8. Components
Rails → Discover shelves (exist, `CardRail`) · title-over-photo card → a `RecipeCard` **variant**
for rails · detail author row → `ChefBadge` / chef identity (exists) · section kickers → exist.

## 9. Unknowable
Light theme counterpart, web width, hover. The current app's dark theme is brown-tinted
(`#1A110F`); this reference argues for neutral.
