-- 20261006000000_kuya_gov_knowledge_gaps.sql
--
-- Questions Kuya Gov could not answer.
--
-- Until now nothing about a chat was kept, so there was no way to know what
-- citizens ask that the bot does not know — the fact table was filled from
-- guesses about demand. chat-agent v7 asks the model to end an unanswerable
-- reply with [[KB_GAP]]; the function strips that marker and writes the
-- question here (supabase/functions/chat-agent/knowledge_gaps.ts).
--
-- PRIVACY, by construction:
--   • No user id, session, report reference or device — just the question.
--   • The function redacts emails and any 7+ digit run (phone / ID numbers)
--     before insert, and caps the text at 300 chars; the check below backs
--     the cap up at the database.
--   • Only the edge function writes (service role, which bypasses RLS).
--     Citizens and staff cannot insert or read; admins can read and delete.
--
-- Not scheduled for automatic purge — this project runs no pg_cron jobs from
-- migrations. Clear old rows by hand, e.g.:
--   delete from public.kuya_gov_knowledge_gaps where created_at < now() - interval '180 days';
--
-- To read the backlog, most-asked first:
--   select lower(question) as q, count(*) as times, max(created_at) as last_asked
--     from public.kuya_gov_knowledge_gaps
--    group by 1 order by 2 desc, 3 desc;

create table if not exists public.kuya_gov_knowledge_gaps (
  id          bigint generated always as identity primary key,
  created_at  timestamptz not null default now(),
  question    text        not null check (char_length(question) between 1 and 300),
  stage       text
);

comment on table public.kuya_gov_knowledge_gaps is
  'Redacted citizen questions Kuya Gov flagged as unanswerable ([[KB_GAP]]). Written only by the chat-agent edge function; no user identifiers.';

create index if not exists kuya_gov_knowledge_gaps_created_at_idx
  on public.kuya_gov_knowledge_gaps (created_at desc);

alter table public.kuya_gov_knowledge_gaps enable row level security;

-- public.is_admin() is deliberately NOT wrapped as (select …) — see the note in
-- 20260826000000_lgu_facts.sql; that InitPlan pattern applies to auth.uid().
drop policy if exists kuya_gov_knowledge_gaps_admin_read on public.kuya_gov_knowledge_gaps;
create policy kuya_gov_knowledge_gaps_admin_read on public.kuya_gov_knowledge_gaps
  for select to authenticated
  using (public.is_admin());

drop policy if exists kuya_gov_knowledge_gaps_admin_delete on public.kuya_gov_knowledge_gaps;
create policy kuya_gov_knowledge_gaps_admin_delete on public.kuya_gov_knowledge_gaps
  for delete to authenticated
  using (public.is_admin());

revoke all on public.kuya_gov_knowledge_gaps from anon, authenticated;
grant select, delete on public.kuya_gov_knowledge_gaps to authenticated; -- gated by RLS above
