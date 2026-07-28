# BUG-TRACKER — Secret-Sauce

Tracks all bugs found or fixed. Update in the same change that discovers/fixes a bug
(see "Docs–code sync" in [CLAUDE.md](../CLAUDE.md)).

Severity: `blocker` \| `high` \| `medium` \| `low`
Status: `open` \| `in-progress` \| `fixed` \| `wontfix`

| ID  | Date | Severity | Area | Description           | Status | Fix / Commit |
| --- | ---- | -------- | ---- | --------------------- | ------ | ------------ |
| —   | —    | —        | —    | No bugs recorded yet. | —      | —            |

---

## Known environment limitations (not bugs)

- Flutter SDK not installed in the scaffolding environment, so `melos bootstrap`,
  `build_runner` codegen, `flutter analyze`, and running the app are pending the developer's
  local setup. Generated files (`*.freezed.dart`, `*.g.dart`) are intentionally absent until
  codegen runs.
- Supabase project not provisioned; migrations under `supabase/migrations` are authored but not
  yet applied.

## Template for new entries

```
| B001 | 2026-07-28 | high | recipe_editor | Saving edit does not bump version_number | open | |
```
