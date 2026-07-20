-- ============================================================
-- OFFICIAL ACTOR NAMING — an LGU account is named by its OFFICE, not its person
-- Run this in the Supabase SQL editor (db push is blocked on Docker; see
-- supabase/README.md). Additive + idempotent — safe to run standalone.
--
-- THE RULE
-- An official does not act as themselves. An admin speaks for the LGU; a staff
-- member speaks for their DEPARTMENT. So every notification an official causes
-- must read institutionally — "LGU Aparri", "Sanitation Office" — never
-- "System Admin" or "Rheinz". A citizen, who genuinely acts for themselves,
-- keeps their own name.
--
-- WHAT WAS WRONG (all three consoles, screenshotted 2026-07-20)
--   citizen bell: "System Admin replied to you: …"      → should be LGU Aparri
--   staff bell:   "System Admin replied to you: …"      → should be LGU Aparri
--   admin bell:   "Rheinz posted a reply: …"            → should be his office
--
-- 20260719000008 fixed the *previous* version of this bug, where staff fell
-- through every name lookup and came out as "A citizen". It fixed it by
-- consulting admin_profiles.full_name first — which named them correctly as
-- PEOPLE. That was the wrong axis: the name was never supposed to be personal.
-- This migration replaces that lookup with the institutional one.
--
-- The Dart mirror of this rule is lib/core/identity/official_display_name.dart.
-- Change one, change the other, or the feed and the bell will disagree about
-- who said something.
--
-- ⚠ §5–§7 CAPTURE THREE TRIGGERS THAT WERE NEVER IN THIS REPO
-- `notify_on_comment` (the "X replied to you" ping behind the screenshots) and
-- its like siblings `notify_on_post_like` / `notify_on_comment_like` were all
-- created straight against the project (see
-- supabase/diagnostics/diagnose_community_engagement_triggers.sql). Their
-- bodies were dumped from the live database on 2026-07-20 and are reproduced
-- here so the repo finally owns them. If you have changed any of the three in
-- the SQL editor since, re-dump before running, or you overwrite the newer
-- version.
--
-- All three shared a second defect worth naming: NO exception handler. A schema
-- drift in any of their lookups or inserts would roll back the comment or the
-- like itself — the thing the user watched succeed. 20260719000009 established
-- that a notification is strictly secondary to the write it announces; these
-- three were the remaining violations. Each now warns instead.
-- ============================================================

-- ── §1  The rule, as one function ────────────────────────────────────────────
-- STABLE so the planner can call it once per row; SECURITY DEFINER because
-- admin_profiles is not readable by the citizen whose notification is being
-- composed. Returns only a display name — no contact details, no ids.
--
-- Fallbacks degrade to something VAGUER, never to something WRONG: a staff
-- account with no department on file is still the LGU, and an unnamed citizen
-- is still "A citizen".
create or replace function public.actor_display_name(p_user_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $function$
  select case
    -- Admin: the LGU brand, always. Their personal name is never public.
    when ur.role_id = 1 then 'LGU Aparri'
    -- Staff: their office. No department on file → fall back to the brand
    -- rather than to their name.
    when ur.role_id = 2 then
      coalesce(nullif(trim(ap.department), ''), 'LGU Aparri')
    -- Citizen: themselves.
    else coalesce(
      nullif(trim(cd.first_name || ' ' || cd.last_name), ''),
      'A citizen'
    )
  end
  from auth.users u
  -- Scalar-safe: user_roles is not guaranteed unique per user, and a second
  -- row would multiply this select. Lowest role_id wins (most privileged).
  left join lateral (
    select role_id from public.user_roles
     where user_id = u.id order by role_id limit 1
  ) ur on true
  left join public.admin_profiles  ap on ap.user_id = u.id
  left join public.citizen_details cd on cd.user_id = u.id
  where u.id = p_user_id;
$function$;

grant execute on function public.actor_display_name(uuid) to authenticated;

-- ── §2  Comment / reply → admins ─────────────────────────────────────────────
-- Reproduced verbatim from 20260719000009 §2 — same topic, colour, actor,
-- reference_id, is_admin early-return and error handler — with ONLY the name
-- resolution swapped for §1. The handler stays: a notification must never cost
-- the comment that caused it.
create or replace function public.tg_notify_comment()
returns trigger
language plpgsql security definer set search_path = public
as $function$
declare
  preview      text;
  v_actor_name text;
begin
  if public.is_admin(new.author_id) then
    return new;
  end if;

  begin
    v_actor_name := public.actor_display_name(new.author_id);

    preview := left(coalesce(new.body, ''), 80);

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
      new.post_id::text
    );
  exception when others then
    raise warning 'tg_notify_comment skipped: % (%)', sqlerrm, sqlstate;
  end;

  return new;
