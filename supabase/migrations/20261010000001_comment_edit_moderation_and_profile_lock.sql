-- 20261010000001_comment_edit_moderation_and_profile_lock.sql
--
-- Two holes found while verifying 20261010000000 (audit 2026-10-09):
--
-- 1. EDITED comments skipped AI moderation. trg_moderate_comment is AFTER
--    INSERT only, so a citizen could post something harmless, let it pass, then
--    edit it into abuse. Only the word list (trg_flag_profanity_comment) re-ran.
--    Now a body change (a) clears ai_moderated_at, so the 15-minute catch-up
--    sweep re-checks it even if the direct call times out, and (b) fires the
--    same moderate-content call an insert does. moderate-content only ever
--    RAISES a flag and never writes `body`, so its own update cannot loop.
--
-- 2. citizen_details had no server-side rules on a citizen's own UPDATE:
--    • verified_by / verified_at / provided_by_staff — set by the admin who
--      verified the person — were writable by that person.
--    • The 30-day profile-edit lock lived only in the Edit Profile screen, and
--      the citizen could also write last_profile_updated_at back to any date.
--    The lock is now enforced here with the app's exact rule: a change to any
--    field the Edit Profile screen saves starts a 30-day lock; a save that
--    changes nothing does not. Admins, the verification-approval trigger and
--    edge functions (owner / service_role) are exempt, as in 20261009000000.
--
-- VERIFIED BEFORE COMMIT: supabase/diagnostics/verify_20261010000001.sql (18/18 PASS on
-- production inside a rolled-back transaction, applied on top of 20261010000000).

-- ── 1. comment edits are re-moderated ───────────────────────────────────────
create or replace function public.reset_comment_moderation_on_edit()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  new.ai_moderated_at := null;
  return new;
end;
$$;

drop trigger if exists trg_comment_edit_reset_moderation on public.community_comments;
create trigger trg_comment_edit_reset_moderation
  before update of body on public.community_comments
  for each row
  when (old.body is distinct from new.body)
  execute function public.reset_comment_moderation_on_edit();

drop trigger if exists trg_moderate_comment_edit on public.community_comments;
create trigger trg_moderate_comment_edit
  after update of body on public.community_comments
  for each row
  when (old.body is distinct from new.body
        and new.body is not null and length(trim(new.body)) > 0)
  execute function public.moderate_content_on_insert();

-- ── 2. citizen_details: server-owned columns + the 30-day edit lock ─────────
create or replace function public.guard_citizen_details_update()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if current_user not in ('authenticated', 'anon') or public.is_admin() then
    return new;
  end if;

  new.user_id                  := old.user_id;
  new.verified_by              := old.verified_by;
  new.verified_at              := old.verified_at;
  new.provided_by_staff        := old.provided_by_staff;
  new.created_at               := old.created_at;
  new.last_password_changed_at := old.last_password_changed_at;

  if (new.first_name, new.middle_name, new.last_name, new.barangay,
      new.street, new.contact_number, new.profile_photo_path)
     is distinct from
     (old.first_name, old.middle_name, old.last_name, old.barangay,
      old.street, old.contact_number, old.profile_photo_path) then
    if old.last_profile_updated_at is not null
       and old.last_profile_updated_at > now() - interval '30 days' then
      raise exception 'profile_locked'
        using errcode = 'P0001',
              hint    = 'profile_edit_cooldown',
              detail  = 'Profile editing is locked for 30 days after a change.';
    end if;
    new.last_profile_updated_at := now();
  else
    new.last_profile_updated_at := old.last_profile_updated_at;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_aa_guard_citizen_details on public.citizen_details;
create trigger trg_aa_guard_citizen_details
  before update on public.citizen_details
  for each row execute function public.guard_citizen_details_update();
