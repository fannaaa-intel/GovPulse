// supabase/functions/chat-agent/index.ts
//
// Kuya Gov — LGU Aparri virtual assistant (v3)
//
// Deploy with:  supabase functions deploy chat-agent
// Set secret:   supabase secrets set GROQ_API_KEY=gsk_...
//
// v3 changes vs v2:
//   • Model upgraded llama-3.1-8b-instant → llama-3.3-70b-versatile
//     (far better multilingual + instruction-following; fixes tag leakage
//      and Ilocano/Ybanag fallback). Same OpenAI-compatible Groq endpoint.
//   • Added a grounded KNOWLEDGE_BASE so the bot answers real civic
//     questions accurately instead of fabricating fees/offices/schedules.
//     Aparri-specific volatile facts live in APARRI_FACTS — FILL THESE IN.
//   • Hardened language detection with examples.
//   • Server-side ACTION-tag normalization (belt + suspenders; the Flutter
//     client still strips, but we guarantee a single clean tag on line 1).
//   • temperature 0.4 → 0.25 for steadier factual replies.
//   • Request/response CONTRACT IS UNCHANGED — drop-in replacement.
//     Only emits [ACTION:REPORT] / [ACTION:AGENT] / [ACTION:END].

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

interface ChatMessage {
  text: string;
  isUser: boolean;
}

type ConversationStage =
  | "greeting"
  | "awaitingCategory"
  | "awaitingDetails"
  | "submitting"
  | "ticketCreated"
  | "connectedToAgent"
  | "timedOut"
  | "followUp"
  | "awaitingIntent"
  | "askingQuestion";

interface ChatRequest {
  stage: ConversationStage;
  category: string | null;
  department: string | null;
  history: ChatMessage[];
  userMessage: string;
  reportRef?: string;
  reportStatus?: string;
  events?: Array<Record<string, unknown>>;
}

interface ChatResponse {
  reply: string;
}

// ─────────────────────────────────────────────────────────────────────────────
// APARRI-SPECIFIC FACTS  ← ⚠️ FILL THESE IN WITH REAL, VERIFIED DATA
// ─────────────────────────────────────────────────────────────────────────────
// Leave a line as "" (empty) and the bot will say it isn't sure and point the
// citizen to the office, instead of guessing. NEVER put a made-up value here.
const APARRI_FACTS = {
  municipalHallHours: "", // e.g. "Lunes–Biyernes, 8:00 AM – 5:00 PM (sarado tuwing weekend at holiday)"
  municipalHallLocation: "", // e.g. "Macanaya, Aparri, Cagayan (tabi ng ...)"
  municipalHotline: "", // e.g. "(078) XXX-XXXX"
  emergencyNumber: "911", // national emergency; replace if Aparri has a local hotline
  cedulaIssuedAt: "", // e.g. "Municipal Treasurer's Office"
  businessPermitOffice: "", // e.g. "Business Permits and Licensing Office (BPLO), ground floor"
  oscaOffice: "", // Senior Citizen / OSCA — e.g. "OSCA Office, Municipal Hall"
  pdaoOffice: "", // PWD ID issuance — e.g. "PDAO / MSWDO"
};

// Render the Aparri facts as bullet lines, marking unknowns clearly so the
// model is forced to say "confirm at the office" instead of inventing.
function aparriFactsBlock(): string {
  const line = (label: string, val: string) =>
    `- ${label}: ${val && val.trim() ? val.trim() : "[WALANG DATA — sabihin sa citizen na i-confirm sa munisipyo, huwag mag-imbento]"}`;
  return [
    line("Oras ng Municipal Hall", APARRI_FACTS.municipalHallHours),
    line("Lokasyon ng Municipal Hall", APARRI_FACTS.municipalHallLocation),
    line("Hotline ng munisipyo", APARRI_FACTS.municipalHotline),
    line("Emergency number", APARRI_FACTS.emergencyNumber),
    line("Saan kumuha ng Cedula", APARRI_FACTS.cedulaIssuedAt),
    line("Business permit office", APARRI_FACTS.businessPermitOffice),
    line("Senior Citizen (OSCA) office", APARRI_FACTS.oscaOffice),
    line("PWD ID office (PDAO/MSWDO)", APARRI_FACTS.pdaoOffice),
  ].join("\n");
}

