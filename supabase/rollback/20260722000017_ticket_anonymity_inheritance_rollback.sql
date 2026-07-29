-- ============================================================================
-- ROLLBACK for 20260722000017_ticket_anonymity_inheritance
-- ============================================================================
-- Restores the pre-migration state of every OBJECT the migration changed:
-- the trigger + its function, the CHECK constraint, both views, promote_ticket
-- and notify_staff_ticket_assigned.
--
-- ── WHAT CANNOT BE ROLLED BACK, AND WHY IT DOES NOT MATTER TODAY ───────────
-- Section 1 of the migration was a DATA backfill (report_id severed on
-- ownership failure, is_anonymous re-derived, uuids scrubbed from details). It
-- is NOT reversible: the prior values are not recorded anywhere, and no
-- shadow/audit column was added to hold them.
--
-- This is acceptable ONLY because the backfill was provably a no-op. Confirmed
-- against the live database on 2026-07-28, immediately before applying:
--
--   concern_tickets 0 rows | ticket_messages 0 | ticket_attachments 0
--
-- Zero rows means all three UPDATEs matched nothing, so there is no prior state
-- to restore. Re-verify that count before trusting this file: if
-- concern_tickets is non-empty when you roll back, the object-level rollback
-- below is still correct but the data changes are PERMANENT.
--
-- ── RUNNING THIS RE-OPENS A LIVE P1 ────────────────────────────────────────
-- Rolling back restores the deanonymisation path: a follow-up ticket on an
-- anonymous report is once again created attributed, with the reporter's uuid,
-- the report id, and the report id again inside reference_code, all reaching
-- staff in one row through staff_tickets_view. Do this only to unblock a
-- deploy, and re-apply immediately.
-- ============================================================================

begin;

-- ── 1. Drop the trigger and its function ──────────────────────────────────
drop trigger if exists trg_concern_tickets_enforce_anonymity on public.concern_tickets;
drop function if exists public.concern_tickets_enforce_anonymity();

-- ── 2. Drop the CHECK tripwire ────────────────────────────────────────────
-- Both names: an earlier draft of the forward migration used the _no_uuid name
-- before the rule became a positive format allowlist. Dropping both makes this
-- correct against either version.
alter table public.concern_tickets
  drop constraint if exists concern_tickets_reference_code_format;
alter table public.concern_tickets
  drop constraint if exists concern_tickets_reference_code_no_uuid;

-- ── 3. Restore staff_tickets_view (report_id back, no server-side ghost
--       filter) — verbatim as created by 20260721000007 ────────────────────
-- DROP + CREATE because the migration removed a column. Dependents were
-- enumerated as ZERO before the forward migration; re-check if that has
-- changed. No CASCADE.
drop view if exists public.staff_tickets_view;

create view public.staff_tickets_view
with (security_invoker = false)
as
select
  t.id,
  t.reference_code,
  t.category,
  t.department,
  t.status,
  t.assigned_staff_id,
  t.report_id,
  t.rating,
  t.rating_comment,
  t.rated_at,
  t.is_ghost,
  t.is_anonymous,
  t.created_at,
  t.updated_at,
  t.resolved_at,
  case when t.is_anonymous then null else t.user_id         end as user_id,
  case when t.is_anonymous then null else t.contact_name     end as contact_name,
  case when t.is_anonymous then null else t.contact_number   end as contact_number,
  case when t.is_anonymous then null else t.contact_address  end as contact_address,
  case when t.is_anonymous then null else t.contact_email     end as contact_email,
  case when t.is_anonymous then null else t.contact_note      end as contact_note
from public.concern_tickets t
where public.current_user_role_id() = 2
  and t.department = public.current_staff_department();

-- DROP+CREATE re-applies Supabase's default grants. Name every grantee.
revoke all on public.staff_tickets_view from public, anon, authenticated;
grant  select on public.staff_tickets_view to authenticated;

-- ── 4. Restore staff_reports_view (duplicate_of back) — verbatim as created
--       by 20260722000000 ────────────────────────────────────────────────────
drop view if exists public.staff_reports_view;

