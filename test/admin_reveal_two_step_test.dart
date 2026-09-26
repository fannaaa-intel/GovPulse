// Two-step anonymous reveal: password + reason → emailed code → identity.
//
// Drives the real RevealableSubmitter through every server answer with a fake
// RevealApi (no backend), and sweeps both steps across phone sizes (bottom
// sheet) and web widths (dialog) at 1.0x and 1.3x text for overflow.
//
// The server-side guarantees (reveal RPC not callable from the app, lockout
// after 5 failures, audit rows) live in reveal-identity + migration
// 20260927000000 and are verified against the live project, not here.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/admin/providers/admin_identity_reveal_provider.dart';
import 'package:govpulse/features/admin/widgets/revealable_submitter.dart';

import '_responsive_matrix.dart';

const _identity = RevealedIdentity(
  userId: 'u-1',
  name: 'Juan Dela Cruz',
  phone: '09171234567',
);

/// Records calls and answers with whatever the test queued.
class _FakeServer {
  final sendAnswers = <Object>[]; // String (masked email) or RevealException
  final revealAnswers = <Object>[]; // RevealedIdentity or RevealException
  final sent = <String>[];
  final reveals = <Map<String, String>>[];

  RevealApi get api => RevealApi(
    sendCode: ({required String password, String? actorName}) async {
      sent.add(password);
      final a = sendAnswers.isEmpty
          ? 'r•••@gmail.com'
          : sendAnswers.removeAt(0);
      if (a is RevealException) throw a;
      return a as String;
    },
    reveal:
        ({
          required RevealSource source,
          required String submissionId,
          required String password,
          required String reason,
          required String code,
          String? actorName,
        }) async {
          reveals.add({
            'source': source.name,
            'id': submissionId,
            'password': password,
            'reason': reason,
            'code': code,
          });
          final a = revealAnswers.isEmpty
              ? _identity
              : revealAnswers.removeAt(0);
          if (a is RevealException) throw a;
          return a as RevealedIdentity;
        },
  );
}

Widget _app(
  _FakeServer server, {
  bool isAnonymous = true,
  bool fullAdmin = true,
}) => ProviderScope(
  overrides: [
    revealApiProvider.overrideWithValue(server.api),
    currentAdminIsFullAdminProvider.overrideWith((ref) async => fullAdmin),
  ],
  child: MaterialApp(
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: RevealableSubmitter(
          source: RevealSource.report,
          submissionId: '11111111-2222-3333-4444-555555555555',
          isAnonymous: isAnonymous,
          name: 'Named Person',
          subject: 'reporter',
        ),
      ),
    ),
  ),
);

Finder _field(String label) => find.widgetWithText(TextField, label);

Future<void> _openForm(WidgetTester t) async {
  await t.tap(find.text('Reveal reporter identity'));
  await t.pumpAndSettle();
}

Future<void> _fillStepOne(
  WidgetTester t, {
  String password = 'secret123',
  String reason = 'Threat to staff',
}) async {
  await t.enterText(_field('Your account password'), password);
  await t.enterText(_field('Reason (recorded in the log)'), reason);
}

Future<void> _toStepTwo(WidgetTester t) async {
  await _fillStepOne(t);
  await t.tap(find.text('Send code'));
  await t.pumpAndSettle();
}

