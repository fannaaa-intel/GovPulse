-- ════════════════════════════════════════════════════════════════════════════
--  Media provenance: record whether each attached photo/video was a live,
--  GPS-stamped camera capture or an ordinary upload (gallery photo / video).
--
--  The citizen Report / Suggestion / Feedback forms now bake a "GPS Map Camera"
--  overlay (location, coordinates, timestamp) into photos taken LIVE with the
--  in-app camera. Gallery photos and videos are uploaded untouched — they may
--  be old or from elsewhere, so we never fake a location on them.
--
--  This column lets the admin & staff consoles label each media item honestly:
--    'camera' → GPS-verified live capture (stamp baked into the pixels)
--    'upload' → uploaded from gallery, or a video — location not verified
--    NULL     → legacy rows from before this feature (treated as 'upload')
--
--  Additive & idempotent. Run once. No backfill needed.
-- ════════════════════════════════════════════════════════════════════════════

alter table if exists public.report_media
  add column if not exists source text;

alter table if exists public.suggestion_media
  add column if not exists source text;

-- Feedback stores its photos as a flat `photo_urls text[]` array (no per-photo
-- row), so its provenance is a parallel `photo_sources text[]` aligned
-- index-for-index with `photo_urls` ('camera' | 'upload').
alter table if exists public.feedbacks
  add column if not exists photo_sources text[];
