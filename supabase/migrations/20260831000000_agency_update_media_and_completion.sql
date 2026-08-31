-- ============================================================================
-- 20260831000000  Agency updates carry photos, and a completion carries words
-- ============================================================================
-- Two gaps left open by 20260829000001/20260829000000, both of which shipped
-- as deliberate limitations and both of which turned out to be wrong in use.
--
-- ── GAP 1: an agency update is text only ───────────────────────────────────
-- §10 of 20260829000001 says it outright: "The agency has no account and
-- therefore cannot upload — an agency update is text only." That reasoned from
-- the credential, not from the need. The agency IS the party standing at the
-- pothole with a phone; a progress update from them without a photo is the one
-- update in this system that most needs one.
--
-- The account is not what should gate the upload — the PIN is. This adds
-- `attach_endorsement_update_media`, callable ONLY by the service role (i.e.
-- from the post-endorsement-media Edge Function, which re-checks the PIN before
-- calling), so no anon write policy is opened on storage.objects or on
-- report_update_media. anon still holds exactly the EXECUTE grants it had.
--
-- ── GAP 2: "Mark Completed" completes in one tap ───────────────────────────
-- advance_endorsement(token, pin) took nothing but a PIN and drove the report
-- to `resolved`. The citizen got a status change and no account of what was
-- actually done.
--
-- Worse, it collided with §11 of 20260829000001: the citizen's SELECT on
-- report_resolution_media now requires an APPROVED COMPLETION UPDATE to exist,
-- and the agency path created none — so an agency completion showed the citizen
-- a resolved report with nothing whatsoever attached to it.
--
-- advance_endorsement gains an optional p_body. On the received → completed
-- transition it is REQUIRED, and it posts a `completion` update (pending
-- approval, like every other agency word) in the same transaction as the state
-- change. The endorsed → received transition is unchanged: there is nothing to
-- narrate about receiving a letter.
--
-- The two-argument signature is KEPT as a thin forwarder. Removing it would
-- break any installed app build that still calls it — the same reasoning that
-- kept the OTP grant in place.
--
-- Rollback: supabase/rollback/20260831000000_agency_update_media_and_completion_rollback.sql
-- Verify:   supabase/diagnostics/verify_20260831000000.sql
-- ============================================================================

begin;

-- ── 1. Media rows may be authored by an account-less agency ────────────────
-- uploaded_by references auth.users and is already nullable; the constraint
-- that mattered was the INSERT policy's `uploaded_by = auth.uid()`, which no
-- definer function is subject to. Nothing structural to change — the column is
-- documented instead, so the null reads as "an office, not a person", the same
-- shape report_updates.author_id already uses.
comment on column public.report_update_media.uploaded_by is
  'The account that uploaded this photo, or NULL when an account-less agency '
  'posted it through the scan page (attach_endorsement_update_media).';

-- ── 2. Attach media to an agency update ────────────────────────────────────
-- Service-role only. The Edge Function has ALREADY verified the PIN and
-- uploaded the object; this records the row and re-asserts the things the
-- function cannot be trusted to have got right on its own: that the update
-- belongs to the endorsement the token names, that the agency wrote it, and
-- that no admin has decided it yet.
--
-- Taking the token rather than a bare update id is what makes those checks
-- possible. An update id alone would let a caller attach a photo to any update
-- in the system.
create or replace function public.attach_endorsement_update_media(
  p_token        text,
  p_update       uuid,
  p_storage_path text,
  p_mime_type    text default null
)
returns json
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  e    public.report_endorsements%rowtype;
  u    public.report_updates%rowtype;
  v_id uuid;
