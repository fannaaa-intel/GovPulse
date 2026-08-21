-- ============================================================
-- ENGAGEMENT NOTIFICATIONS — one event, one bell row per person
--
-- SCREENSHOTTED 2026-08-21, admin console bell, both rows one second apart:
--   "New like on a community post" — "Mark Reduca liked a community post."
--   "New like ❤️"                  — "Mark Reduca liked your post"
--
-- Same like, same recipient, twice. Confirmed live:
--   user_id 702be3ba…  actor 76159d2c…  type post_like  2026-08-20 03:12:34
--
-- WHY IT HAPPENS
-- 20260720000001 §8 documents the design: every community engagement table
-- carries TWO triggers. `trg_notify_*_citizen` tells the post/comment AUTHOR;
-- `trg_notify_*` tells the ADMIN CONSOLE. That comment ends "they are not
-- duplicates of each other" — and for a citizen author they are not. But
-- notify_admins() fans out to every row of admin_details minus the actor, and
-- it has never known who the author was. So when the author IS an admin, the
-- two audiences are the same person and the pair collapses into a duplicate.
--
-- This is not the "second undocumented pipeline" duplicate that
-- legacy/fix_duplicate_push.sql killed. Both triggers here are wanted; only
-- their overlap is not.
--
-- THE FIX
-- notify_admins() learns to skip recipients, and the three engagement triggers
-- tell it to skip the person who already got the personal ping. The personal
-- ping is the one that survives: it carries the actor's photo, the deep-link
-- post_id, and reads as it should ("liked YOUR post").
--
-- WHAT IS DELIBERATELY LEFT ALONE
--   • reports / suggestions / feedbacks / verification_submissions — their
--     notify_admins() callers have no author-directed sibling on the same row.
--   • notify_staff_report_assigned / _endorsed / notify_report_note — they fan
--     out over admin_profiles ⋈ user_roles, and user_roles is UNIQUE(user_id)
--     with admin_profiles keyed on user_id, so neither join can multiply.
--   • community_posts — notify_admins_community_request fires on INSERT,
--     notify_author_post_decision on UPDATE OF status. Different events.
--
-- Additive + idempotent. Run in the Supabase SQL editor (db push is blocked on
-- Docker; see supabase/README.md).
-- ============================================================

-- ── §1  notify_admins(): accept a skip-list ──────────────────────────────────
-- `p_exclude` is appended LAST with a default, so all seven existing call sites
-- keep compiling and simply pass null.
--
-- ⚠ THE DROP IS LOAD-BEARING, NOT TIDINESS — the same trap
-- legacy/notification_deeplink_targets_2.sql §6 documents when it added
-- p_reference_id. Postgres keys functions by signature, so `create or replace`
-- with an extra parameter creates an OVERLOAD alongside the 7-arg version, not
-- a replacement. Both would then serve a 3-arg call through their defaults and
-- every caller would fail with "function notify_admins(text, text, text) is not
-- unique" — swallowed by each caller's exception handler, so admin
-- notifications would silently STOP with nothing in the logs. Dropping first
-- leaves exactly one function to resolve to.
--
-- ⚠ A DROP ALSO DISCARDS THE ACL. The recreated function comes back with the
-- Postgres default of EXECUTE TO PUBLIC, which would undo 20260722000007's
-- revoke. §1b puts the live grants back verbatim (postgres / authenticated /
-- service_role, no public, no anon).
drop function if exists public.notify_admins(text, text, text, text, bigint, uuid, text);

create or replace function public.notify_admins(
  p_topic text,
  p_title text,
  p_subtitle text,
  p_type text default 'general'::text,
  p_color bigint default '4280640491'::bigint,
  p_actor uuid default null::uuid,
  p_reference_id text default null::text,
  p_exclude uuid[] default null::uuid[]
)
returns void
language plpgsql security definer set search_path = public
as $function$
DECLARE
  v_actor_photo text;
