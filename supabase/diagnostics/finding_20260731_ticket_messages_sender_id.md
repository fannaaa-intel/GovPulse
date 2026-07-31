# FINDING — `ticket_messages.sender_id` defeats ticket anonymity for the assigned officer

**Status:** OPEN. Investigated 2026-07-31, verified live, deliberately NOT fixed.
**Severity:** P1 — a citizen who marked a ticket anonymous is identifiable to the staff member handling it.
**Found during:** migration 3b (`20260731000002`), which fixed the bridge and `sender_type` and stopped short of this.

> **Why this file is `finding_` and not `evidence_`.** `.gitignore:48` excludes
> `supabase/diagnostics/evidence_*.md`, so anything written under that prefix stays
> local and untracked. This finding must survive the session that found it, so it
> takes a committed name. Do not rename it back.

---

## 1. The finding

`public.ticket_messages` carries `sender_id uuid NOT NULL`. On a citizen message that column
holds the citizen's `auth.users` id. Staff read that table directly, and nothing masks the
column, so on a ticket the citizen marked **anonymous** the reporter's uuid reaches the
assigned officer by two independent paths.

Verified against production 2026-07-31:

**(a) PostgREST.** `staff_reads_department_messages` grants `SELECT` on the base table to any
role-2 caller for every ticket in their department:

```
policy  staff_reads_department_messages   SELECT
USING   staff_can_see_ticket(ticket_id)          -- was the bridge, pre-20260731000002
```

There is no view over `ticket_messages` at all — catalog sweep for views whose definition
mentions the table returned `null`, and for views mentioning `sender_id`, `null`. A staff JWT
can therefore request `sender_id` and receive it. Live shape at the time of writing:
`concern_tickets` 2 rows, 1 of them `is_anonymous = true`, carrying 1 message.

**(b) Realtime.** `ticket_messages` is a member of the `supabase_realtime` publication, and the
staff client subscribes to it per ticket:

```dart
// lib/features/staff/data/staff_repository.dart:597-610
.channel('staff_ticket_msgs:$ticketId')
.onPostgresChanges(
  event: PostgresChangeEvent.insert,
  table: 'ticket_messages',
  filter: PostgresChangeFilter(type: eq, column: 'ticket_id', value: ticketId),
  callback: (p) => onInsert(StaffMessage.fromRow(p.newRecord)),
)
```

`p.newRecord` is the whole row. `StaffMessage.fromRow` ignores `sender_id`, but the value has
already crossed the socket.

**What the staff client actually reads — this is why the fix is cheap.**
`staff_repository.fetchMessages` selects `id, sender_type, text, created_at`; `sendMessage`
writes its own uid and selects back the same four columns. Threading and bubble sidedness key
off **`sender_type`**, never `sender_id`. A whole-client audit found only four references to
`sender_id`: two writes, one docstring, one citizen-side write. **No staff feature depends on
it.** Masking it breaks nothing in the UI.

---

## 2. The invariant this violates

**`20260722000017` — linked anonymity, stated as an invariant:**

> ```
> -- THE INVARIANT. A report's anonymity constrains everything linked to it. If a
> -- report is anonymous, nothing that links to it may carry, expose, or allow
> -- reconstruction of the reporter's identity.
> ```

`ticket_messages` links to `concern_tickets`, which inherits anonymity from its source report
under that same migration. A row carrying the reporter's uuid is exactly "carry … the
reporter's identity".

**`20260721000007` §1 — the six-column null-set rule, which `sender_id` escapes only by living
on a different table:**

> ```
> -- The null-set below covers ALL SIX identity columns on concern_tickets:
> --   user_id, contact_name, contact_number, contact_address, contact_email,
> --   contact_note
> -- verified against the live column list on 2026-07-21. The whole finding is that
> -- the CLIENT decided which columns to hide; the view must not repeat that by
> -- covering only the three the current screen renders. If a column is ever added
> -- to concern_tickets that can identify a citizen, it must be added here too
> ```

`concern_tickets.user_id` — **the same uuid** — is already in that null-set, and
`staff_tickets_view` nulls it live:

```sql
case when t.is_anonymous then null else t.user_id end as user_id,
```

So the citizen's uuid is already classified as identity that must not reach staff. `sender_id`
is that value arriving through a door the rule's wording did not reach, because the rule was
scoped to one table rather than to the value.

---

## 3. Sourced citations

