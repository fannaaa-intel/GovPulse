// The admin's staff-reply approval queue: the states it must render, and the
// widths it must render them at.
//
// This queue shipped INVISIBLE. Two independent faults hid it:
//
//   1. The provider embedded `admin_profiles(...)`, but
//      `suggestion_replies.author_id` is a foreign key to `auth.users`, not to
//      admin_profiles. PostgREST has no relationship to resolve, so the whole
//      SELECT failed on every load.
//   2. The panel collapsed to SizedBox.shrink() on ANY empty list — including
//      the empty list an error produces. A failed read was indistinguishable
//      from "no work waiting".
//
// Fault 2 is what made fault 1 silent, so the error state is tested here as
// carefully as the populated one: an error must SAY so and offer a retry.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/admin/providers/admin_staff_replies_provider.dart';
import 'package:govpulse/features/admin/widgets/admin_dialog_back.dart';
import 'package:govpulse/features/admin/widgets/staff_reply_approvals.dart';

import '_responsive_matrix.dart';

PendingStaffReply _reply({
  String id = 'r1',
  String authorName = 'Engr. Dela Cruz',
  String department = 'Engineering Office',
  String body = 'We have scheduled an inspection for next week.',
  String details = 'Please add a streetlight on Rizal St.',
  Duration waited = const Duration(days: 2),
}) {
  final now = DateTime.now();
  return PendingStaffReply(
    id: id,
    suggestionId: 's-$id',
    authorId: 'a-$id',
    authorName: authorName,
    authorPhotoUrl: null,
    department: department,
    body: body,
    createdAt: now,
    suggestionCategory: 'infrastructure',
    suggestionCategoryOther: null,
    suggestionDetails: details,
    suggestionCreatedAt: now.subtract(waited),
  );
}

/// Overrides the queue with a fixed state. The panel reads nothing else, so
/// this renders the real widget with no network at all.
Widget _host(
  AsyncValue<List<PendingStaffReply>> state, {
  _StubReplies? stub,
}) {
  return ProviderScope(
    overrides: [
      adminStaffRepliesProvider
          .overrideWith(() => stub ?? _StubReplies(state)),
    ],
    child: const MaterialApp(
      home: Scaffold(
        // SingleChildScrollView mirrors the real page: the panel sits inside
        // one on admin_suggestions_page, so vertical room is never the
        // constraint — horizontal room is.
        body: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: StaffReplyApprovalsPanel(),
        ),
      ),
    ),
  );
}

class _StubReplies extends AdminStaffRepliesNotifier {
  final AsyncValue<List<PendingStaffReply>> _state;

  /// When set, approve/reject throw this instead of touching the network.
  final Object? throws;

  /// Records that the write was actually attempted.
  final List<String> calls = [];

  _StubReplies(this._state, {this.throws});

  @override
  Future<List<PendingStaffReply>> build() {
    return _state.when(
      data: (d) => Future.value(d),
      loading: () => Completer<List<PendingStaffReply>>().future,
      error: (e, st) => Future.error(e, st),
    );
  }

  @override
  Future<void> approve(String id) async {
    calls.add('approve:$id');
    if (throws != null) throw throws!;
  }

  @override
  Future<void> reject(String id, String reason) async {
    calls.add('reject:$id:$reason');
    if (throws != null) throw throws!;
  }
}

