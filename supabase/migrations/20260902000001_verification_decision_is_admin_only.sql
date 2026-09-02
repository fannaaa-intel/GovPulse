-- ════════════════════════════════════════════════════════════════════════════
--  Approving or rejecting a VERIFICATION is an admin decision, not a staff one.
--
--  ── What was wrong ────────────────────────────────────────────────────────
--  `admin_update_status` — despite its name — granted UPDATE on
--  verification_submissions to BOTH roles:
--
--      r.name = ANY (ARRAY['admin', 'staff'])
--
--  So any staff account could mark a citizen verified. Verifying an identity
--  is materially different from the work staff actually do (report progress,
--  citizen chat): a wrong approval admits someone to the system as a person
--  they are not, using a government ID and a selfie as the evidence.
--
--  ── Why this is safe to tighten ───────────────────────────────────────────
--  Confirmed before writing this: the staff portal has NO verification screen.
--  Nothing under lib/features/staff/ reads or writes verification_submissions.
--  The single hit for 'verification' there is a notification TOPIC LABEL in
--  staff_notifications.dart, which is a read-only string and untouched by an
--  UPDATE policy.
--
--  So this closes a door nobody walks through. No staff workflow changes, and
--  the admin console — the only thing that ever called approve/reject — is
--  unaffected because admins keep the grant.
--
--  ── What is deliberately NOT changed ──────────────────────────────────────
--  Staff keep their SELECT reach. This migration is about who DECIDES, not
--  about hiding submissions; narrowing reads would be a separate change with
--  its own consequences, and nothing asked for it.
-- ════════════════════════════════════════════════════════════════════════════

drop policy if exists admin_update_status on public.verification_submissions;

create policy admin_update_status
  on public.verification_submissions
  as permissive
  for update
  to authenticated
  using (
    exists (
      select 1
      from public.user_roles ur
      join public.roles r on r.id = ur.role_id
      where ur.user_id = (select auth.uid())
        and r.name = 'admin'
    )
  );

comment on policy admin_update_status on public.verification_submissions is
  'Only an admin may change a verification submission - approve, reject, or '
  'edit. Staff were previously included here, but the staff portal has no '
  'verification screen and identity decisions are not staff work. The '
  'automated ID check never writes this table at all: it advises the reviewer '
  'through the check_* columns and the decision stays human.';