**C1 — the assigned officer is inside the threat model, explicitly.** `20260721000007` §4:

> ```
> -- This fully closes the leak rather than reducing it. An earlier draft dropped
> -- only the two department-scoped policies and left the two assigned-scoped ones
> -- ... which would have kept exposing all five raw contact columns for tickets a
> -- staffer had claimed — and claiming is normal handling, so in practice the
> -- citizen's number would still reach staff on every anonymous ticket worked.
> -- "ticket anonymity: reduced" is not "ticket anonymity: closed", and a panelist
> -- asking "can the staffer handling my anonymous complaint see my number?" must
> -- get "no".
> ```

**C2 — "the screen looks correct; the wire does not" is the defect shape, and it is this one.**
`20260721000007`, opening finding:

> ```
> -- So a citizen's phone number is fetched over the wire for a ticket they marked
> -- anonymous, and nulled at render time. The screen looks correct; the wire does
> -- not. Anyone talking to PostgREST with a staff JWT — or reading the realtime
> -- payload, see section 5 — gets the number.
> ```

The staff client does not even render `sender_id`, and that is precisely the point: the value
is on the wire regardless.

**C3 — the remedy pattern already exists in this codebase.** `20260721000007` scope note:

> ```
> -- Closes BOTH leak surfaces FULLY, using only patterns already proven in this
> -- codebase:
> --   * REST leak  -> staff read through a definer view that nulls all six
> --                   identity columns on is_anonymous (section 1), and ALL FOUR
> --                   base-table staff policies dropped so no raw-column path
> --                   survives for assigned tickets either (section 4)
> --   * realtime   -> concern_tickets removed from the logical-replication
> --     leak         publication, so the raw row stops going over the socket
> ```

**C4 — the identity-masking discipline predates all of it, and was bypassed once already.**
`20260721000007`:

> ```
> -- The proof that this was a pattern rather than an oversight is one table over:
> -- `ticket_citizen(uuid)` ALREADY exists as a SECURITY DEFINER function that
> -- returns nulls for anonymous tickets. The correct approach was known and built
> -- for the chat header, and bypassed for the list. This migration makes the list
> -- use the same discipline.
> ```

`ticket_messages` is now the third table where the same discipline has not been applied.

---

## 4. Why this is not fixed yet

1. **It is a coupled client + database release.** Masking `sender_id` server-side means staff
   read through a view instead of the base table, which means `staff_repository.fetchMessages`
   must be repointed in the same release. `20260721000007` is the precedent and it carried the
   same warning: *"REQUIRES DART CHANGES … Must not ship before the staff client is repointed."*

2. **The realtime half has an unresolved fork.** `20260721000007` §5 solved the realtime
   surface for `concern_tickets` by removing the table from the publication — the staff inbox
   fell back to polling. **That remedy cannot be copied here.** Staff live chat *depends* on the
   `ticket_messages` subscription; dropping the table from `supabase_realtime` stops new
   messages appearing without a manual refresh. That is a feature outage, not a fix. The fork
   is: mask at source (make the replicated row carry no identity) versus move the staff thread
   onto Realtime Broadcast — the latter overlapping the existing **"7c-realtime"** backlog item,
   which `20260721000007` deferred precisely so a security fix could not be confused with a new
   mechanism.

3. **Scope discipline.** Migration 3b was triggers-adjacent policy work with a mechanical
   acceptance criterion. Bundling a client-coupled anonymity change into it would have made a
   clean, verifiable migration unverifiable.

---

## 5. Recommended fix shape

Follow `20260721000007` rather than inventing anything:

1. **`staff_messages_view`** — `security_invoker = false` definer view over `ticket_messages`,
   nulling identity on the parent ticket's flag:
   ```sql
   case when t.is_anonymous then null else m.sender_id end as sender_id
   ```
   department-scoped internally via `staff_can_see_ticket(m.ticket_id)` so the view is
   self-scoping, exactly as `staff_tickets_view` is.
2. **Repoint the client** — `staff_repository.fetchMessages` reads the view. No other change is
   needed: it already selects only `id, sender_type, text, created_at`, and threads on
   `sender_type`.
3. **Drop the base-table staff SELECT path** — remove `staff_reads_department_messages` (or
   otherwise ensure role 2 cannot reach raw `sender_id`), so no raw-column path survives.
   §4's standard: *"fully closes the leak rather than reducing it."*
