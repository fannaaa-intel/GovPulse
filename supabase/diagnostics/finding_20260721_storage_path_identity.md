# Evidence — citizen identity embedded in storage object paths
Captured 2026-07-21, immediately before the objects were deleted during a test
reset. The objects no longer exist; this file is the record.
Relates to finding **P0-B** in the vulnerability report.
## What the finding is
`report_media.storage_path` and `suggestion_media.storage_path` embed the
**uploader's `auth.uid()`** as the second path segment, including on rows where
`is_anonymous = true`. Staff could read these paths — both through the media
tables and by listing `storage.objects` directly, via the unscoped
`Staff can view all report media` policy — which defeats any anonymity control
applied at the `reports` table level.
The shape was **structural, not incidental**: the upload policy REQUIRED it.
```sql
-- storage.objects INSERT policy, as it stood on 2026-07-21
"Verified citizens can upload report media"
WITH CHECK (bucket_id = 'report-media'
  AND (storage.foldername(name))[1] = 'reports'
  AND (storage.foldername(name))[2] = auth.uid()::text
  AND EXISTS (SELECT 1 FROM verification_submissions vs
              WHERE vs.user_id = auth.uid() AND vs.status = 'approved'))
```
## Scale at capture time
- Total objects: **39** (report-media: 33, suggestion-media: 6)
- Distinct citizen uuids recoverable from paths alone: **3**
- Objects referenced by a surviving database row: **0** (all orphaned)

## Distinct identities exposed
| citizen uuid | objects attributable |
|---|---|
| `384dfd84-efad-488a-8632-5b46e3fbf3d7` | 25 |
| `76159d2c-4eda-4919-abdd-4569cfbde326` | 13 |
| `4a41b350-1d3f-41a9-9d82-cef9a422a056` | 1 |

## Path shapes (uuids replaced with `<CITIZEN_UUID>`)
```
report-media/reports/<CITIZEN_UUID>/<TS>_8644.jpg
report-media/reports/<CITIZEN_UUID>/<TS>_0_10031.jpg
report-media/reports/<CITIZEN_UUID>/<TS>_1_<CITIZEN_UUID>-1_all_6047.jpg
report-media/reports/<CITIZEN_UUID>/<TS>_2_<CITIZEN_UUID>-1_all_1295.jpg
report-media/reports/<CITIZEN_UUID>/<TS>_0_<CITIZEN_UUID>-1_all_3680.jpg
report-media/reports/<CITIZEN_UUID>/<TS>_1_<CITIZEN_UUID>-1_all_3681.jpg
report-media/reports/<CITIZEN_UUID>/<TS>_2_<CITIZEN_UUID>-1_all_3682.jpg
report-media/reports/<CITIZEN_UUID>/<TS>_0_<CITIZEN_UUID>-1_all_1630.jpg
report-media/reports/<CITIZEN_UUID>/<TS>_1_<CITIZEN_UUID>-1_all_1631.jpg
report-media/reports/<CITIZEN_UUID>/<TS>_2_<CITIZEN_UUID>-1_all_1632.jpg
report-media/reports/<CITIZEN_UUID>/<TS>_0_<CITIZEN_UUID>-1_all_6033.jpg
report-media/reports/<CITIZEN_UUID>/<TS>_0_<CITIZEN_UUID>-1_all_6088.jpg
report-media/reports/<CITIZEN_UUID>/<TS>_1_<CITIZEN_UUID>-1_all_6089.jpg
report-media/reports/<CITIZEN_UUID>/<TS>_2_<CITIZEN_UUID>-1_all_6090.jpg
report-media/reports/<CITIZEN_UUID>/<TS>_0_9741.jpg
report-media/reports/<CITIZEN_UUID>/<TS>_0_10132.jpg
report-media/reports/<CITIZEN_UUID>/<TS>_0_11083.jpg
report-media/reports/<CITIZEN_UUID>/<TS>_0_<CITIZEN_UUID>-1_all_6401.jpg
report-media/reports/<CITIZEN_UUID>/<TS>_0_11322.jpg
report-media/reports/<CITIZEN_UUID>/<TS>_0_11314.jpg
report-media/reports/<CITIZEN_UUID>/<TS>_0_7352.jpg
report-media/reports/<CITIZEN_UUID>/<TS>_0_<CITIZEN_UUID>-1_all_6439.jpg
report-media/reports/<CITIZEN_UUID>/<TS>_0_<CITIZEN_UUID><TS>.jpg
report-media/reports/<CITIZEN_UUID>/<TS>_0_13474.jpg
report-media/reports/<CITIZEN_UUID>/<TS>_0_<CITIZEN_UUID>-1_all_6380.jpg
report-media/reports/<CITIZEN_UUID>/<TS>_0_<CITIZEN_UUID>-1_all_6406.jpg
report-media/reports/<CITIZEN_UUID>/<TS>_0_gps_<TS>.jpg
report-media/reports/<CITIZEN_UUID>/<TS>_0_check.png
suggestion-media/suggestions/<CITIZEN_UUID>/<TS>_0_9892.jpg
suggestion-media/suggestions/<CITIZEN_UUID>/<TS>_1_9891.jpg
suggestion-media/suggestions/<CITIZEN_UUID>/<TS>_0_gps_<TS>.jpg
suggestion-media/suggestions/<CITIZEN_UUID>/<TS>_0_14317.webp
```

## Why this mattered
A staff session on 2026-07-21 could see **0 rows** in `reports` (nothing was
triaged to their department) while simultaneously seeing **31 objects** in
`report-media`. Staff could enumerate the uuids of citizens whose reports they
were not permitted to know existed.

## Remediation
Migration 6 re-paths uploads to `reports/<report_id>/...`, rewrites the upload
policy to verify report ownership instead of embedding the uploader id, and
department-scopes the staff bucket read. Because every object here was already
orphaned when it was deleted, that migration has **no data to migrate** — the
re-path applies to new uploads only.

---

# Addendum — the same pattern in a PUBLIC bucket (`feedback-assets`)

Captured 2026-07-21, immediately before deletion. Relates to finding **P2.5**,
and materially raises its severity.

`feedback-assets` carried the identical identity-in-path shape:

```
feedback/<CITIZEN_UUID>/<TS>.jpg     x2
```

Both objects belonged to the same citizen uuid, and both were orphaned
(`feedbacks` held 0 rows referencing them).

**Why this is worse than P0-B.** `report-media` and `suggestion-media` are
private buckets — reaching an object required an authenticated session that
passed a storage policy. `feedback-assets` is `public = true`. A public bucket
serves objects to *anyone with the URL, with no authentication at all*. The
`"Authenticated users can view feedback photos"` policy on it is therefore
decoration: it gates a door in a wall that is not there.

So for feedback specifically, the citizen's uuid was embedded in a URL that
required no credentials to fetch — and `feedbacks.is_anonymous` exists, meaning
anonymous feedback could be attributed to its author by URL inspection alone.

**Remediation** (still outstanding, migration 9): make `feedback-assets`
private and serve via signed URLs, and re-path uploads so the object key does
not carry the uploader's uuid. Verify how `feedbacks.photo_urls` stores its
values first — if it holds full public URLs rather than storage paths, going
private requires a data migration too, not just a bucket flag.

# Buckets confirmed LIVE at capture time — not evidence, do not delete

| bucket | objects | referenced by |
|---|---|---|
| `verification-assets` | 22 | `verification_submissions` (ID + face images) |
| `profile-photos` | 5 | `citizen_details.profile_photo_path` (4 matched) |
| `admin-avatars` | 2 | `admin_profiles.photo_url` (both matched exactly) |
