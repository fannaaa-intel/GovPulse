// ════════════════════════════════════════════════════════════════════════════
//  "You already reported this" — the citizen's own open report is at this spot
//
//  Report-flood hardening (20261014000000). The server now refuses a second
//  report from the same account, same category, within 60 m of their own open
//  report. This dialog says so BEFORE anything is uploaded, using
//  nearby_open_reports.is_mine, so the refusal is an explanation with a way
//  forward rather than an error after a slow upload.
//
//  Unlike "Already reported here?" this offers no "file it anyway": a second
//  copy of your own report would only lengthen the queue. The ways out are to
//  follow the report you already have, or to go back and change the draft
//  (a different category or spot is a different report and goes through).
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/citizen_ui.dart';
import '../../../../core/widgets/app_dialog.dart';

/// What the citizen picked: follow their existing report, or edit the draft.
enum AlreadyReportedChoice { viewMine, editDraft }

/// Shows the dialog. Null when dismissed (treated like [editDraft]).
Future<AlreadyReportedChoice?> showAlreadyReportedDialog(
  BuildContext context, {
  required String shortRef,
  DateTime? filedAt,
}) {
  return showAppDialog<AlreadyReportedChoice>(
    context: context,
    builder: (ctx) =>
        AlreadyReportedDialog(shortRef: shortRef, filedAt: filedAt),
  );
}

class AlreadyReportedDialog extends StatelessWidget {
  final String shortRef;
  final DateTime? filedAt;
  const AlreadyReportedDialog({
    super.key,
    required this.shortRef,
    this.filedAt,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final when = filedAt == null ? null : filedAgo(filedAt!, DateTime.now());

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      constraints: BoxConstraints(
        maxWidth: 400,
        minWidth: 280,
        maxHeight: media.size.height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The explanation may scroll on a tiny screen at a large text size;
          // the two actions below never do, so they cannot leave the card.
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.assignment_turned_in_outlined,
                      color: AppColors.primaryBlue,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'You already reported this',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: CitizenUi.textPrimary,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: CitizenUi.subtle,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: CitizenUi.sharedBorder),
                    ),
                    child: Text(
                      [
                        'RPT-$shortRef',
                        'still open',
                        if (when != null) 'filed $when',
                      ].join(' · '),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: CitizenUi.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Your report about this spot is already in the LGU '
                    'queue. Sending it again will not make it faster. You can '
                    'follow its progress in My Reports.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: CitizenUi.textMuted,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(context, AlreadyReportedChoice.viewMine),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    minimumSize: const Size(0, 46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'View my reports',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () =>
                      Navigator.pop(context, AlreadyReportedChoice.editDraft),
                  style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
                  child: const Text(
                    'Go back and edit',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: CitizenUi.textMuted,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "today", "yesterday", "3 days ago", "2 weeks ago" — written out, because
/// this sits in a sentence ("filed 3 days ago") rather than a timestamp column.
String filedAgo(DateTime at, DateTime now) {
  final days = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(at.year, at.month, at.day)).inDays;
  if (days <= 0) return 'today';
  if (days == 1) return 'yesterday';
  if (days < 14) return '$days days ago';
  final weeks = days ~/ 7;
  return '$weeks weeks ago';
}
