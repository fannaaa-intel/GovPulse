-- ============================================================================
-- ROLLBACK  20260831000001_scan_endorsement_photos
-- ============================================================================
-- Restores scan_endorsement to the projection it had after 20260801000000 (no
-- photo paths, no video count) and drops endorsement_media_paths.
--
-- ⚠ ORDER MATTERS WITH THE EDGE FUNCTION. `scan-endorsement-media` calls
-- endorsement_media_paths, so running this while that function is still
-- deployed leaves every photo request answering 500. Undeploy the function
-- FIRST, or accept that the scan page's photo strip fails closed — it is
-- built to (the strip hides itself and the rest of the page is unaffected),
-- but a 500 in the logs with no explanation is the kind of thing that costs an
-- hour later.
--
-- Safe to run more than once.
-- ============================================================================

begin;

-- ── 1. scan_endorsement, as it was before this migration ───────────────────
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

  return coalesce(v, json_build_object('valid', false));
end;
$function$;

revoke all on function public.scan_endorsement(text) from public;
grant execute on function public.scan_endorsement(text) to anon, authenticated;

-- ── 2. The path lookup goes away entirely ──────────────────────────────────
drop function if exists public.endorsement_media_paths(text);

commit;
