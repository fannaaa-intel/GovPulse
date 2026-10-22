-- ════════════════════════════════════════════════════════════════════════════
--  Backup & Recovery (admin-only)
--
--  Adds: the `backups` catalogue, the `backup_restores` history, a private
--  `backups` Storage bucket, and `admin_apply_restore()` — the one function
--  that writes restored rows.
--
--  Rollback: supabase/rollback/20261022000000_backup_and_recovery_rollback.sql
--  Verify:   supabase/diagnostics/verify_20261022000000.sql
--  Design:   docs/BACKUP_INVESTIGATION.md, docs/BACKUP_RECOVERY.md
--
--  ── WHY THE RESTORE IS ONE BIG SQL FUNCTION ───────────────────────────────
--
--  This database has 103 user triggers. Most are harmless on a restore, but
--  about 25 fire for EVERY caller with no `current_user` guard, and re-running
--  them would:
--    • re-send real push notifications (trg_push_on_notification → net.http_post)
--    • re-call Groq for every restored report, suggestion and feedback
--    • re-route reports to a different office than the backup recorded
--    • re-flag restored content as profanity or spam
--    • double-count the stored like/comment/confirm counters
--
--  The textbook fix is `SET session_replication_role = replica`. That is NOT
--  available here: the GUC's context is `superuser` and `postgres` on this
--  project has rolsuper = false (verified read-only, 2026-10-22). So instead
--  this function pauses USER triggers per table with
--  `ALTER TABLE ... DISABLE TRIGGER USER`, which `postgres` may do because it
--  owns all 38 tables (verified).
--
--  Three properties make that safe rather than reckless:
--
--   1. ONE TRANSACTION. The disable, the writes, the counter rebuild and the
--      re-enable are atomic. Any failure — or a crash — rolls the triggers
--      back ON with the data. There is no window where the triggers are off
--      and the transaction has been committed.
--
--   2. DISABLE TRIGGER USER takes an ACCESS EXCLUSIVE lock. Other sessions
--      BLOCK for the duration rather than writing trigger-free. A citizen
--      filing a report mid-restore waits, then runs with every trigger intact.
--      `lock_timeout` keeps that wait bounded and turns contention into a
--      clean "try again in a minute" instead of a stuck console.
--
--   3. FK CONSTRAINT TRIGGERS ARE NOT TOUCHED. `USER` excludes them, so every
--      foreign key is still enforced on every inserted row. A backup that
--      references a deleted parent fails loudly instead of creating orphans.
--      This is why the tier order below is load-bearing.
--
--  ── WHAT THIS FUNCTION DELIBERATELY WILL NOT DO ───────────────────────────
--   • It never DELETEs. v1 is additive only: `missing_only` inserts absent
--     rows, `missing_and_changed` also updates present ones. Nothing is
--     removed, so a restore can never be the thing that loses data.
--   • It never touches `notifications` or `community_notifications`. They are
--     not in the allowlist and are rejected if a file somehow carries them.
--   • It never creates auth users. A row whose user id is gone is skipped and
--     counted.
-- ════════════════════════════════════════════════════════════════════════════

begin;

-- ──────────────────────────────────────────────────────────────────────────────
-- 1 ── The backup catalogue
-- ──────────────────────────────────────────────────────────────────────────────

create table if not exists public.backups (
  id             uuid primary key default gen_random_uuid(),
  name           text not null unique,
  label          text,
  -- manual      = an admin pressed Create backup
  -- pre_restore = the automatic safety copy taken before a restore
  -- automatic   = a future scheduled job (nothing creates these yet)
  kind           text not null default 'manual'
                   check (kind in ('manual', 'pre_restore', 'automatic')),
  created_by     uuid references auth.users(id) on delete set null,
  created_at     timestamptz not null default now(),
  file_path      text,
  size_bytes     bigint,
  -- {"reports": 13, "profiles": 9, ...}
  table_counts   jsonb not null default '{}'::jsonb,
  total_records  integer not null default 0,
  -- The newest applied migration when the file was written, so a restore can
  -- warn about schema drift instead of failing halfway.
  schema_version text,
  app_version    text,
  checksum       text,
  status         text not null default 'creating'
                   check (status in ('creating', 'ready', 'failed')),
  error          text
);

