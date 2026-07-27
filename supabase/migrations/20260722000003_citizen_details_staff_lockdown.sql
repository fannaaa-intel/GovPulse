-- ============================================================================
-- 20260722000003  citizen_details — remove all staff access
-- ============================================================================
-- FINDING 1.5 (P1, LIVE). Staff (role_id 2) can read every citizen's PII and
-- write any column of any citizen_details row through the ordinary PostgREST
-- path. This needs no unfiltered-UPDATE trick: staff hold SELECT, so a filtered
-- UPDATE finds rows normally.
--
-- Reproduced 2026-07-22 as Test Staff (00000000-0000-0000-0000-000000000000)
-- in a rolled-back transaction:
--     citizen_details rows visible ......... 4 of 4 (name, contact, barangay, street)
--     UPDATE verified_by on another citizen  rows=1   (forged to staff's own uuid)
--     UPDATE first_name/contact_number ..... rows=1   (confirmed changed as owner)
--
-- This finding was identified in round 4, confirmed as "staff need nothing from
-- citizen_details", and then lost when the engagement pivoted to anonymity. No
-- migration ever addressed it. It has been live the entire time.
--
-- ── Why THREE policies must change together ────────────────────────────────
-- Staff read this table through TWO independent permissive policies. Permissive
-- policies OR together, so dropping either one alone changes nothing:
--
--   "Staff view all citizens"        get_user_role(auth.uid()) = 'staff'
--   citizen_details_read_admin_all   role_id = ANY(ARRAY[1,2])   <-- 2 is staff
--
-- This is the load-bearing-redundancy pattern that has already bitten this
-- codebase twice. Dropping the obvious policy and declaring victory would leave
-- staff with unchanged full read.
--
-- ── Why role_id = 1 against user_roles, and NOT is_admin(auth.uid()) ───────
-- There are two is_admin functions and they read DIFFERENT TABLES:
--     is_admin()      -> public.user_roles.role_id = 1     (authoritative)
--     is_admin(uuid)  -> public.admin_details              (near-empty)
-- `create-staff` writes profiles, user_roles and admin_profiles — it never
-- writes admin_details. admin_details currently holds exactly 1 row, the sole
-- existing admin, which is the only reason the uuid variant works at all today.
-- Narrowing this policy with is_admin(auth.uid()) would silently deny every
-- future admin access to all citizen records. We therefore inline the
-- user_roles predicate, matching the policy's own existing shape.
--
-- ── Why dropping the staff INSERT policy is safe ───────────────────────────
-- "Staff insert citizen details" is WITH CHECK role-only and row-independent,
-- so staff can fabricate a citizen_details row for ANY user_id that does not
-- yet have one, with forged contents (the PK blocks overwriting existing rows).
-- Nothing legitimately uses it:
--   * zero INSERT/upsert calls against citizen_details in lib/ or supabase/functions/
--   * the ONLY writer is handle_verification_decision(), a SECURITY DEFINER
--     trigger on verification_submissions that does INSERT ... ON CONFLICT.
--     Being DEFINER it bypasses RLS and does not consult this policy.
--   * the `provided_by_staff` column implies a staff-assisted registration flow
--     that does not exist in code (traced round 4, re-traced today).
--
-- ── Client impact: NONE (verified, not assumed) ────────────────────────────
-- Staff code never touches this table. It reads citizen identity through the
-- ticket_citizen() SECURITY DEFINER RPC, which is unaffected. The comment at
-- lib/features/staff/data/staff_repository.dart:462 already asserts "staff
-- can't read citizen_details directly" — a mitigation built around a hole that
-- was never actually closed. Every other caller is own-row (eq user_id = self)
-- or admin-only. No Dart change accompanies this migration, so no phased
-- deploy is required.
--
-- ── Adjacent, deliberately NOT fixed here ──────────────────────────────────
-- "Admin manage citizen details" still uses is_admin(auth.uid()) -> admin_details.
-- It works today only because the single existing admin happens to have a row
-- there. The next admin onboarded through create-staff will silently lose write
-- access to citizen_details. That is a separate pre-existing finding; changing
-- it here would widen access beyond this migration's stated scope.
--
-- Rollback: supabase/rollback/20260722000003_citizen_details_staff_lockdown_rollback.sql
-- Verify:   supabase/diagnostics/verify_20260722000003_citizen_details.sql
-- ============================================================================

begin;

-- 1. Staff standing read over every citizen record. No row filter at all.
drop policy if exists "Staff view all citizens" on public.citizen_details;

-- 2. Staff write over every citizen record. WITH CHECK was NULL, so Postgres
--    reused USING for the check — role-only, row-independent, every column.
drop policy if exists "Staff update citizen details" on public.citizen_details;

-- 3. Staff ability to fabricate citizen_details rows for arbitrary user_ids.
drop policy if exists "Staff insert citizen details" on public.citizen_details;

-- 4. The second, redundant staff read path. Narrow role_id {1,2} -> {1}.
--    Dropped and recreated in the same statement pair so no window exists in
--    which the loosened version is the only one present.
drop policy if exists citizen_details_read_admin_all on public.citizen_details;

create policy citizen_details_read_admin_all
  on public.citizen_details
  as permissive
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.user_roles ur
      where ur.user_id = auth.uid()
        and ur.role_id = 1        -- admin ONLY; 2 (staff) deliberately removed
    )
  );

commit;

-- Expected policy set on public.citizen_details after this migration:
--   Admin manage citizen details    ALL     is_admin(auth.uid())
--   Citizen can view own details    SELECT  user_id = auth.uid()
--   Citizen can update own details  UPDATE  auth.uid() = user_id  (+WITH CHECK)
--   citizen_details_read_admin_all  SELECT  role_id = 1
-- Total: 4 policies. Zero staff-reachable paths.
