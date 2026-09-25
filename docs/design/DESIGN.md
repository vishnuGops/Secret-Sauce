# Secret-Sauce Design Language & System — v1 (2026-09-25)

Phase 2 of the `ui-overhaul` skill. Reads [AUDIT.md](AUDIT.md) (2026-09-24, 5.1/10); Phase 3
(reference rebuild) reads this file and changes **token values** before it touches a screen.
Dart is the source of truth: `packages/design_system/lib/src/theme/`. Where this document and the
code disagree, the code wins and this file is wrong — fix it the same day.

Owner decisions (2026-09-25): **Newsreader + Manrope**, bundled as assets · seed stays **paprika
`0xFFD2492A`** · tone **warm editorial cookbook, kitchen-proof; the food photo carries the page**.

## 1. Direction

**Purpose.** Secret-Sauce is where a recipe is written down properly, followed at the stove, forked
into someone's own version, and credited back to where it came from. The interface's job is to make
a recipe's *structure* — groups, quantities, order, timers, lineage — effortless to read and to act on.

**Audience, and what each scans first.**

| Who | Doing | Scans first |
| --- | --- | --- |
| A browser (signed out, phone or desktop) | Discover, Explore, a chef page | The photo, then the title, then time and difficulty |
| A cook mid-recipe (phone propped up, hands wet) | Detail rail, cook mode | The next quantity, the current step, the running timer |
| An author (signed in, desktop more often) | Editor, My Recipes | Where they are in the form, what is unsaved, what will print |
| A curious reader | A fork, an imported recipe | Who made the original, and what changed |

**Tone.** *Warm editorial cookbook.* One primary register — a well-set cookbook: a serif display
face for names and headings, a clear sans for everything a cook acts on, generous but not airy
spacing, paper-warm surfaces, paprika used sparingly as the ink colour of emphasis. No accent
register beyond it: the second "colour" of the page is the food.

**Memorable detail.** *The index line.* The numbered shelf heading (`01 UNDER 30`) is the seed:
a small, tracked, tabular-figure kicker set above a serif title. It becomes the one typographic
signature — shelves, recipe-detail sections (`Ingredients`, `Method`), step groups, the chefs hero,
the rank on a spotlight card — built from a single `kicker` text role instead of today's six
hand-rolled versions (UX-032). A cookbook's contents page, carried through the app.

**Constraints.** Flutter M3, one adaptive codebase · breakpoints 600 / 1000, unchanged · the
2.0× text envelope and the 288px card floor (Gotchas 13, 21–27) · CanvasKit on web (no DOM, fonts
must be bundled or they flash) · light and dark · cook mode **always dark** · food photography
that is **usually missing** today (14/14 curated recipes have no cover — UX-034), so every image
slot has a designed no-photo state · the Preserve list in AUDIT.md.

### Principles (they decide arguments, in this order)

1. **The recipe is the interface.** Structure outranks decoration. A quantity, a step number or a
   timer is never smaller, fainter or lower on the page than something ornamental next to it.
   *Decides:* cook-mode temperature/time grow (UX-024); the quantity gutter stays; a banner never
   crowds the cover the card exists to show.
2. **Kitchen-proof.** Legible at arm's length, under bad light, with a thumb. 4.5:1 text, 3:1 UI,
   48dp targets, tabular figures anywhere a number changes, and no state carried by colour alone.
   *Decides:* B133's difficulty/rating contrast; UX-049's jitter; the difficulty badge keeps its word.
3. **Credit is visible.** Every fork names its parent, every imported recipe names its source,
   every chef page says whether it is a member or a credit. Lineage and attribution get real type,
   not a grey footnote. *Decides:* attribution block keeps its four statements (Preserve); the
   `kicker` role is available to label provenance as clearly as a shelf.
4. **Honest numbers, honest emptiness.** No engagement that was not earned; an empty board looks
   empty on purpose and says why, never broken and never padded. *Decides:* empty states explain
   (Preserve: shelf empties); no "Medium" or "0 ratings" shown as fact where nothing is known.
5. **The photo carries the page — and the page stands without it.** Chrome recedes into warm
   neutrals so food is the colour. When there is no photo, the slot is *typeset*, not iconed: the
   dish name in the serif on a quiet paper tone, not a utensil glyph on a brown band.
   *Decides:* the no-photo card is a first-class design state (UX-034, Phase 3), and chrome
   surfaces stay low-chroma.

## 2. Language

### 2.1 Voice & microcopy

- **Plain, direct, second person, sentence case.** "Save recipe", not "Save Recipe" or "Bookmark it!".
- **Numerals and correct plurals** — `1 recipe`, `2 recipes` (B031); `1 rating`, never `1 ratings` (UX-046).
- **Cooking units as a cook reads them** — the canon is `nutritionData/units.json`'s display form
  (B094); fractions for volume and count units are a Phase 3/behaviour item (UX-023), not copy.
- **Errors say what happened and what to do**, always through `friendlyError()`. Never "Oops",
  never an exception string, never blame.
- **Empty states explain why** and, when there is one, offer the next action (Preserve).
- **Honest capability copy** — "Keep this screen open", "chime when a timer ends" (cook mode) —
  never promise what a plugin we have not added would do.
- **One brand spelling in UI copy: "Secret Sauce"** (the product name as a reader says it);
  `Secret-Sauce` survives only as the repo name (UX-041 — a behaviour/copy fix, logged here as the rule).
- **Durations one way:** `1 h 10 min`, `45 min` (UX-043 — the rule; the unification is a copy fix).

### 2.2 Imagery

| Slot | Aspect | Crop | No-photo state |
| --- | --- | --- | --- |
| Recipe card cover | fills the one flexible band of the fixed 352 tile | `BoxFit.cover`, centre | Typeset: dish initial / name in the display serif on `surfaceContainer` (Phase 3) |
| Detail hero (expanded) | ~16:9, capped by the 1140px page | cover, centre | The flat no-image hero (`.hero.noimg`) — header band only, no placeholder |
| Detail cover (compact) | ~4:3 | cover, centre | Collapses; the title leads |
| Step photo | 4:3, full step-card width | cover | Absent — no placeholder (UX-001 is a behaviour fix) |
| Avatars | 1:1 circle | cover | Initials on a tier- or scheme-tinted disc (`ChefAvatar`) |

Every photo gets a **neutral inset hairline** (`AppPalette.imageOutline`, black/white at ~10%),
never brand-tinted, so a pale plate does not bleed into a pale surface. No stock imagery, no
illustration packs, no decorative blobs.

### 2.3 Iconography

- **Material Icons, one set.** Default (filled) weight for actions and navigation; the `_outlined`
  variant only for the *unselected* half of a toggle (like/save, nav destinations) — which is how
  it is used today (126 filled / 36 outlined / 5 rounded; the 5 rounded are migrated when touched).
- **Sizes are tokens:** `AppIconSize.sm 16` (inline with label text), `md 20` (buttons, chips),
  `lg 24` (app bar, nav, standalone `IconButton`).
- **Icon + label** for any action a first-time reader must understand (Fork, Cook, Save); icon-only
  is allowed for universally-known actions and always carries a `tooltip` (UX-047).

### 2.4 Motion character

**Quick and quiet — motion confirms, it never performs.** Things arrive with a short ease-out, leave
faster than they came, and never bounce. Reduced motion (`MediaQuery.disableAnimationsOf`) wins over
everything: durations collapse to zero (UX-050). Cook-mode timers are clock reads, not animations.
