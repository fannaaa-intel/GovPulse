-- ============================================================================
-- ROLLBACK for 20260722000005_citizen_ticket_writes_phase1.sql
-- ============================================================================
-- Policy DDL captured verbatim from live pg_policy on 2026-07-22 BEFORE the
-- migration (generated from pg_get_expr, not hand-typed). Function bodies
-- captured from live pg_get_functiondef.
--
-- Phase 1 was additive against the deployed client, so rolling it back is low
-- risk — BUT only if phase 2 (Dart) has NOT shipped. Once the client calls
-- promote_ticket()/assign_ticket_staff(), dropping them breaks the citizen's
-- escalation to a live agent. Check what is deployed before running this.
--
-- This file lives in supabase/rollback/ and must NEVER be moved into
-- supabase/migrations/. Move files by exact filename, never by wildcard.
-- ============================================================================

begin;

-- Undo 7: restore 'ended' in the accepted set.
create or replace function public.staff_set_ticket_status(p_ticket uuid, p_status text)
returns void language plpgsql security definer set search_path to 'public', 'pg_temp'
as $fn$
declare v_dept text;
begin
  if public.current_user_role_id() <> 2 then
    raise exception 'not staff' using errcode = '42501';
  end if;
  if p_status not in ('open','active','waiting','resolved','ended','closed') then
    raise exception 'invalid status: %', p_status using errcode = '22023';
  end if;
  select department into v_dept from public.concern_tickets where id = p_ticket;
  if v_dept is null then
    raise exception 'ticket not found' using errcode = 'P0002';
  end if;
  if v_dept <> public.current_staff_department() then
    raise exception 'ticket belongs to another department' using errcode = '42501';
  end if;
  update public.concern_tickets
     set status = p_status,
         resolved_at = case when p_status in ('resolved','ended','closed') then now() else resolved_at end,
         updated_at = now()
   where id = p_ticket;
end
$fn$;

-- Undo 6: rate_ticket without the status guard (original live body).
create or replace function public.rate_ticket(p_ticket_id uuid, p_rating integer, p_comment text default null)
returns void language plpgsql security definer set search_path to 'public'
as $fn$
begin
  update public.concern_tickets
     set rating         = greatest(1, least(5, p_rating)),
         rating_comment = nullif(btrim(coalesce(p_comment, '')), ''),
         rated_at       = now()
   where id = p_ticket_id
     and user_id = auth.uid()
     and rating is null;
end;
$fn$;

-- Undo 5 and 4: these functions did not exist before phase 1.
drop function if exists public.promote_ticket(uuid, uuid);
drop function if exists public.assign_ticket_staff(uuid, uuid);

-- Undo 3: restore the untightened DELETE policy.
drop policy if exists "Citizens can delete their own ghost tickets" on public.concern_tickets;

create policy "Citizens can delete their own ghost tickets" on public.concern_tickets
  as permissive for delete to authenticated
  using (((auth.uid() = user_id) AND (is_ghost = true) AND (assigned_staff_id IS NULL)));

-- Undo 2: drop the helper AFTER the policy that referenced it is gone.
drop function if exists public.ticket_has_staff_message(uuid);

-- Undo 1: remove the status constraint.
alter table public.concern_tickets
  drop constraint if exists concern_tickets_status_check;

commit;
