// AI service-category routing — the recommendation the admin sees at triage.
//
// Two things are under test and they fail in different ways:
//
//  1. THE FALLBACK CONTRACT. `ai_department` is null whenever the model hasn't
//     reached a row, AI usage is exhausted, or 20260914000000 hasn't been
//     applied. Every one of those must degrade to the deterministic category
//     lookup rather than showing the admin an empty recommendation. This is the
//     half that silently rots: the AI path works in every manual test because
//     the test data has been classified, and the fallback only runs in the
//     situations nobody reproduces by hand.
//
//  2. THE BADGE MUST NOT OVERFLOW. "AI Recommended" is meaningfully wider than
//     "Recommended" and sits on a card in a 2-up grid on phones. See
//     [[admin-responsive-overflow-probe]] — a 1280px screenshot shows this as
//     fine while 320px clips it.
//
// The dialog is driven through its real entry point (showAcceptAssignDialog) so
// the plumbing between the page, the dialog and the badge is covered too, not
// just the widgets in isolation.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/admin/providers/admin_reports_provider.dart';
import 'package:govpulse/features/admin/widgets/accept_assign_dialog.dart';
import 'package:govpulse/features/staff/data/staff_departments.dart';

import '_responsive_matrix.dart';

/// A report carrying only the fields the routing logic reads. Everything else
/// is filler — the model has a wide constructor and none of it matters here.
AdminReport _report({
  required String categoryKey,
  String? aiCategory,
  String? aiDepartment,
  String? aiCategoryReason,
}) {
  return AdminReport(
    id: '00000000-0000-0000-0000-000000000001',
    shortId: '00000000',
    categoryKey: categoryKey,
    category: reportCategoryLabel(categoryKey, null),
    barangay: 'Macanaya',
    address: null,
    remarks: 'test',
    status: ReportStatus.pending,
    isAnonymous: false,
    submitterName: null,
    submitterPhotoUrl: null,
    submitterRole: null,
    mediaCount: 0,
    createdAt: DateTime(2026, 9, 14),
    aiCategory: aiCategory,
    aiDepartment: aiDepartment,
    aiCategoryReason: aiCategoryReason,
  );
}

