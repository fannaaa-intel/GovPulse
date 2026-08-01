-- ============================================================================
-- verify_20260722000002_view_grants — no view in `public` may grant writes to a
-- client role
-- ============================================================================
-- STANDING DETECTOR, SCHEMA-WIDE. Not tied to one migration's apply and not
-- scoped to any named view — re-run it after ANY migration that CREATES a view,
-- recreates one, or touches grants in `public`.
--
-- Runnable as ONE artifact. Read-only: the single transaction ends in ROLLBACK
-- and nothing here writes outside it. Results accumulate into a temp table and
-- are emitted by the single SELECT at the end — required because the Supabase
-- SQL editor and the Management API both return only the LAST result set of a
-- multi-statement script.
--
-- Expected: 7 rows, every verdict PASS, followed by no exception.
-- On violation the final DO block RAISES, the transaction aborts, and the result
-- table is NOT returned — the exception message names what broke. That is
-- deliberate: this must fail loudly in CI, not emit a FAIL row a human has to
-- notice. Same contract as verify_sender_id_grant_invariant.sql.
--
-- ── WHY THIS FILE EXISTS, AND WHY IT IS BEING WRITTEN LATE ─────────────────
-- 20260722000002 line 62 asserted this file already existed:
--
--     diagnostics/verify_20260722000002_view_grants.sql asserts this for every
--     view in the schema, so a regression fails loudly instead of shipping.
--
-- It did not. The name appeared nowhere in the repo except that sentence, so the
-- standing rule it describes had prose and no enforcement — and the next view
-- created after it, staff_messages_view (20260731000003, nine days later),
-- shipped in breach and stayed that way until 2026-08-01. 20260731000007 strips
-- that grant; THIS file is the guard that makes the third occurrence fail loudly
-- instead of being found by another manual audit.
--
-- ── THE INVARIANT ─────────────────────────────────────────────────────────
-- No view in `public` grants INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES or
-- TRIGGER to PUBLIC, anon, authenticated, or authenticator. SELECT is the only
-- privilege a client role may hold on a view.
--
-- ── WHY IT MATTERS MOST FOR DEFINER VIEWS ─────────────────────────────────
-- A write through a SECURITY DEFINER view executes as the view's OWNER and
-- bypasses base-table RLS entirely. 20260722000002 reproduced this live as the
-- real staff account: two statements against staff_reports_view flipped
-- is_anonymous and de-anonymised the reporter, and DELETE succeeded — a
-- capability staff never held on the base table at all. `public` currently holds
-- three definer views (staff_reports_view, staff_tickets_view,
-- staff_messages_view), all three deliberately so, all three flagged as ERRORs by
-- Security Advisor lint 0010 as an accepted exception. Their grants are the only
-- thing standing between a staff JWT and RLS-free writes.
--
-- ── WHY IT CHECKS INVOKER VIEWS TOO ────────────────────────────────────────
-- Lower severity — a write through an invoker view is still checked against the
-- caller's RLS on the base table — but TRUNCATE and DELETE grants to
-- `authenticated` are wrong regardless, and an invoker view can be converted to
-- definer by a one-word change in a later migration. Leaving them dirty arms the
-- trap for whoever makes that change. 20260722000002 swept all six views for
-- exactly this reason; the check keeps the same scope.
--
-- ── WHY CHECK 1 IS A BLANKET SWEEP AND NOT AN ALLOWLIST OF VIEW NAMES ──────
-- The failure mode being guarded is a NEW view arriving with Supabase's default
-- privileges intact. A detector listing today's seven views would pass happily
-- while the eighth leaked, which is the precise way this regression got in. The
-- sweep therefore names no views at all — anything in `public` with relkind
-- 'v' or 'm' is in scope the moment it is created.
--
-- Materialized views ('m') are included pre-emptively: `public` has none today,
-- they are not subject to RLS at all, and they inherit the same default grants.
--
-- ── WHY CHECKS 4-6 EXIST: NON-VACUITY ──────────────────────────────────────
-- A detector that only asserts absence passes trivially if the thing it guards
-- disappears. Revoking SELECT from authenticated on all seven views would make
-- check 1 pass while the app was entirely broken. Check 4 asserts the three
-- staff views still exist, check 5 asserts authenticated can still READ them,
-- and check 6 asserts they are still DEFINER — so "fixing" a failure by
-- revoking everything, dropping a view, or flipping one to security_invoker
-- trips this file too.
--
-- Check 6 is the one that catches a well-meaning response to the Security
-- Advisor. Someone actioning the three lint-0010 ERRORs would set
-- security_invoker = true, the staff portal would return zero rows, and no other
-- check in this repo would say why. It fails here, with the reason.
--
-- ── CHECK 7 REPLACES THE MUTED ADVISOR RULE — DO NOT DELETE IT ─────────────
-- Supabase lint 0010 (security_definer_view) is DISABLED for this project via
-- Advisors → Rules. That control is PROJECT-WIDE: there is no per-object
-- exception, so muting the three accepted views also mutes the warning for every
-- definer view created from now on. The dashboard will no longer tell anyone that
-- a new one exists.
--
-- Check 7 is what we traded the advisor for. It is a POSITIVE ALLOWLIST: exactly
-- three views in `public` may be SECURITY DEFINER, by name. A fourth — however it
-- arrives, whatever it is called — fails this file. That is stricter than the
-- advisor ever was, because the advisor only ever warned; this raises.
--
-- The distinction that matters: the three allowlisted views are safe because each
-- one's WHERE clause re-derives the caller's identity (current_user_role_id() = 2
-- plus a department match) INSIDE the view. A definer view without such a
-- predicate returns the whole base table to anyone holding SELECT on the view,
-- with RLS bypassed entirely. Nothing here can check for that automatically —
-- so the rule is the allowlist, and adding a name to it is a deliberate act that
-- should not happen without re-reading 20260722000002 and 20260731000007.
--
-- ── HOW TO REACT WHEN THIS FAILS — READ BEFORE EDITING THIS FILE ───────────
-- CHECK 1 FAILED (a view grants writes to a client role):
--   1. Do NOT narrow the privilege list or exclude the view. The sweep is the
--      invariant.
--   2. The cause is almost always a `create view` in a recent migration whose
--      revoke omitted `authenticated`. Supabase's default privileges grant ALL
--      on new objects in `public` to authenticated EXPLICITLY, so
--      `revoke all ... from public, anon` leaves it untouched and the following
--      `grant select` adds nothing it did not already hold.
--   3. Fix it at the source migration AND here-and-now with:
--          revoke all on public.<view> from public, anon, authenticated, authenticator;
--          grant  select on public.<view> to authenticated;      -- staff/internal
--          grant  select on public.<view> to anon, authenticated; -- if guest-visible
--      Preserve anon SELECT only for genuinely public surfaces (community_feed,
--      public_user_profiles, reports_public). service_role keeps its writes by
--      design and is not swept.
--
-- CHECK 6 FAILED (a staff view is no longer SECURITY DEFINER):
--   Someone has actioned the Security Advisor's lint-0010 ERRORs. REVERT IT.
--   Staff hold no SELECT policy on public.reports or public.concern_tickets —
--   20260722000001 and 20260721000007 section 4 dropped them so no raw-column
--   path survives. An invoker view resolves under the caller's RLS, finds no
--   policy, and returns zero rows to every staff user: triage, inbox and chat go
--   blank. Restore with `alter view public.<view> set (security_invoker = false)`.
--   Those three ERRORs are permanent and accepted; see the comments on the views
--   themselves (20260731000007 section 2). The advisor rule is muted project-wide,
--   so the dashboard will NOT re-flag it for you — this file is the only warning.
--
-- CHECK 7 FAILED (a new definer view appeared):
--   Someone created a view without `with (security_invoker = true)`. That is the
--   DEFAULT, so it is far more likely an omission than a decision. Determine which:
--     * If the view is meant to be an ordinary invoker view — the normal case —
--       fix it: `alter view public.<view> set (security_invoker = true);`
--     * If it genuinely needs to be definer, it MUST re-derive the caller's
--       identity in its own WHERE clause (see staff_can_see_report /
--       staff_can_see_ticket for the pattern) — a definer view without such a
--       predicate hands the entire base table to every holder of SELECT, RLS
--       bypassed. Only then add its name to check 7's allowlist, and give it a
--       `comment on view` recording why, as 20260731000007 section 2 did.
--   Do NOT silence this by adding the name without doing that analysis. Lint 0010
--   is off; this check is what replaced it.
-- ============================================================================

