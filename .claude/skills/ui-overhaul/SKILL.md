---
name: ui-overhaul
description: Three-phase UI/UX program for Secret-Sauce's Flutter app — (1) audit the current UI/UX with scored, evidence-cited findings, (2) codify a comprehensive design system + design language and route every visual value through tokens, then (3) rebuild the UI to match reference images/screenshots the user supplies. Use when asked to "audit the UI/UX", "build a design system / design language", "make the UI look like this screenshot/mockup/reference", "restyle / reskin / redesign the app", or when the user drops reference images after a design-system pass. Detects which phase to run from the files under docs/design/.
---

# UI Overhaul — Audit → Design System → Reference Rebuild

A gated, three-phase program. Each phase writes a durable artifact under `docs/design/`, and the
next phase refuses to start without it. The phases are separate on purpose: **an audit that also
redesigns grades its own homework, and a rebuild with no token layer underneath it is a
find-and-replace across 60 files.**

Distilled from ECC (`affaan-m/ecc`, MIT): `design-system` (10-dimension audit, slop detection),
`frontend-design-direction` (direction before code), `make-interfaces-feel-better` (polish
details), `gan-evaluator` / `gan-design` (strict scored generator↔evaluator loop, honest
evaluation mode), `accessibility` + `a11y-architect` (WCAG 2.2 AA), `browser-qa` (viewport matrix,
no-baseline ⇒ INCONCLUSIVE), `motion-foundations` (motion tokens, reduced-motion priority),
`inherit-legacy-style` (mode auto-detect, one-question-at-a-time conflict grilling),
`flutter-dart-code-review` §3/§7/§8 (theming, a11y, responsive), `product-lens` (journey audit).
Every web-only idea is translated to Flutter in [references/flutter-translation.md](references/flutter-translation.md).

## Step 0 — Load context and detect the phase (never skip)

1. Read, in this order: `CLAUDE.md` (Gotchas 13, 14, 18, 21–27 are the layout law of this repo),
   the design-system barrel `packages/design_system/lib/design_system.dart`, the theme
   `packages/design_system/lib/src/theme/app_theme.dart`, the layout helpers
   `packages/design_system/lib/src/layout/adaptive.dart`, and `docs/SDS.md` §UI sections.
2. Check the memory note on the **Claude Design projects** (mockups + `_ds_bundle.css`). If the
   `claude-design` MCP is connected, those canvases are a reference source; if it is not, say so
   and continue — never block on it.
3. Detect the phase from what exists — announce it in one line, never ask the user to pick:

| `docs/design/AUDIT.md` | `docs/design/DESIGN.md` | Reference images in this turn | Phase |
| --- | --- | --- | --- |
| no | — | — | **1 — Audit** |
| yes | no | — | **2 — Design system** |
| yes | yes | no | **Stop.** Ask for references (see "Phase 2 exit") |
| yes | yes | yes | **3 — Reference rebuild** |
| no | — | yes | Run **1** and **2** first, and say why: a rebuild without a token layer cannot be verified or undone |

The user may name a phase explicitly ("just re-audit", "redo the design system") — that
overrides detection. A re-run of a phase **appends a dated section**; it never deletes the
previous one (history is how a regression is noticed).

## Phase 1 — Audit (read-only against code)

Full procedure, rubric, and report template: [references/audit.md](references/audit.md).

- **Declare the evaluation mode that actually ran**: `live` (static web build + screenshots),
  `screenshot` (user-supplied captures only), or `code-only`. A code-only audit reported as a live
  one is the failure this line exists to prevent (from `gan-evaluator`).
- Two sweeps: **static** (grep recipes for raw colors, raw numbers, missing semantics, overrides
  the theme should carry) and **visual** (viewport × theme × text-scale matrix of the real surfaces).
- Score **12 dimensions 0–10** with the calibration table; every score cites evidence
  (`path:line` or a named capture). Findings obey the **concrete-mechanism rule**: name the input,
  width, scale or state that produces the defect, or drop it.
