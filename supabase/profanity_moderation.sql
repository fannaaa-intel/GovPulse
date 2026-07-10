-- ════════════════════════════════════════════════════════════════════════════
--  Profanity moderation — community posts & comments (EN / Tagalog / Ilocano)
--
--  Server-side BACKSTOP for the on-device filter (lib/core/moderation/
--  profanity_filter.dart). Even if a modified client bypasses the app, this
--  trigger re-checks the text on INSERT/UPDATE and sets `flagged` + `flag_reason`
--  so the content surfaces to admins for review. The citizen app additionally
--  MASKS flagged words at render time, so profanity is never shown to citizens.
--
--  Nothing is blocked or deleted here — this only FLAGS, matching the
--  "mask + auto-flag for admin" policy. The original text is preserved so admins
--  can judge it and delete/reject if warranted.
--
--  The banned-term list lives in `moderation_terms` so it can be curated without
--  a code deploy. It is intentionally the high-confidence subset (unambiguous
--  roots); the on-device filter carries the fuller, allowlist-guarded lexicon.
-- ════════════════════════════════════════════════════════════════════════════

-- ── Flag columns ─────────────────────────────────────────────────────────────
alter table public.community_posts
  add column if not exists flagged boolean not null default false;
alter table public.community_posts
  add column if not exists flag_reason text;

alter table public.community_comments
  add column if not exists flagged boolean not null default false;
alter table public.community_comments
  add column if not exists flag_reason text;

-- ── Curated banned terms (normalized: lowercase, letters only) ────────────────
create table if not exists public.moderation_terms (
  term text primary key
);

insert into public.moderation_terms(term) values
  -- English
  ('fuck'), ('shit'), ('bitch'), ('asshole'), ('motherfucker'), ('cunt'),
  ('nigger'), ('faggot'), ('whore'),
  -- Tagalog / Filipino
  ('putangina'), ('tangina'), ('kingina'), ('gago'), ('gaga'), ('ulol'),
  ('tarantado'), ('pakyu'), ('kupal'), ('punyeta'), ('hindot'), ('pesteng'),
  -- Ilocano (Cagayan)
  ('ukinnam'), ('ukininam'), ('okinnam'), ('okinam')
on conflict do nothing;

-- ── Normalization (mirrors the on-device filter) ─────────────────────────────
-- lowercase → de-accent + de-leetspeak → non-letters to spaces → collapse
-- repeats → single spaces. Keeping word gaps lets us match at a word boundary
-- so "reputation" is NOT flagged for containing "puta".
create or replace function public.normalize_text(t text)
returns text language sql immutable as $$
  select trim(regexp_replace(
           regexp_replace(
             regexp_replace(
               translate(
                 lower(coalesce(t, '')),
                 '0134578@$!+áàâäéèêíìîóòôúùûüñ',
                 'oieastbasitaaaaeeeiiiooouuuun'
               ),
               '[^a-z]+', ' ', 'g'
             ),
             '(.)\1+', '\1', 'g'
           ),
           '\s+', ' ', 'g'
         ));
$$;

-- A term matches at a WORD START (equal or prefix), catching plain and suffixed
-- forms (gago → gagong, putangina → putanginamo) without mid-word false hits.
create or replace function public.text_has_banned(t text)
returns boolean language sql stable as $$
  select exists (
    select 1
    from public.moderation_terms
    where public.normalize_text(t) ~ ('(^| )' || term)
  );
$$;

-- ── Trigger functions ────────────────────────────────────────────────────────
create or replace function public.flag_profanity_post()
returns trigger language plpgsql as $$
begin
  if public.text_has_banned(
       coalesce(NEW.title, '') || ' ' || coalesce(NEW.body, '')) then
    NEW.flagged := true;
    NEW.flag_reason := 'Possible profanity';
  end if;
  return NEW;
end;
$$;

create or replace function public.flag_profanity_comment()
returns trigger language plpgsql as $$
begin
  if public.text_has_banned(coalesce(NEW.body, '')) then
    NEW.flagged := true;
    NEW.flag_reason := 'Possible profanity';
  end if;
  return NEW;
end;
$$;

-- ── Triggers ─────────────────────────────────────────────────────────────────
-- Fire only when the text columns change, so like/pin updates don't re-scan.
drop trigger if exists trg_flag_profanity_post on public.community_posts;
create trigger trg_flag_profanity_post
  before insert or update of title, body on public.community_posts
  for each row execute function public.flag_profanity_post();

drop trigger if exists trg_flag_profanity_comment on public.community_comments;
create trigger trg_flag_profanity_comment
  before insert or update of body on public.community_comments
  for each row execute function public.flag_profanity_comment();

-- Backfill existing rows so the current feed is scanned once.
update public.community_posts
  set flagged = true, flag_reason = 'Possible profanity'
  where public.text_has_banned(coalesce(title, '') || ' ' || coalesce(body, ''))
    and flagged = false;
update public.community_comments
  set flagged = true, flag_reason = 'Possible profanity'
  where public.text_has_banned(coalesce(body, ''))
    and flagged = false;
