// Endorsing hands a report out of the LGU's hands and mints a printed letter
// over the Mayor's signature, so the rules worth pinning are about what the
// dialog refuses to resolve with: never an agency without a reason, and never a
// reason the admin did not actually type.
//
// Driven through showEndorseEntityDialog, the same entry point the report
// detail uses. The EndorseChoice it pops with is the whole contract — the
// reason lands verbatim in the letter's "BASIS FOR ENDORSEMENT" section and on
// the agency's scan page.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/router/app_router.dart';
import 'package:govpulse/features/admin/widgets/endorse_entity_dialog.dart';

Future<void> _open(
  WidgetTester tester,
  void Function(EndorseChoice?) onResult, {
  String? current,
}) async {
  // The dialog scrolls, and the default 800x600 test surface leaves the agency
  // cards below the fold where tap() cannot hit them. Behaviour tests get a
  // surface big enough to show the whole dialog; the width sweep at the bottom
  // is where narrow layouts are exercised.
  tester.view.physicalSize = const Size(1100, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => onResult(
              await showEndorseEntityDialog(context, currentEndorsement: current),
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

Finder _sendButton() =>
    find.widgetWithText(FilledButton, 'Send Endorsement');

bool _enabled(WidgetTester tester) =>
    tester.widget<FilledButton>(_sendButton()).onPressed != null;

Finder _reasonField() => find.byType(TextField).last;

const _kMissingReason =
    'A reason is required before this report can be endorsed.';

void main() {
  // The agency picker is stateful and the reason field is required, so these
  // two together are the gate. Neither alone may let an endorsement through.
  testWidgets('no agency picked means nothing can be sent', (tester) async {
    await _open(tester, (_) {});
    expect(_enabled(tester), isFalse);
  });

  testWidgets('an agency without a reason is refused, and says why',
      (tester) async {
    EndorseChoice? result = EndorseChoice.clear; // sentinel, must not survive
    await _open(tester, (r) => result = r);

    await tester.tap(find.text('DPWH').first);
    await tester.pumpAndSettle();

    // The button stays enabled on purpose — pressing it is how the admin finds
    // out what is missing, rather than hunting a greyed-out control.
    expect(_enabled(tester), isTrue);
    expect(find.text(_kMissingReason), findsNothing);

    await tester.tap(_sendButton());
    await tester.pumpAndSettle();

    expect(find.text(_kMissingReason), findsOneWidget);
    expect(
      result,
      same(EndorseChoice.clear),
      reason: 'the dialog must still be open, having resolved with nothing',
    );
  });

  testWidgets('agency plus reason resolves, trimmed', (tester) async {
    EndorseChoice? result;
    await _open(tester, (r) => result = r);

    await tester.tap(find.text('DENR').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      _reasonField(),
      '  Illegal quarrying on a protected riverbank.  ',
    );
    await tester.pumpAndSettle();

    await tester.tap(_sendButton());
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.agency, 'DENR');
    // Trimmed — trailing whitespace would otherwise be typeset into the letter.
    expect(result!.reason, 'Illegal quarrying on a protected riverbank.');
    expect(result!.isClear, isFalse);
  });

  testWidgets('the error clears as soon as the admin starts typing',
      (tester) async {
    await _open(tester, (_) {});

    await tester.tap(find.text('PNP Aparri').first);
    await tester.pumpAndSettle();
    await tester.tap(_sendButton());
    await tester.pumpAndSettle();
    expect(find.text(_kMissingReason), findsOneWidget);

    await tester.enterText(_reasonField(), 'Peace and order matter.');
    await tester.pumpAndSettle();
    expect(find.text(_kMissingReason), findsNothing);
  });

  testWidgets('whitespace is not a reason', (tester) async {
    EndorseChoice? result;
    await _open(tester, (r) => result = r);

    await tester.tap(find.text('DOH').first);
    await tester.pumpAndSettle();
    await tester.enterText(_reasonField(), '     ');
    await tester.pumpAndSettle();

    await tester.tap(_sendButton());
    await tester.pumpAndSettle();

    expect(find.text(_kMissingReason), findsOneWidget);
    expect(result, isNull);
  });

  // ── CHANGED 2026-08-29 ──────────────────────────────────────────────────
  // This used to assert that clearing needed NO reason. Withdrawing voids a
  // signed letter and revokes the agency's credential — the same decision as
  // endorsing, in reverse — and it was leaving no record of who or why, while
  // endorsing has demanded a written justification since 20260801000000. The
  // reason is now recorded on the endorsement event log
  // (migration 20260829000002).
  testWidgets('withdrawing asks for a reason before it resolves',
      (tester) async {
    EndorseChoice? result;
    await _open(tester, (r) => result = r, current: 'DPWH');

    await tester.tap(find.text('Clear endorsement'));
    await tester.pumpAndSettle();

    // The dialog must not have resolved yet — a confirmation stands in between.
    expect(result, isNull,
        reason: 'withdrawing must not fire on the first tap');
    expect(find.text('Withdraw this endorsement'), findsOneWidget);

    // An empty reason is refused, the same way an empty endorsement reason is.
    await tester.tap(find.text('Withdraw'));
    await tester.pumpAndSettle();
    expect(result, isNull, reason: 'a blank reason must not withdraw');

    await tester.enterText(
      find.byType(TextField).last,
      'DPWH confirmed the road is municipal after all.',
    );
    await tester.tap(find.text('Withdraw'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.isClear, isTrue);
    expect(result!.reason, 'DPWH confirmed the road is municipal after all.');
  });

  testWidgets('cancelling returns nothing, so nothing is endorsed',
      (tester) async {
    EndorseChoice? result = EndorseChoice.clear;
    await _open(tester, (r) => result = r);

    await tester.tap(find.text('BFP Aparri').first);
    await tester.pumpAndSettle();
    await tester.enterText(_reasonField(), 'Fire safety inspection needed.');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });

  group('lays out at every width', () {
    for (final w in [1200.0, 700.0, 420.0, 360.0]) {
      testWidgets('${w.toInt()}px', (tester) async {
        tester.view.physicalSize = Size(w, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await _open(tester, (_) {});
        expect(tester.takeException(), isNull);
        // The reason field is required, so it must be reachable at any width.
        expect(find.text('Reason for endorsement'), findsOneWidget);
        expect(_sendButton(), findsOneWidget);
      });
    }
  });

  // ── Scan route parsing ────────────────────────────────────────────────────
  // The token comes off a URL a phone camera resolved, so it arrives with
  // whatever a scanner or share sheet decided to append. Parsing lives in
  // app_router because main() needs it before the app is built.
  group('scanTokenFrom', () {
    test('reads the token out of a scan route', () {
      expect(scanTokenFrom('/scan/abc123'), 'abc123');
    });

    test('tolerates a trailing slash and a query string', () {
      expect(scanTokenFrom('/scan/abc123/'), 'abc123');
      expect(scanTokenFrom('/scan/abc123?utm=qr'), 'abc123');
    });

    test('keeps base64url punctuation intact', () {
      // A real token is 43 base64url chars; - and _ are part of the alphabet
      // and stripping them would silently invalidate one scan in eight.
      expect(scanTokenFrom('/scan/a-b_c123'), 'a-b_c123');
    });

    test('is null for every non-scan route', () {
      for (final r in const [null, '/', '/login', '/guest', '/newsfeed',
        '/report_detail', '/scan', '/scan/', '/scanner/x']) {
        expect(scanTokenFrom(r), isNull, reason: 'should not match $r');
      }
    });
  });
}