create view public.staff_reports_view
with (security_invoker = false)
as
select
  r.id,
  case when r.is_anonymous then null else r.user_id end as user_id,
  r.category,
  r.category_other,
  r.latitude,
  r.longitude,
  r.address,
  r.remarks,
  r.is_anonymous,
  r.status,
  r.created_at,
  r.updated_at,
  r.barangay,
  r.ai_urgency,
  r.ai_urgency_reason,
  r.ai_classified_at,
  r.dismissed_at,
  r.dismissed_by,
  r.dismissed_reason,
  r.endorsed_to_department,
  r.endorsed_at,
  r.endorsed_by,
  r.assigned_to_department,
  r.assigned_at,
  r.assigned_by,
  r.rejection_note,
  r.duplicate_of,
  r.confirm_count
from public.reports r
where public.staff_can_see_report(r.id);

revoke all on public.staff_reports_view from public, anon, authenticated;
grant  select on public.staff_reports_view to authenticated;

-- ── 5. Restore promote_ticket's OR-inheritance — verbatim as created by
--       20260722000005 ───────────────────────────────────────────────────────
-- With the trigger gone this becomes the ONLY thing setting is_anonymous, so it
-- must go back or a follow-up chat on an anonymous report loses its redaction
-- entirely.
CREATE OR REPLACE FUNCTION public.promote_ticket(p_ticket uuid, p_staff uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_owner     uuid;
  v_anonymous boolean;
  v_name      text;
  v_number    text;
  v_address   text;
  v_email     text;
begin
  select user_id into v_owner from public.concern_tickets where id = p_ticket;
  if v_owner is null then
    raise exception 'ticket not found' using errcode = 'P0002';
  end if;
  if v_owner <> auth.uid() then
    raise exception 'not your ticket' using errcode = '42501';
  end if;

  -- Anonymity: the ticket's own flag, or the linked report's. Never the
  -- client's word for it.
  select ct.is_anonymous
         or coalesce((select r.is_anonymous
                        from public.reports r
                       where r.id = ct.report_id), false)
    into v_anonymous
    from public.concern_tickets ct
   where ct.id = p_ticket;

  if v_anonymous then
    update public.concern_tickets
       set assigned_staff_id = p_staff,
           is_ghost          = false,
           is_anonymous      = true,
           contact_name      = null,
           contact_number    = null,
           contact_address   = null,
           contact_email     = null,
           updated_at        = now()
     where id = p_ticket;
    return;
  end if;

  -- Attributed chat: assemble the contact block from the owner's own record.
  select nullif(btrim(concat_ws(' ', cd.first_name, cd.middle_name, cd.last_name)), ''),
         nullif(btrim(coalesce(cd.contact_number, '')), ''),
         nullif(btrim(concat_ws(', ', cd.street, cd.barangay)), '')
    into v_name, v_number, v_address
    from public.citizen_details cd
   where cd.user_id = v_owner;

  select u.email into v_email from auth.users u where u.id = v_owner;

  update public.concern_tickets
     set assigned_staff_id = p_staff,
         is_ghost          = false,
         contact_name      = v_name,
         contact_number    = v_number,
         contact_address   = v_address,
         contact_email     = v_email,
         updated_at        = now()
   where id = p_ticket;
end
$function$;

-- ── 6. Restore notify_staff_ticket_assigned's sent_by = auth.uid() ────────
CREATE OR REPLACE FUNCTION public.notify_staff_ticket_assigned()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- Fire only when a REAL ticket becomes assigned to a staff member — i.e. on a
  -- fresh assignment (insert already assigned, or the assignee just changed).
  if new.assigned_staff_id is null or coalesce(new.is_ghost, false) then
    return new;
  end if;
  if tg_op = 'UPDATE'
     and old.assigned_staff_id is not distinct from new.assigned_staff_id
     and coalesce(old.is_ghost, false) = coalesce(new.is_ghost, false) then
    return new; -- nothing relevant changed
  end if;

  begin
    insert into public.notifications
      (user_id, topic, title, subtitle, type, color_value, icon_code,
       is_approved, sent_by, reference_id)
    values (
      new.assigned_staff_id,
      'chat',
      'New citizen chat',
      'A citizen in ' || coalesce(new.department, 'your department')
        || ' wants to talk. Tap to open.',
      'chat', 4279203438, 0, true, auth.uid(), new.id::text
    );
  exception when others then
    -- Never block the ticket write on a notification failure.
    null;
  end;
  return new;
end;
$function$;

commit;
