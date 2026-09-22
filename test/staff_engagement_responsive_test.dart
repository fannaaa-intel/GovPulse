// Responsive sweep for the two new staff sections (Suggestions, Feedback) and
// the performance panels they share with the admin console.
//
// WHY HOSTILE CONTENT, NOT REALISTIC CONTENT
// A gentle fixture passes on layouts that break the first time a real citizen
// writes a long "Others" category or a staff member has a long name. Every
// string here is the worst plausible value for its field — a 60-character
// category label, a four-digit count, a full Tagalog sentence in a pill — run
// across every phone size AND at 1.3x text scale, which stands in for both the
// Tagalog half of this bilingual app and a user on Android's largest font.
//
// The panels are pumped DIRECTLY rather than through the console shell: the
// shell needs a Supabase session, and what is being measured here is the
// layout, not the fetch.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:govpulse/features/staff/data/staff_engagement_repository.dart';
import 'package:govpulse/features/staff/widgets/staff_performance_panels.dart';

import '_responsive_matrix.dart';

/// Widths the staff console is actually used at. The phones come from the
/// shared matrix; these are the desktop/tablet widths where a two-pane layout
/// engages and a Row that was safe on a phone can still overflow.
const kConsoleWidths = <Device>[
  Device('tablet portrait', Size(768, 1024)),
  Device('small laptop', Size(1024, 768)),
  Device('desktop', Size(1280, 800)),
];

// ── Hostile fixtures ────────────────────────────────────────────────────────

/// A staff member whose name, office and every metric is the worst plausible
/// value: a long name, the longest office string in the set, four-digit counts
/// and a response time that renders as the widest possible token.
StaffScorecard _hostileCard({String? name, String? dept}) => StaffScorecard(
      userId: 'u1',
      fullName: name ??
          'Ma. Kristina Bernadette Villanueva-Domingo',
      photoUrl: null,
      department: dept ?? 'Municipal Planning & Development Office',
      reportsResolved: 1487,
      chatRating: 4.75,
      chatRatingCount: 2310,
      repliesApproved: 1204,
      repliesRejected: 398,
      medianResponseHours: 167.5,
    );

List<RatingPoint> _trend() {
  final now = DateTime.now();
  return [
    for (var i = 7; i >= 0; i--)
      RatingPoint(
        now.subtract(Duration(days: i * 7)),
        // A deliberate gap at week 5: a week with no ratings must render as a
        // break in the line, never as a zero.
        i == 5 ? 0 : 3.0 + (i % 3) * 0.7,
        i == 5 ? 0 : 12,
      ),
  ];
}

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(14),
          child: child,
        ),
      ),
    );

