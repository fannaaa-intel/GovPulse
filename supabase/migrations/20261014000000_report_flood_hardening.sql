-- ─────────────────────────────────────────────────────────────────────────────
-- 20261014000000  Report-flood hardening (panel revision item 2a — DoS)
-- ─────────────────────────────────────────────────────────────────────────────
--
-- The panel's DoS concern is the WORK QUEUE being flooded with the same issue,
-- by one citizen or by many. What already holds: an admin-verified ID to report
-- at all, 5 reports per account per day (atomic limiter), the "Already reported
-- here?" prompt, admin duplicate candidates + Link, Spam Watch. This closes the
-- three gaps those leave. Additive: no table, column or policy is dropped.
--
-- ── A. One citizen repeating the same issue ──────────────────────────────────
-- "No — mine is a different issue" was purely advisory, so one account could
-- refile the same spot with new wording up to five times a day, every day.
-- trg_ac_block_repeat_report refuses a report when the SAME account already has
-- an open report of the same category within dup_radius_m (60 m) filed in the
-- last dup_max_age_days (30) — the exact rule nearby_open_reports already uses
-- to show the prompt. The description is deliberately not compared: rewording
-- is the evasion. 'others' is the exception: two different "others" problems
-- at one spot are normal, so those must also share the typed category.
-- Named trg_ac_* so it fires after the pin/suspension guards and BEFORE
-- trg_rl_reports: a refused repeat does not use up the daily allowance.
-- Direct PostgREST inserts only (current_user authenticated/anon), the same
-- guard rule as 20261009000000 / 20261010000000 — admin and definer paths pass.
--
-- ── B. One person counted many times ─────────────────────────────────────────
-- recount_report_confirms counted ROWS pointing at a report, so one account
-- confirming the same report three times read as three supporters, and an
-- owner could confirm their own report. The trigger above now refuses both,
-- and the count becomes DISTINCT PEOPLE other than the original reporter.
-- Existing counts are recomputed once below (only rows whose number changes
-- are touched, so updated_at does not move on the rest).
--
-- ── C. Many accounts, the same issue ─────────────────────────────────────────
-- admin_report_similar() gives every open ticket its number of open, unmerged
-- neighbours under the SAME rule as report_duplicate_candidates (same category,
-- within 3 × dup_radius_m, filed within dup_max_age_days of each other), plus a
-- surge flag when surge_threshold (5) of them landed within surge_window_hours
-- (24). The queue shows "N similar", the reports page raises the surge.
-- admin_merge_similar() merges a whole group in one step, into the ticket the
-- community already backs (most confirmations, then earliest) — the order the
-- candidate list already uses. It never touches work already under way: a
-- report that is in progress, or endorsed to an agency, is skipped and
-- reported back, because merging clears its office and would silently
-- withdraw an agency endorsement (trg_revoke_endorsement_on_clear).
-- Nothing merges on its own; an admin presses the button.
--
-- nearby_open_reports gains `is_mine`, so the app can say "you already
-- reported this" BEFORE the citizen uploads anything, instead of letting the
-- server refuse after the upload. The return type changes, so it is dropped
-- and recreated; the previous grants are restated exactly.
--
-- Verify:   supabase/diagnostics/verify_20261014000000.sql (rollback-only)
-- ─────────────────────────────────────────────────────────────────────────────

begin;

-- ── A + B: refuse a repeat from the same account ─────────────────────────────
create or replace function public.block_repeat_own_report()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_uid    uuid := auth.uid();
  v_target uuid;
  v_mine   uuid;
