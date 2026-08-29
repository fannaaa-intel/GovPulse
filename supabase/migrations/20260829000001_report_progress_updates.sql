-- ============================================================================
-- 20260829000001  Progress updates — posted by the office, approved by the
--                 admin, then visible to the citizen
-- ============================================================================
-- A report's STATUS is four milestones (pending / under_review / in_progress /
-- resolved). What it never had is the running account underneath them: "site
-- inspected, three potholes found", "materials delivered", "patching started".
-- That is what this adds.
--
-- ── THE SHAPE, AND WHY IT COPIES THE COMMUNITY-POST LOOP ───────────────────
-- Nothing an office writes reaches the citizen unreviewed:
--
--   office posts  ->  pending_approval  ->  admin approves  ->  citizen sees it
--                                       \-> admin rejects with a reason
--                                           (author fixes and resubmits)
--
-- This app already runs exactly that loop for community posts (20260719000001
-- and …000002): same three status words, same rejected_reason column, same
-- "the author's own submission auto-approves when they are the approver" rule,
-- same notify-on-decision trigger. Copying it is deliberate — a second review
-- vocabulary would be a second thing to learn and a second thing to get wrong.
--
-- ── WHY A NEW TABLE AND NOT report_notes ───────────────────────────────────
-- report_notes is the PRIVATE admin<->staff channel. Its own header says the
-- citizen never sees it, and staff_return_to_triage writes internal audit lines
-- into it ("Returned to triage - not this office's scope"). Opening it to
-- citizens would expose all of that retroactively. It keeps working unchanged;
-- progress updates are a separate, citizen-facing thing.
--
-- ── PHOTOS ─────────────────────────────────────────────────────────────────
-- Photos hang off an UPDATE, not off the report, so a picture always arrives
-- with the words explaining it. That also closes a real hole: completion photos
-- (report_resolution_media) currently reach the citizen the instant they are
-- uploaded, with no review at all — rrm_select grants owns_report() with no
-- status condition. Media attached here inherits its update's approval state,
-- so the same photo now waits for an admin.
--
-- The body text is required even when photos are attached: an update is words.
--
-- ── THE AGENCY POSTS TOO, WITH NO ACCOUNT ──────────────────────────────────
-- An endorsed report is worked by a national agency that holds no login — only
-- the letter's token and PIN (see 20260801000000). So there is an anon-callable
-- RPC, post_endorsement_update, authorised exactly the way advance_endorsement
-- is: bcrypt PIN check, attempt limiter, and a withdrawn endorsement refused.
-- Anonymous writes are safe here precisely BECAUSE of the approval gate — the
-- worst a stolen letter achieves is queuing something for an admin to reject.
--
-- Rollback: supabase/rollback/20260829000001_report_progress_updates_rollback.sql
-- Verify:   supabase/diagnostics/verify_20260829000001.sql
-- ============================================================================

begin;

