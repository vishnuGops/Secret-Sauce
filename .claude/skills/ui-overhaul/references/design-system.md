# Phase 2 — Design System + Design Language

Requires `docs/design/AUDIT.md`. Output: `docs/design/DESIGN.md`, token code in
`packages/design_system/lib/src/theme/`, guard tests, docs sync.

**Definition of done:** a Phase 3 re-skin can change the product's color, type, density, shape and
motion by editing token files alone, and every screen follows. Measure it: the Phase 1 static-sweep
counts for raw colors, hex literals, raw spacing, raw radii and raw durations drop to **zero outside
`src/theme/`** (or each survivor carries a one-line comment saying why it must be literal).

## 1. Direction (decide before any token — ECC `frontend-design-direction`)

Write these five into DESIGN.md §1, specific to Secret-Sauce:

1. **Purpose** — what job the interface does (document, follow, fork and credit recipes).
2. **Audience** — who repeats which workflow, and what they scan first (a cook mid-recipe scans
   quantities and the next step; a browser scans the photo and the title).
3. **Tone** — pick explicitly: editorial, utilitarian, warm, dense, calm… One primary, at most one accent.
4. **Memorable detail** — one idea that makes it intentional (e.g. the numbered shelf headings
   `01 UNDER 30`, the recipe-card banner, a lineage mark on forks).
5. **Constraints** — Flutter M3, one adaptive codebase, 600/1000 breakpoints, 2.0× text envelope,
   CanvasKit web, dark mode, always-dark cook mode, food photography that may be missing.

Then **3–5 principles** that decide arguments. Draft candidates grounded in CLAUDE.md — keep the
ones the user agrees with:

- *The recipe is the interface.* Structure (groups, quantities, timers) outranks decoration.
- *Kitchen-proof.* Legible at arm's length, with wet hands, under bad light.
- *Credit is visible.* Forks, originals and imported authors are always shown, never buried.
- *Honest numbers.* No engagement that was not earned; an empty board looks empty, not broken.
- *The photo carries the page.* Chrome recedes; food is the color.

## 2. Language

- **Voice & microcopy** — plain, direct, second person; sentence case; numbers as numerals;
  correct plurals (`1 recipe`, B031); errors say what happened and what to do (all through
  `friendlyError()`); never "Oops". Collect current strings that violate it into the audit's
  findings, not into a rewrite pass here.
- **Imagery** — aspect ratios per slot (card cover, detail hero, step photo), crop focus, treatment
  when no image exists (the flat no-image hero), neutral inset outline so photos don't bleed into
  the surface (see translation table).
- **Iconography** — one set (Material Symbols is the default), one style (outlined *or* rounded),
  one weight, size tokens (16/20/24). Icon + label for actions a first-time user must understand.
