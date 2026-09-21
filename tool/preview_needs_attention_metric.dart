// Dev-only harness for the ADMIN dashboard's "Needs your attention" card,
// specifically the focus row's trailing METRIC.
//
// Not part of the app: nothing under lib/ imports it, and it is never a build
// target for a shipped bundle.
//
//   flutter build web --release -t tool/preview_needs_attention_metric.dart
//   python -m http.server 57816 --directory build/web
//
// -- Why this exists --------------------------------------------------------
// `metric` is model output. It was a bare Text in a Row - unconstrained, so it
// took whatever width it asked for and was then clipped by the card edge: no
// ellipsis, cut mid-word ("1 recent complaint (docu"), reading as a broken
// layout rather than a shortened label. It showed on desktop and on a phone.
//
// The card is three interactions deep behind a login-gated console, so this
// feeds it a canned AI insight carrying the EXACT strings from the report and
// renders every width side by side.
//
// -- What to look at --------------------------------------------------------
//  * Every metric ends in an ellipsis or fits; none is cut mid-word.
//  * The title keeps priority - the metric is capped at 45% of the row, so a
//    long metric never starves it.
//  * 320px is the tightest phone. Both strings must still be legible there.

// This harness drives the same @visibleForTesting seams the widget tests use,
// which is the whole point - it renders the REAL card, not a copy that could
// drift from it. Nothing here ships.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter/material.dart';

import 'package:govpulse/core/services/web_splash.dart';
import 'package:govpulse/features/admin/pages/admin_overview_page.dart';
import 'package:govpulse/features/admin/providers/admin_dashboard_provider.dart';
import 'package:govpulse/features/admin/theme/admin_ui.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  WidgetsBinding.instance.addPostFrameCallback((_) => removeWebSplash());
  runApp(const _PreviewApp());
}

final _now = DateTime.now();

/// The reported rows, verbatim: 24 characters, cut mid-word by the old
/// server-side `.slice(0, 24)`.
Map<String, dynamic> _aiInsight() => {
  'generated_at': _now.toIso8601String(),
  'summary':
      'Overall service rating is moderate (3.5 stars); document handling and '
      'wait-time at the Civil Registrar need immediate attention, while rising '
      'high-urgency reports in three barangays pose a safety risk.',
  'focus': [
    {
      'title': 'Document handling',
      'scope': 'Municipal Civil Registrar',
      'metric': '1 recent complaint (docu',
      'suggestion':
          'Create a centralized document receipt log and assign a staff '
          'member to verify and confirm each filing.',
      'severity': 'high',
      'target': 'feedback',
    },
    {
      'title': 'Wait time',
      'scope': 'Municipal Civil Registrar - 4 responses',
      'metric': '2.75*',
      'suggestion':
          'Add an extra service window and display real-time queue estimates '
          'to reduce waiting time.',
      'severity': 'medium',
      'target': 'feedback',
    },
    {
      'title': 'High-urgency reports',
      'scope': 'Sanja, Macanaya (Pescaria), Maura - 3 reports',
      'metric': '3 recent high-urgency re',
      'suggestion':
          'Deploy inspection teams to these barangays this week to address '
          'road and drainage hazards.',
      'severity': 'high',
      'target': 'reports',
    },
    {
      // Pathological: one long token with no space to break on.
      'title': 'Unbreakable token',
      'scope': null,
      'metric': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'suggestion': 'Must ellipsise rather than overflow.',
      'severity': 'low',
      'target': null,
    },
  ],
};

Map<String, dynamic> _feedback(int rating, DateTime at, String office) => {
  'id': 'fb-${at.microsecondsSinceEpoch}-$rating',
  'office_label': office,
  'service_name': 'Permits',
  'overall_rating': rating,
  'aspect_clarity': rating,
  'comment': null,
  'created_at': at.toIso8601String(),
};

NlpInsights _insights() => AdminDashboardNotifier().analyseNlp(
  [
    _feedback(2, _now.subtract(const Duration(days: 3)), 'Municipal Civil Registrar'),
    _feedback(4, _now.subtract(const Duration(days: 10)), "Mayor's Office"),
    _feedback(3, _now.subtract(const Duration(days: 20)), 'Municipal Health Office'),
  ],
  const [],
  const [],
  _aiInsight(),
  _now,
);

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    final nlp = _insights();
    // 320 is the tightest phone; 360/393 the common ones; 440 the dashboard
    // rail; 700 the card inside a wide dialog.
    const widths = <double>[320, 360, 393, 440, 700];

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF1F2937),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 16,
            runSpacing: 16,
            crossAxisAlignment: WrapCrossAlignment.start,
            children: [
              for (final w in widths)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${w.toInt()} px',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: w,
                      color: AdminUi.pageBg,
                      padding: const EdgeInsets.all(10),
                      child: needsAttentionForTesting(nlp),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