-- ── 1. The update ──────────────────────────────────────────────────────────
create table if not exists public.report_updates (
  id             uuid primary key default gen_random_uuid(),
  report_id      uuid not null references public.reports(id) on delete cascade,

  body           text not null check (btrim(body) <> ''),

  -- 'progress' is the running commentary; 'completion' is the closing one that
  -- accompanies the work being finished. Both accept photos — the distinction
  -- is what the citizen's timeline labels them, not what they may carry.
  kind           text not null default 'progress'
                   check (kind in ('progress', 'completion')),

  status         text not null default 'pending_approval'
                   check (status in ('pending_approval', 'approved', 'rejected')),
  rejected_reason text,

  -- Who wrote it. author_id is null for an agency (no account exists), which is
  -- why author_role carries the answer instead of being derived from the uid.
  author_id      uuid references auth.users(id) on delete set null,
  author_role    text not null check (author_role in ('admin', 'staff', 'agency')),
  -- Display label: the office or agency name. Never a person — the same
  -- office-not-person shape 20260722000017 settled on.
  author_name    text not null,

  reviewed_by    uuid references auth.users(id) on delete set null,
  reviewed_at    timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

-- The citizen's timeline is "approved updates for this report, newest first",
-- and the admin queue is "pending, oldest first". One index per read.
create index if not exists idx_report_updates_report_status
  on public.report_updates (report_id, status, created_at desc);
create index if not exists idx_report_updates_pending
  on public.report_updates (created_at)
  where status = 'pending_approval';

-- ── 2. Photos on an update ─────────────────────────────────────────────────
create table if not exists public.report_update_media (
  id            uuid primary key default gen_random_uuid(),
  update_id     uuid not null
                  references public.report_updates(id) on delete cascade,
  storage_path  text not null,
  mime_type     text,
  uploaded_by   uuid references auth.users(id) on delete set null,
  created_at    timestamptz not null default now()
);

create index if not exists idx_report_update_media_update
  on public.report_update_media (update_id);

-- ── 3. Visibility helper ───────────────────────────────────────────────────
-- One definition of "may this caller see this update", used by both tables'
-- policies so they cannot drift apart. Stable + definer, matching the house
-- helpers (is_admin, staff_can_see_report, owns_report).
create or replace function public.can_see_report_update(p_update uuid)
returns boolean
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $$
  select exists (
    select 1
      from public.report_updates u
     where u.id = p_update
       and (
            public.is_admin()
         or public.staff_can_see_report(u.report_id)
         -- The citizen sees APPROVED updates on their own report, and nothing
         -- else. This is the whole point of the loop.
         or (u.status = 'approved' and public.owns_report(u.report_id))
       )
  );
$$;

revoke all on function public.can_see_report_update(uuid) from public, anon;
grant execute on function public.can_see_report_update(uuid) to authenticated;

-- ── 4. RLS ─────────────────────────────────────────────────────────────────
alter table public.report_updates      enable row level security;
alter table public.report_update_media enable row level security;

-- Reads.
drop policy if exists report_updates_read on public.report_updates;
create policy report_updates_read
  on public.report_updates for select
  to authenticated
  using (
       public.is_admin()
    or public.staff_can_see_report(report_id)
    or (status = 'approved' and public.owns_report(report_id))
  );

-- Staff insert their OWN updates, and only as pending. The status literal in
-- the WITH CHECK is what stops an office publishing straight to the citizen.
drop policy if exists report_updates_staff_insert on public.report_updates;
create policy report_updates_staff_insert
  on public.report_updates for insert
  to authenticated
  with check (
    author_id = (select auth.uid())
    and author_role = 'staff'
    and status = 'pending_approval'
    and public.staff_can_see_report(report_id)
  );

-- Admins do everything, including posting their own (auto-approved by the
-- trigger below) and deciding on someone else's.
drop policy if exists report_updates_admin_all on public.report_updates;
create policy report_updates_admin_all
  on public.report_updates for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- Media follows its update.
drop policy if exists report_update_media_read on public.report_update_media;
create policy report_update_media_read
  on public.report_update_media for select
  to authenticated
  using (public.can_see_report_update(update_id));

drop policy if exists report_update_media_insert on public.report_update_media;
create policy report_update_media_insert
  on public.report_update_media for insert
  to authenticated
  with check (
    uploaded_by = (select auth.uid())
    and exists (
      select 1 from public.report_updates u
       where u.id = update_id
         and (public.is_admin() or public.staff_can_see_report(u.report_id))
    )
  );

drop policy if exists report_update_media_delete on public.report_update_media;
create policy report_update_media_delete
  on public.report_update_media for delete
  to authenticated
  using (
    exists (
      select 1 from public.report_updates u
       where u.id = update_id
         and (public.is_admin() or public.staff_can_see_report(u.report_id))
    )
  );

-- ── 5. Grants ──────────────────────────────────────────────────────────────
-- Supabase's default privileges grant new tables to anon AND authenticated, so
-- the revoke must name both — the 20260722000002 lesson, where omitting
-- `authenticated` left an explicit default grant standing and made the next
-- statement a no-op.
revoke all on public.report_updates      from public, anon, authenticated;
revoke all on public.report_update_media from public, anon, authenticated;

grant select, insert on public.report_updates      to authenticated;
grant update         on public.report_updates      to authenticated;  -- admin decision, scoped by policy
grant select, insert, delete on public.report_update_media to authenticated;

-- ── 6. Admin's own updates are already approved ────────────────────────────
-- The admin IS the approver; making them review themselves is a pointless
-- click. Mirrors notify_author_post_decision's `new.author_id = auth.uid()`
-- skip in the community loop.
create or replace function public.auto_approve_admin_update()
returns trigger
language plpgsql security definer set search_path to 'public'
as $$
begin
  if new.author_role = 'admin' and public.is_admin() then
    new.status      := 'approved';
    new.reviewed_by := auth.uid();
    new.reviewed_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists trg_auto_approve_admin_update on public.report_updates;
create trigger trg_auto_approve_admin_update
  before insert on public.report_updates
  for each row execute function public.auto_approve_admin_update();

-- ── 7. Decision RPC ────────────────────────────────────────────────────────
-- Admin-only, and a rejection must say why: the reason is shown to the office
-- that wrote the update so they can fix and resubmit. A bare UPDATE could not
-- enforce that pairing.
create or replace function public.review_report_update(
  p_update uuid,
  p_approve boolean,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not public.is_admin() then
    raise exception 'Only an LGU admin can review a progress update'
      using errcode = '42501';
  end if;

  if not p_approve and coalesce(btrim(p_reason), '') = '' then
    raise exception 'A reason is required when rejecting an update'
      using errcode = '22023';
  end if;

  update public.report_updates
     set status          = case when p_approve then 'approved' else 'rejected' end,
         rejected_reason = case when p_approve then null else btrim(p_reason) end,
         reviewed_by     = auth.uid(),
         reviewed_at     = now(),
         updated_at      = now()
   where id = p_update;

  if not found then
    raise exception 'Update not found' using errcode = 'P0002';
  end if;
end;
$function$;

revoke all on function public.review_report_update(uuid, boolean, text)
  from public, anon;
grant execute on function public.review_report_update(uuid, boolean, text)
  to authenticated;

-- ── 8. The agency's anon, PIN-gated post ───────────────────────────────────
-- Same authority model as advance_endorsement: the token identifies the
-- endorsement, the PIN authorises the write, attempts are limited per
-- endorsement, and a withdrawn endorsement authorises nothing.
create or replace function public.post_endorsement_update(
  p_token text,
  p_pin   text,
  p_body  text,
  p_kind  text default 'progress'
)
returns json
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  e      public.report_endorsements%rowtype;
  v_id   uuid;
  v_left integer;
  c_max_attempts constant integer := 5;
begin
  if coalesce(btrim(p_body), '') = '' then
    return json_build_object('ok', false, 'error', 'empty_body');
  end if;

  if coalesce(p_kind, 'progress') not in ('progress', 'completion') then
    return json_build_object('ok', false, 'error', 'bad_kind');
  end if;

  select * into e
    from public.report_endorsements
   where token = p_token
   for update;

  if not found then
    return json_build_object('ok', false, 'error', 'invalid_token');
  end if;

  if e.state = 'withdrawn' then
    return json_build_object('ok', false, 'error', 'withdrawn');
  end if;

  if e.locked_until is not null and e.locked_until > now() then
    return json_build_object('ok', false, 'error', 'locked',
                             'locked_until', e.locked_until);
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

  -- Cheap flood guard on top of the PIN check: an agency posting more than 20
  -- updates an hour on one endorsement is not a workflow, and every row here
  -- costs an admin a review.
  if (select count(*) from public.report_updates
       where report_id = e.report_id
         and author_role = 'agency'
         and created_at > now() - interval '1 hour') >= 20 then
    return json_build_object('ok', false, 'error', 'rate_limited');
  end if;

  update public.report_endorsements
     set pin_attempts = 0, locked_until = null, updated_at = now()
   where id = e.id;

  insert into public.report_updates
    (report_id, body, kind, status, author_id, author_role, author_name)
  values
    (e.report_id, btrim(p_body), coalesce(p_kind, 'progress'),
     'pending_approval', null, 'agency', e.agency)
  returning id into v_id;

  return json_build_object('ok', true, 'id', v_id, 'status', 'pending_approval');
end;
$function$;

revoke all on function public.post_endorsement_update(text, text, text, text)
  from public;
grant execute on function public.post_endorsement_update(text, text, text, text)
  to anon, authenticated;

-- ── 9. Notifications ───────────────────────────────────────────────────────
-- Two audiences, one trigger, both wrapped so a notification failure can never
-- roll back the update itself (the house rule from staff_notifications.sql).
create or replace function public.notify_report_update_decision()
returns trigger
language plpgsql security definer set search_path to 'public'
as $$
begin
  if new.status = old.status then return new; end if;

  -- The citizen, when an update goes live on their report.
  if new.status = 'approved' then
    begin
      insert into public.notifications
        (user_id, topic, title, subtitle, type, color_value, icon_code,
         is_approved, sent_by, reference_id)
      select r.user_id, 'report_update',
             'New update on your report',
             left(new.body, 120),
             'report_update', 4279203438, 0, true, auth.uid(), r.id::text
        from public.reports r
       where r.id = new.report_id
         and r.user_id is not null
         -- An anonymous report has no one to tell. is_anonymous is respected
         -- here for the same reason 20260722000000 respected it everywhere.
         and r.is_anonymous = false;
    exception when others then null;
    end;
  end if;

  -- The staff author, when their submission is decided. Agency-authored rows
  -- have no account to notify (author_id is null) — the scan page shows them
  -- the decision instead.
  if new.author_id is not null and new.author_id is distinct from auth.uid() then
    begin
      insert into public.notifications
        (user_id, topic, title, subtitle, type, color_value, icon_code,
         is_approved, sent_by, reference_id)
      values (
        new.author_id, 'report_update',
        case when new.status = 'approved'
             then 'Your progress update was approved'
             else 'Your progress update was returned' end,
        case when new.status = 'approved'
             then left(new.body, 120)
             else coalesce(nullif(btrim(new.rejected_reason), ''), '')
        end,
        'report_update',
        case when new.status = 'approved' then 4281257073 else 4293348412 end,
        0, true, auth.uid(), new.report_id::text
      );
    exception when others then null;
    end;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_notify_report_update_decision on public.report_updates;
create trigger trg_notify_report_update_decision
  after update of status on public.report_updates
  for each row execute function public.notify_report_update_decision();

-- ── 10. Storage ────────────────────────────────────────────────────────────
-- Update photos reuse the EXISTING public `resolution-media` bucket rather
-- than minting a new one. Same content (photographs of public infrastructure,
-- before and after), same write gate (role 1 or 2), same public-read flag that
-- lets the citizen load them without signed-URL fragility. A second bucket
-- would be a second set of policies to keep in step for no difference in kind.
--
-- Paths are namespaced `updates/<update_id>/<file>` so an object can be traced
-- back to the update that owns it, and so the two uses never collide.
--
-- NOTE the write policy is unchanged from report_resolution_media.sql and is
-- NOT re-created here: it already admits role 1 and 2 for the whole bucket. The
-- agency has no account and therefore cannot upload — an agency update is text
-- only, which is the honest consequence of them holding no credential beyond a
-- PIN. Their photos reach the LGU the way the letter did.

-- ── 11. Close the unreviewed-completion-photo hole ─────────────────────────
-- report_resolution_media's SELECT policy grants owns_report() with NO status
-- condition, so a completion photo reaches the citizen the instant it is
-- uploaded — no admin ever sees it. That is the one path left that publishes to
-- a citizen without review, and it is the highest-consequence one: a wrong or
-- embarrassing photo on someone's report.
--
-- The fix keeps the table exactly as it is for admin and staff (who need to
-- see what they uploaded) and narrows only the CITIZEN's read: they see
-- completion media once the report is resolved AND an approved completion
-- update exists to accompany it. In other words the photo rides the same
-- approval the words do.
--
-- Reports resolved BEFORE this migration have no completion update, so their
-- photos would vanish from the citizen's view. The `resolved_at is null or
-- resolved before now()` grandfather clause below keeps existing history
-- visible — this tightens what happens NEXT, it does not retract what citizens
-- have already been shown.
drop policy if exists rrm_select on public.report_resolution_media;
create policy rrm_select
  on public.report_resolution_media for select
  to authenticated
  using (
       public.is_admin()
    or public.staff_can_see_report(report_id)
    or (
         public.owns_report(report_id)
         and (
              -- grandfathered: uploaded before the approval loop existed
              created_at < '2026-08-29T00:00:00Z'::timestamptz
              -- or accompanied by an approved completion update
              or exists (
                   select 1 from public.report_updates u
                    where u.report_id = report_resolution_media.report_id
                      and u.kind = 'completion'
                      and u.status = 'approved'
                 )
            )
       )
  );

commit;

-- Expected after this migration:
--   * report_updates / report_update_media exist with RLS enabled.
--   * A citizen reads ONLY status='approved' rows on a report they own.
--   * Staff can insert only their own rows, only as 'pending_approval'.
--   * An admin's own update is 'approved' on insert.
--   * review_report_update refuses a rejection with no reason.
--   * anon holds EXECUTE on post_endorsement_update and no table privilege.
