-- ============================================================================
-- 20260731000000  Relocate the password-change cooldown to profiles
-- ============================================================================
-- FILE NUMBER: this is 20260731000000, NOT 20260722000018. That number is
-- reserved for the "Migration 17 — ticket_messages" work item and must stay
-- free. Refer to migrations by filename; two different things are called "17".
--
-- ── THE BUG ────────────────────────────────────────────────────────────────
-- The 30-day password-change cooldown never fired for pending or unverified
-- citizens. It is a client-side gate that reads and writes
-- citizen_details.last_password_changed_at, and citizen_details rows are
-- created in exactly ONE place — handle_verification_decision, on
-- `status = 'approved'`. Before approval a citizen has no row there at all:
--
--     profiles.status   profiles   with citizen_details   with timestamp
--     unverified        2          0                      0
--     verified          5          4                      1
--
-- So both halves failed, and reinforced each other:
--   READ  change_password_send_screen.dart: .maybeSingle() -> null, so the
--         `if (raw != null)` guard never enters and _isLocked stays false.
--   WRITE change_password_new_screen.dart: .update().eq('user_id', ...) is an
--         UPDATE, not an upsert. It matched ZERO rows and returned HTTP 200,
--         so the timestamp was never recorded and the next attempt had nothing
--         to read either.
-- Measured live: two password changes seconds apart, both accepted.
--
-- ── WHY profiles AND NOT AN UPSERT INTO citizen_details ────────────────────
-- Making that write an upsert is the obvious one-line fix and it is a TRAP.
-- INSERT on citizen_details fires two triggers:
--     sync_profile_status_on_citizen_insert -> UPDATE profiles SET status = 'verified'
--     grant_citizen_role                    -> INSERT user_roles (user_id, 3)
-- Neither is conditional. A pending citizen who changed their password would
-- be silently marked verified and granted the citizen role — identity
-- verification bypassed from the password screen. Do not reintroduce that.
--
-- profiles is the correct home: every account has exactly one row regardless of
-- verification state (7 of 7 live), and its only UPDATE trigger is
-- set_profiles_updated_at -> set_updated_at, which has no status or role
-- side effect. Verified from pg_trigger before writing this.
--
-- ── SCOPE ──────────────────────────────────────────────────────────────────
-- One nullable column, one backfill, two comments. No policy is created,
-- altered or dropped: the cooldown stays a CLIENT-SIDE UX guardrail, not a
-- security control, and the existing self-service policies already permit it
-- (asserted below). Nothing here can reject a password change.
--
-- The citizen_details column is NOT dropped. It is left in place, backfilled
-- from, and marked superseded — dropping it would be irreversible and buys
-- nothing. Nothing in lib/ reads or writes it after this change.
-- ============================================================================

begin;

-- ── 1. Guard: the client-side gate depends on these two self-service policies
-- If either is missing or has been narrowed to exclude unverified users, the
-- relocation silently fails for exactly the accounts it is meant to fix — the
-- gate would read null and the write would match zero rows, which is the bug
-- being repaired, reappearing one table over. Fail loudly at apply time.
do $$
declare
  v_select boolean;
  v_update boolean;
begin
  select exists (
    select 1 from pg_policies
     where schemaname='public' and tablename='profiles'
       and policyname='Users can view own profile' and cmd='SELECT'
  ) into v_select;

  select exists (
    select 1 from pg_policies
     where schemaname='public' and tablename='profiles'
       and policyname='own_profile_update' and cmd='UPDATE'
  ) into v_update;

  if not (v_select and v_update) then
    raise exception
      'ABORT: profiles self-service policies missing (select=%, update=%). The password cooldown is a client-side gate and needs the signed-in user to read and write their OWN profiles row; without both, pending/unverified citizens silently bypass it exactly as they did via citizen_details.',
      v_select, v_update;
  end if;
end $$;

-- ── 2. The column ──────────────────────────────────────────────────────────
-- Nullable with no default: null means "never changed", which the client treats
-- as unlocked. Backfilling a default would lock every existing account out for
-- 30 days.
alter table public.profiles
  add column if not exists last_password_changed_at timestamptz;

comment on column public.profiles.last_password_changed_at is
  'UTC timestamp of the last password change. Drives the 30-day cooldown gate in '
  'change_password_send_screen.dart and reset_new_password_screen.dart. '
  'CLIENT-SIDE UX GUARDRAIL ONLY — no policy, trigger or function enforces it, '
  'and a direct PUT /auth/v1/user bypasses it entirely. Lives here rather than '
  'on citizen_details because every account has a profiles row regardless of '
  'verification state; pending/unverified citizens have no citizen_details row.';

-- ── 3. Backfill so verified users keep the cooldown they already accrued ───
-- Only fills nulls, so re-running cannot clobber a newer value written by the
-- client after this migration first ran.
update public.profiles p
   set last_password_changed_at = cd.last_password_changed_at
  from public.citizen_details cd
 where cd.user_id = p.id
   and cd.last_password_changed_at is not null
   and p.last_password_changed_at is null;

comment on column public.citizen_details.last_password_changed_at is
  'SUPERSEDED 2026-07-31 by profiles.last_password_changed_at. Backfilled from '
  'here; no longer read or written by any client code. Kept for history. Do NOT '
  'resume writing here — creating a citizen_details row fires '
  'sync_profile_status_on_citizen_insert and grant_citizen_role, which would '
  'verify a pending citizen as a side effect of changing their password.';

commit;

-- Expected after this migration:
--   profiles.last_password_changed_at exists, nullable, no default
--   every citizen_details.last_password_changed_at value mirrored onto profiles
--   no new/changed policies, no new triggers, no enforcement anywhere
