# GovPulse AI Accuracy Test — Results

**33 of 36 items were classified by GovPulse. 3 produced no output.**

All 36 items were inserted into the live database as real citizen submissions, and
the system's own triggers and AI classified them. The labels below were read back
out of the database. Nothing in this report was classified by me — where GovPulse
produced no answer, the item is marked **NO OUTPUT** rather than filled in.

Results are in `govpulse_results.csv` (36 rows, one per item).

No accuracy or F1 was calculated, as instructed.

---

## How the test was run

**What was inserted.** 36 records — 12 reports, 12 suggestions, 12 feedback — all in
a single transaction at **2026-09-23 13:42:52 UTC**. The texts were copied exactly
as written in the instructions and programmatically diffed against the prompt file
before insertion: **all 36 matched character-for-character**, including the Ilocano
and Tagalog spellings and the `!!!` in R3.

**What classified them.** Each table has an `AFTER INSERT` trigger that calls a
Supabase edge function, which calls Groq:

| Type | Table | Trigger | Edge function | Model |
|---|---|---|---|---|
| Report | `public.reports` | `trg_classify_report` | `classify-report` (v10) | `openai/gpt-oss-20b` |
| Suggestion | `public.suggestions` | `trg_classify_suggestion` | `classify-suggestion` (v1) | `openai/gpt-oss-20b` |
| Feedback | `public.feedbacks` | `trg_classify_feedback` | `classify-feedback` (v11) | `openai/gpt-oss-20b` |

All three run at `temperature: 0` with `reasoning_effort: "low"` and a JSON-object
response format ([_shared/groq.ts](supabase/functions/_shared/groq.ts)). All three
functions were confirmed ACTIVE and deployed. No function, prompt, model, rule,
trigger, or migration was changed at any point.

**Neutral values used — identical for every item of a type:**

| Field | Value | Note |
|---|---|---|
| `category` (reports & suggestions) | `others` | The neutral option. Same for all 24, so the hint never varies. |
| `category_other` | `null` | Free text here reaches the model; left empty. |
| `barangay` | `null` | Read by `classify-report`; omitted. |
| `overall_rating` (feedback) | `3` | Mandatory and read by the model. Middle value. |
| `latitude` / `longitude` | `18.3583` / `121.6414` | Required. Aparri town centre. Not read by any classifier. |
| `office_id` / `office_label` | `mayor` / `Mayor's Office` | Required. Not read by the classifier. |
| `service_name` | `TEST-EVAL` | Required. Not read by the classifier. |
| `visit_date` | 2026-09-23 | Required. Not read by the classifier. |
| `user_id` | `null` | Anonymous submission; keeps the per-user rate limiters dormant. |
| `is_anonymous` | `false` | Default. Not read by any classifier. |

Verified after the fact: all 24 report/suggestion rows still have `category='others'`
and all 12 feedback rows still have `overall_rating=3`.

**Tagging.** Every row carries `TEST-EVAL <item_id>` in `address` (reports,
suggestions) or `username` (feedback). I checked each function's database `select`
to confirm neither field is read by any classifier, so the tag cannot have
influenced a label.

**Did the 12 reports inflate each other's urgency?** No, and this was checked rather
than assumed. Each function selects a single row by `id` and sends only that row's
own fields to the model. There is no similar-report count, neighbour lookup, or
duplicate count anywhere in the prompts. Inserting the 12 together is safe, so no
spacing was needed.

---

### What went wrong

**1. Three feedback items were never classified (the main caveat).**

F9, F11 and F12 have no AI label. (S12, the fourth original failure, was classified
on a later retry — see the investigation below.)

I did not fill these in. They are **NO OUTPUT** in the CSV.

**The investigation — what actually causes it**

The failures were retried through the same `classify-feedback` function in batch
mode five more times (14:26, 14:30, 14:45 scheduled sweeps, plus direct single-row
and batch calls at 14:40–14:45). Every attempt failed identically. The function
returns HTTP **200** with the rows named in its own `failures` list:

