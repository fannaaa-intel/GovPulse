-- ============================================================
-- COMMUNITY POST REVIEW LOOP — staff identity on the feed + both-way pings
-- Run this in the Supabase SQL editor AFTER 20260719000001. Additive +
-- idempotent — safe to run standalone.
--
-- Three problems it fixes:
--
-- 1. IDENTITY — a staff-authored post renders "Unknown" on the citizen feed.
--    The live `community_feed` view resolves author name/role from citizen
--    tables (public_user_profiles), where officials have no row. Staff
--    identity lives in `admin_profiles`, which citizens cannot read (owner-only
--    + admin-only SELECT). Fix: `official_public_profiles`, an owner-rights
--    view exposing ONLY the public-facing fields of officials (name, photo,
--    department, role) to everyone — the same fields the app already shows for
--    the signed-in official. The Dart feed resolves official authors through
--    it, so a staff post shows the staff member's name + photo + office.
--
-- 2. ADMIN PING — nothing tells admins a staff submission is waiting.
--    New AFTER INSERT trigger: a pending_approval post pings every admin
--    (bell + push via the existing notifications pipeline), deep-linking to
--    the Community review queue (topic 'community_request', reference_id =
--    post id).
--
-- 3. STAFF PING — post_approved / post_rejected notifications have NEVER been
--    created by anything (verified 2026-07-15: no Dart, no SQL, no trigger
--    writes them), yet the staff console already has icons, topic routing and
--    a mute setting for them. New AFTER UPDATE trigger fires them when an
--    admin decides, deep-linking the staff author to their submission.
--
-- All notification writes are wrapped in EXCEPTION handlers — a broken ping
-- must never block a post insert or an approval.
-- ============================================================

-- ── 1. Public directory of officials (admins + staff) ────────────────────────
-- A SECURITY DEFINER *function* (not a view): it bypasses admin_profiles RLS
-- deliberately, but exposes ONLY public-facing fields, and only for the ids the
-- caller explicitly asks about — there is no way to browse the whole directory.
-- (An earlier draft used an owner-rights VIEW; Supabase's linter rightly flags
-- security-definer views as CRITICAL, and a function is tighter anyway — the
-- drop below cleans it up if that draft was ever applied.)
drop view if exists public.official_public_profiles;

create or replace function public.official_public_profiles(p_user_ids uuid[])
returns table (
  user_id uuid,
  full_name text,
  photo_url text,
  department text,
  role_id int
)
language sql stable security definer set search_path = public
as $$
  select ap.user_id, ap.full_name, ap.photo_url, ap.department, ur.role_id
  from public.admin_profiles ap
  join public.user_roles ur on ur.user_id = ap.user_id
  where ur.role_id in (1, 2)
    and ap.user_id = any(p_user_ids);
$$;

grant execute on function public.official_public_profiles(uuid[])
  to anon, authenticated;

-- ── 2. Ping admins when a staff submission lands in the review queue ─────────
create or replace function public.notify_admins_community_request()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_name text;
begin
  if new.status <> 'pending_approval' then return new; end if;
  begin
    select nullif(trim(full_name), '') into v_name
    from public.admin_profiles where user_id = new.author_id;
    perform public.notify_admins(
      'community_request',
      'Community post awaiting review',
      coalesce(v_name, 'A staff member') || ' submitted "'
        || coalesce(nullif(trim(new.title), ''), 'untitled') || '"',
      'community_request',
      4280640491,
      new.author_id,
      new.id::text
    );
  exception when others then null;
  end;
  return new;
end;
$$;

drop trigger if exists trg_notify_admins_community_request on public.community_posts;
create trigger trg_notify_admins_community_request
  after insert on public.community_posts
  for each row execute function public.notify_admins_community_request();

-- ── 3. Ping the author when their post is approved / rejected ────────────────
-- Fires on any status change INTO approved/rejected (covers "Approve anyway"
-- on a rejected post too). Skips self-decisions (an admin publishing their own
-- post approves it in the same breath — no self-ping).
create or replace function public.notify_author_post_decision()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.status = old.status then return new; end if;
  if new.status not in ('approved', 'rejected') then return new; end if;
  if old.status not in ('pending_approval', 'rejected') then return new; end if;
  if new.author_id = auth.uid() then return new; end if;
  begin
    insert into public.notifications
      (user_id, icon_code, title, subtitle, color_value, type, topic,
       is_approved, sent_by, reference_id)
    values (
      new.author_id,
      0,
      case when new.status = 'approved'
           then 'Your community post was approved'
           else 'Your community post was rejected' end,
      case when new.status = 'approved'
           then '"' || coalesce(nullif(trim(new.title), ''), 'untitled')
                || '" is now live on the citizen feed.'
           else '"' || coalesce(nullif(trim(new.title), ''), 'untitled') || '"'
                || coalesce(' — ' || nullif(trim(new.rejected_reason), ''), '')
      end,
      case when new.status = 'approved' then 4281257073 else 4293348412 end,
      case when new.status = 'approved' then 'post_approved' else 'post_rejected' end,
      case when new.status = 'approved' then 'post_approved' else 'post_rejected' end,
      true,
      auth.uid(),
      new.id::text
    );
  exception when others then null;
  end;
  return new;
end;
$$;

drop trigger if exists trg_notify_author_post_decision on public.community_posts;
create trigger trg_notify_author_post_decision
  after update of status on public.community_posts
  for each row execute function public.notify_author_post_decision();

-- ── 4. community_post_images: admins + authors can read rows ─────────────────
-- The admin review queue and the staff "My submissions" list both render photo
-- thumbnails by reading this table directly (the citizen feed goes through the
-- community_feed view instead and is unaffected).
drop policy if exists post_images_read_admin_or_own on public.community_post_images;
create policy post_images_read_admin_or_own on public.community_post_images
  for select to authenticated
  using (
    public.is_admin()
    or exists (
      select 1 from public.community_posts p
      where p.id = post_id and p.author_id = auth.uid()
    )
  );

-- ── 5. Ping the author when an admin deletes their post ──────────────────────
-- The admin console HARD-deletes posts (row + images), so the submission simply
-- disappears from the staff "My submissions" list — this trigger is what tells
-- the author why. Topic 'community' (staff console already routes + icons it);
-- no reference_id on purpose: the row is gone, there is nothing to deep-link
-- to, so the tap just opens their Community section. Skips self-deletes.
create or replace function public.notify_author_post_deleted()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if old.author_id = auth.uid() then return old; end if;
  begin
    insert into public.notifications
      (user_id, icon_code, title, subtitle, color_value, type, topic,
       is_approved, sent_by)
    values (
      old.author_id,
      0,
      case when old.status = 'approved'
           then 'Your community post was taken down'
           else 'Your community post was removed' end,
      '"' || coalesce(nullif(trim(old.title), ''), 'untitled')
        || '" was removed by an LGU admin.',
      4293348412,
      'post_deleted',
      'community',
      true,
      auth.uid()
    );
  exception when others then null;
  end;
  return old;
end;
$$;

drop trigger if exists trg_notify_author_post_deleted on public.community_posts;
create trigger trg_notify_author_post_deleted
  after delete on public.community_posts
  for each row execute function public.notify_author_post_deleted();

-- ── Verify ───────────────────────────────────────────────────────────────────
-- select * from public.official_public_profiles(array(select user_id from public.admin_profiles));
-- select tgname from pg_trigger where tgrelid = 'public.community_posts'::regclass
--   and tgname like 'trg_notify%';
