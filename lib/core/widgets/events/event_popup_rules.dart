// lib/core/widgets/events/event_popup_rules.dart
//
// The decision layer for the event slide-in card: given the events an LGU has
// published and what this citizen has already been shown, which single event —
// if any — earns a card on this app open?
//
// ── Why this file has no Flutter and no Supabase in it ───────────────────────
//
// Everything here is a pure function over plain data. That is deliberate: the
// rules below are where every real bug in this feature would otherwise hide —
// an off-by-one on the daily cap, a timezone slip that hides today's event, a
// re-show that nags a citizen who already said no. Those are cheap to test as
// functions and expensive to test through a widget tree and a live database.
//
// The widget layer (event_slide_in.dart) does the I/O and the animation and
// asks this file exactly one question: `pickEvent(...)`.
//
// ── The rules, in one place ──────────────────────────────────────────────────
//
//   * ELIGIBLE   = approved AND upcoming AND (featured OR posted since the
//                  citizen's last visit)
//   * RANKED     = featured first, then newest by created_at
//   * ONE SHOW   per event, ever — the rule that stops a week-old event
//                  re-popping every launch. The single exception is a
//                  transition to featured, which re-arms it once.
//   * TWO A DAY  at most, however many events are posted. The rest are not
//                  lost; they surface the next day if still upcoming.
//   * NEVER      an event the citizen swiped away, or one already opened.

import '../../services/events_service.dart';

// ─── Stored state ────────────────────────────────────────────────────────────

/// One event's history with one citizen, as persisted between launches.
///
/// [wasFeatured] is stored alongside the id rather than the id alone because
/// the re-arm fires on the TRANSITION into featured. Without the old value the
/// controller could not tell "the admin just promoted this" from "this was
/// always featured", and re-saving an already-featured event in the admin panel
/// would re-trigger a card for every citizen.
class EventShowRecord {
  /// The event this record is about.
  final String eventId;

  /// Whether the event was flagged featured at the moment it was shown.
  final bool wasFeatured;

  /// Local date the card appeared, truncated to midnight. Drives the daily cap.
  final DateTime shownOn;

  const EventShowRecord({
    required this.eventId,
    required this.wasFeatured,
    required this.shownOn,
  });

  /// Serialised as `id|featured|iso-date` — a single string per record so the
  /// whole history is one `setStringList`, which is the only prefs write shape
  /// that stays cheap as the list grows.
  String encode() =>
      '$eventId|${wasFeatured ? 1 : 0}|${shownOn.toIso8601String().substring(0, 10)}';

  /// Returns null for anything unparseable rather than throwing.
  ///
  /// A record is a convenience, never a source of truth: a corrupt entry (a
  /// half-written prefs file, a format change between app versions) must
  /// degrade to "we have not shown this yet", which shows one extra card at
  /// worst. Throwing here would break the whole check and show nothing, ever.
  static EventShowRecord? decode(String raw) {
    final parts = raw.split('|');
    if (parts.length != 3) return null;
    final date = DateTime.tryParse(parts[2]);
    if (date == null) return null;
    final id = parts[0];
    if (id.isEmpty) return null;
    return EventShowRecord(
      eventId: id,
      wasFeatured: parts[1] == '1',
      shownOn: DateTime(date.year, date.month, date.day),
    );
  }
}

/// Everything the rules need to know about this citizen, read from prefs.
class EventPopupState {
  /// Events that have been shown at least once, newest first is not required.
  final List<EventShowRecord> shown;

  /// Events the citizen swiped away or opened. Never offered again.
  final Set<String> dismissed;

  /// The newness watermark: events published after this are "new" to this
  /// citizen. Null on a first-ever launch.
  ///
  /// On a null watermark nothing counts as new — see [_isNewSince] — so a
  /// citizen's very first launch shows a featured event or nothing at all,
  /// rather than the entire back catalogue.
  ///
  /// ── Why this does NOT simply advance to "now" on every check ─────────────
  ///
  /// The obvious implementation — stamp `now` every time the check runs — has a
  /// bug that only shows up on a busy posting day. An event published at 5pm is
  /// new at 5:10pm, but if the daily cap held it back, a plain `now` watermark
  /// moves past it and the event is invisible FOREVER: never shown, no longer
  /// new, and not featured. The plan promises a capped event "is not lost, it
  /// surfaces tomorrow", and a naive watermark quietly breaks that promise.
  ///
  /// So the watermark only advances as far as the events actually dealt with —
  /// see [advanceWatermark]. Anything held back keeps its claim on being new.
  final DateTime? lastSeenAt;

