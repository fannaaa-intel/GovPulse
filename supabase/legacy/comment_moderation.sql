-- ════════════════════════════════════════════════════════════════════════════
--  Comment-level approval — conditional moderation for community comments
--
--  Clean comments stay INSTANT (status 'approved') so conversation isn't killed.
--  Only comments the moderation layer flags (profanity trigger below, or the AI
--  moderate-content function) are held as 'pending' for an admin to approve or
--  delete. The author still sees their own pending comment ("under review");
--  everyone else sees it only once approved.
--
--  Run AFTER profanity_moderation.sql (it reuses flagged / flag_reason and the
--  normalize/text_has_banned helpers).
-- ════════════════════════════════════════════════════════════════════════════

-- ── Status + AI-moderation bookkeeping ───────────────────────────────────────
-- ADD COLUMN ... DEFAULT backfills existing rows to 'approved', so nothing that
-- is already live disappears.
alter table public.community_comments
  add column if not exists status text not null default 'approved';
alter table public.community_comments
  add column if not exists ai_moderated_at timestamptz;
alter table public.community_posts
  add column if not exists ai_moderated_at timestamptz;

-- Fast lookups for the admin review queue.
create index if not exists community_comments_pending_idx
  on public.community_comments (created_at desc) where status = 'pending';

-- ── Hold flagged comments for review ─────────────────────────────────────────
-- Redefines the comment trigger from profanity_moderation.sql so a flagged
-- comment is also parked in 'pending'. Approving later is an UPDATE of `status`
-- only (not `body`), so it never re-fires this trigger.
create or replace function public.flag_profanity_comment()
returns trigger language plpgsql as $$
begin
  if public.text_has_banned(coalesce(NEW.body, '')) then
    NEW.flagged := true;
    NEW.flag_reason := coalesce(NEW.flag_reason, 'Possible profanity');
    -- Only hold it on the way in; don't yank an already-approved comment.
    if TG_OP = 'INSERT' then
      NEW.status := 'pending';
    end if;
  end if;
  return NEW;
end;
$$;

-- ── Backfill: park existing flagged comments for review ──────────────────────
update public.community_comments
  set status = 'pending'
  where flagged = true and status = 'approved';
