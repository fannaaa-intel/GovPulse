// supabase/functions/_shared/groq.ts
//
// Shared Groq chat-completions caller for the classify-* / recommend-actions
// functions. Retries on 429 (free-tier rate limits) and transient 5xx with a
// short backoff, honouring Retry-After when Groq sends one — without this a
// backfill batch silently drops every row that lands on a rate-limit window.
//
// Returns the assistant message content, or null after the final failure
// (callers already treat null as "classification failed, keep the row queued").

export async function groqChat(
  apiKey: string,
  body: Record<string, unknown>,
  { retries = 2 }: { retries?: number } = {},
): Promise<string | null> {
  for (let attempt = 0; ; attempt++) {
    let res: Response;
    try {
      res = await fetch("https://api.groq.com/openai/v1/chat/completions", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${apiKey}`,
        },
        body: JSON.stringify(body),
      });
    } catch (e) {
      // Network-level failure — retry like a 5xx.
      if (attempt >= retries) {
        console.error("Groq fetch failed:", e);
        return null;
      }
      await new Promise((r) => setTimeout(r, 1000 * Math.pow(3, attempt)));
      continue;
    }

    if (res.ok) {
      const data = await res.json();
      return String(data.choices?.[0]?.message?.content ?? "");
    }

    const text = await res.text();
    const retryable = res.status === 429 || res.status >= 500;
    if (!retryable || attempt >= retries) {
      console.error("Groq error", res.status, text);
      return null;
    }
    const retryAfter = Number(res.headers.get("retry-after"));
    const delayMs = Number.isFinite(retryAfter) && retryAfter > 0
      ? Math.min(retryAfter * 1000, 15000)
      : 1000 * Math.pow(3, attempt); // 1s, 3s
    await new Promise((r) => setTimeout(r, delayMs));
  }
}
