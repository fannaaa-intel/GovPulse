-- Verification for migrations 20260721000000 .. 20260721000003.
-- Read-only. Run AFTER `db push`. Per supabase/README.md, a clean
-- `drop ... if exists` proves nothing — it cannot distinguish "already gone"
-- from "never matched that signature". So every check below queries the
-- catalog directly rather than trusting the migration's exit status.

-- ── 1. 20260721000000 — staff no longer read verification-assets ───────────
-- EXPECT: exactly one row, "verassets_admin_read". If "verassets_staff_read"
-- still appears, the drop did not match and the finding is still live.
select policyname, cmd, roles::text, qual
from pg_policies
where schemaname = 'storage' and tablename = 'objects'
  and policyname like 'verassets%read%'
order by policyname;

-- Belt and braces: no remaining storage policy mentions is_staff on that bucket.
-- EXPECT: 0 rows.
select policyname
from pg_policies
where schemaname = 'storage' and tablename = 'objects'
  and qual like '%verification-assets%'
  and qual like '%is_staff%';

-- ── 2. 20260721000001 — notifications admin check no longer reads metadata ─
-- EXPECT: 0 rows. Any row here means a permission decision still trusts
-- user-writable auth metadata.
select tablename, policyname, cmd, qual
from pg_policies
where schemaname = 'public'
  and (qual like '%raw_user_meta_data%' or with_check like '%raw_user_meta_data%');

-- EXPECT: exactly 6 policies on notifications, including
-- "notifications_update_admin" with BOTH using and with_check = is_admin(),
-- and NO "admin_update".
select policyname, cmd, qual, with_check
from pg_policies
where schemaname = 'public' and tablename = 'notifications'
order by policyname;

-- ── 3. 20260721000002 — one INSERT gate per table ──────────────────────────
-- EXPECT: exactly 1 INSERT policy on reports and 1 on suggestions, each
-- with_check referencing is_verified_citizen(). Two rows for either table
-- means the OR-bypass is still open.
select tablename, policyname, with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('reports', 'suggestions')
  and cmd = 'INSERT'
order by tablename, policyname;

-- EXPECT: 0 rows. No surviving policy should reference the two superseded
-- definitions of "verified".
select tablename, policyname, with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('reports', 'suggestions')
  and cmd = 'INSERT'
  and (with_check like '%verified_by%' or with_check like '%status = ''verified''%');

-- Who can actually file now. EXPECT: 4 citizens, all true.
select p.username, public.is_verified_citizen(p.id) as may_file
from public.profiles p
join public.user_roles ur on ur.user_id = p.id and ur.role_id = 3
order by p.username;

-- ── 4. 20260721000003 — officials directory is no longer public ────────────
-- EXPECT: no row with roles containing 'public' and qual 'true'.
-- "admin_profiles public read" must be absent.
select policyname, cmd, roles::text, qual
from pg_policies
where schemaname = 'public' and tablename = 'admin_profiles'
order by policyname;

-- EXPECT: 1 row — the RPC exists, is SECURITY DEFINER, search_path pinned.
select p.oid::regprocedure as signature, p.prosecdef, p.proconfig
from pg_proc p
where p.pronamespace = 'public'::regnamespace
  and p.proname = 'find_available_staff';

-- EXPECT: execute granted to authenticated, NOT to anon or public.
select grantee, privilege_type
from information_schema.role_routine_grants
where routine_schema = 'public' and routine_name = 'find_available_staff'
order by grantee;

-- ── Cross-cutting: nothing was widened ─────────────────────────────────────
-- EXPECT: 0 rows. No policy in public should be `to public using (true)`.
select tablename, policyname, cmd
from pg_policies
where schemaname = 'public'
  and roles::text like '%public%'
  and coalesce(qual, 'true') = 'true'
  and cmd = 'SELECT'
order by tablename, policyname;
