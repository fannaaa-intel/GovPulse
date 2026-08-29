// Preview target for the progress-updates widget.
//
// The real screens are login-gated, so this boots the widget on its own in all
// three roles side by side. It renders the FIRST frame — the one before the
// Supabase fetch resolves — which is exactly the composer/controls layout this
// preview exists to look at.
//
// Run:
//   flutter run -d web-server --web-port 57810 -t tool/preview_progress_updates.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:govpulse/core/widgets/report_progress_updates.dart';

// ⚠ Deliberately a dead host, not the real project. The widget collapses to
// NOTHING when the table is missing (PostgREST 42P01 = "migration not applied"),
// which is correct behaviour and useless for previewing — pointed at the real
// URL before 20260829000001 is pushed, all three panels render empty. A refused
// connection is a plain network error instead, so the composer stays up and the
// error toast is visible. Swap in the real URL once the migration is live.
const _url = 'http://127.0.0.1:1';
const _anon = 'sb_publishable_ZBDaQPQdFyC5kOHGbce9Ig_zdtIi6Mo';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: _url,
    anonKey: _anon,
    authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
    debug: false,
  );
  runApp(const _PreviewApp());
}

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFEEF2F7),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Wrap(
              spacing: 20,
              runSpacing: 20,
              children: [
                for (final mode in ReportUpdatesMode.values)
                  SizedBox(
                    width: 420,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          mode.name.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ReportProgressUpdates(
                          reportId: '3f2a1b6c-8d4e-4f7a-9b1c-2e5d6a7b8c9d',
                          mode: mode,
                          authorName: 'Engineering Office',
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
