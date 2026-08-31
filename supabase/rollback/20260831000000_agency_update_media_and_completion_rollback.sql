-- ============================================================================
-- ROLLBACK 20260831000000  agency update media + completion account
-- ============================================================================
-- Restores advance_endorsement to its 20260829000000 two-argument-only form and
-- removes the two service-role helpers.
--
-- ⚠ CONSEQUENCES OF ROLLING THIS BACK
--   * The scan page's completion step will call a three-argument function that
--     no longer exists → PostgREST 404. Roll the CLIENT back with it.
--   * Photos already attached to agency updates STAY. The rows are ordinary
--     report_update_media rows and the citizen's read path does not care who
--     uploaded them; only the ability to add MORE goes away.
--   * Completion updates already written stay too, which is what keeps the
--     completion galleries §11 of 20260829000001 gates visible.
-- ============================================================================

begin;

-- Order matters: the two-argument forwarder calls the three-argument form, so
-- the forwarder must be replaced with the standalone body BEFORE that form is
-- dropped, or the drop leaves a function calling a missing one.
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
grant execute on function public.advance_endorsement(text, text)
  to anon, authenticated;

drop function if exists public.advance_endorsement(text, text, text);
drop function if exists
  public.attach_endorsement_update_media(text, uuid, text, text);
drop function if exists public.verify_endorsement_pin(text, text);

comment on column public.report_update_media.uploaded_by is null;

commit;
