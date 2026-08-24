-- ─────────────────────────────────────────────────────────────────────────────
-- 20260823000000  Scope the OTP RPC trio to the CALLER; de-fang can_send_otp
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Audit 2026-08-23. Four SECURITY DEFINER RPCs took a caller-supplied
-- `p_identifier` and acted on it with NO ownership check of any kind. Live
-- grants (has_function_privilege, measured):
--
--     clear_otp_failures   authenticated=t  anon=f
--     record_otp_failure   authenticated=t  anon=f
--     can_verify_otp       authenticated=t  anon=f
--     can_send_otp         authenticated=t  anon=T   <-- anonymous
--
-- What that allowed, against ANY email, from any account (or none):
--
--   clear_otp_failures  DELETEs the victim's otp_failures rows -> the 5-attempt
--                       OTP lockout is bypassable: try 4 codes, clear, repeat.
--   record_otp_failure  INSERTs failures for the victim -> locks them out of
--                       password reset for an hour, in one call per failure.
--   can_verify_otp      returns the victim's failures_count -> lockout oracle.
--   can_send_otp        consumes the victim's OTP-send budget (check_rate_limit
--                       INSERTs on every allowed call) -> five anonymous calls
--                       deny a real user password recovery for an hour.
--
-- ── WHY NOT SIMPLY `REVOKE ... FROM authenticated` ────────────────────────────
-- Because it would BREAK EVERY APP BUILD ALREADY INSTALLED. In both callers the
-- RPC sits inside the try block, on the success path, BEFORE navigation:
--
--   change_password_verify_screen.dart:171-186   admin_change_password.dart:150-153
--     if (200 && success) {                        if (200 && success) {
--       await rpc('clear_otp_failures', ...);        await rpc('clear_otp_failures',...);
--       ... Navigator.push(NewPassword) ...          ... _step = newPassword ...
--     }                                            }
--   } catch (_) { _triggerError(); }              } catch (_) { _error = ... }
--
-- A 403 from the revoked RPC throws, lands in that catch, and the user is told
-- their correct code was wrong — after the OTP has already been consumed. The
-- fix therefore has to keep the signatures, the grants, and the return shapes
-- EXACTLY as they are, and change only WHOSE rows are touched.
--
-- ── THE FIX ───────────────────────────────────────────────────────────────────
-- The three authenticated RPCs now derive the identifier from `auth.uid()` and
-- IGNORE `p_identifier` entirely. Every existing caller already passes its own
-- signed-in email, so behaviour for legitimate use is identical; a caller that
-- passes someone else's email silently operates on its own rows instead of
-- erroring, which keeps old clients working.
--
-- can_send_otp cannot be caller-scoped: signup and password-reset call it while
-- anonymous, so there is no auth.uid() to scope to. It is made READ-ONLY
-- instead. See the note on that function below for why this loses nothing.
--
-- Signatures, return types, JSONB keys and grants are all unchanged.
-- Idempotent (CREATE OR REPLACE only). Rollback:
--   supabase/rollback/20260823000000_otp_rpc_caller_scoping_rollback.sql
-- ─────────────────────────────────────────────────────────────────────────────

begin;

