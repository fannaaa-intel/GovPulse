-- drop_live_staff_chat.sql  (STAGE B — see supabase/pending/README.md)
--
-- Removes what is left of the live citizen-to-staff chat after stage A
-- (20261012000000_close_live_staff_chat.sql) stopped every new write.
--
-- PRECONDITIONS, all three:
--   1. stage A is applied;
--   2. create-staff is redeployed — the old one writes admin_profiles.is_online
--      on every new staff account and would fail once §6 drops it;
--   3. the app build without live chat is live on web AND Play Store. An older
--      build selects concern_tickets / admin_profiles.is_online and would
--      error instead of degrading.
--
-- Order matters: things that READ the tables (cron, views, the spam function)
-- are fixed or dropped before the tables, and the trigger functions after them.
--
-- Live dependency audit this is built from (2026-10-12): 3 views, 19 public
-- functions, 2 realtime publication entries, 3 storage.objects policies, an
-- hourly pg_cron job, and nothing else referencing these objects.

-- ── 1. The hourly ghost-ticket cleanup ──────────────────────────────────────
-- Created in the dashboard, so it is in no migration. Unscheduled by command
-- text rather than by name for that reason; dropping its function first would
-- leave a job failing every hour.
do $$
declare j record;
begin
  if to_regclass('cron.job') is not null then
    for j in select jobid from cron.job where command ilike '%delete_old_ghost_tickets%'
    loop
      perform cron.unschedule(j.jobid);
    end loop;
  end if;
end $$;

-- ── 2. Spam watch without the chat channel ──────────────────────────────────
-- Identical to the live definition except the ticket_messages branch is gone.
create or replace function public.admin_spam_watch(window_hours integer default 24)
returns table(user_id text, username text, total_items integer, duplicate_items integer,
              flagged_items integer, channels integer, last_active timestamptz, score numeric)
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  min_items   int := public.moderation_setting('spam_min_items', 5)::int;
  min_dupes   int := public.moderation_setting('spam_min_dupes', 2)::int;
  min_flagged int := public.moderation_setting('spam_min_flagged', 1)::int;
  w_dupe      numeric := public.moderation_setting('spam_weight_dupe', 3);
  w_flagged   numeric := public.moderation_setting('spam_weight_flagged', 2);
begin
  -- Guard: this reads every user's content, so admins only.
  if not exists (
    select 1 from public.user_roles
    where user_roles.user_id = auth.uid() and role_id = 1
  ) then
    raise exception 'admin only';
  end if;

  return query
  with since as (
    select now() - make_interval(hours => greatest(window_hours, 1)) as t
  ),
  items as (
    select author_id::text as uid,
           public.normalize_text(coalesce(title, '') || ' ' || coalesce(body, '')) as norm,
           coalesce(flagged, false) as fl, 'post' as ch, created_at
      from public.community_posts, since
     where created_at >= since.t and author_id is not null
    union all
    select author_id::text,
           public.normalize_text(body),
           coalesce(flagged, false), 'comment', created_at
      from public.community_comments, since
     where created_at >= since.t and author_id is not null
    union all
    select user_id::text, public.normalize_text(remarks),
           false, 'report', created_at
      from public.reports, since
     where created_at >= since.t and user_id is not null
    union all
    select user_id::text, public.normalize_text(details),
           false, 'suggestion', created_at
      from public.suggestions, since
     where created_at >= since.t and user_id is not null
    union all
    select user_id::text, public.normalize_text(coalesce(comment, '')),
           false, 'feedback', created_at
      from public.feedbacks, since
     where created_at >= since.t and user_id is not null
  ),
  agg as (
    select uid,
           count(*)::int as total_items,
           -- Duplicates among TEXT-BEARING rows only; see 20260822000001.
           (count(*) filter (where norm <> '')
              - count(distinct norm) filter (where norm <> ''))::int
             as duplicate_items,
           (count(*) filter (where fl))::int as flagged_items,
           count(distinct ch)::int as channels,
           max(created_at) as last_active
      from items
     group by uid
  )
  select a.uid,
         p.username,
         a.total_items, a.duplicate_items, a.flagged_items, a.channels,
         a.last_active,
         (a.total_items + a.duplicate_items * w_dupe + a.flagged_items * w_flagged)::numeric
    from agg a
    left join public.profiles p on p.id::text = a.uid
   where a.total_items >= min_items
      or a.duplicate_items >= min_dupes
      or a.flagged_items >= min_flagged
   order by score desc
   limit 100;
