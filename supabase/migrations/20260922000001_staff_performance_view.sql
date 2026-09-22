-- ════════════════════════════════════════════════════════════════════════════
--  Staff performance scorecards
--
--  WHAT IS MEASURED, AND WHAT DELIBERATELY IS NOT
--
--  Every input here is something the staff member personally did:
--    • resolution updates they authored and an admin approved
--    • the citizen's star rating on chat tickets ASSIGNED TO THEM
--    • suggestion replies they wrote that an admin published
--    • how often the admin returned a draft, and how fast they answer
--
--  Citizen OFFICE ratings (feedbacks.overall_rating) are NOT part of any
--  person's score, and this is deliberate. `feedbacks` carries no staff id —
--  verified, the columns are office_id/office_label/service_name — because the
--  citizen is rating a counter visit, often one no console user ever touched.
--  Ranking someone on a number they did not control, and could most easily
--  improve by discouraging low ratings, measures the wrong thing and corrupts
--  the rating. Office stars are exposed separately, per DEPARTMENT, as context
--  beside the scorecard.
--
--  chat ratings ARE per-person: concern_tickets carries both assigned_staff_id
--  and rating (verified), so the citizen is rating a specific person's handling
--  of a specific conversation. That one is fairly attributable.
--
--  VERIFIED BEFORE WRITING:
--    • reports has NO resolved_at column — resolution is attributed through
--      report_updates(author_id, kind, status), which does carry an author
--    • concern_tickets has assigned_staff_id, rating, resolved_at, department
--    • admin_profiles is the staff directory (user_id, full_name, photo_url,
--      department, is_external); staff_details marks who is staff
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1. Per-staff scorecard ──────────────────────────────────────────────────
-- security_invoker so the caller's own RLS decides what they may read. Staff
-- filter to their own user_id from the client; admins read the whole table.
-- The grant below is the real gate.

create or replace view public.staff_performance_view
with (security_invoker = true) as
with resolutions as (
  -- A completion update that an admin approved. `kind` is CHECK-constrained to
  -- ('progress','completion') by 20260829000001, so 'completion' is the whole
  -- vocabulary for "this report is finished" — a progress note is not a
  -- resolution and must not score as one.
  select ru.author_id as user_id, count(*)::int as n
    from public.report_updates ru
   where ru.status = 'approved'
     and ru.kind = 'completion'
   group by ru.author_id
),
chat as (
  -- Only rated tickets count. An unrated conversation is not a zero — it is
  -- an absence, and averaging it in as zero would punish whoever handled the
  -- conversations citizens simply did not rate.
  select t.assigned_staff_id as user_id,
         round(avg(t.rating)::numeric, 2) as avg_rating,
         count(*)::int as n
    from public.concern_tickets t
   where t.assigned_staff_id is not null
     and t.rating is not null
   group by t.assigned_staff_id
),
replies as (
  select sr.author_id as user_id,
         count(*) filter (where sr.status = 'approved')::int as approved,
         count(*) filter (where sr.status = 'rejected')::int as rejected,
         -- Median, not mean: one suggestion answered three weeks late would
         -- drag a mean far enough to misrepresent an otherwise prompt office.
         percentile_cont(0.5) within group (
           order by extract(epoch from (sr.created_at - s.created_at)) / 3600.0
         ) filter (where sr.status = 'approved') as median_hours
    from public.suggestion_replies sr
    join public.suggestions s on s.id = sr.suggestion_id
   group by sr.author_id
)
select
  ap.user_id,
  ap.full_name,
  ap.photo_url,
  ap.department,
  coalesce(r.n, 0)                as reports_resolved,
  c.avg_rating                    as chat_rating,
  coalesce(c.n, 0)                as chat_rating_count,
  coalesce(rep.approved, 0)       as replies_approved,
  coalesce(rep.rejected, 0)       as replies_rejected,
  round(rep.median_hours::numeric, 1) as median_response_hours
