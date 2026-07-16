-- ════════════════════════════════════════════════════════════════════════════
--  Rate-limit fix: anonymous submissions bypassed the daily caps.
--
--  Two holes, same root cause — keying the limit on a column that is NULL for an
--  anonymous submission instead of on the authenticated user.
--
--  §1 rl_reports   — opened with `IF NEW.user_id IS NULL THEN RETURN NEW; END IF;`
--                    so an anonymous report SKIPPED the 5/day cap entirely.
--                    Unlimited anonymous reports: the spam path that matters most.
--  §2 rl_feedbacks — built `'feedback:' || auth.uid()::text` with no guard. In
--                    Postgres, concatenating NULL yields NULL, so an unauthenticated
--                    insert passed a NULL key into enforce_rate_limit() instead of
--                    limiting anything. Likely unreachable through RLS today, but it
--                    was the only one of the three with no guard at all.
--
--  THE FIX IS NOT NEW — rl_suggestions already solved exactly this and says so:
--
--      -- Use auth.uid() for rate limiting (always available for authenticated users)
--      -- This works for both anonymous (user_id=null) and named submissions
--      IF auth.uid() IS NOT NULL THEN
--
--  Someone hit the null-user_id hole on suggestions, fixed it, and never carried
--  it back. Both functions below now use that identical proven shape.
--
--  KEY COMPATIBILITY: for a NAMED submission auth.uid() = new.user_id, so the
--  rate-limit key ('report:<uuid>') is unchanged and no existing counter resets.
--  What changes: a user's anonymous reports now count toward the SAME daily 5 as
--  their named ones — which is the point. Anonymity is about hiding identity from
--  other citizens, not about escaping a spam cap.
--
--  LIMITS ARE UNCHANGED (5 reports/day, 5 feedback/day) and still match the
--  hardcoded messages in report_issue_screen.dart / feedback_screen.dart.
--
--  Triggers are deliberately NOT recreated: `create or replace function` keeps
--  the existing trigger bindings, and their definitions aren't in this repo — so
--  recreating them would mean guessing at something already working.
--
--  Idempotent. Run once. Independent of the notification_deeplink_targets files.
-- ════════════════════════════════════════════════════════════════════════════

-- ── §1  Reports — close the anonymous bypass ─────────────────────────────────
create or replace function public.rl_reports()
returns trigger
language plpgsql security definer set search_path = public
as $function$
begin
  -- Key on auth.uid(), NOT new.user_id. An anonymous report stores user_id =
  -- null (see notify_citizen_report_decision, which guards for exactly that),
  -- so the old `if new.user_id is null then return new` handed anonymous
  -- submitters an unlimited quota. auth.uid() is present for any authenticated
  -- submitter, anonymous or named — same approach as rl_suggestions.
  if auth.uid() is not null then
    perform public.enforce_rate_limit(
      'report:' || auth.uid()::text,
      5,
      86400,
      'You''ve reached the daily limit for reports. Please try again tomorrow.'
    );
  end if;
  return new;
end;
$function$;

-- ── §2  Feedback — guard the key so it can never be NULL ─────────────────────
create or replace function public.rl_feedbacks()
returns trigger
language plpgsql security definer set search_path = public
as $function$
begin
  -- Without this guard, an unauthenticated insert makes the key
  -- ('feedback:' || null) evaluate to NULL — enforce_rate_limit then receives a
  -- null key rather than limiting anything.
  if auth.uid() is not null then
    perform public.enforce_rate_limit(
      'feedback:' || auth.uid()::text,
      5,       -- max 5 per window
      86400,   -- 24-hour window (seconds)
      'You''ve reached the daily limit for feedback. Please try again tomorrow.'
    );
  end if;
  return new;
end;
$function$;
