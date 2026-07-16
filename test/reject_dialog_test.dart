// The reject dialog closes a citizen's report for good and notifies them, so
// the rules worth pinning are about what it returns: never nothing, and always
// the words the admin actually chose.
//
// Driven through showRejectReportDialog, the same entry point the report detail
// uses — the reason it pops with is the whole contract, and it lands verbatim in
// the citizen's notification.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/admin/pages/admin_reports_page.dart';

/// Opens the dialog and captures whatever it pops with.
Future<void> _open(WidgetTester tester, void Function(String?) onResult) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                onResult(await showRejectReportDialog(context)),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Finder _rejectButton() => find.widgetWithText(
      FilledButton,
      'Reject & notify citizen',
    );

bool _enabled(WidgetTester tester) =>
    tester.widget<FilledButton>(_rejectButton()).onPressed != null;

void main() {
  testWidgets('a report cannot be rejected with no reason at all',
      (tester) async {
    await _open(tester, (_) {});
    // Nothing picked, nothing typed — the citizen would get no explanation.
    expect(_enabled(tester), isFalse);
  });

  testWidgets('picking a preset is enough to reject', (tester) async {
    String? result;
    await _open(tester, (r) => result = r);

    await tester.tap(find.text('Duplicate of an existing report'));
    await tester.pumpAndSettle();
    expect(_enabled(tester), isTrue);

    await tester.tap(_rejectButton());
    await tester.pumpAndSettle();
    expect(result, 'Duplicate of an existing report');
  });

  testWidgets('typing a reason is enough on its own', (tester) async {
    String? result;
    await _open(tester, (r) => result = r);

    await tester.enterText(find.byType(TextField), '  Filed by mistake  ');
    await tester.pumpAndSettle();
    expect(_enabled(tester), isTrue);

    await tester.tap(_rejectButton());
    await tester.pumpAndSettle();
    // Trimmed — trailing whitespace would reach the citizen otherwise.
    expect(result, 'Filed by mistake');
  });

  testWidgets('typed words win over a picked preset', (tester) async {
    String? result;
    await _open(tester, (r) => result = r);

    await tester.tap(find.text('Could not be verified'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Photo shows a different street');
    await tester.pumpAndSettle();

    await tester.tap(_rejectButton());
    await tester.pumpAndSettle();
    expect(result, 'Photo shows a different street');
  });

  testWidgets('tapping the chosen preset again clears it', (tester) async {
    await _open(tester, (_) {});

    await tester.tap(find.text('Not enough information to act'));
    await tester.pumpAndSettle();
    expect(_enabled(tester), isTrue);

    await tester.tap(find.text('Not enough information to act'));
    await tester.pumpAndSettle();
    expect(_enabled(tester), isFalse, reason: 'the preset should deselect');
  });

  testWidgets('cancelling returns nothing, so nothing is rejected',
      (tester) async {
    String? result = 'untouched';
    await _open(tester, (r) => result = r);

    await tester.tap(find.text('Duplicate of an existing report'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });

  group('lays out at every width', () {
    for (final w in [1200.0, 700.0, 420.0, 360.0]) {
      testWidgets('${w.toInt()}px', (tester) async {
        tester.view.physicalSize = Size(w, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await _open(tester, (_) {});
        expect(tester.takeException(), isNull);
        // Every reason stays reachable, however narrow.
        for (final p in const [
          'Duplicate of an existing report',
          'Not enough information to act',
          'Not actionable by the LGU',
          'Could not be verified',
        ]) {
          expect(find.text(p), findsOneWidget, reason: '$p missing at ${w}px');
        }
        expect(_rejectButton(), findsOneWidget);
      });
    }
  });
}
