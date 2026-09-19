// Dev-only harness for the STANDALONE GUEST FEED at four browser widths.
//
//   flutter run -d web-server --web-port 57812 -t tool/preview_guest_feed.dart
//
// Why this exists: every web branch in the feed sits behind `kIsWeb`, which is
// a compile-time false under the VM, so `flutter test` cannot reach any of it.
// The guest arm in particular had no preview target and no widget test, which
// is how it drifted out of step with the citizen shell.
//
// EVERY frame here is `embedded: false` — that is the whole point. The guest
// reaches the feed as a top-level route with no shell around it, so the layout
// is chosen by the VIEWPORT (`kIsWeb && rawWidth >= 900`) rather than by the
// column the shell hands it. The existing preview_newsfeed_edge_to_edge.dart
// covers the embedded arm; this one covers the arm a guest actually gets.
//
// The four widths, and what each is meant to prove:
//
//   • 420  — phone browser. Mobile arm, full bleed. Correct today.
//   • 700  — THE REGRESSION. Below the 900 gate, so a guest falls into the
//            mobile arm and gets a stranded 480px column in a 700px window,
//            with the phone logo bar on top. A signed-in citizen at this same
//            width gets the proper web body, because the shell passes
//            embedded: true and skips the viewport test entirely.
//   • 900  — web body, first width that reaches it. Rail is DROPPED here: the
//            content box is 900-48=852, under kFeedRailBelow (1012).
//   • 1440 — web body with the rail. This is where the rail's copy is visible,
//            and it is the only band that ever sees it.
//
// Nothing signs in, so this reads as a real anonymous guest against live data —
// which is exactly the case under test, since community posts are readable by
// anon.

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
            // The standalone feed reads `MediaQuery.size.width` directly to
            // choose its arm, so the frame — not the browser window — decides
            // which branch builds. Same override the shell does for its centre
            // column.
            data: MediaQuery.of(context).copyWith(
              size: Size(width, height),
              padding: EdgeInsets.zero,
              viewPadding: EdgeInsets.zero,
              viewInsets: EdgeInsets.zero,
            ),
            child: Scaffold(
              backgroundColor: CitizenUi.pageBg,
              // embedded: false on every frame — the guest route has no shell.
              body: const NewsFeedBody(embedded: false, isGuest: true),
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
      title: 'GovPulse — guest feed (standalone)',
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
                label: 'guest 420 · mobile arm · full bleed (ok today)',
                width: 420,
                height: 900,
              ),
              SizedBox(width: 28),
              _Frame(
                label: 'guest 700 · REGRESSION · stranded 480 column',
                width: 700,
                height: 900,
              ),
              SizedBox(width: 28),
              _Frame(
                label: 'guest 900 · web body · no rail',
                width: 900,
                height: 900,
              ),
              SizedBox(width: 28),
              _Frame(
                label: 'guest 1440 · web body · WITH rail',
                width: 1440,
                height: 900,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
