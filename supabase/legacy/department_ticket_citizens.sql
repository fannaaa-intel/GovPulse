-- ════════════════════════════════════════════════════════════════════════════
--  Citizen photos for the staff Conversations LIST (batch)
--
--  The inbox list shows one row per ticket; fetching each citizen's photo with a
--  per-row query doesn't scale. This SECURITY DEFINER function returns, in one
--  call, the photo path for every NON-anonymous ticket in the caller's
--  department — so the client can build a ticket_id → photo map. Anonymous
--  tickets are omitted (they keep the default avatar).
--
--  Authorised to staff (role_id 2) in the ticket's department (reuses the
--  helpers from staff_portal.sql). Idempotent. Run after staff_portal.sql.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.department_ticket_citizens()
returns table(ticket_id uuid, photo_path text)
language sql
stable
security definer
set search_path = public
as $$
  select ct.id, cd.profile_photo_path
  from public.concern_tickets ct
  join public.citizen_details cd on cd.user_id = ct.user_id
  where ct.department = public.current_staff_department()
    and public.current_user_role_id() = 2
    and coalesce(ct.is_ghost, false) = false
    and coalesce(ct.is_anonymous, false) = false
    and coalesce(cd.profile_photo_path, '') <> '';
$$;

grant execute on function public.department_ticket_citizens() to authenticated;
