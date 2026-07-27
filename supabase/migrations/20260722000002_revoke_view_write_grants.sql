-- CRITICAL — Revoke write privileges on every view in `public`.
--
-- ══ THE VULNERABILITY, AND IT WAS MINE ═════════════════════════════════════
-- Migrations 20260721000007 and 20260722000000 each created a SECURITY DEFINER
-- view and wrote:
--
--     revoke all on public.<view> from public, anon;
--     grant select on public.<view> to authenticated;
--
-- That revoke names `public` and `anon` but NOT `authenticated`. Supabase's
-- default privileges grant ALL on new objects in `public` to `authenticated`
-- explicitly, so the default survived and the subsequent `grant select` added
-- nothing it did not already hold. Both views shipped with INSERT, UPDATE,
-- DELETE, TRUNCATE, REFERENCES and TRIGGER granted to every logged-in user.
--
-- Because these views are DEFINER (security_invoker = false), a write through
-- them executes as the view OWNER and bypasses base-table RLS entirely.
--
-- ══ REPRODUCED LIVE, AS THE REAL TEST STAFF ACCOUNT ════════════════════════
-- In a rolled-back transaction on 2026-07-22:
--
--   select user_id from staff_reports_view where is_anonymous   ->  NULL   (control working)
--   update staff_reports_view set is_anonymous = false ...      ->  SUCCEEDED
--   select user_id from staff_reports_view ...                  ->  76159d2c-…  (REPORTER IDENTIFIED)
--   delete from staff_reports_view where id = ...               ->  SUCCEEDED
--
-- Two statements defeat the entire reports-anonymity migration. `is_anonymous`
-- is a plain passthrough column and therefore auto-updatable; `user_id` and the
-- contact columns are CASE expressions and are not directly writable, but
-- flipping the flag they switch on achieves the same result. The identical path
-- exists on staff_tickets_view for the five contact columns.
--
-- DELETE is worse than a bypass: it is a capability staff NEVER HAD. There was
-- no staff DELETE policy on `reports` or `concern_tickets` at any point. The
-- view introduced one. That is a widening shipped under a migration whose
-- stated purpose was reduction.
--
-- INSERT happened to fail (`cannot insert into column "user_id" of view` —
-- user_id is a CASE expression, and it is NOT NULL on the base table), but that
-- is an accident of the view's shape, not a control.
--
-- ══ SCOPE — ALL SIX VIEWS, NOT JUST THE TWO ════════════════════════════════
-- The sweep found the same excess grants on every view in `public`:
--   staff_reports_view      DEFINER  <- critical, exploit reproduced
--   staff_tickets_view      DEFINER  <- critical, same shape
--   community_feed          invoker
--   public_user_profiles    invoker
--   reports_public          invoker
--   staff_suggestions_view  invoker
-- The four invoker views are far lower severity — a write through them is still
-- checked against the base table's RLS for the calling user — but TRUNCATE and
-- DELETE grants to `authenticated` are wrong regardless, and leaving them would
-- leave the same trap armed for the next view someone converts to definer.
--
-- ══ THE FIX ════════════════════════════════════════════════════════════════
-- `revoke all` naming EVERY grantee, then re-grant SELECT to exactly the roles
-- that need it. Idempotent and safe to re-run.
--
-- STANDING RULE for anything added later: a `revoke` that does not name
-- `authenticated` does not revoke Supabase's default grant. Every future view
-- must revoke from `public, anon, authenticated` and then grant back only
-- SELECT. diagnostics/verify_20260722000002_view_grants.sql asserts this for
-- every view in the schema, so a regression fails loudly instead of shipping.

-- ── 1. Views: strip everything, re-grant SELECT only ───────────────────────
-- Staff-facing views: authenticated SELECT only. Neither is anon-readable
-- (verified: anon holds no SELECT on either today), and neither should be.
revoke all on public.staff_reports_view from public, anon, authenticated;
grant  select on public.staff_reports_view to authenticated;

revoke all on public.staff_tickets_view from public, anon, authenticated;
grant  select on public.staff_tickets_view to authenticated;

-- Pre-existing staff view. anon currently holds SELECT; it is security_invoker
-- so anon already resolves to zero rows, making the grant meaningless as well
-- as wrong. Removing it changes no behaviour and is a strict reduction.
revoke all on public.staff_suggestions_view from public, anon, authenticated;
grant  select on public.staff_suggestions_view to authenticated;

-- Public-facing views: anon SELECT is PRESERVED — these back guest-visible
-- surfaces and the community feed. Only the write grants are removed.
revoke all on public.community_feed from public, anon, authenticated;
grant  select on public.community_feed to anon, authenticated;

revoke all on public.public_user_profiles from public, anon, authenticated;
grant  select on public.public_user_profiles to anon, authenticated;

revoke all on public.reports_public from public, anon, authenticated;
grant  select on public.reports_public to anon, authenticated;

-- ── 2. Functions: remove the EXECUTE grant to anon ─────────────────────────
-- Same root cause in a different role. Each migration wrote
-- `revoke all on function ... from public`, which does not remove Supabase's
-- explicit default grant to `anon`.
--
-- Most of these are harmless to an anonymous caller because they check
-- current_user_role_id() / auth.uid() internally and return false or raise —
-- but they should not be reachable, and ONE of them matters:
--
--   find_available_staff(text) is SECURITY DEFINER and bypasses RLS to read
--   admin_profiles. An anonymous caller could enumerate on-duty staff user_ids
--   by department — partially undoing 20260721000004, which existed precisely
--   to stop anon reading the officials directory and presence data.
revoke execute on function public.find_available_staff(text)          from anon, public;
revoke execute on function public.storage_path_uuid(text, int)        from anon, public;
revoke execute on function public.owns_report(uuid)                   from anon, public;
revoke execute on function public.owns_suggestion(uuid)               from anon, public;
revoke execute on function public.staff_can_see_report(uuid)          from anon, public;
revoke execute on function public.staff_claim_ticket(uuid)            from anon, public;
revoke execute on function public.staff_set_ticket_status(uuid, text) from anon, public;
revoke execute on function public.staff_touch_ticket(uuid)            from anon, public;
revoke execute on function public.staff_set_report_status(uuid, text) from anon, public;
revoke execute on function public.staff_return_to_triage(uuid)        from anon, public;
revoke execute on function public._bridge_staff_can_read_ticket_pending_msg_migration(uuid)
                                                                      from anon, public;

-- authenticated keeps EXECUTE on all of the above — the app calls them as a
-- signed-in staff member, and each enforces its own role/department check.
