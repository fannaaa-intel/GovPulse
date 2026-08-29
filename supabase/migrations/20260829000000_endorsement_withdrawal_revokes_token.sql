-- ============================================================================
-- 20260829000000  Withdrawing an endorsement REVOKES the printed letter's token
-- ============================================================================
-- Closes the "zombie QR" defect found while auditing the endorse-to-agency flow
-- (see 20260801000000 for the flow itself).
--
-- ── THE DEFECT ─────────────────────────────────────────────────────────────
-- Three paths take a report back from an external agency:
--
--   1. admin clears the endorsement   (AdminReportsNotifier.clearEndorsement)
--   2. admin accepts it internally    (AdminReportsNotifier.accept)
--   3. staff bounce it to triage      (public.staff_return_to_triage)
--
-- All three null `reports.endorsed_to_department`, and ALL THREE left
-- `report_endorsements` untouched — token live, state unchanged. The letter the
-- agency is holding therefore kept working: `scan_endorsement` still resolved
-- it, and `advance_endorsement` still drove `reports.status` to in_progress /
-- resolved on a report the LGU had already taken back. The citizen would be
-- told their report was resolved by an agency that no longer owned it.
--
-- The original migration's comment ("the row is left in place so the transition
-- history survives; a later re-endorsement overwrites it") is right about the
-- history and wrong about the consequence: nothing was invalidating the token
-- in the meantime.
--
-- ── THE FIX ────────────────────────────────────────────────────────────────
-- A new terminal state, 'withdrawn', plus a revoke helper that every withdrawal
-- path calls. History is still preserved — the row and its event log stay, and
-- the transition is appended to report_endorsement_events like any other. What
-- goes away is the token's ability to authorise anything:
--
--   * token is rotated to a value no letter carries ('revoked:' || gen_random_uuid())
--     rather than nulled, because the column is NOT NULL and UNIQUE. Rotation
--     also means a stale QR gets the same uniform 'valid: false' as a made-up
--     token — it does not reveal that it was once real.
--   * pin_hash is rotated to a bcrypt of a random secret nobody holds, so even
--     a leaked PIN authorises nothing.
--
-- Re-endorsing after a withdrawal still works: endorse_report_to_agency's
-- ON CONFLICT already overwrites token, pin_hash and state unconditionally.
--
-- ── WHY 'withdrawn' IS SAFE TO ADD TO THE CHECK ────────────────────────────
-- report_endorsements.state is read by scan_endorsement (returned verbatim to
-- the agency page) and by advance_endorsement (which switches on it). The scan
-- page's Dart enum maps any unknown string to _State.endorsed, so a withdrawn
-- row must never reach it — and it cannot, because the token is rotated in the
-- same statement. advance_endorsement gets an explicit guard below regardless:
-- defence in depth, and it keeps the function correct if a future caller ever
-- resolves a row some other way.
--
-- Rollback: supabase/rollback/20260829000000_endorsement_withdrawal_revokes_token_rollback.sql
-- Verify:   supabase/diagnostics/verify_20260829000000.sql
-- ============================================================================

begin;

-- ── 1. Allow the new terminal state ────────────────────────────────────────
alter table public.report_endorsements
  drop constraint if exists report_endorsements_state_check;

alter table public.report_endorsements
  add constraint report_endorsements_state_check
  check (state in ('endorsed', 'received', 'completed', 'withdrawn'));

