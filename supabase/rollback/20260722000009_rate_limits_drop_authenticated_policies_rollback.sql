-- ============================================================================
-- ROLLBACK for 20260722000009_rate_limits_drop_authenticated_policies.sql
-- ============================================================================
-- Recreates both policies exactly as captured from live pg_policy on 2026-07-22.
--
-- WARNING: this re-opens rate_limits to every authenticated user — full read of
-- the limiter table and unrestricted insert (trip any key, including another
-- account's login/OTP key). Restore only to unbreak something that depended on
-- the open access, and only briefly.
--
-- This file lives in supabase/rollback/ and must NEVER be moved into
-- supabase/migrations/. Move files by exact filename, never by wildcard.
-- ============================================================================

begin;

create policy "Allow insert for authenticated users" on public.rate_limits
  as permissive for insert to authenticated
  with check (true);

create policy "Allow select for authenticated users" on public.rate_limits
  as permissive for select to authenticated
  using (true);

commit;
