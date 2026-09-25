# Phase 3 — Rebuild From Reference Images

Requires `docs/design/AUDIT.md` and `docs/design/DESIGN.md`. Inputs: reference images (pasted,
file paths, or Claude Design canvases). Outputs: code, `docs/design/references/<slug>.md`,
`docs/design/REBUILD-LOG.md`, DESIGN.md v<N+1>, docs sync.

## Step 1 — Intake

For each image, record: source (pasted / path / canvas), which surface it maps to, apparent
viewport, theme, state, and the user's sentence about *what they like in it*. If they gave none,
ask — once, for all images together: "For each reference, which quality is the point: layout,
type, color, density, a specific component, or the whole look?" A reference is ambiguous about
which of its qualities matters; guessing wrong rebuilds the wrong thing.

A reference for a surface that does not exist, or a layout that needs data the app lacks
(e.g. a "trending chefs" strip on a database with no engagement), triggers the CLAUDE.md
**Seed-data fit** rule: say what fixture would be needed before building it.

## Step 2 — Transcribe (the durable record)

Pasted pixels cannot be written to disk, so the reference is transcribed into
`docs/design/references/<slug>.md`. Tag every value **M** measured, **E** estimated, **G** guessed.

1. **Scale anchor** — find something of known size to convert image px → logical px: phone status
   bar (~44–54), a 24px icon, body text cap height, a 48dp button. State the anchor and ratio.
2. **Skeleton** — regions top to bottom, columns, gutters, max content width, alignment axes,
   what is sticky/pinned. Draw it as an ASCII box diagram.
3. **Type** — per text role visible: classification (serif / grotesk / humanist / geometric /
   mono), candidate families, size in logical px, weight, case, tracking, line height, max lines.
   Map each to a `TextTheme` role.
4. **Color** — sample page background, surfaces, text primary/secondary, accent(s), borders,
   destructive. Map each to a `ColorScheme` role or an `AppPalette` field. Compute contrast for
   each text/background pair now; a failing pair is a conflict (Step 4), not a value to copy.
5. **Shape & depth** — radii per element, border vs shadow, divider style, nesting.
6. **Density** — base unit (find the GCD of repeated gaps), paddings, list row heights, card sizes.
7. **Imagery & icons** — aspect ratios, crop, overlay/scrim, icon style/weight/size.
8. **Components** — each distinct element → existing widget (file) | variant of one | new.
9. **Unknowable from a still** — hover/focus/pressed, motion, loading/empty/error, other widths,
   2.0× text. List them; they are designed from DESIGN.md rules, not invented to look like the image.

## Step 3 — Delta table

In `REBUILD-LOG.md`, grouped in build order:

```markdown
| Layer | Token / component | Current | Reference | Decision | Conf. | Cites |
| --- | --- | --- | --- | --- | --- | --- |
| token | colorScheme.surface (light) | fromSeed paprika | #F7F3EC (M) | adopt | M | ref/discover.md §4 |
| token | textTheme.titleLarge | Roboto 22/28 w400 | serif 26/32 w500 (E) | adopt, family per DESIGN §3.2 | E | |
| component | RecipeCard banner | 65 × scale, 2 lines | title over photo, gradient scrim | CONFLICT → Q1 | M | Preserve: fixed card |
| screen | Discover masthead | … | … | … | | |
```

Decision is one of: adopt · adapt (say how) · reject (say why: which rule) · CONFLICT (→ Step 4).
Then present the table to the user and **get approval before editing code**.

## Step 4 — Conflicts (one at a time — ECC `inherit-legacy-style` grilling protocol)

Never stack questions. For each conflict:

> **Evidence:** reference shows <X> (ref/<slug>.md §n); the app has <Y> because <rule / bug id>.
> **Risk:** <what breaks: overflow at 288px × 2.0, contrast 3.1:1 on body text, …>
> **Choose:** 1 follow the reference and accept <cost> · 2 keep current · 3 adapt: <concrete proposal> · 4 something else

Defaults when the user has no preference: accessibility wins; the Preserve list wins; a Gotcha
wins. Weak-signal differences (a 2px radius delta, one-off spacing) are not conflicts — adopt the
token-level value and move on.

## Step 5 — Build in layers

Run `melos run analyze` and `melos run test --no-select` after **each** layer; read the output for
`SUCCESS`/`FAILED`.

1. **Tokens** — values in `app_theme.dart` / `app_typography.dart` / `AppPalette` / `AppMotion`.
   Most of the reference lands here. Capture every surface once afterwards: this is the cheapest
   point to see how far tokens alone got.
