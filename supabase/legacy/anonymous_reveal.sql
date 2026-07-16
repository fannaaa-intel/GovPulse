-- ════════════════════════════════════════════════════════════════════════════
--  Anonymous submitter reveal — guarded, audited de-anonymization
--
--  Anonymous reports / suggestions / feedback are PSEUDONYMOUS, not truly
--  anonymous: the row keeps its real `user_id`, but the identity is withheld
--  from the console. This function is the ONE sanctioned way to surface that
--  identity, for genuine abuse / emergency / legal cases — and it is guarded so
--  that even a logged-in admin cannot reveal casually:
--
--    1. Caller must be a FULL admin (user_roles.role_id = 1). Staff (role 2)
--       can never reveal.
--    2. Step-up re-auth: the caller must re-enter their OWN account password,
--       which is verified server-side against auth.users (bcrypt). This defends
--       against an open/stolen session — the click alone is not enough.
--    3. A non-empty reason is required.
--    4. Every reveal is written to admin_activity_log (who, when, which
--       submission, why). The log NEVER stores the revealed person's name —
--       only the submission reference — because the log is readable by staff
--       too, and staff must not be able to read identities out of it.
--
--  Requires: profanity/admin role model (user_roles), admin_activity_log.sql,
--            pgcrypto (ships with Supabase, in the `extensions` schema).
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.admin_reveal_submitter(
  p_source     text,   -- 'report' | 'suggestion' | 'feedback'
  p_id         uuid,   -- the submission id
  p_password   text,   -- the CALLER's own account password (step-up re-auth)
  p_reason     text,   -- why the identity is being revealed (required, logged)
  p_actor_name text default null  -- denormalised admin name for the log
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_actor    uuid := auth.uid();
  v_stored   text;
  v_uid      uuid;
  v_is_anon  boolean;
  v_first    text;
  v_last     text;
  v_photo    text;
  v_phone    text;
  v_ref      text;
begin
  -- 1 ── Full admin only (role 1). Staff (role 2) and citizens are rejected.
  if not exists (
    select 1 from public.user_roles
    where user_id = v_actor and role_id = 1
  ) then
    raise exception 'Only a full admin can reveal an anonymous submitter'
      using errcode = '42501';
  end if;

  -- 2 ── Reason required.
  if p_reason is null or length(btrim(p_reason)) < 3 then
    raise exception 'A reason is required to reveal an identity';
  end if;

  -- 3 ── Step-up re-authentication: verify the caller's own password.
  select encrypted_password into v_stored
    from auth.users where id = v_actor;
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

  -- 5 ── Resolve the identity (only after every gate has passed). Name + photo
  --       come from public_user_profiles (works for any account); the phone
  --       number lives in citizen_details and may be null if unverified.
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
    (v_actor, p_actor_name, 'identity_revealed', p_source, v_ref, btrim(p_reason));

  -- 7 ── Return the identity to the caller only.
  return jsonb_build_object(
    'user_id',    v_uid,
    'name',       btrim(coalesce(v_first, '') || ' ' || coalesce(v_last, '')),
    'photo_path', v_photo,
    'phone',      v_phone
  );
end;
$$;

grant execute on function
  public.admin_reveal_submitter(text, uuid, text, text, text)
  to authenticated;
