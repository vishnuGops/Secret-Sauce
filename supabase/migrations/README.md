# supabase/migrations — the rules

A **numbered sequence**, applied in filename order, by `supabase db reset`, by
`melos run db:create`, and by hand on the hosted project. `0001_init.sql` is the
**baseline**; everything after it is a new file (OPT-A9).

## Why it stopped being one file

`0001_init.sql` was edited in place and re-applied — every change, everywhere.
That works until a database has data in it: the file ends with an idempotent
profile backfill and an idempotent chef-stats backfill that recompute **every
row**, and re-applying it to push a one-line policy change re-runs both. The cost
grows with the table, forever, for a change that touched neither.

So: the baseline stays exactly as it is, and the next schema change is
`0002_<what_it_does>.sql`.

## The rules

1. **Number and name it**: `NNNN_snake_case_summary.sql`, four digits, next
   number wins. The Supabase CLI records applied versions in
   `supabase_migrations.schema_migrations`, keyed by that number.
2. **Never edit a released migration.** Once a file has been applied to any
   database that is not yours, it is history. Fix it forward with a new one.
   The baseline is the single exception *until it is applied to hosted* — see
   "the baseline" below.
3. **Every statement is still guarded** — `if not exists`, `drop policy if
   exists`, `create or replace`, `alter table … add column if not exists`.
   `melos run db:create` applies the whole directory with no history tracking,
   so a migration that cannot be re-run breaks `db:reset` on the next machine.
4. **A function whose signature changes carries its own drops** (B024). Postgres
   keys drops by argument list, so `create or replace` cannot change one — the
   old overload survives beside the new one and every call becomes ambiguous
   (`42725`). Put `drop function if exists <exact old signature>;` in the
   migration that recreates it, not only in `scripts/drop.sql`, which a plain
   re-apply never runs.
5. **A new table needs its grants and its policies in the same file.** RLS with
   no policy default-denies (reads come back empty, not as an error), and the
   grants block in the baseline only covers tables that existed when it ran
   (B013).
6. **Verify on the upgrade path, not just a fresh reset** (Gotcha 6). A
   migration that assumes an object a *later* file creates passes on every
   machine that has already run the sequence and fails on a clean one (B045).

## Applying

| Where | How |
| --- | --- |
| Local, from scratch | `supabase db reset` — migrations in order, then `seed.sql` + `seed_recipes.sql` |
| Local, ad hoc | `melos run db:create` (applies **all** migrations; safe because each is idempotent) |
| Hosted, with data | apply **only the new file**, through the dashboard SQL editor or the container `psql` form in [BUG-TRACKER B033](../../docs/BUG-TRACKER.md) |

Applying the baseline again to a hosted database is safe, just wasteful — that
waste is the whole reason this directory is a sequence now.

## The baseline

`0001_init.sql` is frozen as of the OPT phase (tables, RLS, grants, triggers,
storage, the Discover/chefs RPCs, `save_recipe`). A hosted database that has not
had it applied since those landed needs **one** more full apply; after that, it
only ever sees `0002+`.