comment on table public.backups is
  'Catalogue of encrypted data backups. Files live in the private `backups` bucket; only the edge function writes here.';

create index if not exists backups_created_at_idx
  on public.backups (created_at desc);
create index if not exists backups_kind_created_idx
  on public.backups (kind, created_at desc);

create table if not exists public.backup_restores (
  id               uuid primary key default gen_random_uuid(),
  backup_id        uuid references public.backups(id) on delete set null,
  -- missing_only        = insert rows whose PK is absent
  -- missing_and_changed = also update rows that exist but differ
  mode             text not null
                     check (mode in ('missing_only', 'missing_and_changed')),
  started_by       uuid references auth.users(id) on delete set null,
  started_at       timestamptz not null default now(),
  finished_at      timestamptz,
  status           text not null default 'running'
                     check (status in ('running', 'completed', 'failed')),
  -- {"reports": {"added": 1, "updated": 0, "unchanged": 12, "skipped": 0}, ...}
  result           jsonb,
  -- The safety copy taken immediately before this restore.
  safety_backup_id uuid references public.backups(id) on delete set null,
  error            text
);

comment on table public.backup_restores is
  'History of restores, including the automatic safety copy taken before each one.';

create index if not exists backup_restores_started_at_idx
  on public.backup_restores (started_at desc);

-- ──────────────────────────────────────────────────────────────────────────────
-- 2 ── RLS: admins READ, nobody writes from a client
--
-- The edge function writes with the service role, which bypasses RLS. Giving
-- the client no INSERT/UPDATE/DELETE policy at all means a compromised admin
-- session cannot forge a backup row claiming a file exists, or rewrite the
-- restore history to hide what it did.
-- ──────────────────────────────────────────────────────────────────────────────

alter table public.backups          enable row level security;
alter table public.backup_restores  enable row level security;

drop policy if exists backups_admin_read on public.backups;
create policy backups_admin_read on public.backups
  for select to authenticated
  using (exists (
    select 1 from public.user_roles ur
     where ur.user_id = (select auth.uid()) and ur.role_id = 1
  ));

drop policy if exists backup_restores_admin_read on public.backup_restores;
create policy backup_restores_admin_read on public.backup_restores
  for select to authenticated
  using (exists (
    select 1 from public.user_roles ur
     where ur.user_id = (select auth.uid()) and ur.role_id = 1
  ));

-- Belt and braces: even a future policy mistake cannot grant writes that were
-- never granted at the table level.
revoke insert, update, delete on public.backups         from anon, authenticated;
revoke insert, update, delete on public.backup_restores from anon, authenticated;

-- ──────────────────────────────────────────────────────────────────────────────
-- 3 ── The private bucket
--
-- No policies for anon/authenticated are created, so the ONLY way to reach a
-- file is the service role minting a short-lived signed URL. 50 MB ceiling:
-- today's whole dataset is far under 1 MB, and a cap keeps a runaway export
-- from filling the Free-plan quota.
-- ──────────────────────────────────────────────────────────────────────────────

insert into storage.buckets (id, name, public, file_size_limit)
values ('backups', 'backups', false, 52428800)
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit;

-- ──────────────────────────────────────────────────────────────────────────────
-- 4 ── admin_apply_restore
--
-- Signature:
--   p_payload  jsonb   the decrypted backup: {tables: {name: {rows: [...]}}}
--   p_mode     text    'missing_only' | 'missing_and_changed'
--   p_dry_run  boolean true = count only; NO ALTER TABLE, NO writes
--
-- Returns jsonb:
--   {"tables": {"<name>": {"added":n,"updated":n,"unchanged":n,
--                          "skipped_missing_user":n,"skipped_too_old":n}},
--    "warnings": [...], "dry_run": bool}
--
-- SECURITY DEFINER, owner postgres, EXECUTE to service_role only. The edge
-- function supplies the payload; the caller's identity is checked there (role 1
-- + password + typed confirmation) because service_role has no auth.uid().
-- ──────────────────────────────────────────────────────────────────────────────

