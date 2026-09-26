-- ════════════════════════════════════════════════════════════════════════════
--  Anonymous reveal: password + emailed code (two-step)
--
--  Before: admin_reveal_submitter was callable straight from the app by any
--  signed-in full admin, gated only by the caller's password. Anyone holding
--  the admin password (shared PC, saved browser password, leak) could unmask
--  every anonymous reporter, and nothing limited wrong-password guesses.
--
--  After: the reveal can ONLY run through the `reveal-identity` edge function,
--  which requires (1) the admin's password AND (2) a one-time code emailed to
--  the admin's own address, locks the admin out after 5 failures in 15 minutes,
--  and logs every failure as well as every success.
--
--  How the "only through the edge function" guarantee is made: both functions
--  below are EXECUTE-able by service_role only. The app's `authenticated` role
--  can no longer call the reveal at all, so there is no way to skip the code
--  step by calling the RPC directly. Because service_role has no auth.uid(),
--  the caller's id is passed in (p_actor); the edge function takes it from the
--  verified JWT, never from the request body.
--
--  The old 5-arg signature is DROPPED, not left beside the new one: leaving it
--  would leave the password-only path open.
--
--  Supersedes supabase/legacy/anonymous_reveal.sql.
-- ════════════════════════════════════════════════════════════════════════════

drop function if exists public.admin_reveal_submitter(text, uuid, text, text, text);

-- Step 1 helper: is this the admin's password? Used before a code is emailed so
-- a wrong password never triggers an email.
create or replace function public.admin_reveal_check_password(
  p_actor    uuid,
  p_password text
)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_stored text;
begin
  if not exists (
    select 1 from public.user_roles where user_id = p_actor and role_id = 1
  ) then
    return false;
  end if;
  select encrypted_password into v_stored from auth.users where id = p_actor;
  return v_stored is not null
     and v_stored = crypt(coalesce(p_password, ''), v_stored);
end;
$$;

create or replace function public.admin_reveal_submitter(
  p_actor      uuid,   -- the admin, from the edge function's verified JWT
  p_source     text,   -- 'report' | 'suggestion' | 'feedback'
  p_id         uuid,   -- the submission id
  p_password   text,   -- the admin's own password (checked again here)
  p_reason     text,   -- why the identity is being revealed (required, logged)
  p_actor_name text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_stored   text;
  v_uid      uuid;
  v_is_anon  boolean;
  v_first    text;
  v_last     text;
  v_photo    text;
  v_phone    text;
  v_ref      text;
begin
  -- 1 ── Full admin only (role 1).
  if p_actor is null or not exists (
    select 1 from public.user_roles
    where user_id = p_actor and role_id = 1
  ) then
    raise exception 'Only a full admin can reveal an anonymous submitter'
      using errcode = '42501';
  end if;

  -- 2 ── Reason required.
  if p_reason is null or length(btrim(p_reason)) < 3 then
    raise exception 'A reason is required to reveal an identity';
  end if;

  -- 3 ── Password, re-checked here so the edge function is not the only gate.
  select encrypted_password into v_stored
    from auth.users where id = p_actor;
  if v_stored is null
     or v_stored <> crypt(coalesce(p_password, ''), v_stored) then
    raise exception 'Incorrect password' using errcode = '28P01';
  end if;

  -- 4 ── Load the submission's real user_id + anon flag.
  if p_source = 'report' then
    select user_id, is_anonymous into v_uid, v_is_anon
      from public.reports where id = p_id;
  elsif p_source = 'suggestion' then
    select user_id, is_anonymous into v_uid, v_is_anon
      from public.suggestions where id = p_id;
  elsif p_source = 'feedback' then
    select user_id, is_anonymous into v_uid, v_is_anon
      from public.feedbacks where id = p_id;
  else
    raise exception 'Unknown submission type: %', p_source;
  end if;

  if v_uid is null then
    raise exception 'Submission not found (or it carries no submitter)';
  end if;

  -- 5 ── Resolve the identity (only after every gate has passed).
  select first_name, last_name, profile_photo_path
    into v_first, v_last, v_photo
    from public.public_user_profiles where user_id = v_uid;

  select contact_number into v_phone
    from public.citizen_details where user_id = v_uid;

  -- 6 ── Audit. Store the submission REFERENCE, never the revealed name — the
  --       log is readable by staff, who must not learn identities from it.
  v_ref := p_source || ' ' || upper(substr(p_id::text, 1, 8));
  insert into public.admin_activity_log
    (actor_id, actor_name, action, target_type, target_label, detail)
  values
    (p_actor, p_actor_name, 'identity_revealed', p_source, v_ref, btrim(p_reason));

  return jsonb_build_object(
    'user_id',    v_uid,
    'name',       btrim(coalesce(v_first, '') || ' ' || coalesce(v_last, '')),
    'photo_path', v_photo,
    'phone',      v_phone
  );
end;
$$;

revoke all on function public.admin_reveal_check_password(uuid, text)
  from public, anon, authenticated;
revoke all on function public.admin_reveal_submitter(uuid, text, uuid, text, text, text)
  from public, anon, authenticated;
grant execute on function public.admin_reveal_check_password(uuid, text)
  to service_role;
grant execute on function public.admin_reveal_submitter(uuid, text, uuid, text, text, text)
  to service_role;

-- Failure counting reads the log by (actor, action, time). Tiny table today;
-- the index keeps the lockout check cheap as the log grows.
create index if not exists admin_activity_log_actor_action_time_idx
  on public.admin_activity_log (actor_id, action, created_at desc);
