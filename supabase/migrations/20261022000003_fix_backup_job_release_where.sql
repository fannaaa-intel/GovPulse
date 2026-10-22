-- ─────────────────────────────────────────────────────────────────────────────
-- Fix: every backup/restore claim leaked, so the NEXT job was told
-- "Another backup or restore is running" for 15 minutes.
--
-- `backup_job_release()` was a LANGUAGE sql function whose whole body was
--
--     delete from public.backup_jobs;
--
-- A LANGUAGE sql function with a single statement is INLINED into the calling
-- statement, so when the edge function calls it over PostgREST that bare DELETE
-- is what the request executes. This project runs pg-safeupdate, which rejects
-- an unqualified DELETE:
--
--     400 {"code":"21000","message":"DELETE requires a WHERE clause"}
--
-- So the release failed EVERY time. It never deleted anything. The claim row sat
-- there until the 900-second stale takeover in backup_job_claim expired it, and
-- any backup or restore started inside that window was correctly — but
-- misleadingly — told that another job was running.
--
-- Reproduced live on 2026-10-22: a manual backup completed at 09:17:09 and left
-- its `kind = 'create'` claim behind; restore attempts at 09:24 and 09:28 both
-- answered "busy" with nothing actually running. Replaying the release RPC
-- returned the 21000 above, and the row survived the call.
--
-- The caller never saw it: withJobLock only console.error's a release failure,
-- because failing to release must not fail an otherwise successful backup.
--
-- Two changes:
--
--   1. The DELETE carries a WHERE clause, so the guardrail passes. `id` is the
--      single-row primary key (always true), so `where id` deletes the claim
--      without narrowing what the function means.
--
--   2. The body is plpgsql, not sql. That stops the inlining that exposed the
--      statement to the guardrail in the first place, so a future edit to this
--      body cannot silently reintroduce the same failure.
--
-- Written so release stays idempotent: releasing when no claim is held is not an
-- error, which is what lets withJobLock call it unconditionally in a finally.
-- ─────────────────────────────────────────────────────────────────────────────

begin;

create or replace function public.backup_job_release()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- `where id` is the primary key and is always true for the one allowed row.
  -- It is here to satisfy pg-safeupdate's "DELETE requires a WHERE clause"
  -- guardrail, which an unqualified DELETE fails over PostgREST.
  delete from public.backup_jobs where id;
end;
$$;

revoke all on function public.backup_job_release() from public, anon, authenticated;
grant execute on function public.backup_job_release() to service_role;

comment on function public.backup_job_release() is
  'Release the backup/restore claim. Idempotent. The WHERE clause is required: '
  'pg-safeupdate rejects an unqualified DELETE over PostgREST with SQLSTATE 21000.';

commit;
