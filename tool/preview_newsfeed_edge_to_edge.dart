// Dev-only harness for the FEED POST SLAB at three column widths.
//
//   flutter run -d web-server --web-port 57811 -t tool/preview_newsfeed_edge_to_edge.dart
//
// What it is for: the post card now has two shapes — the floating rounded card
// it has always had, and a full-bleed slab (no side margin, squared corners,
// top/bottom hairline, full-bleed media) for phone-width columns. Both shapes
// and the switch between them are laid out from `MediaQuery.size` and from a
// `LayoutBuilder` on the feed column, so the only way to check them is to put
// the three interesting widths next to each other:
//
//   • 390  — phone. Mobile branch of the feed, full bleed. This is also the
//            widget tree the ANDROID/iOS app builds: the mobile arm is chosen
//            by width, not by `kIsWeb`, and the only kIsWeb difference inside
//            the card is CitizenUi.sharedBorder's exact grey.
//   • 584  — phone browser in the shell (embedded), full bleed.
//   • 900  — roomy shell column, embedded. MUST still be the rounded card:
//            this frame is the regression check, not the feature.
//
// Nothing signs in, so the feed reads as an anonymous guest — which is fine,
// the community posts are readable by anon (that is what the guest feed is).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:govpulse/core/theme/citizen_ui.dart';
import 'package:govpulse/features/home/newsfeed/news_feed_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://vxvflhjbafqwehuxnmeq.supabase.co',
    anonKey: 'sb_publishable_ZBDaQPQdFyC5kOHGbce9Ig_zdtIi6Mo',
  );
  runApp(const ProviderScope(child: _PreviewApp()));
}

class _Frame extends StatelessWidget {
  final String label;
  final double width;
  final double height;
  final bool embedded;

  const _Frame({
    required this.label,
    required this.width,
    required this.height,
    required this.embedded,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        SizedBox(
          width: width,
          height: height,
          child: MediaQuery(
            // The feed sizes itself off MediaQuery — same override the shell
            // does for its centre column — so the frame, not the browser
            // window, decides which arm it builds.
            data: MediaQuery.of(context).copyWith(
              size: Size(width, height),
              padding: EdgeInsets.zero,
              viewPadding: EdgeInsets.zero,
              viewInsets: EdgeInsets.zero,
            ),
            child: Scaffold(
              backgroundColor: CitizenUi.pageBg,
              body: NewsFeedBody(embedded: embedded, isGuest: true),
            ),
          ),
        ),
      ],
    );
  }
}

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'GovPulse feed — full-bleed post slab',
      theme: ThemeData(useMaterial3: true, fontFamily: 'Roboto'),
      home: Scaffold(
        backgroundColor: const Color(0xFF111827),
        body: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              _Frame(
                label: 'phone 390 · mobile arm · full bleed',
                width: 390,
                height: 844,
                embedded: false,
              ),
              SizedBox(width: 28),
              _Frame(
                label: 'shell 584 · embedded · full bleed',
                width: 584,
                height: 844,
                embedded: true,
              ),
              SizedBox(width: 28),
              _Frame(
                label: 'shell 900 · embedded · CARD (unchanged)',
                width: 900,
                height: 844,
                embedded: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