BEGIN
  IF p_actor IS NOT NULL THEN
    SELECT coalesce(
      ap.photo_url,
      case
        when cd.profile_photo_path is not null and cd.profile_photo_path <> ''
        then 'https://vxvflhjbafqwehuxnmeq.supabase.co/storage/v1/object/public/profile-photos/' || cd.profile_photo_path
        else null
      end
    ) INTO v_actor_photo
    FROM auth.users u
    LEFT JOIN public.admin_profiles  ap ON ap.user_id = u.id
    LEFT JOIN public.citizen_details cd ON cd.user_id = u.id
    WHERE u.id = p_actor;
  END IF;

  insert into public.notifications
    (user_id, icon_code, title, subtitle, color_value, type, topic,
     is_approved, sent_by, actor_id, actor_photo_url, reference_id)
  select distinct
    ad.user_id, 0, p_title, coalesce(p_subtitle, ''), p_color, p_type, p_topic,
    true, p_actor, p_actor, v_actor_photo, p_reference_id
  from public.admin_details ad
  where (p_actor is null or ad.user_id <> p_actor)
    -- Someone already told this admin about this event in a better way.
    -- `<> all` over a NULL array yields NULL, not true, so the null default has
    -- to be handled outside the comparison or the fan-out reaches nobody.
    and (p_exclude is null or ad.user_id <> all (p_exclude));
end;
$function$;

-- ── §1b  Restore the ACL the drop discarded ──────────────────────────────────
-- Verbatim from the live proacl read immediately before this migration:
--   postgres=X/postgres | authenticated=X/postgres | service_role=X/postgres
-- The revoke is what 20260722000007 established: every trigger that calls this
-- is SECURITY DEFINER, so an anon-context write reaches it through the
-- definer's rights and never needs a direct grant of its own.
revoke execute on function public.notify_admins(text, text, text, text, bigint, uuid, text, uuid[]) from public, anon;
grant  execute on function public.notify_admins(text, text, text, text, bigint, uuid, text, uuid[]) to authenticated, service_role;

-- ── §2  Post like → admins, minus the post's own author ──────────────────────
-- Verbatim from 20260720000001 §8 — topic, title, subtitle, type, colour, the
-- is_admin early-return and the handler — plus the author lookup and the skip.
--
-- The lookup is deliberately NOT guarded by is_admin(): passing a citizen
-- author's uuid to p_exclude costs one comparison against a table that does not
-- contain them. Cheaper than a second is_admin() round-trip, and it stays
-- correct if that citizen is ever promoted.
create or replace function public.tg_notify_post_like()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_actor_name text;
  v_author     uuid;
begin
  if public.is_admin(new.user_id) then
    return new;
  end if;

  begin
    v_actor_name := coalesce(public.actor_display_name(new.user_id), 'A citizen');

    -- notify_on_post_like() already sent this person "X liked your post".
    select author_id into v_author
    from public.community_posts where id = new.post_id;

    perform public.notify_admins(
      'post_heart',
      'New like on a community post',
      v_actor_name || ' liked a community post.',
      'post_like',
      4293675161,
      new.user_id,
      null,
      case when v_author is null then null else array[v_author] end
    );
  exception when others then
    raise warning 'tg_notify_post_like skipped: % (%)', sqlerrm, sqlstate;
  end;
  return new;
end;
$function$;

-- ── §3  Comment like → admins, minus the comment's own author ────────────────
-- As §2.
create or replace function public.tg_notify_comment_like()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_actor_name text;
  v_author     uuid;
begin
  if public.is_admin(new.user_id) then
    return new;
  end if;

  begin
    v_actor_name := coalesce(public.actor_display_name(new.user_id), 'A citizen');

    -- notify_on_comment_like() already sent this person "X liked your comment".
    select author_id into v_author
    from public.community_comments where id = new.comment_id;

    perform public.notify_admins(
      'comment_heart',
      'New like on a comment',
      v_actor_name || ' liked a comment.',
      'post_like',
      4293675161,
      new.user_id,
      null,
      case when v_author is null then null else array[v_author] end
    );
  exception when others then
    raise warning 'tg_notify_comment_like skipped: % (%)', sqlerrm, sqlstate;
  end;
  return new;
end;
$function$;

