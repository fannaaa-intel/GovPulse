-- ─────────────────────────────────────────────────────────────────────────────
-- ROLLBACK for 20260823000001_revoke_limiter_table_grants.sql
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Restores the EXACT pre-migration ACLs, decoded from pg_class.relacl captured
-- live on 2026-08-23:
--
--   anon=rm/postgres              -> SELECT, MAINTAIN
--   authenticated=arwdDxtm/...    -> INSERT, SELECT, UPDATE, DELETE, TRUNCATE,
--                                    REFERENCES, TRIGGER, MAINTAIN
--
-- ⚠ These grants are only harmless while RLS stays enabled with zero policies on
-- all three tables. Restoring them re-creates the single-point-of-failure the
-- forward migration removed.
-- ─────────────────────────────────────────────────────────────────────────────

begin;

grant select, maintain on table public.rate_limits     to anon;
grant select, maintain on table public.otp_failures    to anon;
grant select, maintain on table public.pending_signups to anon;

grant insert, select, update, delete, truncate, references, trigger, maintain
  on table public.rate_limits     to authenticated;
grant insert, select, update, delete, truncate, references, trigger, maintain
  on table public.otp_failures    to authenticated;
grant insert, select, update, delete, truncate, references, trigger, maintain
  on table public.pending_signups to authenticated;

commit;
