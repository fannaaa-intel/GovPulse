-- 20261009000000_pin_server_owned_columns.sql
--
-- Audit 2026-10-09. Four holes where a signed-in user could write a column
-- only the server or an admin should set, by calling PostgREST directly with
-- their own session (the app never sends these values; a hand-made request does):
--
--   #1 verification_submissions — a citizen could INSERT their own row with
--      status = 'approved'. is_verified_citizen() reads exactly that, so it
--      unlocked every verified-citizen RLS gate with no admin involved.
--   #2 profiles — own_profile_update has no column limit, so a deactivated
--      user could PATCH is_deactivated = false (and status = 'verified').
--   #6 reports — a citizen could file a report already 'resolved', AI-labelled,
--      assigned, or backdated.
--   #3 notifications — staff_admin_send let staff target any citizen with
--      is_approved = true, skipping the staff_message approval loop and pushing.
--
-- VERIFIED BEFORE COMMIT: supabase/diagnostics/verify_20261009000000.sql applies
-- this file inside a transaction, runs 20 attack + normal-use checks as a real
-- citizen / staff / admin, and rolls itself back. 20/20 PASS on production.

-- Guard rule used by all three triggers:
--   current_user is 'authenticated' only for a DIRECT PostgREST call. Inside a
--   SECURITY DEFINER function (all 34 internal writers, owner postgres) it is
--   'postgres'; in edge functions it is 'service_role'. So internal paths and
--   admins are untouched, and only a citizen/staff writing straight to the
--   table gets server-owned columns reset. The functions must stay SECURITY
--   INVOKER or current_user would always read as the owner.

-- ── #1 verification_submissions: a citizen cannot self-approve ──────────────
create or replace function public.pin_verification_submission_columns()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if current_user not in ('authenticated', 'anon') or public.is_admin() then
    return new;
  end if;
  new.status         := 'pending';
  new.reviewed_by    := null;
  new.reviewed_at    := null;
  new.reviewer_notes := null;
  return new;
end;
$$;

drop trigger if exists trg_aa_pin_verification_columns on public.verification_submissions;
create trigger trg_aa_pin_verification_columns
  before insert on public.verification_submissions
  for each row execute function public.pin_verification_submission_columns();

-- ── #2 profiles: a user cannot reactivate or verify themselves ──────────────
create or replace function public.pin_profile_admin_columns()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if current_user not in ('authenticated', 'anon') or public.is_admin() then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.status         := 'unverified';
    new.is_active      := true;
    new.is_deactivated := false;
    new.deactivated_at := null;
    new.deactivated_by := null;
    new.created_by     := null;
  else
    new.id             := old.id;
    new.email          := old.email;
    new.status         := old.status;
    new.is_active      := old.is_active;
    new.is_deactivated := old.is_deactivated;
    new.deactivated_at := old.deactivated_at;
    new.deactivated_by := old.deactivated_by;
    new.created_by     := old.created_by;
    new.created_at     := old.created_at;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_aa_pin_profile_admin_columns on public.profiles;
create trigger trg_aa_pin_profile_admin_columns
  before insert or update on public.profiles
  for each row execute function public.pin_profile_admin_columns();

-- ── #6 reports: a citizen cannot file a pre-resolved / pre-labelled report ──
-- Named trg_aa_* so it sorts BEFORE trg_flatten_then_adopt_status: a confirmed
-- duplicate must still inherit its parent's status after this resets it.
create or replace function public.pin_citizen_report_columns()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if current_user not in ('authenticated', 'anon') or public.is_admin() then
    return new;
  end if;
  new.status                 := 'pending';
  new.confirm_count          := 0;
  new.created_at             := now();
  new.updated_at             := now();
  new.ai_urgency             := null;
  new.ai_urgency_reason      := null;
  new.ai_classified_at       := null;
  new.ai_category            := null;
  new.ai_department          := null;
  new.ai_endorse_hint        := null;
  new.ai_category_reason     := null;
  new.dismissed_at           := null;
  new.dismissed_by           := null;
  new.dismissed_reason       := null;
  new.endorsed_to_department := null;
  new.endorsed_at            := null;
  new.endorsed_by            := null;
  new.assigned_to_department := null;
  new.assigned_at            := null;
  new.assigned_by            := null;
  new.rejection_note         := null;
  return new;
end;
$$;

drop trigger if exists trg_aa_pin_citizen_report_columns on public.reports;
create trigger trg_aa_pin_citizen_report_columns
  before insert on public.reports
  for each row execute function public.pin_citizen_report_columns();

-- ── #3 notifications: staff may only queue an UNAPPROVED staff_message ──────
-- A policy, not a trigger: the 26 notifier functions run as the table owner
-- and bypass RLS, so this cannot touch them — whereas a trigger would see the
-- staff member's auth.uid() inside them and break report-progress pushes.
drop policy if exists staff_admin_send on public.notifications;
create policy staff_admin_send on public.notifications
  as permissive for insert to authenticated
  with check (
    sent_by = (select auth.uid())
    and (
      public.is_admin((select auth.uid()))
      or (
        public.is_staff((select auth.uid()))
        and type = 'staff_message'
        and is_approved is false
        and approved_by is null
        and coalesce(target_all, false) = false
      )
    )
  );