  const EventPopupState({
    this.shown = const [],
    this.dismissed = const {},
    this.lastSeenAt,
  });
}

// ─── Tunables ────────────────────────────────────────────────────────────────

/// Most cards a citizen can see in one local day.
///
/// Two rather than one because a genuinely important second event should not
/// have to wait a full day; two rather than unlimited because an LGU that posts
/// five events on a Monday should not produce five popups. Events beyond the
/// cap are not consumed — they stay eligible and surface the next day.
const int kMaxCardsPerDay = 2;

// ─── Rules ───────────────────────────────────────────────────────────────────

/// Midnight on [t], in local time.
///
/// Every date comparison here is date-only. An event happening later TODAY is
/// still upcoming, and a card shown at 11pm and another at 1am are on different
/// days — both of which only work if the boundary is midnight rather than "24
/// hours ago".
DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

/// True when [e] has not finished yet, as of [now].
///
/// Uses the date floor, not the timestamp: an event dated today is upcoming all
/// day, because `event_date` carries no time-of-day and `event_time` is free
/// text ("6:00 AM", "whole day") that cannot be parsed reliably.
bool isUpcoming(EventModel e, DateTime now) =>
    !dayOf(e.eventDate).isBefore(dayOf(now));

/// True when [e] was published after the citizen last had this check run.
bool _isNewSince(EventModel e, DateTime? lastSeenAt) {
  if (lastSeenAt == null) return false;
  return e.createdAt.isAfter(lastSeenAt);
}

/// The record of [e] having been shown before, or null if it never has.
EventShowRecord? _recordFor(String eventId, List<EventShowRecord> shown) {
  for (final r in shown) {
    if (r.eventId == eventId) return r;
  }
  return null;
}

/// Whether this event may be offered at all, ignoring ranking and the daily cap.
///
/// Split out from [pickEvent] so each clause can be tested on its own, and so
/// the reason an event was skipped stays readable.
bool isEligible(EventModel e, EventPopupState state, DateTime now) {
  // Never anything the citizen has already acted on. Checked first: it is the
  // strongest signal we have and the cheapest test.
  if (state.dismissed.contains(e.id)) return false;

  // RLS already hides unapproved events from citizens, so in production this is
  // belt-and-braces — but the rules must be correct on their own, because they
  // are also fed by tests and could one day be fed by an admin preview.
  if (e.status != EventStatus.approved) return false;

  if (!isUpcoming(e, now)) return false;

  final seen = _recordFor(e.id, state.shown);
  if (seen == null) {
    // Never shown: featured, or new since the last visit.
    return e.isFeatured || _isNewSince(e, state.lastSeenAt);
  }

  // Shown before. The ONLY way back is an admin promoting it to featured after
  // the fact — a fresh editorial decision, worth exactly one more appearance.
  // Note this is a transition test, not a state test: an event that was already
  // featured when shown does not re-arm, no matter how often it is re-saved.
  return e.isFeatured && !seen.wasFeatured;
}

/// Orders eligible events best-first: featured ahead of merely new, then newest.
///
/// Exposed for tests; [pickEvent] applies it internally.
int compareCandidates(EventModel a, EventModel b) {
  if (a.isFeatured != b.isFeatured) return a.isFeatured ? -1 : 1;
  return b.createdAt.compareTo(a.createdAt);
}

/// How many cards have already been shown on [now]'s local date.
int cardsShownToday(EventPopupState state, DateTime now) {
  final today = dayOf(now);
  var count = 0;
  for (final r in state.shown) {
    if (r.shownOn == today) count++;
  }
  return count;
}