create or replace function public.admin_apply_restore(
  p_payload jsonb,
  p_mode    text default 'missing_only',
  p_dry_run boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  -- Restore order. MUST match supabase/functions/_shared/backup_tables.ts:
  -- parents before children, because FK constraint triggers stay enabled.
  -- `roles` is first (user_roles.role_id is ON DELETE RESTRICT); the audit log
  -- is last (append-only).
  c_order constant text[] := array[
    'roles','moderation_settings','moderation_terms','moderation_allow_terms','lgu_facts',
    'profiles','user_roles','citizen_details','admin_details','staff_details','admin_profiles',
    'user_restrictions','user_suspensions','notification_preferences',
    'reports','suggestions','feedbacks','events','verification_submissions','concern_tickets',
    'report_media','report_notes','report_updates','report_resolution_media',
    'report_endorsements','suggestion_media','suggestion_replies',
    'ticket_messages','ticket_attachments',
    'report_update_media','report_endorsement_events','agency_feedback',
    'community_posts','community_post_images','community_post_likes','community_comments',
    'community_comment_likes',
    'admin_activity_log'
  ];

  -- Tables that must NEVER be written by a restore, whatever the file says.
  -- A second, independent line of defence: the edge function filters them out
  -- of the backup, and this function refuses them even if one appears.
  c_forbidden constant text[] := array[
    'notifications','community_notifications','notification_receipts','device_tokens',
    'rate_limits','otp_failures','login_failures','pending_signups',
    'ai_dashboard_insights','id_check_results','kuya_gov_knowledge_gaps',
    'backups','backup_restores','backup_jobs'
  ];

  -- Self-referencing columns, restored in a second pass.
  c_self_ref constant jsonb := jsonb_build_object(
    'reports', 'duplicate_of',
    'community_comments', 'parent_comment_id'
  );

  -- Columns naming an auth.users row that must still exist. A row pointing at
  -- a deleted account is skipped, never inserted with a dangling reference.
  c_user_col constant jsonb := jsonb_build_object(
    'profiles', 'id',
    'user_roles', 'user_id',
    'citizen_details', 'user_id',
    'admin_details', 'user_id',
    'staff_details', 'user_id',
    'admin_profiles', 'user_id',
    'notification_preferences', 'user_id',
    'user_restrictions', 'user_id',
    'user_suspensions', 'user_id'
  );

  c_age_days constant integer := 90;  -- admin_activity_log prune window

  v_tbl           text;
  v_rows          jsonb;
  v_pk            text[];
  v_cols          text[];
  v_live_cols     text[];
  v_use_cols      text[];
  v_self          text;
  v_user_col      text;
  v_added         integer;
  v_updated       integer;
  v_unchanged     integer;
  v_skipped_user  integer;
  v_skipped_old   integer;
  v_out           jsonb := '{}'::jsonb;
  v_warnings      jsonb := '[]'::jsonb;
  v_locked        text[] := array[]::text[];
  v_sql           text;
  v_seq_col       text;
  v_present       jsonb;
  v_staged        integer;
begin
  if p_mode not in ('missing_only', 'missing_and_changed') then
    raise exception 'Unknown restore mode: %', p_mode using errcode = '22023';
  end if;
  if p_payload is null or p_payload->'tables' is null then
    raise exception 'This backup has no table data.' using errcode = '22023';
  end if;

  -- Bounded waits. Contention becomes a clean message, not a hung console.
  -- Only meaningful for a real run: a dry run takes no ACCESS EXCLUSIVE lock.
  if not p_dry_run then
    set local lock_timeout = '5s';
    set local statement_timeout = '60s';
  end if;

  -- ── Refuse a file carrying a forbidden table ─────────────────────────────
  --
  -- This loop walks the PAYLOAD's keys; the restore loop below walks c_order.
  -- That asymmetry matters: a table present in the file but absent from
  -- c_order is never visited by the restore loop at all, so without the second
  -- check here it would be dropped in total silence -- no rows restored, no
  -- warning, and a count that looks correct because the table simply is not in
  -- it. That is how a backup taken before a table was removed from the
  -- allowlist would quietly lose data on restore.
  for v_tbl in select jsonb_object_keys(p_payload->'tables') loop
    if v_tbl = any (c_forbidden) then
      raise exception
        'This backup contains %, which is never restored (it would re-send notifications or reset anti-spam counters).',
        v_tbl
        using errcode = '22023';
    end if;

    if not (v_tbl = any (c_order)) then
      v_warnings := v_warnings || to_jsonb(format(
        'Table "%s" is in the backup but is not part of this restore; its rows were skipped.',
        v_tbl));
    end if;
  end loop;

  -- ── Pause USER triggers, in a FIXED alphabetical order ───────────────────
  -- Alphabetical, not restore order: every session that ever locks these
  -- tables in bulk must take them in the SAME sequence, or two concurrent runs
  -- deadlock. The advisory lock in the edge function makes that near-
  -- impossible, but ordering costs nothing and removes the class of bug.
  if not p_dry_run then
    for v_tbl in
      select t from unnest(c_order) t
       where to_regclass('public.' || quote_ident(t)) is not null
       order by t
    loop
      execute format('alter table public.%I disable trigger user', v_tbl);
      v_locked := v_locked || v_tbl;
    end loop;
  end if;

  -- ── Table by table, in FK order ──────────────────────────────────────────
  foreach v_tbl in array c_order loop
    v_rows := p_payload->'tables'->v_tbl->'rows';
    if v_rows is null or jsonb_typeof(v_rows) <> 'array'
       or jsonb_array_length(v_rows) = 0 then
      continue;
    end if;

    if to_regclass('public.' || quote_ident(v_tbl)) is null then
      v_warnings := v_warnings || to_jsonb(
        format('Table "%s" is in the backup but no longer exists; skipped.', v_tbl));
      continue;
    end if;

    v_added := 0; v_updated := 0; v_unchanged := 0;
    v_skipped_user := 0; v_skipped_old := 0;

    -- Primary key from the LIVE catalogue, not the file: if the key changed,
    -- the live definition is the one that governs the upsert.
    select array_agg(a.attname order by k.ord)
      into v_pk
      from pg_constraint pc
      join unnest(pc.conkey) with ordinality k(att, ord) on true
      join pg_attribute a on a.attrelid = pc.conrelid and a.attnum = k.att
     where pc.conrelid = ('public.' || quote_ident(v_tbl))::regclass
       and pc.contype = 'p';

    if v_pk is null then
      v_warnings := v_warnings || to_jsonb(
        format('Table "%s" has no primary key; skipped.', v_tbl));
      continue;
    end if;

    -- ── Schema drift: intersect the file's columns with the live ones ──────
    select array_agg(distinct key) into v_cols
      from jsonb_array_elements(v_rows) r, jsonb_object_keys(r.value) key;

    select array_agg(a.attname) into v_live_cols
      from pg_attribute a
     where a.attrelid = ('public.' || quote_ident(v_tbl))::regclass
       and a.attnum > 0 and not a.attisdropped
       -- Generated columns cannot be written. (None today; a future one would
       -- otherwise abort the whole restore.)
       and a.attgenerated = '';

    select array_agg(c) into v_use_cols
      from unnest(v_cols) c where c = any (v_live_cols);

    if v_use_cols is null then
      v_warnings := v_warnings || to_jsonb(
        format('Table "%s": none of its backed-up columns still exist; skipped.', v_tbl));
      continue;
    end if;

    -- Report dropped columns rather than discarding them quietly.
    if array_length(v_use_cols, 1) < array_length(v_cols, 1) then
      v_warnings := v_warnings || to_jsonb(format(
        'Table "%s": %s column(s) in the backup no longer exist and were ignored (%s).',
        v_tbl,
        array_length(v_cols, 1) - array_length(v_use_cols, 1),
        (select string_agg(c, ', ') from unnest(v_cols) c where not (c = any (v_live_cols)))));
    end if;

    -- Every PK column must have survived, or rows cannot be matched at all.
    if exists (select 1 from unnest(v_pk) k where not (k = any (v_use_cols))) then
      v_warnings := v_warnings || to_jsonb(format(
        'Table "%s": the backup is missing part of its primary key; skipped.', v_tbl));
      continue;
    end if;

    v_self := c_self_ref->>v_tbl;
    v_user_col := c_user_col->>v_tbl;

    -- ── Stage the file's rows into a typed temp table ─────────────────────
    -- jsonb_populate_record casts each JSON value to the real column type, so
    -- a text timestamp becomes timestamptz and a malformed value fails HERE,
    -- with the table named, rather than deep inside the INSERT.
    --
    -- The populated record is expanded in an outer SELECT rather than inline:
    -- `select (jsonb_populate_record(...)).*` re-evaluates the function once
    -- per output column, which on a wide table is both slow and a trap if the
    -- cast ever has a side effect. One subquery, expanded once.
    execute format('drop table if exists _restore_stage');
    execute format(
      'create temp table _restore_stage as
         select (r).*
           from (select jsonb_populate_record(null::public.%I, elem) as r
                   from jsonb_array_elements($1) as t(elem)) q',
      v_tbl) using v_rows;

    -- ── Drop rows whose auth user is gone (decision 2) ────────────────────
    if v_user_col is not null then
      execute format(
        'delete from _restore_stage s
          where s.%I is not null
            and not exists (select 1 from auth.users u where u.id = s.%I)',
        v_user_col, v_user_col);
      get diagnostics v_skipped_user = row_count;
    end if;

    -- ── admin_activity_log: only the last 90 days ─────────────────────────
    -- The 03:00 prune job deletes anything older, so inserting it is churn the
    -- next run undoes — and it would make these counts misleading.
    if v_tbl = 'admin_activity_log' then
      execute format(
        'delete from _restore_stage where created_at < now() - interval ''%s days''',
        c_age_days);
      get diagnostics v_skipped_old = row_count;
    end if;

    -- ── Count what already matches, for the preview and the result ─────────
    v_sql := format(
      'select jsonb_build_object(
                ''present'', count(*) filter (where live.%I is not null),
                ''differs'',  count(*) filter (where live.%I is not null and not %s))
         from _restore_stage s
         left join public.%I live on %s',
      v_pk[1], v_pk[1],
      -- "same" = every restorable column equal (NULL-safe).
      (select string_agg(format('live.%I is not distinct from s.%I', c, c), ' and ')
         from unnest(v_use_cols) c),
      v_tbl,
      (select string_agg(format('live.%I = s.%I', k, k), ' and ') from unnest(v_pk) k));
    execute v_sql into v_present;

    v_unchanged := (v_present->>'present')::int - (v_present->>'differs')::int;

    if p_dry_run then
      -- Rows to ADD = staged (after the skips above) minus already-present.
      execute 'select count(*) from _restore_stage' into v_staged;
      v_added := v_staged - (v_present->>'present')::int;
      v_updated := case when p_mode = 'missing_and_changed'
                        then (v_present->>'differs')::int else 0 end;
    else
      -- ── Pass 1: insert, with any self-FK held back as NULL ──────────────
      v_sql := format(
        -- The alias `s` is REQUIRED: the column list below emits `s.<col>`,
        -- so a bare `from _restore_stage` fails with 42P01 "missing
        -- FROM-clause entry for table s" on every real restore. The dry run
        -- never reaches here, which is why only a non-dry-run test catches it.
        'insert into public.%I (%s) select %s from _restore_stage s
           on conflict (%s) do %s',
        v_tbl,
        (select string_agg(quote_ident(c), ', ') from unnest(v_use_cols) c),
        -- The self-FK goes in as NULL and is filled by pass 2 below.
        -- `null` needs no cast here: the INSERT's own column list gives it the
        -- target type.
        (select string_agg(
            case when c = v_self then 'null' else format('s.%I', c) end, ', ')
           from unnest(v_use_cols) c),
        (select string_agg(quote_ident(k), ', ') from unnest(v_pk) k),
        case
          when p_mode = 'missing_and_changed' and v_tbl <> 'admin_activity_log'
          then 'update set ' || (
            select string_agg(format('%I = excluded.%I', c, c), ', ')
              from unnest(v_use_cols) c
             where not (c = any (v_pk)) and c is distinct from v_self)
          else 'nothing'
        end);
      execute v_sql;
      get diagnostics v_added = row_count;

      -- INSERT ... ON CONFLICT DO UPDATE reports inserted + updated together,
      -- so split them using the pre-computed counts.
      if p_mode = 'missing_and_changed' and v_tbl <> 'admin_activity_log' then
        v_updated := least(v_added, (v_present->>'differs')::int);
        v_added := v_added - v_updated;
      else
        v_updated := 0;
      end if;

      -- ── Pass 2: fill the self-FK now that every row exists ──────────────
      -- Held back as NULL in pass 1 because a parent that sorts after its own
      -- child would fail its FK. The `exists` guard keeps a pointer to a row
      -- that is NOT in this backup (and not already live) as NULL rather than
      -- failing the whole restore — which matches the column's own
      -- ON DELETE SET NULL semantics for reports.duplicate_of.
      if v_self is not null then
        execute format(
          'update public.%I live
              set %I = s.%I
             from _restore_stage s
            where %s
              and s.%I is not null
              and live.%I is distinct from s.%I
              and exists (select 1 from public.%I p where p.%I = s.%I)',
          v_tbl, v_self, v_self,
          (select string_agg(format('live.%I = s.%I', k, k), ' and ') from unnest(v_pk) k),
          v_self, v_self, v_self, v_tbl, v_pk[1], v_self);
      end if;
    end if;

    v_out := v_out || jsonb_build_object(v_tbl, jsonb_build_object(
      'added', greatest(v_added, 0),
      'updated', greatest(v_updated, 0),
      'unchanged', greatest(v_unchanged, 0),
      'skipped_missing_user', v_skipped_user,
      'skipped_too_old', v_skipped_old));

    execute 'drop table if exists _restore_stage';
  end loop;

  -- ── Rebuild the counters the paused triggers normally maintain ───────────
  -- Formulas copied from the live trigger bodies (bump_comment_counts,
  -- bump_post_likes_count, bump_comment_likes_count) so the rebuilt value is
  -- what incremental bumping would have produced. recount_report_confirms is
  -- reused as-is rather than reimplemented.
  if not p_dry_run then
    update public.community_posts p set
      comments_count = (select count(*) from public.community_comments c where c.post_id = p.id),
      likes_count    = (select count(*) from public.community_post_likes l where l.post_id = p.id);

    update public.community_comments c set
      likes_count   = (select count(*) from public.community_comment_likes l where l.comment_id = c.id),
      replies_count = (select count(*) from public.community_comments r where r.parent_comment_id = c.id);

    perform public.recount_report_confirms(id)
       from public.reports
      where duplicate_of is null;

    -- ── Sequences, so the next insert does not collide ────────────────────
    -- Driven from the catalogue rather than a hand-kept list, so a sequence
    -- added later is reset too. Covers both `serial` defaults and identity
    -- columns (pg_get_serial_sequence returns both). `is_called := mx is not
    -- null` means an empty table is left pointing at the first value rather
    -- than skipping one.
    for v_tbl, v_seq_col in
      select t.tbl, a.attname
        from unnest(c_order) t(tbl)
        join pg_attribute a
          on a.attrelid = ('public.' || quote_ident(t.tbl))::regclass
         and a.attnum > 0 and not a.attisdropped
       where to_regclass('public.' || quote_ident(t.tbl)) is not null
         and pg_get_serial_sequence('public.' || quote_ident(t.tbl), a.attname) is not null
    loop
      execute format(
        'select setval(pg_get_serial_sequence(%L, %L),
                       greatest(coalesce((select max(%I) from public.%I), 0), 1),
                       (select max(%I) from public.%I) is not null)',
        'public.' || v_tbl, v_seq_col, v_seq_col, v_tbl, v_seq_col, v_tbl);
    end loop;

    -- ── Hand the triggers back ────────────────────────────────────────────
    -- Reverse order, mirroring how they were taken. A failure before this
    -- point rolls the whole transaction back, triggers included — there is no
    -- path that commits with triggers still disabled.
    foreach v_tbl in array v_locked loop
      execute format('alter table public.%I enable trigger user', v_tbl);
    end loop;
  end if;

  return jsonb_build_object(
    'dry_run',  p_dry_run,
    'mode',     p_mode,
    'tables',   v_out,
    'warnings', v_warnings);