end;
$function$;

-- ── §3  Staff submission → the admin review queue ────────────────────────────
-- From 20260719000002 §2, which read admin_profiles.full_name directly and so
-- announced "Rheinz submitted …". The queue's question is which OFFICE wants
-- something published; the console still carries authorId and the author photo
-- when an admin needs the individual behind it.
create or replace function public.notify_admins_community_request()
returns trigger
language plpgsql security definer set search_path = public
as $function$
begin
  if new.status <> 'pending_approval' then return new; end if;
  begin
    perform public.notify_admins(
      'community_request',
      'Community post awaiting review',
      coalesce(public.actor_display_name(new.author_id), 'A staff member')
        || ' submitted "'
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
$function$;

-- ── §4  Note on a report → the other side (admin ⇄ staff) ────────────────────
-- From notification_deeplink_targets_2.sql §5. Only the STAFF branch changes:
-- "Staff note on <report>" becomes "<Department> note on <report>", so an admin
-- reading the queue knows which office weighed in. The ADMIN branch already
-- said "Admin note" — a role, not a person — and is left alone; "LGU Aparri
-- note on …" would be strictly worse English for an internal channel where
-- both sides are the LGU.
create or replace function public.notify_report_note()
returns trigger
language plpgsql security definer set search_path = public
as $function$
declare
  v_assigned text;
  v_endorsed text;
  v_category text;
  v_other    text;
  v_label    text;
  v_author   text;
  v_short    text := upper(substring(new.report_id::text from 1 for 8));
begin
  select assigned_to_department, endorsed_to_department, category, category_other
    into v_assigned, v_endorsed, v_category, v_other
    from public.reports where id = new.report_id;
  v_label := public.report_label(v_category, v_other);

  if new.author_role = 'admin' then
    begin
      insert into public.notifications
        (user_id, topic, title, subtitle, type, color_value, icon_code,
         is_approved, sent_by, reference_id)
      select ap.user_id, 'report',
             'Admin note on ' || v_label || ' (RPT-' || v_short || ')',
             left(coalesce(new.body, ''), 120),
             'report_note', 4279203438, 0, true, auth.uid(),
             new.report_id::text
      from public.admin_profiles ap
      join public.user_roles ur
        on ur.user_id = ap.user_id and ur.role_id = 2
      where ap.department = coalesce(v_assigned, v_endorsed)
        and ap.user_id <> new.author_id;
    exception when others then null;
    end;
  elsif new.author_role = 'staff' then
    begin
      -- The note's OFFICE. Falls back to the old wording, never to a name.
      select nullif(trim(ap.department), '')
        into v_author
        from public.admin_profiles ap
       where ap.user_id = new.author_id;

      insert into public.notifications
        (user_id, topic, title, subtitle, type, color_value, icon_code,
         is_approved, sent_by, reference_id)
      select ur.user_id, 'report',
             coalesce(v_author, 'Staff') || ' note on ' || v_label
               || ' (RPT-' || v_short || ')',
             left(coalesce(new.body, ''), 120),
             'report_note', 4279203438, 0, true, auth.uid(),
             new.report_id::text
      from public.user_roles ur
      where ur.role_id = 1
        and ur.user_id <> new.author_id;
    exception when others then null;
    end;
  end if;
  return new;
end;
$function$;

-- ── §5  Comment / reply → the POST or PARENT-COMMENT author ──────────────────
-- This is the one the citizen and staff bells read, and the last place a
-- person's name leaked. Dumped verbatim from the live database 2026-07-20;
-- recipient resolution, the community_notifications row, both column lists,
-- icon/colour/type, the actor photo (including its hardcoded storage URL) and
-- `left(new.body, 60)` are all exactly as they were. THREE changes:
--
--   1. The name. It resolved admin_details / staff_details / citizen_details —
--      so an admin came out "System Admin" (admin_details HAS that row) and a
--      staff member came out "Someone" (staff_details has none; their identity
--      lives in admin_profiles, as 20260719000008 found the hard way). Both
--      wrong in the same direction: personal, or nothing. Now §1.
--
--   2. An exception handler, per the rule 20260719000009 set: a notification is
--      strictly secondary to the write it announces. This function had none —
--      a schema drift in ANY of its five lookups or two inserts would roll back
--      the citizen's comment. That is data loss the user watched happen.
--
--   3. `left(new.body, 60)` on a NULL body yields NULL, which would blank the
--      whole subtitle through concatenation. coalesce'd, matching §2's preview.
--
-- ⚠ NOT changed: the actor PHOTO still comes from admin_profiles.photo_url for
-- officials. The rule here is about names; an office's avatar is already the
-- account's own photo, and the consoles key their icon-only topics off it.
create or replace function public.notify_on_comment()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_post_author   uuid;
  v_parent_author uuid;
  v_actor_name    text;
  v_actor_photo   text;
  v_recipient     uuid;
  v_kind          text;
begin
  if new.parent_comment_id is null then
    select author_id into v_post_author from public.community_posts where id = new.post_id;
    v_recipient := v_post_author;
    v_kind      := 'post_comment';
  else
    select author_id into v_parent_author from public.community_comments where id = new.parent_comment_id;
    v_recipient := coalesce(new.mentioned_user_id, v_parent_author);
    v_kind      := 'comment_reply';
  end if;
  if v_recipient is null or v_recipient = new.author_id then return new; end if;

  begin
    -- Officials by office, citizens by name. See §1.
    v_actor_name := coalesce(public.actor_display_name(new.author_id), 'Someone');

    select coalesce(
      ap.photo_url,
      case when cd.profile_photo_path is not null and cd.profile_photo_path <> ''
        then 'https://vxvflhjbafqwehuxnmeq.supabase.co/storage/v1/object/public/profile-photos/' || cd.profile_photo_path
        else null end
    ) into v_actor_photo
    from auth.users u
    left join public.admin_profiles  ap on ap.user_id = u.id
    left join public.citizen_details cd on cd.user_id = u.id
    where u.id = new.author_id;

    insert into public.community_notifications(recipient_id, actor_id, type, post_id, comment_id)
    values (v_recipient, new.author_id, v_kind, new.post_id, new.id);

    insert into public.notifications(user_id, icon_code, title, subtitle, color_value, type, is_approved, created_at, actor_id, actor_photo_url, post_id)
    values (
      v_recipient, 58826,
      case when v_kind = 'comment_reply' then 'New reply' else 'New comment' end,
      case when v_kind = 'comment_reply'
        then v_actor_name || ' replied to you: "' || coalesce(left(new.body, 60), '') || '"'
        else v_actor_name || ' commented on your post: "' || coalesce(left(new.body, 60), '') || '"'
      end,
      4280391411, v_kind, true, now(), new.author_id, v_actor_photo, new.post_id
    );
  exception when others then
    -- The comment itself must survive a failed notification.
    raise warning 'notify_on_comment skipped: % (%)', sqlerrm, sqlstate;
  end;

  return new;
end;
$function$;

-- ── §6  Post like → the post author ──────────────────────────────────────────
-- Sibling of §5, same origin (created against the project, never in this repo),
-- same two defects: the personal-name lookup, and no exception handler — so a
-- failed "New like ❤️" could roll back the LIKE. Dumped from the live database
-- 2026-07-20; recipient, self-like skip, both inserts, icon 59517, colour, the
-- actor photo and its hardcoded URL are all verbatim.
create or replace function public.notify_on_post_like()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_author      uuid;
  v_actor_name  text;
  v_actor_photo text;
begin
  select author_id into v_author from public.community_posts where id = new.post_id;
  if v_author is null or v_author = new.user_id then return new; end if;

  begin
    -- Officials by office, citizens by name. See §1.
    v_actor_name := coalesce(public.actor_display_name(new.user_id), 'Someone');

    select coalesce(
      ap.photo_url,
      case when cd.profile_photo_path is not null and cd.profile_photo_path <> ''
        then 'https://vxvflhjbafqwehuxnmeq.supabase.co/storage/v1/object/public/profile-photos/' || cd.profile_photo_path
        else null end
    ) into v_actor_photo
    from auth.users u
    left join public.admin_profiles  ap on ap.user_id = u.id
    left join public.citizen_details cd on cd.user_id = u.id
    where u.id = new.user_id;

    insert into public.community_notifications(recipient_id, actor_id, type, post_id)
    values (v_author, new.user_id, 'post_like', new.post_id);

    insert into public.notifications(user_id, icon_code, title, subtitle, color_value, type, is_approved, created_at, actor_id, actor_photo_url, post_id)
    values (v_author, 59517, 'New like ❤️', v_actor_name || ' liked your post', 4294198070, 'post_like', true, now(), new.user_id, v_actor_photo, new.post_id);
  exception when others then
    -- The like itself must survive a failed notification.
    raise warning 'notify_on_post_like skipped: % (%)', sqlerrm, sqlstate;
  end;

  return new;
end;
$function$;

-- ── §7  Comment like → the comment author ────────────────────────────────────
-- As §6. This one already coalesced its body preview, so the name and the
-- handler are the only changes.
create or replace function public.notify_on_comment_like()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_comment_author uuid;
  v_comment_body   text;
  v_post_id        uuid;
  v_actor_name     text;
  v_actor_photo    text;
begin
  select author_id, body, post_id into v_comment_author, v_comment_body, v_post_id
  from public.community_comments where id = new.comment_id;

  if v_comment_author is null or v_comment_author = new.user_id then return new; end if;

  begin
    -- Officials by office, citizens by name. See §1.
    v_actor_name := coalesce(public.actor_display_name(new.user_id), 'Someone');

    select coalesce(
      ap.photo_url,
      case when cd.profile_photo_path is not null and cd.profile_photo_path <> ''
        then 'https://vxvflhjbafqwehuxnmeq.supabase.co/storage/v1/object/public/profile-photos/' || cd.profile_photo_path
        else null end
    ) into v_actor_photo
    from auth.users u
    left join public.admin_profiles  ap on ap.user_id = u.id
    left join public.citizen_details cd on cd.user_id = u.id
    where u.id = new.user_id;

    insert into public.community_notifications(recipient_id, actor_id, type, comment_id)
    values (v_comment_author, new.user_id, 'comment_like', new.comment_id);

    insert into public.notifications(user_id, icon_code, title, subtitle, color_value, type, is_approved, created_at, actor_id, actor_photo_url, post_id)
    values (
      v_comment_author, 59517, 'New like ❤️',
      v_actor_name || ' liked your comment: "' || left(coalesce(v_comment_body, ''), 60) || '"',
      4294198070, 'comment_like', true, now(), new.user_id, v_actor_photo, v_post_id
    );
  exception when others then
    raise warning 'notify_on_comment_like skipped: % (%)', sqlerrm, sqlstate;
  end;

  return new;
end;
$function$;

-- ── §8  Post like → admins ───────────────────────────────────────────────────
-- The ENGAGEMENT TABLES CARRY TWO PINGS EACH, which is the thing to remember
-- here. `trg_notify_*_citizen` tells the post/comment author (§5–§7);
-- `trg_notify_*` tells the admin console (§2, §8, §9). Fixing one of a pair
-- leaves the other still naming people, and the two are named similarly enough
-- to look like duplicates of each other. They are not.
--
-- Dumped from the live database 2026-07-20 — topic, colour, type ('post_like'
-- for both, as it was), actor and the is_admin early-return are verbatim. Name
-- swapped for §1, and the unguarded `perform notify_admins(...)` — which could
-- roll back the LIKE — wrapped, matching every other trigger in this file.
create or replace function public.tg_notify_post_like()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_actor_name text;
begin
  if public.is_admin(new.user_id) then
    return new;
  end if;

  begin
    v_actor_name := coalesce(public.actor_display_name(new.user_id), 'A citizen');

    perform public.notify_admins(
      'post_heart',
      'New like on a community post',
      v_actor_name || ' liked a community post.',
      'post_like',
      4293675161,
      new.user_id
    );
  exception when others then
    raise warning 'tg_notify_post_like skipped: % (%)', sqlerrm, sqlstate;
  end;
  return new;
end;
$function$;

-- ── §9  Comment like → admins ────────────────────────────────────────────────
-- As §8.
create or replace function public.tg_notify_comment_like()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_actor_name text;
begin
  if public.is_admin(new.user_id) then
    return new;
  end if;

  begin
    v_actor_name := coalesce(public.actor_display_name(new.user_id), 'A citizen');

    perform public.notify_admins(
      'comment_heart',
      'New like on a comment',
      v_actor_name || ' liked a comment.',
      'post_like',
      4293675161,
      new.user_id
    );
  exception when others then
    raise warning 'tg_notify_comment_like skipped: % (%)', sqlerrm, sqlstate;
  end;
  return new;
end;
$function$;

-- ── §10  Sweep for anything still naming an actor personally ─────────────────
-- ⚠ Match on p.prosrc (the raw body), NOT on pg_get_functiondef(). That
-- function RAISES on aggregates — `ERROR 42809: "array_agg" is an aggregate
-- function` — and the planner is free to evaluate it before the nspname filter
-- has excluded them, so putting it in a WHERE clause kills the whole query.
-- `prokind = 'f'` is belt-and-braces for the same reason.
--
-- ⚠ Do NOT add '%display_name%' to this pattern. It matches
-- `actor_display_name` itself, so every function this migration FIXED comes
-- back as a hit — a sweep that reports its own fix as the bug.
--
-- This doubles as the "did it apply?" check: a function still listed here has
-- NOT been run yet. That is how §6/§7 were caught outstanding on 2026-07-20
-- while §5 had landed. When this migration is fully applied it should return
-- ONLY the two verification functions:
--   handle_verification_decision — names the RECIPIENT of their own result.
--   tg_notify_verification       — names the CITIZEN who submitted an ID, from
--                                  the verification row's own first/last name.
-- Both are people being described as themselves, not officials acting. Left
-- alone deliberately; re-check only if that changes.
--
-- Anything else this returns that describes an ACTOR is a leak:
--
--   select p.proname from pg_proc p
--     join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'public'
--      and p.prokind = 'f'
--      and p.prosrc ilike '%notifications%'
--      and (p.prosrc ilike '%full_name%' or p.prosrc ilike '%first_name%');

-- ── Verify ───────────────────────────────────────────────────────────────────
--   select public.actor_display_name('<a staff user_id>');  -- their department
--   select public.actor_display_name('<an admin user_id>'); -- LGU Aparri
--   select public.actor_display_name('<a citizen user_id>');-- their own name
--
-- Then, from a staff/admin account, comment on AND like another account's post
-- and confirm every writer names the office. §2 writes the admin's row, §5–§7
-- the post/comment author's:
--   select type, title, subtitle, created_at from public.notifications
--    where type in ('post_comment', 'comment_reply', 'post_like', 'comment_like')
--    order by created_at desc limit 10;
--
-- ⚠ Do NOT hit "Clear All" in the app before running that — it DELETES the rows
-- (NotificationService.clearAll), so an empty result proves nothing either way.
-- That is exactly what made the 2026-07-20 verification run come back with zero
-- rows and look like a broken trigger.
--
-- §5 no longer raises, so a failure there is now a warning instead of a lost
-- comment. If a notification goes missing, that is where it says why:
--   (Supabase Dashboard → Logs → Postgres, filter 'notify_on_comment skipped')
--
-- Rows already in the table keep the text they were created with — this only
-- affects notifications written from here on.