/// The single event that should slide in on this app open, or null for silence.
///
/// [events] is whatever the query returned — order does not matter, and past or
/// ineligible rows are filtered here rather than being the caller's problem.
///
/// Returns null when nothing qualifies, which is the common case and is not an
/// error: a quiet week produces no cards at all.
EventModel? pickEvent(
  List<EventModel> events,
  EventPopupState state,
  DateTime now,
) {
  // The daily cap is checked before any per-event work: once it is reached
  // nothing can show, and the cheapest correct answer is to stop here. Events
  // are NOT consumed by this — they stay eligible for tomorrow.
  if (cardsShownToday(state, now) >= kMaxCardsPerDay) return null;

  final candidates = events.where((e) => isEligible(e, state, now)).toList()
    ..sort(compareCandidates);

  return candidates.isEmpty ? null : candidates.first;
}

/// The watermark to persist after a check that considered [events].
///
/// This is deliberately NOT `now`. The watermark may only move past events the
/// citizen has actually been dealt: anything still eligible — held back by the
/// daily cap, or outranked by a better card — must stay "new" so it can surface
/// on a later launch. Advancing to `now` would silently lose it.
///
/// [shownNow] is the event that just slid in, or null if nothing did.
///
/// The rule: advance to the newest `created_at` among events that are no longer
/// waiting for a turn — the one just shown, plus everything already handled.
/// If anything eligible remains unshown, the watermark stops just before the
/// oldest of those, preserving its newness.
DateTime? advanceWatermark(
  List<EventModel> events,
  EventPopupState state,
  DateTime now, {
  EventModel? shownNow,
}) {
  // Events still waiting for a turn: eligible, and not the one just shown.
  final pending = events
      .where((e) => isEligible(e, state, now) && e.id != shownNow?.id)
      .toList();

  if (pending.isEmpty) {
    // Nothing is waiting, so the watermark can safely catch up to the present.
    return now;
  }

  // Something is still waiting. Hold the watermark just before the OLDEST
  // pending event so it still reads as new next time. One millisecond is
  // enough: `_isNewSince` is a strict `isAfter`.
  var oldest = pending.first.createdAt;
  for (final e in pending) {
    if (e.createdAt.isBefore(oldest)) oldest = e.createdAt;
  }
  final held = oldest.subtract(const Duration(milliseconds: 1));

  // Never move the watermark BACKWARDS — a citizen who has already seen later
  // events should not have them become new again.
  final current = state.lastSeenAt;
  if (current != null && held.isBefore(current)) return current;
  return held;
}

// ─── Housekeeping ────────────────────────────────────────────────────────────

/// Drops records for events that can never be offered again.
///
/// Without this the stored lists grow for the life of the install: every event
/// a citizen has ever seen or swiped stays in prefs forever. An event whose date
/// has passed can never be picked again ([isUpcoming] fails), so its history
/// has nothing left to protect.
///
/// [knownEventIds] is the set of ids the current query returned. Ids outside it
/// are kept unless they are also older than [retention], because a single query
/// is a window on the table, not the whole of it — dropping everything absent
/// from one page would forget dismissals for events that simply were not in it.
List<EventShowRecord> pruneShown(
  List<EventShowRecord> shown,
  DateTime now, {
  Duration retention = const Duration(days: 60),
}) {
  final floor = dayOf(now.subtract(retention));
  return shown.where((r) => !r.shownOn.isBefore(floor)).toList();
}

/// The dismissed set, minus ids that have aged out.
///
/// Mirrors [pruneShown]'s reasoning. A dismissal only has to outlive the event
/// it refers to; [retention] is generous because the cost of keeping one extra
/// id is a few bytes, while the cost of forgetting one too early is a card the
/// citizen already refused.
Set<String> pruneDismissed(
  Set<String> dismissed,
  List<EventModel> knownEvents,
  DateTime now, {
  Duration retention = const Duration(days: 60),
}) {
  final floor = dayOf(now.subtract(retention));

  // Ids we can still see in the data: keep if the event has not aged out.
  final byId = {for (final e in knownEvents) e.id: e};

  return dismissed.where((id) {
    final e = byId[id];
    if (e == null) return true; // not in this window — keep, cannot judge it
    return !dayOf(e.eventDate).isBefore(floor);
  }).toSet();
}