end;
$function$;

-- ── 3. Staff scorecard without chat ratings ─────────────────────────────────
-- DROP + CREATE, not CREATE OR REPLACE: a view cannot lose columns in place.
-- The app reads it with select(), so the two vanished columns break nothing.
drop view if exists public.staff_performance_view;

create view public.staff_performance_view
with (security_invoker = true) as
with resolutions as (
  -- A completion update an admin approved ('completion' is the whole
  -- vocabulary for "this report is finished", per 20260829000001).
  select ru.author_id as user_id, count(*)::int as n
    from public.report_updates ru
   where ru.status = 'approved'
     and ru.kind = 'completion'
   group by ru.author_id
),
replies as (
  select sr.author_id as user_id,
         count(*) filter (where sr.status = 'approved')::int as approved,
         count(*) filter (where sr.status = 'rejected')::int as rejected,
         -- Median, not mean: one very late answer must not misrepresent an
         -- otherwise prompt office.
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
  coalesce(rep.approved, 0)       as replies_approved,
  coalesce(rep.rejected, 0)       as replies_rejected,
  round(rep.median_hours::numeric, 1) as median_response_hours
from public.admin_profiles ap
join public.user_roles ur on ur.user_id = ap.user_id and ur.role_id = 2
left join resolutions r  on r.user_id   = ap.user_id
left join replies rep    on rep.user_id = ap.user_id
-- External agencies are not LGU staff and do not belong on this leaderboard.
where coalesce(ap.is_external, false) = false;

comment on view public.staff_performance_view is
  'Per-staff scorecard built ONLY from actions the person took. Citizen office '
  'ratings are excluded by design — feedbacks has no staff id. Chat ratings '
  'went with the live staff chat (2026-10-12). Staff read their own row; '
  'admins read all.';

grant select on public.staff_performance_view to authenticated;

-- ── 4. The chat's own views, storage rules and tables ───────────────────────
drop view if exists public.staff_messages_view;
drop view if exists public.staff_tickets_view;

drop policy if exists "Users upload to own folder"  on storage.objects;
drop policy if exists "Users read own attachments"  on storage.objects;
drop policy if exists "Users delete own attachments" on storage.objects;

-- Dropping a table also drops its triggers, its policies and its entry in the
-- supabase_realtime publication.
drop table if exists public.ticket_attachments;
drop table if exists public.ticket_messages;
drop table if exists public.concern_tickets;

-- ── 5. Functions that only served the chat ──────────────────────────────────
drop function if exists public.agent_avg_rating();
drop function if exists public.assign_ticket_staff(uuid, uuid);
drop function if exists public.delete_old_ghost_tickets();
drop function if exists public.department_ticket_citizens();
drop function if exists public.find_available_staff(text);
drop function if exists public.promote_ticket(uuid, uuid);
drop function if exists public.rate_ticket(uuid, integer, text);
drop function if exists public.staff_can_see_ticket(uuid);
drop function if exists public.staff_claim_ticket(uuid);
drop function if exists public.staff_set_ticket_status(uuid, text);
drop function if exists public.staff_touch_ticket(uuid);
drop function if exists public.ticket_accepts_messages(uuid);
drop function if exists public.ticket_agent(uuid);
drop function if exists public.ticket_citizen(uuid);
drop function if exists public.ticket_has_staff_message(uuid);
drop function if exists public.notify_citizen_new_message();
drop function if exists public.notify_staff_new_message();
drop function if exists public.notify_staff_ticket_assigned();
drop function if exists public.concern_tickets_enforce_anonymity();

-- ── 6. The on-duty flag ─────────────────────────────────────────────────────
-- last_seen_at was written only by the removed on-duty toggle.
alter table public.admin_profiles drop column if exists is_online;
alter table public.admin_profiles drop column if exists last_seen_at;

-- NOT done here: the `ticket-attachments` storage bucket and any files in it.
-- Storage objects cannot be deleted from SQL; empty and delete the bucket from
-- the dashboard (Storage → ticket-attachments) after this has run.
