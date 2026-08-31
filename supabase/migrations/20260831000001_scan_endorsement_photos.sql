-- ============================================================================
-- 20260831000001  The citizen's attachments on the scanned endorsement page
-- ============================================================================
-- The agency that scans the QR on an endorsement letter sees the report in
-- words: category, barangay, address, the citizen's description. It cannot see
-- what the citizen ATTACHED — which is the thing that actually locates a
-- pothole on a two-kilometre stretch of national road, and the thing the
-- officer standing at the roadside most needs.
--
-- Videos are included, not just photographs. A report whose only attachment is
-- a clip of moving floodwater would otherwise reach the agency as a page with
-- an empty media section, which is the worst of both: the evidence exists, the
-- officer is not told, and the screen built to save them a phone call costs
-- them one.
--
-- ── WHAT THIS ADDS, AND WHAT IT DELIBERATELY STILL WITHHOLDS ───────────────
-- scan_endorsement gains ONE key: report.media — an ordered array of
-- {path, kind} objects, where kind is 'photo' or 'video'. Nothing else
-- changes. The anonymity promise at the head of 20260801000000 is unchanged
-- and re-verified here:
--
--   no user_id, no name, no is_anonymous, not even a hint that the flag exists.
--
-- The paths are safe to hand out for a reason that is structural rather than
-- incidental. 20260721000006 (P0-B) re-keyed every media object from
--   reports/<CITIZEN_UUID>/<file>   ->   reports/<REPORT_ID>/<file>
-- precisely because the old shape let a staff member enumerate reporter uuids
-- from object keys alone. A path today contains the REPORT's id, which the
-- holder of this token is already authorised to know about, and nothing about
-- the person who filed it. Verify check 6 asserts that shape has not regressed.
--
-- ── WHY PATHS AND NOT URLS ─────────────────────────────────────────────────
-- `report-media` is a PRIVATE bucket. The obvious move — have this SECURITY
-- DEFINER function return signed urls — is IMPOSSIBLE, not merely discouraged:
-- signed urls are HMAC-signed by the Storage service using a key the database
-- does not hold. 20260721000006 states this outright ("a Postgres SECURITY
-- DEFINER function CANNOT mint them"). So the function returns paths, and the
-- `scan-endorsement-media` Edge Function exchanges token+paths for short-lived
-- signed urls using the service key.
--
-- The alternative was making report-media public, or copying every photo into
-- the public bucket on endorsement. Both were rejected: the first inverts a
-- deliberate privacy decision for every report in the system to serve one
-- screen, and the second duplicates storage and leaves orphans to collect on
-- withdrawal. The proxy changes no bucket policy at all — the same conclusion
-- 20260831000000 reached for the upload direction.
--
-- ── A PATH IS NOT A CAPABILITY ─────────────────────────────────────────────
-- Handing out paths grants nothing on its own: `report-media` has no anon
-- SELECT policy, so an anon caller holding a path can do nothing with it. The
-- capability is minted only by the Edge Function, only for paths that belong to
-- the scanned token's own report, and only for 10 minutes.
--
-- ── STATE ──────────────────────────────────────────────────────────────────
-- Attachments are returned for every state INCLUDING withdrawn/completed. An officer
-- who has finished the work still has a legitimate reason to look at what was
-- reported, and the page already shows the description in those states — the
-- photographs are the same class of information as the words beside them.
--
-- Rollback: supabase/rollback/20260831000001_scan_endorsement_photos_rollback.sql
-- Verify:   supabase/diagnostics/verify_20260831000001.sql
-- ============================================================================

begin;

-- ── 1. scan_endorsement — same projection, plus attachment paths ──────────
-- Rewritten whole rather than patched: this is the function the anonymity
-- promise is attached to, and a reader must be able to see the ENTIRE
-- projection in one place to check that promise.
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
             'reported_at', r.created_at,
             -- Storage PATHS, not urls. See the header: a definer function
             -- cannot mint a signed url, and these are inert without one.
             --
             -- EVERY attachment, videos included, each tagged with its kind.
             --
             -- Videos were nearly excluded here on the reasoning that there is
             -- no thumbnail to draw: report_media has no thumbnail column
             -- (verified live 2026-08-31 the columns are id, report_id,
             -- storage_path, mime_type, display_order, uploaded_at, source,
             -- ai_score, ai_status), and the citizen app's video_thumbnail
             -- call feeds only its own local preview and uploads nothing.
             --
             -- That reasoned from the THUMBNAIL rather than from the need. The
             -- agency is the party standing at the site, and when a citizen
             -- reports flooding the video is often the only attachment that
             -- shows the water moving. Telling that officer "a video exists,
             -- ask the LGU" is a dead end on the one screen built to save them
             -- the phone call. The admin and staff consoles both PLAY these
             -- (report_detail_kit's DetailMediaThumb -> NetworkVideoDialog),
             -- and a signed url streams to video_player_web exactly as it does
             -- to the mobile player, so this page can do the same.
             --
             -- The client draws a play tile rather than an image where kind is
             -- 'video', as the admin console already does. Ordering is the
             -- report's own display_order, so photos and videos interleave in
             -- the sequence the citizen attached them.
             --
             -- coalesce so a report with no media returns [] rather than
             -- collapsing the whole json_build_object to null the bug shape
             -- that would make a media-less report look like an invalid token.
             'media', coalesce(
               (
                 select json_agg(
                          json_build_object(
                            'path', m.storage_path,
                            'kind', case
                                      when coalesce(m.mime_type, '') like 'video/%'
                                      then 'video' else 'photo'
                                    end
                          )
                          order by m.display_order, m.id
                        )
                   from public.report_media m
                  where m.report_id = r.id
               ),
               '[]'::json
             )
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

-- ── 2. Paths for a token, for the Edge Function only ───────────────────────
-- The function could re-read scan_endorsement, but then the signing step would
-- trust a projection built for display. This returns exactly the set of paths
-- that may be signed for this token and nothing else, so the authorisation
-- question is answered in ONE place by the database.
--
-- service_role ONLY. Granting this to anon would hand out the same paths
-- scan_endorsement already returns — harmless in itself — but it is the input
-- to a signing operation, and keeping it service-only means a future change to
-- the signer cannot accidentally widen what anon can ask to have signed. Same
-- posture as verify_endorsement_pin / attach_endorsement_update_media in
-- 20260831000000.
create or replace function public.endorsement_media_paths(p_token text)
returns table (storage_path text)
language sql
stable
security definer
set search_path to 'public'
as $function$
  -- Videos included: they are signed and streamed like any other object, and
  -- the scan page plays them. Excluding them here would sign the photos and
  -- silently 404 the play tile beside them.
  select m.storage_path
    from public.report_endorsements e
    join public.reports r        on r.id = e.report_id
    join public.report_media m   on m.report_id = r.id
   where e.token = p_token
   order by m.display_order, m.id;
$function$;

revoke all on function public.endorsement_media_paths(text) from public;
revoke all on function public.endorsement_media_paths(text) from anon, authenticated;
grant execute on function public.endorsement_media_paths(text) to service_role;

commit;
