# Reference 2 + 3 — cream editorial home, web (2026-09-25)

**Source:** pasted by the owner; originals (git-ignored) `.playwright-mcp/references/2026-09-25/2.png`
(899 × 1034, above the fold) and `3.png` (394 × 988, the whole page, small).
**Surface:** Discover (web, expanded). **Theme:** light. **State:** populated, signed in (avatar).
**Owner's note:** "style like this"; fonts are not the point.

## 1. Scale anchor
Card width 170 image px; four cards plus gutters span ~770 px of an ~1440 logical page →
ratio ≈ 1.6 logical px per image px (**E**). Ref 3 is the same page at ≈ 0.27.

## 2. Skeleton
```
┌ hero band (cream, full bleed) ──────────────────────────────────────────────────────────┐
│ wordmark                              [search pill] [Share Recipe ●] (avatar) (≡)        │
│ DISPLAY HEADLINE, 2 lines              ┌──────── food photo, bleeds off the right ─────┐ │
│ one-line strapline                     │                                              │ │
│ [search pill ────────] (●)             └──────────────────────────────────────────────┘ │
│ social icons                                                                            │
├ "Best Recipe Of The Week" ─ 4 cards: photo 4:3 · rank ribbon · 5/5★ chip · author · counts ┤
├ "Today Popular Recipes" ─ 4-col grid, 2 rows: photo · meta chips · ★★★★ · title · [Load more] ┤
├ "Tips And Tricks" 3-up · "Blogs And News" 2-up                                           ┤
└ footer: dark brown band — wordmark, links, newsletter field, socials                     ┘
```

## 3. Type
| Role seen | Class | Size (E) | Weight | Maps to |
| --- | --- | --- | --- | --- |
| Hero headline | display serif, high contrast | ~64 | 400 | `displayLarge` |
| Section heading | geometric sans | ~22 | 700 | `headlineSmall`, bold |
| Card title | sans | ~16 | 700 | `titleMedium` |
| Author, counts | sans | ~11 | 500 | `labelSmall`, tabular |
| Buttons | sans | ~13 | 700 | `labelLarge` |

## 4. Color
| Sample | Value | Tag | Maps to |
| --- | --- | --- | --- |
| Hero band | `#FBF7F4` | M | new `surfaceWarm` (a cream section surface) |
| Body page | `#FFFFFF` | M | `surface` |
| Ink (headings, buttons) | `#442418` / `#492511` | M | `onSurface` → a deep brown ink; filled button `secondary` |
| Footer band | `#53250B` | M | `inverseSurface`-like brand band |
| Rank ribbon | `#F2CF3B` | M | `AppPalette.rankRibbon` (dark text on it) |

## 5. Shape & depth
Photos radius ~8 (E); buttons and the search field are **pills**; cards have no border and no
fill. Ribbon: a flag shape hanging from the photo's top-left.

## 6. Density
Generous: section gap ~80 (E), 4 columns at 1440 with ~24 gutters.

## 7. Imagery & icons
Hero food photo bleeds off the right edge on the cream band. Card photos 4:3. Rank ribbons 1st–4th.
Heart + bookmark icons top-right on photos (outline, white).

## 8. Components
Hero band → Discover masthead (restyle: cream band, big headline, pill search) · rank ribbon →
maps to our ranked shelves (MOST FORKED is ranked) · meta chips → card footer · Load more → the
`RecipeAsyncSliverGrid` footer (exists) · footer band → `LegalFooter`/`SiteFooter` (restyle).

## 9. Out of scope / unknowable
"Share Recipe" CTA (we have New recipe), social links, blog/tips sections, newsletter —
not in the product (**reject** unless asked). Dark theme, phone width, states: from DESIGN.md.
