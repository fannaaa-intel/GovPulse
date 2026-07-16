-- ════════════════════════════════════════════════════════════════════════════
--  Fix: create-staff upsert fails with
--    "there is no unique or exclusion constraint matching the ON CONFLICT
--     specification"
--
--  The create-staff Edge Function upserts one row per user into `user_roles`
--  and `admin_profiles` (keyed by user_id). That requires a UNIQUE constraint
--  on user_id — which is also the model the app assumes everywhere (login reads
--  a single role via maybeSingle(); each official has one admin_profiles row).
--
--  This migration de-duplicates any accidental extra rows, then adds the unique
--  constraints. Idempotent — guarded so re-running is a no-op.
-- ════════════════════════════════════════════════════════════════════════════

-- ── user_roles: one role per user ────────────────────────────────────────────
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'user_roles_user_id_key'
  ) then
    -- Keep the highest-privilege row (lowest role_id) per user, drop the rest.
    delete from public.user_roles a
      using public.user_roles b
     where a.user_id = b.user_id
       and (a.role_id > b.role_id
            or (a.role_id = b.role_id and a.ctid > b.ctid));

    alter table public.user_roles
      add constraint user_roles_user_id_key unique (user_id);
  end if;
end $$;

-- ── admin_profiles: one profile per official ─────────────────────────────────
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'admin_profiles_user_id_key'
  ) then
    -- Drop any duplicate profile rows for the same user (keep one arbitrarily).
    delete from public.admin_profiles a
      using public.admin_profiles b
     where a.user_id = b.user_id
       and a.ctid > b.ctid;

    alter table public.admin_profiles
      add constraint admin_profiles_user_id_key unique (user_id);
  end if;
end $$;
