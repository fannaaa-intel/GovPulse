-- ============================================================
-- Fix broadcast_notification: overload ambiguity (PGRST203) + admin avatar
-- ============================================================
-- Run this once in the Supabase SQL editor. It does two things:
--
-- 1. Drops the stale 6-arg overload that made the RPC ambiguous:
--      PostgrestException(... code: PGRST203, hint: Multiple Choices).
--    The canonical 3-arg (text, text, bigint) version is kept.
--
-- 2. Replaces that canonical version so every broadcast row carries the
--    acting admin as its actor (actor_id + actor_photo_url). The citizen bell
--    then shows the admin's profile photo instead of a generic icon, matching
--    the suggestion / feedback response notifications.

-- 1 ── Drop the stray overload ────────────────────────────────────────────────
drop function if exists public.broadcast_notification(
  text, text, text, bigint, integer, text
);

-- 2 ── Canonical function, now personalised with the admin's avatar ───────────
create or replace function public.broadcast_notification(
  p_title    text,
  p_subtitle text,
  p_color    bigint default 4283980779  -- 0xFF2563EB
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
  v_photo text;
begin
  if not public.is_admin() then
    raise exception 'not authorized';
  end if;

  -- The broadcasting admin's avatar (best-effort; null → citizen sees the icon).
  select photo_url into v_photo
  from public.admin_profiles
  where user_id = auth.uid();

  insert into public.notifications
    (user_id, title, subtitle, type, color_value, icon_code,
     is_approved, sent_by, actor_id, actor_photo_url)
  select p.id, p_title, p_subtitle, 'admin_broadcast', p_color, 0,
         true, auth.uid(), auth.uid(), v_photo
  from public.profiles p
  where coalesce(p.is_deactivated, false) = false
    and not exists (
      select 1 from public.user_roles ur
      where ur.user_id = p.id and ur.role_id in (1,2)
    );

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

grant execute on function public.broadcast_notification(text, text, bigint) to authenticated;
