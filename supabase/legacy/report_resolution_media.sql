-- ════════════════════════════════════════════════════════════════════════════
--  Resolution (completion) media.
--
--  When an LGU office / admin marks a report RESOLVED, they can attach "after"
--  photos/videos of the completed work. Unlike the citizen's original
--  attachments (report_media), these are proof-of-completion and are shown to
--  the CITIZEN on their resolved report — so they can see the fix, not just read
--  "Resolved".
--
--  Storage lives in a dedicated PUBLIC bucket `resolution-media` (completion
--  shots of fixed public infrastructure aren't sensitive), so the citizen can
--  load them with a plain public URL — no signed-URL / read-RLS fragility.
--  WRITES are still gated: only admins (role 1) or the staff office that owns
--  the report may upload.
--
--  Additive & idempotent. Run once.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1. Storage bucket (public read, gated write) ─────────────────────────────
insert into storage.buckets (id, name, public)
values ('resolution-media', 'resolution-media', true)
on conflict (id) do nothing;

-- Only admins / staff may upload into the bucket. (Public read is handled by the
-- bucket's `public = true` flag, so no SELECT policy is needed for citizens.)
drop policy if exists resolution_media_write on storage.objects;
create policy resolution_media_write on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'resolution-media'
    and exists (
      select 1 from public.user_roles ur
      where ur.user_id = auth.uid() and ur.role_id in (1, 2)
    )
  );

drop policy if exists resolution_media_delete on storage.objects;
create policy resolution_media_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'resolution-media'
    and exists (
      select 1 from public.user_roles ur
      where ur.user_id = auth.uid() and ur.role_id in (1, 2)
    )
  );

-- ── 2. Metadata table ────────────────────────────────────────────────────────
create table if not exists public.report_resolution_media (
  id           uuid primary key default gen_random_uuid(),
  report_id    uuid not null references public.reports(id) on delete cascade,
  storage_path text not null,
  mime_type    text,
  uploaded_by  uuid references auth.users(id) on delete set null,
  created_at   timestamptz not null default now()
);

create index if not exists idx_rrm_report
  on public.report_resolution_media(report_id);

alter table public.report_resolution_media enable row level security;

-- Read: the report owner (citizen), any admin, or staff on the owning office.
drop policy if exists rrm_select on public.report_resolution_media;
create policy rrm_select on public.report_resolution_media
  for select to authenticated
  using (
    exists (
      select 1 from public.reports r
      where r.id = report_resolution_media.report_id
        and (
          r.user_id = auth.uid()
          or public.is_admin()
          or r.assigned_to_department = public.current_staff_department()
          or r.endorsed_to_department = public.current_staff_department()
        )
    )
  );

-- Write: admins, or the staff office the report is assigned/endorsed to.
drop policy if exists rrm_insert on public.report_resolution_media;
create policy rrm_insert on public.report_resolution_media
  for insert to authenticated
  with check (
    uploaded_by = auth.uid()
    and exists (
      select 1 from public.reports r
      where r.id = report_resolution_media.report_id
        and (
          public.is_admin()
          or r.assigned_to_department = public.current_staff_department()
          or r.endorsed_to_department = public.current_staff_department()
        )
    )
  );

drop policy if exists rrm_delete on public.report_resolution_media;
create policy rrm_delete on public.report_resolution_media
  for delete to authenticated
  using (
    public.is_admin()
    or exists (
      select 1 from public.reports r
      where r.id = report_resolution_media.report_id
        and (
          r.assigned_to_department = public.current_staff_department()
          or r.endorsed_to_department = public.current_staff_department()
        )
    )
  );

-- ── 3. Realtime ──────────────────────────────────────────────────────────────
-- So the citizen's open report screen shows completion media the instant the
-- office uploads it. Guarded — already-published just no-ops.
do $$ begin
  alter publication supabase_realtime add table public.report_resolution_media;
exception when others then null; end $$;

alter table public.report_resolution_media replica identity full;