from public.admin_profiles ap
join public.user_roles ur on ur.user_id = ap.user_id and ur.role_id = 2
left join resolutions r  on r.user_id   = ap.user_id
left join chat c         on c.user_id   = ap.user_id
left join replies rep    on rep.user_id = ap.user_id
-- External agencies (DPWH, DENR, …) are not LGU staff and hold no inbox, so
-- they do not belong on an internal leaderboard.
where coalesce(ap.is_external, false) = false;

comment on view public.staff_performance_view is
  'Per-staff scorecard built ONLY from actions the person took. Citizen office '
  'ratings are excluded by design — feedbacks has no staff id and rates the '
  'office, not a person. Staff read their own row; admins read all.';

grant select on public.staff_performance_view to authenticated;

-- admin_profiles is not publicly readable, so the view above would return
-- nothing for a staff member reading their OWN row unless they can see their
-- own directory entry. Confirm that narrow policy exists.
do $$
begin
  if not exists (
    select 1 from pg_policies
     where schemaname = 'public' and tablename = 'admin_profiles'
       and policyname = 'staff_reads_own_profile'
  ) then
    execute $p$
      create policy staff_reads_own_profile
        on public.admin_profiles for select to authenticated
        using (user_id = auth.uid())
    $p$;
  end if;
end $$;

-- ── 2. Department rating trend ──────────────────────────────────────────────
-- SECURITY DEFINER: it aggregates other people's feedback rows, which the
-- caller cannot read individually. It returns only an average and a count —
-- never a comment, a name or a row — and it refuses any department that is not
-- the caller's own unless the caller is an admin.

create or replace function public.department_rating_trend(
  p_department text,
  p_weeks integer default 8
) returns table (week_start date, avg_rating numeric, n integer)
language plpgsql stable security definer
set search_path to 'public', 'pg_temp' as $$
declare
  v_weeks integer := greatest(1, least(52, coalesce(p_weeks, 8)));
begin
  if not (public.is_admin() or public.staff_owns_department(p_department)) then
    raise exception 'not your department' using errcode = '42501';
  end if;

  return query
  select d.wk::date,
         round(avg(f.overall_rating)::numeric, 2),
         count(f.id)::int
    from generate_series(
           date_trunc('week', now()) - ((v_weeks - 1) || ' weeks')::interval,
           date_trunc('week', now()),
           '1 week'::interval) as d(wk)
    left join public.feedbacks f
           on f.department = p_department
          and f.created_at >= d.wk
          and f.created_at <  d.wk + interval '1 week'
   group by d.wk
   order by d.wk;
end;
$$;

comment on function public.department_rating_trend(text, integer) is
  'Weekly average citizen rating for one office. Aggregate only — no comments, '
  'no identities. Refuses a department that is not the callers own.';

revoke execute on function public.department_rating_trend(text, integer) from public, anon;
grant  execute on function public.department_rating_trend(text, integer) to authenticated;

-- ── 3. Department rating mix ────────────────────────────────────────────────
-- An average of 3.0 can be "everyone is lukewarm" or "half love it, half hate
-- it", and those call for opposite responses. The star histogram separates
-- them; the average alone cannot.

create or replace function public.department_rating_mix(p_department text)
returns table (stars integer, n integer)
language plpgsql stable security definer
set search_path to 'public', 'pg_temp' as $$
begin
  if not (public.is_admin() or public.staff_owns_department(p_department)) then
    raise exception 'not your department' using errcode = '42501';
  end if;

  return query
  select s.star::int, count(f.id)::int
    from generate_series(1, 5) as s(star)
    left join public.feedbacks f
           on f.department = p_department
          and f.overall_rating = s.star
   group by s.star
   order by s.star;
end;
$$;

comment on function public.department_rating_mix(text) is
  'Star histogram (1-5) for one office. Aggregate only.';

revoke execute on function public.department_rating_mix(text) from public, anon;
grant  execute on function public.department_rating_mix(text) to authenticated;
