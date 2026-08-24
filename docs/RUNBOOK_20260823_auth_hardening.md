# Auth hardening — deployment runbook (2026-08-23)

All code is written, type-checked and analyzed. Two production steps remain, and
both need privileges this workstation's tooling does not have:

* **SQL** — `cli_login_postgres` has no `CREATE` on schema `public`, so the
  migrations must run in the **Supabase SQL editor** (which runs as `postgres`).
* **Deploys** — must be run by you from this repo.

**The two steps are independent.** Neither half breaks while the other is
pending, so you can do them in either order, or days apart. Recommended order is
SQL first, because it closes the only finding that is exploitable today.

---

## Step 1 — SQL migrations

Open the Supabase SQL editor. **Run one block at a time** — the editor keeps
only the last result set, so a multi-block paste silently discards output.

### 1a. `supabase/migrations/20260823000000_otp_rpc_caller_scoping.sql`

Closes F-01 and F-03. Scopes `clear_otp_failures`, `record_otp_failure` and
`can_verify_otp` to the calling user, and makes `can_send_otp` read-only.

Paste everything from `begin;` to `commit;`. Then run the `VERIFY` block from
the file's footer **separately**. Expected:

```
can_send_otp        auth=t anon=t  caller_scoped=f  still_consumes=f
can_verify_otp      auth=t anon=f  caller_scoped=t  still_consumes=f
clear_otp_failures  auth=t anon=f  caller_scoped=t  still_consumes=f
record_otp_failure  auth=t anon=f  caller_scoped=t  still_consumes=f
```

### 1b. `supabase/migrations/20260823000001_revoke_limiter_table_grants.sql`

Closes F-10. Removes `anon` / `authenticated` grants on the three limiter
tables. Behaviour is unchanged (RLS already denied every row); this removes the
single-point-of-failure. Run its `VERIFY` block separately — expect `postgres=`
and `service_role=` only.

### Smoke test after 1a

Sign in on a real account and run **Settings → Change password** end to end.
That exercises all three rescoped RPCs (`can_verify_otp` → `record_otp_failure`
or `clear_otp_failures`). It must behave exactly as before.

### Rollback

`supabase/rollback/20260823000000_otp_rpc_caller_scoping_rollback.sql`
`supabase/rollback/20260823000001_revoke_limiter_table_grants_rollback.sql`

Both restore the exact pre-change state, captured live before any edit.

---

## Step 2 — Edge function deploys

Seven functions changed. **`verify_jwt` must be preserved per function** — two
of them are intentionally unauthenticated and will break the signup and
password-reset flows if they are deployed with JWT verification on.

```bash
# Group A — verify_jwt must stay TRUE (config.toml already declares it)
supabase functions deploy username-login        --use-api
supabase functions deploy send-email-otp        --use-api
supabase functions deploy reset-send-otp        --use-api
supabase functions deploy check-email-exists    --use-api
supabase functions deploy check-username-exists --use-api

# Group B — verify_jwt MUST stay FALSE. Pass the flag explicitly; do not rely
# on config.toml being honoured by the CLI on this path.
supabase functions deploy verify-email-otp  --use-api --no-verify-jwt
supabase functions deploy reset-verify-otp  --use-api --no-verify-jwt
```

Deploying `username-login` also clears F-09 on its own: production is still
running v1 from 2026-07-23, which carries the `export const config =
{ auth: false }` line the repo removed on 07-28.

### Verify immediately after deploying

```bash
U="https://vxvflhjbafqwehuxnmeq.supabase.co/functions/v1"
for f in username-login send-email-otp check-email-exists \
         check-username-exists reset-send-otp \
         verify-email-otp reset-verify-otp; do
  printf '%-24s %s\n' "$f" \
    "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$U/$f" \
        -H 'Content-Type: application/json' -d '{}' --max-time 25)"
done
```

**Expected — any deviation means stop and roll back:**

| function | expected | meaning |
|---|---|---|
| username-login | `401` | gateway gate on |
| send-email-otp | `401` | gateway gate on |
| check-email-exists | `401` | gateway gate on |
| check-username-exists | `401` | gateway gate on |
| reset-send-otp | `401` | gateway gate on |
| verify-email-otp | `400` | function ran — gate correctly off |
| reset-verify-otp | `400` | function ran — gate correctly off |

A `401` on either Group B function means JWT verification was wrongly enabled:
signup and password reset are broken. Redeploy that one with `--no-verify-jwt`.

### Rollback

The currently-deployed code for the Group A/B functions is identical to git
`HEAD` (verified by diffing the downloaded bundles), **except** `username-login`,
whose deployed copy is older. To restore any function:

```bash
git stash                       # park the new code
supabase functions deploy <name> --use-api   # redeploys the old version
git stash pop                   # bring the new code back
```

---

## Step 3 — ship the app changes

Two Dart files changed. They are **not** required for the server fixes to work,
and old installed builds keep working against the new backend.

* `lib/core/services/auth_service.dart` — removes the dead client-side
  deactivation re-check (F-13); documents why the password `.trim()` must never
  be removed (F-12).
* `lib/features/Resets/reset_password_email_screen.dart` — stops the UI claiming
  an address "is not registered", which would reintroduce in the client the
  enumeration oracle the server fix removes (F-02).

Ship on your normal release cadence.

---

## Not fixed, deliberately

* **F-12 — password `.trim()` stays.** Signup and login both trim, so stored
  bcrypt hashes are of trimmed passwords. Removing the trim on either side alone
  locks out every user whose password has surrounding whitespace, and the hashes
  are one-way so no migration can fix it afterwards. Documented in-code instead.
* **`checkRateLimit` count/insert is still non-atomic.** Two simultaneous
  requests can both pass a check near the ceiling. Fixing it needs a
  single-statement upsert-and-count or an advisory lock. Much smaller than the
  fail-open bug that was fixed; noted in the source.
* **F-08 threshold not measured.** `listUsers()` sends an empty `per_page`, so
  the page size is GoTrue's server-side default. The fix removes the call
  entirely, so the exact number never mattered.
