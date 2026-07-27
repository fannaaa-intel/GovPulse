-- ============================================================================
-- ROLLBACK for 20260722000003_citizen_details_staff_lockdown.sql
-- ============================================================================
-- DDL captured verbatim from live pg_policy on 2026-07-22 BEFORE the migration
-- was applied (generated from pg_get_expr(polqual/polwithcheck), not hand-typed).
--
-- WARNING: running this restores a LIVE P1. It re-grants staff standing read of
-- every citizen's PII and unrestricted write on every citizen_details row. Use
-- only to unbreak production, and only long enough to find another way.
--
-- This file lives in supabase/rollback/ and must NEVER be moved into
-- supabase/migrations/. Move files by exact filename, never by wildcard — this
-- rollback shares its version prefix with the migration it reverses.
-- ============================================================================

begin;

-- Undo step 4: restore the loosened admin/staff read (role_id {1,2}).
drop policy if exists citizen_details_read_admin_all on public.citizen_details;

create policy citizen_details_read_admin_all on public.citizen_details
  as permissive for select to authenticated
  using ((EXISTS ( SELECT 1
     FROM user_roles ur
    WHERE ((ur.user_id = auth.uid()) AND (ur.role_id = ANY (ARRAY[(1)::bigint, (2)::bigint]))))));

-- Undo step 3.
create policy "Staff insert citizen details" on public.citizen_details
  as permissive for insert to authenticated
  with check ((EXISTS ( SELECT 1
     FROM (user_roles ur
       JOIN roles r ON ((ur.role_id = r.id)))
    WHERE ((ur.user_id = auth.uid()) AND (r.name = ANY (ARRAY['admin'::text, 'staff'::text]))))));

-- Undo step 2. NOTE: no WITH CHECK, exactly as it was — Postgres reuses USING.
create policy "Staff update citizen details" on public.citizen_details
  as permissive for update to authenticated
  using ((get_user_role(auth.uid()) = 'staff'::text));

-- Undo step 1.
create policy "Staff view all citizens" on public.citizen_details
  as permissive for select to authenticated
  using ((get_user_role(auth.uid()) = 'staff'::text));

commit;