begin;

create temp table _v(seq int primary key, check_name text, expected text, actual text, verdict text);

-- ── 1. THE INVARIANT: no client role holds a write privilege on any view ───
-- Blanket sweep over every view and matview in `public`. Reports offender:role
-- pairs so the operator sees exactly what to revoke, not just a count.
insert into _v
select 1,
       'no view in public grants writes to PUBLIC/anon/authenticated/authenticator',
       '<none>',
       coalesce(string_agg(distinct g.table_name || ':' || g.grantee || ':' || g.privilege_type, ', '), '<none>'),
       case when count(*) = 0 then 'PASS' else 'FAIL' end
from information_schema.role_table_grants g
join pg_class c   on c.relname   = g.table_name
join pg_namespace n on n.oid     = c.relnamespace and n.nspname = g.table_schema
where g.table_schema  = 'public'
  and c.relkind       in ('v','m')
  and g.privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER')
  and g.grantee        in ('PUBLIC','anon','authenticated','authenticator');

-- ── 2. Same question asked of the privilege system directly ────────────────
-- information_schema.role_table_grants enumerates ACL entries; it can disagree
-- with real privilege resolution through role inheritance or a PUBLIC grant.
-- has_table_privilege asks the resolver the question PostgREST's session will
-- effectively ask. Both must agree — checks 1 and 2 failing together is a real
-- grant; check 2 alone failing means the privilege arrives by inheritance.
insert into _v
select 2,
       'privilege resolver agrees no client role can write to any public view',
       '<none>',
       coalesce(string_agg(v.relname || ':' || r.rolname || ':' || p.priv, ', '), '<none>'),
       case when count(*) = 0 then 'PASS' else 'FAIL' end
