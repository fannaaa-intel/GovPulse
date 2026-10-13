-- ─────────────────────────────────────────────────────────────────────────────
-- 20261014000001  Fix: the repeat-report guard never fired
-- ─────────────────────────────────────────────────────────────────────────────
--
-- 20261014000000 created block_repeat_own_report() as SECURITY DEFINER and
-- guarded it with `current_user not in ('authenticated', 'anon')`. Inside a
-- definer function current_user is the function's OWNER (postgres), so that
-- guard was always true and the function returned before checking anything:
-- every repeat report and every self/second confirmation went through.
-- Caught by verify_20261014000000.sql on the live database (A2, A7, B1, B3
-- failed; everything else passed). The other guards in this schema
-- (block_suspended_writes, pin_citizen_report_columns) are SECURITY INVOKER
-- for exactly this reason.
--
-- The citizen app was not exposed meanwhile: its own pre-check
-- (nearby_open_reports.is_mine, which did pass) already stops the common path
-- before upload. Only a direct PostgREST call could repeat.
--
-- The fix splits the two jobs:
--   • block_repeat_own_report() — SECURITY INVOKER, so the "direct citizen
--     insert" test sees the real caller, exactly like block_suspended_writes;
--   • caller_repeat_report(...) — SECURITY DEFINER, does the lookup. It needs
--     the elevated read because a citizen cannot see the report they are
--     confirming. It only ever answers about the CALLER's own reports
--     (auth.uid(), no user parameter), so it cannot be used to probe anyone
--     else's.
-- The rules themselves are unchanged from 20261014000000.
--
-- Verify: supabase/diagnostics/verify_20261014000001.sql (rollback-only)
-- ─────────────────────────────────────────────────────────────────────────────

begin;

create or replace function public.caller_repeat_report(
  p_category       text,
  p_category_other text,
  p_lat            double precision,
  p_lng            double precision,
  p_duplicate_of   uuid
)
returns uuid
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_uid    uuid := auth.uid();
  v_target uuid;
  v_mine   uuid;
begin
  if v_uid is null then
    return null;
  end if;

  -- B: a confirmation of your own report, or a second one of the same report.
  if p_duplicate_of is not null then
    select coalesce(t.duplicate_of, t.id) into v_target
      from public.reports t where t.id = p_duplicate_of;
    select r.id into v_mine
      from public.reports r
     where r.user_id = v_uid
       and (r.id = v_target or r.duplicate_of = v_target)
     limit 1;
    if v_mine is not null then
      return v_mine;
    end if;
  end if;

  -- A: an open report of yours, same category, at the same spot.
  if p_lat is null or p_lng is null then
    return null;
  end if;

  select r.id into v_mine
    from public.reports r
   where r.user_id = v_uid
     and r.category = p_category
     and (p_category <> 'others'
          or lower(btrim(coalesce(r.category_other, '')))
           = lower(btrim(coalesce(p_category_other, ''))))
     and r.status in ('pending', 'under_review', 'in_progress')
     and r.dismissed_at is null
     and r.latitude is not null
     and r.longitude is not null
     and r.created_at > now() - make_interval(
           days => public.moderation_setting('dup_max_age_days', 30)::int)
     and earth_box(ll_to_earth(p_lat, p_lng),
                   public.moderation_setting('dup_radius_m', 60))
         @> ll_to_earth(r.latitude, r.longitude)
     and earth_distance(ll_to_earth(p_lat, p_lng),
                        ll_to_earth(r.latitude, r.longitude))
         <= public.moderation_setting('dup_radius_m', 60)
   order by r.created_at desc
   limit 1;

  return v_mine;
end;
$function$;

revoke all on function public.caller_repeat_report(text, text, double precision, double precision, uuid)
  from public, anon;
grant execute on function public.caller_repeat_report(text, text, double precision, double precision, uuid)
  to authenticated;

create or replace function public.block_repeat_own_report()
returns trigger
language plpgsql
security invoker
set search_path to 'public'
as $function$
declare
  v_mine uuid;
begin
  -- Same guard rule as block_suspended_writes: only a DIRECT PostgREST call.
  if current_user not in ('authenticated', 'anon') or auth.uid() is null then
    return new;
  end if;

  v_mine := public.caller_repeat_report(
    new.category, new.category_other, new.latitude, new.longitude,
    new.duplicate_of);

  if v_mine is not null then
    raise exception 'You already reported this issue.'
      using errcode = 'P0001',
            hint    = 'duplicate_own_report',
            detail  = v_mine::text;
  end if;

  return new;
end;
$function$;

commit;
