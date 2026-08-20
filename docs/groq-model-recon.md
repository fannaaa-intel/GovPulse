# Groq / `llama-3.1-8b-instant` decommission recon

**Date:** 2026-08-14 · **Decommission date:** 2026-08-16 (2 days out) · **Code changed: none**

Scope: every place GovPulse touches the Groq API, what each call sends and expects, and what
should replace the models that are going away.

---

## 0. Headline

Three production Edge Functions call `llama-3.1-8b-instant` and **will start failing on Aug 16**:

| Function | Model line | Blast radius when it 400s |
|---|---|---|
| `classify-report` | [index.ts:24](../supabase/functions/classify-report/index.ts#L24) | Reports lose AI urgency triage → dashboard silently falls back to the on-device keyword rule |
| `classify-feedback` | [index.ts:34](../supabase/functions/classify-feedback/index.ts#L34) | Feedback loses sentiment/urgency/theme → on-device rule fallback |
| `moderate-content` | [index.ts:31](../supabase/functions/moderate-content/index.ts#L31) | **Toxic posts/comments stop being AI-flagged, permanently** (see §6 — no catch-up cron) |

The good news: all three are architected as *additive* layers over on-device fallbacks, so nothing
crashes for citizens. The bad news: two of the three failure modes are **silent**, and the
moderation one is **unrecoverable** without a manual backfill, because a 400 (bad model) is not
retryable and `moderate-content` has no catch-up sweep.

Two more functions use `llama-3.3-70b-versatile`, which is **not** in the announced decommission but
sits on the same Llama-3.x deprecation trajectory — treat it as a watch item, not a crisis.

---

## 1. Summary table — every GovPulse AI feature

| # | Feature | Entry point | Model | Input size (approx) | Data sensitivity |
|---|---|---|---|---|---|
| 1 | **Report urgency triage** | [classify-report/index.ts:96](../supabase/functions/classify-report/index.ts#L96) | `llama-3.1-8b-instant` ⚠️ | ~250 tok sys + 1 short report (~30–150 tok) | Semi-private — citizen remarks + barangay, no identity |
| 2 | **Feedback sentiment / urgency / theme** | [classify-feedback/index.ts:146](../supabase/functions/classify-feedback/index.ts#L146) | `llama-3.1-8b-instant` ⚠️ | ~450 tok sys + 1 short comment (~20–120 tok) | Private — free-text citizen feedback, no identity |
| 3 | **Community content moderation** | [moderate-content/index.ts:99](../supabase/functions/moderate-content/index.ts#L99) | `llama-3.1-8b-instant` ⚠️ | ~250 tok sys + post title/body (unbounded) | **Public** — already-published community text |
| 4 | **Predictive outlook / recommended actions** | [recommend-actions/index.ts:360](../supabase/functions/recommend-actions/index.ts#L360) | `llama-3.3-70b-versatile` | ~900 tok sys + 2–6k tok aggregate JSON | Private — 20 verbatim negative comments + 12 verbatim urgent remarks + office/barangay labels |
| 5 | **"Kuya Gov" citizen chat assistant** | [chat-agent/index.ts:517](../supabase/functions/chat-agent/index.ts#L517) | `llama-3.3-70b-versatile` | ~2.5–3k tok sys+KB + **unbounded** history + events JSON | **Most sensitive** — anything a citizen types, plus report refs/status |

Not Groq, listed to close the loop: **AI-generated-image detection**
([check-ai-image/index.ts](../supabase/functions/check-ai-image/index.ts)) uses **Sightengine**, not an
LLM. Unaffected by this decommission.

---

## 2. Feature-by-feature detail

### 1. Report urgency triage — `classify-report`

- **What it does:** Labels each citizen report `ai_urgency` = high/medium/low with a short
  `ai_urgency_reason`, written back to `public.reports`. The admin "Urgency triage" panel reads it
  and shows a "Hybrid AI" badge; unlabelled rows fall back to the on-device keyword rule in
  [admin_dashboard_provider.dart:1069](../lib/features/admin/providers/admin_dashboard_provider.dart#L1069).
- **Call site:** [classify-report/index.ts:96](../supabase/functions/classify-report/index.ts#L96) via the shared
  `groqChat` wrapper.
- **Sends:** system prompt (~700 chars) + one line of `Category: … (Barangay …)\nReport: "<remarks>"`.
  Multilingual (EN/FIL/Taglish/Ilocano). Short — one report per call.
- **Expects:** JSON object `{urgency, reason}`, requested with `response_format: {type:"json_object"}`,
  `temperature: 0`, `max_tokens: 100`. Parser tolerates ``` fences and stray prose
  ([:76](../supabase/functions/classify-report/index.ts#L76)).
- **Model config:** hardcoded `const MODEL` at [:24](../supabase/functions/classify-report/index.ts#L24). Not shared, not env-driven.
- **Traffic:** per-insert trigger (`trg_classify_report`,
  [SETUP.sql:84](../supabase/functions/classify-report/SETUP.sql#L84)) on every report with remarks,
  **plus** a batch sweep every 15 min at `limit 50`
  ([CATCHUP_CRON.sql:51](../supabase/functions/CATCHUP_CRON.sql#L51)). Batch loops **sequentially** — up to
  50 serial Groq calls in one function invocation.

### 2. Feedback classification — `classify-feedback`

- **What it does:** Writes `ai_sentiment`, `ai_urgency`, `ai_theme` (fixed 8-label taxonomy) onto
  `public.feedbacks`. Feeds the admin NLP panel and, downstream, the trend inputs of feature 4.
- **Call site:** [classify-feedback/index.ts:146](../supabase/functions/classify-feedback/index.ts#L146) via `groqChat`.
- **Sends:** system prompt (~1.6k chars, includes the theme taxonomy) + `Overall rating: n/5\nComment: "<text>"`.
- **Expects:** JSON `{sentiment, urgency, theme}`, JSON mode, `temperature: 0`, `max_tokens: 120`.
  Theme is coerced onto the closed taxonomy by `normalizeTheme`
  ([:64](../supabase/functions/classify-feedback/index.ts#L64)) so model drift can't fragment the labels.
- **Model config:** hardcoded `const MODEL` at [:34](../supabase/functions/classify-feedback/index.ts#L34).
  The comment right above it already suggests the 70B as the upgrade path.
- **Traffic:** per-insert trigger (`trg_classify_feedback`,
  [AUTO_CLASSIFY.sql:71](../supabase/functions/classify-feedback/AUTO_CLASSIFY.sql#L71)) — **only for rows
  with a written comment** — plus the same 15-min `limit 50` catch-up sweep. Rating-only rows are
  handled deterministically with no API call at all
  ([:164](../supabase/functions/classify-feedback/index.ts#L164)), which is a nice quota saver.

### 3. Community moderation — `moderate-content`

- **What it does:** Context-aware profanity/abuse detection on `community_posts` and
  `community_comments` in EN/Tagalog/Taglish/Ilocano — catching coded and mixed-language toxicity the
  on-device word list misses. Sets `flagged`, `flag_reason`, `ai_moderated_at`; a flagged **comment**
  also goes to `status = 'pending'` (held for review).
- **Call site:** [moderate-content/index.ts:99](../supabase/functions/moderate-content/index.ts#L99) — **a direct
  `fetch`, not the shared `groqChat` wrapper.** See §6.
- **Sends:** system prompt (~900 chars) + `Text: "<title\nbody>"`. Post bodies are **not length-capped**
  anywhere in this path — the only unbounded per-item input among the three 8B features.
- **Expects:** JSON `{toxic, reason}`, JSON mode, `temperature: 0`, `max_tokens: 60`.
- **Model config:** hardcoded `const MODEL` at [:31](../supabase/functions/moderate-content/index.ts#L31).
- **Traffic:** **highest volume of the three.** Per-insert triggers on *both* posts and comments
  ([AUTO_MODERATE.sql:72,79](../supabase/functions/moderate-content/AUTO_MODERATE.sql#L72)); comments are the
  most frequent write in the app. Batch mode exists but nothing schedules it.

### 4. Predictive outlook — `recommend-actions`

- **What it does:** Aggregates recent feedback + reports + suggestions server-side, asks for a
  1–2 sentence outlook plus up to 4 `{title, scope, metric, suggestion, severity}` focus items, and
  caches them in the singleton `ai_dashboard_insights` row (id=1). Rendered under "Predictive
  outlook → Recommended focus" with an "AI" badge.
- **Call site:** [recommend-actions/index.ts:360](../supabase/functions/recommend-actions/index.ts#L360) via `groqChat`.
- **Sends:** the largest *structured* payload in the system. Reads up to 300 feedback + 300 reports +
  300 suggestions, then compacts them via `buildAggregate`
  ([:127](../supabase/functions/recommend-actions/index.ts#L127)) into counts, per-office aspect
  averages, negative-theme 30d-vs-prior-30d trend, high-urgency report trend by category/barangay —
  **plus up to 20 verbatim negative comments and 12 verbatim urgent report remarks.** Realistically
  2–6k tokens, and it scales with data volume.
- **Expects:** JSON `{summary, focus[]}`, JSON mode, `temperature: 0.3`, `max_tokens: 600`.
  Post-parse the client applies a hallucination guard — it refuses the AI outlook entirely when
  there's too little real feedback behind it
  ([admin_dashboard_provider.dart:1144](../lib/features/admin/providers/admin_dashboard_provider.dart#L1144)).
- **Model config:** hardcoded `const MODEL` at [:22](../supabase/functions/recommend-actions/index.ts#L22),
  with a comment explaining the 70B choice.
- **Traffic:** **occasional.** Client fire-and-forget kick when the cached row is stale, behind a
  **static 10-minute debounce** shared across rebuilds
  ([admin_dashboard_provider.dart:588](../lib/features/admin/providers/admin_dashboard_provider.dart#L588)).
  The daily cron backstop in [SETUP.sql:51](../supabase/functions/recommend-actions/SETUP.sql#L51) is
  **commented out** — so in practice this only runs when an admin opens the dashboard.

### 5. "Kuya Gov" chat assistant — `chat-agent`

- **What it does:** The citizen-facing LGU virtual assistant. Answers civic-process questions from a
  large embedded `KNOWLEDGE_BASE`, mirrors the citizen's language (EN/Filipino/Ilocano/Ybanag rules),
  and emits exactly one `[ACTION:REPORT|AGENT|END]` tag to drive the Flutter conversation state machine.
- **Call site:** [chat-agent/index.ts:517](../supabase/functions/chat-agent/index.ts#L517) — the model string is
  an **inline literal in the request body**, not even a named const. Direct `fetch`, no `groqChat`.
- **Sends:** the biggest prompt in the app. `SYSTEM_PROMPT` + `KNOWLEDGE_BASE` ≈ 2.5–3k tokens, then
  **the entire client-supplied `history` array with no truncation**
  ([:483](../supabase/functions/chat-agent/index.ts#L483)), a per-stage instruction block, and an optional
  events JSON blob. Long conversations grow this without bound.
- **Expects:** **plain text** (not JSON) — free-form prose with an optional tag on line 1, normalised
  server-side by `normalizeActionTag` ([:392](../supabase/functions/chat-agent/index.ts#L392)).
  `max_tokens: 800`, `temperature: 0.25`, `top_p: 0.9`.
- **Model config:** inline literal at [:517](../supabase/functions/chat-agent/index.ts#L517).
- **Traffic:** **highest per-user volume.** One call per citizen chat message, plus one on chat open
  and one on follow-up open — three separate invoke sites in
  [chat_service.dart:424, 1071, 1616](../lib/core/services/chat_service.dart#L424). Protected by a
  server-side per-user limit of **30 messages/60s** via the `enforce_rate_limit` RPC
  ([:456](../supabase/functions/chat-agent/index.ts#L456)), and it degrades to the on-device
  [local_assistant.dart](../lib/core/services/local_assistant.dart) brain when Groq is unavailable.

---

## 3. Is the model string centralized?

**No — and this is the main migration friction.**

[`_shared/groq.ts`](../supabase/functions/_shared/groq.ts) centralizes the *transport* — the base URL
([:19](../supabase/functions/_shared/groq.ts#L19)), auth header, and 429/5xx retry with `Retry-After`
handling — but the caller passes `model` in the body, so **the model name is deliberately outside the
shared layer.** There is no env var, no config file, no `config.toml` entry.

Five call sites, five independent declarations:

| Location | Form | Model |
|---|---|---|
| [classify-report/index.ts:24](../supabase/functions/classify-report/index.ts#L24) | `const MODEL` | `llama-3.1-8b-instant` ⚠️ |
| [classify-feedback/index.ts:34](../supabase/functions/classify-feedback/index.ts#L34) | `const MODEL` | `llama-3.1-8b-instant` ⚠️ |
| [moderate-content/index.ts:31](../supabase/functions/moderate-content/index.ts#L31) | `const MODEL` | `llama-3.1-8b-instant` ⚠️ |
| [recommend-actions/index.ts:22](../supabase/functions/recommend-actions/index.ts#L22) | `const MODEL` | `llama-3.3-70b-versatile` |
| [chat-agent/index.ts:517](../supabase/functions/chat-agent/index.ts#L517) | **inline literal in the request body** | `llama-3.3-70b-versatile` |

**Minimum change for the Aug 16 deadline: 3 one-line edits + 3 redeploys.** Small, but each is a
separate `supabase functions deploy`, and the model can't be flipped without a deploy — there's no
runtime override.

Also stale: [chat-agent/index.ts:9](../supabase/functions/chat-agent/index.ts#L9) documents the historical
`llama-3.1-8b-instant → llama-3.3-70b-versatile` upgrade, and
[classify-feedback/index.ts:32](../supabase/functions/classify-feedback/index.ts#L32) recommends the 70B as
the upgrade path. Both comments will be misleading after the migration.

**Suggested (post-deadline) hardening:** add `MODEL_FAST` / `MODEL_SMART` to `_shared/groq.ts`, or read
`Deno.env.get("GROQ_MODEL_FAST")` with a hardcoded default, so the next decommission is a secret
change instead of three deploys.

### `GROQ_API_KEY`

Read via `Deno.env.get("GROQ_API_KEY")` in all five functions
([chat-agent:435](../supabase/functions/chat-agent/index.ts#L435),
[classify-report:120](../supabase/functions/classify-report/index.ts#L120),
[classify-feedback:187](../supabase/functions/classify-feedback/index.ts#L187),
[moderate-content:133](../supabase/functions/moderate-content/index.ts#L133),
[recommend-actions:296](../supabase/functions/recommend-actions/index.ts#L296)).
It is a Supabase secret — **it does not appear in any repo file, `.env`, or `config.toml`.** Good.
Every function returns a clean 500 when it's missing. One shared key across all five, so any per-model
rate limiting is pooled across features.

---

## 4. Tests, mocks, fixtures referencing the old model

**None.** A whole-project grep (excluding `node_modules/`) for `llama` / `groq` / `GROQ_API_KEY` hits
only the 5 Edge Functions, 3 SQL files, and 2 Dart files that mention Groq **in comments only**
([chat_service.dart:115](../lib/core/services/chat_service.dart#L115),
[local_assistant.dart:5](../lib/core/services/local_assistant.dart#L5),
[admin_dashboard_provider.dart:250](../lib/features/admin/providers/admin_dashboard_provider.dart#L250)).
The single `groq` hit in `functions/package-lock.json` is a false positive — a base64 fragment inside a
`sha512` integrity hash.

Three widget tests exercise the AI-labelled **columns**, but are provider- and model-agnostic — they
build `ai_dashboard_insights` / `ai_urgency` fixtures by hand and never name a model:

- [test/admin_nlp_outlook_test.dart](../test/admin_nlp_outlook_test.dart) — the stale-cached-summary regression
- [test/admin_outlook_render_test.dart](../test/admin_outlook_render_test.dart)
- [test/admin_dashboard_layout_test.dart](../test/admin_dashboard_layout_test.dart)

**Implication:** the test suite will stay green through a model swap and will **not** catch a bad model
name. There is no integration test that actually calls Groq. Post-swap verification has to be manual
(invoke each function once and check for a 400).

---

## 5. Rate-limit / token-limit risk per feature

Ranked by exposure:

| Feature | Volume shape | Peak burst | Risk |
|---|---|---|---|
| **moderate-content** | Every post **and** comment insert | 50 serial calls per batch run | 🔴 **Highest.** Comment traffic is the app's most frequent write; no retry wrapper (§6); unbounded post-body length |
| **chat-agent** | 1 per chat message, ×3 open paths | 30/user/60s cap | 🟠 Capped per user, but **unbounded history** is a real TPM/context risk on long conversations |
| **classify-report** | 1 per report + 50/15min sweep | 200 calls/hr worst case | 🟡 Sweep is self-limiting — finds 0 rows when healthy, costs nothing |
| **classify-feedback** | 1 per commented feedback + 50/15min sweep | 200 calls/hr worst case | 🟡 Same; rating-only rows skip the API entirely |
| **recommend-actions** | On dashboard open, 10-min debounce | 1 call | 🟢 Lowest RPM, **highest TPM per call** (2–6k tokens in, 600 out) |

Two structural notes:

1. **Both catch-up crons run every 15 min at `limit 50` and loop sequentially.** With a deployment-wide
   shared API key, a large backfill on both functions simultaneously can eat a meaningful slice of a
   free-tier RPM budget. The `groqChat` wrapper's `Retry-After` handling
   ([groq.ts:48](../supabase/functions/_shared/groq.ts#L48)) is what keeps this from silently dropping rows —
   which is exactly what `moderate-content` lacks.
2. **`chat-agent` has no history truncation.** A 50-turn conversation replays every prior message on
   every call. This is the one place a context/TPM limit could bite in normal use, independent of the
   model migration. Worth a `history.slice(-N)` regardless of which model you land on.

---

## 6. Two pre-existing defects worth fixing in the same PR

Not caused by the decommission, but the decommission makes both much worse. **Not fixed — flagging only,
per your no-code-change instruction.**

**a) `moderate-content` bypasses the shared retry wrapper.**
It calls `fetch` directly at [:99](../supabase/functions/moderate-content/index.ts#L99) instead of importing
`groqChat`. So it has **no 429 retry and no `Retry-After` handling** — on a rate-limit it logs and
returns `null`, and the row stays unmoderated. Note that when this happens `ai_moderated_at` is
*never set*, so the row does stay eligible for a future batch run — but nothing schedules one.

**b) `moderate-content` has no catch-up cron.**
[CATCHUP_CRON.sql](../supabase/functions/CATCHUP_CRON.sql) schedules sweeps for `classify-feedback` and
`classify-report` **only**. Moderation has a working `mode: batch` path that nothing ever calls.

**Combined effect on Aug 16:** every community post and comment created after the decommission gets a
400, is never flagged, and is **never revisited**. The word-list trigger still provides the baseline,
but the AI layer's backlog will be permanently lost unless someone manually POSTs the batch endpoint.
Reports and feedback, by contrast, will self-heal within ~15 minutes of a fix landing.

---

## 7. Replacement recommendation per feature

> ⚠️ **Verify model IDs against Groq's live model list before deploying** — the roster and pricing move
> fast, and this is exactly the kind of change that just bit us. Treat the IDs below as candidates to
> confirm, not as verified strings.

The three JSON classifiers share a profile: tiny input, tiny output, `temperature: 0`, strict JSON mode,
multilingual (Tagalog/Taglish/Ilocano) — and every one of them has a defensive parser plus an on-device
fallback, so a slightly different failure shape is survivable.

| Feature | Recommendation | Why |
|---|---|---|
| **classify-report** | `openai/gpt-oss-20b` | Matches your instinct. Short input, trivial output, needs speed and JSON-mode support, not reasoning depth. Set `reasoning_effort: "low"` so GPT-OSS's reasoning tokens don't inflate latency/cost on a 100-token task |
| **classify-feedback** | `openai/gpt-oss-20b` | Same profile. **Watch the multilingual quality** — this is the most language-sensitive of the three (Ilocano/Taglish sentiment nuance). If eval regresses, `llama-3.3-70b-versatile` is the drop-in per the existing comment at [:32](../supabase/functions/classify-feedback/index.ts#L32); volume is low enough to afford it |
| **moderate-content** | `openai/gpt-oss-20b` | Highest volume → cheapest/fastest tier wins. **But validate against coded and mixed-language toxicity specifically** — that's the whole reason this layer exists over the word list. A weaker multilingual model here is a silent safety regression, not a cosmetic one |
| **recommend-actions** | **Keep `llama-3.3-70b-versatile`** for now; if you're consolidating, `openai/gpt-oss-120b` | Not affected by this decommission. Genuinely needs reasoning quality (grounding numbers, refusing to invent metrics) and runs rarely — quality/cost trade-off already documented at [:20](../supabase/functions/recommend-actions/index.ts#L20). Its 2–6k-token aggregate is nowhere near any modern context limit, so "large-context" isn't the constraint; reasoning is |
| **chat-agent** | **Keep `llama-3.3-70b-versatile`**; evaluate `openai/gpt-oss-120b` as successor | Not affected. The v3 notes at [:9](../supabase/functions/chat-agent/index.ts#L9) record that the 8B was *already rejected here* for tag leakage and Ilocano/Ybanag fallback failures — so do **not** downgrade this one. If you migrate, re-test the `[ACTION:*]` tag discipline and the Ybanag→Ilocano fallback rule explicitly; those are the two things that broke last time |

### Nothing here needs a large-context model

Worth stating plainly, since it's a common assumption: GovPulse has **no long-document summarization
feature**. The largest payloads are `chat-agent`'s accumulated history and `recommend-actions`'
aggregate JSON, both comfortably inside a standard 128k window. Context length should not drive the
model choice — multilingual quality and JSON-mode reliability should.

### Suggested order of work

1. **Before Aug 16** — flip the three `MODEL` constants, redeploy all three functions.
2. **Immediately after** — invoke each once (single-row mode) and confirm a 200 with a parseable JSON
   body. The test suite will *not* tell you this (§4).
3. **Same PR if possible** — point `moderate-content` at `groqChat`, and add its batch sweep to
   `CATCHUP_CRON.sql` (§6).
4. **Follow-up** — centralize the model names (§3), and cap `chat-agent` history (§5).
5. **Backlog** — re-validate Tagalog/Ilocano quality on features 2 and 3 against a handful of real rows
   before trusting the new labels in the dashboard.
