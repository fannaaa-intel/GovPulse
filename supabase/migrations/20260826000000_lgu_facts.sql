-- ─────────────────────────────────────────────────────────────────────────────
-- 20260826000000  lgu_facts — grounded local knowledge for Kuya Gov
-- ─────────────────────────────────────────────────────────────────────────────
--
-- THE PROBLEM
-- supabase/functions/chat-agent/index.ts carries APARRI_FACTS, a const struct
-- whose every field ships as "". aparriFactsBlock() renders each blank as
--   [WALANG DATA — sabihin sa citizen na i-confirm sa munisipyo, huwag mag-imbento]
-- and the ACCURACY section of SYSTEM_PROMPT then correctly forbids the model
-- from filling the gap. So the bot answers "hindi po ako sigurado" to questions
-- about Aparri itself — the one subject it exists to be expert in.
--
-- Filling that struct in TypeScript would work exactly once. Officials change
-- every election, hotlines change, offices move; a fact that needs a redeploy
-- to correct is a fact that goes stale silently. Worse, the people who KNOW
-- these values (the LGU) cannot edit a Deno file.
--
-- THE FIX
-- Move the facts into a table the LGU edits, read live per conversation, the
-- same way `events` already reaches the model: fetched client-side, injected as
-- a grounded block the prompt is told to treat as its only source of truth.
--
-- ── DESIGN NOTES ─────────────────────────────────────────────────────────────
-- * Key/value, not one column per fact. A wide table needs a migration for
--   every new question type ("sino ang SB member?"); a keyed table needs an
--   INSERT. The chat function does not hardcode key names — it renders whatever
--   rows it is handed, so a new fact reaches citizens with no code change.
-- * `label` travels WITH the value because the model needs to know what the
--   string means. Storing 'mayor' -> 'Juan Cruz' and captioning it in TypeScript
--   would put the caption back in the deploy path, which is the bug being fixed.
-- * NO SEED VALUES. This migration creates the shape and leaves it empty on
--   purpose. Officials' names and hotlines in a government app must come from
--   the LGU, verified. An invented value here is strictly worse than the
--   "confirm at the office" answer the empty state already produces — the bot
--   degrades honestly, and that behaviour is preserved when rows are absent.
-- * `is_published` gates a half-typed fact from reaching citizens mid-edit.
-- * `sort_order` is what the LGU controls; the read path orders by it so the
--   most-asked facts sit at the top of a token-bounded block.
--
-- Additive and idempotent.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── §1  The table ────────────────────────────────────────────────────────────
create table if not exists public.lgu_facts (
  key           text primary key,
  label         text        not null,
  value         text        not null default '',
  category      text        not null default 'general',
  sort_order    integer     not null default 100,
  is_published  boolean     not null default true,
  updated_at    timestamptz not null default now(),
  updated_by    uuid        references auth.users(id) on delete set null
);

comment on table public.lgu_facts is
  'Verified LGU Aparri facts injected into the Kuya Gov chat prompt. Edited by admins; never seeded with guessed data.';
comment on column public.lgu_facts.label is
  'Human caption sent to the model alongside the value, e.g. "Kasalukuyang Mayor". Lives here so a new fact needs no redeploy.';
comment on column public.lgu_facts.value is
  'Empty string = not yet verified. The chat prompt tells the model to say "confirm at the office" rather than guess.';

-- ── §2  Row template ─────────────────────────────────────────────────────────
-- Keys and captions only, values deliberately ''. This gives the LGU a form to
-- fill rather than a blank table to invent a schema for, while keeping the
-- honest-degradation behaviour until each row is actually filled.
-- `on conflict do nothing` so a re-run never overwrites a filled-in value.
insert into public.lgu_facts (key, label, category, sort_order) values
  ('mayor',                  'Kasalukuyang Mayor ng Aparri',        'officials', 10),
  ('vice_mayor',             'Kasalukuyang Vice Mayor',             'officials', 20),
  ('sangguniang_bayan',      'Mga miyembro ng Sangguniang Bayan',   'officials', 30),
  ('municipal_hall_hours',   'Oras ng Municipal Hall',              'contact',   40),
  ('municipal_hall_location','Lokasyon ng Municipal Hall',          'contact',   50),
  ('municipal_hotline',      'Hotline ng munisipyo',                'contact',   60),
  ('emergency_number',       'Emergency number',                    'contact',   70),
  ('cedula_office',          'Saan kumuha ng Cedula',               'services',  80),
  ('business_permit_office', 'Business permit office (BPLO)',       'services',  90),
  ('osca_office',            'Senior Citizen (OSCA) office',        'services', 100),
  ('pdao_office',            'PWD ID office (PDAO/MSWDO)',          'services', 110),
  ('barangay_list',          'Mga barangay ng Aparri',              'general',  120)
on conflict (key) do nothing;

-- The one value seeded with content: 911 is the nationwide PH emergency number,
-- not an Aparri-specific guess, and v5 already shipped it as the sole non-empty
-- field in APARRI_FACTS. Leaving it blank would have been a REGRESSION — the bot
-- would stop giving an emergency number to someone reporting a fire. If Aparri
-- has its own local hotline, an admin appends it to this row.
update public.lgu_facts
   set value = '911'
 where key = 'emergency_number'
   and value = '';

-- ── §3  Keep updated_at honest ───────────────────────────────────────────────
create or replace function public.touch_lgu_facts()
  returns trigger
  language plpgsql
  security invoker
  set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_touch_lgu_facts on public.lgu_facts;
create trigger trg_touch_lgu_facts
  before update on public.lgu_facts
  for each row execute function public.touch_lgu_facts();

-- ── §4  RLS ──────────────────────────────────────────────────────────────────
-- Read: every authenticated citizen, published rows only. These are public
-- civic facts — the mayor's name is not a secret — but the gate keeps an
-- in-progress edit off the chat prompt.
--
-- Write: admins only, via is_admin(). Per the staff-RLS lesson recorded for
-- this project, role_id 2 gets NO write access by default and none is granted
-- here; if staff ever need to maintain these, that is a deliberate later
-- policy, not an accident of omission.
--
-- On the (select ...) wrapper, so a future RLS audit does not "fix" this:
-- 20260824000002 wrapped bare auth.uid() calls so the planner hoists them into
-- an InitPlan. That applies to auth.uid() itself. public.is_admin() is the
-- no-argument STABLE form which reads the GUC internally and takes no per-row
-- argument, so it is already evaluated once per statement here. Wrapping it
-- would add noise without changing the plan.
alter table public.lgu_facts enable row level security;

drop policy if exists lgu_facts_read on public.lgu_facts;
create policy lgu_facts_read on public.lgu_facts
  for select to authenticated
  using (is_published);

drop policy if exists lgu_facts_admin_write on public.lgu_facts;
create policy lgu_facts_admin_write on public.lgu_facts
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- Anon has no business reading these; the chat function runs authenticated.
revoke all on public.lgu_facts from anon;
grant select on public.lgu_facts to authenticated;
grant insert, update, delete on public.lgu_facts to authenticated; -- gated by RLS above
