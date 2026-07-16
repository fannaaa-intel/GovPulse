-- ════════════════════════════════════════════════════════════════════════════
--  Report duplicate clustering — many citizens, one real-world issue.
--
--  DISTINCT FROM spam_detection.sql. That file catches ONE user re-posting the
--  same text (abuse). This file handles DIFFERENT users reporting the SAME
--  pothole — which is not abuse, it's corroboration, and it's the most useful
--  signal the system produces. Five reports of one pothole means it's a bad
--  pothole; the admin should see ONE ticket confirmed by five people, not five
--  tickets to triage by hand.
--
--  Duplicates are LINKED, never deleted and never rejected:
--    • `duplicate_of` points a report at the canonical one it confirms.
--    • `confirm_count` on the canonical = how many others confirmed it.
--  Every duplicate stays a real row with its own reporter, so each of those
--  citizens still gets status notifications from the existing
--  notify_citizen_report_decision trigger. They each reported it; they each
--  deserve to hear it was fixed.
--
--  Matching is GEOMETRY, not language: same category + within a radius + still
--  open. Deterministic, free, and instant — no model call on the hot path.
--
--  Thresholds are data-driven via moderation_settings (spam_detection.sql), so
--  the radius is tuned with an UPDATE, no redeploy:
--     update public.moderation_settings set value = 75 where key = 'dup_radius_m';
--
--  Additive & idempotent. Run once.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1. Geo extensions ────────────────────────────────────────────────────────
-- earthdistance gives metre distances between lat/lng pairs and rides on cube.
-- Sufficient at barangay scale — PostGIS would be a heavier dependency for no
-- gain here.
create extension if not exists cube;
create extension if not exists earthdistance;

-- ── 2. Columns ───────────────────────────────────────────────────────────────
alter table public.reports
  -- Non-null → this report confirms another one; it is NOT its own ticket and
  -- must stay out of the triage queue. Always points at a CANONICAL report
  -- (enforced by flatten_duplicate_chain below) so chains can never form.
  add column if not exists duplicate_of uuid references public.reports(id) on delete set null,
  -- On a canonical report: how many OTHER reports confirm it. Total citizens
  -- who reported the issue = confirm_count + 1. Maintained by trigger only —
  -- never write this column by hand.
  add column if not exists confirm_count int not null default 0;

-- Finding a report's confirmations, and excluding duplicates from every admin
-- and staff query, both key on duplicate_of.
create index if not exists reports_duplicate_of_idx
  on public.reports (duplicate_of)
  where duplicate_of is not null;

-- The nearby lookup is category + radius over OPEN CANONICAL rows only, so the
-- geo index is partial on exactly that set — it stays small no matter how much
-- resolved history accumulates.
create index if not exists reports_open_geo_idx
  on public.reports using gist (ll_to_earth(latitude, longitude))
  where duplicate_of is null
    and latitude is not null
    and longitude is not null;

-- ── 3. Tunable knobs ─────────────────────────────────────────────────────────
-- moderation_settings + moderation_setting() come from spam_detection.sql.
insert into public.moderation_settings(key, value, description) values
  ('dup_radius_m',    60, 'Reports of the same category within this many metres are offered as the same issue'),
  ('dup_max_age_days', 30, 'Only reports filed within this many days are offered as a match')
on conflict (key) do nothing;

-- ── 4. Chain flattening ──────────────────────────────────────────────────────
-- If B confirms A and someone points C at B, C must point at A instead.
-- Guarantees duplicate_of always names a canonical report, so confirm_count is
-- a plain one-level count and "show me the original" is never a recursive walk.
-- Also refuses self-links, which would orphan a report from its own queue.
create or replace function public.flatten_duplicate_chain()
returns trigger language plpgsql as $$
declare
  parent uuid;
begin
  if new.duplicate_of is null then
    return new;
  end if;

  if new.duplicate_of = new.id then
    new.duplicate_of := null;   -- a report cannot confirm itself
    return new;
  end if;

  select r.duplicate_of into parent
    from public.reports r where r.id = new.duplicate_of;

  if parent is not null and parent <> new.id then
    new.duplicate_of := parent;
  elsif parent = new.id then
    new.duplicate_of := null;   -- would close a 2-cycle
  end if;

  return new;
end;
$$;

drop trigger if exists trg_flatten_duplicate_chain on public.reports;
create trigger trg_flatten_duplicate_chain
  before insert or update of duplicate_of on public.reports
  for each row execute function public.flatten_duplicate_chain();

-- ── 5. confirm_count maintenance ─────────────────────────────────────────────
-- Recount from the rows themselves rather than incrementing, so the count can
-- never drift out of agreement with reality (merge, unmerge, delete all land on
-- the same authoritative count).
create or replace function public.recount_report_confirms(p_id uuid)
returns void language sql security definer set search_path = public as $$
  update public.reports
     set confirm_count = (
       select count(*) from public.reports d where d.duplicate_of = p_id
     )
   where id = p_id;
$$;

