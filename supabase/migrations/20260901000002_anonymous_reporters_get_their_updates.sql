-- ════════════════════════════════════════════════════════════════════════════
--  An anonymous reporter is still the person waiting for an answer.
--
--  ── What was wrong ─────────────────────────────────────────────────────────
--  Both citizen-facing update triggers ended with the same line:
--
--      and r.is_anonymous = false;
--
--  under a comment reading "An anonymous report has no one to tell". That is
--  the one thing it is not. Anonymity on this platform means the CONSOLES
--  cannot see who reported — it has never meant the report stops belonging to
--  the person who filed it:
--
--    • reports.user_id is still set on an anonymous row. It is withheld from
--      staff by staff_reports_view and from admin by the provider's column
--      list, but it is there, and it is the citizen's.
--    • owns_report() (20260721000006) resolves purely on user_id = auth.uid()
--      and deliberately does not consult is_anonymous.
--    • report_updates_read therefore grants the anonymous reporter SELECT on
--      every approved update on their own report:
--        (status = 'approved' AND owns_report(report_id))
--    • my_reports_screen.dart filters on user_id alone, and the detail screen
--      renders ReportProgressUpdates for whatever it opens.
--
--  So the database SHOWS an anonymous citizen the agency's update, and then
--  these two triggers decline to tell them it arrived. The update is sitting
--  in the app; the only way to find it is to reopen the report and look.
--
--  That is the worst shape this can take. The citizen who chose anonymity is
--  usually the one reporting something they are nervous about — and they are
--  the only one who gets silence after the office finally responds.
--
--  ── Why removing the gate leaks nothing ────────────────────────────────────
--  A notification row is addressed BY user_id and read only by its addressee
--  (notifications' own RLS). Writing one tells the reporter something about
--  THEIR report; it discloses nothing to anybody else, and no console reads
--  this table for another user's rows. The subtitle is the update body — text
--  an agency or office wrote about the ISSUE, which the citizen can already
--  read in full on the report itself.
--
--  Note what stays: `r.user_id is not null`. A report filed with no account at
--  all genuinely has nobody to notify, and that — not anonymity — is the
--  condition the original code should have been testing. It is the only one
--  kept here.
--
--  ── Scope ──────────────────────────────────────────────────────────────────
--  Two functions, one line each. No table, policy, or grant changes; nothing
--  a console can see is altered. Idempotent: `create or replace` only, and no
--  backfill — this changes what happens NEXT. Updates approved before this
--  migration were never announced and are not re-announced, which would wake
--  people up over decisions that are already old.
-- ════════════════════════════════════════════════════════════════════════════

begin;

-- ── 1. The decision trigger (pending_approval → approved) ───────────────────
-- Rewritten whole rather than patched, for the same reason scan_endorsement is
-- in 20260831000001: this is a function the anonymity promise is attached to,
-- and a reader must see the entire body to check that promise. The ONLY change
-- from 20260829000001 is the removal of the is_anonymous predicate in the
-- citizen branch. The staff-author branch below is untouched.
create or replace function public.notify_report_update_decision()
returns trigger
language plpgsql security definer set search_path to 'public'
as $$
begin
  if new.status = old.status then return new; end if;

  -- The citizen, when an update goes live on their report.
  if new.status = 'approved' then
    begin
      insert into public.notifications
        (user_id, topic, title, subtitle, type, color_value, icon_code,
         is_approved, sent_by, reference_id)
      select r.user_id, 'report_update',
             'New update on your report',
             left(new.body, 120),
             'report_update', 4279203438, 0, true, auth.uid(), r.id::text
        from public.reports r
       where r.id = new.report_id
         -- The ONE condition that matters: is there an account to notify.
         -- is_anonymous is NOT consulted — an anonymous report still belongs
         -- to the person who filed it, and this row goes to them alone. See
         -- the header.
         and r.user_id is not null;
    exception when others then null;
    end;
  end if;

  -- The staff author, when their submission is decided. Agency-authored rows
  -- have no account to notify (author_id is null) — the scan page shows them
  -- the decision instead.
  if new.author_id is not null and new.author_id is distinct from auth.uid() then
    begin
      insert into public.notifications
        (user_id, topic, title, subtitle, type, color_value, icon_code,
         is_approved, sent_by, reference_id)
      values (
        new.author_id, 'report_update',
        case when new.status = 'approved'
             then 'Your progress update was approved'
             else 'Your progress update was returned' end,
        case when new.status = 'approved'
             then left(new.body, 120)
             else coalesce(nullif(btrim(new.rejected_reason), ''), '')
        end,
        'report_update',
        case when new.status = 'approved' then 4281257073 else 4293348412 end,
        0, true, auth.uid(), new.report_id::text
      );
    exception when others then null;
    end;
  end if;

  return new;
end;
$$;

-- ── 2. The already-approved-on-insert trigger ───────────────────────────────
-- The admin's own update, and the completion an agency's advance_endorsement
-- writes, land as 'approved' in the INSERT itself — an UPDATE-keyed trigger
-- never sees them. Same single-line change.
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
       -- See §1 and the header: an account to notify, nothing else.
       and r.user_id is not null;
  exception when others then
    -- Never roll back the update itself over a notification. House rule from
    -- staff_notifications.sql.
    null;
  end;
  return new;
end;
$$;

commit;

-- Expected after this migration:
--   * Neither notify_report_update_decision nor
--     notify_citizen_of_approved_insert mentions is_anonymous.
--   * Both still test `r.user_id is not null`.
--   * The triggers themselves are unchanged and still attached (this migration
--     replaces function bodies only).
--   * An approved update on an ANONYMOUS report with an owner now writes one
--     notification addressed to that owner.
