# legacy/ — historical scripts. Read them. Do not run them.

These 42 files were how this project's schema was built, one hand-pasted script at a
time, before `migrations/` existed. They are kept for their **reasoning**, not their
DDL — the RLS design, the anonymity guarantees, the triage-gate rationale, and the
comments explaining why each decision was made are genuinely valuable and exist
nowhere else.

## Why you must not run them

They have no order and no record of what ran. Nearly all use `create or replace`, which
overwrites silently, so several files define the same function and disagree about it.
Running one today does not "re-apply" anything — it reverts whatever ran after it.

Known live landmines, as of 2026-07-16:

- **`report_triage_gate.sql`** §4 defines `notify_citizen_report_decision()` **without**
  `reference_id`. The live version has it. Running this file downgrades every report
  notification so tapping one opens nothing. Its insert is wrapped in
  `exception when others then null`, so the damage is silent — no error, anywhere.
- **`staff_notifications.sql`** §3 and **`notification_deeplink_targets.sql`** §1 both
  re-create `trg_notify_staff_new_report`, which pings staff about pending reports RLS
  hides from them. Their `create trigger` lines are **commented out on purpose**. Leave
  them commented.
- **`fix_broadcast_overload.sql`** never worked. It drops signature
  `(text, text, text, bigint, integer, text)`; the real overload was
  `(integer, text, text, bigint, text, uuid)`. `IF EXISTS` matched nothing and said
  nothing. Superseded by `drop_stale_broadcast_overload.sql`, which is also spent.
- **`notification_deeplink_targets_2.sql` / `_3.sql`** are order-dependent on each
  other and will roll back citizen submissions entirely if run out of sequence.

## If you need to change something one of these files describes

Write a **new migration** in `../migrations/`. Do not edit the file here and re-run it —
that is the exact habit that produced four production bugs in one day. See `../README.md`.

## Already applied and spent

`fix_duplicate_push.sql`, `drop_stale_broadcast_overload.sql`, and
`fix_staff_new_report_ping.sql` were written and applied on 2026-07-16 to fix the bugs
above. They are verified done. They are here as the record of *why*, and re-running them
is pointless (though harmless — they are idempotent drops).
