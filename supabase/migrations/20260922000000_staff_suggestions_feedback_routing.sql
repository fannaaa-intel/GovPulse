-- ════════════════════════════════════════════════════════════════════════════
--  Staff suggestions + feedback: department routing
--
--  WHY
--  Reports route to one of four LGU offices automatically (report_department()).
--  Suggestions and feedback did not route anywhere — every one of them landed on
--  the admin console and nowhere else, so a single admin absorbed all of it.
--
--  This migration gives both tables the same `department` column reports already
--  have, filled by trigger, so the existing four offices each get two more
--  inboxes. No new department, no new role, no new staff account.
--
--  THE "OTHERS" CASE
--  A suggestion category of 'others' carries no routing information. classify-
--  suggestion already re-derives the REAL category into `ai_category` from what
--  the citizen wrote — that column is live (verified in pg_attribute) and until
--  now drove only the admin's "mis-filed" chip. Here it becomes authoritative
--  for routing, but ONLY for 'others':
--
--    • a category the citizen picked deliberately is never overridden. If they
--      chose Infrastructure and the AI disagrees, it stays in Engineering and
--      the mis-filed chip remains the admin's call.
--    • the AI arrives LATE (webhook on insert, cron sweep every 15 min), so the
--      row routes to Mayor's Office on insert and is re-routed when ai_category
--      lands. Mayor's Office staff will occasionally see an item appear and then
--      leave. That is the design, not a bug.
--    • re-routing stops the moment anyone touches the row (status moved off
--      'pending', an admin note, a response, a dismissal, or a staff reply
--      already drafted). Work must never vanish out from under someone
--      mid-sentence.
--
--  FEEDBACK does not use the AI. Its form has no "Others" — the citizen picks
--  one of five concrete offices, all five map cleanly, so there is nothing to
--  infer. This deliberately does not disturb the locked no-routing decision for
--  classify-feedback (it emits sentiment/urgency/theme only, verified).
--
--  ENVIRONMENT OFFICE receives NO feedback, ever: no office in the citizen form
--  maps to it. The staff console hides the Feedback tab for that department
--  rather than showing a room that can never fill.
--
--  VERIFIED BEFORE WRITING (live catalog, not assumption):
--    • suggestions has ai_category/ai_category_reason/ai_theme/ai_classified_at
--    • neither table has `department`
--    • report_department(text) and current_staff_department() exist as used here
--    • reports has NO staff RLS policy — staff read through staff_reports_view,
--      gated by staff_can_see_report(). This migration mirrors that shape.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1. The routing columns ──────────────────────────────────────────────────
alter table public.suggestions add column if not exists department text;
alter table public.feedbacks   add column if not exists department text;

comment on column public.suggestions.department is
  'LGU office that owns this suggestion. Set by trg_route_suggestion on insert, '
  're-routed from ai_category only when the citizen picked "others" and nobody '
  'has touched the row yet.';
comment on column public.feedbacks.department is
  'LGU office that owns this feedback, derived from office_id. Never AI-routed.';

-- ── 2. Routing functions ────────────────────────────────────────────────────
-- Mirrors report_department()'s shape: IMMUTABLE, total (always returns an
-- office), and defaulting to Mayor's Office so a category we have never seen
-- still lands somewhere a human will read it.

create or replace function public.suggestion_department(p_category text)
returns text language sql immutable as $$
  select case p_category
    when 'infrastructure'   then 'Engineering Office'
    when 'environment'      then 'Environment Office'
    when 'health_safety'    then 'Sanitation Office'
    when 'public_service'   then 'Mayor''s Office'
    when 'community_program' then 'Mayor''s Office'
    else 'Mayor''s Office'   -- 'others' + anything unrecognised
  end;
$$;

comment on function public.suggestion_department(text) is
  'Suggestion category key -> owning LGU office. Health & Safety routes to '
  'Sanitation as the nearest public-health office in the four-office set.';