```json
{"requested":3,"classified":0,
 "failures":["62feb46e-…(F9)","2db9c5d5-…(F11)","e70a3851-…(F12)"]}
```

**The decisive evidence is timing.** Measuring the call duration from the database:

| Call | Rows | Duration | Result |
|---|---|---|---|
| F12 alone (14:42) | 1 | **0.049 s** | failed |
| F11 alone (14:43) | 1 | **0.037 s** | failed |
| All three, batch (14:45) | 3 | **0.046 s** | all failed |
| Control: `classify-report` with nothing to do | 0 | 0.038 s | n/a |
| The successful runs at 13:43–13:45 | — | **6–7 s** each | succeeded |

A real Groq call on this project takes 6–7 seconds. Three rows, each with two
retries in `groqChat()`, would take at least ~24 seconds if they were reaching the
API. Instead all three fail in **46 milliseconds** — the same duration as a function
that does no work at all. **The function is not reaching Groq. It fails before the
network call.**

That rules out the explanations that look plausible from the outside: it is not a
timeout, not rate-limiting (no retry delay is being served), not the 5-second
`net.http_post` limit, and not the text content — F9/F11/F12 are plain ASCII, 80–137
characters, no unusual encoding, and sit between F8 (93 chars) and F10 (87 chars),
both of which classified fine.

**It is also not a broken API key or a Groq outage.** At 14:30:00 in the *same
second*, `classify-suggestion` successfully classified S12 (`"classified":1`) while
`classify-feedback` failed all three. Both functions share the same `groqChat()`
helper, the same `openai/gpt-oss-20b` model, and the same `GROQ_API_KEY`.

