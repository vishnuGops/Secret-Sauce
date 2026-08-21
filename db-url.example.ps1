# Shell-only database credential for the `melos run db:*` scripts (B034 / OPT-S7).
#
# Copy to `db-url.local.ps1` (git-ignored) and fill in the real URI, then
# dot-source it in the shell you want to run db tasks from:
#
#     . .\db-url.local.ps1
#     melos run db:create
#
# Why a dot-sourced script and not `apps/app/env.local.json`: every key in a
# dart-define file is compiled into the shipped app bundle, and this is a
# Postgres SUPERUSER credential. Why not a Windows user environment variable:
# it would be global, so a second project pointing at a different database
# would silently inherit this one — and `tool/db.dart` fires at whatever
# `SUPABASE_DB_URL` says with no confirmation and no prod guard (Gotcha 7).
# Per-shell and per-project is the combination that makes a mistake unlikely.
#
# Hosted projects need the SESSION POOLER host, not `db.<ref>.supabase.co`
# (which is IPv6-only, and the Docker psql container has no IPv6 route — B033).
# The pooler user is `postgres.<project-ref>`, not a bare `postgres`.

# Local stack (supabase start):
# $env:SUPABASE_DB_URL = "postgresql://postgres:postgres@127.0.0.1:54322/postgres"

# Hosted (Session pooler):
$env:SUPABASE_DB_URL = "postgresql://postgres.<project-ref>:<password>@aws-0-<region>.pooler.supabase.com:5432/postgres"
