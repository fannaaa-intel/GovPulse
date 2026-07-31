# Finding — `realtime.messages` ships insecure-by-default (LATENT, not live)

**Recorded** 2026-07-31 · **Severity** latent-critical (P2 today, P1 the day a Broadcast
feature ships) · **Status** RECORDED, NOT FIXED — deliberately. Nothing on the live
surface was altered by this session.
**Standing guard** `supabase/diagnostics/verify_realtime_broadcast_anon_invariant.sql`

---

## 1. The misconfiguration

`realtime.messages` — the table that backs Supabase Realtime **Broadcast** — is in the
Supabase-default posture, which is insecure in three compounding ways:

| Property | Live value | Why it matters |
|---|---|---|
| RLS enabled | `true` | The only thing denying `anon` today |
| Policy count | **0** | Deny-all — but *only* because zero policies exist |
| `anon` table grants | **INSERT, SELECT, UPDATE** | Standing write capability, all 9 columns |
| `authenticated` grants | INSERT, SELECT, UPDATE | Same |
| Schema `realtime` USAGE → `anon` | `true` | The schema is reachable |
| `EXECUTE realtime.send()` → `anon` | `true` | And it is `SECURITY INVOKER` |
| `messages.private` column default | `false` | **Channels are public unless asked otherwise** |

The dangerous shape is not any one row above. It is that **the deny is supplied by the
absence of policies, while the capability is supplied by a standing grant.** Those two
facts are maintained by different people at different times. The grant is permanent; the
absence of policies lasts exactly until someone builds a Broadcast feature — at which
point adding policies is not "adding security", it is *removing the only control there was.*

## 2. Why it is harmless right now

Nothing uses Broadcast. Proven by whole-repo grep on 2026-07-31:

```
$ grep -rn "\.channel(" lib/ --include=*.dart | wc -l          → 15
$ grep -rn "onPostgresChanges" lib/ --include=*.dart | wc -l   → 19
$ grep -rniE "onBroadcast|sendBroadcastMessage|RealtimeListenTypes\.broadcast|
              realtime\.messages|RealtimeBroadcast" lib/ test/ --include=*.dart
    lib/features/admin/pages/community_updates_page.dart:394:  final VoidCallback onBroadcast;
    lib/features/admin/providers/admin_users_provider.dart:630:  targetType: 'broadcast',
    lib/features/admin/widgets/admin_user_actions.dart:869:  Text(widget.broadcast ? 'Broadcast' : 'Send')
$ grep -rnE "private\s*:\s*(true|false)|RealtimeChannelConfig" lib/ --include=*.dart
    (none)
```

All 15 `.channel(...)` calls attach **only** `onPostgresChanges` listeners — the
publication path (`supabase_realtime`, 8 public tables), which is a different surface with
its own policies. The three residual "broadcast" hits are **not** Realtime: `onBroadcast`
is a Flutter `VoidCallback`, `targetType: 'broadcast'` is an audit-log string, and
`widget.broadcast` is a bool on a compose form. All three belong to
`broadcast_notification(...)`, the server-side **push-notification fan-out RPC**, which
writes `public.notifications` rows and never touches `realtime.messages`.

Corroborated server-side: **0 rows across all 7 `realtime.messages_*` partitions.** The
table has never carried a message.

> No Broadcast client, no Broadcast traffic ⇒ **no live exposure.** This finding is not a
> live incident and must not be reported as one.

## 3. Why it is latent-critical

Because the fail-closed state is destroyed by the *first* thing anyone will naturally do.

`lib/features/staff/providers/staff_providers.dart:76` already records the intent:

```
UPGRADE PATH: when Broadcast lands (7c) it replaces all three timers in a
```

