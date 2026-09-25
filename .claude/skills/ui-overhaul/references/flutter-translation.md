# ECC Web Guidance → Flutter (this repo)

ECC's design skills are written for CSS/React. This table is the translation; use the right-hand
column in audits, DESIGN.md and code.

| ECC guidance (web) | Flutter in Secret-Sauce |
| --- | --- |
| CSS custom properties / design tokens | `ColorScheme` roles + `ThemeExtension` (`AppPalette`), `TextTheme` roles, `AppSpacing`, `AppRadii`, `AppMotion`, `Breakpoints` — all exported from `design_system.dart` |
| "No hardcoded hex / `Colors.red`" | `Theme.of(context).colorScheme.<role>` or `context.palette.<field>`; literals live only in `src/theme/` |
| "No inline font sizes" | `Theme.of(context).textTheme.<role>`; a repeated `copyWith(fontWeight:)` means a missing role |
| `font-variant-numeric: tabular-nums` | `TextStyle(fontFeatures: [FontFeature.tabularFigures()])` on timers, scores, counts, quantities |
| `text-wrap: balance / pretty` | No equivalent. Use `maxLines` + `TextOverflow.ellipsis` deliberately, `softWrap`, or a `Wrap` for chip rows; decide what yields first (Gotcha 27) |
| Font smoothing | N/A (CanvasKit renders its own glyphs) |
| Image outline `1px rgba(0,0,0,.1)` inset | `foregroundDecoration: BoxDecoration(border: Border.all(color: (dark ? Colors.white : Colors.black).withValues(alpha: .1)), borderRadius: …)` — neutral, never brand-tinted |
| Concentric radius | outer = inner + padding using `AppRadii` values |
| Borders vs shadows | `BorderSide(color: scheme.outlineVariant)` for separation (card theme already does); `Material(elevation:)`/`BoxShadow` only for floating layers |
| `transition: <specific props>`, never `all` | Implicit animations per property (`AnimatedOpacity`, `AnimatedScale`, `AnimatedSlide`, `AnimatedSwitcher` with keys); don't wrap a large subtree in one `AnimatedContainer` animating many props |
| Animate transform/opacity, not layout | Prefer `Transform`/`FadeTransition`/`ScaleTransition`; avoid animating `width`/`height`/padding inside grids and slivers |
| Press `scale(0.96)` | `AnimatedScale(scale: pressed ? AppMotion.pressScale : 1)`; pick either the M3 ink ripple or the scale for a given control — not both stacked |
| Enter: opacity + small translateY; exit shorter | `FadeTransition` + `SlideTransition(Offset(0, .02))`, `AppMotion.normal` in / `AppMotion.exit` out |
| `prefers-reduced-motion` | `MediaQuery.disableAnimationsOf(context)` → `Duration.zero` or opacity-only (`AppMotion.of`) |
| `will-change` | N/A; use `RepaintBoundary` only where a profile shows repaint cost |
| Hover / focus / active states | `WidgetStateProperty.resolveWith` on button styles; `InkWell(onHover:, focusColor:, hoverColor:)`; `MouseRegion(cursor: SystemMouseCursors.click)` on custom tappables (web) |
| Hit area ≥ 40–44px | M3 minimum **48×48 dp** (`kMinInteractiveDimension`); keep `MaterialTapTargetSize.padded` on touch |
| `aria-label` on icon-only button | `IconButton(tooltip: …)` (tooltip doubles as the semantics label) |
| `alt` text | `Image(semanticLabel: …)`; decorative → `ExcludeSemantics` or `excludeFromSemantics: true` |
| Group into one announcement | `MergeSemantics` (a recipe card row), `Semantics(container: true, label: …)` |
| `role="button"` on a div | Use `InkWell`/buttons, or `Semantics(button: true, onTap: …)` around a `GestureDetector` |
| `aria-live` | `Semantics(liveRegion: true)` or `SemanticsService.announce` (e.g. a timer finishing) |
| Focus order / focus trap in modal | `FocusTraversalGroup` + `OrderedTraversalPolicy`; dialogs trap focus natively when opened with `showDialog(useRootNavigator: true)` |
| Visible focus indicator (SC 2.4.11) | Theme `focusColor` + check keyboard Tab on the web build |
| 400% zoom reflow | This repo's contract: **2.0× text scale** with no overflow (`context.textScale`), envelopes in widget tests |
| Breakpoints 375 / 768 / 1440 | **390 / 600 / 1000 / 1440** (compact < 600 ≤ medium < 1000 ≤ expanded) |
| Dark mode "complete, not half-done" | Both `AppTheme.light()` / `dark()`; never branch raw colors on `Brightness` in widgets — use roles; cook mode is always `AppTheme.dark()` |
| Visual regression baseline; no baseline ⇒ INCONCLUSIVE | Captures in `.playwright-mcp/captures/`; a surface with no prior capture is INCONCLUSIVE in the audit, never a silent pass |
| Measure with the DOM | No DOM on Flutter web — measure with `tester.getSize` / `getRect` in widget tests |
| axe-core | No equivalent for CanvasKit; use `flutter test` with `meetsGuideline(androidTapTargetGuideline)`, `meetsGuideline(textContrastGuideline)`, `meetsGuideline(labeledTapTargetGuideline)` on key screens, plus a manual keyboard pass on web |
| "Don't add a dependency for a flourish" | Same. `pubspec.lock` is committed; fonts bundled as assets beat a runtime font fetch |