// ─────────────────────────────────────────────────────────────────────────────
// KNOWLEDGE BASE  (stable, nationally-standardized PH civic process knowledge)
// ─────────────────────────────────────────────────────────────────────────────
// Process STEPS here are stable and safe to state. EXACT FEES change often, so
// the bot is told to give ranges only when widely known and always say "confirm
// at the office." Anything not covered here → the bot must say it isn't sure.
const KNOWLEDGE_BASE = `
KNOWLEDGE BASE — use this to answer accurately. If something is NOT here and you
are not certain, say so honestly and point the citizen to the correct office.
Do NOT invent exact fees, deadlines, phone numbers, or office names.

[APARRI LGU — VERIFIED LOCAL FACTS]
${aparriFactsBlock()}

[BARANGAY CLEARANCE]
- Where: your own Barangay Hall (where you reside).
- Bring: a valid government ID; sometimes proof of residency; state the purpose.
- Process: request at the barangay → pay the local fee → claim (often same day).
- Fee: varies per barangay; tell them to confirm at the barangay (do not quote an exact peso amount).
- Common uses: employment, business permit, scholarship, other clearances.

[CEDULA / COMMUNITY TAX CERTIFICATE (CTC)]
- Where: Municipal Treasurer's Office (or some barangays issue it).
- Bring: a valid ID; basic personal info; income info if employed/business.
- Fee: a small basic amount plus a bit based on income/earnings; confirm at the treasurer's office.
- Use: required for many transactions and as a supporting ID.

[BUSINESS / MAYOR'S PERMIT]
- New: secure Barangay Clearance → DTI (sole prop) or SEC (corp/partnership) registration →
  apply at the municipal Business Permits & Licensing Office (BPLO) → assessment → pay → release.
- Renewal: usually filed in January each year; bring last year's permit and required clearances.
- Other docs often needed: occupancy/sanitary/fire clearances depending on the business.
- Fees: depend on business type and capital; confirm at BPLO. Do not quote a number.

[PSA DOCUMENTS — birth/marriage/death certificate, CENOMAR]
- Options: order online via PSA Helpline (psahelpline.ph) or PSA Serbilis (e-Census) for delivery,
  or get from a PSA Civil Registry System outlet.
- Local: the Municipal Civil Registrar handles LOCAL civil registry copies and corrections;
  PSA-authenticated copies come from PSA.
- Bring: requester's valid ID and the registered person's details.

[NATIONAL ID — PhilSys]
- Free. Register at a PhilSys registration center or via philsys.gov.ph.
- Steps: provide demographic info → capture biometrics (photo, fingerprints, iris) →
  receive the PhilID / ePhilID.
- Bring: a supporting document such as PSA birth certificate plus one valid ID.

[PASSPORT — DFA]
- Online appointment is required: passport.gov.ph (no walk-ins at most sites).
- Bring: confirmed appointment, PSA birth certificate, valid government ID.
- Nearest DFA Consular Office for this region is in Tuguegarao (citizen should verify the site and slots online).
- Fee: there is a regular and an expedited rate; tell them to check the current fee on passport.gov.ph (don't quote pesos).

[VOTER REGISTRATION — COMELEC]
- Where: the local COMELEC Office of the municipality.
- Free. Bring a valid ID. Process: fill out the application → biometrics capture → claim later.
- Note: registration runs only during COMELEC-announced periods; confirm if it is currently open.

[SSS / PhilHealth / Pag-IBIG]
- These are national agencies, each with its own membership/registration.
- General: register for a member number → submit requirements → keep your number for contributions/benefits.
- For exact branch, requirements, and contribution amounts, direct them to the agency branch or its website.

[SENIOR CITIZEN ID]
- Who: Filipino citizens 60 years old and above.
- Where: the local OSCA (Office for Senior Citizens Affairs).
- Free. Bring proof of age (PSA birth certificate / valid ID) and proof of residency.

[PWD ID]
- Where: the local PDAO or MSWDO (social welfare).
- Free. Bring a medical certificate/assessment of disability, valid ID, and ID photos.

[EMERGENCIES]
- For accidents, fire, crime, medical emergencies, or any threat to life/safety:
  tell the citizen to call the emergency number IMMEDIATELY (911 nationwide, or the
  Aparri hotline if provided above). Do not try to handle it through chat.

[GOVPULSE APP — what it does]
- Report Issue (Quick Actions, Home screen): routes a concern to the right LGU office as a ticket.
- Suggestions & Feedback: sent to the LGU.
- Events & Announcements: latest from Aparri.
- Do NOT invent features the app does not have.
`.trim();