**What is left, and what I could not confirm.** The one substantive difference
between the two functions' Groq calls is the token budget —
`classify-feedback` sends `max_tokens: 120`
([classify-feedback/index.ts:159](supabase/functions/classify-feedback/index.ts#L159))
while `classify-suggestion` sends `max_tokens: 200`
([classify-suggestion/index.ts:239](supabase/functions/classify-suggestion/index.ts#L239)).
GPT-OSS is a reasoning model that spends tokens thinking before it answers, so a
120-token ceiling is the tightest budget of the three classifiers and the most
likely thing to fail on the rows that need the most reasoning. The same three rows
failing every single time, while shorter/simpler comments succeed, fits that.

**However, I am not claiming this as proven.** A truncated reply would still cost a
full 6–7 second round-trip, and these calls return in 40 ms. Something is failing
earlier than that. The remaining candidates — an exception thrown inside the
function before the fetch, or a per-function resource limit — can only be separated
by reading the function's own `console.error` output, which logs *"Groq error"* with
the status and body, or *"Groq fetch failed"* for a thrown fetch
([_shared/groq.ts](supabase/functions/_shared/groq.ts)).

**I could not retrieve that log line.** The Management API's analytics endpoint
returned only `booted` / `shutdown` / `Listening` records for these functions and
rejected every filtered query against the log level or message body with
*"Backend error! Retry your query."* The raw Groq error message therefore could not
be captured from here. It is visible in the Supabase dashboard under
**Edge Functions → classify-feedback → Logs**, filtered to the timestamps above
(14:42:46, 14:43:48, 14:45:26 UTC) — that will show the exact error in one line.

I deliberately did not change `max_tokens`, the prompt, the model, or anything else
to test the theory, since the instruction was to leave the system as it is.

Note on method: I downloaded the deployed `classify-feedback` to confirm the running
code matches the repository source — it is byte-identical apart from line endings,
so the code quoted above is what is actually executing. The working tree was
restored immediately (`git status` clean).

**2. The insert trigger times out on essentially every row (a real finding).**

`net._http_response` shows 75 calls with `status_code = null` at insert time, all
reading *"Timeout of 5000 ms reached. Total time: ~6000-6900 ms"*. The database's
`net.http_post` has a **5-second timeout**, but the edge function needs ~6–7 seconds
for the Groq round-trip. So the caller times out on nearly every submission — while
the function keeps running and still writes its label. The trigger "fails" and the
work succeeds anyway, with the 15-minute sweep covering whatever slips through.

This is invisible in normal operation and unrelated to this test's validity, but it
means the trigger path is effectively fire-and-forget rather than the synchronous
call it appears to be. Worth a look independently of the thesis.

**3. Classification was not instant.** First label landed 8 seconds after insert;
29 of 36 within 3 minutes; 32 of 36 after the 14:00 sweep; 33 of 36 after the 14:30
sweep, which finally picked up S12 on its fourth attempt. The remaining 3 never
arrived. If you re-run this test, allow at least 45 minutes rather than assuming the
insert trigger is enough.

**4. No `.env` file exists in the project.** The `SUPABASE_URL` /
`SUPABASE_SERVICE_ROLE_KEY` / `TEST_USER_EMAIL` credentials referenced in the
instructions were not present. Database access used the authenticated Supabase CLI's
Management API token instead. No key was printed at any point.

**5. Rate limits were avoided by design.** `rl_reports`/`rl_feedbacks` (5 per 24h)
and `rl_suggestions` (3 per 24h) are keyed on `auth.uid()` and wrapped in
`if auth.uid() is not null`. Inserting as `postgres` with `user_id = null` carries no
JWT, so they no-op. A logged-in test account would have been blocked at item 6 (and
item 4 for suggestions) — two-thirds of the test set.

---

## Reports — GovPulse's answers

Category and urgency both come from the AI (`ai_category`, `ai_urgency`).

| Item | Text (start) | Category | Urgency |
|---|---|---|---|
| R1 | Gumuho na ang gilid ng kalsada malapit sa tulay… | Road & Infrastructure | High |
| R2 | Adda dakkel nga abut iti kalsada iti sango ti eskuelaan… | Road & Infrastructure | High |
| R3 | URGENT!!! The paint of the pedestrian lane… | Road & Infrastructure | Medium |
| R4 | Saan a naala ti basura mi iti las-ud ti maysa a lawas… | Waste & Garbage | Low |
| R5 | The garbage bin beside the waiting shed is already full… | Waste & Garbage | Low |
| R6 | Baha na sa loob ng mga bahay namin, hanggang tuhod… | Drainage & Flooding | High |
| R7 | The canal along our street is clogged with plastic… | Drainage & Flooding | Medium |
| R8 | Tatlong poste ng ilaw ang patay sa kalye namin… | Streetlight Outage | Medium |
| R9 | Saan nga agsilsilaw ti maysa a poste iti igid ti plasa. | Streetlight Outage | Medium |
| R10 | Someone burns plastic and rubber behind the market… | Environment & Pollution | Medium |
| R11 | Sobrang lakas ng videoke ng kapitbahay hanggang 2am… | Environment & Pollution | Low |
| R12 | A stray dog has been sleeping at the entrance… | Others | Low |

All 12 classified. Note R3: despite "URGENT!!!" in the text, GovPulse rated it
Medium — it judged the situation (faded paint), not the shouting.

## Suggestions — GovPulse's answers

Category comes from the AI (`ai_category`). The system produces **no urgency and no
sentiment** for suggestions, by design — this is documented in the function header
as a deliberate decision, not a gap.

| Item | Text (start) | Category |
|---|---|---|
| S1 | Please allow online payment for business permit renewal… | Public Service |
| S2 | Sana may hiwalay na pila para sa mga senior citizen at PWD… | Public Service |
| S3 | Sapay koma ta adda libre a seminar iti panagnegosio… | Community Program |
| S4 | Sana po magkaroon ng basketball league para sa youth… | Community Program |
| S5 | Sapay koma ta adda libre a medical mission… | Health & Safety |
| S6 | Please assign tanods at the plaza at night… | Health & Safety |
| S7 | Sana po lagyan ng waiting shed ang sakayan… | Infrastructure |
| S8 | Paki-install po ng streetlights sa road going to the beach… | Health & Safety |
| S9 | Mabalin koma nga agmula kami iti kayo iti igid ti karayan… | Environment & Cleanliness |
| S10 | Put up separate bins for biodegradable and non-biodegradable… | Environment & Cleanliness |
| S11 | Please name the new park after a local hero of Aparri. | Infrastructure |
| S12 | Sapay koma ta adda museo ti Aparri… | Community Program |

All 12 classified. S12 needed four attempts — it failed the insert trigger and the
13:45, 14:00 and 14:15 sweeps before the 14:30 sweep labelled it.

## Feedback — GovPulse's answers

Sentiment and urgency both come from the AI (`ai_sentiment`, `ai_urgency`).

| Item | Text (start) | Sentiment | Urgency |
|---|---|---|---|
| F1 | Very accommodating staff. I got my business permit… | Positive | Low |
| F2 | Napintas ti serbisio. Napardas ken nasayaat… | Positive | Low |
| F3 | Mabilis ang pagkuha ng birth certificate ko… | Positive | Low |
| F4 | Super bait ni ate sa window, she explained everything… | Positive | Low |
| F5 | I requested a copy of my marriage certificate this morning… | Neutral | Medium |
| F6 | Nagpabakuna ako ng anti-rabies sa Health Office kahapon. | Neutral | Low |
| F7 | Nagala ak iti Mayor's clearance idi Martes. | Neutral | Low |
| F8 | Tatlong oras akong naghintay para sa kopya… | Negative | Medium |
| F9 | Nabayag ti panagur-ay mi, dua nga oras… | **NO OUTPUT** | **NO OUTPUT** |
| F10 | Mabilis naman ang process, pero ang sungit ng staff… | Negative | Medium |
| F11 | Ang galing talaga, pinabalik-balik ako ng limang beses… | **NO OUTPUT** | **NO OUTPUT** |
| F12 | The Health Office sent my father home without an anti-rabies shot… | **NO OUTPUT** | **NO OUTPUT** |

9 of 12 classified. F9, F11 and F12 failed on all eight attempts; the cause is
analysed above. Note that F12 — the one describing a person sent home without a
rabies shot — is exactly the kind of comment an LGU would most want flagged, so this
gap matters operationally as well as for the thesis.

---

## Items needing attention

**NO OUTPUT — 3 items.** F9, F11, F12 (all feedback). GovPulse's classifier reaches
each of these rows and the model call fails in ~40 ms without ever contacting Groq;
the function reports them in its own `failures` list with an HTTP 200 response. They
remain unclassified in the database after eight attempts. See "What went wrong" above
for the full investigation.

S12 was a fourth failure initially, but the scheduled catch-up sweep classified it at
14:30 UTC on its fourth attempt — so suggestion coverage is 12/12. Its label
(Community Program) came from the model like every other one.

**Fallback instead of AI — 0 items.** Every one of the 32 labelled items came from
the Groq model. Worth explaining, since your CSV has a `label_source` column:
`classify-feedback` has a rule-based shortcut (`classifyRatingOnly()`) that derives
sentiment and urgency from the star rating alone, skipping the model — but it only
applies to feedback with *no written comment*. All 12 feedback items have comments,
so it never triggered. I verified this in the data as well as in the code: its
signature is `ai_theme IS NULL` on a classified row, and zero rows match.

(Separately, the admin dashboard shows an on-device rule-based fallback for rows the
AI hasn't reached. That fallback is computed in Dart at display time and is never
written to the database, so it cannot be read back via SQL. The 4 NO OUTPUT items
would display that way in the admin UI.)

**UNMAPPED — 0 items.** Every raw value mapped cleanly onto your rater options:

| GovPulse raw | Your option |
|---|---|
| `road` / `waste` / `drainage` / `streetlight` / `environment` / `others` | Road & Infrastructure / Waste & Garbage / Drainage & Flooding / Streetlight Outage / Environment & Pollution / Others |
| `public_service` / `community_program` / `health_safety` / `infrastructure` / `environment` / `others` | Public Service / Community Program / Health & Safety / Infrastructure / Environment & Cleanliness / Others |
| `positive` / `neutral` / `negative` | Positive / Neutral / Negative |
| `high` / `medium` / `low` | High / Medium / Low |

UNMAPPED is structurally impossible here: the tables' CHECK constraints reject
anything outside these sets, and each function coerces model output onto the closed
vocabulary before writing. Both raw and mapped values are in the CSV regardless.

---

## One thing to disclose in your thesis

**GovPulse's feedback sentiment is not a pure text judgment.** The star rating is
included in the model's prompt, and the prompt instructs it to *"weigh the words more
than the star rating, but use the rating as a tie-breaker"*
([classify-feedback/index.ts:105-106](supabase/functions/classify-feedback/index.ts#L105-L106)).
The rating column is `NOT NULL` with a CHECK of 1–5, so it cannot be omitted — a
neutral 3 is the least-steering value available, which is what was used.

Your human raters saw text only. GovPulse saw text plus a neutral 3. That asymmetry
is unavoidable given the system's design, but it should be stated rather than left
implicit, particularly for the borderline Neutral cases (F5, F6, F7).

A smaller note: for reports and suggestions the citizen's own category pick is also
shown to the model, labelled as an unreliable hint. Holding it constant at `others`
for all 24 items means it cannot have skewed one item relative to another, but it is
present in every prompt.

---

## Cleanup — delete all TEST-EVAL records

**DONE — completed 2026-09-23 ~15:00 UTC.** All 36 test records and the 36
notifications the system created for them were deleted in one transaction, matched
by exact record ID. Row counts returned to the pre-test baseline (reports 10,
suggestions 7, feedbacks 13) and all 30 real citizen submissions are intact and
still classified. The `record_id` values in `govpulse_results.csv` now refer to
deleted rows — the labels remain valid, but the rows are gone.

The statements below are kept for the record. **They are no longer needed.**

```sql
delete from public.reports     where address  like 'TEST-EVAL%';
delete from public.suggestions where address  like 'TEST-EVAL%';
delete from public.feedbacks   where username like 'TEST-EVAL%';
```

To see what would be deleted first (should be 12 / 12 / 12):

```sql
select 'reports' as t, count(*) from public.reports     where address  like 'TEST-EVAL%'
union all select 'suggestions', count(*) from public.suggestions where address  like 'TEST-EVAL%'
union all select 'feedbacks',   count(*) from public.feedbacks   where username like 'TEST-EVAL%';
```

Every record ID is also in the `record_id` column of `govpulse_results.csv` if you
prefer to delete by explicit ID.

While they existed, these rows were visible in the admin console and staff queues
(reports as `pending`, feedback as `unreviewed`), and one staff/admin account
received 36 "new submission" notifications. All of that has been removed.

---

## Where each claim came from

- Pipeline, model, prompts, fallback logic: read from
  [classify-report/index.ts](supabase/functions/classify-report/index.ts),
  [classify-suggestion/index.ts](supabase/functions/classify-suggestion/index.ts),
  [classify-feedback/index.ts](supabase/functions/classify-feedback/index.ts),
  [_shared/groq.ts](supabase/functions/_shared/groq.ts).
- Triggers, rate limiters, routing functions: read from the live database with
  `pg_get_functiondef` — they are not defined in `supabase/migrations/`.
- Label vocabularies: the live CHECK constraints (`reports_ai_category_chk`,
  `suggestions_ai_category_chk`, `feedbacks_ai_sentiment_chk`, `*_ai_urgency_chk`).
- The 4 failures: the classifier's own HTTP 200 response body naming them.
- The 5s timeout finding: `net._http_response` error messages.
- Catch-up sweep: [CATCHUP_CRON.sql](supabase/functions/CATCHUP_CRON.sql) and
  `cron.job` / `cron.job_run_details` live.
- All labels: read back from `public.reports`, `public.suggestions`,
  `public.feedbacks`. No other source.
