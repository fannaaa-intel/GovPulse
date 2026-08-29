-- ============================================================================
-- 20260829000003  Tell the admins an update is waiting on them
-- ============================================================================
-- 20260829000001 notifies two audiences when a progress update is DECIDED: the
-- citizen when it goes live, and the staff author when it is approved or
-- returned. Both fire on UPDATE OF status — i.e. after an admin has already
-- acted.
--
-- Nothing fires when the update is SUBMITTED. So an office (or an agency, via
-- the scan page) posts something, it sits in pending_approval, and the only way
-- an admin ever learns of it is by opening that specific report and looking.
-- The whole loop is gated on a review that nobody is told to perform.
--
-- This adds the missing half: an INSERT trigger that notifies every admin when
-- an update lands needing a decision.
--
-- ── WHY EVERY ADMIN, AND NOT ONE ───────────────────────────────────────────
-- There is no assignment model for reviews — any admin may approve any update.
-- Picking one would invent a routing rule the rest of the system does not have,
-- and would leave the update unseen if that person is off duty. This matches
-- notify_staff_report_endorsed, which likewise fans out to the whole matching
-- group rather than choosing a recipient.
--
-- ── PUSH COMES FREE ────────────────────────────────────────────────────────
-- trg_push_on_notification (20260722000016, verified enabled live) fires on any
-- notifications row with a non-null user_id and is_approved = true, and posts
-- it to the send-push Edge Function. Every insert here has both, so these
-- arrive as push notifications without anything further.
--
-- Rollback: supabase/rollback/20260829000003_notify_admins_of_pending_updates_rollback.sql
-- Verify:   supabase/diagnostics/verify_20260829000003.sql
-- ============================================================================

begin;

create or replace function public.notify_admins_of_pending_update()
returns trigger
language plpgsql security definer set search_path to 'public'
as $$
begin
  -- Only a submission awaiting review. An admin's own update is auto-approved
  -- by trg_auto_approve_admin_update (which is also a BEFORE INSERT trigger and
  -- has already run by the time this AFTER trigger fires), so it arrives here
  -- already 'approved' and correctly produces no "review this" ping.
  if new.status is distinct from 'pending_approval' then
    return new;
  end if;

  begin
    insert into public.notifications
      (user_id, topic, title, subtitle, type, color_value, icon_code,
       is_approved, sent_by, reference_id)
    select ur.user_id,
           'report_update',
           case when new.kind = 'completion'
                then 'Completion update needs review'
                else 'Progress update needs review' end,
           -- Who wrote it matters more than what it says at the bell: the admin
           -- decides whether to open the report from this line.
           new.author_name || ': ' || left(new.body, 90),
           'report_update',
           4294940672,   -- 0xFFFFA000, amber: awaiting action, not yet good news
           0,
           true,
           -- The submitter, not the recipient. auth.uid() is NULL for an agency
           -- posting through the scan page, which is the office-not-person shape
           -- the rest of this schema uses.
           new.author_id,
           new.report_id::text
      from public.user_roles ur
     where ur.role_id = 1
       -- No self-ping: an admin who somehow submits a pending row does not need
       -- telling about it.
       and ur.user_id is distinct from new.author_id;
  exception when others then
    -- A notification failure must never roll back the update itself. House rule
    -- from staff_notifications.sql.
    null;
  end;

  return new;
end;
$$;

drop trigger if exists trg_notify_admins_of_pending_update
  on public.report_updates;
create trigger trg_notify_admins_of_pending_update
  after insert on public.report_updates
  for each row execute function public.notify_admins_of_pending_update();

commit;

-- Expected after this migration:
--   * trg_notify_admins_of_pending_update exists on report_updates (AFTER
--     INSERT).
--   * A staff or agency submission inserts one notification per admin.
--   * An admin's own (auto-approved) update inserts none.
