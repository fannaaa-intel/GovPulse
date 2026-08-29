-- ============================================================================
-- ROLLBACK 20260829000000  endorsement withdrawal revokes token
-- ============================================================================
-- Restores the pre-migration definitions. NOTE: rows already moved to
-- 'withdrawn' keep their rotated token and pin_hash — those values are
-- unrecoverable by design (the plaintext PIN was discarded at revoke time), so
-- this rollback moves them to 'completed' rather than pretending they can be
-- reactivated. A withdrawn endorsement that needs to live again must be
-- re-endorsed, which mints a fresh token and PIN.
-- ============================================================================

begin;

drop trigger if exists trg_revoke_endorsement_on_clear on public.reports;
drop function if exists public.revoke_endorsement_on_clear();
drop function if exists public.clear_report_endorsement(uuid);
drop function if exists public.revoke_endorsement(uuid);

-- Park any withdrawn rows in a state the old CHECK allows before restoring it.
update public.report_endorsements
   set state = 'completed', updated_at = now()
 where state = 'withdrawn';

alter table public.report_endorsements
  drop constraint if exists report_endorsements_state_check;

alter table public.report_endorsements
  add constraint report_endorsements_state_check
  check (state in ('endorsed', 'received', 'completed'));

-- staff_return_to_triage — restored to the 20260722000000 definition.
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
  update public.reports
     set status = 'pending',
         assigned_to_department = null,
         endorsed_to_department = null,
         updated_at = now()
   where id = p_report;
end
$$;

revoke all on function public.staff_return_to_triage(uuid) from public;
grant execute on function public.staff_return_to_triage(uuid) to authenticated;

-- advance_endorsement — restored to the 20260801000000 definition (no
-- 'withdrawn' guard).
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