-- ── 1. clear_otp_failures ────────────────────────────────────────────────────
-- Clears the CALLER'S OWN failure rows. p_identifier is accepted for signature
-- compatibility and deliberately ignored.
create or replace function public.clear_otp_failures(p_identifier text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
DECLARE
  v_email text;
BEGIN
  SELECT lower(trim(u.email)) INTO v_email
    FROM auth.users u WHERE u.id = auth.uid();

  -- No signed-in caller (service_role, or a null JWT): do nothing rather than
  -- raise. Raising here would surface as a failed password change in the
  -- clients described in the header.
  IF v_email IS NULL THEN RETURN; END IF;

  DELETE FROM public.otp_failures WHERE email = v_email;
  DELETE FROM public.rate_limits  WHERE key   = 'otp_failure:' || v_email;
END;
$function$;

-- ── 2. record_otp_failure ────────────────────────────────────────────────────
-- Records a failure against the CALLER'S OWN identity, so it can no longer be
-- used to lock another account out of password recovery.
create or replace function public.record_otp_failure(p_identifier text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
DECLARE
  v_email text;
BEGIN
  SELECT lower(trim(u.email)) INTO v_email
    FROM auth.users u WHERE u.id = auth.uid();

  IF v_email IS NULL THEN RETURN; END IF;

  INSERT INTO public.otp_failures(email, created_at) VALUES (v_email, now());
END;
$function$;

-- ── 3. can_verify_otp ────────────────────────────────────────────────────────
-- Reports the CALLER'S OWN lockout state. Same JSONB shape as before
-- (allowed / failures_count / message) — both clients read `allowed` and
-- `message`, so the contract must not move.
create or replace function public.can_verify_otp(p_identifier text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
DECLARE
  v_email    text;
  v_failures int;
  v_allowed  boolean;
BEGIN
  SELECT lower(trim(u.email)) INTO v_email
    FROM auth.users u WHERE u.id = auth.uid();

  -- Unknown caller: report "allowed" so no legitimate flow is hard-blocked by
  -- this advisory pre-flight. The authoritative 5-attempt gate lives in the
  -- reset-verify-otp / verify-email-otp Edge Functions, which read
  -- otp_failures directly under the service role and cannot be bypassed.
  IF v_email IS NULL THEN
    RETURN jsonb_build_object('allowed', true, 'failures_count', 0, 'message', 'OK');
  END IF;

  SELECT COUNT(*) INTO v_failures
    FROM public.otp_failures
   WHERE email = v_email
     AND created_at > now() - interval '1 hour';

  v_allowed := v_failures < 5;

  RETURN jsonb_build_object(
    'allowed',        v_allowed,
    'failures_count', v_failures,
    'message',        CASE WHEN v_allowed THEN 'OK'
                      ELSE 'Too many incorrect codes. Please try again in an hour.' END
  );
END;
$function$;

-- ── 4. can_send_otp ──────────────────────────────────────────────────────────
-- READ-ONLY from here on: it counts, it no longer INSERTs.
--
-- This one is reachable by `anon` (signup_screen.dart:478 and
-- reset_password_email_verify_screen.dart:151 both call it with no session), so
-- it cannot be scoped to auth.uid(). The abuse was that check_rate_limit()
-- INSERTs a row on every allowed call, so five anonymous calls naming a
-- victim's address exhausted that address's 5-per-hour budget and denied them
-- password recovery.
--
-- Making it non-consuming costs nothing real. It was only ever a client-side
-- PRE-FLIGHT: the enforcement a genuine attacker actually has to get past is
-- the checkRateLimit() inside send-email-otp / reset-send-otp, which runs under
-- the service role on a DIFFERENT key namespace ('send-otp:' / 'reset-send:'
-- versus this function's 'otp_send:'). An attacker who wants to send OTPs just
-- skips this RPC and posts to the Edge Function, so the consuming version
-- deterred nobody while handing anyone a denial-of-recovery primitive.
--
-- Behaviour for honest callers is unchanged: same JSONB shape, and it still
-- reports `allowed:false` while a genuine 'otp_send:' backlog is inside the
-- window. Because nothing writes those keys any more, existing rows age out and
-- it settles to a permanent `allowed:true` — an advisory gate that always
-- passes, with the real limit enforced one layer up.
create or replace function public.can_send_otp(p_identifier text, p_purpose text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
DECLARE
  v_count   integer;
  v_allowed boolean;
BEGIN
  SELECT COUNT(*) INTO v_count
    FROM public.rate_limits
   WHERE key = 'otp_send:' || p_purpose || ':' || lower(trim(p_identifier))
     AND created_at > now() - interval '1 hour';

  v_allowed := v_count < 5;

  RETURN jsonb_build_object(
    'allowed', v_allowed,
    'message', CASE WHEN v_allowed THEN 'OK'
               ELSE 'Too many OTP requests. Please wait an hour before trying again.' END
  );
END;
$function$;

commit;

-- ─────────────────────────────────────────────────────────────────────────────
-- VERIFY (run separately; the SQL editor keeps only the last result set)
-- ─────────────────────────────────────────────────────────────────────────────
-- select p.proname,
--        has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_exec,
--        has_function_privilege('anon',          p.oid, 'EXECUTE') as anon_exec,
--        pg_get_functiondef(p.oid) ilike '%auth.uid()%'            as is_caller_scoped,
--        pg_get_functiondef(p.oid) ilike '%INSERT INTO public.rate_limits%'
--                                                                  as still_consumes
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--  where n.nspname = 'public'
--    and p.proname in ('clear_otp_failures','record_otp_failure',
--                      'can_verify_otp','can_send_otp')
--  order by p.proname;
--
-- EXPECTED
--   can_send_otp        auth=t anon=t  caller_scoped=f  still_consumes=f
--   can_verify_otp      auth=t anon=f  caller_scoped=t  still_consumes=f
--   clear_otp_failures  auth=t anon=f  caller_scoped=t  still_consumes=f
--   record_otp_failure  auth=t anon=f  caller_scoped=t  still_consumes=f