-- ── §4  Comment / reply → admins, minus whoever was replied to ───────────────
-- Verbatim from 20260720000001 §2 plus the skip. This pair was the worst of the
-- three: both rows are titled exactly "New comment" (or exactly "New reply"),
-- so an admin whose post was commented on saw the same headline twice with
-- nothing in the title to tell the rows apart.
--
-- ⚠ THE RECIPIENT IS NOT ALWAYS THE POST AUTHOR. notify_on_comment() sends a
-- top-level comment to the post's author but a REPLY to
-- coalesce(mentioned_user_id, parent comment author). Excluding the post author
-- for replies would be wrong in both directions at once — it would drop a
-- console ping the post author should still get, and leave the duplicate on the
-- person actually replied to. The branch below mirrors notify_on_comment()
-- exactly; change one, change the other.
create or replace function public.tg_notify_comment()
returns trigger
language plpgsql security definer set search_path = public
as $function$
declare
  preview      text;
  v_actor_name text;
  v_recipient  uuid;
begin
  if public.is_admin(new.author_id) then
    return new;
  end if;

  begin
    v_actor_name := public.actor_display_name(new.author_id);

    preview := left(coalesce(new.body, ''), 80);

    -- Mirror of notify_on_comment()'s recipient resolution.
    if new.parent_comment_id is null then
      select author_id into v_recipient
      from public.community_posts where id = new.post_id;
    else
      select coalesce(new.mentioned_user_id, c.author_id) into v_recipient
      from public.community_comments c where c.id = new.parent_comment_id;
    end if;

    -- notify_on_comment() returns without inserting when the recipient is the
    -- commenter themselves, so in that case there is nothing to skip.
    if v_recipient = new.author_id then
      v_recipient := null;
    end if;

    perform public.notify_admins(
      'comment',
      case when new.parent_comment_id is null
           then 'New comment' else 'New reply' end,
      coalesce(v_actor_name, 'Someone')
        || case when new.parent_comment_id is null
                then ' posted a comment: "' else ' posted a reply: "' end
        || coalesce(nullif(preview, ''), '') || '"',
      'post_comment',
      4280640491,
      new.author_id,
      new.post_id::text,
      case when v_recipient is null then null else array[v_recipient] end
    );
  exception when others then
    raise warning 'tg_notify_comment skipped: % (%)', sqlerrm, sqlstate;
  end;

  return new;
end;
$function$;

-- ── §5  Clear the duplicates already in the bell ─────────────────────────────
-- §1–§4 stop new ones; the rows written before today are still there. Deletes
-- only the ADMIN-CONSOLE half of a pair, and only where the personal half is
-- present for the same recipient, the same actor and the same event.
--
-- The two halves are told apart by `topic`: notify_admins() always writes one,
-- the notify_on_* triggers never do. The 10-second window is generous — both
-- rows come from triggers on a single INSERT, so in practice they share a
-- transaction, but clock skew on the created_at default is not worth betting an
-- off-by-one on.
--
-- Idempotent by construction: once the console half is gone there is no `a` row
-- left to match, so a second run deletes nothing.
delete from public.notifications a
where a.topic in ('post_heart', 'comment_heart', 'comment')
  and exists (
    select 1
    from public.notifications b
    where b.user_id  = a.user_id
      and b.actor_id = a.actor_id
      and b.actor_id is not null
      and b.topic is null              -- the personal half, never the console's
      and b.id <> a.id
      and b.created_at between a.created_at - interval '10 seconds'
                           and a.created_at + interval '10 seconds'
      -- Console topic → the citizen-side type(s) it duplicates.
      and b.type = any (
            case a.topic
              when 'post_heart'    then array['post_like']
              when 'comment_heart' then array['comment_like']
              when 'comment'       then array['post_comment', 'comment_reply']
            end
          )
  );

-- ── §6  Verify ───────────────────────────────────────────────────────────────
-- Run on its own — the SQL editor shows only the last result set in a tab
-- (supabase/README.md). Expect zero rows. Anything returned is a recipient
-- still getting one event twice; check whether a NEW trigger pair was added.
--
--   select n.user_id, n.actor_id, n.type, count(*),
--          array_agg(n.title || ' [' || coalesce(n.topic, '-') || ']')
--     from public.notifications n
--    where n.created_at > now() - interval '90 days'
--    group by n.user_id, n.actor_id, n.type, date_trunc('second', n.created_at)
--   having count(*) > 1;
