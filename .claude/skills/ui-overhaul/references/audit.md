# Phase 1 — UI/UX Audit

Read-only against code. Output: `docs/design/AUDIT.md`.

## Posture (from ECC `gan-evaluator`)

Be strict. A passing score means *a professional would ship this*, not *good for an AI*.

- No "solid foundation", no "overall good effort" — that is cope, not evidence.
- Do not talk yourself out of an issue you found. Do not score potential.
- Every issue has a **how-to-fix** naming the element, file and value
  (not "spacing feels off" but "`<file>:<line>` uses `EdgeInsets.all(18)`, off the 8pt scale;
  use `AppSpacing.md`").
- Quantify where possible ("7 of 19 `IconButton`s have no `tooltip`").
- Acknowledge what genuinely works — it becomes the **Preserve** list.

## Step 1 — Surface inventory

List every routed surface from `apps/app/lib/routing/app_router.dart` and the feature map in
CLAUDE.md: `/discover`, `/explore`, `/chefs`, `/chef/:id`, `/entity/:id`, `/my`, `/recipe/:id`,
`/recipe/:id/cook`, `/recipe/new` + `/edit`, `/profile`, `/auth`, `/legal/:doc`. Note the shell
(web top bar + `LegalFooter(dense: true)` vs compact `NavigationBar`), and which surfaces need
sign-in (`needsAuth`).

## Step 2 — Static sweep (code)

Run with the Grep tool over `apps/app/lib` and `packages/design_system/lib` (`--include=*.dart`).
Record counts **and** the worst offenders by file. Baseline counts taken 2026-09-24 are in
parentheses so a re-audit can show movement.

| Signal | Pattern | Why it matters |
| --- | --- | --- |
| Raw palette colors | `Colors\.[a-z]` (21) | bypasses `ColorScheme`; usually wrong in dark mode |
| Hex literals outside the theme | `Color\(0x` (14; `chefs_hero.dart`, `chef_spotlight_card.dart`, `tier_chip.dart`) | an unnamed color is an untokened color |
| Alpha tweaks | `withOpacity\|withValues\(alpha` (28) | often hand-made tints the scheme already has (`surfaceContainer*`, `onSurfaceVariant`) |
| Weight overrides | `FontWeight\.` (79) | the type ramp is not carrying hierarchy if call sites keep re-bolding |
| Raw font sizes | `fontSize:` (2) | a size outside the ramp |
| Raw spacing | `EdgeInsets\.[a-z]*\([^)]*[0-9]` (33), `SizedBox\((height\|width): [0-9]` | off the 8pt `AppSpacing` scale |
| Raw radii | `BorderRadius\.circular\([0-9]` (15) | off `AppRadii` |
| Raw motion | `Duration\(milliseconds` (7), `Curves\.` (2) | no motion tokens exist yet |
| Shadows | `BoxShadow\(` (2) | elevation policy (border vs shadow) undefined |
| Tap targets w/o semantics | `GestureDetector\(` (1), `InkWell\(` (20) | custom tappables need a role + label |
| Icon buttons vs tooltips | `IconButton\(` (19) vs `tooltip:` (32 total, incl. other widgets) | icon-only buttons are invisible to screen readers without a label |
| Semantics coverage | `Semantics\(` (3), `semanticLabel` (0), `ExcludeSemantics`, `MergeSemantics` | images and composite rows have no accessible name |
| Theme usage (healthy) | `textTheme\.` (226), `colorScheme\.` (21) | ratio vs raw usage is the headline consistency number |
| Numbers that tick | timers, counts, scores without `FontFeature.tabularFigures()` | digits jitter as they change (cook-mode timers, chef scores) |
| Reduced motion | any `Animated*` / `AnimationController` without `MediaQuery.disableAnimationsOf` | motion that cannot be turned off |

Then read, not grep: `app_theme.dart` (what the theme already styles — cards, filled buttons,
inputs — and what it leaves to M3 defaults), `state_views.dart` (loading/empty/error ladder),
`recipe_card.dart` (the most-seen component), the three largest screens per feature.

## Step 3 — Visual sweep (live)

Follow SKILL.md "Verification commands". Matrix per surface:

| Axis | Values |
| --- | --- |
| Width | 390 (phone), 600 (compact/medium edge), 1000 (medium/expanded edge), 1440 (desktop) |
| Theme | light, dark (dark = pin `themeMode`, rebuild, revert) |
| State | signed out; signed in where the surface differs; empty; loading if observable |

Text scale 2.0× cannot be set from the browser — it is covered by the widget-test envelope suites
(`recipe_card_test`, `recipe_detail_test`, `cook_mode_test`, `top_nav_bar_test`, …). Run
`melos run test --no-select` and cite the suites; do not claim a 2.0× visual check you did not do.

Open each capture with the Read tool and look for: alignment breaks, orphaned elements, inconsistent
radii, missing hover/focus/pressed states (web), ellipsized names that should wrap (B032),
pluralization (`1 recipes`, B031), modal chrome not dimmed (Gotcha 23), dead space from 50/50 flex
splits (Gotcha 21), empty surfaces that look broken rather than empty.

**Seed-data caveat:** say which database the captures came from. After `db:reset` the chefs board
and engagement counters are empty *on purpose* (B113). Score an empty board on its empty state,
not on missing data.

If the app cannot be built or served, drop to `screenshot` mode (user captures, existing
`.playwright-mcp/captures/*.png`) or `code-only`, and **say so in the report header**.

## Step 4 — UX journeys (from ECC `product-lens` + `click-path-audit`)

Walk each journey, count steps/taps, note every friction point, dead end, or state that lies:

1. Cold start → Discover → open a recipe → scale servings → start cook mode → run a timer → finish.
2. Search for a dish → no results → recover.
3. Sign up → confirm → create a recipe (ingredients in groups, steps with timers, photo) → save.
4. Fork someone's recipe → edit → view version history → see attribution to the original.
5. Browse chefs → open a chef → switch All / Popular / Trending → open an entity page.
6. Signed-out reader on a phone → reach Privacy/Terms/Rights (the legal-footer split exists for this).

Time-to-value = steps from cold start to reading the first full recipe. For each click that changes
state, check the state actually changes everywhere it is shown (the `click-path-audit` lesson:
cook mode and the reading page share `selectedServingsProvider` for exactly this reason — B066).

## Step 5 — Score (12 dimensions, 0–10)

Calibration (ECC `gan-evaluator`): **1–3** broken/embarrassing · **4–5** functional but
templated/AI-generic · **6** decent, unremarkable, missing polish · **7** solid junior work ·
**8** professional, some rough edges · **9** senior, polished · **10** ship-grade, distinctive.

| # | Dimension | Weight | What earns a high score here |
| --- | --- | --- | --- |
| 1 | **Recipe legibility** | 2 | Ingredients/steps scannable mid-cook: groups, quantities, timers, temperatures read at arm's length; structure is *the* product (CLAUDE.md) |
| 2 | Typography hierarchy | 1 | Ramp roles carry hierarchy without per-call-site weight overrides; numerals tabular where they tick |
| 3 | Color system | 1 | Everything from scheme roles/tokens; accent used with intent; contrast passes in both themes |
| 4 | Spacing & layout rhythm | 1 | 8pt scale; consistent page gutters; grid alignment with headers (B123) |
| 5 | Shape & depth | 0.5 | Radii from tokens, concentric where nested; one policy for border vs shadow |
| 6 | Component consistency | 1 | Same concept → same widget → same look (chips, pills, badges, empty states) |
| 7 | Responsive & envelope | 1.5 | Holds at 390/600/1000/1440 × 1.0/2.0 with no overflow, no dead split space |
| 8 | Dark mode | 0.5 | Complete, not inverted-light; imagery and elevation still read |
| 9 | Accessibility | 2 | WCAG 2.2 AA: contrast, 48dp targets, labels, focus order/visibility on web, color-not-only, text scaling |
| 10 | States & feedback | 1 | Loading/empty/error/success for every async surface; `friendlyError()` copy; optimistic actions confirm |
| 11 | Motion | 0.5 | Purposeful (attention / state / continuity) or absent; reduced-motion honored |
| 12 | Identity (anti-slop) | 1 | Looks like a recipe vault with a point of view, not an M3 seed demo |

Overall = Σ(score × weight) / Σ(weight). Report both the table and the number; the number is a
trend line across re-audits, the table is the work list.

**Slop tells** (ECC `design-system` Mode 3 + `gan-generator`), each a finding if present:
default M3 look with only a seed color changed; gradient backgrounds; glass cards; identical card
grids everywhere regardless of content; rounded-everything; decorative illustrations standing in
for food photography; generic "Welcome to …" hero; one-hue palette.

## Step 6 — Findings

Severity: **Critical** (overflow, inaccessible control, lying state, broken journey) · **Major**
(inconsistency a user notices, missing state, contrast fail on secondary text) · **Minor** (polish).

One row each: `ID | severity | dimension | evidence (path:line or capture) | mechanism | fix`.
IDs are `UX-001…`, stable across re-audits so Phase 3 can cite them.

## Report template — `docs/design/AUDIT.md`

```markdown
# UI/UX Audit — <YYYY-MM-DD>

**Evaluation mode:** live | screenshot | code-only — <why, if degraded>
**Build / data:** <commit sha>, <database: local reset | sim | hosted>, widths captured, themes

## Scores
| # | Dimension | Score | Weight | Evidence (short) |
| … |
**Weighted overall: X.X / 10**

## Top 10 fixes (ordered by user impact ÷ effort)
1. UX-0xx — …

## Findings
### Critical
### Major
### Minor

## Journeys
| Journey | Steps | Friction | Verdict |

## Static sweep
| Signal | Count | Worst files |

## Preserve (load-bearing — Phase 3 must not break)
- Fixed-height `RecipeCard` (352) with one flexible band; flowing grid 288–340, max 6 cols (Gotcha 13)
- Legal links: chrome on web, page content on compact (Phase 35a)
- Cook mode always dark; several timers, one ticker; alarm is state (CLAUDE.md "Cook mode")
- `/` is redirect-only to `/discover` (widget_test pins it)
- <everything else the audit found working>

## Captures
| File | Surface | Width | Theme | Note |
```

Re-audits append a new dated `# UI/UX Audit — <date>` section at the top and a one-line
"movement" row per dimension (`Color 5 → 7`).
