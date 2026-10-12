// The wire format for Kuya Gov's routing tags. Split out of index.ts so the
// test can import it without starting serve().
//
// Guarantees: at most ONE recognized tag, placed cleanly on line 1, with the
// message body following. Strips any stray/duplicate tags from the body so a
// tag can never leak into visible text.
//
// AGENT is retired (v8). If the model emits it anyway, the WHOLE reply is
// replaced with NO_LIVE_STAFF_REPLY — its own body is likely the old
// "connecting you to staff" script, and an app build from before the revision
// would turn the tag itself into a ticket insert the database now refuses.
export const NO_LIVE_STAFF_REPLY =
  "Pasensya na po — walang live chat sa staff dito sa GovPulse. 🙏\n\n" +
  "Para maaksyunan ng tamang opisina, gamitin po ang Quick Actions sa Home:\n" +
  "• Report Issue — para sa problema o reklamo\n" +
  "• Suggestion — para sa mungkahi\n" +
  "• Feedback — para sa serbisyo ng opisina\n\n" +
  "Kung emergency po, tawagan ang hotlines sa Emergency section. " +
  "May iba pa po ba kayong tanong?";

export function normalizeActionTag(raw: string): string {
  const tagRe = /\[ACTION:(REPORT|AGENT|END)\]/gi;
  const matches = [...raw.matchAll(tagRe)];
  const body = raw.replace(tagRe, "").trim();
  if (matches.length === 0) return body;
  const action = matches[0][1].toUpperCase(); // first tag wins
  if (action === "AGENT") return NO_LIVE_STAFF_REPLY;
  return body.length > 0 ? `[ACTION:${action}]\n${body}` : `[ACTION:${action}]`;
}
