# `rollback/` — restore points, never applied

Files here are **not migrations**. `supabase db push` does not read this
directory and will never apply anything in it. Nothing here is recorded in
`supabase_migrations.schema_migrations`.

Each file restores the state that existed *before* a specific numbered
migration, and is named for the migrations it reverts.

## Why this exists

The DDL in these files is generated from live `pg_policies` **before** the
corresponding migration is applied — not reconstructed afterwards from memory or
from the repo. A rollback written while production is broken is a rollback
written badly, so it gets written while everything is healthy.

This matters more than usual here because
`migrations/20260716155045_remote_schema.sql` is 0 bytes: the baseline
`supabase db pull` never completed, so the repo does not contain the schema.
Until that is fixed, the live database is the only source of truth, and a
captured restore point is the only written record of a policy's prior state.

## How to use one

1. Run only the section for the migration you are reverting, and run it whole.
2. Re-run the matching `diagnostics/verify_*.sql`. Expect it to report the
   ORIGINAL state — that is how you know the revert landed. Per the note in
   `../README.md`, a clean `drop ... if exists` proves nothing on its own.
3. Fix forward in the same session.

## Read the warnings

Reverting undoes a security fix. Some reverts restore an actively exploitable
condition — reverting `20260721000001`, for example, restores a privilege
escalation path that any citizen can trigger through `auth.updateUser()`. Each
file states this at the top. Reverts are for restoring service, not for leaving
in place.