from pg_class v
join pg_namespace n on n.oid = v.relnamespace
cross join unnest(array['anon','authenticated','authenticator']) as r(rolname)
cross join unnest(array['INSERT','UPDATE','DELETE','TRUNCATE']) as p(priv)
where n.nspname = 'public'
  and v.relkind in ('v','m')
  and has_table_privilege(r.rolname, v.oid, p.priv);

-- ── 3. The specific regression 20260731000007 closed ───────────────────────
-- Named separately from the sweep so a re-occurrence on THIS view is
-- unambiguous in the output rather than one entry in an aggregated string. This
-- view is the reason the file exists.
insert into _v
select 3,
       'staff_messages_view grants authenticated SELECT and nothing else',
       'SELECT',
       coalesce(string_agg(privilege_type, ', ' order by privilege_type), '<none>'),
       case when coalesce(string_agg(privilege_type, ', ' order by privilege_type), '<none>') = 'SELECT'
            then 'PASS' else 'FAIL' end
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name   = 'staff_messages_view'
  and grantee      = 'authenticated';

-- ── 4-6. Non-vacuity ──────────────────────────────────────────────────────
insert into _v
select 4,
       'all three staff definer views still exist (guards against a vacuous PASS)',
       '3',
       count(*)::text,
       case when count(*) = 3 then 'PASS' else 'FAIL' end
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relkind = 'v'
  and c.relname in ('staff_reports_view','staff_tickets_view','staff_messages_view');

insert into _v
select 5,
       'authenticated still holds SELECT on all three staff views',
       '3',
       count(*)::text,
       case when count(*) = 3 then 'PASS' else 'FAIL' end
from information_schema.role_table_grants
where table_schema  = 'public'
  and table_name    in ('staff_reports_view','staff_tickets_view','staff_messages_view')
  and grantee       = 'authenticated'
  and privilege_type = 'SELECT';

-- The check that catches someone "fixing" the Security Advisor. A view with no
-- reloptions at all defaults to security_invoker = false, so the test is for the
-- ABSENCE of an enabling value rather than the presence of 'security_invoker=false'
-- — 'on'/'true'/'1' are all accepted spellings of true and public_user_profiles
-- already uses 'on', proving the spellings vary in this schema.
insert into _v
select 6,
       'all three staff views are still SECURITY DEFINER (invoker NOT enabled)',
       'all definer',
       coalesce(string_agg(c.relname || '=' || coalesce(c.reloptions::text,'{}'), ', ' order by c.relname), '<none>'),
       case when count(*) filter (
              where array_to_string(coalesce(c.reloptions, '{}'), ',') ~* 'security_invoker=(true|on|1|yes)'
            ) = 0 then 'PASS' else 'FAIL' end
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('staff_reports_view','staff_tickets_view','staff_messages_view');

-- ── 7. ALLOWLIST: no definer view may exist beyond the three accepted ─────
-- The compensating control for the muted advisor rule. A view with NO reloptions
-- defaults to security_invoker = false, i.e. DEFINER — so a plain `create view`
-- with no options lands here, which is exactly the accident worth catching.
insert into _v
select 7,
       'no SECURITY DEFINER view in public outside the three accepted',
       '<none>',
       coalesce(string_agg(c.relname, ', ' order by c.relname), '<none>'),
       case when count(*) = 0 then 'PASS' else 'FAIL' end
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relkind in ('v','m')
  and c.relname not in ('staff_reports_view','staff_tickets_view','staff_messages_view')
  and array_to_string(coalesce(c.reloptions, '{}'), ',') !~* 'security_invoker=(true|on|1|yes)';

select seq, check_name, expected, actual, verdict from _v order by seq;

-- ── Loud failure ──────────────────────────────────────────────────────────
do $$
declare
  v_failed text;
begin
  select string_agg(seq || ': ' || check_name || ' (got: ' || actual || ')', '; ' order by seq)
    into v_failed
    from _v
   where verdict <> 'PASS';

  if v_failed is not null then
    raise exception
      'VIEW GRANT INVARIANT FAILED -- %. A write through a SECURITY DEFINER view executes as the view OWNER and bypasses base-table RLS entirely (reproduced live in 20260722000002: two statements de-anonymised a report, and DELETE succeeded -- a capability staff never held). Revoke naming `authenticated` EXPLICITLY: Supabase default privileges grant ALL on new objects in public to it, so `revoke all ... from public, anon` does nothing. Do not narrow this sweep. If check 6 failed, someone actioned the Security Advisor lint-0010 ERRORs -- revert it: staff hold no SELECT policy on reports or concern_tickets, so an invoker view returns zero rows and blanks the staff portal.',
      v_failed;
  end if;
end $$;

rollback;
