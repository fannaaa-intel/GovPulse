// Dev-only harness for the ADMIN → Citizens toolbar.
//
// Not part of the app: nothing under lib/ imports it, and it is never a build
// target for a shipped bundle.
//
//   flutter build web --release -t tool/preview_admin_users_toolbar.dart
//   python -m http.server 57816 --directory build/web
//
// ── Why this exists ────────────────────────────────────────────────────────
// The Citizens page is behind a login and a role gate, and the toolbar's fault
// only shows below the 720px breakpoint — a phone-width browser window or the
// mobile app. This mounts the page at a set of widths so the pill row can be
// checked on both sides of that line without signing in.
//
// ── What to look at ────────────────────────────────────────────────────────
//  * Below 720: the three pills are a two-column grid. Equal widths, aligned
//    left and right edges, the odd third directly under the first. Before this
//    they were a Wrap, so the first two shared a row at their own natural
//    widths and "Sort by: Newest" fell to a second row - three controls
//    staggered across two rows with a ragged right edge.
//  * At or above 720: unchanged. Search left, the three pills hugging their
//    labels on the right.
//  * 360 is the tightest phone worth supporting: "Sort by: Newest" must still
//    read without clipping in a half-width slot.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:govpulse/features/admin/pages/admin_users_page.dart';
import 'package:govpulse/features/admin/theme/admin_ui.dart';

void main() => runApp(const ProviderScope(child: _PreviewApp()));

class _PreviewApp extends StatefulWidget {
  const _PreviewApp();
  @override
  State<_PreviewApp> createState() => _PreviewAppState();
}

class _PreviewAppState extends State<_PreviewApp> {
  // 360/420 are phones, 700 is just under the breakpoint, 900/1280 are over it.
  double _width = 390;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF1F2937),
        body: Column(
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final w in const [360.0, 390.0, 420.0, 700.0, 900.0])
                      FilledButton(
                        onPressed: () => setState(() => _width = w),
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              _width == w ? Colors.white : Colors.white24,
                          foregroundColor:
                              _width == w ? Colors.black : Colors.white,
                        ),
                        child: Text('${w.toInt()} px'),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: SizedBox(
                  width: _width,
                  child: ClipRect(
                    child: Builder(
                      builder: (outer) {
                        final mq = MediaQuery.of(outer);
                        return MediaQuery(
                          data: mq.copyWith(
                            size: Size(_width, mq.size.height - 70),
                          ),
                          child: Container(
                            color: AdminUi.pageBg,
                            child: const AdminUsersPage(),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