- **Motion character** — see §3.7; describe it in one sentence ("quick and quiet; motion confirms,
  never performs").

## 3. Foundations → code

Keep existing public names (`AppTheme`, `AppSpacing`, `AppRadii`, `Breakpoints`,
`FlowGridMetrics`, `kRecipeCard*`) — they have hundreds of call sites. Add, don't rename. Every new
file is exported from `design_system.dart` (Gotcha 14). `package:` imports only.

### 3.1 Color

- M3 `ColorScheme` roles first (`primary`, `onPrimary`, `surface`, `surfaceContainerLow…Highest`,
  `onSurfaceVariant`, `outline`, `outlineVariant`, `error`, …). Seed today: paprika `0xFFD2492A`.
- If the reference/direction needs exact brand values, build the scheme with `ColorScheme.fromSeed`
  **then `copyWith`** the specific roles — do not hand-author all 40 roles.
- What M3 has no role for goes in a `ThemeExtension`, light and dark values both defined:

```dart
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({required this.rating, required this.tierBronze /* … */});
  final Color rating; // was AppTheme.rating — keep that constant as an alias during migration
  final Color tierBronze;

  static const light = AppPalette(rating: Color(0xFFF2A93B), tierBronze: Color(0xFF…));
  static const dark = AppPalette(rating: Color(0xFFF2A93B), tierBronze: Color(0xFF…));

  @override
  AppPalette copyWith({Color? rating, Color? tierBronze}) => AppPalette(
        rating: rating ?? this.rating,
        tierBronze: tierBronze ?? this.tierBronze,
      );

  @override
  AppPalette lerp(AppPalette? other, double t) => other == null
      ? this
      : AppPalette(
          rating: Color.lerp(rating, other.rating, t)!,
          tierBronze: Color.lerp(tierBronze, other.tierBronze, t)!,
        );
}

extension AppPaletteX on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
}
```

- Migrate the hex literals the audit found (`tier_chip.dart`, `chef_spotlight_card.dart`,
  `chefs_hero.dart`) into it. `Colors.black/white` with alpha for scrims/outlines may stay literal
  only when brightness-aware and commented.
- DESIGN.md gets a **contrast table**: each foreground/background role pair, light and dark, ratio,
  pass/fail against 4.5 (text) / 3.0 (large text, UI).

### 3.2 Typography

- Families: body + display (+ mono only if needed). **User decision** — mockups propose
  Newsreader (display) + Manrope (UI); today it is Roboto. Recommend bundling font files as assets
  in `packages/design_system` (`fonts:` in its pubspec, referenced as
  `packages/design_system/<Family>`) over `google_fonts` — no runtime fetch, works offline, one
  less dependency. Include the license file.
- Define the full M3 `TextTheme` (display/headline/title/body/label × L/M/S) in one
  `app_typography.dart`: size, height, weight, letter spacing. Call sites pick a **role**; they do
  not re-bold. A repeated `copyWith(fontWeight: …)` pattern in the audit means a missing role —
  add it (e.g. a `recipeQuantity` style) to an extension instead of 30 overrides.
- `FontFeature.tabularFigures()` on every style used for timers, counts, scores, quantities.
- Heights must hold the 2.0× envelope: the card banner is `65 × textScale` capped at 2.0
  (B047) — a new ramp changes that math; re-run `recipe_card_test`.

### 3.3 Spacing & layout

- `AppSpacing` (4/8/16/24/32/48) stays the scale. Add semantic aliases only if the audit shows
  repeated intent (`pageGutterCompact`, `sectionGap`) — aliases point at scale values, never new numbers.
- Page gutters per breakpoint, max content widths (the 1140px detail page), and the grid rules
  (`FlowGridMetrics`, 288–340 tile, max 6 columns, left-aligned trailing slack — B123) are written
  down in DESIGN.md, not changed.

### 3.4 Shape

- `AppRadii`: `button 12`, `card 16`, `pill 999` today. Add `sm`/`lg` only if used ≥ 3 times.
- **Concentric rule** (ECC `make-interfaces-feel-better`): outer radius = inner radius + padding
  for nested rounded surfaces; if padding is large, treat them as separate surfaces.

### 3.5 Elevation & borders

One policy, written down: this app uses **borders for separation** (`CardThemeData` has
`elevation: 0` + `outlineVariant` side) and **shadow only for floating layers** (menus, dialogs,
sheets, sticky bars). Tonal surfaces (`surfaceContainer*`) express depth in dark mode.

### 3.6 Breakpoints & density

`Breakpoints.compact = 600`, `medium = 1000`, `context.textScale` — unchanged. Document
`VisualDensity` (web may run `compact`, touch stays `standard`) and the 48dp minimum target.

### 3.7 Motion (ECC `motion-foundations`, in Flutter)

```dart
abstract final class AppMotion {
  static const instant = Duration(milliseconds: 80);  // focus ring, badge
  static const fast = Duration(milliseconds: 180);    // press, icon swap, chip toggle
  static const normal = Duration(milliseconds: 300);  // sheet/dialog, card expand, enter
  static const slow = Duration(milliseconds: 500);    // page-level, hero
  static const exit = Duration(milliseconds: 150);    // exits are shorter than enters
  static const emphasized = Curves.easeOutCubic;      // enter / state change
  static const standard = Curves.easeInOutCubic;      // move
  static const exitCurve = Curves.easeInCubic;
  static const pressScale = 0.97;

  /// Reduced motion wins over everything: opacity-only, ≤ fast.
  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : d;
}
```

Motion must guide attention, communicate state, or preserve continuity — otherwise remove it.
Animate `Transform`/`Opacity` (`AnimatedScale`, `FadeTransition`, `AnimatedSwitcher`) over layout
properties on anything inside a grid or list. Cook-mode timers are **not** animations — they are
clock reads (32c4); don't route them through motion tokens.

## 4. Components

Inventory table in DESIGN.md — one row per widget in `design_system/lib/src/widgets/` and each
shared app widget in `apps/app/lib/widgets/`:

`Component | file | anatomy | variants | states (default/hover/focus/pressed/disabled/loading/empty/error) | envelope tested at | tokens used | audit findings`

Flag duplicates (two pill implementations, two empty states) and name the survivor. States are part
of the component: hover and focus rings on web are **required** (`WidgetStateProperty` / theme
`focusColor`/`hoverColor`), not polish.

## 5. Patterns

Page chrome (web top bar vs compact `NavigationBar`, legal footer split), page header anatomy,
sections/shelves, the paged grid ladder (`RecipeAsyncSliverGrid`: loading/error/empty/grid —
never hand-rolled, Gotcha 24), forms (editor groups, validation copy), dialogs/sheets
(`useRootNavigator: true`, Gotcha 23), attribution block, cook mode.

## 6. Accessibility contract

WCAG 2.2 AA mapped to Flutter (see [flutter-translation.md](flutter-translation.md)): contrast
table (§3.1), 48dp targets, `tooltip` on every `IconButton`, `semanticLabel` on meaningful images
and `ExcludeSemantics` on decorative ones, `MergeSemantics` on composite rows (a recipe card should
read as one announcement), logical focus traversal on web (`FocusTraversalGroup`), visible focus,
color-not-only (difficulty, tiers, errors carry text or icon), text scale to 2.0× without loss.

## 7. Guard tests (same change)

Add `packages/design_system/test/theme_contrast_test.dart`:

```dart
double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
// for each of AppTheme.light()/dark(): onSurface/surface ≥ 4.5, onSurfaceVariant/surface ≥ 4.5,
// onPrimary/primary ≥ 4.5, outline/surface ≥ 3.0, palette.rating/surface ≥ 3.0 (UI), …
```

Plus: a test that `AppTheme.light()`/`dark()` both carry every `ThemeExtension` (a missing
extension is a runtime `!` crash, not a compile error), and the existing envelope suites green.

## 8. DESIGN.md template

```markdown
# Secret-Sauce Design Language & System — v<N> (<YYYY-MM-DD>)

## 1. Direction        purpose · audience · tone · memorable detail · constraints · principles
## 2. Language         voice & microcopy · imagery · iconography · motion character
## 3. Foundations      color (roles + contrast table) · type ramp · spacing · layout & grid ·
                       shape · elevation · breakpoints & density · motion
## 4. Components       inventory table (§4)
## 5. Patterns         chrome · headers · shelves · paged grid · forms · dialogs · attribution · cook mode
## 6. Accessibility    contract + WCAG mapping
## 7. Token ↔ code map | Token | Dart symbol | File | Light | Dark |
## 8. Do / Don't       anti-slop list + the repo Gotchas that are visual (13, 18, 21–27)
## 9. Changelog        dated entries; Phase 3 appends "v<N+1> — reference rebuild: <surfaces>"
```

Optional: publish a token specimen (color swatches with contrast, type ramp, spacing, radii) as an
HTML Artifact for review. Dart is the source of truth — the specimen is a snapshot, regenerate it
rather than editing it.

## Order of work

1. DESIGN.md §1–2 → show the user the direction + principles, one question at a time for choices
   that are theirs (fonts, seed, tone).
2. Token files + theme wiring (value-neutral) → `melos run analyze` + tests.
3. Migrate raw values feature by feature (value-neutral) → tests after each feature.
4. Fix audit defects that are token-shaped (contrast, missing states, targets) — each cites its `UX-0xx`.
5. Guard tests, DESIGN.md §3–9, docs sync, then the **Phase 2 exit** request in SKILL.md.