begin
  if current_user not in ('authenticated', 'anon') or v_uid is null then
    return new;
  end if;

  -- B: a confirmation of your own report, or a second one of the same report.
  if new.duplicate_of is not null then
    select coalesce(t.duplicate_of, t.id) into v_target
      from public.reports t where t.id = new.duplicate_of;
    select r.id into v_mine
      from public.reports r
     where (r.id = v_target and r.user_id = v_uid)
        or (r.duplicate_of = v_target and r.user_id = v_uid)
     limit 1;
    if v_mine is not null then
      raise exception 'You already reported this issue.'
        using errcode = 'P0001',
              hint    = 'duplicate_own_report',
              detail  = v_mine::text;
    end if;
  end if;

  -- A: an open report of yours, same category, at the same spot.
  if new.latitude is null or new.longitude is null then
    return new;
  end if;

  select r.id into v_mine
    from public.reports r
   where r.user_id = v_uid
     and r.category = new.category
     and (new.category <> 'others'
          or lower(btrim(coalesce(r.category_other, '')))
           = lower(btrim(coalesce(new.category_other, ''))))
     and r.status in ('pending', 'under_review', 'in_progress')
     and r.dismissed_at is null
     and r.latitude is not null
     and r.longitude is not null
     and r.created_at > now() - make_interval(
           days => public.moderation_setting('dup_max_age_days', 30)::int)
     and earth_box(ll_to_earth(new.latitude, new.longitude),
                   public.moderation_setting('dup_radius_m', 60))
         @> ll_to_earth(r.latitude, r.longitude)
     and earth_distance(ll_to_earth(new.latitude, new.longitude),
                        ll_to_earth(r.latitude, r.longitude))
         <= public.moderation_setting('dup_radius_m', 60)
   order by r.created_at desc
   limit 1;

  if v_mine is not null then
    raise exception 'You already reported this issue.'
      using errcode = 'P0001',
            hint    = 'duplicate_own_report',
            detail  = v_mine::text;
  end if;

  return new;
end;
$function$;

revoke all on function public.block_repeat_own_report() from public, anon, authenticated;

drop trigger if exists trg_ac_block_repeat_report on public.reports;
create trigger trg_ac_block_repeat_report
  before insert on public.reports
  for each row execute function public.block_repeat_own_report();

