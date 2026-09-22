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
Widget _host(AsyncValue<List<PendingStaffReply>> state) {
  return ProviderScope(
    overrides: [
      adminStaffRepliesProvider.overrideWith(() => _StubReplies(state)),
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
  _StubReplies(this._state);

  @override
  Future<List<PendingStaffReply>> build() {
    return _state.when(
      data: (d) => Future.value(d),
      loading: () => Completer<List<PendingStaffReply>>().future,
      error: (e, st) => Future.error(e, st),
    );
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
