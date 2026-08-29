-- ============================================================================
-- 20260829000004  Tell the citizen when an update is born approved
-- ============================================================================
-- notify_report_update_decision fires AFTER UPDATE OF status, which is right
-- for the path it was written for: an office submits as pending_approval, an
-- admin approves, the status CHANGES, the citizen is told.
--
-- An admin's own update never takes that path. trg_auto_approve_admin_update is
-- a BEFORE INSERT trigger that stamps status = 'approved' on the row as it is
-- written, so it arrives already approved and no UPDATE ever occurs. The
-- citizen-facing notification therefore never fired for anything an admin
-- posted — the update appeared on their report silently.
--
-- ── WHY A SECOND TRIGGER AND NOT A WIDER ONE ───────────────────────────────
-- Adding INSERT to the existing trigger's event list looks tempting and is
-- wrong: that function reads OLD (`if new.status = old.status then return new`),
-- and OLD is NULL on an INSERT, so the very first line would raise. It also
-- notifies the AUTHOR on a decision, which is meaningless for a row whose
-- author is the person approving it.
--
-- So this is a separate, narrower trigger: AFTER INSERT, only for rows that
-- arrive already approved, and it tells only the citizen.
--
-- ── NO DOUBLE NOTIFICATION ─────────────────────────────────────────────────
-- The two are mutually exclusive by construction. A row inserted as
-- 'pending_approval' does not satisfy this trigger's WHEN clause, and a row
-- inserted as 'approved' never undergoes the status change the other trigger
-- keys on. An admin who later re-approves an already-approved row changes
-- nothing, and `new.status = old.status` returns early there.
--
-- Rollback: supabase/rollback/20260829000004_notify_citizen_on_approved_insert_rollback.sql
-- Verify:   supabase/diagnostics/verify_20260829000004.sql
-- ============================================================================

begin;

create or replace function public.notify_citizen_of_approved_insert()
returns trigger
language plpgsql security definer set search_path to 'public'
as $$
begin
  begin
    insert into public.notifications
      (user_id, topic, title, subtitle, type, color_value, icon_code,
       is_approved, sent_by, reference_id)
    select r.user_id,
           'report_update',
           'New update on your report',
           left(new.body, 120),
           'report_update',
           4279203438,
           0,
           true,
           auth.uid(),
           -- The REPORT id, not the update id: every surface's tap handler
           -- resolves this to a report and opens its detail screen.
           r.id::text
      from public.reports r
     where r.id = new.report_id
       and r.user_id is not null
       -- An anonymous report has nobody to tell, the same rule
       -- notify_report_update_decision applies.
       and r.is_anonymous = false;
  exception when others then
    -- Never roll back the update itself over a notification. House rule from
    -- staff_notifications.sql.
    null;
  end;
  return new;
end;
$$;

drop trigger if exists trg_notify_citizen_of_approved_insert
  on public.report_updates;
create trigger trg_notify_citizen_of_approved_insert
  after insert on public.report_updates
  -- The WHEN clause is what keeps this from overlapping the decision trigger:
  -- it fires only for rows that were ALREADY approved when written, which is
  -- exactly the case the UPDATE-keyed trigger cannot see.
  for each row when (new.status = 'approved')
  execute function public.notify_citizen_of_approved_insert();

commit;

-- Expected after this migration:
--   * An admin-posted update notifies the citizen (and pushes, since
--     trg_push_on_notification fires on any targeted approved row).
--   * A staff/agency submission still notifies nobody until it is approved.
--   * No update produces two citizen notifications.
