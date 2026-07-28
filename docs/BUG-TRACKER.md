# BUG-TRACKER — Secret-Sauce

Tracks all bugs found or fixed. Update in the same change that discovers/fixes a bug
(see "Docs–code sync" in [CLAUDE.md](../CLAUDE.md)).

Severity: `blocker` \| `high` \| `medium` \| `low`
Status: `open` \| `in-progress` \| `fixed` \| `wontfix`

| ID   | Date       | Severity | Area          | Description                                                                  | Status | Fix / Commit                                                                      |
| ---- | ---------- | -------- | ------------- | ---------------------------------------------------------------------------- | ------ | --------------------------------------------------------------------------------- |
| B001 | 2026-07-28 | low      | design_system | `RecipeCard` `RenderFlex` overflow when given unbounded height (test only).  | fixed  | Test constrains card to a 320px-wide box, matching real grid usage.               |
| B002 | 2026-07-28 | low      | home          | Feature-card grid overflowed inside the 900px content column (fixed aspect). | fixed  | Switched grid to `mainAxisExtent: 132` and clamped card text (maxLines/ellipsis). |

---

## Known environment limitations (not bugs)

- Flutter SDK 3.44.8 / Dart 3.12.2 installed at `C:\Flutter\flutter\bin`. `melos bootstrap`,
  `build_runner` codegen, `flutter analyze`, and `flutter test` all run clean.
- Web runs via the `web-server` device (`http://localhost:8080`); Chrome is not installed and
  Edge's auto-launch debugger fails, so use `-d web-server` or `-d windows`.
- Supabase project is provisioned (hosted); the consolidated `supabase/migrations/0001_init.sql`
  is idempotent and applied.

## Template for new entries

```
| B001 | 2026-07-28 | high | recipe_editor | Saving edit does not bump version_number | open | |
```
