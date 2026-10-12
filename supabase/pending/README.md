# supabase/pending/

Migrations that are WRITTEN but must NOT run yet. `supabase db push` only reads
`supabase/migrations/`, so a file here cannot be applied by accident.

To apply one: check its precondition, `git mv` it into `supabase/migrations/`
with a fresh timestamp, then `supabase db push`.

| File | Run when |
| --- | --- |
| `drop_live_staff_chat.sql` | Stage B of the live-chat removal. Only after (1) `20261012000000_close_live_staff_chat.sql` is applied, (2) the `create-staff` Edge Function is redeployed (it no longer writes `is_online`), and (3) the app build without live chat is on the web AND in the Play Store. An older build still selects these tables and `admin_profiles.is_online`. |
