-- 20261012000000_close_live_staff_chat.sql
--
-- Panel revision (2026-10-12), stage A: stop every new live-chat write.
-- Applied by hand in the SQL editor on 2026-10-12 and verified live (all
-- checks in supabase/diagnostics/verify_20261012000000.sql PASS). Stage B,
-- which drops the tables, is supabase/pending/drop_live_staff_chat.sql.
--
-- Citizens no longer chat with staff: the panel ruled a direct line bypasses
-- GovPulse's tracked channels and invites idle or abusive conversation. The
-- staff on-duty flag goes too — it existed only to route these chats.
-- Reads are left alone so nothing breaks before the new app build ships.

-- No new tickets, messages or attachments.
drop policy if exists "Citizens can create their own tickets" on public.concern_tickets;
drop policy if exists "Ticket participants can send messages" on public.ticket_messages;
drop policy if exists "staff_writes_department_messages" on public.ticket_messages;
drop policy if exists "Ticket participants can upload attachments" on public.ticket_attachments;

-- Definer functions write past RLS, so each write path is closed at EXECUTE.
revoke execute on function public.find_available_staff(text)          from public, anon, authenticated;
revoke execute on function public.promote_ticket(uuid, uuid)          from public, anon, authenticated;
revoke execute on function public.assign_ticket_staff(uuid, uuid)     from public, anon, authenticated;
revoke execute on function public.staff_claim_ticket(uuid)            from public, anon, authenticated;
revoke execute on function public.staff_set_ticket_status(uuid, text) from public, anon, authenticated;
revoke execute on function public.staff_touch_ticket(uuid)            from public, anon, authenticated;
revoke execute on function public.rate_ticket(uuid, integer, text)    from public, anon, authenticated;

-- End every conversation still open ('closed' is what an old client reads as
-- "the chat has ended").
update public.concern_tickets set status = 'closed', updated_at = now()
 where coalesce(status, '') not in ('resolved', 'closed');

-- Nobody is "online" any more; the column itself goes in stage B.
update public.admin_profiles set is_online = false where is_online;
