import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:govpulse/features/landing/landing_page.dart';

// ════════════════════════════════════════════════════════════════════════════
//  The landing page survives EVERY size class, scrolled end to end.
//
//  ── Why this is separate from landing_page_render_test ─────────────────────
//  That file pumps a handful of widths and checks the first frame. This one
//  sweeps thirteen real device widths AND scrolls each one through the whole
//  page, because a section can lay out perfectly at first paint and overflow
//  only once it is actually reached.
//
//  ── The bug it caught ──────────────────────────────────────────────────────
//  The Features ring wrapped its two text columns in an IntrinsicHeight, which
//  imposes the tallest child's height on every child. The tallest child was the
//  fixed-width device stack — SHORTER than the columns once their copy wrapped
//  — so both columns overflowed the bottom by 60-90px at every desktop and
//  laptop width from 1180 up.
//
//  Every phone and tablet passed, because below 1180 the section uses a grid
//  instead of the ring. Checking "does it work on mobile" would have proved the
//  layout sound while it was broken on every machine an LGU officer owns.
// ════════════════════════════════════════════════════════════════════════════

Widget _host() => MaterialApp.router(
  routerConfig: GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const LandingPage()),
      GoRoute(path: '/login', builder: (_, _) => const SizedBox()),
      GoRoute(path: '/signup', builder: (_, _) => const SizedBox()),
      GoRoute(path: '/guest', builder: (_, _) => const SizedBox()),
      GoRoute(path: '/about', builder: (_, _) => const SizedBox()),
      GoRoute(path: '/privacy_policy', builder: (_, _) => const SizedBox()),
      GoRoute(path: '/terms_of_service', builder: (_, _) => const SizedBox()),
    ],
  ),
);

void main() {
  const sizes = <String, Size>{
    'ultrawide 2560': Size(2560, 1440),
    'large desktop 1920': Size(1920, 1080),
    'desktop 1440': Size(1440, 900),
    'laptop 1280': Size(1280, 800),
    'laptop 1180': Size(1180, 800),
    'tablet land 1024': Size(1024, 768),
    'tablet port 834': Size(834, 1112),
    'tablet small 768': Size(768, 1024),
    'phone large 430': Size(430, 932),
    'phone 414': Size(414, 896),
    'phone 390': Size(390, 844),
    'phone small 360': Size(360, 740),
    'phone tiny 320': Size(320, 568),
  };
  sizes.forEach((label, size) {
    testWidgets(label, (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host());
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(
        tester.takeException(),
        isNull,
        reason: 'paint at ${size.width.toInt()}',
      );
      // Scroll the whole page at this width — a section only breaks once laid out.
      final sc = find.byType(Scrollable).first;
      for (var i = 0; i < 16; i++) {
        await tester.drag(sc, const Offset(0, -700));
        await tester.pump();
        expect(
          tester.takeException(),
          isNull,
          reason: '${size.width.toInt()} threw at scroll step $i',
        );
      }
    });
  });
}
