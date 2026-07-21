-- P1.4 (part 1 of 2) — Additive only. Safe to apply at any time.
--
-- Creates the replacement read path for the one legitimate consumer of the
-- `admin_profiles public read` policy, so that policy can be dropped in
-- 20260721000004 without breaking anything.
--
-- The consumer: ticket_repository.dart:188 `findAvailableStaffId(department)`.
-- It runs as a CITIZEN when a ticket is created, to route that ticket to an
-- on-duty staff member. A citizen has no other policy granting read on other
-- users' `admin_profiles` rows, so dropping the public read without this would
-- break routing — silently, because the call site catches the error and returns
-- null, which the caller treats as "nobody on duty" and hands to the bot.
--
-- This function answers the one question that call site asks and returns
-- nothing else. It is a strict reduction versus the policy it replaces:
--   before — every column of every row, to anyone holding the anon key
--   after  — one user_id, for one department, to authenticated callers only
--
-- Deliberately NOT narrowed: the body preserves the existing query exactly
-- (department + is_online, no role filter), so routing behaviour is unchanged
-- by this migration. Adding `and role_id = 2` would also be correct — admins
-- are not meant to be ticket assignees — but that is a routing change, not a
-- security change, and belongs in its own migration.
--
-- SPLIT DELIBERATELY. This file is separated from the policy drop so the
-- ordering is enforced by the migration sequence rather than by remembering:
--   1. apply this (harmless on its own — nothing calls it yet)
--   2. deploy the Dart change and CONFIRM the running build calls the RPC
--   3. apply 20260721000004, which drops the policy
-- Applying the drop before a build that uses the RPC is live will break ticket
-- routing silently.

create or replace function public.find_available_staff(p_department text)
returns uuid
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
  select ap.user_id
  from public.admin_profiles ap
  where ap.department = p_department
    and ap.is_online = true
  limit 1;
$$;

revoke all on function public.find_available_staff(text) from public;
grant execute on function public.find_available_staff(text) to authenticated;
