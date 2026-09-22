-- Verify 20260922000000_staff_suggestions_feedback_routing
-- Run ONE BLOCK AT A TIME in the Supabase SQL editor (it keeps only the last
-- result set), or pass this whole file as sbx.py's third argument, which runs
-- every block inside the same transaction and prints each.

-- 1. the routing columns exist on both tables
select c.relname, a.attname, format_type(a.atttypid, a.atttypmod) as typ
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
join pg_attribute a on a.attrelid = c.oid and a.attname = 'department'
where n.nspname = 'public' and c.relname in ('suggestions','feedbacks')
order by c.relname;

---
-- 2. routing functions return the agreed mapping.
-- Expect: infrastructure->Engineering, environment->Environment,
-- health_safety->Sanitation, the rest + others->Mayor's.
select k as category, public.suggestion_department(k) as office
from unnest(array['infrastructure','environment','health_safety',
                  'public_service','community_program','others']) k;

---
-- 3. feedback mapping. NOTE: no office maps to Environment Office — that is
-- why the staff console hides the Feedback tab for that department.
select k as office_id, public.feedback_department(k) as office
from unnest(array['health','mpdo','mayor','civil','cert']) k;

---
-- 4. every row was backfilled. A null department is invisible to every office,
-- so both counts MUST be 0.
select
  (select count(*) from public.suggestions where department is null) as suggestions_unrouted,
  (select count(*) from public.feedbacks   where department is null) as feedbacks_unrouted;

---
-- 5. the triggers are attached
select c.relname as tbl, t.tgname, t.tgenabled
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and not t.tgisinternal
  and t.tgname in ('trg_route_suggestion','trg_route_feedback',
                   'trg_reroute_suggestion_ai','trg_publish_suggestion_reply',
                   'trg_notify_admins_pending_reply')
order by c.relname, t.tgname;

---
-- 6. the staff views exist and are security_invoker (so the caller's own RLS
-- applies rather than the view owner's)
select c.relname, c.reloptions
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('staff_suggestions_view','staff_feedbacks_view');

---
-- 7. staff SELECT policies exist on the base tables. Without these the
-- security_invoker views return zero rows for staff and the page looks empty
-- rather than erroring.
select tablename, policyname, cmd
from pg_policies
where schemaname = 'public'
  and policyname in ('staff_reads_department_suggestions',
                     'staff_reads_department_feedbacks')
order by tablename;

---
-- 8. suggestion_replies: RLS on, and all four policies present.
-- role_id 2 has no INSERT anywhere by default, so a missing write policy here
-- would fail in a way that reads as a flaky network, not a permission error.
select c.relrowsecurity as rls_enabled,
       (select count(*) from pg_policies
         where schemaname='public' and tablename='suggestion_replies') as policy_count
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname='public' and c.relname='suggestion_replies';

---
-- 9. the one-live-reply index (a suggestion can hold only one pending or
-- approved draft at a time; a rejected one is revised in place)
select indexname from pg_indexes
where schemaname='public' and tablename='suggestion_replies'
order by indexname;

---
-- 10. the authenticated role can reach the new objects
select c.relname, array_to_string(c.relacl, ' | ') as acl
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname='public'
  and c.relname in ('staff_suggestions_view','staff_feedbacks_view','suggestion_replies')
order by c.relname;