void main() {
  group('suggestedDepartment — the single source of the recommendation', () {
    test('prefers the AI department when classify-report has reached the row', () {
      final r = _report(
        categoryKey: 'others',
        aiCategory: 'road',
        aiDepartment: 'Engineering Office',
      );
      expect(r.suggestedDepartment, 'Engineering Office');
      expect(r.hasAiSuggestion, isTrue);
    });

    test('falls back to the category lookup when the AI has not run', () {
      // The unclassified case: no columns, no model, no network. This is what
      // every report looks like for the first few seconds of its life.
      final r = _report(categoryKey: 'waste');
      expect(r.suggestedDepartment, 'Sanitation Office');
      expect(r.suggestedDepartment,
          StaffDepartments.forReportCategory('waste'));
      expect(r.hasAiSuggestion, isFalse);
    });

    test('falls back when the migration has not been applied', () {
      // The select ladder degrades past the aiRouting tier, so the row map has
      // no such keys at all and every AI field parses as null. Behaviourally
      // identical to "not yet classified" — asserted separately because the
      // CAUSE is different and a future refactor could break one without the
      // other (e.g. by treating a missing column as an error).
      final r = _report(categoryKey: 'drainage');
      expect(r.suggestedDepartment, 'Engineering Office');
      expect(r.hasAiSuggestion, isFalse);
    });

    test('treats a blank AI department as absent, not as an office', () {
      // Defensive: a whitespace-only value would satisfy a bare null check and
      // put an empty string on the badge.
      final r = _report(categoryKey: 'waste', aiDepartment: '   ');
      expect(r.suggestedDepartment, 'Sanitation Office');
      expect(r.hasAiSuggestion, isFalse);
    });

    test('unknown category keys still resolve to an office', () {
      // report_department()'s else-branch. A category the app does not know
      // must not produce a null recommendation.
      final r = _report(categoryKey: 'not-a-real-category');
      expect(r.suggestedDepartment, "Mayor's Office");
    });
  });

  group('isMiscategorized — the signal that did not exist before', () {
    test('true when the model read a different category than the citizen', () {
      final r = _report(
        categoryKey: 'others',
        aiCategory: 'road',
        aiDepartment: 'Engineering Office',
      );
      expect(r.isMiscategorized, isTrue);
      expect(r.aiCategoryLabel, 'Road & Infrastructure');
    });

    test('false when they agree — no notice on a correctly filed report', () {
      final r = _report(
        categoryKey: 'road',
        aiCategory: 'road',
        aiDepartment: 'Engineering Office',
      );
      expect(r.isMiscategorized, isFalse);
      expect(r.aiCategoryLabel, isNull);
    });

    test('false when the AI has not classified the row', () {
      final r = _report(categoryKey: 'road');
      expect(r.isMiscategorized, isFalse);
      expect(r.aiCategoryLabel, isNull);
    });
  });

  group('the dialog reflects the recommendation source', () {
    testWidgets('badges the AI when the recommendation came from the model',
        (tester) async {
      await _openDialog(tester,
          recommendedOffice: 'Engineering Office', isAi: true);

      expect(find.text('AI Recommended'), findsOneWidget);
      expect(find.text('Recommended'), findsNothing);
      expect(find.text('Recommended from the details of this report.'),
          findsOneWidget);
    });

    testWidgets('keeps the plain badge for the deterministic rule',
        (tester) async {
      await _openDialog(tester,
          recommendedOffice: 'Engineering Office', isAi: false);

      expect(find.text('Recommended'), findsOneWidget);
      expect(find.text('AI Recommended'), findsNothing);
      // The lookup table cannot claim to have read the report.
      expect(find.text('Recommended from the details of this report.'),
          findsNothing);
    });

    testWidgets('shows the mis-filed notice with the model\'s reasoning',
        (tester) async {
      await _openDialog(
        tester,
        recommendedOffice: 'Engineering Office',
        isAi: true,
        miscategorizedAs: 'Road & Infrastructure',
        aiReason: 'describes a collapsed bridge',
      );

      expect(find.textContaining('may be filed under the wrong category'),
          findsOneWidget);
      expect(find.textContaining('describes a collapsed bridge'),
          findsOneWidget);
    });

    testWidgets('no notice when the citizen categorised correctly',
        (tester) async {
      await _openDialog(tester,
          recommendedOffice: 'Sanitation Office', isAi: true);

      expect(find.textContaining('may be filed under the wrong category'),
          findsNothing);
    });

    testWidgets('a rule-sourced recommendation never shows a mis-filed notice',
        (tester) async {
      // Guard against a future caller passing miscategorizedAs without the AI
      // flag: the deterministic rule has no opinion on whether the citizen was
      // right, so it must not appear to make that claim.
      await _openDialog(
        tester,
        recommendedOffice: 'Engineering Office',
        isAi: false,
        miscategorizedAs: 'Road & Infrastructure',
      );

      expect(find.textContaining('may be filed under the wrong category'),
          findsNothing);
    });

    testWidgets('the admin can still override the AI', (tester) async {
      await _openDialog(tester,
          recommendedOffice: 'Engineering Office', isAi: true);

      await tester.tap(find.text('Sanitation Office'));
      await tester.pumpAndSettle();

      // Stepping off the recommendation swaps the copy to the guiding form.
      expect(find.text('Choose the office that best handles this report.'),
          findsOneWidget);
      expect(find.text('Recommended from the details of this report.'),
          findsNothing);
    });
  });

  group('responsiveness — the wider badge must not clip', () {
    for (final device in kAllPhones) {
      testWidgets('no overflow at $device', (tester) async {
        // The worst case on purpose: the AI badge (widest label), the mis-filed
        // notice (extra vertical content above the grid), and a long reason
        // that has to wrap.
        final errors = await pumpAt(tester, device, () {
          return MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showAcceptAssignDialog(
                    context,
                    recommendedOffice: 'Engineering Office',
                    isAiRecommendation: true,
                    miscategorizedAs: 'Road & Infrastructure',
                    aiReason:
                        'describes a collapsed bridge on the national highway, '
                        'not a general administrative concern',
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          );
        }, after: (t) async {
          await t.tap(find.text('open'));
          await t.pumpAndSettle();
        });

        expect(errors, isEmpty, reason: errors.join('\n'));
      });
    }

    testWidgets('no overflow at the largest accessibility text scale',
        (tester) async {
      // The badge is a fixed-height pill with a 10px label; a user on Android's
      // largest font setting is the case most likely to burst it.
      final errors = await pumpAt(tester, kSmallPhone, () {
        return MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAcceptAssignDialog(
                  context,
                  recommendedOffice: 'Engineering Office',
                  isAiRecommendation: true,
                  miscategorizedAs: 'Road & Infrastructure',
                  aiReason: 'describes a collapsed bridge',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        );
      }, textScale: 1.3, after: (t) async {
        await t.tap(find.text('open'));
        await t.pumpAndSettle();
      });

      expect(errors, isEmpty, reason: errors.join('\n'));
    });
  });
}

/// Opens the dialog through its real entry point and settles.
Future<void> _openDialog(
  WidgetTester tester, {
  required String recommendedOffice,
  required bool isAi,
  String? miscategorizedAs,
  String? aiReason,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAcceptAssignDialog(
              context,
              recommendedOffice: recommendedOffice,
              isAiRecommendation: isAi,
              miscategorizedAs: miscategorizedAs,
              aiReason: aiReason,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}
