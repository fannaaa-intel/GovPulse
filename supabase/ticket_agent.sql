-- ════════════════════════════════════════════════════════════════════════════
--  Connected-staff identity for the citizen chat header
--
--  When a citizen is connected to a live staff member, their chat header should
--  show the staff's name + photo (not just "Engineering Office staff"). A citizen
--  can't read admin_profiles under RLS, so this SECURITY DEFINER function returns
--  ONLY the assigned staff's public-facing name / photo / department for a ticket
--  the caller owns — nothing else, no other staff, no PII.
--
--  Authorised to the ticket's owner (the citizen) only. Returns no row if the
--  caller doesn't own the ticket or no staff is assigned yet.
--
--  Idempotent. Run once.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.ticket_agent(p_ticket uuid)
returns table(full_name text, photo_url text, department text)
language sql
stable
security definer
set search_path = public
as $$
  select ap.full_name, ap.photo_url, ct.department
  from public.concern_tickets ct
  join public.admin_profiles ap on ap.user_id = ct.assigned_staff_id
  where ct.id = p_ticket
    and ct.user_id = auth.uid()          -- caller must own the ticket
    and ct.assigned_staff_id is not null;
$$;

grant execute on function public.ticket_agent(uuid) to authenticated;
