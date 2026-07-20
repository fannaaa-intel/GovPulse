-- ============================================================
-- COMMENT NOTIFICATION ACTOR NAME — stop calling staff "a citizen"
-- Run this in the Supabase SQL editor (db push is blocked on Docker; see
-- supabase/README.md). Additive + idempotent — safe to run standalone.
--
-- Problem it fixes: when a STAFF member comments on a community post, the admin
-- bell reads "A citizen posted a comment: ..." — attributing LGU staff activity
-- to the public. Wrong on its face, and actively misleading in a moderation
-- queue, where "a citizen said this" is the cue to go review it.
--
-- Cause: tg_notify_comment (notification_deeplink_targets_3.sql §4) resolves the
-- author's name from admin_details / staff_details / citizen_details, each as
-- `first_name || ' ' || last_name`. But staff and admin names do not live in
-- those columns — they live in `admin_profiles.full_name`, a single column
-- (see StaffRepository.fetchIdentity, which reads exactly that). So for a staff
-- author every branch is null and the coalesce falls through to its literal
-- last resort, 'A citizen'. The string was never role-aware; it was the
-- fallback for "no name found", and staff always hit it.
--
-- Two changes, both confined to naming — the trigger is otherwise reproduced
-- verbatim from targets_3 §4 (topic, colour, actor, reference_id, and the
-- is_admin early-return are all unchanged):
--
--   1. admin_profiles.full_name is consulted FIRST, so officials are named.
--   2. The last-resort string is role-aware: an unnamed staff author is now
--      "A staff member", not "A citizen". A missing name should degrade to a
--      vaguer label, never to a WRONG one.
--
-- Also fixes the body text for replies: the title already said "New reply" while
-- the subtitle still said "posted a comment".
--
-- Only affects notifications written from here on; rows already in the table
-- keep the text they were created with.
-- ============================================================

create or replace function public.tg_notify_comment()
returns trigger
language plpgsql security definer set search_path = public
as $function$
declare
  preview      text;
  v_actor_name text;
  v_role_id    int;
begin
  if public.is_admin(new.author_id) then
    return new;
  end if;

  -- Scalar lookup rather than a join: user_roles is not guaranteed to hold a
  -- single row per user, and a second row would multiply the select below.
  select ur.role_id
    into v_role_id
    from public.user_roles ur
   where ur.user_id = new.author_id
   order by ur.role_id
   limit 1;

  select coalesce(
    -- Officials (admin + staff) keep their name here, as one column.
    nullif(trim(ap.full_name), ''),
    nullif(trim(ad.first_name || ' ' || ad.last_name), ''),
    nullif(trim(sd.first_name || ' ' || sd.last_name), ''),
    nullif(trim(cd.first_name || ' ' || cd.last_name), ''),
    -- No name on file: say what they ARE, don't guess that they're the public.
    case v_role_id
      when 1 then 'An administrator'
      when 2 then 'A staff member'
      else 'A citizen'
    end
  ) into v_actor_name
  from auth.users u
  left join public.admin_profiles  ap on ap.user_id = u.id
  left join public.admin_details   ad on ad.user_id = u.id
  left join public.staff_details   sd on sd.user_id = u.id
  left join public.citizen_details cd on cd.user_id = u.id
  where u.id = new.author_id;

  preview := left(coalesce(new.body, ''), 80);

  perform public.notify_admins(
    'comment',
    case when new.parent_comment_id is null
         then 'New comment' else 'New reply' end,
    v_actor_name
      || case when new.parent_comment_id is null
              then ' posted a comment: "' else ' posted a reply: "' end
      || coalesce(nullif(preview, ''), '') || '"',
    'post_comment',
    4280640491,
    new.author_id,
    new.post_id::text
  );
  return new;
end;
$function$;

-- ── Verify ───────────────────────────────────────────────────────────────────
-- Comment as a staff user, then confirm the subtitle names them:
--   select title, subtitle, created_at from public.notifications
--    where type = 'post_comment' order by created_at desc limit 5;
--
-- NOTE — same fallback string, same wrong assumption, elsewhere. If any other
-- notify trigger reports "A citizen ...", it needs this treatment too. Find
-- them with:
--   select p.proname from pg_proc p
--     join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'public'
--      and pg_get_functiondef(p.oid) ilike '%A citizen%';