begin
  select * into e
    from public.report_endorsements
   where token = p_token;

  if not found then
    return json_build_object('ok', false, 'error', 'invalid_token');
  end if;

  if e.state = 'withdrawn' then
    return json_build_object('ok', false, 'error', 'withdrawn');
  end if;

  select * into u
    from public.report_updates
   where id = p_update;

  if not found then
    return json_build_object('ok', false, 'error', 'unknown_update');
  end if;

  -- The update must belong to the report this token endorses, and must be one
  -- the agency itself wrote. Without both, a leaked token could bolt a photo
  -- onto an LGU office's update.
  if u.report_id is distinct from e.report_id
     or u.author_role is distinct from 'agency' then
    return json_build_object('ok', false, 'error', 'not_yours');
  end if;

  -- A decided update is a closed record. Photos attach only while it is still
  -- waiting on an admin, so what the admin approves is what the citizen sees.
  if u.status is distinct from 'pending_approval' then
    return json_build_object('ok', false, 'error', 'already_reviewed');
  end if;

  -- Cap per update. The Edge Function enforces the same limit, but a limit only
  -- the caller enforces is not a limit.
  if (select count(*) from public.report_update_media
       where update_id = p_update) >= 4 then
    return json_build_object('ok', false, 'error', 'too_many_media');
  end if;

  insert into public.report_update_media
    (update_id, storage_path, mime_type, uploaded_by)
  values (p_update, p_storage_path, p_mime_type, null)
  returning id into v_id;

  return json_build_object('ok', true, 'id', v_id);
end;
$function$;

-- Service role ONLY. Not anon, not authenticated: the whole point of routing
-- this through an Edge Function is that the PIN is re-checked somewhere the
-- client cannot skip.
revoke all on function
  public.attach_endorsement_update_media(text, uuid, text, text)
  from public, anon, authenticated;
grant execute on function
  public.attach_endorsement_update_media(text, uuid, text, text)
  to service_role;

-- ── 3. Verify a PIN without spending a transition ──────────────────────────
-- The Edge Function needs to know the PIN is right BEFORE it accepts several
-- megabytes of photo. It cannot call post_endorsement_update to find out — that
-- would post an update — and it must not be handed a way to test PINs for free,
-- so this consumes an attempt and honours the lockout exactly like every other
-- PIN path here.
--
-- Service role only, for the same reason as §2.
create or replace function public.verify_endorsement_pin(
  p_token text,
  p_pin   text
)
returns json
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  e      public.report_endorsements%rowtype;
  v_left integer;
  c_max_attempts constant integer := 5;
begin
  select * into e
    from public.report_endorsements
   where token = p_token
   for update;

  if not found then
    return json_build_object('ok', false, 'error', 'invalid_token');
  end if;

  if e.state = 'withdrawn' then
    return json_build_object('ok', false, 'error', 'withdrawn');
  end if;

  if e.locked_until is not null and e.locked_until > now() then
    return json_build_object('ok', false, 'error', 'locked',
                             'locked_until', e.locked_until);
  end if;

  if e.pin_hash is distinct from extensions.crypt(coalesce(p_pin, ''), e.pin_hash) then
    v_left := greatest(c_max_attempts - (e.pin_attempts + 1), 0);
    update public.report_endorsements
       set pin_attempts = pin_attempts + 1,
           locked_until = case
                            when pin_attempts + 1 >= c_max_attempts
                              then now() + interval '15 minutes'
                            else locked_until
                          end,
           updated_at   = now()
     where id = e.id;
    return json_build_object('ok', false, 'error', 'bad_pin',
                             'attempts_left', v_left);
  end if;

  update public.report_endorsements
     set pin_attempts = 0, locked_until = null, updated_at = now()
   where id = e.id;

  return json_build_object('ok', true, 'report_id', e.report_id,
                           'state', e.state);
end;
$function$;

revoke all on function public.verify_endorsement_pin(text, text)
  from public, anon, authenticated;
grant execute on function public.verify_endorsement_pin(text, text)
  to service_role;

-- ── 4. A completion must say what was done ─────────────────────────────────
-- New three-argument form. p_body is required on received → completed and
-- ignored on endorsed → received.
create or replace function public.advance_endorsement(
  p_token text,
  p_pin   text,
  p_body  text
)
returns json
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  e        public.report_endorsements%rowtype;
  v_next   text;
  v_rows   integer;
  v_left   integer;
  v_update uuid;
  c_max_attempts constant integer := 5;
