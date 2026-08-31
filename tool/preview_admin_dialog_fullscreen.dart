// Preview target: the report-process dialogs at the widths that decide their
// shape — a full screen on a phone, a centred modal on tablet and desktop.
//
//   flutter build web --release -t tool/preview_admin_dialog_fullscreen.dart
//
// The real dialogs are opened from the reports console, which needs a session
// and a report. This mounts AdminResponsiveDialog directly with stand-in
// content, because what is being judged is the SHELL: which shape it takes,
// where the back chevron sits, and whether the action bar stays reachable.
//
// ?w= overrides the frame width.
import 'package:flutter/material.dart';

import 'package:govpulse/core/theme/app_colors.dart';
import 'package:govpulse/features/admin/theme/admin_ui.dart';
import 'package:govpulse/features/admin/widgets/admin_responsive_dialog.dart';

void main() {
  final w = double.tryParse(Uri.base.queryParameters['w'] ?? '');
  runApp(_App(single: w));
}

class _App extends StatelessWidget {
  final double? single;
  const _App({this.single});

  @override
  Widget build(BuildContext context) {
    const widths = [900.0, 700.0, 641.0, 639.0, 409.0, 360.0];
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF2B2F3A),
        body: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final w in (single != null ? [single!] : widths)) ...[
                _Frame(width: w),
                const SizedBox(width: 24),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Frame extends StatelessWidget {
  final double width;
  const _Frame({required this.width});

  @override
  Widget build(BuildContext context) {
    final full = width < kAdminDialogFullscreenBelow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${width.toInt()} — ${full ? 'FULL SCREEN' : 'modal'}',
          style: const TextStyle(
              color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Container(
          width: width,
          height: 760,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(6)),
          // The shell reads the viewport, so each frame declares its own.
          child: MediaQuery(
            data: MediaQueryData(size: Size(width, 760)),
            child: Navigator(
              onGenerateRoute: (_) => MaterialPageRoute(
                builder: (ctx) => Stack(
                  children: [
                    // The console behind it, so the modal's barrier has
                    // something to float over.
                    Container(color: const Color(0xFFF1F4F9)),
                    const ModalBarrier(color: Colors.black54),
                    AdminResponsiveDialog(
                      title: 'Endorse to External Entity',
                      subtitle:
                          'Send this report to the appropriate external '
                          'agency for action and follow-up.',
                      headerNote: const Text(
                        'This issues a printed letter with a one-time PIN.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          fontWeight: FontWeight.w700,
                          color: AppColors.red,
                        ),
                      ),
                      leading: Container(
                        width: 56,
                        height: 56,
                        decoration: const BoxDecoration(
                          color: Color(0xFFEAF1FF),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.send_rounded,
                            size: 26, color: AppColors.primaryBlue),
                      ),
                      actions: [
                        FilledButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.send_rounded, size: 17),
                          label: const Text('Send Endorsement'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primaryBlue,
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                        OutlinedButton(
                          onPressed: () {},
                          style: OutlinedButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ],
                      child: const _AgencyPicker(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Stands in for the dialog's body: a search field and the 2-up agency grid.
class _AgencyPicker extends StatelessWidget {
  const _AgencyPicker();

  @override
  Widget build(BuildContext context) {
    const agencies = [
      ('PNP Aparri', 'Philippine National Police', 'Peace & Order'),
      ('BFP Aparri', 'Bureau of Fire Protection', 'Fire Safety & Rescue'),
      ('DPWH', 'Department of Public Works and Highways',
          'Infrastructure & Roads'),
      ('DENR', 'Department of Environment and Natural Resources',
          'Environment & Sustainability'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Select External Entity',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AdminUi.textPrimary)),
        const SizedBox(height: 4),
        const Text(
          'Choose the agency or department that best handles this report.',
          style: TextStyle(fontSize: 12.5, color: AdminUi.textSecondary),
        ),
        const SizedBox(height: 12),
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AdminUi.border),
          ),
          child: const Row(children: [
            Icon(Icons.search_rounded, size: 18, color: AdminUi.textMuted),
            SizedBox(width: 10),
            Text('Search agency…',
                style: TextStyle(fontSize: 13.5, color: AdminUi.textMuted)),
          ]),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(builder: (context, c) {
          const gap = 12.0;
          final cols = c.maxWidth >= 260 ? 2 : 1;
          final itemW = (c.maxWidth - gap * (cols - 1)) / cols;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final a in agencies)
                SizedBox(width: itemW, child: _AgencyCard(a.$1, a.$2, a.$3)),
            ],
          );
        }),
      ],
    );
  }
}

class _AgencyCard extends StatelessWidget {
  final String name;
  final String full;
  final String tag;
  const _AgencyCard(this.name, this.full, this.tag);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AdminUi.border),
        ),
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                  color: Color(0xFFEFF3FA), shape: BoxShape.circle),
              child: const Icon(Icons.account_balance_rounded,
                  color: AppColors.primaryBlue),
            ),
            const SizedBox(height: 10),
            Text(name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text('($full)',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 11, color: AdminUi.textSecondary, height: 1.3)),
            const SizedBox(height: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(tag,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryBlue)),
            ),
          ],
        ),
      );
}