2. **Theme** — component themes in `ThemeData` (buttons, chips, inputs, cards, navigation bar,
   dialogs, tooltips, `focusColor`/`hoverColor`), so widgets inherit instead of overriding.
3. **Primitives** — `packages/design_system` widgets (`RecipeCard`, pills, badges, state views,
   footer). Keep public constructors stable; new looks are new parameters or variants.
4. **Shared app widgets** — `apps/app/lib/widgets/` (grids, share dialog, legal footer), routing
   chrome (`top_nav_bar.dart`, `app_shell.dart`).
5. **Screens** — composition only; by now a screen should need layout changes, not style values.

Scope per turn: one surface through step 5 at a time once tokens and theme are done. Independent
surfaces may be handed to parallel subagents **after** layers 1–3 are merged — never before, or
each invents its own tokens.

## Step 6 — Fidelity loop (ECC `gan-design`, bounded)

Per surface, max **3** iterations:

1. Build + serve on a new port, capture at the reference's viewport and theme (SKILL.md commands).
2. Read the reference and the capture; compare region by region using the transcription.
3. Score (be strict — the generator does not grade itself):

| Criterion | Weight | 10 means |
| --- | --- | --- |
| Layout fidelity | 0.30 | Same skeleton, proportions, alignment axes, hierarchy of regions |
| Typography fidelity | 0.20 | Families/classes, sizes, weights, rhythm match within the confidence of the transcription |
| Color & surface fidelity | 0.20 | Roles match; accent used in the same places and amount |
| Component craft | 0.20 | Details: radii, borders, icon weights, states on web, image treatment |
| Behavior preserved | 0.10 | Every route, action, state and label that existed still works |

**Pass: weighted ≥ 8.0 AND all hard gates green.** Hard gates, independent of score:
analyze SUCCESS · tests SUCCESS · no overflow in the envelope suites · contrast test green ·
Preserve list intact · no `git diff` left in `main.dart` from a dark capture.

4. Log to `REBUILD-LOG.md`: iteration, scores, what changed, what regressed, capture filenames.
5. After 3 iterations below 8.0, stop and show the user the side-by-side gap with the specific
   blocker (usually a font not bundled, a missing asset, or a conflict answered "keep current").

Feedback rules (ECC `gan-evaluator`): every gap names the element and the fix
("masthead title is `headlineMedium` 28; reference is ~36 serif → `displaySmall`"), quantify
("card gutter 16 vs reference 24"), and record improvements as well as regressions.

## Step 7 — Measure, don't eyeball

Flutter web draws to a canvas — there is no DOM to measure with `getBoundingClientRect`. Pin the
reference's key dimensions in widget tests instead:

```dart
testWidgets('discover masthead matches reference height at 1440', (tester) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(/* app under ProviderScope with fakes */);
  await tester.pumpAndSettle();
  // Illustrative key and value: add a ValueKey to the region if it has none; the number comes
  // from references/<slug>.md, with a tolerance that matches its M/E confidence tag.
  expect(tester.getSize(find.byKey(const Key('discover-masthead'))).height, closeTo(220, 4));
});
```

Also re-run each touched widget at **390/600/1000/1440 × 1.0/2.0** (Gotchas 13, 22, 25, 26): a new
look is a new envelope. Assert degradation order with `RenderParagraph.didExceedMaxLines`
implications, never pixel widths of text (Gotcha 27 — the test font is wider than production's).

## Step 8 — Tests that break

- A test failing because a **visual contract intentionally changed** (a label moved, a banner
  height changed): update it, and list each one in the summary as *contract change: <what>, <why>*.
- A test failing for any other reason is a regression. Fix the code, not the test.
- Changing an assertion to match new output without naming the contract is the review-blocking
  "test integrity" failure from the repo's `code-review` skill.

## Step 9 — Close

- DESIGN.md → v<N+1>: update foundations and the token↔code map; changelog entry listing surfaces.
- `docs/SDS.md` UI/design_system sections, `docs/ROADMAP.md` status, `docs/BUG-TRACKER.md` for
  any defect found on the way (with a new `Bxxx`), CLAUDE.md if a Gotcha or command changed.
- Re-run the Phase 1 static sweep and append the movement numbers to AUDIT.md.
- If the Claude Design MCP is connected, offer to mirror the new tokens into `_ds_bundle.css` so
  the mockups and the app stop drifting (memory: the two projects drift — sync both).