exception
  when lock_not_available then
    raise exception 'GovPulse is busy. Try the restore again in a minute.'
      using errcode = '55P03';
end;
$$;

comment on function public.admin_apply_restore(jsonb, text, boolean) is
  'Applies a decrypted GovPulse backup additively inside one transaction. Pauses USER triggers (FK checks stay on), rebuilds stored counters, resets sequences. Dry run counts only. service_role only.';

-- The app's roles must NEVER be able to call this: it writes with triggers off.
revoke all on function public.admin_apply_restore(jsonb, text, boolean)
  from public, anon, authenticated;
grant execute on function public.admin_apply_restore(jsonb, text, boolean)
  to service_role;

-- ──────────────────────────────────────────────────────────────────────────────
-- 4b ── "Is another backup or restore already running?"
--
-- One job at a time, project-wide. A SESSION-scoped advisory lock would be
-- wrong here: edge functions run over a shared connection pool, so the session
-- that takes the lock is not reliably the one that releases it, and a lock
-- could outlive its request and wedge the feature until the pooler recycled.
--
-- Instead the claim is a ROW, with a transaction-scoped advisory lock serialising
-- the check-and-set. Stale claims expire on their own, so a function that dies
-- mid-flight cannot block the next attempt forever.
-- ──────────────────────────────────────────────────────────────────────────────

