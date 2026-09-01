-- Verify 20260901000002 — anonymous reporters get their updates.
--
-- Run each block SEPARATELY in the Supabase SQL editor: it keeps only the
-- LAST result set of a multi-statement script (see the house note in
-- diagnostics/README.md).

-- ── 1. Neither citizen trigger consults is_anonymous any more ──────────────
-- EXPECT: 2 rows, code_gates_on_anon = false for both,
--         still_requires_an_account = true for both.
--
-- COMMENTS ARE STRIPPED FIRST, and that is not cosmetic. Both function bodies
-- EXPLAIN at length why is_anonymous is deliberately not consulted, so a naive
-- `position('is_anonymous' in pg_get_functiondef(...))` matches the prose
-- defending the guarantee and reports a false failure. This bit once already:
-- the first run after applying 20260901000002 flagged
-- notify_report_update_decision as still gated when its WHERE clause was
-- clean. Search the CODE, never the definition.
with stripped as (
  select p.proname,
         regexp_replace(pg_get_functiondef(p.oid), '--[^
]*', '', 'g') as code
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('notify_report_update_decision',
                       'notify_citizen_of_approved_insert')
)
select proname,
       (position('is_anonymous' in code) > 0)        as code_gates_on_anon,
       (position('user_id is not null' in code) > 0) as still_requires_an_account
  from stripped
 order by proname;

-- ── 2. Both triggers are still attached and enabled ────────────────────────
-- EXPECT: 4 rows on report_updates, all 'enabled'. This migration replaces
-- function BODIES only; a missing trigger here means something else dropped it.
select t.tgname, p.proname,
       case when t.tgenabled = 'D' then 'DISABLED' else 'enabled' end as state
  from pg_trigger t
  join pg_proc p on p.oid = t.tgfoid
 where t.tgrelid = 'public.report_updates'::regclass
   and not t.tgisinternal
 order by t.tgname;

-- ── 3. The containment that makes this safe is untouched ───────────────────
-- A notification is readable ONLY by its addressee. EXPECT users_read_own to
-- be the only SELECT policy, and its USING to compare auth.uid() to user_id.
-- If a staff/admin SELECT policy ever appears here, revisit this migration:
-- the whole safety argument rests on this row going to one person.
select polname, polcmd, pg_get_expr(polqual, polrelid) as using_expr
  from pg_policy
 where polrelid = 'public.notifications'::regclass
   and polcmd in ('r', '*')
 order by polname;

-- ── 4. The citizen's read on their own updates still resolves on ownership ─
-- EXPECT report_updates_read to contain owns_report(report_id) and NOT
-- is_anonymous. This is what the fix aligns the notification with: the
-- database already shows these rows to an anonymous reporter.
select polname, pg_get_expr(polqual, polrelid) as using_expr
  from pg_policy
 where polrelid = 'public.report_updates'::regclass
   and polcmd in ('r', '*')
 order by polname;

-- ── 5. owns_report still ignores is_anonymous ──────────────────────────────
-- EXPECT ignores_anonymity = true. If this ever becomes false, an anonymous
-- reporter has lost their own report and this migration's premise is gone.
select (position('is_anonymous' in
                 pg_get_functiondef('public.owns_report(uuid)'::regprocedure)) = 0)
         as ignores_anonymity;
