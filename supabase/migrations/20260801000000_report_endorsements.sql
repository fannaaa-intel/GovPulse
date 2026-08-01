-- ============================================================================
-- 20260801000000  Endorse to External Entity — signed token, PIN, scan handoff
-- ============================================================================
-- Backs the "Endorse to External Entity" flow end to end: an admin endorses a
-- report to a national agency (DPWH, DENR, PNP, BFP, DOH) with a written
-- reason; the agency receives a printed endorsement letter carrying a QR code;
-- scanning it opens a public page where the agency confirms receipt and later
-- marks the work completed, authenticated by a 4-digit PIN the LGU sends
-- through a separate channel.
--
-- ── WHY THE LIFECYCLE IS NOT reports.status ────────────────────────────────
-- The obvious implementation is to write 'endorsed' / 'received' / 'completed'
-- into reports.status. That column has no CHECK constraint (verified live
-- 2026-08-01: the only check on the table is reports_ai_urgency_chk), so the
-- database would happily accept it — and three things downstream would break
-- quietly, which is the worst way for them to break:
--
--   1. reportStatusFromDb() in admin_reports_provider.dart maps any unknown
--      string to ReportStatus.pending. Every endorsed report would read back
--      as "Pending" in the console, in all six queue buckets, and in analytics.
--   2. notify_citizen_report_decision() ends its CASE with
--      `else return new; -- unknown status - no notification`. The citizen who
--      filed the report would stop being told anything as it progressed.
--   3. cascade_status_to_duplicates() copies status to every merged
--      confirmation, so the corruption fans out to linked reports.
--
-- Endorsement is ALREADY orthogonal to status in this schema — it is
-- `endorsed_to_department is not null`, and AdminReport.isEndorsed is what the
-- Endorsed bucket keys on. This migration keeps that separation. The agency
-- lifecycle lives on report_endorsements.state, which is what the scan page and
-- the letter speak in, and each transition MIRRORS onto reports.status
-- (received -> in_progress, completed -> resolved) so the console, the
-- citizen's timeline, and the notification trigger all keep working unchanged.
--
-- ── WHY TOKEN + PIN, AND WHY BOTH ──────────────────────────────────────────
-- The token is 32 bytes from extensions.gen_random_bytes, base64url-encoded.
-- It is the report identifier for this purpose: unguessable, and bound to ONE
-- report, so a photographed QR cannot be replayed against a different report.
-- But a QR code is a public artefact — anyone who can see the letter, or a
-- photo of it, holds the token. So the token alone only grants READ of a
-- deliberately narrow projection (see scan_endorsement). Every state change
-- additionally requires the PIN, which travels to the agency separately and is
-- never printed on the letter.
--
-- Only a bcrypt hash of the PIN is stored. The plaintext is returned exactly
-- once, from endorse_report_to_agency, and is unrecoverable afterwards — an
-- admin who loses it must re-endorse, which mints a fresh token and PIN and
-- invalidates the old QR. That is a deliberate property, not a gap.
--
-- ── ANONYMITY ──────────────────────────────────────────────────────────────
-- scan_endorsement is reachable by anon and returns NO reporter identity of any
-- kind: no user_id, no name, not even the is_anonymous flag. This is the same
-- promise 20260722000000 enforced across the staff surfaces, held at the one
-- point in this schema that answers to an unauthenticated caller.
--
-- ── pgcrypto IS IN `extensions`, NOT `public` ──────────────────────────────
-- Verified live. Every definer function here sets `search_path to 'public'`
-- following house convention, which means crypt / gen_salt / gen_random_bytes
-- are NOT on the path. They are fully qualified as extensions.* throughout.
-- Adding 'extensions' to the search_path would also work and is worse: it
-- widens name resolution for a whole function body to buy three qualifiers.
--
-- ── FORWARD NOTE FOR 10a (20260722000007) ──────────────────────────────────
-- That migration is drafted but NOT applied (confirmed live — actor_display_name
-- and friends are still anon-executable). It ends with a standing assertion that
-- definer functions granting anon, minus an allowlist, is empty. The two RPCs
-- below are granted to anon DELIBERATELY and must be added to that allowlist
-- when 10a is pushed, or the sweep will flag them as regressions. They qualify
-- on the same test the allowlist applies: each re-derives its own authority
-- (a 256-bit token, and for writes a bcrypt PIN check) rather than trusting the
-- caller's role.
--
-- Rollback: supabase/rollback/20260801000000_report_endorsements_rollback.sql
-- Verify:   supabase/diagnostics/verify_20260801000000.sql
-- ============================================================================

begin;

