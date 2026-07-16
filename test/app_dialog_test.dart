// Pins HOW a GovPulse pop-up leaves.
//
// The bug this guards: Flutter's stock showDialog fades out in 150ms flat,
// which on the cards this app uses reads as the pop-up blinking out of
// existence rather than closing. Every dialog goes through showAppDialog now,
// and these tests fail against a plain showDialog.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/widgets/app_dialog.dart';

/// Pumps a screen with one button that opens a dialog, and returns a handle to
/// open it.
Future<void> _pumpHost(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAppDialog<void>(
              context: context,
              builder: (_) => const Dialog(child: Text('CARD')),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a dialog opens and closes', (tester) async {
    await _pumpHost(tester);
    await _open(tester);
    expect(find.text('CARD'), findsOneWidget);

    final ctx = tester.element(find.text('CARD'));
    Navigator.of(ctx).pop();
    await tester.pumpAndSettle();
    expect(find.text('CARD'), findsNothing);
  });

  testWidgets('the exit is a real animation, not a cut', (tester) async {
    await _pumpHost(tester);
    await _open(tester);

    final ctx = tester.element(find.text('CARD'));
    Navigator.of(ctx).pop();
    await tester.pump(); // start the exit

    // Still on screen at the point the STOCK 150ms fade would already be over.
    // This is the assertion that fails against a plain showDialog.
    await tester.pump(const Duration(milliseconds: 160));
    expect(
      find.text('CARD'),
      findsOneWidget,
      reason: 'the card should still be leaving, not already gone',
    );

    // ...and it is mid-fade rather than parked at full opacity, i.e. actually
    // animating out rather than sitting still and then vanishing.
    final opacity = tester.widget<FadeTransition>(
      find.ancestor(
        of: find.text('CARD'),
        matching: find.byType(FadeTransition),
      ).first,
    );
    expect(opacity.opacity.value, lessThan(1.0));
    expect(opacity.opacity.value, greaterThan(0.0));

    // Gone once the shared duration is up.
    await tester.pumpAndSettle();
    expect(find.text('CARD'), findsNothing);
  });

  testWidgets('the exit runs for the shared dialog duration', (tester) async {
    await _pumpHost(tester);
    await _open(tester);

    final ctx = tester.element(find.text('CARD'));
    Navigator.of(ctx).pop();
    await tester.pump();

    // One frame shy of the full duration it is still there; past it, gone.
    await tester.pump(kAppDialogDuration - const Duration(milliseconds: 20));
    expect(find.text('CARD'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 40));
    await tester.pumpAndSettle();
    expect(find.text('CARD'), findsNothing);
  });

  testWidgets('a barrier tap still dismisses when it is allowed to',
      (tester) async {
    await _pumpHost(tester);
    await _open(tester);

    await tester.tapAt(const Offset(10, 10)); // outside the card
    await tester.pumpAndSettle();
    expect(find.text('CARD'), findsNothing);
  });

  testWidgets('barrierDismissible: false survives a barrier tap',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAppDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => const Dialog(child: Text('CARD')),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await _open(tester);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(
      find.text('CARD'),
      findsOneWidget,
      reason: 'a form holding unsaved input must not vanish on a stray click',
    );
  });
}
