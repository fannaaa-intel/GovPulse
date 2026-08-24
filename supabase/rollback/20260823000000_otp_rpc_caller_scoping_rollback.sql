-- ─────────────────────────────────────────────────────────────────────────────
-- ROLLBACK for 20260823000000_otp_rpc_caller_scoping.sql
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Restores the EXACT pre-migration bodies of the four OTP RPCs, captured live
-- from pg_get_functiondef() on 2026-08-23 before any change was applied.
--
-- ⚠ RESTORING THESE RE-OPENS ALL FOUR HOLES:
--     clear_otp_failures  any signed-in user clears ANY email's OTP lockout
--     record_otp_failure  any signed-in user locks ANY email out for an hour
--     can_verify_otp      any signed-in user reads ANY email's failure count
--     can_send_otp        ANY ANONYMOUS caller burns ANY email's send budget
--
-- Only run this if the forward migration actually broke a real flow. Grants and
-- signatures are untouched by both directions, so nothing here needs re-granting.
-- ─────────────────────────────────────────────────────────────────────────────

begin;

create or replace function public.clear_otp_failures(p_identifier text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
BEGIN
  IF p_identifier LIKE '%@%' THEN
    DELETE FROM public.otp_failures WHERE email = lower(trim(p_identifier));
  ELSE
    DELETE FROM public.rate_limits WHERE key = 'otp_failure:' || lower(trim(p_identifier));
  END IF;
END;
$function$;

create or replace function public.record_otp_failure(p_identifier text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
BEGIN
  IF p_identifier LIKE '%@%' THEN
    INSERT INTO public.otp_failures(email, created_at) VALUES (lower(trim(p_identifier)), now());
  ELSE
    INSERT INTO public.rate_limits(key, created_at) VALUES ('otp_failure:' || lower(trim(p_identifier)), now());
  END IF;
END;
$function$;

create or replace function public.can_verify_otp(p_identifier text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
DECLARE
  v_failures int;
  v_allowed  boolean;
BEGIN
  IF p_identifier LIKE '%@%' THEN
    SELECT COUNT(*) INTO v_failures FROM public.otp_failures
    WHERE email = lower(trim(p_identifier)) AND created_at > now() - interval '1 hour';
  ELSE
    SELECT COUNT(*) INTO v_failures FROM public.rate_limits
    WHERE key = 'otp_failure:' || lower(trim(p_identifier)) AND created_at > now() - interval '1 hour';
  END IF;
  v_allowed := v_failures < 5;
  RETURN jsonb_build_object(
    'allowed', v_allowed,
    'failures_count', v_failures,
    'message', CASE WHEN v_allowed THEN 'OK' ELSE 'Too many incorrect codes. Please try again in an hour.' END
  );
END;
$function$;

create or replace function public.can_send_otp(p_identifier text, p_purpose text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
DECLARE v_allowed boolean;
BEGIN
  v_allowed := public.check_rate_limit('otp_send:' || p_purpose || ':' || lower(trim(p_identifier)), 5, 3600);
  RETURN jsonb_build_object(
    'allowed', v_allowed,
    'message', CASE WHEN v_allowed THEN 'OK' ELSE 'Too many OTP requests. Please wait an hour before trying again.' END
  );
END;
$function$;

commit;