- Include a **"Preserve" list** — load-bearing decisions the rebuild must not break (fixed-height
  card, flowing grid, legal-footer split, always-dark cook mode, …). This list is the audit's most
  important output for Phase 3.
- Output: `docs/design/AUDIT.md`. **No code edits in this phase.**

## Phase 2 — Design system + design language

Full spec of the deliverable: [references/design-system.md](references/design-system.md).

The goal is **re-skinnability**: after this phase, every color, type style, spacing, radius,
elevation, duration and curve in `apps/app` and `packages/design_system` flows from one named
token, so Phase 3 changes *values* in one place before it touches any screen.

1. **Direction first** (`frontend-design-direction`): purpose, audience, tone, one memorable
   detail, constraints — and 3–5 product principles written for *this* product (recipes, cooking,
   forks, credit), not generic ones.
2. **Language**: voice & microcopy rules, imagery, iconography, motion character.
3. **Foundations as code**: color roles (M3 `ColorScheme` + a `ThemeExtension` for what M3 has no
   role for), type ramp (`TextTheme` roles only), spacing, shape, elevation/borders, motion
   (`AppMotion` durations/curves), breakpoints (unchanged: 600 / 1000).
4. **Value-neutral migration**: replace raw values with tokens **without changing what renders**,
   except where the audit filed a defect. Fixes are separate, named commits-worth of change.
5. **Guard tests**: a theme test that asserts WCAG contrast for every role pair in light *and*
   dark, plus the existing envelope suites green.
6. Output: `docs/design/DESIGN.md` + token code + tests + docs sync.

Ask the user (one question at a time, only when it changes the output) about decisions that are
theirs: **fonts** (the mockups propose Newsreader + Manrope, still unconfirmed; bundling as assets
vs `google_fonts`), and whether the seed color stays paprika `0xFFD2492A`.

### Phase 2 exit — request references

End Phase 2 by telling the user exactly what references are most useful, then **stop**:

- one image per surface they want changed (Discover, Recipe detail, Cook mode, Chefs, My Recipes,
  Editor, Auth/Profile), ideally **desktop (~1440) and phone (~390)**;
- dark variants if the dark look matters; any state that matters (empty, loading, error, signed out);
- a sentence on what they like in each ("this density", "this type", "this card") — a reference
  is ambiguous about *which* of its qualities is the point.

## Phase 3 — Rebuild from reference

Full procedure: [references/rebuild.md](references/rebuild.md).

1. **Transcribe each reference into a written spec** (`docs/design/references/<slug>.md`):
   layout skeleton, scale anchor, type, color samples, shape, density, imagery, components — each
   value tagged *measured / estimated / guessed*. Pixels pasted into chat cannot be saved to disk;
   the transcription is the durable record.
2. **Delta table**: token | current | reference | decision. Tokens first, component anatomy
   second, screen composition last.
3. **Conflicts** (reference vs a Preserve item, vs WCAG, vs a Gotcha): ask **one question at a
   time** with evidence and 3–4 options. Accessibility and the Preserve list win by default — the
   user can overrule, but must be told what it costs.
4. **Get the delta table approved before editing code.** This is a large, visible change.
5. **Build in order**: tokens → theme → design_system primitives → shared app widgets → screens.
   Run `analyze` + tests after each layer, not at the end.
6. **Fidelity loop** (from `gan-design`): capture the rebuilt surface at the reference's
   viewport, compare side by side, score with the fidelity rubric, fix, repeat — **max 3
   iterations per surface, pass ≥ 8.0**, hard gates must be green regardless of score.
7. **Measure, don't eyeball**: key dimensions from the reference spec are pinned in widget tests
   with `tester.getSize` — Flutter web renders to a canvas, so there is no DOM to measure.

## Non-negotiables (all phases)

