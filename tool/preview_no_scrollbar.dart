// Preview target: the painted scrollbar that ran down the inside edge of every
// admin/staff detail pop-up, and its absence once GovPulseWebApp sets
// NoScrollbarBehavior at the web root.
//
//   flutter build web --release -t tool/preview_no_scrollbar.dart
//
// The real Report Details dialog needs a session, a role and a report row. What
// is being judged here is NOT that dialog's content but the SCROLL BEHAVIOUR
// that reaches it, so this mounts the same shape — a rounded card whose body is
// a SingleChildScrollView longer than its frame — under two different roots:
//
//   LEFT  "BEFORE": a bare MaterialApp, which is what GovPulseWebApp was. This
//                   is the bar in the bug report.
//   RIGHT "AFTER" : the same tree with scrollBehavior: NoScrollbarBehavior(),
//                   which is the one-line change.
//
// Each side wraps the card in the SAME widget MaterialApp.scrollBehavior
// installs internally (a ScrollConfiguration), so what is on screen is what the
// root-level fix produces. See _Frame for why a nested MaterialApp per side
// cannot be used here.
import 'package:flutter/material.dart';

import 'package:govpulse/core/widgets/no_scrollbar_behavior.dart';
import 'package:govpulse/features/admin/theme/admin_ui.dart';

void main() => runApp(const _Harness());

class _Harness extends StatelessWidget {
  const _Harness();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF2B2F3A),
        body: SafeArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Expanded(child: _Frame(label: 'BEFORE — bare root', barred: true)),
              Expanded(
                child: _Frame(
                  label: 'AFTER — NoScrollbarBehavior',
                  barred: false,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One labelled frame holding the stand-in detail.
///
/// ── WHY NOT A NESTED MaterialApp PER SIDE ─────────────────────────────────
/// The obvious harness — two MaterialApps, one with `scrollBehavior` set — does
/// NOT work, and fails in a way that reads as "the app never mounted": a nested
/// MaterialApp's showDialog resolves to the ROOT navigator, so both dialogs
/// mount on the outermost overlay, stacked, and only the last one is visible.
///
/// [ScrollConfiguration] is used instead, which is exactly what
/// `MaterialApp.scrollBehavior` installs internally — it is the same widget the
/// real fix ends up as, just declared here rather than by the app root.
class _Frame extends StatelessWidget {
  final String label;
  final bool barred;
  const _Frame({required this.label, required this.barred});

  @override
  Widget build(BuildContext context) {
    final detail = const _StandInDetail();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: barred
                ? detail
                : ScrollConfiguration(
                    // The one thing under test.
                    behavior: const NoScrollbarBehavior(),
                    child: detail,
                  ),
          ),
        ),
      ],
    );
  }
}

/// The same shape as the real detail: a clipped rounded card whose body is a
/// SingleChildScrollView taller than the frame. The bar, when there is one,
/// paints on that rounded corner — which is the actual complaint.
class _StandInDetail extends StatelessWidget {
  const _StandInDetail();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AdminUi.pageBg,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AdminUi.surface,
            borderRadius: BorderRadius.circular(AdminUi.cardRadius),
            border: Border.all(color: AdminUi.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Report Details',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AdminUi.textPrimary,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 16),
              // Long enough to overflow the frame, so the scroll view is
              // genuinely scrollable and a bar has cause to appear.
              for (var i = 0; i < 24; i++) ...[
                Text(
                  'Line ${i + 1} — the details pane runs past the bottom of the '
                  'card, which is what makes this scroll.',
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: AdminUi.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
