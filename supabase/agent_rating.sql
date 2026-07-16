-- ════════════════════════════════════════════════════════════════════════════
--  Agent rating aggregate
--
--  The citizen chat header shows the live-agent's average star rating. Citizens
--  can't read other citizens' tickets under RLS, so a plain avg() query returns
--  only their own rows. This SECURITY DEFINER function returns just the
--  aggregate (average + count) over every rated concern_ticket — no rows, no
--  PII — so it's safe to expose to any signed-in (or anonymous) client.
--
--  Idempotent. Run once.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.agent_avg_rating()
returns table(avg numeric, cnt bigint)
language sql
stable
security definer
set search_path = public
as $$
  select
    coalesce(round(avg(rating)::numeric, 1), 0) as avg,
    count(rating)                               as cnt
  from public.concern_tickets
  where rating is not null;
$$;

grant execute on function public.agent_avg_rating() to authenticated, anon;
