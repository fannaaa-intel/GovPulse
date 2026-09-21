import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Time-relative status of an event, derived from its date + free-text time
/// (e.g. "9:00 AM" or "9:00 AM - 12:00 PM"). Powers the countdown/"done" pill
/// on event cards and the auto-hide of long-past events.
///
/// The `event_time` column is free text, so the start/end are parsed
/// best-effort; anything unparseable degrades to an all-day event (date only).

enum EventPhase { upcoming, soon, live, done }

class EventTimeStatus {
  final EventPhase phase;
  final String label;
  const EventTimeStatus(this.phase, this.label);
}

// Matches "9", "9:30", "9 AM", "9:30 pm", "14:00" … first = start, second = end.
final RegExp _timeRe =
    RegExp(r'(\d{1,2})(?::(\d{2}))?\s*([AaPp][Mm])?');

List<Duration> _parseTimes(String raw) {
  final out = <Duration>[];
  for (final m in _timeRe.allMatches(raw)) {
    var h = int.tryParse(m.group(1) ?? '');
    if (h == null) continue;
    final min = int.tryParse(m.group(2) ?? '') ?? 0;
    final ap = m.group(3)?.toLowerCase();
    if (ap == 'pm' && h < 12) h += 12;
    if (ap == 'am' && h == 12) h = 0;
    if (h > 23 || min > 59) continue;
    out.add(Duration(hours: h, minutes: min));
    if (out.length == 2) break;
  }
  return out;
}

/// Start of the event as a full [DateTime]. Falls back to midnight of the day.
DateTime eventStartDateTime(DateTime date, String time) {
  final d = DateTime(date.year, date.month, date.day);
  final times = _parseTimes(time);
  return times.isEmpty ? d : d.add(times.first);
}

/// End of the event. Uses the second time in a range when present; otherwise
/// assumes a 2-hour block after the start, or end-of-day for an all-day event.
DateTime eventEndDateTime(DateTime date, String time) {
  final d = DateTime(date.year, date.month, date.day);
  final times = _parseTimes(time);
  if (times.isEmpty) {
    return d.add(const Duration(hours: 23, minutes: 59, seconds: 59));
  }
  final start = d.add(times.first);
  if (times.length >= 2) {
    var end = d.add(times[1]);
    if (!end.isAfter(start)) end = start.add(const Duration(hours: 2));
    return end;
  }
  return start.add(const Duration(hours: 2));
}

/// True once the event has been over for more than a day — used to auto-hide it
/// from the citizen list (mirrors the backend cron that deletes the row).
bool isEventExpired(DateTime date, String time, {DateTime? now}) {
  final n = now ?? DateTime.now();
  return n.isAfter(eventEndDateTime(date, time).add(const Duration(days: 1)));
}

EventTimeStatus computeEventTimeStatus(DateTime date, String time, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final start = eventStartDateTime(date, time);
  final end = eventEndDateTime(date, time);

  if (n.isBefore(start)) {
    final diff = start.difference(n);
    if (diff.inMinutes < 60) {
      return EventTimeStatus(EventPhase.soon,
          diff.inMinutes <= 1 ? 'Starting soon' : 'In ${diff.inMinutes} min');
    }
    if (diff.inHours < 24) {
      final h = diff.inHours;
      return EventTimeStatus(EventPhase.soon, 'In $h hr${h == 1 ? '' : 's'}');
    }
    // 24h+ → count in calendar days so "Tomorrow" reads naturally.
    final today = DateTime(n.year, n.month, n.day);
    final evDay = DateTime(start.year, start.month, start.day);
    final days = evDay.difference(today).inDays;
    return EventTimeStatus(
        EventPhase.upcoming, days == 1 ? 'Tomorrow' : 'In $days days');
  }

  if (!n.isAfter(end)) {
    return const EventTimeStatus(EventPhase.live, 'Happening now');
  }

  final diff = n.difference(end);
  if (diff.inMinutes < 60) {
    return EventTimeStatus(EventPhase.done,
        diff.inMinutes < 2 ? 'Just ended' : 'Done ${diff.inMinutes} min ago');
  }
  if (diff.inHours < 24) {
    final h = diff.inHours;
    return EventTimeStatus(EventPhase.done, 'Done $h hr${h == 1 ? '' : 's'} ago');
  }
  final d = diff.inDays;
  return EventTimeStatus(EventPhase.done, 'Done $d day${d == 1 ? '' : 's'} ago');
}

// ── Pill widget ────────────────────────────────────────────────────────────────

class EventStatusPill extends StatelessWidget {
  final DateTime eventDate;
  final String eventTime;
  final double fontSize;

  const EventStatusPill({
    super.key,
    required this.eventDate,
    required this.eventTime,
    this.fontSize = 11,
  });

  @override
  Widget build(BuildContext context) {
    final s = computeEventTimeStatus(eventDate, eventTime);
    final (Color color, IconData icon) = switch (s.phase) {
      EventPhase.upcoming => (AppColors.primaryBlue, Icons.schedule_rounded),
      EventPhase.soon => (AppColors.orange, Icons.hourglass_bottom_rounded),
      EventPhase.live => (AppColors.green, Icons.sensors_rounded),
      EventPhase.done => (const Color(0xFF6B7280), Icons.check_circle_rounded),
    };

    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: fontSize * 0.6, vertical: fontSize * 0.28),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(fontSize),
        border: Border.all(color: color.withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      // `MainAxisSize.min` makes this pill exactly as wide as its own content,
      // which is right — but on its own it also made the pill RIGID. The label
      // carried no maxLines and no Flexible, so a host Row could not shrink it
      // by even a pixel: beside a long category chip on a 320dp handset the
      // pair overflowed by a hairline at 1.0x and by 38px at Android's largest
      // font, and no amount of yielding on the CATEGORY's side could absorb it
      // once that chip hit its own floor.
      //
      // The icon stays fixed (it is the phase at a glance); the label is what
      // gives. Under a bounded parent it now ellipsizes instead of overflowing,
      // and because the Row is still `min`, an unbounded parent — the event
      // cards that place this pill on its own — is unaffected and the pill
      // keeps hugging its text exactly as before.
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: fontSize * 1.1, color: color),
          SizedBox(width: fontSize * 0.3),
          Flexible(
            child: Text(
              s.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
