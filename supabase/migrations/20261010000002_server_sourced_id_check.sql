-- 20261010000002_server_sourced_id_check.sql
--
-- The "Passed automated checks" badge in the admin verification console could
-- be forged. verification_submissions.check_* were written by the CITIZEN's
-- app at submit time, so a hand-made insert could claim auto_accept / 100 for
-- an ID no checker ever saw (audit 2026-10-09, verified on production).
--
-- Now the checker records its own result (verify-id → id_check_results, which
-- only the service role can touch), and the submission's check_* columns are
-- filled from THOSE rows by the existing pin trigger. Whatever the app sends
-- for check_* is ignored, so installed app builds keep working unchanged.
--
-- Same combine rule as IdSubmissionCheck.combine() in the app: per side the
-- latest result for this user + ID type in the last 6 hours; the WORST side
-- wins (reject > review > auto_accept, then lowest score); every reason from
-- both sides; the union of source flags. No server result → all NULL, which the
-- console already shows as "not checked" — exactly what phone camera scans
-- (checked on-device with ML Kit, never via verify-id) store today.
--
-- Honest limit: this proves THIS user's ID of THIS type passed the checker
-- recently. It cannot prove the uploaded photo is the one that was checked; the
-- reviewer still looks at the photos.
--
-- VERIFIED BEFORE COMMIT: supabase/diagnostics/verify_20261010000002.sql (16/16 PASS on
-- production inside a rolled-back transaction, 2026-10-09).

create table if not exists public.id_check_results (
  id           bigint generated always as identity primary key,
  user_id      uuid        not null references auth.users(id) on delete cascade,
  id_type      text        not null,
  side         text        not null check (side in ('front', 'back')),
  score        smallint    not null check (score between 0 and 100),
  verdict      text        not null check (verdict in ('auto_accept', 'review', 'reject')),
  reasons      jsonb       not null default '[]'::jsonb,
  source_flags text[]      not null default '{}',
  created_at   timestamptz not null default now()
);

create index if not exists id_check_results_user_recent_idx
  on public.id_check_results (user_id, id_type, side, created_at desc);

comment on table public.id_check_results is
  'One row per verify-id scan. Written only by the verify-id edge function '
  '(service role). Source of truth for verification_submissions.check_*.';

alter table public.id_check_results enable row level security;
revoke all on public.id_check_results from anon, authenticated;
-- No policies on purpose: only the service role (verify-id) and owner-context
-- functions read or write this table.

create or replace function public.server_id_check_for(p_user uuid, p_id_type text)
returns table (score smallint, verdict text, reasons jsonb, source_flags text[], checked_at timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  with latest as (
    select distinct on (r.side) r.side, r.score, r.verdict, r.reasons, r.source_flags, r.created_at,
           case r.verdict when 'reject' then 0 when 'review' then 1 else 2 end as rank
      from public.id_check_results r
     where r.user_id = p_user
       and r.id_type = p_id_type
       and r.created_at > now() - interval '6 hours'
     order by r.side, r.created_at desc
  ), worst as (
    select score, verdict from latest order by rank, score limit 1
  )
  select w.score, w.verdict,
         coalesce((select jsonb_agg(e order by l.rank, l.score)
                     from latest l, jsonb_array_elements(l.reasons) e), '[]'::jsonb),
         coalesce((select array_agg(distinct f) from latest l, unnest(l.source_flags) f), '{}'),
         (select max(created_at) from latest)
    from worst w;
$$;

revoke all on function public.server_id_check_for(uuid, text) from public, anon, authenticated;

-- Same function and trigger as 20261009000000, extended: the check_* columns
-- now come from the server too.
create or replace function public.pin_verification_submission_columns()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
declare
  c record;
begin
  if current_user not in ('authenticated', 'anon') or public.is_admin() then
    return new;
  end if;
  new.status         := 'pending';
  new.reviewed_by    := null;
  new.reviewed_at    := null;
  new.reviewer_notes := null;

  new.check_score        := null;
  new.check_verdict      := null;
  new.check_reasons      := null;
  new.check_source_flags := null;
  new.check_at           := null;
  select * into c from public.server_id_check_for_caller(new.selected_id_type);
  if found and c.verdict is not null then
    new.check_score        := c.score;
    new.check_verdict      := c.verdict;
    new.check_reasons      := c.reasons;
    new.check_source_flags := c.source_flags;
    new.check_at           := c.checked_at;
  end if;
  return new;
end;
$$;

-- The trigger runs as the citizen (SECURITY INVOKER is what makes the
-- current_user test work), so it reaches the private table through this
-- caller-scoped wrapper: it can only ever return the CALLER's own results.
create or replace function public.server_id_check_for_caller(p_id_type text)
returns table (score smallint, verdict text, reasons jsonb, source_flags text[], checked_at timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  select * from public.server_id_check_for(auth.uid(), p_id_type);
$$;

revoke all on function public.server_id_check_for_caller(text) from public, anon;
grant execute on function public.server_id_check_for_caller(text) to authenticated;
