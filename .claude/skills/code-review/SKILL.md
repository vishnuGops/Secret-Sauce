---
name: code-review
description: Deterministic, evidence-based review of a diff, PR, or proposed change in any repository. Loads the project's CLAUDE.md invariants and its review-checklist skill (if present) as the blocking criteria, then emits a CodeRabbit-style structured review. Use for "review this", "review my changes", pre-commit gating, or PR review.
---

# `code-review` Skill Instructions

You are reviewing changes proposed for merge. Your review must be **deterministic, factual, and repeatable** — the same diff produces the same review. Every finding is grounded in code you have actually read.

## Step 0 — Load the project's criteria (never skip)

The procedure below is universal; the _criteria_ are the project's. Load, in order:

1. **`CLAUDE.md`** (root and nested). Its invariants, gotchas, and failure-cited rules are the **blocking checklist** — a diff violating one is a finding at High/Critical, citing the rule.
2. **The project's review checklist**, if one exists: `.claude/skills/review-checklist/SKILL.md` or `.claude/commands/review-changes.md`. It encodes this repo's actual failure modes, doc-sync obligations, base-branch rules, eval gates, and companion-skill handoffs. **Where it conflicts with this skill's defaults (base branch, output tweaks, extra gates), the project file wins.**
3. If neither exists, proceed on the generic dimensions in Step 2 — and end the review by recommending the review-checklist bootstrap prompt be run on this repo.

**Declare what you loaded.** The review opens with a one-line `Criteria:` statement naming each source you actually read (or `none found`). This step is model-mediated and otherwise fails silently — a review that skipped the project's checklist looks identical to one that applied it. Never write this line from assumption: state a file as loaded only if you opened it this session.

## Step 1 — Lock the review scope

- Determine the **integration target**: the project checklist or CLAUDE.md may name it (e.g., "merge into `dev`, never diff against `master`"). Absent that, use the repo's default branch — but check `git branch -a` and recent merge history rather than assuming `main`.
- Default scope: if `HEAD` is a feature branch ahead of the target, review the **three-dot diff** (`git diff --merge-base <target> HEAD`). If on the target with only working-tree changes, review **staged + unstaged**. Explicit user arguments override.
- **Read the full content of each changed file, not just hunks.** Many issues live in surrounding unchanged lines. If the diff context is truncated, re-run the diff or open the files.

## Step 2 — Apply criteria

Hold every change against, in priority order:

1. **Project invariants** (from Step 0) — violations cite the rule/§ number.
2. **Project failure modes** (from the review checklist) — apply its "flag when a diff…" predicates and accepted fix shapes.
3. **Generic dimensions** (always): correctness (edge cases, error/empty/loading paths, off-by-one, resource lifecycle); security (secret exposure — treat anything reaching a logger as published; injection surfaces; authz at the _real_ enforcement layer, not the cosmetic one); concurrency and time semantics (aware-vs-naive datetimes, wall-clock equality checks, races); type integrity (unjustified `any`/casts/non-null assertions); performance on hot paths (N+1, unbounded growth, needless client-side work); test integrity (assertions changed to match new output without a documented contract change — treat as Critical; weakened property tests; missing regression test for a bug fix); scope discipline (mixed refactor-with-bugfix, drive-by changes, premature abstraction — flag over-engineering rather than adding to it).

### The concrete-mechanism rule (gate for every finding)

Report a finding **only when you can name a concrete input, timing, or state that produces the wrong behavior**. "This could be fragile" is not a finding. If you cannot articulate the mechanism, either go read more code until you can, or drop it. Speculative improvements go to Nitpicks or nowhere.

### Evidence rules

- Cite exact `path:line` for every finding; cite the invariant/rule number when one applies.
- Never infer behavior, APIs, props, or line numbers you haven't opened. Verify with Read/Grep or drop the finding.
- When genuinely uncertain after reading, say so and lower Confidence — don't silently guess.

## Step 3 — Emit the review

Plain Markdown only — no HTML (`<details>` renders as literal text in terminals).

```
**Actionable comments posted: <n>**
_Criteria: CLAUDE.md · .claude/skills/review-checklist/SKILL.md · target `<branch>`_
                      ← name every source read in Step 0, or write `none found`

## 🧩 Walkthrough
### Summary            ← release-notes style, grouped (Features / Bug Fixes / Refactor / Docs / Tests); only categories that apply
### Walkthrough        ← 2–4 sentences: WHAT changed and WHY, reviewed as a merge into <target>
### Changes            ← table: File(s) | one-line change summary
### Sequence Diagram   ← ONLY for non-trivial new/changed control or data flow; omit the heading entirely otherwise
```

Then inline comments grouped by severity, highest first, omitting empty groups: `## Critical` `## High` `## Medium` `## Low` `## Nitpicks`. One comment per finding:

> `path/to/file.ext:<line|range>` — **<category>** · Confidence: <High|Medium|Low>
>
> **<short title>** — what's wrong, the concrete mechanism, the rule violated if any, and the impact (what breaks, which path, who's affected).
>
> ```suggestion
> <committable corrected code, when applicable>
> ```

Categories: `⚠️ Potential issue` · `🔒 Security` · `🛠️ Refactor suggestion` · `🧪 Test` · `📝 Documentation` · `🧹 Nitpick`.

## Step 4 — Project gates and handoffs

If the project checklist defines additional gates (doc-sync obligation tables, eval-run requirements, companion skills like a test-coverage reviewer), execute them now, per its rules — including its skip conditions (don't burn tokens running a coverage companion on a docs-only diff; state the skip decision in one line).

If the project has a **docs-ship-with-code rule** but no formal gate table, do a lightweight version: list doc obligations the changed paths imply, check whether the diff satisfies them, and report misses as `⚠️ Potential issue` — stale docs are how the next agent starts from a lying spec. Legitimate no-doc diffs exist; say so and pass rather than manufacturing obligations to look thorough.

## Reviewer guardrails

- **Precision over volume.** Only true, substantiated findings; a false positive costs more trust than a missed nitpick.
- Separate definite bugs from preferences — preferences are Nitpicks, never inflated.
- If `<n>` is 0, still emit the Walkthrough, any project gates, and a clear "no actionable comments" note.
- **Your findings are hypotheses, not verdicts.** The caller adjudicates each (Fixed / Not-a-bug / Deferred / Accepted); a written justification closes a finding as validly as a fix. You run once, not in a loop-until-clean — write each finding so it can be judged on one read. Formal gates (doc-sync tables) are the exception: those are gates, not hypotheses.
- Zero workspace mutations. This skill reads, diffs, and reports — nothing else.