create or replace function public.feedback_department(p_office_id text)
returns text language sql immutable as $$
  select case p_office_id
    when 'health' then 'Sanitation Office'
    when 'mpdo'   then 'Engineering Office'
    when 'mayor'  then 'Mayor''s Office'
    when 'civil'  then 'Mayor''s Office'
    when 'cert'   then 'Mayor''s Office'
    else 'Mayor''s Office'
  end;
$$;

comment on function public.feedback_department(text) is
  'Feedback office_id -> owning LGU office. No office maps to Environment, '
  'which is why the staff console hides that tab for Environment Office.';

-- ── 3. Route on insert ──────────────────────────────────────────────────────
-- A trigger, not client code: the citizen web app, the mobile app and any path
-- written later all insert through this. A client-side assignment would be one
-- forgotten call site away from an unrouted row that no staff member can see.

create or replace function public.route_suggestion()
returns trigger language plpgsql as $$
begin
  if new.department is null then
    -- The citizen's own category. 'others' deliberately falls through to
    -- Mayor's Office here; ai_category has not arrived yet at insert time.
    new.department := public.suggestion_department(new.category);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_route_suggestion on public.suggestions;
create trigger trg_route_suggestion
  before insert on public.suggestions
  for each row execute function public.route_suggestion();

create or replace function public.route_feedback()
returns trigger language plpgsql as $$
begin
  if new.department is null then
    new.department := public.feedback_department(new.office_id);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_route_feedback on public.feedbacks;
create trigger trg_route_feedback
  before insert on public.feedbacks
  for each row execute function public.route_feedback();

-- ── 4. Re-route "others" when the AI lands ──────────────────────────────────
-- Fires only on a real ai_category transition. Four guards, each one load-
-- bearing:
--   a) the citizen picked 'others'      — never override a deliberate choice
--   b) the AI did not also say 'others' — no information gained
--   c) the row is untouched             — see is_suggestion_untouched()
--   d) the target differs               — avoid a no-op write that would churn
--                                         realtime subscribers

create or replace function public.is_suggestion_untouched(p_row public.suggestions)
returns boolean language sql immutable as $$
  select coalesce(p_row.status, 'pending') = 'pending'
     and p_row.admin_note      is null
     and p_row.admin_response  is null
     and p_row.reviewed_at     is null
     and p_row.dismissed_at    is null;
$$;

comment on function public.is_suggestion_untouched(public.suggestions) is
  'True while no human has acted on the suggestion. Gates AI re-routing so a '
  'late classification cannot move an item a staff member is already answering.';

create or replace function public.reroute_suggestion_from_ai()
returns trigger language plpgsql as $$
declare
  v_target text;
begin
  if new.ai_category is null
     or new.ai_category is not distinct from old.ai_category then
    return new;
  end if;
  if coalesce(new.category, '') <> 'others' then return new; end if;
  if new.ai_category = 'others'             then return new; end if;
  if not public.is_suggestion_untouched(new) then return new; end if;
  -- A staff member may have drafted a reply before the AI landed. That is a
  -- touch too, but it lives in another table, so it is checked separately.
  if exists (select 1 from public.suggestion_replies sr
              where sr.suggestion_id = new.id) then
    return new;
  end if;

  v_target := public.suggestion_department(new.ai_category);
  if v_target is distinct from new.department then
    new.department := v_target;
  end if;
  return new;
end;
$$;

-- Created after suggestion_replies exists (section 5) — see the trigger at the
-- end of this migration.

-- ── 5. Staff replies to suggestions (staff draft -> admin approves) ─────────
-- The reply CANNOT live on suggestions.admin_response: that column is what the
-- citizen reads. A draft awaiting approval sharing a column with published text
-- is one stray update away from publishing itself. Separate table, own status,
-- mirroring the community_posts loop (pending_approval | approved | rejected).