begin
  select * into e
    from public.report_endorsements
   where token = p_token
   for update;

  if not found then
    return json_build_object('ok', false, 'error', 'invalid_token');
  end if;

  -- Checked before the lock and before the PIN: a withdrawn endorsement is not
  -- a credential problem and must not consume attempts or report a lockout.
  if e.state = 'withdrawn' then
    return json_build_object('ok', false, 'error', 'withdrawn',
                             'state', 'withdrawn');
  end if;

  if e.locked_until is not null and e.locked_until > now() then
    return json_build_object('ok', false, 'error', 'locked',
                             'locked_until', e.locked_until);
  end if;

  if e.state = 'completed' then
    return json_build_object('ok', false, 'error', 'already_completed',
                             'state', 'completed');
  end if;

  -- Checked BEFORE the PIN so a completion with no note does not burn an
  -- attempt: a missing note is the officer's omission, not a bad credential.
  if e.state = 'received' and coalesce(btrim(p_body), '') = '' then
    return json_build_object('ok', false, 'error', 'body_required');
  end if;

  if e.pin_hash is distinct from extensions.crypt(coalesce(p_pin, ''), e.pin_hash) then
    v_left := greatest(c_max_attempts - (e.pin_attempts + 1), 0);
    update public.report_endorsements
       set pin_attempts = pin_attempts + 1,
           locked_until = case
                            when pin_attempts + 1 >= c_max_attempts
                              then now() + interval '15 minutes'
                            else locked_until
                          end,
           updated_at   = now()
     where id = e.id;
    return json_build_object('ok', false, 'error', 'bad_pin',
                             'attempts_left', v_left);
  end if;

  v_next := case e.state when 'endorsed' then 'received'
                         when 'received' then 'completed' end;

  update public.report_endorsements
     set state        = v_next,
         received_at  = case when v_next = 'received'  then now() else received_at  end,
         completed_at = case when v_next = 'completed' then now() else completed_at end,
         pin_attempts = 0,
         locked_until = null,
         updated_at   = now()
   where id = e.id
     and state = e.state;

  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    return json_build_object('ok', false, 'error', 'already_advanced',
                             'state', e.state);
  end if;

  insert into public.report_endorsement_events
    (endorsement_id, report_id, from_state, to_state, actor)
  values (e.id, e.report_id, e.state, v_next, 'agency');

  update public.reports
     set status = case when v_next = 'received' then 'in_progress' else 'resolved' end
   where id = e.report_id;

  -- The completion account, in the SAME transaction as the state change. If the
  -- update cannot be written the completion does not happen either — a resolved
  -- report with no explanation is the exact failure this migration exists to
  -- remove, and half of it is worse than none of it.
  --
  -- pending_approval like every other agency word: the admin still decides what
  -- reaches the citizen. §11 of 20260829000001 keys the citizen's view of
  -- completion PHOTOS on an approved completion update existing, so approving
  -- this row is also what releases the gallery.
  if v_next = 'completed' then
    insert into public.report_updates
      (report_id, body, kind, status, author_id, author_role, author_name)
    values
      (e.report_id, btrim(p_body), 'completion', 'pending_approval',
       null, 'agency', e.agency)
    returning id into v_update;
  end if;

  return json_build_object('ok', true, 'state', v_next,
                           'update_id', v_update);
end;
$function$;

revoke all on function public.advance_endorsement(text, text, text) from public;
grant execute on function public.advance_endorsement(text, text, text)
  to anon, authenticated;

-- ── 5. The old two-argument form still resolves ────────────────────────────
-- An installed app build calls advance_endorsement(text, text). Dropping it
-- would 404 every one of those clients the moment this is applied. It forwards
-- with a null body, which the new form refuses on a completion — the right
-- answer for an old client: it cannot supply what is now required, and it
-- should be told so rather than silently completing without an account.
create or replace function public.advance_endorsement(
  p_token text,
  p_pin   text
)
returns json
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  return public.advance_endorsement(p_token, p_pin, null);
end;
$function$;

revoke all on function public.advance_endorsement(text, text) from public;
grant execute on function public.advance_endorsement(text, text)
  to anon, authenticated;

commit;

-- Expected after this migration:
--   * attach_endorsement_update_media and verify_endorsement_pin exist and are
--     executable by service_role ONLY.
--   * advance_endorsement has TWO overloads; both are anon-executable.
--   * advance_endorsement(token, pin, '') on a `received` row returns
--     body_required and does NOT consume a PIN attempt.
--   * A successful completion inserts one pending_approval `completion` row in
--     report_updates authored by 'agency'.
--   * anon holds no new table privilege.
