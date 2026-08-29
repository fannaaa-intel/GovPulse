// Preview target for the CITIZEN framing of the progress-updates widget.
//
// The question this answers is one screenshot could not: does the timeline sit
// among its neighbours on the citizen report screen, or does it read as a
// foreign box? So it renders the widget the way that screen does — blue heading
// outside, no card — sandwiched between two stand-ins for the sections above
// and below it.
//
// Run:
//   flutter run -d web-server --web-port 57840 -t tool/preview_citizen_updates.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:govpulse/core/theme/app_colors.dart';
import 'package:govpulse/core/widgets/report_progress_updates.dart';

/// Returns two approved updates, one of them with a photo, so the citizen view
/// renders with real content rather than an empty state.
class _MockApi extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = [
      {
        'id': '00000000-0000-0000-0000-000000000000',
        'body': 'Patching completed, curing overnight.',
        'kind': 'progress',
        'status': 'approved',
        'rejected_reason': null,
        'author_role': 'staff',
        'author_name': 'Engineering Office',
        'created_at': '2026-08-29T13:05:00Z',
        'report_update_media': [],
      },
      {
        'id': '11111111-1111-1111-1111-111111111111',
        'body': 'Hi citizen, thank you for your understanding.',
        'kind': 'progress',
        'status': 'approved',
        'rejected_reason': null,
        'author_role': 'admin',
        'author_name': 'LGU Admin',
        'created_at': '2026-08-29T12:40:00Z',
        'report_update_media': [],
      },
      {
        'id': '22222222-2222-2222-2222-222222222222',
        'body': 'Inspected the site today, the post is corroded at the base.',
        'kind': 'progress',
        'status': 'approved',
        'rejected_reason': null,
        'author_role': 'staff',
        'author_name': 'Engineering Office',
        'created_at': '2026-08-29T12:10:00Z',
        'report_update_media': [
          {'id': 'm1', 'storage_path': 'updates/demo/a.jpg'},
        ],
      },
    ];
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
  await Supabase.initialize(
    url: 'https://preview.invalid',
    anonKey: 'preview-not-a-real-key',
    httpClient: _MockApi(),
    authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
    debug: false,
  );
  runApp(const _App());
}

class _App extends StatelessWidget {
  const _App();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFF3F5F9),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: w * .05),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: w * .05),
                    _label(w, 'Processing timeline'),
                    SizedBox(height: w * .03),
                    _placeholder(w, 120),
                    ReportProgressUpdates(
                      reportId: '3f2a1b6c-8d4e-4f7a-9b1c-2e5d6a7b8c9d',
                      mode: ReportUpdatesMode.citizen,
                      chrome: false,
                      maxVisible: 2,
                      heading: Padding(
                        padding: EdgeInsets.only(
                          top: w * .045,
                          bottom: w * .03,
                        ),
                        child: _label(w, 'Latest updates'),
                      ),
                    ),
                    SizedBox(height: w * .045),
                    _label(w, 'Report details'),
                    SizedBox(height: w * .03),
                    _placeholder(w, 150),
                    SizedBox(height: w * .1),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _label(double w, String text) => Text(
        text,
        style: TextStyle(
          fontSize: w * .036,
          fontWeight: FontWeight.w700,
          color: AppColors.primaryBlue,
          letterSpacing: 0.2,
        ),
      );

  /// Stands in for the neighbouring cards, at their real corner radius, so the
  /// comparison is about framing rather than content.
  Widget _placeholder(double w, double h) => Container(
        width: double.infinity,
        height: h,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black12),
        ),
      );
}