create or replace function public.sync_report_confirms()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  -- Recount BOTH sides so an unmerge/re-merge fixes the old parent too.
  if tg_op in ('UPDATE', 'DELETE') and old.duplicate_of is not null then
    perform public.recount_report_confirms(old.duplicate_of);
  end if;
  if tg_op in ('INSERT', 'UPDATE') and new.duplicate_of is not null then
    perform public.recount_report_confirms(new.duplicate_of);
  end if;
  return null;
end;
$$;

-- The WHEN clause is what stops infinite recursion: recount_report_confirms
-- writes confirm_count ONLY, leaving duplicate_of untouched, so the resulting
-- UPDATE fails this condition and the trigger does not re-fire.
drop trigger if exists trg_sync_report_confirms on public.reports;
create trigger trg_sync_report_confirms
  after insert or delete on public.reports
  for each row execute function public.sync_report_confirms();

drop trigger if exists trg_sync_report_confirms_upd on public.reports;
create trigger trg_sync_report_confirms_upd
  after update of duplicate_of on public.reports
  for each row
  when (old.duplicate_of is distinct from new.duplicate_of)
  execute function public.sync_report_confirms();

-- ── 6. Citizen-facing lookup: "is my issue already reported?" ────────────────
-- SECURITY DEFINER because a citizen cannot read other citizens' reports under
-- RLS — and must not be able to. This returns ONLY the issue itself (what,
-- where, when, how many agree). It NEVER returns user_id or is_anonymous, so a
-- reporter's identity — anonymous or named — cannot be inferred from it. Do not
-- add identity columns to this result: it is readable by every signed-in
-- citizen by design.
create or replace function public.nearby_open_reports(
  p_category text,
  p_lat      double precision,
  p_lng      double precision,
  p_limit    int default 3
)
returns table (
  id            uuid,
  short_ref     text,
  category      text,
  remarks       text,
  barangay      text,
  address       text,
  status        text,
  confirm_count int,
  created_at    timestamptz,
  distance_m    int
)
language sql
security definer
set search_path = public
as $$
  select r.id,
         upper(substring(r.id::text from 1 for 8)),
         r.category,
         r.remarks,
         r.barangay,
         r.address,
         r.status,
         r.confirm_count,
         r.created_at,
         earth_distance(
           ll_to_earth(p_lat, p_lng),
           ll_to_earth(r.latitude, r.longitude)
         )::int
    from public.reports r
   where auth.uid() is not null          -- signed-in citizens only
     and r.category = p_category
     and r.duplicate_of is null          -- only canonical tickets
     and r.status in ('pending', 'under_review', 'in_progress')
     and r.dismissed_at is null          -- never surface dismissed spam
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
   order by earth_distance(ll_to_earth(p_lat, p_lng),
                           ll_to_earth(r.latitude, r.longitude)) asc
   limit greatest(coalesce(p_limit, 3), 1);
$$;

grant execute on function public.nearby_open_reports(text, double precision, double precision, int)
  to authenticated;