with matching notes at `staff_conversations_page.dart:45`, `staff_overview_page.dart:45`,
and `staff_repository.dart:603` ("returns in 7c via Broadcast with a non-identifying
payload"). **Deferred item 7c is a planned Broadcast feature over exactly this surface.**

Two independent latent exposures, which need different fixes:

**(a) Private channels — the grant becomes live the instant a policy appears.**
With RLS on and zero policies, *every* caller is denied. Adding one permissive policy to
make a legitimate feature work does not grant access narrowly — it opens the standing
`anon` grant. Demonstrated in §4.

**(b) Public channels — the grant is not even involved.**
`private` defaults to `false`, and the client has no `RealtimeChannelConfig` anywhere. A
channel created as `supabase.channel('staff-alerts')` is **public**: Realtime relays it in
the Elixir layer without consulting the database at all. Any holder of the (publicly
shipped) anon key who guesses the topic name can subscribe to and inject into it. Revoking
grants does **not** fix this; only `private: true` does. This is the exposure most likely
to ship unnoticed, because it produces no database change to review.

## 4. Evidence — executed against the live project, 2026-07-31

Catalog state (`pg_class` / `information_schema.role_table_grants`):

```
table_name  rls_enabled  rls_forced  policy_count  relkind
messages    true         false       0             p        ← partitioned

grantee        privilege_type
anon           INSERT
anon           SELECT
anon           UPDATE
authenticated  INSERT / SELECT / UPDATE
service_role   INSERT / SELECT / UPDATE
postgres       DELETE/INSERT/REFERENCES/SELECT/TRIGGER/TRUNCATE/UPDATE
```

Column grants confirm the table-level grants expand across **all 9 columns** for `anon`
(`id, topic, extension, payload, event, private, inserted_at, updated_at, binary_payload`)
— including `private`, i.e. a writer can set its own message's privacy flag.

Partition-bypass path checked and **closed**: the 7 `messages_YYYY_MM_DD` partitions each
report `rls_enabled=false, policy_count=0` but `anon_privs=(none)`. Direct partition access
is denied for lack of grants, so parent-table RLS cannot be sidestepped that way. This is
a property worth *keeping* — see check 6 of the detector.

Authorization mechanism, from the live function bodies:

- `realtime.topic()` → `current_setting('realtime.topic', true)`; Realtime sets this
  per-channel so policies can scope by topic. **With zero policies nothing reads it.**
- `realtime.send(payload, event, topic, private DEFAULT true)` → `SET LOCAL realtime.topic`,
  then `INSERT INTO realtime.messages`. `prosecdef = false` (**SECURITY INVOKER**), so it
  runs with the caller's rights and RLS applies. Note it wraps the insert in
  `EXCEPTION WHEN OTHERS THEN RAISE WARNING` — **a denied insert is swallowed as a warning,
  not an error.** A misconfiguration here fails silently.

### The probe — `BEGIN … ROLLBACK`, one Management API call, nothing committed

No message was ever committed, so nothing was relayed and no exposure was created.

```
step               detail
A.select_as_anon   rows visible = 0
A.insert_as_anon   DENIED: new row violates row-level security policy for table "messages"
B.insert_as_anon   ACCEPTED -- anon can write ANY topic
B.select_as_anon   rows visible = 1 (incl. other users' topics)
```

**State A** is today: `anon` is denied, fail-closed. **State B** is the counterfactual —
the transaction added a single ordinary-looking policy:

```sql
create policy probe_tmp_policy on realtime.messages
  for all to anon, authenticated using (true) with check (true);
```

and `anon` immediately gained unrestricted write to *any* topic and read of *every*
message. That policy is the shape a developer writes to get a Broadcast feature working on
the first try. **The gap between A and B is one CREATE POLICY statement.**

Post-rollback ledger: `policies_on_messages = 0`, `rows_in_messages = 0`,
`anon_privs = INSERT,SELECT,UPDATE`, `rls_enabled = true`, `publication_count = 8` —
identical to pre-probe.

## 5. Acceptance criterion

> **Before any Broadcast feature ships**, all four must hold simultaneously:
>
> 1. `has_table_privilege('anon','realtime.messages', p)` is **false** for each of
>    `INSERT`, `UPDATE`, `SELECT`.
> 2. `realtime.messages` has **≥1 policy**, and **no** policy on it lists `anon` or
>    `public` in `pg_policies.roles`.
> 3. Every policy's `qual`/`with_check` references **`realtime.topic()`** — i.e. it scopes
>    to the subscribed topic rather than granting table-wide (`using (true)` is a fail).
> 4. Every client channel that carries Broadcast is constructed `private: true`; no
>    Broadcast listener/sender exists on a channel lacking an explicit
>    `RealtimeChannelConfig(private: true)`.

Criteria 1–3 are checked mechanically by
`verify_realtime_broadcast_anon_invariant.sql`. Criterion 4 is **not SQL-observable** —
a public-channel broadcast never touches the database — so the detector enforces it as a
documented repo-side grep, and check 3 is what makes 1–2 non-vacuous if someone satisfies
them with a `using (true)` policy.

## 6. Explicitly NOT done tonight

Not revoked, not policied, not republished, by instruction. `anon` retains
INSERT/SELECT/UPDATE; `realtime.messages` retains zero policies; publication membership
unchanged at 8 tables. **The fix is deferred to whichever migration first introduces a
Broadcast feature** — and the detector exists to make it impossible to introduce one
without doing the fix in the same change.
