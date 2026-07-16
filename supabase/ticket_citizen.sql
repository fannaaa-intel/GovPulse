-- ════════════════════════════════════════════════════════════════════════════
--  Citizen identity for the staff chat header + bubbles
--
--  Staff can't read citizen_details under RLS, so this SECURITY DEFINER function
--  returns ONLY the ticket's citizen name + profile photo path — for a ticket in
--  the caller's own department. Anonymous chats return NULL identity (the staff
--  must never see who filed it), so the UI falls back to a default avatar.
--
--  Authorised to staff (role_id 2) whose department matches the ticket. Photo is
--  a storage path in the public `profile-photos` bucket; the client resolves it
--  to a URL.
--
--  Idempotent. Run once (after staff_portal.sql — uses the same role/dept model).
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.ticket_citizen(p_ticket uuid)
returns table(full_name text, photo_path text, is_anonymous boolean)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user uuid;
  v_dept text;
  v_anon boolean;
begin
  select ct.user_id, ct.department, coalesce(ct.is_anonymous, false)
    into v_user, v_dept, v_anon
  from public.concern_tickets ct
  where ct.id = p_ticket;
  if not found then return; end if;

  -- Caller must be staff (role_id 2) in the ticket's department.
  if not exists (
    select 1 from public.admin_profiles ap
    join public.user_roles ur on ur.user_id = ap.user_id and ur.role_id = 2
    where ap.user_id = auth.uid() and ap.department = v_dept
  ) then
    return;
  end if;

  -- Anonymous chats expose no identity.
  if v_anon then
    return query select null::text, null::text, true;
    return;
  end if;

  return query
  select
    nullif(trim(coalesce(cd.first_name, '') || ' ' || coalesce(cd.last_name, '')), ''),
    nullif(trim(coalesce(cd.profile_photo_path, '')), ''),
    false
  from public.citizen_details cd
  where cd.user_id = v_user;
end;
$$;

grant execute on function public.ticket_citizen(uuid) to authenticated;
