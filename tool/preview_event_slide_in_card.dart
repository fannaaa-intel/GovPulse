// Dev-only harness for the event slide-in card.
//
//   flutter build web --release -t tool/preview_event_slide_in_card.dart
//
// The card itself is a plain StatelessWidget over an EventModel, so unlike most
// of this app it can be rendered without Supabase, a navigator or a session —
// which is what makes it viewable at all. The controller (event_slide_in.dart)
// is NOT driven here: it needs a real session, a root overlay and a route
// observer, none of which exist in a preview.
//
// Why this exists rather than a golden test: goldens in the Flutter test
// environment render with no real font and no image decoding, so the card comes
// out as a grey slab. A web build draws it with actual type, actual colours and
// actual layout — the only way to LOOK at this widget in this environment.
//
// What is worth looking at here:
//   * does the card read as one object, or as a thumbnail beside some text?
//   * is the badge legible at its real size, or is it noise?
//   * does the category rail do anything, or is it decoration?
//   * does a long Tagalog title ellipsise gracefully or look truncated?
//   * do the five category colours all survive on white?

import 'package:flutter/material.dart';

import 'package:govpulse/core/services/events_service.dart';
import 'package:govpulse/core/widgets/events/event_slide_in_card.dart';

void main() => runApp(const _PreviewApp());

EventModel _event({
  required String title,
  required String location,
  String time = '6:00 AM',
  bool featured = false,
  String color = '#14B8A6',
  DateTime? date,
  String? imageUrl,
}) => EventModel(
  id: title,
  title: title,
  location: location,
  eventDate: date ?? DateTime(2026, 9, 14),
  eventTime: time,
  category: 'Environment',
  categoryColor: color,
  isFeatured: featured,
  imageUrl: imageUrl,
  status: EventStatus.approved,
  createdBy: 'admin',
  createdAt: DateTime(2026, 9, 1),
);

/// The card as the overlay host actually paints it: the real Home ground
/// colour behind it, and the two-layer shadow the host wraps it in.
///
/// Without the shadow the card reads as pasted onto the page rather than
/// floating above it, which is most of what the design is doing.
class _Floating extends StatelessWidget {
  final EventModel event;
  final double? dwell;
  final double width;

  const _Floating({
    required this.event,
    this.dwell,
    this.width = 390,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      color: const Color(0xFFF3F6FC),
      alignment: Alignment.centerRight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 30,
              offset: Offset(0, 12),
              spreadRadius: -10,
            ),
          ],
        ),
        child: EventSlideInCard(
          event: event,
          onTap: () {},
          dwellRemaining: dwell,
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  final String? note;
  const _Label(this.text, {this.note});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 7, top: 2),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF131820),
            letterSpacing: 0.2,
          ),
        ),
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              note!,
              style: const TextStyle(fontSize: 11, color: Color(0xFF6B7688)),
            ),
          ),
      ],
    ),
  );
}

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFEFF1F5),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Event slide-in card',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF131820),
                ),
              ),
              const SizedBox(height: 3),
              const Text(
                'The real EventSlideInCard widget, on the real Home ground '
                'colour, inside the shadow the overlay host paints.',
                style: TextStyle(fontSize: 12.5, color: Color(0xFF414B5A)),
              ),
              const SizedBox(height: 22),

              Wrap(
                spacing: 30,
                runSpacing: 24,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _Label(
                        'FEATURED, dwell running',
                        note: 'the ordinary case, mid-countdown',
                      ),
                      _Floating(
                        event: _event(
                          title: 'Barangay Clean-Up Drive',
                          location: 'Riverside Park',
                          featured: true,
                        ),
                        dwell: 0.62,
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _Label(
                        'NEW, no dwell bar',
                        note: 'paused, or a finger is down',
                      ),
                      _Floating(
                        event: _event(
                          title: 'Free Medical Check-Up',
                          location: 'Barangay Hall',
                          time: '8:00 AM',
                          color: '#22C55E',
                          date: DateTime(2026, 9, 19),
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _Label(
                        'A long Tagalog title',
                        note: 'the case that would break a wrapping card',
                      ),
                      _Floating(
                        event: _event(
                          title:
                              'Libreng Tuli at Medical Mission para sa mga '
                              'Kabataan ng Barangay San Isidro',
                          location:
                              'Barangay San Isidro Multi-Purpose Covered '
                              'Court, Poblacion District',
                          time: '6:00 AM to 4:00 PM',
                          color: '#2563EB',
                        ),
                        dwell: 0.35,
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 30),
              const _Label(
                'Every category colour',
                note: 'the rail and the date block both take category_color',
              ),
              Wrap(
                spacing: 26,
                runSpacing: 14,
                children: [
                  for (final e in const [
                    ('Health', '#22C55E', 11),
                    ('Training', '#2563EB', 12),
                    ('Environment', '#14B8A6', 13),
                    ('Special', '#F59E0B', 14),
                    ('Others', '#64748B', 15),
                  ])
                    _Floating(
                      width: 360,
                      event: _event(
                        title: '${e.$1} Outreach Program',
                        location: 'Barangay Covered Court',
                        color: e.$2,
                        date: DateTime(2026, 9, e.$3),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 30),
              const _Label(
                'Across handset widths',
                note: 'the card clamps between 240 and 300dp',
              ),
              Wrap(
                spacing: 26,
                runSpacing: 14,
                crossAxisAlignment: WrapCrossAlignment.start,
                children: [
                  for (final w in const [320.0, 360.0, 390.0, 430.0])
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Text(
                            '${w.toInt()}dp',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF6B7688),
                            ),
                          ),
                        ),
                        // MediaQuery is what EventSlideInCard.widthFor reads,
                        // so overriding it here is what makes each column a
                        // genuine simulation of that handset rather than the
                        // same card drawn four times.
                        MediaQuery(
                          data: MediaQueryData(size: Size(w, 800)),
                          child: _Floating(
                            width: w,
                            event: _event(
                              title: 'Barangay Clean-Up Drive',
                              location: 'Riverside Park',
                              featured: true,
                            ),
                            dwell: 0.5,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