-- ── B: count people, not rows ────────────────────────────────────────────────
create or replace function public.recount_report_confirms(p_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.reports c
     set confirm_count = (
       select count(distinct coalesce(d.user_id::text, d.id::text))
         from public.reports d
        where d.duplicate_of = c.id
          and d.user_id is distinct from c.user_id
     )
   where c.id = p_id;
$$;

-- One-time recount; only rows whose number actually changes are written.
update public.reports c
   set confirm_count = x.n
  from (
    select c2.id,
           (select count(distinct coalesce(d.user_id::text, d.id::text))
              from public.reports d
             where d.duplicate_of = c2.id
               and d.user_id is distinct from c2.user_id)::int as n
      from public.reports c2
     where c2.confirm_count > 0
        or exists (select 1 from public.reports d where d.duplicate_of = c2.id)
  ) x
 where x.id = c.id
   and c.confirm_count is distinct from x.n;

-- ── nearby_open_reports + is_mine ────────────────────────────────────────────
drop function if exists public.nearby_open_reports(text, double precision, double precision, integer);
create function public.nearby_open_reports(
  p_category text,
  p_lat      double precision,
  p_lng      double precision,
  p_limit    integer default 3
)
returns table (
  id            uuid,
  short_ref     text,
  category      text,
  remarks       text,
  barangay      text,
  address       text,
  status        text,
  confirm_count integer,
  created_at    timestamptz,
  distance_m    integer,
  is_mine       boolean
)
language sql
stable
security definer
set search_path to 'public'
as $function$
  select r.id,
         upper(substring(r.id::text from 1 for 8)),
         r.category,
         r.remarks,
         r.barangay,
         r.address,
         r.status,
         r.confirm_count,
         r.created_at,
         earth_distance(ll_to_earth(p_lat, p_lng),
                        ll_to_earth(r.latitude, r.longitude))::int,
         -- About the CALLER only: did I file this, or already confirm it?
         (r.user_id = auth.uid()
          or exists (select 1 from public.reports d
                      where d.duplicate_of = r.id and d.user_id = auth.uid()))
    from public.reports r
   where auth.uid() is not null
     and r.category = p_category
     and r.duplicate_of is null
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
   -- Your own report first: it is the one the app must tell you about.
   order by 11 desc,
            earth_distance(ll_to_earth(p_lat, p_lng),
                           ll_to_earth(r.latitude, r.longitude)) asc
   limit greatest(coalesce(p_limit, 3), 1);
$function$;

revoke all on function public.nearby_open_reports(text, double precision, double precision, integer) from public, anon;
grant execute on function public.nearby_open_reports(text, double precision, double precision, integer) to authenticated, service_role;

-- ── C: groups of similar open reports ────────────────────────────────────────
-- One row per open ticket that has at least one similar open ticket.
create or replace function public.admin_report_similar()
returns table (
  report_id     uuid,
  similar_count integer,
  recent_count  integer,
  is_surge      boolean
)
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
#variable_conflict use_column
declare
  v_radius numeric := public.moderation_setting('dup_radius_m', 60) * 3;
  v_age    numeric := public.moderation_setting('dup_max_age_days', 30) * 86400;
  v_window numeric := public.moderation_setting('surge_window_hours', 24);
  v_surge  numeric := public.moderation_setting('surge_threshold', 5);
begin
  if not public.is_admin() then
    raise exception 'Admins only' using errcode = '42501';
  end if;

  return query
  with open_r as (
    select r.id, r.category, r.latitude, r.longitude, r.created_at
      from public.reports r
     where r.duplicate_of is null
       and r.status in ('pending', 'under_review', 'in_progress')
       and r.dismissed_at is null
       and r.latitude is not null
       and r.longitude is not null
  ),
  pairs as (
    select a.id as report_id, b.id as other_id, b.created_at as other_at,
           a.created_at as own_at
      from open_r a
      join open_r b
        on b.id <> a.id
       and b.category = a.category
       and abs(extract(epoch from (b.created_at - a.created_at))) < v_age
       and earth_box(ll_to_earth(a.latitude, a.longitude), v_radius)
           @> ll_to_earth(b.latitude, b.longitude)
       and earth_distance(ll_to_earth(a.latitude, a.longitude),
                          ll_to_earth(b.latitude, b.longitude)) <= v_radius
  )
  select p.report_id,
         count(*)::int,
         -- Counting this ticket too: "5 reports here in 24 h" includes it.
         (count(*) filter (where p.other_at > now() - make_interval(hours => v_window::int))
          + case when max(p.own_at) > now() - make_interval(hours => v_window::int)
                 then 1 else 0 end)::int,
         (count(*) filter (where p.other_at > now() - make_interval(hours => v_window::int))
          + case when max(p.own_at) > now() - make_interval(hours => v_window::int)
                 then 1 else 0 end) >= v_surge
    from pairs p
   group by p.report_id;
end;
$function$;

revoke all on function public.admin_report_similar() from public, anon;
grant execute on function public.admin_report_similar() to authenticated;

-- Merge p_report and every similar open ticket into ONE.
-- Returns {ok, target, merged, skipped}.
create or replace function public.admin_merge_similar(p_report uuid)
returns json
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_radius  numeric := public.moderation_setting('dup_radius_m', 60) * 3;
  v_age     numeric := public.moderation_setting('dup_max_age_days', 30) * 86400;
  x         public.reports%rowtype;
  v_target  uuid;
  v_merged  int := 0;
  v_skipped int := 0;
  m         record;
begin
  if not public.is_admin() then
    raise exception 'Admins only' using errcode = '42501';
  end if;

  select * into x from public.reports where id = p_report;
  if not found or x.duplicate_of is not null or x.latitude is null then
    return json_build_object('ok', false, 'error', 'not_open_ticket');
  end if;

  drop table if exists pg_temp._grp;
  create temp table _grp on commit drop as
  select r.id, r.status, r.endorsed_to_department, r.confirm_count, r.created_at
    from public.reports r
   where r.duplicate_of is null
     and r.status in ('pending', 'under_review', 'in_progress')
     and r.dismissed_at is null
     and r.latitude is not null
     and r.category = x.category
     and (r.id = x.id or (
           abs(extract(epoch from (r.created_at - x.created_at))) < v_age
       and earth_box(ll_to_earth(x.latitude, x.longitude), v_radius)
           @> ll_to_earth(r.latitude, r.longitude)
       and earth_distance(ll_to_earth(x.latitude, x.longitude),
                          ll_to_earth(r.latitude, r.longitude)) <= v_radius));

  if (select count(*) from _grp) < 2 then
    return json_build_object('ok', false, 'error', 'nothing_to_merge');
  end if;

  -- The ticket the community already backs; ties go to the earliest.
  select g.id into v_target from _grp g
   order by g.confirm_count desc, g.created_at asc limit 1;

  for m in select * from _grp g where g.id <> v_target loop
    if m.status = 'in_progress' or m.endorsed_to_department is not null then
      v_skipped := v_skipped + 1;
      continue;
    end if;
    -- Its own confirmations move with it, so no chain is left behind.
    update public.reports set duplicate_of = v_target where duplicate_of = m.id;
    update public.reports
       set duplicate_of           = v_target,
           assigned_to_department = null,
           assigned_at            = null
     where id = m.id;
    v_merged := v_merged + 1;
  end loop;

  return json_build_object('ok', true, 'target', v_target,
                           'merged', v_merged, 'skipped', v_skipped);
end;
$function$;

revoke all on function public.admin_merge_similar(uuid) from public, anon;
grant execute on function public.admin_merge_similar(uuid) to authenticated;

commit;
