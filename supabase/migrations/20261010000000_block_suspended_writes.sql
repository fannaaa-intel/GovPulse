-- 20261010000000_block_suspended_writes.sql
--
-- Suspension and deactivation are enforced by the DATABASE, not only the app.
--
-- Before this, both lived in the client: CitizenGuard shows a blocking modal and
-- signs a suspended citizen out, and the splash screen signs out a deactivated
-- one. Neither ends the session, and no RLS policy or trigger read either flag,
-- so anyone calling PostgREST directly with a still-valid session (refresh
-- tokens keep it alive indefinitely) could keep filing reports, commenting,
-- liking and messaging staff.
--
-- "Blocked" = profiles.is_deactivated, OR a user_suspensions row that is not
-- lifted and not expired — exactly the rule CitizenGuard.refresh() applies.
--
-- VERIFIED BEFORE COMMIT: supabase/diagnostics/verify_20261010000000.sql (25/25 PASS on
-- production inside a rolled-back transaction, 2026-10-09).
--
-- Scope: BEFORE INSERT on every table a citizen writes content to, plus
-- BEFORE UPDATE on community_comments (editing a comment). DELETE is left open
-- on purpose: removing your own like/comment is harmless. Reads are untouched.
--
-- Same guard rule as 20261009000000: only a DIRECT PostgREST call
-- (current_user = authenticated/anon) is checked. SECURITY DEFINER functions
-- (owner postgres) and edge functions (service_role) pass through, so staff
-- and admin actions ON a suspended citizen's records keep working.
--
-- Uses auth.uid() — the ACTOR — not the row's user column, so it also blocks a
-- deactivated staff member's direct inserts on these tables.

-- Self-only lookup: takes no argument, so it cannot be used to probe whether
-- SOMEONE ELSE is suspended.
create or replace function public.caller_account_blocked()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
           select 1 from public.profiles p
            where p.id = auth.uid() and coalesce(p.is_deactivated, false)
         )
      or exists (
           select 1 from public.user_suspensions s
            where s.user_id = auth.uid()
              and s.lifted_at is null
              and (s.expires_at is null or s.expires_at > now())
         );
$$;

revoke all on function public.caller_account_blocked() from public, anon;
grant execute on function public.caller_account_blocked() to authenticated;

create or replace function public.block_suspended_writes()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;
  if public.caller_account_blocked() then
    raise exception 'suspended'
      using errcode = 'P0001',
            hint    = 'account_suspended',
            detail  = 'Your account is suspended or deactivated. Contact the LGU to restore access.';
  end if;
  return new;
end;
$$;

do $$
declare t text;
begin
  foreach t in array array[
    'reports', 'report_media', 'suggestions', 'suggestion_media', 'feedbacks',
    'community_posts', 'community_post_images', 'community_comments',
    'community_post_likes', 'community_comment_likes',
    'concern_tickets', 'ticket_messages', 'verification_submissions'
  ] loop
    execute format('drop trigger if exists trg_ab_block_suspended on public.%I', t);
    execute format(
      'create trigger trg_ab_block_suspended before insert on public.%I
         for each row execute function public.block_suspended_writes()', t);
  end loop;
end $$;

drop trigger if exists trg_ab_block_suspended_edit on public.community_comments;
create trigger trg_ab_block_suspended_edit
  before update on public.community_comments
  for each row execute function public.block_suspended_writes();