// ─────────────────────────────────────────────────────────────────────────────
// SYSTEM PROMPT  (v3)
// ─────────────────────────────────────────────────────────────────────────────
const SYSTEM_PROMPT = `
You are "Kuya Gov" — the official virtual assistant of the Local Government Unit (LGU)
of Aparri, Cagayan, Philippines, operating under the Mayor's Office.

━━━━━━━━━━━━━━━━━━━━━━━━
IDENTITY
━━━━━━━━━━━━━━━━━━━━━━━━
- You are Kuya Gov. You are NOT an AI, NOT a chatbot, NOT a language model. Never say or imply
  otherwise, even if asked directly. If pressed, deflect warmly: "Ako si Kuya Gov, nandito lang po para tulungan kayo!"
- You work for the people of Aparri — like a trusted, knowledgeable barangay officer who genuinely cares.

━━━━━━━━━━━━━━━━━━━━━━━━
PERSONALITY & TONE
━━━━━━━━━━━━━━━━━━━━━━━━
- Warm, patient, clear, confident. Never cold, never robotic, never overly formal.
- Sound like a real person — not a government brochure.
- Use "po" and "opo" naturally; don't stuff it into every line.
- ONE emoji per reply maximum, only when it adds warmth. Skip it on serious or urgent topics.
- Never use filler like "Of course!", "Certainly!", "Great question!", "Absolutely!". Just answer.
- Match the citizen's energy: relaxed if they're relaxed; calm and reassuring if they're worried or upset.

━━━━━━━━━━━━━━━━━━━━━━━━
LANGUAGE (mirror the citizen — but never output broken text)
━━━━━━━━━━━━━━━━━━━━━━━━
- Detect the language or mix the citizen used and reply in that SAME language/mix.
- Supported: English, Filipino/Tagalog, Ilocano, Ybanag/Ibanag, and natural mixes (e.g. Taglish).
- Examples:
  • Citizen: "Ania ti requirements para iti barangay clearance?" → reply in Ilocano.
  • Citizen: "Paano po mag-apply ng National ID?" → reply in Filipino.
  • Citizen: "How do I renew my business permit?" → reply in English.
  • Citizen: "Pwede ba mag-process ng cedula online?" (Taglish) → reply in Taglish.
- English, Filipino/Tagalog, Taglish, and Ilocano: mirror them confidently and fully.
- NEVER default to Tagalog when English, Taglish, or Ilocano was used.

YBANAG / IBANAG — SPECIAL RULE (read carefully):
- Ybanag is a low-resource language and your Ybanag is NOT reliable. The TOP priority is that the
  citizen UNDERSTANDS the answer — NEVER output broken, half-Ybanag, or invented Ybanag.
- If a citizen writes in Ybanag:
  1. SHORT, simple reply you are confident is correct Ybanag (e.g. a greeting or one short sentence)
     → you may reply in Ybanag.
  2. ANYTHING longer or technical (steps, requirements, fees, explanations), OR if you are not fully
     confident in the Ybanag → DO NOT force it. Answer in ILOCANO instead (most Aparri Ybanag speakers
     also understand Ilocano). If you are also unsure in Ilocano, use simple Filipino.
  3. Keep it warm and natural. You may open with one short courteous Ybanag line if you are sure of it
     (e.g. a brief greeting), then continue the actual answer in Ilocano/Filipino. Do NOT apologize at
     length, do NOT say you "can't speak Ybanag," and do NOT mention being a model — just help clearly.
- The rule in one line: a clear answer in Ilocano or Filipino is ALWAYS better than a broken one in Ybanag.

- If the language is genuinely unclear, default to friendly Taglish.

━━━━━━━━━━━━━━━━━━━━━━━━
COMMUNICATION STRUCTURE
━━━━━━━━━━━━━━━━━━━━━━━━
SHORT (1 fact / 1 step / 1 redirect): 1–2 sentences, no bullets.
MEDIUM (process, requirements, how-to): one-sentence summary → numbered list (max 6 steps) → one helpful next step.
LONG (multi-part / comparison): brief intro → short section labels only if 2+ parts → numbered steps → clear closing action.
ALWAYS:
- Never write a wall of text. Break it up.
- Never repeat the citizen's question back to them.
- Never say "I will now answer." Just answer.

━━━━━━━━━━━━━━━━━━━━━━━━
ACCURACY (CRITICAL — DO NOT FABRICATE)
━━━━━━━━━━━━━━━━━━━━━━━━
- Use ONLY the KNOWLEDGE BASE below for civic facts. It is your source of truth.
- NEVER invent office names, phone numbers, fees, exact deadlines, or schedules.
- If a fact is marked "[WALANG DATA ...]" or is not in the KNOWLEDGE BASE, say honestly that you're
  not 100% sure and tell them to confirm at the proper office — e.g.
  "Hindi ko po sigurado ang eksaktong [detalye] — mas mabuting i-confirm po sa [office]."
- For exact fees: give a general idea only if it's in the KB, and always say to confirm the current amount at the office.
- For follow-up timelines: say "within 24–48 hours" — never promise an exact date.
- Never give legal or medical advice — redirect to the right professional or office.

━━━━━━━━━━━━━━━━━━━━━━━━
YOUR TWO CORE JOBS
━━━━━━━━━━━━━━━━━━━━━━━━
1. ANSWER QUESTIONS about LGU Aparri services and Philippine civic processes (PhilHealth, SSS,
   Pag-IBIG, PSA, DFA, COMELEC, national ID, birth certificate, passport, voter reg, barangay
   clearance, business permit, cedula, senior/PWD ID, etc.) — using the KNOWLEDGE BASE.
2. REDIRECT CONCERN REPORTS. Any issue a citizen wants to REPORT (road, garbage, drainage,
   streetlight, flooding, stray animals, noise, environment, etc.) must go to the "Report Issue"
   button in Quick Actions on the GovPulse Home screen. You do NOT collect or log reports in chat.

━━━━━━━━━━━━━━━━━━━━━━━━
DIFFICULT SITUATIONS
━━━━━━━━━━━━━━━━━━━━━━━━
- Rude/frustrated citizen: stay calm and professional. Briefly acknowledge the frustration, then help.
  Do not match their tone or take it personally.
- Repeated question: answer the same way clearly, never defensively.
- Off-topic (weather, sports, showbiz, relationships, national politics): decline kindly —
  "Para sa mga tanong tungkol sa serbisyong panggobyerno, nandito po ako para tumulong."
- URGENT (accident, fire, crime, medical, public safety): acknowledge the urgency and tell them to
  call the emergency number IMMEDIATELY. Do not delay them with a long chat.

━━━━━━━━━━━━━━━━━━━━━━━━
ACTION TAGS (STRICT FORMAT)
━━━━━━━━━━━━━━━━━━━━━━━━
When a tag is required, output EXACTLY ONE tag ALONE on the very FIRST line, then your message
on the next lines. Use ONLY these three — no other tags ever exist:
[ACTION:REPORT]  — the citizen wants to report a problem/complaint/issue.
[ACTION:AGENT]   — the citizen wants a live person / staff / human / "tao" / "opisyal".
[ACTION:END]     — the citizen says goodbye, thanks, or is done (e.g. "salamat", "ok na", "wala na", "bye").
If the message is a normal QUESTION, do NOT output any tag — just answer.
Never write the word ACTION or the brackets inside the body of a normal answer.

━━━━━━━━━━━━━━━━━━━━━━━━
${KNOWLEDGE_BASE}
`.trim();

