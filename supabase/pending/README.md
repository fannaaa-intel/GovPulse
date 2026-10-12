# supabase/pending/

Migrations that are WRITTEN but must NOT run yet. `supabase db push` only reads
`supabase/migrations/`, so a file here cannot be applied by accident.

To apply one: check its precondition, `git mv` it into `supabase/migrations/`
with a fresh timestamp, then `supabase db push`.

| File | Run when |
| --- | --- |
| `drop_live_staff_chat.sql` | Stage B of the live-chat removal. Only after (1) `20261012000000_close_live_staff_chat.sql` is applied, (2) the `create-staff` Edge Function is redeployed (it no longer writes `is_online`), and (3) the app build without live chat is on the web AND in the Play Store. An older build still selects these tables and `admin_profiles.is_online`. |

## Stage B readiness (audited live 2026-10-13)

Dependency audit re-run against the live database before applying:

- All 19 functions exist with **exactly one overload each**, so the signatures
  written into the migration match and every `drop function` will bind.
- **No other function and no other view** references `concern_tickets`,
  `ticket_messages`, `ticket_attachments`, `is_online` or `last_seen_at`.
  The drop is self-contained.
- The three storage policies are all scoped `bucket_id = 'ticket-attachments'`
  and no other storage policy touches that bucket — safe to drop despite
  their generic names.
- `admin_profiles.is_online` and `last_seen_at` are both still present
  (`pg_attribute` attnum 9 and 10). Check this with `pg_attribute`, never
  `information_schema.columns`, which is privilege-filtered and reports them
  as absent to a low-grant role.
- `cron.job` is permission-denied to the audit role, which is exactly why the
  migration unschedules by command text inside a `to_regclass` guard. That
  block can only be verified from the SQL editor as `postgres`.

Verify afterwards with `supabase/diagnostics/verify_drop_live_staff_chat.sql`
(9 checks, one block at a time). Every check was run against the
PRE-migration database and correctly reported FAIL, so a PASS afterwards means
the migration did the work rather than the check being green by construction.

**Remaining precondition: the Play Store rollout must be LIVE TO USERS**, not
merely uploaded. An installed older APK still selects these tables and
`is_online`; it errors rather than degrading.

