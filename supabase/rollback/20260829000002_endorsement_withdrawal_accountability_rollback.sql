-- ============================================================================
-- ROLLBACK 20260829000002  endorsement withdrawal accountability
-- ============================================================================
-- Restores the 20260829000000 single-argument signatures and drops the two
-- audit columns. ⚠ Dropping the columns DESTROYS the recorded actor and reason
-- for every withdrawal so far — drop them only if the columns themselves are
-- the problem. Reverting just the function signatures is the safer half and can
-- be done by running this file with the ALTERs at the end commented out.
-- ============================================================================

begin;

-- Two-argument forms first: the single-argument ones below would be ambiguous
-- against them.
drop function if exists public.clear_report_endorsement(uuid, text);
drop function if exists public.revoke_endorsement(uuid, text);

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
         token        = 'revoked:' || gen_random_uuid()::text,
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

-- Callers of the two-argument form, restored to the one-argument call.
create or replace function public.revoke_endorsement_on_clear()
returns trigger
language plpgsql security definer set search_path to 'public'
as $$
begin
  if old.endorsed_to_department is not null
     and new.endorsed_to_department is null then
    begin
      perform public.revoke_endorsement(new.id);
    exception when others then null;
    end;
  end if;
  return new;
end;
$$;

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

-- ⚠ Destroys the recorded audit trail. Comment these two out to keep it.
alter table public.report_endorsement_events drop column if exists reason;
alter table public.report_endorsement_events drop column if exists actor_id;

commit;
