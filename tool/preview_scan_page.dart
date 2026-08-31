// Preview target for the public /scan/<token> endorsement page.
//
// The real page needs a live token, and its whole point is a layout nobody can
// see without one. This boots ScanPage against a MOCK HTTP CLIENT handed to
// Supabase, so all four lifecycle states (endorsed / received / completed /
// withdrawn) can be looked at without touching the database.
//
// A mock client rather than a local HTTP server on purpose: dart:io does not
// exist on the web build, and web is the only target that renders here.
//
// Run:
//   flutter run -d web-server --web-port 57820 -t tool/preview_scan_page.dart
//
// Query parameters:
//   ?state=endorsed|received|completed|withdrawn   which lifecycle state
//   &delay=3000                                    ms before the RPC answers,
//                                                  so the SKELETON is visible
//                                                  (it is otherwise gone in one
//                                                  frame and cannot be looked at)
//   &w=320                                         clamp the viewport width, to
//                                                  check the page holds together
//                                                  on a small phone without
//                                                  resizing the browser
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:govpulse/features/scan/scan_page.dart';

/// Answers the two RPCs this page calls. `scan_endorsement` returns a report in
/// [state]; the write RPCs return a wrong-PIN error, so the error path and the
/// attempts-remaining copy are previewable too.
class _MockApi extends http.BaseClient {
  final String state;

  /// Held before answering, so the loading state can actually be looked at.
  /// Without it the mock resolves in the same frame the page mounts and the
  /// skeleton is unobservable — which is how a bare spinner survived here.
  final Duration delay;

  _MockApi(this.state, {this.delay = Duration.zero});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final path = request.url.path;
    final Object body;

    if (path.endsWith('/scan_endorsement')) {
      body = {
        'valid': true,
        'reference': 'END-3F2A1B6C',
        'agency': 'DPWH',
        'reason': 'The affected carriageway forms part of the Maharlika '
            'Highway, a national road under DPWH jurisdiction, and is outside '
            'the maintenance authority of this Municipality.',
        'state': state,
        'endorsed_at': '2026-08-29T08:54:00Z',
        'received_at': state == 'endorsed' ? null : '2026-08-29T10:12:00Z',
        'completed_at': state == 'completed' ? '2026-08-30T14:03:00Z' : null,
        'locked': false,
        'report': {
          'category': 'Road & Infrastructure',
          'barangay': 'Macanaya (Pescaria)',
          'address': 'Near Lyceum of Aparri',
          'description':
              'Large pothole across both lanes of the national road.',
          'reported_at': '2026-08-29T08:54:00Z',
        },
      };
    } else {
      body = {'ok': false, 'error': 'bad_pin', 'attempts_left': 3};
    }

    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      200,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final q = Uri.base.queryParameters;
  final state = q['state'] ?? 'endorsed';
  final delayMs = int.tryParse(q['delay'] ?? '') ?? 0;
  final width = double.tryParse(q['w'] ?? '');

  await Supabase.initialize(
    url: 'https://preview.invalid',
    anonKey: 'preview-not-a-real-key',
    httpClient: _MockApi(state, delay: Duration(milliseconds: delayMs)),
    authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
    debug: false,
  );

  const page = ScanPage(token: 'preview-token');

  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: width == null
          ? page
          // A hard viewport clamp rather than a browser resize: the narrow end
          // (320px) is where this page's fixed widths — the tracker labels, the
          // 116px detail column, the letter-spaced PIN field — either fit or
          // overflow, and dragging a window to exactly 320 by hand is not a
          // repeatable check.
          : Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: width,
                child: MediaQuery(
                  data: MediaQueryData(size: Size(width, 900)),
                  child: const _Ruler(child: page),
                ),
              ),
            ),
    ),
  );
}

/// Draws a hairline border round the clamped viewport so an overflow past its
/// edge is visible rather than merely being clipped by the window.
class _Ruler extends StatelessWidget {
  final Widget child;
  const _Ruler({required this.child});

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFEF4444)),
        ),
        child: child,
      );
}