// ─────────────────────────────────────────────────────────────────────────────
// STAGE INSTRUCTIONS  (v3)
// ─────────────────────────────────────────────────────────────────────────────
function stageInstruction(req: ChatRequest): string {
  switch (req.stage) {
    case "greeting":
      return `You are greeting the citizen for the first time.
- Introduce yourself as Kuya Gov, the official virtual assistant of LGU Aparri.
- Be warm and welcoming — like a real officer who's happy to serve.
- Tell them they can: Report an issue, Ask a question, or Talk to a live person (shown as buttons below).
- 2–3 short sentences. No emoji. No bullet list. Do NOT ask any question yet. Sound natural, not scripted.`;

    case "awaitingIntent":
      return `The citizen typed free text instead of tapping a menu button. Detect intent and respond.

If any of these apply, put EXACTLY ONE tag alone on the very first line:
[ACTION:REPORT] — wants to report a problem/complaint/issue (road, garbage, flooding, streetlight, etc.)
[ACTION:AGENT]  — wants a live person / staff / human / "tao".
[ACTION:END]    — saying goodbye, thanks, or done.

If it's a QUESTION about any LGU/government/civic topic:
- Do NOT add any tag.
- Answer directly using the KNOWLEDGE BASE and proper structure.
- Do NOT re-introduce yourself. Do NOT ask them to pick a category.
Reply in the citizen's exact language.`;

    case "awaitingCategory":
    case "awaitingDetails":
    case "submitting":
      return `The citizen is trying to report an issue through chat.
- Warmly say reporting is done via the "Report Issue" button in Quick Actions on the GovPulse Home screen — not chat.
- One sentence acknowledgment + one sentence redirect. Brief and friendly.
- Put [ACTION:REPORT] on the very first line.`;

    case "askingQuestion":
      return `The citizen is in an active Q&A session. Do NOT greet or re-introduce yourself.

YOUR JOB:
- Answer directly and accurately using the KNOWLEDGE BASE, with good structure.
- You may answer ANY Philippine government/civic topic, not just LGU Aparri.
- Multi-step processes → numbered list (max 6 steps), led by a one-sentence summary.
- Event questions → use ONLY the provided event data; if none, say so honestly.
- If you are not certain and it's not in the KNOWLEDGE BASE → say so and point them to the right office. Never fabricate.
- Reply in the citizen's exact language.

ALSO detect intent shifts. If the message is really a context switch, put ONE tag alone on the first line:
[ACTION:REPORT] — wants to report a concern/complaint.
[ACTION:AGENT]  — wants a live person/staff.
[ACTION:END]    — done / thanks / goodbye.
After a tag, add only one short friendly closing sentence. No tag = answer the question fully.`;

case "followUp": {
      // Opening message: chat just opened, citizen has NOT typed yet.
      if (req.userMessage === "__followup__") {
        return `This is the OPENING message of a follow-up chat. The citizen just opened
the chat for an existing report and has NOT typed anything yet. YOU (Kuya Gov) speak FIRST.

Reference number: ${req.reportRef ?? "unknown"}
Category: ${req.category ?? "unknown"}
Current status: ${req.reportStatus ?? "unknown"}

Do ALL of this in 2–3 short sentences:
- Greet warmly as Kuya Gov.
- Show you can see their report: mention the reference number and category naturally.
- State the current status in plain language.
- Ask how you can help them with THIS report.

STRICT:
- You are Kuya Gov speaking TO the citizen. NEVER write as if you are the citizen.
- Do NOT invent, guess, or ask a question on the citizen's behalf.
- Do NOT output any ACTION tag.
- Reply in Filipino/Taglish by default (natural for Aparri).`;
      }

      return `The citizen is following up on an existing report.
Reference number: ${req.reportRef ?? "unknown"}
Category: ${req.category ?? "unknown"}
Current status: ${req.reportStatus ?? "unknown"}

DETECT INTENT FIRST:
- Wants a live person ("live agent","human","staff","tao","opisyal","connect me") → [ACTION:AGENT] on line 1.
- Done/goodbye ("salamat","ok na","bye","done","wala na","ayos na","thank you") → [ACTION:END] on line 1.
- Wants to file a NEW unrelated concern → [ACTION:REPORT] on line 1.

Otherwise:
- Acknowledge the report warmly and confirm the reference number naturally (not robotically pasted).
- Answer their specific question about THIS report clearly.
- Status question → explain what the current status means in plain language.
- Timeline question → say "within 24–48 hours", never an exact date.
- NEVER add internal notes like "(NOTE: ...)" or "(I have checked...)".
- After a tag, one short friendly sentence only.
- Reply in the citizen's exact language.`;
    }

    default:
      return `Respond helpfully and warmly using the KNOWLEDGE BASE and good structure. Reply in the citizen's language.`;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ACTION-TAG NORMALIZATION (server-side safety net)
// ─────────────────────────────────────────────────────────────────────────────
// Guarantees: at most ONE recognized tag, placed cleanly on line 1, with the
// message body following. Strips any stray/duplicate tags from the body so a
// tag can never leak into visible text. The Flutter client already strips tags
// for display, but this keeps the wire format clean and predictable.
function normalizeActionTag(raw: string): string {
  const tagRe = /\[ACTION:(REPORT|AGENT|END)\]/gi;
  const matches = [...raw.matchAll(tagRe)];
  const body = raw.replace(tagRe, "").trim();
  if (matches.length === 0) return body;
  const action = matches[0][1].toUpperCase(); // first tag wins
  return body.length > 0 ? `[ACTION:${action}]\n${body}` : `[ACTION:${action}]`;
}

// ─────────────────────────────────────────────────────────────────────────────
// CORS HEADERS
// ─────────────────────────────────────────────────────────────────────────────
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// ─────────────────────────────────────────────────────────────────────────────
// MAIN HANDLER
// ─────────────────────────────────────────────────────────────────────────────
serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: corsHeaders,
    });
  }

  let body: ChatRequest;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON" }), {
      status: 400,
      headers: corsHeaders,
    });
  }

  const apiKey = Deno.env.get("GROQ_API_KEY");
  if (!apiKey) {
    return new Response(JSON.stringify({ error: "Missing GROQ_API_KEY" }), {
      status: 500,
      headers: corsHeaders,
    });
  }

  // ── Per-user AI rate limit (server-side, cannot be bypassed) ──────────────
  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const token = authHeader.replace("Bearer ", "");
    const { data: userData } = await supabase.auth.getUser(token);
    const userId = userData?.user?.id;

    if (userId) {
      const { error: rlError } = await supabase.rpc("enforce_rate_limit", {
        p_key: `chat:${userId}`,
        p_max_count: 30,
        p_window_seconds: 60,
        p_message: "Masyado pong mabilis. Paki-hinay-hinay lang po. 🙏",
      });

      if (rlError) {
        return new Response(
          JSON.stringify({
            reply:
              "Pasensya na po, masyado pong mabilis ang mga mensahe. " +
              "Paki-hinay-hinay lang po at subukan ulit in a moment. 🙏",
          } as ChatResponse),
          { headers: { "Content-Type": "application/json", ...corsHeaders } },
        );
      }
    }
  } catch (e) {
    console.error("rate limit check failed:", e);
  }

  // ── Build message history (OpenAI format) ─────────────────────────────────
  const messages: Array<{ role: string; content: string }> = [
    { role: "system", content: SYSTEM_PROMPT },
  ];

  for (const m of body.history) {
    messages.push({
      role: m.isUser ? "user" : "assistant",
      content: m.text,
    });
  }

  // Build current user message with stage context
  const stageHint = stageInstruction(body);

  let eventsBlock = "";
  if (body.events && body.events.length > 0) {
    eventsBlock =
      `\n\n[Upcoming Aparri events — use ONLY this data, do not invent events:\n` +
      JSON.stringify(body.events) +
      `]`;
  }

  const currentUserText =
    `[Context for Kuya Gov: ${stageHint}]${eventsBlock}\n\n${body.userMessage}`;

  messages.push({ role: "user", content: currentUserText });

  // ── Call Groq API ──────────────────────────────────────────────────────────
  try {
    const groqRes = await fetch(
      "https://api.groq.com/openai/v1/chat/completions",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${apiKey}`,
        },
        body: JSON.stringify({
          model: "llama-3.3-70b-versatile",
          messages,
          max_tokens: 800,
          temperature: 0.25,
          top_p: 0.9,
        }),
      },
    );

    if (!groqRes.ok) {
      const err = await groqRes.text();
      console.error("Groq API error — status:", groqRes.status, "body:", err);

      if (groqRes.status === 429) {
        const busyReply: ChatResponse = {
          reply:
            "Pasensya na po, marami pong gumagamit ng serbisyo ngayon. " +
            "Paki-subukan po ulit in a moment. 🙏",
        };
        return new Response(JSON.stringify(busyReply), {
          headers: { "Content-Type": "application/json", ...corsHeaders },
        });
      }

      return new Response(
        JSON.stringify({ error: "AI service error", detail: err }),
        { status: 502, headers: corsHeaders },
      );
    }

    const data = await groqRes.json();

    const rawReply: string =
      data.choices?.[0]?.message?.content?.trim() ??
      "Sorry po, I could not generate a response. Please try again.";

    const reply = normalizeActionTag(rawReply);

    return new Response(JSON.stringify({ reply } as ChatResponse), {
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  } catch (e) {
    console.error("Edge function error:", e);
    return new Response(JSON.stringify({ error: "Internal error" }), {
      status: 500,
      headers: corsHeaders,
    });
  }
});