create table if not exists public.suggestion_replies (
  id             uuid primary key default gen_random_uuid(),
  suggestion_id  uuid not null references public.suggestions(id) on delete cascade,
  author_id      uuid not null references auth.users(id) on delete cascade,
  department     text not null,
  body           text not null check (length(btrim(body)) > 0),
  status         text not null default 'pending_approval'
                 check (status in ('pending_approval','approved','rejected')),
  rejected_reason text,
  approved_by    uuid references auth.users(id) on delete set null,
  approved_at    timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

-- One live reply per suggestion. A rejected draft is revised in place, so the
-- partial index covers only the states that can still be published.
create unique index if not exists suggestion_replies_one_live
  on public.suggestion_replies (suggestion_id)
  where status in ('pending_approval','approved');

create index if not exists suggestion_replies_dept_status
  on public.suggestion_replies (department, status, created_at desc);
create index if not exists suggestion_replies_author
  on public.suggestion_replies (author_id, created_at desc);

comment on table public.suggestion_replies is
  'Staff-written replies to suggestions, held unpublished until an admin '
  'approves. The citizen sees nothing and gets no push until status=approved.';

alter table public.suggestion_replies enable row level security;

-- Now the re-route trigger can reference suggestion_replies.
drop trigger if exists trg_reroute_suggestion_ai on public.suggestions;
create trigger trg_reroute_suggestion_ai
  before update of ai_category on public.suggestions
  for each row execute function public.reroute_suggestion_from_ai();

-- ── 6. Staff read paths ─────────────────────────────────────────────────────
-- Reports set the precedent: `reports` has NO staff policy at all; staff read
-- through staff_reports_view, gated by a SECURITY DEFINER predicate. Same shape
-- here, which keeps the citizen-identity masking in one auditable place.

create or replace function public.staff_owns_department(p_department text)
returns boolean language sql stable security definer
set search_path to 'public', 'pg_temp' as $$
  select public.current_user_role_id() = 2
     and p_department is not null
     and p_department = public.current_staff_department();
$$;

comment on function public.staff_owns_department(text) is
  'True when the caller is staff (role_id 2) and the row belongs to their '
  'office. The single department predicate behind every staff-facing view here.';

-- Anonymous submitters are masked exactly as staff_reports_view masks them:
-- user_id becomes NULL. is_anonymous never unowns the row — it only hides who
-- wrote it from the console.
create or replace view public.staff_suggestions_view
with (security_invoker = true) as
  select
    s.id,
    case when s.is_anonymous then null::uuid else s.user_id end as user_id,
    s.category,
    s.category_other,
    s.barangay,
    s.address,
    s.latitude,
    s.longitude,
    s.details,
    s.is_anonymous,
    s.status,
    s.created_at,
    s.updated_at,
    s.department,
    s.ai_category,
    s.ai_category_reason,
    s.ai_theme,
    s.ai_classified_at,
    s.admin_response,
    s.reviewed_at,
    s.dismissed_at,
    s.dismissed_reason
  from public.suggestions s
  where public.staff_owns_department(s.department);

create or replace view public.staff_feedbacks_view
with (security_invoker = true) as
  select
    f.id,
    case when f.is_anonymous then null::uuid else f.user_id end as user_id,
    case when f.is_anonymous then null::text else f.username end as username,
    f.office_id,
    f.office_label,
    f.service_name,
    f.overall_rating,
    f.aspect_staff,
    f.aspect_wait,
    f.aspect_clarity,
    f.aspect_facility,
    f.comment,
    f.visit_date,
    f.is_anonymous,
    f.status,
    f.created_at,
    f.department,
    f.ai_sentiment,
    f.ai_urgency,
    f.ai_theme,
    f.admin_response,
    f.reviewed_at,
    f.dismissed_at
  from public.feedbacks f
  where public.staff_owns_department(f.department);

comment on view public.staff_suggestions_view is
  'Department-scoped, anonymity-masked suggestions for the staff console.';
comment on view public.staff_feedbacks_view is
  'Department-scoped, anonymity-masked feedback for the staff console. '
  'READ ONLY by design — staff never author the public reply to a rating of '
  'their own office.';

-- security_invoker views need the underlying SELECT to succeed for the caller,
-- so staff need a SELECT policy on the base tables. The policy carries the same
-- department predicate, which means the view is a presentation layer, not the
-- security boundary — a staff member querying the base table directly gets the
-- same rows (minus the masking, which is why the app must use the views).
drop policy if exists staff_reads_department_suggestions on public.suggestions;
create policy staff_reads_department_suggestions
  on public.suggestions for select to authenticated
  using (public.staff_owns_department(department));

drop policy if exists staff_reads_department_feedbacks on public.feedbacks;
create policy staff_reads_department_feedbacks
  on public.feedbacks for select to authenticated
  using (public.staff_owns_department(department));

grant select on public.staff_suggestions_view to authenticated;
grant select on public.staff_feedbacks_view   to authenticated;

-- ── 7. Reply RLS ────────────────────────────────────────────────────────────
-- role_id 2 has no INSERT anywhere by default; every staff write needs its own
-- policy or it fails in a way that reads as a flaky network, not a permission
-- error. Both the INSERT and the UPDATE are spelled out here.

drop policy if exists staff_reads_own_dept_replies on public.suggestion_replies;
create policy staff_reads_own_dept_replies
  on public.suggestion_replies for select to authenticated
  using (public.staff_owns_department(department) or public.is_admin());

drop policy if exists staff_writes_own_dept_replies on public.suggestion_replies;
create policy staff_writes_own_dept_replies
  on public.suggestion_replies for insert to authenticated
  with check (
    author_id = auth.uid()
    and public.staff_owns_department(department)
    and status = 'pending_approval'
    -- The reply's department must match the suggestion's, or a staff member
    -- could file a reply against another office's item.
    and exists (
      select 1 from public.suggestions s
      where s.id = suggestion_id and s.department = department
    )
  );

-- A staff member may revise their OWN draft while it is unpublished. They can
-- never move it to 'approved' — that transition is the admin's alone, and the
-- WITH CHECK pins the status to keep it that way.
drop policy if exists staff_revises_own_pending_reply on public.suggestion_replies;
create policy staff_revises_own_pending_reply
  on public.suggestion_replies for update to authenticated
  using (
    author_id = auth.uid()
    and public.staff_owns_department(department)
    and status in ('pending_approval','rejected')
  )
  with check (
    author_id = auth.uid()
    and public.staff_owns_department(department)
    and status = 'pending_approval'
  );

drop policy if exists admin_manages_replies on public.suggestion_replies;
create policy admin_manages_replies
  on public.suggestion_replies for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

grant select, insert, update on public.suggestion_replies to authenticated;

-- ── 8. Publish on approval ──────────────────────────────────────────────────
-- Approval is what makes the reply real: it copies the body onto the suggestion
-- (where the citizen's "LGU Response" block reads it) and fires the push. Doing
-- both here rather than in the client means a reply can never be visible
-- without having been approved, whatever the console does.

create or replace function public.publish_approved_suggestion_reply()
returns trigger language plpgsql security definer
set search_path to 'public', 'pg_temp' as $$
declare
  v_row       public.suggestions%rowtype;
  v_label     text;
  v_snippet   text;
  v_photo     text;
begin
  if new.status = old.status then return new; end if;

  -- ── approved ──
  if new.status = 'approved' then
    select * into v_row from public.suggestions where id = new.suggestion_id;
    if not found then return new; end if;

    -- The staff author's face, not the approving admin's: the citizen is
    -- reading the office's answer. admin_profiles holds staff rows too (it is
    -- what current_staff_department() reads), so one lookup serves both.
    select photo_url into v_photo
      from public.admin_profiles where user_id = new.author_id;

    update public.suggestions
       set admin_response     = new.body,
           responder_photo_url = v_photo,
           reviewed_by        = new.approved_by,
           reviewed_at        = now(),
           -- The app's vocabulary is 'pending' | 'responded' (see
           -- suggestionStatusToDb in admin_suggestions_provider.dart). Writing
           -- anything else here would render as "New" forever.
           status             = 'responded',
           updated_at         = now()
     where id = new.suggestion_id;

    if v_row.user_id is not null then
      v_label := coalesce(nullif(btrim(v_row.category_other), ''),
                          initcap(replace(coalesce(v_row.category,'')  , '_', ' ')));
      v_snippet := left(btrim(new.body), 120);
      insert into public.notifications
        (user_id, icon_code, title, subtitle, color_value, type,
         is_approved, sent_by, actor_id, actor_photo_url, reference_id)
      values
        (v_row.user_id, 0,
         case when v_label is null or v_label = ''
              then 'The LGU replied to your suggestion'
              else 'The LGU replied to your ' || v_label || ' suggestion' end,
         v_snippet, 4281257073, 'suggestion_response',
         true, new.approved_by, new.author_id, v_photo,
         new.suggestion_id::text);
    end if;
    return new;
  end if;

  -- ── rejected: ping the staff author so the draft does not sit silently ──
  if new.status = 'rejected' then
    insert into public.notifications
      (user_id, icon_code, title, subtitle, color_value, type,
       is_approved, sent_by, reference_id)
    values
      (new.author_id, 0,
       'Your suggestion reply needs changes',
       coalesce(nullif(btrim(new.rejected_reason), ''),
                'The Municipality returned your draft for revision.'),
       4293348412, 'suggestion_reply_rejected',
       true, new.approved_by, new.suggestion_id::text);
  end if;

  return new;
