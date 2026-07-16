-- ════════════════════════════════════════════════════════════════════════════
--  Chat ratings — a citizen rates the live-agent conversation after a staff
--  member ends it. Stored on the ticket; written through a SECURITY DEFINER RPC
--  so the citizen can rate ONLY their own ticket without a broad update policy.
--
--  Idempotent. Safe to run more than once.
-- ════════════════════════════════════════════════════════════════════════════

alter table public.concern_tickets
  add column if not exists rating         smallint,
  add column if not exists rating_comment text,
  add column if not exists rated_at       timestamptz;

-- Rate a ticket the caller owns. Clamps the score to 1..5; ignores re-rating a
-- ticket that already has a score (first rating wins).
create or replace function public.rate_ticket(
  p_ticket_id uuid,
  p_rating    int,
  p_comment   text default null
)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  update public.concern_tickets
     set rating         = greatest(1, least(5, p_rating)),
         rating_comment = nullif(btrim(coalesce(p_comment, '')), ''),
         rated_at       = now()
   where id = p_ticket_id
     and user_id = auth.uid()
     and rating is null;
end;
$$;

grant execute on function public.rate_ticket(uuid, int, text) to authenticated;