- **Repo rules beat reference images.** Gotchas 13/21–27 (overflow envelope: 288px card, 2.0×
  text, 390/600/1000/1440), Gotcha 14 (export from the barrel), Gotcha 18 (nav bar at 600px ×
  2.0×), Gotcha 23 (`useRootNavigator: true`), "every error through `friendlyError()`", hand-written
  providers, `package:` imports, `require_trailing_commas`.
- **No behavior change hidden in a restyle.** Routes, providers, repository calls, semantics
  labels and `Key`s tests depend on stay put. A test assertion changed to match new output is a
  **documented visual-contract change** — say which contract and why, or don't change it.
- **No new dependency for a flourish** (`frontend-design-direction`). Fonts and icon packs are a
  user decision; `pubspec.lock` is committed, so a dependency shows up as a lockfile diff.
- **Anti-slop**: no default purple/blue gradients, glassmorphism without purpose, cards inside
  cards, rounded-everything, decorative blobs, generic centered hero copy, stock placeholder
  imagery, unmodified M3 defaults presented as a design. The food photograph carries the page.
- **Accessibility floor**: text 4.5:1, large text/UI 3:1, targets ≥ 48dp, color never the only
  signal, every `IconButton` has a `tooltip`, decorative images excluded from semantics, respects
  `MediaQuery.disableAnimationsOf`.
- **Cook mode stays always-dark** (the one screen that overrides the theme — CLAUDE.md "Cook mode").

## Verification commands (this machine)

```powershell
melos run analyze                 # grep output for SUCCESS / FAILED — melos.bat exits 0 either way
melos run test --no-select        # --no-select is mandatory without a TTY (B006/B007)
melos run format                  # safe since OPT-T4
cd apps/app
flutter build web --release --dart-define-from-file=env.local.json
npx serve -l <NEW_PORT> build/web # new port after every rebuild (HTTP cache); hashed deep links: /#/discover
npx playwright screenshot --viewport-size=390,844 --wait-for-timeout=6000 "http://localhost:<PORT>/#/discover" docs-capture.png
```

**Serve from a copy, not `build/web`.** Copy the bundle into the scratchpad before serving
(`cp -r apps/app/build/web <scratch>/web-light`), so a dark rebuild can't overwrite the light build
mid-capture. `npx serve` falls back to a random port when the one you asked for is busy, and a busy
port may be serving a *stale* build: read the port from serve's own output. Use Playwright's
bundled Chromium (no `--channel`); `--channel chrome` fails on this machine.

**Signed-in captures:** `scripts/capture_signed_in.mjs` signs in the **local** test account through
GoTrue's password grant and injects the session into localStorage (`sb-127-auth-token`), because a
CanvasKit form can't be filled from the DOM. Credentials live only in the git-ignored
`env.test-account.local.json` at the repo root. The script refuses any non-local `SUPABASE_URL`.
Owner views need a recipe the account owns: `--fork <id>`, capture, then `--delete <newId>`, and
check that the delete really removed a row. Install Playwright once in a scratch directory
(`npm i playwright@1.63.0`) and run the script from there.

Dark captures: set `themeMode: ThemeMode.dark` in `apps/app/lib/main.dart`, rebuild, shoot,
**revert**, and confirm `git diff apps/app/lib/main.dart` is empty. Captures go in
`.playwright-mcp/captures/` (git-ignored). Seed data: `db:reset` gives the 14 curated recipes +
whatever corpus was imported; the leaderboard and engagement numbers are **empty by design** unless
`db:sim` ran on a throwaway database (B113) — say which one a capture was taken on.

## Docs sync and final response

Per CLAUDE.md "Docs–code sync": `docs/design/` is new documentation — on first creation add it to
CLAUDE.md's repository-layout tree; token/theme changes update `docs/SDS.md` (UI / design_system
sections); a defect found goes into `docs/BUG-TRACKER.md`; phase progress goes into
`docs/ROADMAP.md`. End with the CLAUDE.md executive-summary format (Changed / Verified / Docs
updated / Open), quoting real `SUCCESS`/`FAILED` output.
