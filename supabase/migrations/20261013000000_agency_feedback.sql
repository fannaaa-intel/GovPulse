-- ─────────────────────────────────────────────────────────────────────────────
-- 20261013000000  Citizen feedback on external agencies (panel revision item 3)
-- ─────────────────────────────────────────────────────────────────────────────
--
-- The panel asked that citizens be able to rate the external agency a report
-- was endorsed to (DPWH, DENR, DOH, BFP, PNP), and that the LGU see it as
-- agency performance. Additive only: one table, three functions, no drops.
--
-- ── WHY A NEW TABLE KEYED ON (report, agency NAME) ───────────────────────────
-- report_endorsements is UNIQUE(report_id) and re-endorsing UPSERTS that row:
-- agency, state and every timestamp are overwritten. A rating that pointed at
-- the endorsement row would silently move to the new agency. So the agency
-- name is SNAPSHOTTED here at rating time, and a report re-endorsed elsewhere
-- can carry one rating per agency it was sent to.
--
-- ── WHY CITIZENS GO THROUGH FUNCTIONS ────────────────────────────────────────
-- Citizens have no read on report_endorsements (admin + the agency's own staff
-- only). rate_agency() therefore runs SECURITY DEFINER and takes the agency
-- and state from the server, never from the client:
--   • the caller must OWN the report — anonymous reports included: is_anonymous
--     hides the reporter from consoles, it does not unown the report;
--   • the endorsement must exist and not be withdrawn;
--   • any of endorsed / received / completed may be rated — "they never even
--     acknowledged it" is exactly the feedback the panel wants recorded, and
--     endorsement_state keeps that distinguishable from a finished job;
--   • editable (upsert), rate-limited to 10 saves a day per citizen.
-- DEFINER functions are invisible to the block_suspended_writes trigger guard
-- (it only fires for current_user = authenticated/anon), so the suspension
-- check is repeated explicitly here.
--
-- Reads are ADMIN-ONLY. The citizen reads back their own rating through
-- my_agency_rating(), never the table. Agency staff do not see ratings.
--
-- ── PERFORMANCE NUMBERS ──────────────────────────────────────────────────────
-- admin_agency_performance() counts each report's CURRENT endorsement row.
-- report_endorsement_events records no agency, so a re-endorsed report's
-- earlier agency cannot be reconstructed from history; its timing counts
-- toward the agency it is endorsed to now. Ratings are unaffected (snapshot).
--
-- Verify:   supabase/diagnostics/verify_20261013000000.sql (rollback-only)
-- Rollback: drop function public.admin_agency_performance();
--           drop function public.my_agency_rating(uuid);
--           drop function public.rate_agency(uuid, integer, text);
--           drop table public.agency_feedback;
-- ─────────────────────────────────────────────────────────────────────────────

begin;

create table if not exists public.agency_feedback (
  id                uuid primary key default gen_random_uuid(),
  report_id         uuid not null references public.reports(id) on delete cascade,
  endorsement_id    uuid references public.report_endorsements(id) on delete set null,
  agency            text not null,
  user_id           uuid not null references auth.users(id) on delete cascade,
  stars             smallint not null check (stars between 1 and 5),
  comment           text check (comment is null or char_length(comment) <= 500),
  endorsement_state text not null
                    check (endorsement_state in ('endorsed', 'received', 'completed')),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (report_id, agency)
);

create index if not exists agency_feedback_agency_idx
  on public.agency_feedback (agency, updated_at desc);

alter table public.agency_feedback enable row level security;

-- Supabase's default privileges grant everything to anon/authenticated on new
-- tables. Writes only ever happen inside rate_agency(); reads are admin-only.
revoke all on public.agency_feedback from public, anon, authenticated;
grant select on public.agency_feedback to authenticated;

drop policy if exists admin_reads_agency_feedback on public.agency_feedback;
create policy admin_reads_agency_feedback on public.agency_feedback
  for select to authenticated
  using (public.is_admin());

-- ── rate_agency ──────────────────────────────────────────────────────────────
-- Returns {ok:true, agency, state, stars, comment} or {ok:false, error} for the
-- states a citizen can legitimately hit. Not owning the report is an exception:
-- the app never offers the control on someone else's report.
create or replace function public.rate_agency(
  p_report  uuid,
  p_stars   integer,
  p_comment text default null
)
returns json
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_uid     uuid := auth.uid();
  v_comment text := nullif(btrim(coalesce(p_comment, '')), '');
  e         public.report_endorsements%rowtype;