-- ── 1. The endorsement record ──────────────────────────────────────────────
-- One row per report. re-endorsing UPDATES this row (see the RPC's ON CONFLICT)
-- rather than accumulating rows, so there is never more than one live token for
-- a report and "which QR is valid" has exactly one answer.
create table if not exists public.report_endorsements (
  id              uuid primary key default gen_random_uuid(),
  report_id       uuid not null unique
                    references public.reports(id) on delete cascade,

  -- base64url, no padding, 32 random bytes -> 43 chars. Unique so a collision
  -- is a constraint violation rather than a silent cross-report scan.
  token           text not null unique,

  -- bcrypt. The plaintext PIN is never stored, logged, or recoverable.
  pin_hash        text not null,

  agency          text not null,
  reason          text not null,

  -- Human-facing identifier printed on the letter and shown on the scan page.
  reference_code  text not null unique,

  state           text not null default 'endorsed'
                    check (state in ('endorsed', 'received', 'completed')),

  -- Brute-force accounting for the PIN. The token is not guessable, so the PIN
  -- is the only credential worth rate limiting, and per-endorsement is the
  -- correct axis: one agency fumbling its PIN must not lock out another.
  pin_attempts    integer not null default 0,
  locked_until    timestamptz,

  endorsed_by     uuid references auth.users(id) on delete set null,
  endorsed_at     timestamptz not null default now(),
  received_at     timestamptz,
  completed_at    timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index if not exists idx_report_endorsements_agency
  on public.report_endorsements (agency);

-- ── 2. Transition log ──────────────────────────────────────────────────────
-- Append-only. Every state change is recorded with its timestamp, including the
-- initial endorsement, so the full handoff is reconstructable after the fact.
create table if not exists public.report_endorsement_events (
  id              bigserial primary key,
  endorsement_id  uuid not null
                    references public.report_endorsements(id) on delete cascade,
  report_id       uuid not null,
  from_state      text,
  to_state        text not null,
  -- 'admin' when the LGU endorsed; 'agency' when a PIN-authenticated scan
  -- advanced it. Never a person: the agency side has no account to name.
  actor           text not null,
  at              timestamptz not null default now()
);

create index if not exists idx_report_endorsement_events_endorsement
  on public.report_endorsement_events (endorsement_id, at);

-- ── 3. RLS ─────────────────────────────────────────────────────────────────
-- Reads are for the console (admin) and the owning agency's staff. Writes have
-- NO policy at all on either table — every mutation goes through the definer
-- RPCs below, which is what lets the PIN check and the single-transition guard
-- be unbypassable rather than merely customary.
alter table public.report_endorsements       enable row level security;
alter table public.report_endorsement_events enable row level security;

drop policy if exists admin_reads_endorsements on public.report_endorsements;
create policy admin_reads_endorsements
  on public.report_endorsements for select
  to authenticated
  using (public.is_admin());

drop policy if exists staff_reads_own_agency_endorsements on public.report_endorsements;
create policy staff_reads_own_agency_endorsements
  on public.report_endorsements for select
  to authenticated
  using (
    public.current_user_role_id() = 2
    and agency = public.current_staff_department()
  );

drop policy if exists admin_reads_endorsement_events on public.report_endorsement_events;
create policy admin_reads_endorsement_events
  on public.report_endorsement_events for select
  to authenticated
  using (public.is_admin());

-- ── 4. Grants ──────────────────────────────────────────────────────────────
-- Supabase's default privileges grant new tables to anon AND authenticated, so
-- the revoke must name both explicitly — the 20260722000002 lesson, where
-- omitting `authenticated` left an EXPLICIT default grant standing and made the
-- following statement a no-op. SELECT is granted back to authenticated only,
-- where the policies above scope it. No write privilege is granted to anyone:
-- the RPCs run as owner.
--
-- NOTE: pin_hash is deliberately inside the authenticated SELECT grant. It is a
-- bcrypt digest, useless without an offline attack, and admins legitimately read
-- the row to render endorsement state. The PLAINTEXT never lands here at all.
revoke all on public.report_endorsements       from public, anon, authenticated;
revoke all on public.report_endorsement_events from public, anon, authenticated;

grant select on public.report_endorsements       to authenticated;
grant select on public.report_endorsement_events to authenticated;

grant usage, select on sequence public.report_endorsement_events_id_seq to postgres;

-- ── 5. Admin RPC: endorse ──────────────────────────────────────────────────
create or replace function public.endorse_report_to_agency(
  p_report uuid,
  p_agency text,
  p_reason text
)
returns json
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_pin        text;
  v_token      text;
  v_reference  text;
  v_bytes      bytea;
  v_id         uuid;
  v_prev_state text;
  v_status     text;
begin
  if not public.is_admin() then
    raise exception 'Only an LGU admin can endorse a report to an external entity'
      using errcode = '42501';
  end if;

  if coalesce(btrim(p_agency), '') = '' then
    raise exception 'An external entity must be selected' using errcode = '22023';
  end if;

  -- The reason is required by the endorsement form and required here too. A
  -- client-side-only requirement is not a requirement.
  if coalesce(btrim(p_reason), '') = '' then
    raise exception 'A reason for endorsement is required' using errcode = '22023';
  end if;

  if not exists (select 1 from public.reports where id = p_report) then
    raise exception 'Report not found' using errcode = 'P0002';
  end if;

  -- 32 bytes -> base64 -> base64url. translate()'s `to` string is shorter than
  -- its `from`, which DELETES '=' — exactly the unpadded base64url we want in a
  -- URL path segment.
  v_token := translate(encode(extensions.gen_random_bytes(32), 'base64'), '+/=', '-_');

  -- 4-digit PIN from the CSPRNG rather than random(). Two bytes give 0..65535;
  -- the modulo bias across 10000 buckets is immaterial for a credential whose
  -- real defence is the attempt limiter below.
  v_bytes := extensions.gen_random_bytes(2);
  v_pin   := lpad((((get_byte(v_bytes, 0) << 8) | get_byte(v_bytes, 1)) % 10000)::text, 4, '0');

  v_reference := 'END-' || upper(substr(replace(p_report::text, '-', ''), 1, 8));

  select state into v_prev_state
    from public.report_endorsements where report_id = p_report;

  insert into public.report_endorsements
    (report_id, token, pin_hash, agency, reason, reference_code,
     state, pin_attempts, locked_until, endorsed_by, endorsed_at,
     received_at, completed_at, updated_at)
  values
    (p_report, v_token,
     extensions.crypt(v_pin, extensions.gen_salt('bf', 10)),
     btrim(p_agency), btrim(p_reason), v_reference,
     'endorsed', 0, null, auth.uid(), now(),
     null, null, now())
  on conflict (report_id) do update set
    -- Re-endorsing mints a NEW token and PIN. The previously printed letter's
    -- QR stops working, which is the intended behaviour: there is exactly one
    -- valid handoff per report at any time.
    token        = excluded.token,
    pin_hash     = excluded.pin_hash,
    agency       = excluded.agency,
    reason       = excluded.reason,
    state        = 'endorsed',
    pin_attempts = 0,
    locked_until = null,
    endorsed_by  = excluded.endorsed_by,
    endorsed_at  = now(),
    received_at  = null,
    completed_at = null,
    updated_at   = now()
  returning id into v_id;

  insert into public.report_endorsement_events
    (endorsement_id, report_id, from_state, to_state, actor)
  values (v_id, p_report, v_prev_state, 'endorsed', 'admin');

  -- Mirror onto the report, matching what AdminReportsNotifier.endorse() did
  -- before this RPC existed: ownership leaves the LGU, so any internal
  -- assignment is cleared, and a still-pending report advances to under_review
  -- so it never sits looking ignored.
  select status into v_status from public.reports where id = p_report;

  update public.reports
     set endorsed_to_department = btrim(p_agency),
         endorsed_at            = now(),
         endorsed_by            = auth.uid(),
         assigned_to_department = null,
         assigned_at            = null,
         status = case when v_status = 'pending' then 'under_review' else status end
   where id = p_report;

  return json_build_object(
    'token',     v_token,
    'pin',       v_pin,          -- the ONLY time the plaintext is ever emitted
    'reference', v_reference,
    'agency',    btrim(p_agency)
  );
end;
$function$;

revoke all on function public.endorse_report_to_agency(uuid, text, text) from public, anon;
grant execute on function public.endorse_report_to_agency(uuid, text, text) to authenticated;

-- ── 6. Public RPC: read one endorsement by token ───────────────────────────
-- Reachable by anon. Returns a narrow projection chosen so the whole response
-- is safe in the hands of anyone holding the letter. No user_id, no reporter
-- name, no is_anonymous, no coordinates, no media, no internal work log.
create or replace function public.scan_endorsement(p_token text)
returns json
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v json;
begin
  select json_build_object(
           'valid',        true,
           'reference',    e.reference_code,
           'agency',       e.agency,
           'reason',       e.reason,
           'state',        e.state,
           'endorsed_at',  e.endorsed_at,
           'received_at',  e.received_at,
           'completed_at', e.completed_at,
           'locked',       (e.locked_until is not null and e.locked_until > now()),
           'report', json_build_object(
             'category',    public.report_label(r.category, r.category_other),
             'barangay',    r.barangay,
             'address',     r.address,
             'description', r.remarks,
             'reported_at', r.created_at
           )
         )
    into v
    from public.report_endorsements e
    join public.reports r on r.id = e.report_id
   where e.token = p_token;

  -- Uniform negative answer. A missing token and a malformed one are
  -- indistinguishable to the caller, so this endpoint reveals nothing about
  -- which tokens exist.
  return coalesce(v, json_build_object('valid', false));
end;
$function$;

revoke all on function public.scan_endorsement(text) from public;
grant execute on function public.scan_endorsement(text) to anon, authenticated;

-- ── 7. Public RPC: advance the endorsement, PIN-gated ──────────────────────
-- endorsed -> received -> completed, one step per successful call.
create or replace function public.advance_endorsement(
  p_token text,
  p_pin   text
)
returns json
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  e         public.report_endorsements%rowtype;
  v_next    text;
  v_rows    integer;
  v_left    integer;
  c_max_attempts constant integer := 5;
begin
  -- FOR UPDATE serialises concurrent scans of the same QR — two phones hitting
  -- the button at once queue here instead of both reading state 'endorsed'.
  select * into e
    from public.report_endorsements
   where token = p_token
   for update;

  if not found then
    return json_build_object('ok', false, 'error', 'invalid_token');
  end if;

  if e.locked_until is not null and e.locked_until > now() then
    return json_build_object('ok', false, 'error', 'locked',
                             'locked_until', e.locked_until);
  end if;

  -- Terminal state is checked BEFORE the PIN so a completed endorsement stops
  -- consuming attempts, but AFTER the lock so it cannot be used as an oracle
  -- while locked out.
  if e.state = 'completed' then
    return json_build_object('ok', false, 'error', 'already_completed',
                             'state', 'completed');
  end if;

  if e.pin_hash is distinct from extensions.crypt(coalesce(p_pin, ''), e.pin_hash) then
    v_left := greatest(c_max_attempts - (e.pin_attempts + 1), 0);
    update public.report_endorsements
       set pin_attempts = pin_attempts + 1,
           locked_until = case
                            when pin_attempts + 1 >= c_max_attempts
                              then now() + interval '15 minutes'
                            else locked_until
                          end,
           updated_at   = now()
     where id = e.id;
    return json_build_object('ok', false, 'error', 'bad_pin',
                             'attempts_left', v_left);
  end if;

  v_next := case e.state when 'endorsed' then 'received'
                         when 'received' then 'completed' end;

  -- The state is re-asserted in the WHERE clause. FOR UPDATE above already
  -- makes this unreachable, and it stays correct if that lock is ever removed —
  -- a second scan of the same step updates zero rows instead of advancing twice.
  update public.report_endorsements
     set state        = v_next,
         received_at  = case when v_next = 'received'  then now() else received_at  end,
         completed_at = case when v_next = 'completed' then now() else completed_at end,
         pin_attempts = 0,
         locked_until = null,
         updated_at   = now()
   where id = e.id
     and state = e.state;

  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    return json_build_object('ok', false, 'error', 'already_advanced',
                             'state', e.state);
  end if;

  insert into public.report_endorsement_events
    (endorsement_id, report_id, from_state, to_state, actor)
  values (e.id, e.report_id, e.state, v_next, 'agency');

  -- Mirror onto the citizen-facing lifecycle. This is what keeps the console
  -- buckets, the status tracker, and notify_citizen_report_decision correct —
  -- both target values are already in that trigger's CASE, so the citizen is
  -- told their report is being worked on / has been resolved, exactly as if an
  -- internal office had moved it. auth.uid() is null for an anon caller, so the
  -- notification's sent_by is null, which is the same office-not-person shape
  -- 20260722000017 settled on.
  update public.reports
     set status = case when v_next = 'received' then 'in_progress' else 'resolved' end
   where id = e.report_id;

  return json_build_object('ok', true, 'state', v_next);
end;
$function$;

revoke all on function public.advance_endorsement(text, text) from public;
grant execute on function public.advance_endorsement(text, text) to anon, authenticated;

commit;

-- Expected after this migration:
--   * report_endorsements / report_endorsement_events exist, RLS enabled, with
--     SELECT policies only — no INSERT/UPDATE/DELETE policy on either.
--   * anon holds EXECUTE on exactly scan_endorsement + advance_endorsement, and
--     no table privilege on either new table.
--   * endorse_report_to_agency is authenticated-only and refuses a non-admin.
--   * reports.status still only ever holds the five values the Dart enum knows.
