// Preview target for the completion-photos card (ResolutionMediaSection).
//
// The real card only appears inside the admin report dialog, on a report whose
// status is already `resolved` — three gates deep behind a login. This boots it
// on its own against a MOCK HTTP CLIENT so both states that matter can be
// looked at side by side:
//
//   • EMPTY  — what an admin meets the moment they resolve a report. This is
//              the state in the screenshot that prompted the redesign, and the
//              one that was carrying two equal-weight outlined buttons under a
//              line of grey prose with nothing to anchor them.
//   • FILLED — the same card once photos exist, so the thumbnail grid and the
//              header count can be checked against it.
//
// The citizen's read-only variant is included because it shares every line of
// the layout and renders nothing at all when empty — easy to break by accident
// while editing the admin path.
//
// Run:
//   flutter run -d web-server --web-port 57840 -t tool/preview_resolution_media.dart
//
// Query parameters:
//   ?w=380   clamp the viewport, to check the card holds on a narrow pane
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:govpulse/core/widgets/resolution_media.dart';

/// Answers the one table this widget reads. A report id ending in `filled`
/// comes back with media; anything else comes back empty, which is how one
/// mock serves both panels at once.
class _MockApi extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final url = request.url.toString();
    // The widget filters on report_id, so the requested id is in the query.
    final filled = url.contains('filled');

    // Realtime is a websocket the mock cannot serve; the widget subscribes and
    // simply never receives, which is fine for a layout preview.
    final body = filled
        ? [
            {
              'id': '1',
              'storage_path': 'demo/after-1.jpg',
              'mime_type': 'image/jpeg',
              'created_at': '2026-08-30T14:03:00Z',
            },
            {
              'id': '2',
              'storage_path': 'demo/after-2.jpg',
              'mime_type': 'image/jpeg',
              'created_at': '2026-08-30T14:04:00Z',
            },
            {
              'id': '3',
              'storage_path': 'demo/walkthrough.mp4',
              'mime_type': 'video/mp4',
              'created_at': '2026-08-30T14:05:00Z',
            },
          ]
        : <Map<String, dynamic>>[];

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
  final width = double.tryParse(Uri.base.queryParameters['w'] ?? '');

  await Supabase.initialize(
    url: 'https://preview.invalid',
    anonKey: 'preview-not-a-real-key',
    httpClient: _MockApi(),
    authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
    debug: false,
  );

  runApp(_PreviewApp(width: width));
}

class _PreviewApp extends StatelessWidget {
  final double? width;
  const _PreviewApp({this.width});

  @override
  Widget build(BuildContext context) {
    const panels = [
      ('ADMIN · EMPTY', 'empty-1111-2222-3333-444444444444', true),
      ('ADMIN · FILLED', 'filled-1111-2222-3333-44444444', true),
      ('CITIZEN · FILLED', 'filled-5555-6666-7777-88888888', false),
    ];

    final body = SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Wrap(
        spacing: 20,
        runSpacing: 20,
        children: [
          for (final (label, id, canEdit) in panels)
            SizedBox(
              // The admin dialog's right pane, near enough — the card has to
              // work at this measure, not at a full browser width.
              width: 420,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ResolutionMediaSection(reportId: id, canEdit: canEdit),
                ],
              ),
            ),
        ],
      ),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFEEF2F7),
        body: SafeArea(
          child: width == null
              ? body
              : Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(width: width, child: body),
                ),
        ),
      ),
    );
  }
}