4. **Decide the realtime half separately, and do not skip it.** Masking only the REST path
   leaves surface (b) wide open, and a fix that closes one of two doors is the "reduced, not
   closed" outcome C1 rejects. Do **not** remove `ticket_messages` from `supabase_realtime`
   without a working replacement.

---

## 6. ACCEPTANCE CRITERION

Written to be checked mechanically, in the style `20260721000007` §3 used for the bridge
(*"Acceptance criterion: this function no longer exists after that migration. If it survives,
that is a finding."*).

**A migration closes this finding if and only if ALL FIVE hold after it:**

1. **No role-2 caller can obtain a non-null `sender_id` for a message on an anonymous ticket,
   by any path.** Under a real staff JWT (`set local role authenticated` + `request.jwt.claims`),
   for every row belonging to a `concern_tickets` row with `is_anonymous = true`, every readable
   surface — base table, view, and RPC — returns `sender_id IS NULL`. Assert with a count, not
   by inspection: the number of such rows exposing a non-null `sender_id` must be `0`.
2. **No raw-column path survives.** No policy on `public.ticket_messages` grants `SELECT` to a
   role-2 caller against the base table, or the base table provably yields no `sender_id` to
   role 2. Reducing rather than removing the path does not satisfy this.
3. **The realtime payload carries no identity for anonymous tickets.** Either
   `ticket_messages` is absent from `pg_publication_tables` for `supabase_realtime`, **or** the
   replicated row is proven not to carry a citizen uuid on anonymous tickets.
4. **Staff live chat still works.** A new message on a staff-visible ticket still reaches the
   staff thread without a manual refresh. If condition 3 is met by dropping the publication
   membership and nothing replaces it, this condition FAILS and the finding is **not** closed —
   that is a regression wearing a fix's clothes.
5. **Attributed tickets are unaffected.** On `is_anonymous = false`, staff-visible `sender_id`
   is unchanged, and no client code newly depends on `sender_id` for threading (it keys on
   `sender_type` today and must continue to).

**If any of the five is unmet, this finding is not closed. If a migration claims to close it
and leaves surface (b) open, that is itself a finding.**

---

## 7. Carried forward — two smaller items, also unfixed

### (i) A citizen can forge a staff message — `sender_type` is unconstrained as to *who claims it*

`20260731000002` added `ticket_messages_sender_type_check` pinning the value set to
`('citizen','staff')`. That constrains the **vocabulary**, not **who may claim which value**.
The participant INSERT policy places no condition on `sender_type`:

```
policy "Ticket participants can send messages"  INSERT
WITH CHECK ( auth.uid() = sender_id
             AND ticket_accepts_messages(ticket_id)
             AND ( ticket owner OR assigned staff OR admin ) )
```

Nothing there says *a citizen must write `sender_type = 'citizen'`*. So the ticket owner can
insert a row with `sender_type = 'staff'`, and since `20260731000001` that value now:

* renders as an official reply in both the citizen and staff threads, and
* fires `notify_citizen_new_message`, producing a **"New reply from &lt;department&gt;"**
  notification attributable to the LGU.

Impact is bounded — a citizen can only do this inside their own ticket, so it is
self-deception plus a forged record rather than a route to another user — but the forged
message is indistinguishable from a real one in the staff thread and in the audit trail.

**Fix shape:** a conjunct on the participant policy binding the claimed `sender_type` to the
caller's role (ticket owner ⇒ `'citizen'`; assigned staff/admin ⇒ `'staff'`). This is a
behavioural change to the citizen write path, so it needs its own migration and a client check
that nothing sends a mismatched pair. **Do not** attempt it by widening the CHECK constraint —
a CHECK cannot see the caller.

### (ii) Cosmetic — `20260722000017`'s `reference_code` hint states the wrong length

The trigger's error hint says:

> `Expected LGU-YYYYMMDD-NNNNN (_generateRef).`

five tail characters, while its own CHECK and the trigger's `c_ref_ok` require **six**:

```
^LGU-[0-9]{8}-[0-9A-HJKMNP-TV-Z]{6}$
```

Anyone building a fixture or a manual row from the hint gets rejected with `22023` and a
message that describes a format the database does not accept. It cost one round-trip while
writing 3b's verify fixtures. Harmless to data; fix opportunistically in whatever next touches
that trigger, and change the hint text only — **not** the regex, which is load-bearing and is
mechanically compared against the CHECK by `verify_20260722000017.sql`.