void main() {
  group('states', () {
    testWidgets('an empty queue takes no space at all', (tester) async {
      await tester.pumpWidget(_host(const AsyncValue.data([])));
      await tester.pumpAndSettle();

      // A queue, not a permanent section: nothing to approve, nothing shown.
      expect(find.byType(StaffReplyApprovalsPanel), findsOneWidget);
      expect(find.textContaining('waiting for approval'), findsNothing);
      expect(find.text('Approve & publish'), findsNothing);
    });

    testWidgets('a FAILED read says so instead of looking empty',
        (tester) async {
      await tester.pumpWidget(
        _host(AsyncValue.error('PostgrestException', StackTrace.empty)),
      );
      await tester.pumpAndSettle();

      // The regression that hid this whole feature. An error must never be
      // rendered as an empty queue.
      expect(find.text('Approvals could not be loaded'), findsOneWidget);
      expect(
        find.textContaining('not an empty queue'),
        findsOneWidget,
        reason: 'the admin must be told this is a loading failure',
      );
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('the first load shows a skeleton, not a blank', (tester) async {
      await tester.pumpWidget(_host(const AsyncValue.loading()));
      await tester.pump();

      expect(find.text('Checking for staff replies…'), findsOneWidget);
    });

    testWidgets('a populated queue counts the items and explains itself',
        (tester) async {
      await tester.pumpWidget(_host(AsyncValue.data([
        _reply(id: 'a'),
        _reply(id: 'b', authorName: 'Ms. Reyes'),
      ])));
      await tester.pumpAndSettle();

      expect(find.text('2 staff replies waiting for approval'), findsOneWidget);
      // Says what approving DOES — the count alone never explained the stakes.
      expect(find.textContaining('has reached the citizen'), findsOneWidget);
      expect(find.text('Approve & publish'), findsNWidgets(2));
      expect(find.text('Send back'), findsNWidgets(2));
      // The citizen's words AND the office's reply: a reply cannot be judged
      // without the thing it answers.
      expect(find.text('The citizen wrote'), findsNWidgets(2));
      expect(find.text('The office replied'), findsNWidgets(2));
    });

    testWidgets('one item is singular', (tester) async {
      await tester.pumpWidget(_host(AsyncValue.data([_reply()])));
      await tester.pumpAndSettle();
      expect(find.text('1 staff reply waiting for approval'), findsOneWidget);
    });
  });

  group('the actions actually fire, and report honestly', () {
    testWidgets('Approve & publish calls approve and toasts the result',
        (tester) async {
      final stub = _StubReplies(AsyncValue.data([_reply()]));
      await tester.pumpWidget(_host(const AsyncValue.loading(), stub: stub));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Approve & publish'));
      await tester.pumpAndSettle();

      expect(stub.calls, ['approve:r1']);
      expect(find.text('Reply published. The citizen has been notified.'),
          findsOneWidget);
    });

    // The whole point of the read-back added to the provider: an UPDATE that
    // RLS filters to zero rows SUCCEEDS in PostgREST, changing nothing. If the
    // panel reported that as published, the admin would believe a citizen had
    // been answered who had not been.
    testWidgets('a silent no-op is reported as a failure, not a success',
        (tester) async {
      final stub = _StubReplies(
        AsyncValue.data([_reply()]),
        throws: StateError('approve-no-op:r1'),
      );
      await tester.pumpWidget(_host(const AsyncValue.loading(), stub: stub));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Approve & publish'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Nothing changed'), findsOneWidget);
      expect(find.text('Reply published. The citizen has been notified.'),
          findsNothing);
    });

    testWidgets('a permission error names permission, not the network',
        (tester) async {
      final stub = _StubReplies(
        AsyncValue.data([_reply()]),
        throws: Exception('42501: new row violates row-level security policy'),
      );
      await tester.pumpWidget(_host(const AsyncValue.loading(), stub: stub));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Approve & publish'));
      await tester.pumpAndSettle();

      expect(find.textContaining('does not have permission'), findsOneWidget);
    });

    testWidgets('Send back requires a reason and passes it through',
        (tester) async {
      final stub = _StubReplies(AsyncValue.data([_reply()]));
      await tester.pumpWidget(_host(const AsyncValue.loading(), stub: stub));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Send back'));
      await tester.pumpAndSettle();

      // Submitting empty must NAME the field rather than doing nothing.
      await tester.tap(find.widgetWithText(FilledButton, 'Send back'));
      await tester.pumpAndSettle();
      expect(find.text('Please say what needs changing.'), findsOneWidget);
      expect(stub.calls, isEmpty, reason: 'nothing may be written yet');

      await tester.enterText(find.byType(TextField), 'Answer the drainage bit');
      await tester.tap(find.widgetWithText(FilledButton, 'Send back'));
      await tester.pumpAndSettle();

      expect(stub.calls, ['reject:r1:Answer the drainage bit']);
      expect(find.text('Sent back to the office with your note.'),
          findsOneWidget);
    });
  });

  group('the inline panel is capped, and the rest is reachable', () {
    // A long queue used to render every row inline, above the suggestions list
    // it belongs to. Seven rows is a screen and a half on a desktop and far
    // worse on a phone — the page the panel is attached to became unreachable
    // by scrolling past its own gate.
    List<PendingStaffReply> many(int n) => [
          for (var i = 0; i < n; i++)
            _reply(
              id: 'q$i',
              authorName: 'Officer $i',
              // Descending wait, matching the provider's oldest-first order.
              waited: Duration(days: n - i),
            ),
        ];

    testWidgets('only two rows draw, however long the queue', (tester) async {
      await tester.pumpWidget(_host(AsyncValue.data(many(7))));
      await tester.pumpAndSettle();

      expect(find.text('Approve & publish'), findsNWidgets(kInlineApprovalRows));
      expect(find.text('Send back'), findsNWidgets(kInlineApprovalRows));
    });

    testWidgets('the header still counts every one of them', (tester) async {
      await tester.pumpWidget(_host(AsyncValue.data(many(7))));
      await tester.pumpAndSettle();

      // Capping what is DRAWN must not cap what is REPORTED: an admin reading
      // "2 waiting" over a queue of seven has been told something false.
      expect(find.text('7 staff replies waiting for approval'), findsOneWidget);
    });

    testWidgets('the two shown are the longest-waiting', (tester) async {
      await tester.pumpWidget(_host(AsyncValue.data(many(7))));
      await tester.pumpAndSettle();

      expect(find.text('Officer 0'), findsOneWidget);
      expect(find.text('Officer 1'), findsOneWidget);
      expect(find.text('Officer 2'), findsNothing);
    });

    testWidgets('the footer names the REMAINDER, not the total',
        (tester) async {
      await tester.pumpWidget(_host(AsyncValue.data(many(7))));
      await tester.pumpAndSettle();

      // "2 of 7 shown" makes the admin do the subtraction to learn what the
      // control gains them.
      expect(find.text('View all — 5 more replies waiting'), findsOneWidget);
    });

    testWidgets('one hidden reply is singular', (tester) async {
      await tester.pumpWidget(_host(AsyncValue.data(many(3))));
      await tester.pumpAndSettle();
      expect(find.text('View all — 1 more reply waiting'), findsOneWidget);
    });

    testWidgets('a queue that fits shows no footer', (tester) async {
      await tester.pumpWidget(_host(AsyncValue.data(many(2))));
      await tester.pumpAndSettle();

      // A "View all" over a list already fully shown is a no-op control.
      expect(find.textContaining('View all'), findsNothing);
      expect(find.text('Approve & publish'), findsNWidgets(2));
    });

    testWidgets('View all opens the whole queue on a desktop', (tester) async {
      await pumpAt(
        tester,
        const Device('web', Size(1280, 900)),
        () => _host(AsyncValue.data(many(7))),
      );

      await tester.tap(find.textContaining('View all'));
      await tester.pumpAndSettle();

      expect(find.text('Staff replies waiting'), findsOneWidget);
      // Every row, not just the two the panel drew. The rows scroll inside the
      // card, so some are off-screen but built.
      expect(find.text('Officer 6'), findsOneWidget);
    });

    testWidgets('View all pushes a chevron screen on a phone', (tester) async {
      await pumpAt(tester, kPhone, () => _host(AsyncValue.data(many(7))));

      await tester.scrollUntilVisible(
        find.textContaining('View all'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.textContaining('View all'));
      await tester.pumpAndSettle();

      expect(find.text('Staff replies waiting'), findsOneWidget);
      // The console's own back chip, not a second copy of it — the screen is a
      // place you navigated to, so it is dismissed by a chevron.
      expect(find.byType(AdminDialogBack), findsOneWidget);
    });

    testWidgets('no overflow in the full view on the smallest phone',
        (tester) async {
      final errors = await pumpAt(
        tester,
        kSmallPhone,
        () => _host(AsyncValue.data(many(7))),
        after: (t) async {
          await t.scrollUntilVisible(
            find.textContaining('View all'),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          await t.tap(find.textContaining('View all'));
          await t.pumpAndSettle();
        },
      );
      expect(errors, isEmpty, reason: errors.join('\n'));
    });
  });

  group('the send-back prompt changes shape with the screen', () {
    // As a centred AlertDialog on a 445px phone this was a small card floating
    // mid-viewport, with the keyboard covering the buttons. The validation and
    // the write must survive the shape change — both shapes render one body.
    testWidgets('a phone gets a bottom sheet that still refuses empty',
        (tester) async {
      final stub = _StubReplies(AsyncValue.data([_reply()]));
      await pumpAt(
        tester,
        kPhone,
        () => _host(const AsyncValue.loading(), stub: stub),
      );

      await tester.tap(find.text('Send back'));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Send back'));
      await tester.pumpAndSettle();
      expect(find.text('Please say what needs changing.'), findsOneWidget);
      expect(stub.calls, isEmpty);

      await tester.enterText(find.byType(TextField), 'Add the timeline');
      await tester.tap(find.widgetWithText(FilledButton, 'Send back'));
      await tester.pumpAndSettle();
      expect(stub.calls, ['reject:r1:Add the timeline']);
    });

    testWidgets('a desktop keeps the centred card', (tester) async {
      await pumpAt(
        tester,
        const Device('web', Size(1280, 900)),
        () => _host(AsyncValue.data([_reply()])),
      );

      await tester.tap(find.text('Send back'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('no overflow in the sheet on the smallest phone',
        (tester) async {
      final errors = await pumpAt(
        tester,
        kSmallPhone,
        () => _host(AsyncValue.data([_reply()])),
        after: (t) async {
          await t.tap(find.text('Send back'));
          await t.pumpAndSettle();
        },
      );
      expect(errors, isEmpty, reason: errors.join('\n'));
    });
  });

  group('the wait badge', () {
    Future<void> expectLabel(
      WidgetTester tester,
      Duration waited,
      String label,
    ) async {
      // Fresh ProviderScope per case: pumping a new tree into the same tester
      // otherwise reuses the already-resolved provider and the second
      // assertion silently measures the FIRST case's render.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        _host(AsyncValue.data([_reply(waited: waited)])),
      );
      await tester.pumpAndSettle();
      expect(find.text(label), findsOneWidget);
    }

    testWidgets('days, hours, minutes — and never a bare "0h"',
        (tester) async {
      await expectLabel(tester, const Duration(days: 4), '4d waiting');
      await expectLabel(tester, const Duration(hours: 5), '5h waiting');
      // The bug: anything under an hour printed "0h waiting", which reads as
      // broken rather than fresh.
      await expectLabel(tester, const Duration(minutes: 20), '20m waiting');
      await expectLabel(tester, const Duration(seconds: 5), 'just now');
    });
  });

  group('responsiveness', () {
    // Hostile content: the longest plausible values in every field at once.
    // A gentle fixture passes layouts that real data breaks.
    final hostile = [
      _reply(
        id: 'h1',
        authorName: 'Engr. Maria Cristina Villanueva-Bautista',
        department: 'Municipal Planning & Development Office',
        details:
            'Good day po. I would like to respectfully suggest that the '
            'municipality consider installing additional streetlights along '
            'the entire stretch of Rizal Street, particularly between the '
            'public market and the barangay hall, because the area becomes '
            'extremely dark after sunset and many residents walk home there.',
        body:
            'Thank you for raising this concern with our office. We have '
            'endorsed your request to the Engineering Office and an ocular '
            'inspection has been scheduled for the coming week, after which a '
            'costing will be prepared for the Municipal Council.',
        waited: const Duration(days: 12),
      ),
      _reply(id: 'h2', waited: const Duration(minutes: 3)),
    ];

    for (final device in kAllPhones) {
      testWidgets('no overflow on $device', (tester) async {
        final errors = await pumpAt(
          tester,
          device,
          () => _host(AsyncValue.data(hostile)),
        );
        expect(errors, isEmpty, reason: errors.join('\n'));
      });
    }

    testWidgets('no overflow on a tablet rail', (tester) async {
      final errors = await pumpAt(
        tester,
        kTablet,
        () => _host(AsyncValue.data(hostile)),
      );
      expect(errors, isEmpty, reason: errors.join('\n'));
    });

    // The admin console is web/desktop-first. These are the widths a real
    // browser window gets, including the narrow split-window case where the
    // action row is above the stacking breakpoint but still tight.
    for (final w in const [1024.0, 1280.0, 1440.0, 1920.0]) {
      testWidgets('no overflow at web ${w.toInt()}px', (tester) async {
        final errors = await pumpAt(
          tester,
          Device('web', Size(w, 900)),
          () => _host(AsyncValue.data(hostile)),
        );
        expect(errors, isEmpty, reason: errors.join('\n'));
      });
    }

    testWidgets('no overflow in the error state on the smallest phone',
        (tester) async {
      final errors = await pumpAt(
        tester,
        kSmallPhone,
        () => _host(AsyncValue.error('boom', StackTrace.empty)),
      );
      expect(errors, isEmpty, reason: errors.join('\n'));
    });

    testWidgets('no overflow in the skeleton on the smallest phone',
        (tester) async {
      final errors = await pumpAt(
        tester,
        kSmallPhone,
        () => _host(const AsyncValue.loading()),
        after: (t) async => t.pump(),
      );
      expect(errors, isEmpty, reason: errors.join('\n'));
    });

    // Large-text accessibility. A console that overflows at 1.3x is unusable
    // for anyone who has turned system text up.
    testWidgets('no overflow at 1.3x text on a phone', (tester) async {
      final errors = await pumpAt(
        tester,
        kPhone,
        () => _host(AsyncValue.data(hostile)),
        textScale: 1.3,
      );
      expect(errors, isEmpty, reason: errors.join('\n'));
    });

    testWidgets('no overflow at 1.3x text at 1280px', (tester) async {
      final errors = await pumpAt(
        tester,
        const Device('web', Size(1280, 900)),
        () => _host(AsyncValue.data(hostile)),
        textScale: 1.3,
      );
      expect(errors, isEmpty, reason: errors.join('\n'));
    });
  });
}
