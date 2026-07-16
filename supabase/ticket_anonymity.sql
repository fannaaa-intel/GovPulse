-- ════════════════════════════════════════════════════════════════════════════
--  Ticket anonymity — a follow-up chat about an ANONYMOUS report must stay
--  anonymous. Staff handle the concern, but never see who the citizen is.
--
--  `promoteTicket` (client) derives anonymity from the linked report and skips
--  attaching contact details; this column records the decision on the ticket so
--  the staff console can label the chat "Anonymous citizen".
--
--  Idempotent.
-- ════════════════════════════════════════════════════════════════════════════

alter table public.concern_tickets
  add column if not exists is_anonymous boolean not null default false;

-- Backfill: any existing ticket linked to an anonymous report is anonymous, and
-- its leaked contact columns are cleared.
update public.concern_tickets t
   set is_anonymous   = true,
       contact_name   = null,
       contact_number = null,
       contact_address = null,
       contact_email  = null
  from public.reports r
 where t.report_id = r.id
   and coalesce(r.is_anonymous, false) = true
   and coalesce(t.is_anonymous, false) = false;
