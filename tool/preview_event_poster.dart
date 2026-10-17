// Dev-only harness for the tappable event poster + its full-screen preview.
//
//   flutter build web --release -t tool/preview_event_poster.dart
//
// Why a preview target at all: 2349 widget tests and `flutter analyze` both
// pass on a page that cannot render, and they cannot answer the questions this
// change is actually about — whether the expand badge reads as "tap me" at
// 148px, whether it collides with the artwork, and whether the opened viewer
// letterboxes a tall poster instead of cropping it.
//
// The real EventDetailScreen IS driven here (unlike the events LIST, whose
// EventsService fetch needs Supabase): it takes its EventItem by constructor,
// so a poster can be handed straight in. The image is a local asset served by
// the same build, so there is no network dependency.
import 'package:flutter/material.dart';

import 'package:govpulse/features/home/Quick-action/Events/event_detail_screen.dart';
import 'package:govpulse/features/home/Quick-action/Events/events_screen.dart';

void main() => runApp(const _PreviewApp());

/// A tall poster, which is the shape that matters: `BoxFit.cover` in the
/// thumbnail crops it hard, and the viewer must show all of it.
const _poster =
    'https://images.unsplash.com/photo-1540575467063-178a50c2df87?w=1200';

EventItem _event() => EventItem(
  id: 'e1',
  title: 'DOLE Cagayan Valley Serbisyo Caravan and Job Fair',
  location: 'Aparri Municipal Plaza, Cagayan',
  date: 'Sep 20, 2026',
  time: '8:00 AM - 5:00 PM',
  category: 'Health',
  categoryColor: const Color(0xFF22C55E),
  eventDate: DateTime(2026, 9, 20),
  description:
      'Bringing government services closer to the community with free '
      'medical check-ups, job placement and document assistance.',
  whatToExpect: 'Free medical check-up\nJob placement assistance\nPhilID '
      'registration',
  requirements: 'Valid ID\nBarangay clearance',
  imageUrl: _poster,
);

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF111827),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Wrap(
              spacing: 24,
              runSpacing: 24,
              children: [
                // The widths that bracket the real surfaces: smallest handset,
                // a modern phone, and the web centre column.
                _Frame(label: 'small phone 320', width: 320, height: 640),
                _Frame(label: 'modern phone 390', width: 390, height: 760),
                _Frame(label: 'web column 680', width: 680, height: 760),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One device-sized window onto the real screen.
class _Frame extends StatelessWidget {
  final String label;
  final double width;
  final double height;
  const _Frame({
    required this.label,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white24),
          ),
          // MediaQuery is overridden so the screen's `uiScaleWidth` reads this
          // frame's width rather than the browser window's — otherwise every
          // frame renders at one size and the sweep proves nothing.
          child: MediaQuery(
            data: MediaQueryData(size: Size(width, height)),
            child: EventDetailScreen(event: _event(), username: 'juan'),
          ),
        ),
      ],
    );
  }
}