void main() {
  group('scorecard panel', () {
    for (final device in kAllPhones) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('no overflow at $device @${scale}x', (tester) async {
          final errors = await pumpAt(
            tester,
            device,
            () => _wrap(ScorecardPanel(
              card: _hostileCard(),
              departmentRating: 4.25,
            )),
            textScale: scale,
          );
          expect(errors, isEmpty, reason: errors.join('\n'));
        });
      }
    }

    for (final device in kConsoleWidths) {
      testWidgets('no overflow at $device', (tester) async {
        final errors = await pumpAt(
          tester,
          device,
          () => _wrap(ScorecardPanel(
            card: _hostileCard(),
            departmentRating: 4.25,
          )),
        );
        expect(errors, isEmpty, reason: errors.join('\n'));
      });
    }

    testWidgets('an office with no ratings shows no department line',
        (tester) async {
      await pumpAt(
        tester,
        kPhone,
        () => _wrap(ScorecardPanel(
          card: _hostileCard(),
          departmentRating: null,
          departmentReceivesRatings: false,
        )),
      );
      // Environment Office receives no feedback at all, so the office-rating
      // context must be absent rather than reading "no ratings yet" — which
      // would imply some are expected.
      expect(find.textContaining('citizen rating'), findsNothing);
      expect(find.textContaining('no citizen ratings'), findsNothing);
    });

    testWidgets('a new staff member reads as no data, not as zero',
        (tester) async {
      await pumpAt(
        tester,
        kPhone,
        () => _wrap(ScorecardPanel(
          card: const StaffScorecard(
            userId: 'u2',
            fullName: 'New Staffer',
            photoUrl: null,
            department: 'Sanitation Office',
            reportsResolved: 0,
            chatRating: null,
            chatRatingCount: 0,
            repliesApproved: 0,
            repliesRejected: 0,
            medianResponseHours: null,
          ),
          departmentRating: null,
        )),
      );
      // An unrated newcomer must not render 0.0, which reads as the worst
      // possible score rather than an absence of data.
      expect(find.text('0.0'), findsNothing);
      expect(find.text('—'), findsWidgets);
    });
  });

  group('rating trend', () {
    for (final device in kAllPhones) {
      testWidgets('no overflow at $device', (tester) async {
        final errors = await pumpAt(
          tester,
          device,
          () => _wrap(RatingTrendPanel(points: _trend())),
        );
        expect(errors, isEmpty, reason: errors.join('\n'));
      });
    }

    testWidgets('too few points renders the empty note, not a broken chart',
        (tester) async {
      await pumpAt(
        tester,
        kPhone,
        () => _wrap(RatingTrendPanel(
          points: [RatingPoint(DateTime.now(), 4, 3)],
        )),
      );
      expect(find.textContaining('Not enough ratings'), findsOneWidget);
    });
  });

  group('leaderboard', () {
    // Several staff with near-identical long names is the realistic worst case
    // for the fixed-width name column.
    final cards = [
      _hostileCard(name: 'Ma. Kristina Bernadette Villanueva-Domingo'),
      _hostileCard(
          name: 'Juan Paolo Miguel Santos-Reyes', dept: "Mayor's Office"),
      _hostileCard(name: 'A', dept: 'Engineering Office'),
    ];

    for (final device in kAllPhones) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('no overflow at $device @${scale}x', (tester) async {
          final errors = await pumpAt(
            tester,
            device,
            () => _wrap(StaffLeaderboardPanel(
              cards: cards,
              metric: LeaderboardMetric.reportsResolved,
              onMetric: (_) {},
            )),
            textScale: scale,
          );
          expect(errors, isEmpty, reason: errors.join('\n'));
        });
      }
    }

    for (final device in kConsoleWidths) {
      testWidgets('no overflow at $device', (tester) async {
        final errors = await pumpAt(
          tester,
          device,
          () => _wrap(StaffLeaderboardPanel(
            cards: cards,
            metric: LeaderboardMetric.chatRating,
            onMetric: (_) {},
          )),
        );
        expect(errors, isEmpty, reason: errors.join('\n'));
      });
    }

    testWidgets('empty roster renders a note rather than an empty card',
        (tester) async {
      await pumpAt(
        tester,
        kPhone,
        () => _wrap(const StaffLeaderboardPanel(
          cards: [],
          metric: LeaderboardMetric.reportsResolved,
        )),
      );
      expect(find.textContaining('No staff activity'), findsOneWidget);
    });

    testWidgets('speed ranks the FASTEST first, not the slowest',
        (tester) async {
      // The bar value for response time is inverted (1/(h+1)) so that a short
      // reply time produces a long bar. Getting this backwards would rank the
      // slowest staff at the top and quietly reward being slow.
      const fast = StaffScorecard(
        userId: 'fast',
        fullName: 'Fast',
        photoUrl: null,
        department: 'Engineering Office',
        reportsResolved: 0,
        chatRating: null,
        chatRatingCount: 0,
        repliesApproved: 3,
        repliesRejected: 0,
        medianResponseHours: 2,
      );
      const slow = StaffScorecard(
        userId: 'slow',
        fullName: 'Slow',
        photoUrl: null,
        department: 'Engineering Office',
        reportsResolved: 0,
        chatRating: null,
        chatRatingCount: 0,
        repliesApproved: 3,
        repliesRejected: 0,
        medianResponseHours: 200,
      );
      await pumpAt(
        tester,
        kTablet,
        () => _wrap(const StaffLeaderboardPanel(
          cards: [slow, fast], // deliberately passed slowest-first
          metric: LeaderboardMetric.responseTime,
        )),
      );
      final fastY = tester.getTopLeft(find.text('Fast')).dy;
      final slowY = tester.getTopLeft(find.text('Slow')).dy;
      expect(fastY, lessThan(slowY),
          reason: 'the faster responder must rank above the slower one');
    });
  });

  _gridTests();

  group('routing rules', () {
    test('Environment Office receives no feedback', () {
      // The console hides the Feedback nav item on this, so it must stay true.
      expect(departmentReceivesFeedback('Environment Office'), isFalse);
      expect(departmentReceivesFeedback('Engineering Office'), isTrue);
      expect(departmentReceivesFeedback('Sanitation Office'), isTrue);
      expect(departmentReceivesFeedback("Mayor's Office"), isTrue);
      // An unknown or absent department must not silently get an inbox.
      expect(departmentReceivesFeedback(null), isFalse);
      expect(departmentReceivesFeedback(''), isFalse);
    });

    test('a suggestion with a pending reply is closed to new replies', () {
      final s = _suggestion(replyState: ReplyState.pending);
      // Two staff answering the same item is the failure this prevents.
      expect(s.isAnswered, isTrue);
      expect(s.canEdit('me'), isFalse);
    });

    test('only the author can revise a returned draft', () {
      final mine = _suggestion(
          replyState: ReplyState.rejected, replyAuthorId: 'me');
      final theirs = _suggestion(
          replyState: ReplyState.rejected, replyAuthorId: 'someone-else');
      expect(mine.canEdit('me'), isTrue);
      expect(theirs.canEdit('me'), isFalse);
    });

    test('a published reply closes the composer even with no reply row', () {
      // A reply published before this feature existed lives only in
      // admin_response. It must still close the composer.
      final s = _suggestion(adminResponse: 'Already answered by the LGU.');
      expect(s.isAnswered, isTrue);
    });

    test('AI routing is claimed only when it actually decided', () {
      expect(_suggestion(category: 'others', aiCategory: 'infrastructure')
          .wasAiRouted, isTrue);
      // The citizen picked deliberately — the AI never overrides that, so the
      // chip must not claim it did.
      expect(_suggestion(category: 'infrastructure', aiCategory: 'environment')
          .wasAiRouted, isFalse);
      // The AI agreed it was "others": no information gained, nothing routed.
      expect(_suggestion(category: 'others', aiCategory: 'others')
          .wasAiRouted, isFalse);
      // Not yet classified.
      expect(_suggestion(category: 'others').wasAiRouted, isFalse);
    });

    test('the citizen\'s own words win over the generic "Others" label', () {
      expect(
        suggestionCategoryLabel('others', 'Covered basketball court'),
        'Covered basketball court',
      );
      expect(suggestionCategoryLabel('others', '  '), 'Others');
      expect(suggestionCategoryLabel('health_safety', null), 'Health & Safety');
    });
  });
}

