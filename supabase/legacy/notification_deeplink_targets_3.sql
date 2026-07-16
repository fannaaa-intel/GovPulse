-- ════════════════════════════════════════════════════════════════════════════
--  Deep-link targets, part 3 — the notify_admins() callers.
--
--  Part 2 gave notify_admins() an optional `p_reference_id`. This passes it from
--  each caller, so an admin notification finally knows WHICH row it's about.
--  Every function below is reproduced VERBATIM from its live definition
--  (pg_get_functiondef) with ONE change: the id appended to the notify_admins()
--  call.
--
--  ⚠ RUN AFTER notification_deeplink_targets_2.sql — the §0 guard below refuses
--  to run otherwise, and that guard is not paranoia. These callers `perform
--  notify_admins(...)` with NO exception handler, unlike the notify_staff_*
--  functions. If the 7-argument notify_admins() doesn't exist yet, the call
--  raises, the trigger raises, and the whole INSERT is rolled back — meaning a
--  citizen could not submit a report, feedback, or suggestion AT ALL. The
--  failure would be loud and total, not a missing notification.
--
--  WHICH ID, AND WHY:
--    • tg_notify_report     → new.id       (reports)     — Reports console flashes it. ACTIVE.
--    • tg_notify_feedback   → new.id       (feedbacks)   — Feedback console flashes it. ACTIVE.
--    • tg_notify_suggestion → new.id       (suggestions) — Suggestions console flashes it. ACTIVE.
--    • tg_notify_comment    → new.post_id  (the POST, not the comment) — the admin
--      Community console lists posts, so the post is the row to land on. The
--      comment id would match nothing there. FORWARD-LOOKING: that page has no
--      highlight support yet, so the tap opens the tab and the id is ignored.
--    • tg_notify_verification → new.id (verification_submissions) —
--      FORWARD-LOOKING for the same reason.
--
--  DELIBERATELY UNTOUCHED — tg_notify_post_like / tg_notify_comment_like. Hearts
--  navigate but never flash a row (see kNonFlashingNotifTopics): a reaction is
--  ambient acknowledgement, not work arriving. They keep passing 6 arguments and
--  write a null reference_id, which is exactly right.
--
--  Null-safe throughout: the app treats a null/unknown reference_id as "open the
--  tab, flash nothing", so the forward-looking rows cost nothing today.
--
--  Idempotent. Run once, AFTER parts 1 and 2.
-- ════════════════════════════════════════════════════════════════════════════

-- ── §0  Ordering guard ───────────────────────────────────────────────────────
--  Fails loudly and changes nothing if part 2 hasn't been applied. Without this,
--  a wrong-order run leaves triggers calling a function that doesn't exist —
--  and citizens can no longer submit reports/feedback/suggestions.
--  Resolved with to_regprocedure, which matches on the TYPE signature and
--  returns null when there's no such function. Do NOT compare against
--  pg_get_function_identity_arguments() here: it renders parameter NAMES too
--  ("p_topic text, p_title text, ..."), so a plain type-list comparison never
--  matches and the guard rejects a correctly-applied part 2.
do $$
begin
  if to_regprocedure(
       'public.notify_admins(text, text, text, text, bigint, uuid, text)'
     ) is null then
    raise exception
      'Apply notification_deeplink_targets_2.sql first — notify_admins() has no p_reference_id parameter yet. Aborting so submissions keep working.';
  end if;
end
$$;

-- ── §1  New report → admins ──────────────────────────────────────────────────
create or replace function public.tg_notify_report()
returns trigger
language plpgsql security definer set search_path = public
as $function$
declare
  cat_label text;
begin
  cat_label := case new.category
    when 'road'        then 'Road & Infrastructure'
    when 'waste'       then 'Waste & Garbage'
    when 'drainage'    then 'Drainage & Flooding'
    when 'streetlight' then 'Streetlight Outage'
    when 'environment' then 'Environment & Pollution'
    when 'others'      then coalesce(nullif(new.category_other, ''), 'Others')
    else coalesce(new.category, 'Others')
  end;

  perform public.notify_admins(
    'report',
    'New report submitted',
    cat_label || coalesce(' • ' || new.barangay, ''),
    'general',
    4294286859,            -- orange 0xFFF59E0B
    new.user_id,
    new.id::text
  );
  return new;
end;
$function$;

-- ── §2  New feedback → admins ────────────────────────────────────────────────
create or replace function public.tg_notify_feedback()
returns trigger
language plpgsql security definer set search_path = public
as $function$
begin
  perform public.notify_admins(
    'feedback',
    'New feedback',
    coalesce(new.office_label, 'Service feedback')
      || coalesce(' • ' || new.overall_rating::text || '★', ''),
    'general',
    4279548070,            -- teal 0xFF14B8A6
    new.user_id,
    new.id::text
  );
  return new;
end;
$function$;

-- ── §3  New suggestion → admins ──────────────────────────────────────────────
create or replace function public.tg_notify_suggestion()
returns trigger
language plpgsql security definer set search_path = public
as $function$
begin
  perform public.notify_admins(
    'suggestion',
    'New suggestion',
    'A citizen submitted a suggestion.',
    'general',
    4280468830,            -- green 0xFF22C55E
    new.user_id,
    new.id::text
  );
  return new;
end;
$function$;

-- ── §4  New comment / reply → admins ─────────────────────────────────────────
--  Points at new.post_id, NOT new.id: the admin Community console lists POSTS,
--  so the post is the row to land on. A comment id would match nothing there.
create or replace function public.tg_notify_comment()
returns trigger
language plpgsql security definer set search_path = public
as $function$
declare
  preview text;
  v_actor_name text;
begin
  if public.is_admin(new.author_id) then
    return new;
  end if;

  select coalesce(
    nullif(trim(ad.first_name || ' ' || ad.last_name), ''),
    nullif(trim(sd.first_name || ' ' || sd.last_name), ''),
    nullif(trim(cd.first_name || ' ' || cd.last_name), ''),
    'A citizen'
  ) into v_actor_name
  from auth.users u
  left join public.admin_details   ad on ad.user_id = u.id
  left join public.staff_details   sd on sd.user_id = u.id
  left join public.citizen_details cd on cd.user_id = u.id
  where u.id = new.author_id;

  preview := left(coalesce(new.body, ''), 80);

  perform public.notify_admins(
    'comment',
    case when new.parent_comment_id is null
         then 'New comment' else 'New reply' end,
    v_actor_name || ' posted a comment: "' || coalesce(nullif(preview, ''), '') || '"',
    'post_comment',
    4280640491,
    new.author_id,
    new.post_id::text
  );
  return new;
end;
$function$;

-- ── §5  New verification submission → admins ─────────────────────────────────
create or replace function public.tg_notify_verification()
returns trigger
language plpgsql security definer set search_path = public
as $function$
begin
  perform public.notify_admins(
    'verification',
    'New verification submission',
    coalesce(
      nullif(trim(coalesce(new.first_name, '') || ' ' || coalesce(new.last_name, '')), ''),
      'A citizen submitted their ID for review.'
    ),
    'general',
    4284704497,            -- indigo 0xFF6366F1
    new.user_id,
    new.id::text
  );
  return new;
end;
$function$;
