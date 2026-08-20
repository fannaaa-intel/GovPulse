import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../services/events_service.dart';
import '../../../../theme/citizen_ui.dart';

/// Right-rail "Upcoming Events" list.
///
/// CITIZEN WEB ONLY — mounted by the shell's right sidebar.
///
/// Reads through [EventsService.instance.fetchEvents], the same call the Events
/// screen uses; there is no new query and no second source of truth. RLS already
/// limits citizens to approved events, and the service orders by `event_date`
/// ascending, so this only has to drop events that have already happened and
/// take the first few.
class HomeUpcomingEventsCard extends StatefulWidget {
  /// Opens the full Events surface. The shell passes its own quick-action
  /// dispatch, so "View All" goes through the same verification and restriction
  /// gates as the Events quick action itself.
  final VoidCallback onViewAll;

  /// How many events the rail shows before deferring to "View All".
  ///
  /// Two, not three: the rail also carries the quick actions and the download
  /// card, and a third event was pushing it past the height of a 1366x768
  /// browser. The rest are one "View All" away.
  final int maxItems;

  const HomeUpcomingEventsCard({
    super.key,
    required this.onViewAll,
    this.maxItems = 2,
  });

  @override
  State<HomeUpcomingEventsCard> createState() => _HomeUpcomingEventsCardState();
}

class _HomeUpcomingEventsCardState extends State<HomeUpcomingEventsCard> {
  late Future<List<EventModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadUpcoming();
  }

  Future<List<EventModel>> _loadUpcoming() async {
    final all = await EventsService.instance.fetchEvents();

    // Date-only comparison: an event happening later TODAY is still upcoming.
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);

    return all
        .where((e) => !e.eventDate.isBefore(startOfToday))
        .take(widget.maxItems)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: CitizenUi.surface,
        borderRadius: BorderRadius.circular(CitizenUi.cardRadius),
        border: Border.all(color: CitizenUi.border),
        boxShadow: CitizenUi.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Upcoming Events',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: CitizenUi.textPrimary,
                  ),
                ),
              ),
              InkWell(
                onTap: widget.onViewAll,
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    'View All',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: CitizenUi.accent,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<EventModel>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const _QuietLine('Loading events…');
              }
              // A rail is not the place to shout about a failed side-fetch; the
              // feed beside it owns the loud error state.
              if (snapshot.hasError) {
                return const _QuietLine("Couldn't load events");
              }
              final events = snapshot.data ?? const <EventModel>[];
              if (events.isEmpty) {
                return const _QuietLine('No upcoming events');
              }
              return Column(
                children: [
                  for (var i = 0; i < events.length; i++) ...[
                    if (i > 0) const SizedBox(height: 14),
                    _EventRow(event: events[i]),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Loading, empty and failure all read the same way here — one muted line. None
/// of the three is an error the citizen can act on from a rail.
class _QuietLine extends StatelessWidget {
  final String text;
  const _QuietLine(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12.5, color: CitizenUi.textFaint),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  final EventModel event;
  const _EventRow({required this.event});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Date chip
        Container(
          width: 42,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: CitizenUi.accentWash,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Text(
                DateFormat('MMM').format(event.eventDate).toUpperCase(),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .4,
                  color: CitizenUi.accent,
                ),
              ),
              Text(
                '${event.eventDate.day}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                  color: CitizenUi.accent,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                event.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                  color: CitizenUi.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              _meta(Icons.schedule_rounded, event.eventTime),
              const SizedBox(height: 2),
              _meta(Icons.place_rounded, event.location),
            ],
          ),
        ),
      ],
    );
  }

  Widget _meta(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 12, color: CitizenUi.textFaint),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, color: CitizenUi.textMuted),
          ),
        ),
      ],
    );
  }
}
