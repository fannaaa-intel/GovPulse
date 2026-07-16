# Supabase — how database changes work here

## The rule

**New schema changes go in `migrations/`, as numbered migrations. Nothing else.**

```bash
supabase migration new add_thing      # creates migrations/<timestamp>_add_thing.sql
# ...edit it...
supabase db push                      # applies only what hasn't run yet
```

`db push` records each migration in `supabase_migrations.schema_migrations`, so it
applies each one **once**, **in order**, and knows what's already live. That is the
entire point, and it is what this project did not have.

---

## Why this exists

Until 2026-07-16 every schema change was a hand-run script in `supabase/*.sql`. They
had no order and no record of what had run, and almost all of them used
`create or replace` — which overwrites silently. So when two files defined the same
function, **whichever was pasted into the SQL editor last won**, and nothing anywhere
said so.

In a single day, four bugs were traced to exactly that:

| What was found | Cause |
|---|---|
| One notification → two device pushes | A second, undocumented push pipeline (`notify_push` → a `push-on-notification` Edge Function) existed only in the database. Both it and `push_on_notification` fired on every insert. |
| RPC ambiguity (PGRST203) worked around in Dart | `fix_broadcast_overload.sql` tried to drop a stale overload using the **wrong signature**. `drop function IF EXISTS` cannot tell "already gone" from "never matched", so it reported success and did nothing. The overload lived on for months. |
| Staff pinged about reports RLS hid from them | `report_triage_gate.sql` §5 dropped that trigger on purpose. `notification_deeplink_targets.sql` §1 re-created it and happened to run later. |
| Report notifications nearly lost their deep-links | Two files define `notify_citizen_report_decision()`. Re-running the older one to fix something unrelated would have silently downgraded it. |

Every one was found by querying `pg_trigger` / `pg_proc` — **none** by reading this
repo. The repo was not wrong so much as unable to be right: it described intent, and
the database held the truth, and nothing reconciled them.

---

## Layout

| Directory | What it is |
|---|---|
| `migrations/` | **The schema.** Numbered, ordered, applied once each. All new work goes here. |
| `legacy/` | The 42 historical hand-run scripts. **Do not run these.** See below. |
| `diagnostics/` | Read-only queries for inspecting the live database. Safe to run anytime. |
| `functions/` | Edge Functions. Deployed with `supabase functions deploy <name>`, not by `db push`. |

---

## `legacy/` — read, don't run

These are kept because they are the only written record of *why* much of this schema
looks the way it does — the RLS reasoning, the anonymity rules, the triage design.
That rationale is worth more than the DDL.

**They are not re-runnable and are not a migration path.** Several would actively
break production today: `report_triage_gate.sql` would downgrade
`notify_citizen_report_decision()` to a version without `reference_id` and kill every
report notification's deep-link. Others resurrect triggers that were deliberately
dropped (the `create trigger` lines in `staff_notifications.sql` §3 and
`notification_deeplink_targets.sql` §1 are commented out for exactly this reason —
leave them that way).

The live database, as captured by the baseline migration, is the truth. If one of
these files disagrees with the baseline, **the file is wrong**.

---

## Adopting this on the existing database — run once

The database already exists and already has ~45 scripts' worth of schema in it. So the
first migration is not written by hand: it is **pulled from what is actually live**.

```bash
supabase link --project-ref <ref>        # if not already linked
supabase db pull                         # writes migrations/<ts>_remote_schema.sql
```

`db pull` introspects the live schema, writes it as the baseline migration, **and
records it as already applied** — so `db push` will never try to re-run it against the
database it came from.

Then confirm the baseline is real before trusting it:

```bash
supabase migration list                  # baseline should show applied both sides
```

Sanity-check that the baseline captured today's fixes, because these are the things
that were wrong and are now right:

- exactly **one** trigger on `notifications` (`trg_push_on_notification`)
- **no** `trg_notify_staff_new_report` on `reports`
- exactly **one** `broadcast_notification`, signature `(text, text, bigint)`
- `notify_citizen_report_decision()` **contains** `reference_id`

`diagnostics/diagnose_report_triggers.sql` checks the last two.

---

## Things that still live only in the database

Not everything is in this repo, and pretending otherwise is how the push bug survived:

- **`device_tokens`** (table) and **`register_device_token`** / **`unregister_device_token`**
  (RPCs) — created directly against the project. Nothing here defines them.
- Whatever else has never been written down. The baseline pull is what finally captures it.

Once the baseline exists, this stops being a category of problem — but until you have
run `db pull`, assume the database knows things this repo does not.