void main() {
  group('gating (regression)', () {
    testWidgets('named submission shows the name and no reveal button', (
      t,
    ) async {
      await t.pumpWidget(_app(_FakeServer(), isAnonymous: false));
      await t.pumpAndSettle();
      expect(find.text('Named Person'), findsOneWidget);
      expect(find.text('Reveal reporter identity'), findsNothing);
    });

    testWidgets('staff (not full admin) never sees the reveal button', (
      t,
    ) async {
      await t.pumpWidget(_app(_FakeServer(), fullAdmin: false));
      await t.pumpAndSettle();
      expect(find.text('Reveal reporter identity'), findsNothing);
    });

    testWidgets(
      'full admin sees the reveal button on an anonymous submission',
      (t) async {
        await t.pumpWidget(_app(_FakeServer()));
        await t.pumpAndSettle();
        expect(find.text('Reveal reporter identity'), findsOneWidget);
      },
    );
  });

  group('step one', () {
    testWidgets('empty password names the field and sends nothing', (t) async {
      final s = _FakeServer();
      await t.pumpWidget(_app(s));
      await t.pumpAndSettle();
      await _openForm(t);
      expect(find.text('Step 1 of 2'), findsOneWidget);
      await t.tap(find.text('Send code'));
      await t.pump();
      expect(find.text('Enter your account password.'), findsOneWidget);
      expect(s.sent, isEmpty);
    });

    testWidgets('missing reason names the field and sends nothing', (t) async {
      final s = _FakeServer();
      await t.pumpWidget(_app(s));
      await t.pumpAndSettle();
      await _openForm(t);
      await _fillStepOne(t, reason: '');
      await t.tap(find.text('Send code'));
      await t.pump();
      expect(
        find.text('Give a reason for revealing this identity.'),
        findsOneWidget,
      );
      expect(s.sent, isEmpty);
    });

    testWidgets('wrong password stays on step one with the server message', (
      t,
    ) async {
      final s = _FakeServer()
        ..sendAnswers.add(
          const RevealException(
            'bad_password',
            'Incorrect password. Please try again.',
          ),
        );
      await t.pumpWidget(_app(s));
      await t.pumpAndSettle();
      await _openForm(t);
      await _fillStepOne(t);
      await t.tap(find.text('Send code'));
      await t.pumpAndSettle();
      expect(
        find.text('Incorrect password. Please try again.'),
        findsOneWidget,
      );
      expect(find.text('Step 1 of 2'), findsOneWidget);
    });

    testWidgets('locked out shows the lock message', (t) async {
      final s = _FakeServer()
        ..sendAnswers.add(
          const RevealException(
            'locked',
            'Too many failed attempts. Reveal is locked for 15 minutes.',
          ),
        );
      await t.pumpWidget(_app(s));
      await t.pumpAndSettle();
      await _openForm(t);
      await _fillStepOne(t);
      await t.tap(find.text('Send code'));
      await t.pumpAndSettle();
      expect(find.textContaining('locked for 15 minutes'), findsOneWidget);
    });
  });

  group('step two', () {
    testWidgets('good password moves to the code step and names the inbox', (
      t,
    ) async {
      final s = _FakeServer();
      await t.pumpWidget(_app(s));
      await t.pumpAndSettle();
      await _openForm(t);
      await _toStepTwo(t);
      expect(s.sent, ['secret123']);
      expect(find.text('Step 2 of 2'), findsOneWidget);
      expect(find.textContaining('r•••@gmail.com'), findsOneWidget);
      expect(find.text('Reveal'), findsOneWidget);
    });

    testWidgets('short code names the field and does not call the server', (
      t,
    ) async {
      final s = _FakeServer();
      await t.pumpWidget(_app(s));
      await t.pumpAndSettle();
      await _openForm(t);
      await _toStepTwo(t);
      await t.enterText(_field('Code from your email'), '123');
      await t.tap(find.text('Reveal'));
      await t.pump();
      expect(find.text('Enter the code from your email.'), findsOneWidget);
      expect(s.reveals, isEmpty);
    });

    testWidgets('wrong code stays on step two so a new code can be entered', (
      t,
    ) async {
      final s = _FakeServer()
        ..revealAnswers.add(
          const RevealException(
            'bad_code',
            'Incorrect or expired code. Request a new one.',
          ),
        );
      await t.pumpWidget(_app(s));
      await t.pumpAndSettle();
      await _openForm(t);
      await _toStepTwo(t);
      await t.enterText(_field('Code from your email'), '000000');
      await t.tap(find.text('Reveal'));
      await t.pumpAndSettle();
      expect(
        find.text('Incorrect or expired code. Request a new one.'),
        findsOneWidget,
      );
      expect(find.text('Step 2 of 2'), findsOneWidget);
    });

    testWidgets(
      'password rejected at reveal sends the admin back to step one',
      (t) async {
        final s = _FakeServer()
          ..revealAnswers.add(
            const RevealException(
              'bad_password',
              'Incorrect password. Please start again.',
            ),
          );
        await t.pumpWidget(_app(s));
        await t.pumpAndSettle();
        await _openForm(t);
        await _toStepTwo(t);
        await t.enterText(_field('Code from your email'), '123456');
        await t.tap(find.text('Reveal'));
        await t.pumpAndSettle();
        expect(find.text('Step 1 of 2'), findsOneWidget);
        expect(
          find.text('Incorrect password. Please start again.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('Resend code asks the server again', (t) async {
      final s = _FakeServer();
      await t.pumpWidget(_app(s));
      await t.pumpAndSettle();
      await _openForm(t);
      await _toStepTwo(t);
      await t.tap(find.text('Resend code'));
      await t.pumpAndSettle();
      expect(s.sent.length, 2);
      expect(find.text('Step 2 of 2'), findsOneWidget);
    });

    testWidgets('Back returns to step one', (t) async {
      await t.pumpWidget(_app(_FakeServer()));
      await t.pumpAndSettle();
      await _openForm(t);
      await _toStepTwo(t);
      await t.tap(find.text('Back'));
      await t.pumpAndSettle();
      expect(find.text('Step 1 of 2'), findsOneWidget);
    });

    testWidgets('correct code reveals the identity and sends everything once', (
      t,
    ) async {
      final s = _FakeServer();
      await t.pumpWidget(_app(s));
      await t.pumpAndSettle();
      await _openForm(t);
      await _toStepTwo(t);
      await t.enterText(_field('Code from your email'), '482913');
      await t.tap(find.text('Reveal'));
      await t.pumpAndSettle();
      expect(s.reveals, [
        {
          'source': 'report',
          'id': '11111111-2222-3333-4444-555555555555',
          'password': 'secret123',
          'reason': 'Threat to staff',
          'code': '482913',
        },
      ]);
      expect(find.text('Juan Dela Cruz'), findsOneWidget);
      expect(find.text('09171234567'), findsOneWidget);
      expect(find.text('Step 2 of 2'), findsNothing); // form closed
      // Let the success snackbar finish.
      await t.pump(const Duration(seconds: 5));
    });
  });

  group('responsive: no overflow on either step', () {
    const web = [
      Device('web narrow', Size(700, 800)),
      Device('web laptop', Size(1280, 800)),
      Device('web wide', Size(1920, 1080)),
    ];
    final devices = [...kAllPhones, kTablet, ...web];

    for (final d in devices) {
      for (final scale in const [1.0, 1.3]) {
        testWidgets('$d @${scale}x', (t) async {
          final errors = await pumpAt(
            t,
            d,
            () => _app(_FakeServer()),
            textScale: scale,
            after: (t) async {
              await _openForm(t);
              // Show the error row too, so the densest step-one layout is measured.
              await t.tap(find.text('Send code'));
              await t.pump();
              await _toStepTwo(t);
              await t.enterText(_field('Code from your email'), '1');
              await t.tap(find.text('Reveal'));
              await t.pump();
            },
          );
          expect(errors, isEmpty, reason: errors.join('\n'));
          expect(find.text('Step 2 of 2'), findsOneWidget);
        });
      }
    }
  });
}