-- ── 2. The revoke helper ───────────────────────────────────────────────────
-- Definer, and deliberately NOT granted to anon: withdrawal is an LGU action.
-- Callable by an admin (any report) or by staff on a report they can see, which
-- is exactly the set of callers the three withdrawal paths run as.
--
-- Idempotent: a report with no endorsement, or one already withdrawn, is a
-- no-op returning false rather than an error. All three call sites run this
-- alongside other work and must not fail because there was nothing to revoke.
create or replace function public.revoke_endorsement(p_report uuid)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  e public.report_endorsements%rowtype;
begin
  if not (public.is_admin() or public.staff_can_see_report(p_report)) then
    raise exception 'Not authorised to withdraw this endorsement'
      using errcode = '42501';
  end if;

  select * into e
    from public.report_endorsements
   where report_id = p_report
   for update;

  if not found or e.state = 'withdrawn' then
    return false;
  end if;

  update public.report_endorsements
     set state        = 'withdrawn',
         -- Rotated, not nulled: the column is NOT NULL and UNIQUE. The printed
         -- QR now resolves to nothing, indistinguishably from a bogus token.
         token        = 'revoked:' || gen_random_uuid()::text,
         -- A leaked PIN must not authorise anything either. The plaintext of
         -- this hash is discarded — nobody, including us, can produce it.
         pin_hash     = extensions.crypt(
                          encode(extensions.gen_random_bytes(24), 'base64'),
                          extensions.gen_salt('bf', 10)),
         pin_attempts = 0,
         locked_until = null,
         updated_at   = now()
   where id = e.id;

  insert into public.report_endorsement_events
    (endorsement_id, report_id, from_state, to_state, actor)
  values (e.id, p_report, e.state, 'withdrawn', 'admin');

  return true;
end;
$function$;

revoke all on function public.revoke_endorsement(uuid) from public, anon;
grant execute on function public.revoke_endorsement(uuid) to authenticated;

-- ── 3. staff_return_to_triage revokes as it bounces ────────────────────────
-- Rewritten from 20260722000000 with the revoke added. Everything else is
-- byte-identical to the live definition.
create or replace function public.staff_return_to_triage(p_report uuid)
returns void language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  if public.current_user_role_id() <> 2 then
    raise exception 'not staff' using errcode = '42501';
  end if;
  if not public.staff_can_see_report(p_report) then
    raise exception 'report not in your department' using errcode = '42501';
  end if;

  -- BEFORE the update: revoke_endorsement re-checks authority through
  -- staff_can_see_report(), which stops matching the instant the department
  -- columns below are nulled. Same ordering contract the audit note has.
  perform public.revoke_endorsement(p_report);

  update public.reports
     set status = 'pending',
         assigned_to_department = null,
         endorsed_to_department = null,
         updated_at = now()
   where id = p_report;
end
$$;

revoke all on function public.staff_return_to_triage(uuid) from public, anon;
grant execute on function public.staff_return_to_triage(uuid) to authenticated;