create table if not exists public.backup_jobs (
  id         boolean primary key default true check (id),  -- exactly one row
  kind       text not null,
  actor_id   uuid,
  started_at timestamptz not null default now()
);

alter table public.backup_jobs enable row level security;
revoke all on public.backup_jobs from anon, authenticated;

comment on table public.backup_jobs is
  'At most one row: the backup/restore currently running. Claimed and released by backup_job_claim/backup_job_release.';

/**
 * Claim the job slot. Returns true when the caller may proceed.
 *
 * A claim older than p_stale_seconds is taken over: the previous attempt died
 * without releasing (function timeout, cold stop), and the alternative is a
 * feature that stays broken until someone clears a table by hand.
 */
create or replace function public.backup_job_claim(
  p_kind text,
  p_actor uuid default null,
  p_stale_seconds integer default 900
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- Serialise the check-and-set. Transaction-scoped: released at commit or
  -- rollback, whichever comes first, with no cleanup to forget.
  perform pg_advisory_xact_lock(hashtext('govpulse:backup_job'));

  delete from public.backup_jobs
   where started_at < now() - make_interval(secs => p_stale_seconds);

  if exists (select 1 from public.backup_jobs) then
    return false;
  end if;

  insert into public.backup_jobs (id, kind, actor_id)
  values (true, p_kind, p_actor)
  on conflict (id) do nothing;

  return true;
end;
$$;

create or replace function public.backup_job_release()
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  delete from public.backup_jobs;
$$;

revoke all on function public.backup_job_claim(text, uuid, integer)
  from public, anon, authenticated;
revoke all on function public.backup_job_release() from public, anon, authenticated;
grant execute on function public.backup_job_claim(text, uuid, integer) to service_role;
grant execute on function public.backup_job_release() to service_role;

-- ──────────────────────────────────────────────────────────────────────────────
-- 5 ── Read-only helper: the live public tables, for the coverage check
--
-- The edge function needs the list to prove every table is classified, and
-- `information_schema` is permission-filtered for non-owners (it under-reports
-- and would make a missing table look classified). pg_class is the truth.
-- ──────────────────────────────────────────────────────────────────────────────

create or replace function public.admin_list_public_tables()
returns setof text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select c.relname::text
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r'
   order by c.relname;
$$;

revoke all on function public.admin_list_public_tables() from public, anon, authenticated;
grant execute on function public.admin_list_public_tables() to service_role;

commit;