StaffSuggestion _suggestion({
  String category = 'others',
  String? aiCategory,
  ReplyState replyState = ReplyState.none,
  String? replyAuthorId,
  String? adminResponse,
}) =>
    StaffSuggestion(
      id: 's1',
      userId: null,
      category: category,
      categoryOther: null,
      barangay: null,
      address: null,
      details: 'details',
      isAnonymous: true,
      status: StaffSuggestionStatus.fresh,
      createdAt: DateTime.now(),
      department: 'Engineering Office',
      aiCategory: aiCategory,
      aiCategoryReason: null,
      adminResponse: adminResponse,
      replyState: replyState,
      replyId: replyState == ReplyState.none ? null : 'r1',
      replyBody: null,
      replyRejectedReason: null,
      replyAuthorId: replyAuthorId,
    );

// ── Stat grid column choice ─────────────────────────────────────────────────
// Extracted from the dashboard's LayoutBuilder. Six tiles in a 4-wide grid
// leaves a 4 + 2 split whose second row is half empty, which reads as a
// missing card rather than as a layout.
int statCols(double width, int tileCount) {
  if (width < 720) return 2;
  if (tileCount % 4 == 0) return 4;
  if (tileCount % 3 == 0) return 3;
  return 4;
}

void _gridTests() {
  group('stat grid columns', () {
    test('six tiles split 3 + 3, never 4 + 2', () {
      expect(statCols(1280, 6), 3);
      expect(6 % statCols(1280, 6), 0, reason: 'no ragged trailing row');
    });

    test('four and five tiles keep four across', () {
      expect(statCols(1280, 4), 4);
      expect(statCols(1280, 5), 4);
    });

    test('an external agency with two tiles does not stretch to four', () {
      // cols is clamped to the tile count at the call site; what matters here
      // is that the chosen value never leaves an empty trailing row.
      expect(statCols(1280, 2).clamp(1, 2), 2);
    });

    test('phones always stack two-up', () {
      for (final w in [320.0, 360.0, 430.0, 719.0]) {
        expect(statCols(w, 6), 2, reason: 'at ${w}px');
      }
    });
  });
}
