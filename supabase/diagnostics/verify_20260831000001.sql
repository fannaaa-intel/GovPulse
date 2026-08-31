-- ============================================================================
-- VERIFY 20260831000001  citizen attachments on the scanned endorsement page
-- ============================================================================
-- Read-only. One query, one row per check.
--
-- The checks that matter most here are the ANONYMITY ones (12-14). This
-- migration widens the only function in the schema that answers to an
-- unauthenticated caller, and the promise at the head of 20260801000000 is
-- that it returns no reporter identity of any kind. That promise is now
-- enforced by assertion rather than by reading.
--
-- NOTE the catalog choice: pg_proc / prosrc throughout rather than
-- information_schema.routines. information_schema views only show objects the
-- QUERYING role holds privileges on, which has already made an applied
-- migration look unapplied here once.
-- ============================================================================

with src as (
  select p.prosrc
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'scan_endorsement'
   limit 1
),
checks as (

  select 1 as n, 'scan_endorsement exists' as what,
         exists (select 1 from pg_proc p
                   join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public'
                    and p.proname = 'scan_endorsement') as ok

  union all
  select 2, 'endorsement_media_paths exists',
         exists (select 1 from pg_proc p
                   join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public'
                    and p.proname = 'endorsement_media_paths')

  -- ── The projection actually carries photos ───────────────────────────────
  union all
  select 3, 'scan_endorsement returns a media key',
         (select prosrc like '%''media''%' from src)

  union all
  select 4, 'each attachment carries a path and a kind',
         (select prosrc like '%''path''%' and prosrc like '%''kind''%' from src)

  -- Videos must be INCLUDED and tagged, not filtered out. A report whose only
  -- attachment is a video would otherwise reach the agency as an empty media
  -- section - see the migration header.
  union all
  select 5, 'videos are tagged rather than excluded',
         (select prosrc like '%''video''%' and prosrc not like '%not like ''video/%%'
            from src)

  -- The empty case. Without coalesce, json_agg over no rows returns NULL and
  -- collapses the surrounding json_build_object — a photo-less report would
  -- read to the client as an invalid token.
  union all
  select 6, 'media falls back to an empty array, not null',
         (select prosrc like '%coalesce(%''[]''::json%' from src)

  -- ── Path shape: the reason handing paths out is safe at all ──────────────
  -- 20260721000006 re-keyed media from reports/<CITIZEN_UUID>/ to
  -- reports/<REPORT_ID>/ precisely so an object key could not be used to
  -- enumerate reporters. If that ever regressed, these paths would carry
  -- identity to an anonymous caller.
  union all
  select 7, 'no media object is keyed by a path segment that is not the report id',
         not exists (
           select 1
             from public.report_media m
            where m.storage_path like 'reports/%'
              and split_part(m.storage_path, '/', 2) <> m.report_id::text
         )

  -- ── The signing helper is service-role ONLY ──────────────────────────────
  -- It is the input to a signing operation. Keeping it service-only means a
  -- future change to the signer cannot widen what anon may ask to have signed.
  union all
  select 8, 'endorsement_media_paths is NOT anon-executable',
         not has_function_privilege('anon',
           'public.endorsement_media_paths(text)', 'EXECUTE')

  union all
  select 9, 'endorsement_media_paths is NOT authenticated-executable',
         not has_function_privilege('authenticated',
           'public.endorsement_media_paths(text)', 'EXECUTE')

  union all
  select 10, 'endorsement_media_paths IS service_role-executable',
         has_function_privilege('service_role',
           'public.endorsement_media_paths(text)', 'EXECUTE')

  -- Signing the photos while filtering the videos would leave the play tile
  -- beside them pointing at nothing.
  union all
  select 11, 'endorsement_media_paths does not filter videos out',
         (select p.prosrc not like '%not like ''video/%%'
            from pg_proc p
            join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'endorsement_media_paths'
           limit 1)

  -- ── ANONYMITY — the promise this function is bound by ────────────────────
  -- Substring assertions on the source, because that is what a reader checks
  -- when they audit the projection by eye. Each of these appearing would mean
  -- the anon endpoint had started returning reporter identity.
  union all
  select 12, 'scan_endorsement returns no user_id',
         (select prosrc not like '%user_id%' from src)

  union all
  select 13, 'scan_endorsement returns no is_anonymous',
         (select prosrc not like '%is_anonymous%' from src)

  union all
  select 14, 'scan_endorsement returns no submitter/reporter name',
         (select prosrc not like '%submitter%'
             and prosrc not like '%reporter_name%'
             and prosrc not like '%full_name%' from src)

  -- ── The anon grant is intact (the page must still work) ──────────────────
  union all
  select 15, 'scan_endorsement IS anon-executable',
         has_function_privilege('anon',
           'public.scan_endorsement(text)', 'EXECUTE')

  union all
  select 16, 'scan_endorsement is still SECURITY DEFINER',
         (select p.prosecdef from pg_proc p
            join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'scan_endorsement'
           limit 1)

  union all
  select 17, 'endorsement_media_paths is SECURITY DEFINER',
         (select p.prosecdef from pg_proc p
            join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'endorsement_media_paths'
           limit 1)

  -- Both pin search_path per house convention — an unpinned definer function
  -- resolves names against the CALLER's path.
  union all
  select 18, 'both functions pin search_path to public',
         (select bool_and(p.proconfig @> array['search_path=public'])
            from pg_proc p
            join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public'
             and p.proname in ('scan_endorsement', 'endorsement_media_paths'))

  -- ── report-media stays PRIVATE ───────────────────────────────────────────
  -- The entire design rests on this. If the bucket were flipped public, the
  -- Edge Function would be pointless and every report photo in the system
  -- would be readable by url.
  union all
  select 19, 'report-media bucket is still private',
         not coalesce((select b.public from storage.buckets b
                        where b.id = 'report-media'), false)

)
select n,
       case when ok then 'PASS' else 'FAIL' end as result,
       what
  from checks
 order by n;
