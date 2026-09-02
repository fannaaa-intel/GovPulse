// Dev-only: SEE the automated-check panel a reviewer gets in the admin console.
//
//   flutter run -d chrome -t tool/preview_verification_check_panel.dart
//
// The panel is the whole point of persisting the check result — if a reviewer
// cannot read it at a glance, the scoring may as well still be thrown away. So
// it gets looked at rather than only analysed.
//
// The production widget is private to admin_verification_page.dart and its
// dialog needs a Supabase-backed provider, so the panel's LAYOUT is rebuilt
// here against the same tokens and the same four states. What this verifies is
// the visual result: whether "needs a closer look" reads as different from
// "passed", and whether four reason lines fit without crushing.
import 'package:flutter/material.dart';

import 'package:govpulse/features/admin/theme/admin_ui.dart';

void main() => runApp(const _App());

class _App extends StatelessWidget {
  const _App();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: AdminUi.pageBg,
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Center(
            child: SizedBox(
              width: 560,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: const [
                  _Case(
                    caption: 'REJECT — wrong card entirely',
                    verdict: 'reject',
                    score: 12,
                    reasons: [
                      'Declared as PhilSys ID, but the wording matches '
                          'PhilHealth ID more closely.',
                      'No number in the documented PhilSys ID format was found.',
                    ],
                    flags: [],
                  ),
                  _Case(
                    caption: 'REVIEW — expired, and uploaded as a screenshot',
                    verdict: 'review',
                    score: 66,
                    reasons: [
                      'The card appears to have expired (JANUARY 15, 2019).',
                      'Only the printed wording matched — no valid ID number '
                          'and too few readable fields to confirm this is a '
                          'real card.',
                    ],
                    flags: ['no_camera_metadata', 'png_likely_screenshot'],
                  ),
                  _Case(
                    caption: 'AUTO-ACCEPT — nothing to report',
                    verdict: 'auto_accept',
                    score: 95,
                    reasons: [],
                    flags: [],
                  ),
                  _Case(
                    caption: 'NOT CHECKED — pre-migration row, or checker down',
                    verdict: null,
                    score: null,
                    reasons: [],
                    flags: [],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Case extends StatelessWidget {
  final String caption;
  final String? verdict;
  final int? score;
  final List<String> reasons;
  final List<String> flags;

  const _Case({
    required this.caption,
    required this.verdict,
    required this.score,
    required this.reasons,
    required this.flags,
  });

  static const _meta = <String, (String, IconData, Color)>{
    'auto_accept': (
      'Passed automated checks',
      Icons.verified_rounded,
      Color(0xFF1B873F),
    ),
    'review': ('Needs a closer look', Icons.flag_rounded, Color(0xFFB26A00)),
    'reject': (
      'Failed automated checks',
      Icons.gpp_bad_rounded,
      Color(0xFFC62828),
    ),
  };

  static String _flagLabel(String code) => switch (code) {
    'no_camera_metadata' => 'No camera data — may be a screenshot',
    'png_likely_screenshot' => 'PNG file — likely a screenshot',
    _ => code,
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            caption,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AdminUi.textMuted,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AdminUi.surface,
              borderRadius: BorderRadius.circular(AdminUi.cardRadius),
              border: Border.all(color: AdminUi.border),
            ),
            child: verdict == null ? _notChecked() : _checked(),
          ),
        ],
      ),
    );
  }

  Widget _notChecked() => const Row(
    children: [
      Icon(Icons.help_outline_rounded, size: 15, color: AdminUi.textMuted),
      SizedBox(width: 7),
      Expanded(
        child: Text(
          'Not checked automatically — review the photos directly.',
          style: TextStyle(fontSize: 12, color: AdminUi.textMuted),
        ),
      ),
    ],
  );

  Widget _checked() {
    final (label, icon, colour) = _meta[verdict]!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AdminUi.controlRadius),
        border: Border.all(color: colour.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: colour),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: colour,
                  ),
                ),
              ),
              if (score != null)
                Text(
                  '$score/100',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colour,
                  ),
                ),
            ],
          ),
          if (reasons.isNotEmpty) ...[
            const SizedBox(height: 9),
            for (final r in reasons)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 5, right: 6),
                      child: Icon(
                        Icons.circle,
                        size: 5,
                        color: AdminUi.textSecondary,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        r,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: AdminUi.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (flags.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final f in flags)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AdminUi.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AdminUi.border),
                    ),
                    child: Text(
                      _flagLabel(f),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AdminUi.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
