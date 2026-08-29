-- ============================================================================
-- 20260829000002  Who withdrew an endorsement, and why
-- ============================================================================
-- report_endorsement_events records that a transition happened and whether it
-- came from 'admin' or 'agency'. For the agency side that is the whole truth —
-- they hold no account, so there is no person to name (the office-not-person
-- shape 20260722000017 settled on).
--
-- For the LGU side it is not enough. Withdrawing an endorsement voids a signed
-- letter that went out over the Mayor's signature and revokes the credential
-- the agency was given. "An admin did this, at 14:32" leaves nobody to ask
-- about it afterwards, and no record of the justification — while ENDORSING has
-- required a written reason since 20260801000000. The two halves of the same
-- decision were held to different standards.
--
-- This adds actor_id and reason to the event log, and threads a reason through
-- the withdrawal paths that have a human behind them. The trigger path
-- (accepting a report internally) supplies its own: nobody typed anything
-- there, but the cause is known exactly.
--
-- Rollback: supabase/rollback/20260829000002_endorsement_withdrawal_accountability_rollback.sql
-- Verify:   supabase/diagnostics/verify_20260829000002.sql
-- ============================================================================

begin;

-- ── 1. Columns ─────────────────────────────────────────────────────────────
-- Both nullable: every row written before this migration has neither, and an
-- agency-actor row legitimately has no actor_id forever.
alter table public.report_endorsement_events
  add column if not exists actor_id uuid references auth.users(id) on delete set null;

alter table public.report_endorsement_events
  add column if not exists reason text;

-- ── 2. revoke_endorsement carries the reason ───────────────────────────────
-- New optional parameter, defaulted, so the existing three-call-site contract
-- keeps compiling. Replaces the 20260829000000 definition.
create or replace function public.revoke_endorsement(
  p_report uuid,
  p_reason text default null
)
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
    (endorsement_id, report_id, from_state, to_state, actor, actor_id, reason)
  values (e.id, p_report, e.state, 'withdrawn', 'admin',
          auth.uid(), nullif(btrim(p_reason), ''));

  return true;
end;
$function$;

revoke all on function public.revoke_endorsement(uuid, text) from public, anon;
grant execute on function public.revoke_endorsement(uuid, text) to authenticated;

-- The single-argument form from 20260829000000 is now ambiguous against the
-- defaulted two-argument one — PL/pgSQL cannot resolve revoke_endorsement(uuid)
-- between them. Drop it; every caller is updated below.
drop function if exists public.revoke_endorsement(uuid);

-- ── 3. Admin withdrawal takes a reason ─────────────────────────────────────
create or replace function public.clear_report_endorsement(
  p_report uuid,
  p_reason text default null
)
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

  perform public.revoke_endorsement(p_report, p_reason);

  update public.reports
     set endorsed_to_department = null,
         endorsed_at            = null,
         endorsed_by            = null,
         updated_at             = now()
   where id = p_report;
end;
$function$;

revoke all on function public.clear_report_endorsement(uuid, text)
  from public, anon;
grant execute on function public.clear_report_endorsement(uuid, text)
  to authenticated;

drop function if exists public.clear_report_endorsement(uuid);

-- ── 4. The other two paths name themselves ─────────────────────────────────
-- Neither has a human typing a justification, but both know exactly why they
-- fired — which is the useful half. Recording it beats a null.
create or replace function public.revoke_endorsement_on_clear()
returns trigger
language plpgsql security definer set search_path to 'public'
as $$
begin
  if old.endorsed_to_department is not null
     and new.endorsed_to_department is null then
    begin
      perform public.revoke_endorsement(
        new.id,
        'Endorsement cleared when the report was routed to an internal office.');
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

  -- BEFORE the update — revoke_endorsement re-checks staff_can_see_report(),
  -- which stops matching the instant the columns below are nulled.
  perform public.revoke_endorsement(
    p_report,
    'Returned to the admin triage desk by the receiving office.');

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

commit;

-- Expected after this migration:
--   * report_endorsement_events has actor_id and reason.
--   * revoke_endorsement / clear_report_endorsement take (uuid, text); the
--     single-argument overloads are gone (they would be ambiguous).
--   * Both the accept-path trigger and staff_return_to_triage record why.
