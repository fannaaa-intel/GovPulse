// Dev-only harness for the CITIZEN WEB top-nav BRAND LOCKUP.
//
// Not part of the app: nothing under lib/ imports it, and it is never a build
// target for a shipped bundle.
//
//   flutter build web --release -t tool/preview_top_nav_brand.dart
//   python -m http.server 57812 --directory build/web
//
// ── Why this exists ────────────────────────────────────────────────────────
// `_BrandLogo` picks its mark height off `MediaQuery.sizeOf(context).width`
// AND sits behind `kIsWeb`, which is a compile-time false under the VM — so
// `flutter test` can never reach the branch this is checking. The nav itself
// needs no Supabase (every value it draws is a plain constructor argument), so
// unlike the other preview targets this one fakes nothing: it just mounts the
// real `HomeTopNav` once per width step.
//
// ── What to look at ────────────────────────────────────────────────────────
// One pane per step of `_brandMetrics`, each under its own MediaQuery width
// override — the mark must grow 28 → 32 → 36 → 40 → 44 down the page, stay on
// the wordmark's optical centre at every step, and never collide with the nav
// links or crowd the 60px bar.

import 'package:flutter/material.dart';

import 'package:govpulse/core/widgets/Home/nav/home_top_nav.dart';

void main() => runApp(const _PreviewApp());

/// The width steps `_brandMetrics` switches on, plus one just under each line
/// so a step that fires on the wrong side of a boundary is visible.
const List<int> _kWidths = [1920, 1440, 1439, 1200, 1199, 900, 899, 700, 599];

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFE9EDF5),
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final w in _kWidths) _Pane(width: w.toDouble()),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

/// One nav bar rendered at [width], with the MediaQuery it reads overridden to
/// match — the same trick citizen_shell uses for its centre column, and what
/// lets every step be shot in a single page instead of nine resizes.
class _Pane extends StatelessWidget {
  final double width;
  const _Pane({required this.width});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${width.toInt()}px',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: width,
            child: MediaQuery(
              data: mq.copyWith(size: Size(width, mq.size.height)),
              child: HomeTopNav(
                currentIndex: 0,
                onTap: (_) {},
                onNotificationTap: () {},
                onLogoutTap: () {},
                notificationCount: 3,
                username: 'mark',
                fullName: 'Mark Reduca',
                facePhotoUrl: null,
                verifStatus: 'approved',
                // The citizen shell's set, and its narrow-width chip collapse,
                // so the panes below 600 show what the shell actually draws.
                items: const [
                  (label: 'Home', index: 0),
                  (label: 'My Reports', index: 1),
                  (label: 'Emergency', index: 2),
                ],
                settingsIndex: 3,
                avatarOnlyChip: width < 600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