end;
$$;

drop trigger if exists trg_publish_suggestion_reply on public.suggestion_replies;
create trigger trg_publish_suggestion_reply
  after update of status on public.suggestion_replies
  for each row execute function public.publish_approved_suggestion_reply();

-- Ping every admin when a draft arrives, mirroring the community_posts loop.
create or replace function public.notify_admins_of_pending_reply()
returns trigger language plpgsql security definer
set search_path to 'public', 'pg_temp' as $$
begin
  if new.status <> 'pending_approval' then return new; end if;
  insert into public.notifications
    (user_id, icon_code, title, subtitle, color_value, type,
     is_approved, sent_by, actor_id, reference_id)
  select ur.user_id, 0,
         'A staff reply is waiting for approval',
         new.department || ' drafted a reply to a suggestion.',
         4281257073, 'suggestion_reply_pending',
         true, new.author_id, new.author_id, new.suggestion_id::text
    from public.user_roles ur
   where ur.role_id = 1;
  return new;
end;
$$;

drop trigger if exists trg_notify_admins_pending_reply on public.suggestion_replies;
create trigger trg_notify_admins_pending_reply
  after insert on public.suggestion_replies
  for each row execute function public.notify_admins_of_pending_reply();

-- ── 9. Backfill ─────────────────────────────────────────────────────────────
-- Every pre-existing row must get a department in the SAME migration that adds
-- the column. A null department satisfies no staff predicate, so an unbackfilled
-- row is invisible to every office — it would look like data loss.
--
-- 'others' rows use ai_category where the classifier has already reached them,
-- which is the same rule the trigger applies going forward.
update public.suggestions
   set department = public.suggestion_department(
         case when coalesce(category,'') = 'others'
                   and ai_category is not null
                   and ai_category <> 'others'
              then ai_category else category end)
 where department is null;

update public.feedbacks
   set department = public.feedback_department(office_id)
 where department is null;

-- ── 10. Indexes for the staff console's list queries ────────────────────────
create index if not exists suggestions_department_created
  on public.suggestions (department, created_at desc);
create index if not exists feedbacks_department_created
  on public.feedbacks (department, created_at desc);
