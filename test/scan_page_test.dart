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

  /// What the citizen attached: 'none', 'photos', 'video' (a video and nothing
  /// else) or 'mixed'.
  final String media;

  _MockApi(
    this.state, {
    this.writeError = const {
      'ok': false,
      'error': 'bad_pin',
      'attempts_left': 3,
    },
    this.valid = true,
    this.media = 'none',
  });

  List<Map<String, String>> get _mediaRows {
    switch (media) {
      case 'photos':
        return const [
          {'path': 'reports/r1/a.jpg', 'kind': 'photo'},
          {'path': 'reports/r1/b.jpg', 'kind': 'photo'},
        ];
      case 'video':
        return const [
          {'path': 'reports/r1/clip.mp4', 'kind': 'video'},
        ];
      case 'mixed':
        return const [
          {'path': 'reports/r1/a.jpg', 'kind': 'photo'},
          {'path': 'reports/r1/clip.mp4', 'kind': 'video'},
        ];
      default:
        return const [];
    }
  }

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
                'media': _mediaRows,
              },
            }
          : {'valid': false};
    } else if (request.url.path.contains('scan-endorsement-media')) {
      body = {
        'ok': true,
        'photos': [
          for (final m in _mediaRows)
            {
              'path': m['path'],
              'url': 'https://signed.invalid/${m['path']}',
            },
        ],
      };
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

  // ── Completing is two presses ────────────────────────────────────────────
  //
  // It used to be one, with nothing but a PIN, which left the resident with a
  // status change and no account of what was actually done — and, because §11
  // of migration 20260829000001 keys the completion gallery on an APPROVED
  // completion update existing, no photographs either. The agency path created
  // no such update, so an agency completion published a resolved report with
  // nothing attached to it at all.
  group('marking completed', () {
    testWidgets('the first press opens a form rather than completing',
        (tester) async {
      await _boot(_MockApi('received'));
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      // Before: an invitation, not a form.
      expect(find.text('Mark Completed'), findsOneWidget);
      expect(find.text('Record the completed work'), findsNothing);

      await _tapAfterScroll(tester, find.text('Mark Completed'));

      // After: the account is asked for, and the button that actually commits
      // is a DIFFERENT one, so the press that opened the form cannot also have
      // sent it.
      expect(find.text('Record the completed work'), findsOneWidget);
      expect(find.byKey(const Key('scan-completion-body')), findsOneWidget);
      expect(find.text('Submit & Complete'), findsOneWidget);
      expect(find.text('Mark Completed'), findsNothing);
    });

    testWidgets('a completion with no note is refused before the PIN is spent',
        (tester) async {
      // The mock answers every write with bad_pin. If the client let this
      // through, the assertion below would find the PIN message instead — which
      // is exactly the bug: a missing note is the officer's omission, not a bad
      // credential, and must not consume one of their five attempts.
      await _boot(_MockApi('received'));
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      await _tapAfterScroll(tester, find.text('Mark Completed'));
      await tester.enterText(find.byKey(const Key('scan-confirm-pin')), '1234');
      await tester.pumpAndSettle();
      await _tapAfterScroll(tester, find.text('Submit & Complete'));

      expect(
        find.textContaining('Describe what was done'),
        findsWidgets,
        reason: 'the note must be demanded before the PIN is checked',
      );
      expect(find.textContaining('not correct'), findsNothing);
    });

    testWidgets('there is a way back out of the completion step',
        (tester) async {
      await _boot(_MockApi('received'));
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      await _tapAfterScroll(tester, find.text('Mark Completed'));
      expect(find.text('Submit & Complete'), findsOneWidget);

      // Nothing has been sent at this point, so leaving must cost the officer
      // only what they typed. A two-step form with no exit is a trap.
      await _tapAfterScroll(tester, find.text('Not yet — go back'));
      expect(find.text('Mark Completed'), findsOneWidget);
      expect(find.text('Submit & Complete'), findsNothing);
    });

    testWidgets('the completion form offers photos', (tester) async {
      await _boot(_MockApi('received'));
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      await _tapAfterScroll(tester, find.text('Mark Completed'));
      expect(
        find.textContaining('PHOTOS OF THE COMPLETED WORK'),
        findsOneWidget,
      );
      // Two pickers on the page now: the progress composer's and this one.
      expect(find.text('Add photos'), findsNWidgets(2));
    });
  });

  // ── The detail card's information design ─────────────────────────────────
  group('the report facts are grouped, not listed flat', () {
    testWidgets('the milestones read as a dated sequence', (tester) async {
      await _boot(_MockApi('received'));
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      // Reported → Endorsed → Received is ONE sequence. As four identical
      // label/value rows that was invisible; as dated steps it answers "how
      // long has this been sitting with us" at a glance.
      expect(find.text('Reported by resident'), findsOneWidget);
      expect(find.text('Endorsed to DPWH'), findsOneWidget);
      expect(find.text('Receipt confirmed'), findsOneWidget);

      // A milestone that has not happened is ABSENT, not rendered as "—".
      // Placeholder rows for the future are noise on a phone held outdoors.
      expect(find.text('Work completed'), findsNothing);
    });

    testWidgets('completion joins the sequence once it happens',
        (tester) async {
      await _boot(_MockApi('completed'));
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      expect(find.text('Work completed'), findsOneWidget);
    });

    testWidgets('the milestones are actually JOINED by a rail', (tester) async {
      // ⚠ The connector between the dots silently collapsed to zero height in
      // the first draft: an `Expanded` inside a bare Column has nothing bounded
      // to expand into, so the line rendered at 0px and the dots floated
      // unconnected. Nothing errored, nothing overflowed, and the analyzer was
      // perfectly happy — only a screenshot caught it.
      //
      // Measuring the painted height is what makes this test worth having;
      // asserting the widget merely EXISTS would have passed on the broken
      // version too.
      await _boot(_MockApi('completed'));
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      final connectors = tester
          .widgetList<ColoredBox>(find.byType(ColoredBox))
          .where((b) => b.color == const Color(0xFFA7F3D0))
          .toList();
      expect(
        connectors,
        isNotEmpty,
        reason: 'the timeline should draw connectors between its dots',
      );

      final heights = find
          .byWidgetPredicate((w) =>
              w is ColoredBox && w.color == const Color(0xFFA7F3D0))
          .evaluate()
          .map((e) => e.renderObject! as RenderBox)
          .map((r) => r.size.height)
          .toList();
      expect(
        heights.every((h) => h > 0),
        isTrue,
        reason: 'a connector collapsed to zero height: $heights',
      );
    });

    testWidgets('the location is lifted out of the timestamp rows',
        (tester) async {
      await _boot(_MockApi('received'));
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      // It is the one fact the officer has to ACT on — they are standing in
      // the street looking for the place — and the one that wraps to several
      // lines. Sharing a 116px label column with four dates made the longest
      // and most useful value the most cramped.
      expect(find.text('LOCATION'), findsOneWidget);
      expect(
        find.textContaining('Near Lyceum of Aparri'),
        findsOneWidget,
      );
    });
  });

  // ── Ranking the two actions ──────────────────────────────────────────────
  group('only one action is a filled button at a time', () {
    testWidgets('the completion opener is outlined, the composer is filled',
        (tester) async {
      await _boot(_MockApi('received'));
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      // "Mark Completed" only OPENS the form here; a solid green button gave
      // the page two equally loud primaries competing for the same attention,
      // when one is done many times and the other once, irreversibly.
      expect(
        find.widgetWithText(OutlinedButton, 'Mark Completed'),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Post update'), findsOneWidget);
    });

    testWidgets('the solid green is spent on the press that actually commits',
        (tester) async {
      await _boot(_MockApi('received'));
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      await _tapAfterScroll(tester, find.text('Mark Completed'));

      expect(
        find.widgetWithText(FilledButton, 'Submit & Complete'),
        findsOneWidget,
      );
    });
  });

  testWidgets('a completed report does not congratulate itself twice',
      (tester) async {
    // Two green panels used to stack the moment an officer completed: the
    // "Recorded…" banner AND the "already completed" card, saying the same
    // thing in different words.
    await _boot(_MockApi('completed'));
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    // On a LATER scan (nothing just advanced) the standing notice is the only
    // one, and it must still be there — it is the whole answer to "what do I
    // do now".
    expect(find.textContaining('already completed'), findsOneWidget);
    expect(find.textContaining('now marked completed'), findsNothing);
  });

  // Migration 20260829000001 §10 concluded "an agency update is text only",
  // reasoning from the credential rather than from the need. The agency is the
  // party standing at the site with a phone; theirs is the update that most
  // needs a photograph. Uploads now go through an Edge Function that re-checks
  // the PIN, so the account is no longer what gates them.
  testWidgets('the progress composer offers photos too', (tester) async {
    await _boot(_MockApi('received'));
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.text('Post a progress update'), findsOneWidget);
    expect(find.text('PHOTOS (OPTIONAL)'), findsOneWidget);
  });

  // The page is opened on a phone held in one hand, outdoors, essentially
  // always — and now carries a three-step tracker, two PIN fields, two photo
  // pickers and a multiline composer that did not exist before.
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

  // ⚠ The matrix above never sees the completion form: it renders only in the
  // `received` state and only after a tap, so a page pumped and measured
  // straight away is measuring the collapsed card. That is the newest and
  // densest layout on this page — a 5-line field, a photo picker, a PIN box and
  // two buttons — and it is exactly the one most likely to overflow.
  group('the expanded completion form lays out too', () {
    for (final device in kAllPhones) {
      testWidgets('at $device', (tester) async {
        await _boot(_MockApi('received'));
        final overflows = await pumpAt(
          tester,
          device,
          _host,
          after: (t) async {
            await t.ensureVisible(find.text('Mark Completed'));
            await t.pumpAndSettle();
            await t.tap(find.text('Mark Completed'));
            await t.pumpAndSettle();
          },
        );
        expect(overflows, isEmpty, reason: overflows.join('\n'));
      });
    }
  });

  group('the citizen\'s attachments', () {
    // The agency officer is the party standing at the site. Until this existed
    // they got the report in words only - and a report whose only evidence is a
    // clip of moving floodwater reached them looking like a report with no
    // evidence at all.
    //
    // ⚠ The STRIP itself cannot be driven from a widget test: functions.invoke
    // decodes its response inside a YAJsonIsolate, which does not run under
    // flutter_test's fake async, so the signing call never completes here no
    // matter how long the test pumps. (Confirmed by logging every url the mock
    // client saw: only the scan_endorsement RPC ever arrives.) The join is
    // therefore tested directly through joinScanMedia, and the rendered strip
    // was verified by screenshot - tool/preview_scan_page.dart ?media=.

    testWidgets('no attachments renders no strip at all', (tester) async {
      await _boot(_MockApi('endorsed', media: 'none'));
      await tester.pumpWidget(_host());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Attached by the resident'), findsNothing,
          reason: 'an empty heading is worse than no heading');
    });

    testWidgets('attachments announce themselves while loading',
        (tester) async {
      // The heading and its shimmer appear as soon as the RPC says media
      // exists, before the signing call returns - so the strip holds its space
      // instead of appearing suddenly and pushing the PIN field under the
      // officer's thumb.
      await _boot(_MockApi('endorsed', media: 'photos'));
      await tester.pumpWidget(_host());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Attached by the resident'), findsOneWidget);
    });

    group('joinScanMedia', () {
      test('pairs each attachment with its signed url', () {
        final out = joinScanMedia(
          const [
            {'path': 'reports/r1/a.jpg', 'kind': 'photo'},
            {'path': 'reports/r1/clip.mp4', 'kind': 'video'},
          ],
          const {
            'ok': true,
            'photos': [
              {'path': 'reports/r1/a.jpg', 'url': 'https://s/a'},
              {'path': 'reports/r1/clip.mp4', 'url': 'https://s/c'},
            ],
          },
        );

        expect(out, hasLength(2));
        expect(out[0].isVideo, isFalse);
        expect(out[0].url, 'https://s/a');
        expect(out[1].isVideo, isTrue,
            reason: 'the video must survive the join, not be filtered out');
      });

      test('a video-only report still yields an attachment', () {
        // The case that motivated including videos at all. There is no
        // thumbnail stored for one, so the easy implementation drops them -
        // and the report then reaches the agency looking like it has no
        // evidence attached.
        final out = joinScanMedia(
          const [
            {'path': 'reports/r1/clip.mp4', 'kind': 'video'}
          ],
          const {
            'ok': true,
            'photos': [
              {'path': 'reports/r1/clip.mp4', 'url': 'https://s/c'}
            ],
          },
        );

        expect(out, hasLength(1));
        expect(out.single.isVideo, isTrue);
      });

      test('urls are matched by path, never by position', () {
        // A reordered signing response must not pair a url with the wrong
        // attachment - the same failure AdminReportsNotifier.fetchMedia was
        // fixed for.
        final out = joinScanMedia(
          const [
            {'path': 'a', 'kind': 'photo'},
            {'path': 'b', 'kind': 'photo'},
          ],
          const {
            'photos': [
              {'path': 'b', 'url': 'https://s/B'},
              {'path': 'a', 'url': 'https://s/A'},
            ],
          },
        );

        expect(out[0].path, 'a');
        expect(out[0].url, 'https://s/A');
        expect(out[1].url, 'https://s/B');
      });

      test('an object that failed to sign is dropped, not shown broken', () {
        final out = joinScanMedia(
          const [
            {'path': 'a', 'kind': 'photo'},
            {'path': 'b', 'kind': 'photo'},
          ],
          const {
            'photos': [
              {'path': 'a', 'url': 'https://s/A'}
            ],
          },
        );

        expect(out, hasLength(1));
        expect(out.single.path, 'a');
      });

      test('a failed response yields nothing rather than throwing', () {
        expect(
          joinScanMedia(
            const [
              {'path': 'a', 'kind': 'photo'}
            ],
            const {'ok': false, 'error': 'server_error'},
          ),
          isEmpty,
        );
        expect(joinScanMedia(const [], null), isEmpty);
      });

      test('malformed rows are skipped', () {
        final out = joinScanMedia(
          const [
            'not a map',
            {'kind': 'photo'},
            {'path': 'a', 'kind': 'photo'},
          ],
          const {
            'photos': [
              {'path': 'a', 'url': 'https://s/A'}
            ],
          },
        );

        expect(out, hasLength(1));
      });
    });
  });


  group('phone goes edge to edge, desktop keeps the card', () {
    // On a 360px phone the card layout spent ~36px per side on chrome carrying
    // no information: scroll padding, a border, and the card's own inset, with
    // grey canvas showing either side of a white sheet that filled the screen
    // anyway. This page is opened by a phone camera at a roadside essentially
    // always, so that is the ordinary case, not the exception.

    Future<void> pumpAt(WidgetTester tester, double width) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await _boot(_MockApi('endorsed'));
      await tester.pumpWidget(_host());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    /// The surface a content section is drawn on.
    BoxDecoration shellDecoration(WidgetTester tester) {
      // The first Container whose decoration is a white BoxDecoration is a
      // content shell; the scaffold above it paints through its own property.
      final containers = tester.widgetList<Container>(find.byType(Container));
      for (final c in containers) {
        final d = c.decoration;
        if (d is BoxDecoration && d.color == Colors.white) return d;
      }
      fail('no white content surface found');
    }

    testWidgets('a phone draws no rounded card border', (tester) async {
      await pumpAt(tester, 390);
      final d = shellDecoration(tester);

      expect(d.borderRadius, isNull,
          reason: 'a full-bleed surface with a radius shows canvas in the '
              'corners');
      // A full border on a full-bleed surface draws a line down the very edge
      // of the screen, which reads as a rendering fault.
      expect(d.border, isA<Border>().having((b) => b.left, 'left side',
          BorderSide.none));
    });

    testWidgets('a desktop keeps the rounded bordered card', (tester) async {
      await pumpAt(tester, 1100);
      final d = shellDecoration(tester);

      expect(d.borderRadius, isNotNull);
      expect(d.border, isNotNull);
    });

    testWidgets('the scaffold is white on a phone, grey on a desktop',
        (tester) async {
      // The cards ARE the page on a phone, so a grey scaffold would show only
      // as a seam wherever content stops short of the fold.
      await pumpAt(tester, 390);
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        Colors.white,
      );

      await pumpAt(tester, 1100);
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        isNot(Colors.white),
      );
    });

    testWidgets('the phone layout starts at the top, not vertically centred',
        (tester) async {
      // Center on a child taller than the viewport pushes the top of the page
      // off the top of the scroll view: the letterhead ends up below a band of
      // empty white and the officer has to scroll UP to find it.
      await pumpAt(tester, 390);
      final align = tester.widget<Align>(
        find
            .ancestor(
              of: find.byType(SingleChildScrollView),
              matching: find.byType(Align),
            )
            .first,
      );
      expect(align.alignment, Alignment.topCenter);
    });
  });

}