-- ── 7. Admin-facing lookup: merge candidates for ONE report ──────────────────
-- Suggestion only — the admin decides. Searches a WIDER radius than the citizen
-- prompt (people pin the same pothole from across the street), which is exactly
-- why this stays a human decision rather than an auto-merge.
create or replace function public.report_duplicate_candidates(p_report_id uuid)
returns table (
  id            uuid,
  short_ref     text,
  remarks       text,
  barangay      text,
  address       text,
  status        text,
  confirm_count int,
  created_at    timestamptz,
  distance_m    int
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cat text;
  v_lat double precision;
  v_lng double precision;
  v_at  timestamptz;
  v_radius numeric := public.moderation_setting('dup_radius_m', 60) * 3;
begin
  if not exists (
    select 1 from public.user_roles
    where user_roles.user_id = auth.uid() and role_id = 1
  ) then
    raise exception 'admin only';
  end if;

  select r.category, r.latitude, r.longitude, r.created_at
    into v_cat, v_lat, v_lng, v_at
    from public.reports r where r.id = p_report_id;

  if v_lat is null or v_lng is null then
    return;
  end if;

  return query
  select r.id,
         upper(substring(r.id::text from 1 for 8)),
         r.remarks, r.barangay, r.address, r.status, r.confirm_count,
         r.created_at,
         earth_distance(ll_to_earth(v_lat, v_lng),
                        ll_to_earth(r.latitude, r.longitude))::int
    from public.reports r
   where r.id <> p_report_id
     and r.category = v_cat
     and r.duplicate_of is null
     and r.status in ('pending', 'under_review', 'in_progress')
     and r.dismissed_at is null
     and r.latitude is not null
     and r.longitude is not null
     and abs(extract(epoch from (r.created_at - v_at))) <
         public.moderation_setting('dup_max_age_days', 30) * 86400
     and earth_box(ll_to_earth(v_lat, v_lng), v_radius)
         @> ll_to_earth(r.latitude, r.longitude)
     and earth_distance(ll_to_earth(v_lat, v_lng),
                        ll_to_earth(r.latitude, r.longitude)) <= v_radius
   -- Prefer the report the community already backs, then the earliest filed:
   -- merging INTO the established ticket keeps its history and confirmations.
   order by r.confirm_count desc, r.created_at asc
   limit 5;
end;
$$;

grant execute on function public.report_duplicate_candidates(uuid) to authenticated;

-- ── 8. Citizen notification when an ADMIN merges their report ────────────────
-- Being merged is good news — "we already know, it's being handled" — but it is
-- invisible unless we say so, and silence after filing reads as being ignored.
-- The existing decision trigger only fires on status change, so merging needs
-- its own ping. Wrapped: a notification failure can never roll back the merge.
--
-- UPDATE-only by design. The citizen "confirm this" flow sets duplicate_of at
-- INSERT — that citizen chose the link and already saw it confirmed on screen,
-- so telling them again would be noise. This fires only when someone ELSE
-- (an admin at triage) links a report the citizen filed as its own issue.
create or replace function public.notify_citizen_report_merged()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_label text := public.report_label(new.category, new.category_other);
begin
  if new.user_id is null or new.duplicate_of is null then
    return new;
  end if;

  begin
    insert into public.notifications
      (user_id, topic, title, subtitle, type, color_value, icon_code,
       is_approved, sent_by)
    values (
      new.user_id, 'report',
      'Report linked to an existing one',
      'Thanks — your ' || v_label || ' report matches one already being tracked '
        || '(RPT-' || upper(substring(new.duplicate_of::text from 1 for 8))
        || '). Your confirmation was added and we''ll keep you posted.',
      'report_merged', 4279203438, 0, true, auth.uid()
    );
  exception when others then null;
  end;
  return new;
end;
$$;

drop trigger if exists trg_notify_citizen_report_merged on public.reports;
create trigger trg_notify_citizen_report_merged
  after update of duplicate_of on public.reports
  for each row
  when (old.duplicate_of is null and new.duplicate_of is not null)
  execute function public.notify_citizen_report_merged();

-- ── 9. Status cascade — canonical → its confirmations ────────────────────────
-- Without this the whole design quietly breaks its promise: a merged report's
-- own status would never move again, so that citizen would sit on "Pending"
-- forever while the issue they reported was fixed. Mirroring the canonical's
-- status onto its confirmations means the EXISTING per-report
-- notify_citizen_report_decision trigger fires for each of those reporters on
-- its own — every citizen who reported the pothole hears it was resolved, which
-- is the entire reason duplicates are linked instead of deleted.
create or replace function public.cascade_status_to_duplicates()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  update public.reports
     set status = new.status
   where duplicate_of = new.id
     and status is distinct from new.status;
  return null;
end;
$$;

-- Terminates after one hop: duplicate_of always names a CANONICAL report
-- (section 4), so no row ever points at a duplicate and the cascaded UPDATE
-- finds nothing to cascade onward. The WHEN clause makes that explicit.
drop trigger if exists trg_cascade_status_to_duplicates on public.reports;
create trigger trg_cascade_status_to_duplicates
  after update of status on public.reports
  for each row
  when (new.duplicate_of is null and old.status is distinct from new.status)
  execute function public.cascade_status_to_duplicates();

-- Same problem at the moment of merging: a report linked to an already
-- in-progress canonical must adopt that progress immediately, or the citizen
-- who just confirmed a job already underway would be told it hadn't started.
create or replace function public.adopt_canonical_status()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_status text;
begin
  select status into v_status from public.reports where id = new.duplicate_of;
  if v_status is not null then
    new.status := v_status;
  end if;
  return new;
end;
$$;

-- BEFORE, so it writes NEW.status in place rather than issuing a second UPDATE
-- that would race the merge notification.
--
-- Covers INSERT as well as UPDATE: the citizen "confirm this" flow sets
-- duplicate_of at insert time with a hardcoded status of 'pending', so without
-- the INSERT arm someone confirming an in-progress issue would be shown a fresh
-- Pending report for work already underway.
--
-- NAMED to sort AFTER trg_flatten_duplicate_chain — Postgres fires same-timing
-- triggers in alphabetical order, and this must read the status of the FINAL
-- (flattened) canonical, not of the intermediate row the caller happened to
-- name. Same trick spam_detection.sql uses to order its triggers.
drop trigger if exists trg_adopt_canonical_status on public.reports;
drop trigger if exists trg_flatten_then_adopt_status on public.reports;
create trigger trg_flatten_then_adopt_status
  before insert or update of duplicate_of on public.reports
  for each row
  when (new.duplicate_of is not null)
  execute function public.adopt_canonical_status();

-- ── 10. Backfill ─────────────────────────────────────────────────────────────
-- Existing rows are all canonical (nothing was merged before this migration),
-- so their counts are zero — which the column default already gives them. This
-- re-syncs anyway, making the migration safe to re-run after any manual linking.
select public.recount_report_confirms(id)
  from public.reports
 where duplicate_of is null;
