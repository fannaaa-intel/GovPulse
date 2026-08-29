// The public /scan/<token> page — what an agency officer with no account sees.
//
// Every case here is driven through a MOCK HTTP CLIENT handed to Supabase,
// because the page's whole behaviour is a function of what `scan_endorsement`
// returns and there is no other way to reach those branches offline. The mock
// answers the read RPC with a chosen lifecycle state and fails the write RPCs,
// which is also how the error copy gets exercised.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/scan/scan_page.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '_responsive_matrix.dart';

/// Answers the page's two RPCs. [state] drives `scan_endorsement`; the write
/// RPCs return [writeError] so the recoverable-error paths are reachable.
class _MockApi extends http.BaseClient {
  final String state;
  final Map<String, dynamic> writeError;
  final bool valid;

  _MockApi(
    this.state, {
    this.writeError = const {
      'ok': false,
      'error': 'bad_pin',
      'attempts_left': 3,
    },
    this.valid = true,
  });

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final Object body;
    if (request.url.path.endsWith('/scan_endorsement')) {
      body = valid
          ? {
              'valid': true,
              'reference': 'END-3F2A1B6C',
              'agency': 'DPWH',
              'reason': 'National road outside municipal authority.',
              'state': state,
              'endorsed_at': '2026-08-29T08:54:00Z',
              'received_at':
                  state == 'endorsed' ? null : '2026-08-29T10:12:00Z',
              'completed_at':
                  state == 'completed' ? '2026-08-30T14:03:00Z' : null,
              'locked': false,
              'report': {
                'category': 'Road & Infrastructure',
                'barangay': 'Macanaya',
                'address': 'Near Lyceum of Aparri',
                'description': 'Large pothole across both lanes.',
                'reported_at': '2026-08-29T08:54:00Z',
              },
            }
          : {'valid': false};
    } else {
      body = writeError;
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      200,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }
}

/// Supabase is a singleton, so each case disposes and re-initialises it with
/// its own mock rather than trying to swap the client underneath.
Future<void> _boot(_MockApi api) async {
  try {
    await Supabase.instance.dispose();
  } catch (_) {
    // Not initialized yet on the first call.
  }
  await Supabase.initialize(
    url: 'https://preview.invalid',
    anonKey: 'test-not-a-real-key',
    httpClient: api,
    authOptions: const FlutterAuthClientOptions(
      localStorage: EmptyLocalStorage(),
      detectSessionInUri: false,
      // Off, or the SDK starts a periodic refresh timer inside the test body
      // and the binding fails every test with "Pending timers". Nobody signs
      // in here, so there is nothing to refresh anyway.
      autoRefreshToken: false,
    ),
    debug: false,
  );
}

Widget _host() => const MaterialApp(home: ScanPage(token: 'tok'));

/// Scrolls [finder] into view before tapping it.
///
/// The page is a tall single column and the default test window is 800x600, so
/// "Post update" sits well below the fold — a bare tap() lands outside the
/// render tree and silently does nothing (it warns, it does not fail, which is
/// how the first draft of these tests "passed" a button it never pressed).
Future<void> _tapAfterScroll(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Supabase.initialize starts a periodic token-refresh timer. The test
  // binding fails any test that ends with one pending — which is every test
  // here, since each boots its own client. Disposing in teardown cancels it.
  tearDown(() async {
    try {
      await Supabase.instance.dispose();
    } catch (_) {
      // Already disposed, or never initialized.
    }
  });

  group('the update composer appears only where it can be used', () {
    testWidgets('not before the agency has confirmed receipt', (tester) async {
      await _boot(_MockApi('endorsed'));
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      expect(find.text('Confirm Received'), findsOneWidget);
      expect(find.text('Post a progress update'), findsNothing,
          reason: 'nothing has happened yet to report on');
    });

    testWidgets('yes once received — the window where work happens',
        (tester) async {
      await _boot(_MockApi('received'));
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      expect(find.text('Post a progress update'), findsOneWidget);
      expect(find.text('Mark Completed'), findsOneWidget);
    });

    testWidgets('not after completion', (tester) async {
      await _boot(_MockApi('completed'));
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      expect(find.text('Post a progress update'), findsNothing);
      expect(
        find.textContaining('already completed'),
        findsOneWidget,
      );
    });
  });

  // The state the LGU sets by taking the report back. Unreachable from this
  // page — the token is rotated — but a page already open will see it on
  // refresh and must not offer a button that cannot work.
  testWidgets('a withdrawn endorsement says so and offers nothing',
      (tester) async {
    await _boot(_MockApi('withdrawn'));
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.textContaining('taken this report back'), findsOneWidget);
    expect(find.text('Confirm Received'), findsNothing);
    expect(find.text('Mark Completed'), findsNothing);
    expect(find.text('Post a progress update'), findsNothing);
  });

  testWidgets('an invalid token replaces the whole page', (tester) async {
    await _boot(_MockApi('endorsed', valid: false));
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.text('This code is not valid'), findsOneWidget);
    expect(find.text('Confirm Received'), findsNothing);
  });

  group('posting an update', () {
    testWidgets('refuses an empty body before spending a request',
        (tester) async {
      await _boot(_MockApi('received'));
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      await _tapAfterScroll(tester, find.text('Post update'));

      expect(find.text('Write what has happened before posting.'),
          findsOneWidget);
    });

    testWidgets('refuses a body with no PIN', (tester) async {
      await _boot(_MockApi('received'));
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('scan-update-body')),
        'Crew inspected the site today.',
      );
      await _tapAfterScroll(tester, find.text('Post update'));

      expect(find.text('Enter your 4-digit PIN to post an update.'),
          findsOneWidget);
    });

    testWidgets('surfaces a wrong PIN with the attempts remaining',
        (tester) async {
      await _boot(_MockApi('received'));
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      // By key, not by position: the composer sits ABOVE the action card in
      // the received state (the irreversible button must not come first), so
      // "first" and "last" do not mean what they look like.
      await tester.enterText(
          find.byKey(const Key('scan-update-body')), 'Crew inspected today.');
      await tester.enterText(find.byKey(const Key('scan-update-pin')), '1111');
      await _tapAfterScroll(tester, find.text('Post update'));

      expect(find.textContaining('3 attempts remaining'), findsOneWidget);
    });

    testWidgets('a rate-limited agency is told to come back later',
        (tester) async {
      await _boot(_MockApi('received',
          writeError: const {'ok': false, 'error': 'rate_limited'}));
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('scan-update-body')), 'Another update.');
      await tester.enterText(find.byKey(const Key('scan-update-pin')), '4821');
      await _tapAfterScroll(tester, find.text('Post update'));

      expect(find.textContaining('lot of updates in one hour'), findsOneWidget);
    });
  });

  // The page is opened on a phone held in one hand, outdoors, essentially
  // always — and now carries a three-step tracker, two PIN fields and a
  // multiline composer that did not exist before.
  group('lays out on every phone', () {
    for (final state in ['endorsed', 'received', 'completed', 'withdrawn']) {
      for (final device in kAllPhones) {
        testWidgets('$state at $device', (tester) async {
          await _boot(_MockApi(state));
          final overflows = await pumpAt(tester, device, _host);
          expect(overflows, isEmpty, reason: overflows.join('\n'));
        });
      }
    }
  });

  testWidgets('survives a large text scale on the smallest phone',
      (tester) async {
    await _boot(_MockApi('received'));
    final overflows =
        await pumpAt(tester, kSmallPhone, _host, textScale: 1.6);
    expect(overflows, isEmpty, reason: overflows.join('\n'));
  });
}
