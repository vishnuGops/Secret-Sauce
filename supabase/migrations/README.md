# supabase/migrations — the rules

A **numbered sequence**, applied in filename order, by `supabase db reset`, by
`melos run db:create`, and by hand on the hosted project.

| File | What it holds |
| --- | --- |
| `0001_init.sql` | Everything: enums, tables, indexes, triggers, RLS, grants, storage buckets, and the discovery / shelf / chefs / fork / save RPCs |

## While the project is pre-release, the baseline is editable

**Owner's call, 2026-08-23.** Nothing outside this machine depends on the schema
yet, so a change goes into `0001_init.sql` — idempotently — instead of a new
file. Phase 26's three Discover shelves (`recipes_quick`, `recipes_projects`,
`recipes_most_forked` and the `site_rating_prior()` they share) were folded back
in on that basis, and `0002_discover_shelves.sql` was deleted.

This costs nothing today because the two things that make an edited baseline
dangerous are both about *other people's databases*:

1. **A tracked apply skips it.** The Supabase CLI records applied versions in
   `supabase_migrations.schema_migrations` and never re-runs a recorded one. Edit
   `0001` after a database has recorded it and `supabase db push` applies
   **nothing** — while reporting success. Locally this does not bite, because
   `db reset` rebuilds from scratch and `melos run db:create` is a raw `psql`
   loop that tracks nothing.
2. **Re-applying is not free.** This file ends with two whole-table backfills —
   the `profiles` B015 backfill and `recompute_all_chef_stats()`. Measured on the
   local stack at 1,016 profiles / 1,344 public recipes: **~110 ms**, and it
   scales with the table forever.

## When it stops — the OPT-A9 rule resumes

**The day the schema reaches a database that is not ours** (the hosted project,
or anyone else's clone), `0001_init.sql` is history and every change after it is
a new `0002_*.sql`, `0003_*.sql`, … Do not rediscover this the hard way: the
failure mode of getting it wrong is a deploy that silently applies nothing.

## The rules (which apply either way)

1. **Every statement is guarded** — `if not exists`, `drop policy if exists`,
   `create or replace`, `alter table … add column if not exists`. The baseline is
   applied over itself constantly; a statement that cannot be re-run breaks
   `db:create` on the next machine.
2. **A function whose signature changes carries its own drops** (B024). Postgres
   keys drops by argument list, so `create or replace` cannot change one — the
   old overload survives beside the new one and every call becomes ambiguous
   (`42725`). Put `drop function if exists <exact old signature>;` in the file
   that recreates it, not only in `scripts/drop.sql`, which a plain re-apply
   never runs.
3. **Define before use.** Postgres validates a SQL function body at creation, so
   a function that calls another must come after it in the file —
   `site_rating_prior()` sits above `recipes_popular` and `recipes_quick` for
   exactly that reason.
4. **A new table needs its grants and its policies in the same change.** RLS with
   no policy default-denies (reads come back empty, not as an error), and the
   grants block only covers tables that existed above it (B013).
5. **A new function needs an explicit `grant execute`** to `anon, authenticated`,
   guarded on the role existing — EXECUTE otherwise goes to `public` rather than
   to the API roles by name (B013).
6. **Numbering, once the sequence resumes**: `NNNN_snake_case_summary.sql`, four
   digits, next number wins. The CLI keys its history on that number.
7. **Verify from a dropped-schema state, not just an incremental apply**
   (Gotcha 6 / B045). A body that references an object created later in the file
   passes on any machine that already has the object and fails on a clean one.
8. **A policy, a `security definer` function, or a column grant means running
   `melos run db:rls`** — `supabase/tests/rls_matrix.sql`, the only thing here
   that exercises RLS as a signed-in user (everything else, including the rest of
   CI, runs as `postgres` and bypasses policies). If the change adds a table or a
   policy the matrix does not name, add the check in the same change: an
   unasserted policy is how B053 and B061 both survived.

## Applying

| Where | How |
| --- | --- |
| Local, from scratch | `supabase db reset` — migrations in order, then `seed.sql` + `seed_recipes.sql` |
| Local, ad hoc | `melos run db:create` (idempotent, so it is safe to repeat) |
| Local, no `psql` on PATH | pipe the file into the DB container — see [BUG-TRACKER B033](../../docs/BUG-TRACKER.md) |
| Hosted | the dashboard SQL editor, or the container `psql` + Session-pooler form in B033. While the baseline is still editable this means re-applying `0001_init.sql` whole |
