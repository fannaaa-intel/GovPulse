// supabase/functions/chat-agent/knowledge_gaps.ts
//
// Records the questions Kuya Gov could not answer, so the LGU can see which
// facts to add next. Before this, nothing about a chat was kept anywhere, so
// "what do citizens ask that the bot doesn't know?" had no answer at all.
//
// The model flags a gap by ending its reply with [[KB_GAP]] (see the ACCURACY
// rules in index.ts). The marker is ALWAYS stripped here, before the reply
// leaves the function, whether or not the log write succeeds — a citizen must
// never see it, and the client sends replies back as history, so a leaked
// marker would also teach the model to repeat it.
//
// PRIVACY: only the question text is stored — no user id, no session, no
// report reference — and it is redacted first. Citizens type phone numbers,
// emails and ID numbers into chat; none of that is what we want to learn from.

/** Matches the marker however the model spaces or cases it. */
const GAP_MARKER = /\[\[\s*kb[_ ]?gap\s*\]\]/gi;

/** Longest question we keep. Enough to see the ask, not a life story. */
export const MAX_GAP_QUESTION_CHARS = 300;

/** Removes the marker and reports whether it was there. */
export function extractGapMarker(reply: string): { reply: string; gap: boolean } {
  const gap = GAP_MARKER.test(reply);
  GAP_MARKER.lastIndex = 0;
  return { reply: reply.replace(GAP_MARKER, "").trim(), gap };
}

/**
 * Blanks personal details out of a question before it is stored.
 *
 * Order matters: emails first (they contain digits and dots), then any run of
 * 7+ digits allowing the separators people type into PH phone and ID numbers
 * ("0917 123 4567", "1234-5678-9012"). Short numbers survive on purpose —
 * "Centro 3", "4Ps", "911" and "60 years old" are the question, not PII.
 */
export function redactQuestion(question: string): string {
  return (question ?? "")
    .replace(/[\r\n\t]+/g, " ")
    .replace(/[\p{L}\p{N}._%+-]+@[\p{L}\p{N}.-]+\.[\p{L}]{2,}/gu, "[email]")
    .replace(/\+?\d(?:[\s().-]*\d){6,}/g, "[number]")
    .replace(/\s{2,}/g, " ")
    .trim()
    .slice(0, MAX_GAP_QUESTION_CHARS);
}
