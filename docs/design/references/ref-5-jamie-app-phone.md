# Reference 5 — bright recipe app, phone (2026-09-25)

**Source:** pasted by the owner; original (git-ignored) `.playwright-mcp/references/2026-09-25/5.png`
(1413 × 1255, five phone fragments). **Surfaces:** Recipe detail (compact), Discover/home
(compact), bottom navigation. **Theme:** light. **State:** populated.

## 1. Scale anchor
Status bar "9:41" row and the 24px nav icons → phone width ≈ 400 image px ↔ 390 logical →
ratio ≈ 0.98 (**M**-ish; treat sizes as logical).

## 2. Skeleton (detail)
```
┌ photo, full bleed, ~4:3 ─────────────── floating square actions (★ share print) on the right ┐
├ white sheet, top radius ~28, overlaps the photo ────────────────────────────────────────────┤
│ RECIPE (kicker, accent)                                                                     │
│ Flaky pastry pesto chicken (title)                                                          │
│ With roasted cherry tomatoes & green beans (subtitle, grey)                                 │
│ COOKS IN      SERVES      DIFFICULTY   (caps labels, grey)                                  │
│ 30 min        4           Not too tricky (values)                                           │
│ (Chicken) (Chicken breast) (Lunch)   accent pill tags                                       │
│ Nutrition per serving                                                                       │
│ [Calories 31% | 618] [Fat 50% | 34.8g] [Protein …]  → horizontal cards, pager dots         │
│ [ Ingredients              ▾ ]   accordion panel, light grey, radius ~16                    │
│ [ Method                   ▾ ]   (open: accent bullets / accent step numbers)               │
└ bottom nav: 5 destinations, active in accent ──────────────────────────────────────────────┘
```
Home: wordmark (green) + search/settings icons → `VIDEO` kicker → large rounded photo card →
`LATEST VIDEOS` rail → `PLAYLISTS` rail.

## 3. Type
| Role seen | Class | Size | Weight | Maps to |
| --- | --- | --- | --- | --- |
| Kicker `RECIPE` / `LATEST VIDEOS` | sans caps, tracked | ~14 | 700, accent | `appText.kickerLarge` in accent |
| Title | sans | ~20 | 600 | `titleLarge` (sans) |
| Subtitle | sans | ~17 | 400, grey | `bodyLarge`, `onSurfaceVariant` |
| Fact label `COOKS IN` | sans caps | ~12 | 500, grey | `appText.overline` |
| Fact value | sans | ~17 | 500 | `titleMedium` |
| Nutrition number | sans | ~22 | 600, accent | `appText.statLarge` in accent |
| Accordion heading | sans | ~18 | 500 | `titleMedium` |
| Method step number | sans | ~16 | 600, accent | `titleSmall`, tabular |

## 4. Color
| Sample | Value | Tag | Maps to |
| --- | --- | --- | --- |
| Outer page | `#F5F9FC` | M | a cool light page (vs the sheet) |
| Sheet / cards | `#FFFFFF` | M | `surfaceContainerLowest` |
| Accent orange (kickers, chips, numbers, nav) | `#E98C3B` | M | accent — **white on it ≈ 2.4:1, orange text on white ≈ 2.4:1: fails AA** |
| Brand / action green | `#2AAE88` | M | secondary action (white on it ≈ 2.7:1 — fails) |
| Accordion panel | ~`#F3F5F7` | E | `surfaceContainer` |
| Labels grey | ~`#8A8A8A` | E | `onSurfaceVariant` |

## 5. Shape & depth
Sheet top radius ~28; accordion and nutrition cards ~16; tag pills fully round and **filled**;
action buttons ~10 square; nutrition cards carry a soft shadow; no borders anywhere.

## 6. Density
Base 8; sheet padding ~24; fact columns ~120 wide; tag gap ~10.

## 7. Imagery & icons
Full-bleed photo under a rounded sheet. Outline icons (Material Symbols-like), filled when active.

## 8. Components
Sheet over photo → `recipe_detail_compact.dart` (restyle: cover + overlapping sheet) · facts row →
the compact facts quad (exists; restyle to label-over-value) · pill tags → cuisine/category chips
(new visual; data: `cuisine`, `category`) · nutrition cards → **new** summary row above the FDA
label (`NutritionFactsLabel` stays — Preserve) · accordions → CONFLICT (the rail + method column,
the jump bar) · accent step numbers → `method_column.dart` (exists) · bottom nav → `NavigationBar`
(restyle active colour).

## 9. Unknowable
Web width, dark theme, hover/focus, 2.0× text (the three fact columns will wrap).