begin
  if v_uid is null or not public.owns_report(p_report) then
    raise exception 'Only the person who filed this report can rate the agency'
      using errcode = '42501';
  end if;

  if public.caller_account_blocked() then
    raise exception 'suspended'
      using errcode = 'P0001',
            hint    = 'account_suspended',
            detail  = 'Your account is suspended or deactivated. Contact the LGU to restore access.';
  end if;

  if p_stars is null or p_stars not between 1 and 5 then
    return json_build_object('ok', false, 'error', 'invalid_stars');
  end if;
  if v_comment is not null and char_length(v_comment) > 500 then
    return json_build_object('ok', false, 'error', 'comment_too_long');
  end if;

  select * into e from public.report_endorsements where report_id = p_report;
  if not found then
    return json_build_object('ok', false, 'error', 'not_endorsed');
  end if;
  if e.state = 'withdrawn' then
    return json_build_object('ok', false, 'error', 'withdrawn');
  end if;

  -- Checked last so a rejected request does not use up the allowance.
  if not public.check_rate_limit('agency_rating:' || v_uid, 10, 86400) then
    return json_build_object('ok', false, 'error', 'rate_limited');
  end if;

  insert into public.agency_feedback
    (report_id, endorsement_id, agency, user_id, stars, comment, endorsement_state)
  values
    (p_report, e.id, e.agency, v_uid, p_stars, v_comment, e.state)
  on conflict (report_id, agency) do update set
    endorsement_id    = excluded.endorsement_id,
    stars             = excluded.stars,
    comment           = excluded.comment,
    endorsement_state = excluded.endorsement_state,
    updated_at        = now();

  return json_build_object(
    'ok', true, 'agency', e.agency, 'state', e.state,
    'stars', p_stars, 'comment', v_comment);
end;
$function$;

revoke all on function public.rate_agency(uuid, integer, text) from public, anon;
grant execute on function public.rate_agency(uuid, integer, text) to authenticated;

-- ── my_agency_rating ─────────────────────────────────────────────────────────
-- What the report owner's rating card needs: whether rating is open, for which
-- agency, and the rating they already gave (to the CURRENT agency).
create or replace function public.my_agency_rating(p_report uuid)
returns json
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  e public.report_endorsements%rowtype;
  f public.agency_feedback%rowtype;
begin
  if auth.uid() is null or not public.owns_report(p_report) then
    raise exception 'Not your report' using errcode = '42501';
  end if;

  select * into e from public.report_endorsements where report_id = p_report;
  if not found or e.state = 'withdrawn' then
    return json_build_object('eligible', false);
  end if;

  select * into f from public.agency_feedback
   where report_id = p_report and agency = e.agency;

  return json_build_object(
    'eligible',   true,
    'agency',     e.agency,
    'state',      e.state,
    'stars',      f.stars,
    'comment',    f.comment,
    'updated_at', f.updated_at);
end;
$function$;

revoke all on function public.my_agency_rating(uuid) from public, anon;
grant execute on function public.my_agency_rating(uuid) to authenticated;

-- ── admin_agency_performance ─────────────────────────────────────────────────
-- One row per agency that has ever been endorsed to or rated. Day averages are
-- measured from endorsement, so "days to complete" is the whole turnaround the
-- citizen waited, not the time after the agency acknowledged it.
create or replace function public.admin_agency_performance()
returns table (
  agency               text,
  endorsements         integer,
  awaiting             integer,
  received             integer,
  completed            integer,
  withdrawn            integer,
  avg_days_to_receive  numeric,
  avg_days_to_complete numeric,
  ratings              integer,
  avg_stars            numeric
)
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
#variable_conflict use_column
begin
  if not public.is_admin() then
    raise exception 'Admins only' using errcode = '42501';
  end if;

  return query
  with e as (
    select
      re.agency,
      count(*) filter (where re.state <> 'withdrawn')::int  as endorsements,
      count(*) filter (where re.state = 'endorsed')::int    as awaiting,
      count(*) filter (where re.state in ('received', 'completed'))::int as received,
      count(*) filter (where re.state = 'completed')::int   as completed,
      count(*) filter (where re.state = 'withdrawn')::int   as withdrawn,
      round(avg(extract(epoch from re.received_at - re.endorsed_at) / 86400.0)
              filter (where re.state in ('received', 'completed')
                        and re.received_at is not null)::numeric, 1)
        as avg_days_to_receive,
      round(avg(extract(epoch from re.completed_at - re.endorsed_at) / 86400.0)
              filter (where re.state = 'completed'
                        and re.completed_at is not null)::numeric, 1)
        as avg_days_to_complete
    from public.report_endorsements re
    group by re.agency
  ),
  r as (
    select af.agency,
           count(*)::int                        as ratings,
           round(avg(af.stars)::numeric, 2)     as avg_stars
      from public.agency_feedback af
     group by af.agency
  )
  select coalesce(e.agency, r.agency),
         coalesce(e.endorsements, 0),
         coalesce(e.awaiting, 0),
         coalesce(e.received, 0),
         coalesce(e.completed, 0),
         coalesce(e.withdrawn, 0),
         e.avg_days_to_receive,
         e.avg_days_to_complete,
         coalesce(r.ratings, 0),
         r.avg_stars
    from e
    full outer join r on r.agency = e.agency
   order by 1;
end;
$function$;

revoke all on function public.admin_agency_performance() from public, anon;
grant execute on function public.admin_agency_performance() to authenticated;

commit;