-- ── 4. Admin-side withdrawal, as one transaction ───────────────────────────
-- The Dart previously cleared the three columns with a bare PostgREST UPDATE.
-- That cannot also revoke the token, and two round trips can half-succeed. This
-- RPC does both atomically, and re-checks admin rights server-side.
create or replace function public.clear_report_endorsement(p_report uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not public.is_admin() then
    raise exception 'Only an LGU admin can withdraw an endorsement'
      using errcode = '42501';
  end if;

  perform public.revoke_endorsement(p_report);

  update public.reports
     set endorsed_to_department = null,
         endorsed_at            = null,
         endorsed_by            = null,
         updated_at             = now()
   where id = p_report;
end;
$function$;

revoke all on function public.clear_report_endorsement(uuid) from public, anon;
grant execute on function public.clear_report_endorsement(uuid) to authenticated;

-- ── 5. Accepting internally also revokes ───────────────────────────────────
-- Admin ACCEPT routes a report to an internal office and, per
-- AdminReportsNotifier.accept, clears any external endorsement in the same
-- write. Same defect, same fix: a trigger, because accept() is a plain
-- PostgREST UPDATE and turning it into an RPC would rewrite a working triage
-- path for one line of cleanup.
--
-- Fires only on the transition to NULL, so re-endorsing (null -> agency) and
-- switching agencies (agency -> other agency, handled by the RPC's ON CONFLICT)
-- are untouched.
create or replace function public.revoke_endorsement_on_clear()
returns trigger
language plpgsql security definer set search_path to 'public'
as $$
begin
  if old.endorsed_to_department is not null
     and new.endorsed_to_department is null then
    -- Guarded: this is cleanup riding on someone else's triage write, and a
    -- failure here must never roll back the accept itself.
    begin
      perform public.revoke_endorsement(new.id);
    exception when others then null;
    end;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_revoke_endorsement_on_clear on public.reports;
create trigger trg_revoke_endorsement_on_clear
  after update of endorsed_to_department on public.reports
  for each row execute function public.revoke_endorsement_on_clear();

-- ── 6. advance_endorsement refuses a withdrawn row ─────────────────────────
-- Unreachable today (the token is rotated, so no letter resolves the row) but
-- asserted anyway — the guard is what makes the invariant true by construction
-- rather than by the token rotation happening to be correct.
create or replace function public.advance_endorsement(
  p_token text,
  p_pin   text
)
returns json
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  e         public.report_endorsements%rowtype;
  v_next    text;
  v_rows    integer;
  v_left    integer;
  c_max_attempts constant integer := 5;
begin
  select * into e
    from public.report_endorsements
   where token = p_token
   for update;

  if not found then
    return json_build_object('ok', false, 'error', 'invalid_token');
  end if;

  -- Checked before the lock and before the PIN: a withdrawn endorsement is not
  -- a credential problem and must not consume attempts or report a lockout.
  if e.state = 'withdrawn' then
    return json_build_object('ok', false, 'error', 'withdrawn',
                             'state', 'withdrawn');
  end if;

  if e.locked_until is not null and e.locked_until > now() then
    return json_build_object('ok', false, 'error', 'locked',
                             'locked_until', e.locked_until);
  end if;

  if e.state = 'completed' then
    return json_build_object('ok', false, 'error', 'already_completed',
                             'state', 'completed');
  end if;

  if e.pin_hash is distinct from extensions.crypt(coalesce(p_pin, ''), e.pin_hash) then
    v_left := greatest(c_max_attempts - (e.pin_attempts + 1), 0);
    update public.report_endorsements
       set pin_attempts = pin_attempts + 1,
           locked_until = case
                            when pin_attempts + 1 >= c_max_attempts
                              then now() + interval '15 minutes'
                            else locked_until
                          end,
           updated_at   = now()
     where id = e.id;
    return json_build_object('ok', false, 'error', 'bad_pin',
                             'attempts_left', v_left);
  end if;

  v_next := case e.state when 'endorsed' then 'received'
                         when 'received' then 'completed' end;

  update public.report_endorsements
     set state        = v_next,
         received_at  = case when v_next = 'received'  then now() else received_at  end,
         completed_at = case when v_next = 'completed' then now() else completed_at end,
         pin_attempts = 0,
         locked_until = null,
         updated_at   = now()
   where id = e.id
     and state = e.state;

  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    return json_build_object('ok', false, 'error', 'already_advanced',
                             'state', e.state);
  end if;

  insert into public.report_endorsement_events
    (endorsement_id, report_id, from_state, to_state, actor)
  values (e.id, e.report_id, e.state, v_next, 'agency');

  update public.reports
     set status = case when v_next = 'received' then 'in_progress' else 'resolved' end
   where id = e.report_id;

  return json_build_object('ok', true, 'state', v_next);
end;
$function$;

revoke all on function public.advance_endorsement(text, text) from public;
grant execute on function public.advance_endorsement(text, text) to anon, authenticated;

commit;

-- Expected after this migration:
--   * report_endorsements.state accepts 'withdrawn'.
--   * revoke_endorsement / clear_report_endorsement exist, authenticated-only.
--   * trg_revoke_endorsement_on_clear fires on reports.endorsed_to_department.
--   * staff_return_to_triage revokes BEFORE nulling the department columns.
--   * advance_endorsement returns error 'withdrawn' for a withdrawn row.
