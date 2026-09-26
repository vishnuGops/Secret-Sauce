# Reference 1 — bright category grid, web home (2026-09-25)

**Source:** pasted by the owner; original kept (git-ignored) at
`.playwright-mcp/references/2026-09-25/1.png` (1024 × 768, a tilted browser mockup).
**Surface:** Discover (web, expanded). **Theme:** light. **State:** populated, signed out.
**Owner's note:** "I want the style to be something like this" (all five references together);
"font is not important, use something basic for now".

Tags: **M** measured (pixel-sampled), **E** estimated, **G** guessed.

## 1. Scale anchor
The page is drawn in perspective, so every size is **E**. The search field (~42 image px tall) is
taken as a 48dp input → ratio ≈ 1.15 logical px per image px at the page centre.

## 2. Skeleton
```
┌ top bar: logo | location picker | search field (wide) | Cuisines ▾ | My Cart | [Login/Signup] ┐
├ hero carousel: full-width photo banner (radius ~16) · serif headline · white CTA · ‹ › · dots ┤
├ category tiles: 4 across, equal width, solid colour blocks + cut-out food photo + "View More" ┤
├ "Trending Recipes" heading ─────────────────────────────────────────────── › (scroll arrow) ┤
└ photo cards: 5+ across, horizontal rail; photo (≈4:5, radius ~12) · title below, 2 lines     ┘
```
Content column ≈ 1300 logical px, left-aligned headings share the card grid's left edge (E).

## 3. Type
| Role seen | Class | Size (E) | Weight | Maps to |
| --- | --- | --- | --- | --- |
| Hero headline | high-contrast serif | ~48 | 600 | `displayMedium` (family per owner: basic) |
| Tile title | geometric sans | ~22 | 800 | `titleLarge`, bold |
| Section heading "Trending Recipes" | serif-ish | ~24 | 500 | `headlineSmall` |
| Card title | humanist sans | ~15 | 500 | `titleSmall` / `bodyLarge`, 2 lines |
| Time pill "20 min" | sans | ~11 | 600 | `labelSmall`, tabular |
| Nav links | sans | ~14 | 500 | `labelLarge` |

## 4. Color
| Sample | Value | Tag | Maps to |
| --- | --- | --- | --- |
| Page | `#FDFDFD` | M | `surface` (neutral white — no pink tint) |
| Primary CTA / brand red | `#E54A3A` | M | `primary` family (white text on it ≈ 3.9:1 → fails 4.5 for 14px) |
| Tile yellow / coral / pink / brown | `#FED801` / `#FF6449` / `#FDB5C0` / `#8C4411` | M | new `AppPalette` category colours |
| Time pill | white on photo | M | `surfaceContainerLowest` @ ~92% |
| Text | near-black | E | `onSurface` |

## 5. Shape & depth
Photos radius ~12 (E), hero ~16, tiles ~12, buttons ~6 (square-ish), pills fully round. No card
borders; cards are photo + text on the page. No shadows except the carousel arrows.

## 6. Density
Base unit ≈ 8. Tile gap ~20, card gap ~16, section gap ~40 (E).

## 7. Imagery & icons
Food photography carries every card and tile; tiles use **cut-out** food on a flat colour.
Heart in a white circle top-right of each photo; time pill bottom-left. Outline icons.

## 8. Components
Top bar → `TopNavBar` (restyle) · hero carousel → **new** (needs featured recipes + photos) ·
category tile → **new** · card → `RecipeCard` (restyle: photo-first, title below) · heart → like
toggle (exists on detail only) · time pill → card meta (exists in the footer today).

## 9. Out of scope / unknowable
Location picker, "My Cart", "Order Now" — a commerce product, not ours (**reject**). Hover, focus,
2.0× text, phone width, dark theme: designed from DESIGN.md rules.
