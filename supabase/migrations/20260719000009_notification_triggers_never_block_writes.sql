-- ============================================================
-- NOTIFICATION TRIGGERS MUST NEVER BLOCK THE WRITE THEY ANNOUNCE
-- Run this in the Supabase SQL editor. Additive + idempotent.
--
-- ⚠ RUN THIS if you applied 20260719000006 or 20260719000008 and staff started
-- seeing "The server rejected the request. Please try again in a moment."
-- That string is staffFriendlyError()'s branch for a PostgrestException that is
-- NOT 42501 — i.e. a raw Postgres error, not an RLS refusal. A raising trigger
-- produces exactly that.
--
-- THE MISTAKE THIS CORRECTS
-- notification_deeplink_targets_3.sql warned about this precisely: these
-- triggers "`perform notify_admins(...)` with NO exception handler ... the
-- call raises, the trigger raises, and the whole INSERT is rolled back". I
-- reproduced tg_notify_comment in 20260719000008 from the repo copy without
-- being able to see the LIVE body, and added a new unguarded trigger in
-- 20260719000006. Either can turn a schema mismatch — a column that isn't named
-- what I assumed on admin_profiles, user_roles or notifications — into a hard
-- failure of the comment or like itself.
--
-- A notification is strictly secondary to the thing it announces. Losing one is
-- a cosmetic defect; losing the comment or the like is data loss the user
-- watched happen. So both trigger bodies below swallow their own errors and
-- return NEW, logging a warning instead. If the schema assumption was wrong,
-- the deep-link target or the actor name is simply missing — the write lands.
--
-- This does NOT paper over the underlying cause. Run the diagnostic at the
-- bottom to see whether either trigger is actually warning, and what about.
-- ============================================================

-- ── 1. Heart deep-link backfill (from 20260719000006) ────────────────────────
create or replace function public.tg_backfill_heart_reference()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_post_id uuid;
begin
  begin
    if TG_TABLE_NAME = 'community_post_likes' then
      v_post_id := new.post_id;
    else
      select c.post_id into v_post_id
      from public.community_comments c
      where c.id = new.comment_id;
    end if;

    if v_post_id is null then
      return new;
    end if;

    update public.notifications n
       set reference_id = v_post_id::text
     where n.reference_id is null
       and n.actor_id = new.user_id
       and n.created_at >= now()
       and coalesce(n.topic, n.type) in (
             'post_heart', 'comment_heart', 'post_like', 'comment_like'
           );
  exception when others then
    -- The heart itself must survive a bookkeeping failure.
    raise warning 'tg_backfill_heart_reference skipped: % (%)', sqlerrm, sqlstate;
  end;

  return new;
end;
$function$;

-- ── 2. Comment → admins (from 20260719000008) ────────────────────────────────
-- Same body as 000008 — admin_profiles.full_name first, role-aware fallback —
-- but the whole thing, notify_admins() included, is now inside a handler. A
-- staff member's comment can no longer be rejected because the notification
-- could not be composed or delivered.
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

  begin
    select ur.role_id
      into v_role_id
      from public.user_roles ur
     where ur.user_id = new.author_id
     order by ur.role_id
     limit 1;

    select coalesce(
      nullif(trim(ap.full_name), ''),
      nullif(trim(ad.first_name || ' ' || ad.last_name), ''),
      nullif(trim(sd.first_name || ' ' || sd.last_name), ''),
      nullif(trim(cd.first_name || ' ' || cd.last_name), ''),
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
    -- The comment itself must survive a failed notification.
    raise warning 'tg_notify_comment skipped: % (%)', sqlerrm, sqlstate;
  end;

  return new;
end;
$function$;

-- ── Diagnose (read-only) ─────────────────────────────────────────────────────
-- If a notification is now missing rather than erroring, these tell you why.
--
-- Do the columns 20260719000008 assumes actually exist?
--   select table_name, column_name
--     from information_schema.columns
--    where table_schema = 'public'
--      and (table_name = 'admin_profiles' and column_name in ('user_id','full_name'))
--       or (table_name = 'user_roles'     and column_name in ('user_id','role_id'))
--       or (table_name = 'notifications'  and column_name in ('topic','type','actor_id','reference_id'))
--    order by table_name, column_name;
--
-- Then comment as staff and heart a post, and read the server logs for
-- 'tg_notify_comment skipped' / 'tg_backfill_heart_reference skipped'. The
-- sqlerrm names the exact column or function that did not match.
--
-- TO REVERT ENTIRELY: restore tg_notify_comment from
-- supabase/legacy/notification_deeplink_targets_3.sql §4 (its pre-000008 form)
-- and drop the two zz_backfill_heart_reference triggers. The only losses are
-- the staff actor name and the heart deep-link target.
