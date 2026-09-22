// The staff dashboard must actually RENDER.
//
// WHY THIS EXISTS
// An `IntrinsicHeight` wrapped around a Row whose child contains a
// `LayoutBuilder` throws "LayoutBuilder does not support returning intrinsic
// dimensions" during layout, and the whole page fails to draw. It shipped past
// `flutter analyze` (valid Dart), past `flutter test` (every existing test
// pumped the panels in ISOLATION, never the real page) and past a release web
// build. Only running the app surfaced it.
//
// So this pumps StaffOverviewPage itself — the assembled tree, not its parts —
// and fails on ANY exception raised during layout, not just an overflow. Both
// the full-width layout and the tabbed narrow one are covered, and every tab is
// visited, because a throw hides in whichever branch is not built.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:govpulse/features/staff/data/staff_engagement_repository.dart';
import 'package:govpulse/features/staff/data/staff_repository.dart';
import 'package:govpulse/features/staff/pages/staff_overview_page.dart';
import 'package:govpulse/features/staff/providers/staff_engagement_providers.dart';
import 'package:govpulse/features/staff/providers/staff_providers.dart';

const _identity = StaffIdentity(
  userId: 'me',
  email: 'staff@aparri.gov.ph',
  fullName: 'Engr. Rheinz Villanueva',
  title: 'Engineer II',
  department: 'Engineering Office',
  isExternal: false,
  isOnline: true,
  photoUrl: null,
);

const _external = StaffIdentity(
  userId: 'ext',
  email: 'dpwh@example.gov.ph',
  fullName: 'DPWH Liaison',
  title: 'Liaison',
  department: 'DPWH',
  isExternal: true,
  isOnline: true,
  photoUrl: null,
);

const _card = StaffScorecard(
  userId: 'me',
  fullName: 'Engr. Rheinz Villanueva',
  photoUrl: null,
  department: 'Engineering Office',
  reportsResolved: 37,
  chatRating: 4.6,
  chatRatingCount: 52,
  repliesApproved: 18,
  repliesRejected: 3,
  medianResponseHours: 19.4,
);

List<RatingPoint> _trend() {
  final now = DateTime.now();
  return [
    for (var i = 7; i >= 0; i--)
      RatingPoint(now.subtract(Duration(days: i * 7)), 3.0 + i * 0.2, 9),
  ];
}

class _Identity extends StaffIdentityNotifier {
  _Identity(this.value);
  final StaffIdentity value;
  @override
  Future<StaffIdentity> build() async => value;
}

class _Convos extends StaffConversationsNotifier {
  @override
  Future<List<StaffConversation>> build() async => const [];
}

class _Reports extends StaffReportsNotifier {
  @override
  Future<List<StaffReport>> build() async => const [];
}

class _Endorsed extends StaffEndorsementsNotifier {
  @override
  Future<List<StaffReport>> build() async => const [];
}

/// Pumps the real page and returns every exception Flutter raised while laying
/// it out. An empty list is the pass condition.
Future<List<String>> _pumpDashboard(
  WidgetTester tester,
  Size size, {
  StaffIdentity identity = _identity,
  bool withScorecard = true,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());

  final errors = <String>[];
  final prev = FlutterError.onError;
  // Captures EVERYTHING, not just overflows: the intrinsic-dimension failure is
  // an assertion, and a probe that filtered for "overflowed" would have let it
  // through exactly as the existing suite did.
  FlutterError.onError = (details) => errors.add(details.exceptionAsString());

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  try {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        staffIdentityProvider.overrideWith(() => _Identity(identity)),
        staffConversationsProvider.overrideWith(_Convos.new),
        staffReportsProvider.overrideWith(_Reports.new),
        staffEndorsementsProvider.overrideWith(_Endorsed.new),
        staffHasFeedbackProvider.overrideWithValue(!identity.isExternal),
        staffMyScorecardProvider
            .overrideWith((ref) async => withScorecard ? _card : null),
        staffRatingTrendProvider.overrideWith((ref) async => _trend()),
      ],
      child: MaterialApp(
        home: Scaffold(body: StaffOverviewPage(onNavigate: (_) {})),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  } finally {
    FlutterError.onError = prev;
  }
  return errors;
}

void main() {
  group('staff dashboard renders', () {
    testWidgets('full layout at desktop width', (tester) async {
      final errors = await _pumpDashboard(tester, const Size(1400, 1400));
      expect(errors, isEmpty, reason: errors.join('\n'));
      expect(find.textContaining('Your performance'), findsOneWidget);
    });

    testWidgets('full layout at the tabbed threshold', (tester) async {
      // 1024 is the boundary itself: >= keeps the full layout.
      final errors = await _pumpDashboard(tester, const Size(1024, 1400));
      expect(errors, isEmpty, reason: errors.join('\n'));
    });

    testWidgets('tabbed layout on a phone', (tester) async {
      final errors = await _pumpDashboard(tester, const Size(390, 844));
      expect(errors, isEmpty, reason: errors.join('\n'));
      // The tab bar only exists in the narrow branch.
      expect(find.text('Overview'), findsOneWidget);
      expect(find.text('Queue'), findsOneWidget);
      expect(find.text('Performance'), findsOneWidget);
    });

    testWidgets('every tab lays out', (tester) async {
      // A throw hides in whichever branch is not built, so each one is opened.
      for (final tab in ['Queue', 'Performance', 'Overview']) {
        final errors = await _pumpDashboard(tester, const Size(390, 844));
        expect(errors, isEmpty, reason: 'before opening $tab');

        final more = <String>[];
        final prev = FlutterError.onError;
        FlutterError.onError = (d) => more.add(d.exceptionAsString());
        try {
          await tester.tap(find.text(tab));
          await tester.pump(const Duration(milliseconds: 400));
        } finally {
          FlutterError.onError = prev;
        }
        expect(more, isEmpty, reason: 'on the $tab tab:\n${more.join('\n')}');
      }
    });

    testWidgets('an external agency gets no tabs and still renders',
        (tester) async {
      final errors = await _pumpDashboard(
        tester,
        const Size(390, 844),
        identity: _external,
        withScorecard: false,
      );
      expect(errors, isEmpty, reason: errors.join('\n'));
      // One panel and no scorecard: a tab bar would hide nothing.
      expect(find.text('Queue'), findsNothing);
      expect(find.text('Performance'), findsNothing);
    });

    testWidgets('renders before the scorecard has loaded', (tester) async {
      // myCard is null on first paint. The Performance tab must simply be
      // absent rather than the page failing.
      final errors = await _pumpDashboard(
        tester,
        const Size(390, 844),
        withScorecard: false,
      );
      expect(errors, isEmpty, reason: errors.join('\n'));
      expect(find.text('Performance'), findsNothing);
      expect(find.text('Overview'), findsOneWidget);
    });
  });
}
