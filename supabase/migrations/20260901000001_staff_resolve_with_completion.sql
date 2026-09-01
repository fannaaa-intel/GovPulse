-- ════════════════════════════════════════════════════════════════════════════
--  Resolving a report and accounting for it become ONE act, in the consoles
--  as they already are on the agency scan page.
--
--  ── What was wrong ─────────────────────────────────────────────────────────
--  `kind` on report_updates was only ever a LABEL. The console composer let an
--  office pick "Completion", and picking it wrote `kind = 'completion'` and
--  nothing else — it did not touch reports.status. So the two halves of
--  "the work is finished" were separate, optional, and in either order:
--
--    • a completion update on a report still reading in_progress, or
--    • a report moved to resolved with no account of what was done.
--
--  The second is the one the citizen feels. §11 of 20260829000001 keys the
--  citizen's completion GALLERY on an approved completion update existing, so
--  an office that resolved a report without writing one left the resident with
--  a closed report, no explanation and no photographs.
--
--  The agency scan page already refuses this. advance_endorsement (rewritten in
--  20260831000000) makes the state change and writes the completion update in
--  the same transaction, and scan_page.dart is explicit about why the two are
--  not interchangeable: "conflating them would let an agency close a report by
--  writing a sentence."
--
--  This gives the consoles the same contract. The Progress/Completion picker
--  goes; a completion is what RESOLVING produces, never what typing produces.
--
--  ── Why an RPC and not two writes from the client ──────────────────────────
--  Two sequential client writes have a gap between them, and a failure in that
--  gap lands on exactly the desync this migration exists to delete — a resolved
--  report whose explanation never got written. One transaction or neither.
--
--  Idempotent: `create or replace`, and no data is rewritten.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1. Resolve + account, atomically ────────────────────────────────────────
--
-- Mirrors advance_endorsement's completion branch, with the authorisation
-- swapped: an agency proves itself with a PIN against a token, staff prove
-- themselves with role_id 2 plus staff_can_see_report — the same two checks
-- staff_set_report_status has always made.
create or replace function public.staff_resolve_report(
  p_report uuid,
  p_body   text
)
returns json
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_status text;
  v_office text;
  v_update uuid;
  v_rows   integer;
begin
  if public.current_user_role_id() <> 2 then
    raise exception 'not staff' using errcode = '42501';
  end if;

  if not public.staff_can_see_report(p_report) then
    raise exception 'report not in your department' using errcode = '42501';
  end if;

  -- Checked before anything is written. The note is REQUIRED here, as it is on
  -- the scan page: resolving is the moment the citizen is told the work is
  -- done, and "done" with no account of what was done is the complaint this
  -- whole line of work started from.
  if coalesce(btrim(p_body), '') = '' then
    return json_build_object('ok', false, 'error', 'body_required');
  end if;

  -- Lock the row so two officers pressing Resolve at once cannot both write a
  -- completion update. The second sees already_resolved and writes nothing.
  select status,
         coalesce(assigned_to_department, endorsed_to_department)
    into v_status, v_office
    from public.reports
   where id = p_report
   for update;

  if not found then
    return json_build_object('ok', false, 'error', 'not_found');
  end if;

  if v_status = 'resolved' then
    return json_build_object('ok', false, 'error', 'already_resolved',
                             'status', v_status);
  end if;

  -- A rejected report is closed on the admin's authority, not this office's,
  -- and must not be talked back open by an office filing a completion.
  if v_status = 'rejected' then
    return json_build_object('ok', false, 'error', 'report_rejected',
                             'status', v_status);
  end if;

  update public.reports
     set status     = 'resolved',
         updated_at = now()
   where id = p_report
     and status = v_status;

  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    -- Someone moved it between the SELECT and here despite the lock (a trigger,
    -- an admin action). Nothing was written; say so rather than reporting a
    -- completion that did not happen.
    return json_build_object('ok', false, 'error', 'already_advanced',
                             'status', v_status);
  end if;

  -- pending_approval like every other office word: the admin still decides what
  -- reaches the citizen. Approving this row is also what releases the citizen's
  -- completion gallery — §11 of 20260829000001.
  insert into public.report_updates
    (report_id, body, kind, status, author_id, author_role, author_name)
  values
    (p_report, btrim(p_body), 'completion', 'pending_approval',
     auth.uid(), 'staff', coalesce(v_office, 'Assigned office'))
  returning id into v_update;

  return json_build_object('ok', true, 'status', 'resolved',
                           'update_id', v_update);
end
$$;

revoke all on function public.staff_resolve_report(uuid, text) from public;
grant execute on function public.staff_resolve_report(uuid, text) to authenticated;

comment on function public.staff_resolve_report(uuid, text) is
  'Staff-only: move a report to resolved AND write its completion update in one '
  'transaction. The note is required. Use this instead of '
  'staff_set_report_status(id, ''resolved'') — that path leaves a closed report '
  'with no account of the work, and no completion gallery for the citizen.';

-- ── 2. Close the back door on the old path ──────────────────────────────────
--
-- staff_set_report_status stays — it is still how under_review and in_progress
-- are set — but it stops accepting 'resolved'. Left open, an older app build or
-- a future caller could still produce the unaccounted-for closure this
-- migration exists to prevent, and the RPC would look like a suggestion rather
-- than the contract.
--
-- 'rejected' goes with it: that was never staff's to set. The list here has
-- allowed it since 20260722000000 while the console has never offered it, so
-- this is closing a gap between the grant and the intent, not removing a
-- capability anyone uses.
create or replace function public.staff_set_report_status(p_report uuid, p_status text)
returns void language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  if public.current_user_role_id() <> 2 then
    raise exception 'not staff' using errcode = '42501';
  end if;

  -- ⚠ 'resolved' is deliberately NOT in this list — see staff_resolve_report.
  -- Resolving writes a completion update in the same transaction, and a status
  -- update alone cannot. 'rejected' is the admin's call, never an office's.
  if p_status not in ('pending','under_review','in_progress') then
    raise exception
      'invalid status for staff: % (resolve via staff_resolve_report)', p_status
      using errcode = '22023';
  end if;

  if not public.staff_can_see_report(p_report) then
    raise exception 'report not in your department' using errcode = '42501';
  end if;

  update public.reports
     set status = p_status,
         updated_at = now()
   where id = p_report;
end
$$;

revoke all on function public.staff_set_report_status(uuid,text) from public;
grant execute on function public.staff_set_report_status(uuid,text) to authenticated;
