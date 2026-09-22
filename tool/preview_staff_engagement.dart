// Dev-only harness for the two new staff sections (Suggestions, Feedback) and
// the performance panels.
//
// Not part of the app: nothing under lib/ imports it, and it is never a build
// target for a shipped bundle.
//
//   flutter build web --release -t tool/preview_staff_engagement.dart
//   python -m http.server 57820 --directory build/web
//
// ── Why this exists ────────────────────────────────────────────────────────
// The staff console is login-gated AND department-gated: the pages read through
// views whose WHERE calls current_staff_department(), so a browser with no
// session sees nothing at all. Faking PostgREST would mean standing up the
// whole view; overriding the providers directly is the supported route and
// gives the exact widget tree the console renders.
//
// ── What to look at ────────────────────────────────────────────────────────
//  * Suggestions: the "Routed by AI" chip appears ONLY on an item the citizen
//    filed as "Others" that the classifier moved here. An item the citizen
//    categorised deliberately never carries it.
//  * The composer is CLOSED on an item whose reply is pending or published,
//    and open on a returned draft (which prefills the old body).
//  * The pending-approval notice states plainly that the citizen sees nothing
//    yet — that sentence is the whole point of the approval loop.
//  * Feedback has NO composer anywhere. It is read-only by design.
//  * The rating mix bars: 5-star first, and the percentages must sum to 100.
//  * At < 900px both pages are one column and the detail opens as a sheet;
//    above it, list + detail side by side.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:govpulse/features/admin/providers/admin_staff_replies_provider.dart';
import 'package:govpulse/features/admin/widgets/staff_reply_approvals.dart';
import 'package:govpulse/features/staff/data/staff_engagement_repository.dart';
import 'package:govpulse/features/staff/data/staff_repository.dart';
import 'package:govpulse/features/staff/pages/staff_feedback_page.dart';
import 'package:govpulse/features/staff/pages/staff_overview_page.dart';
import 'package:govpulse/features/staff/pages/staff_suggestions_page.dart';
import 'package:govpulse/features/staff/providers/staff_engagement_providers.dart';
import 'package:govpulse/features/staff/providers/staff_providers.dart';
import 'package:govpulse/features/staff/theme/staff_ui.dart';
import 'package:govpulse/features/staff/widgets/staff_performance_panels.dart';

// ── Fixtures ────────────────────────────────────────────────────────────────

StaffSuggestion _s({
  required String id,
  required String category,
  String? other,
  String? aiCategory,
  String? aiReason,
  required String details,
  ReplyState reply = ReplyState.none,
  String? replyBody,
  String? rejectedReason,
  String? adminResponse,
  bool anon = false,
  int daysAgo = 1,
}) =>
    StaffSuggestion(
      id: id,
      userId: anon ? null : 'citizen-1',
      category: category,
      categoryOther: other,
      barangay: 'Macanaya',
      address: null,
      details: details,
      isAnonymous: anon,
      status: reply == ReplyState.approved
          ? StaffSuggestionStatus.responded
          : StaffSuggestionStatus.fresh,
      createdAt: DateTime.now().subtract(Duration(days: daysAgo)),
      department: 'Engineering Office',
      aiCategory: aiCategory,
      aiCategoryReason: aiReason,
      adminResponse: adminResponse,
      replyState: reply,
      replyId: reply == ReplyState.none ? null : 'reply-$id',
      replyBody: replyBody,
      replyRejectedReason: rejectedReason,
      replyAuthorId: 'me',
    );

final _suggestions = <StaffSuggestion>[
  // The headline case: filed as "Others", moved here by the classifier.
  _s(
    id: '1',
    category: 'others',
    other: 'Covered walkway from the terminal to the market',
    aiCategory: 'infrastructure',
    aiReason:
        'Describes building a physical structure on a public route, which is '
        'infrastructure work.',
    details:
        'Sana po may covered walkway mula terminal papuntang palengke. Tuwing '
        'umuulan basang-basa ang mga nagtitinda at ang mga matatanda na '
        'naglalakad papunta doon. Baka pwede po sana kahit yung simpleng bubong '
        'lang muna.',
    daysAgo: 0,
  ),
  _s(
    id: '2',
    category: 'infrastructure',
    details: 'The footbridge railing near the school has been loose for weeks.',
    reply: ReplyState.pending,
    replyBody:
        'Thank you for reporting this. Our team has scheduled an inspection of '
        'the footbridge railing this week and will secure it immediately.',
    daysAgo: 3,
  ),
  _s(
    id: '3',
    category: 'infrastructure',
    details: 'Please add streetlights along the riverside path.',
    reply: ReplyState.rejected,
    replyBody: 'We will look into it.',
    rejectedReason:
        'Too vague — please tell the citizen which stretch is covered by the '
        'current budget and when work would start.',
    daysAgo: 6,
  ),
  _s(
    id: '4',
    category: 'infrastructure',
    anon: true,
    details: 'Drainage on Rizal St. backs up every heavy rain.',
    reply: ReplyState.approved,
    replyBody:
        'Desilting of the Rizal St. drainage line is scheduled for the last '
        'week of this month. Thank you for raising it.',
    adminResponse:
        'Desilting of the Rizal St. drainage line is scheduled for the last '
        'week of this month. Thank you for raising it.',
    daysAgo: 12,
  ),
];

StaffFeedback _f({
  required String id,
  required int rating,
  required String service,
  String? comment,
  bool anon = false,
  int daysAgo = 1,
  int? staff,
  int? wait,
  int? clarity,
  int? facility,
}) =>
    StaffFeedback(
      id: id,
      username: anon ? null : 'juan.dc',
      officeId: 'mpdo',
      officeLabel: 'Municipal Planning & Development Office',
      serviceName: service,
      overallRating: rating,
      aspectStaff: staff,
      aspectWait: wait,
      aspectClarity: clarity,
      aspectFacility: facility,
      comment: comment,
      visitDate: DateTime.now().subtract(Duration(days: daysAgo + 1)),
      isAnonymous: anon,
      createdAt: DateTime.now().subtract(Duration(days: daysAgo)),
      adminResponse: null,
      aiSentiment: rating <= 2 ? 'negative' : 'positive',
    );

final _feedback = <StaffFeedback>[
  _f(
    id: 'f1',
    rating: 1,
    service: 'Securing a Building Permit',
    comment:
        'Ang tagal po ng proseso. Tatlong beses akong bumalik kasi iba-iba ang '
        'sinasabi kung anong papeles ang kailangan.',
    daysAgo: 0,
    staff: 2,
    wait: 1,
    clarity: 1,
    facility: 3,
  ),
  _f(
    id: 'f2',
    rating: 5,
    service: 'Zoning Clearance',
    comment: 'Mabilis at magalang ang staff. Salamat po!',
    anon: true,
    daysAgo: 2,
    staff: 5,
    wait: 4,
    clarity: 5,
    facility: 4,
  ),
  _f(id: 'f3', rating: 4, service: 'Locational Clearance', daysAgo: 4),
  _f(
    id: 'f4',
    rating: 2,
    service: 'Securing a Building Permit',
    comment: 'Sarado nang dumating ako kahit 4pm pa lang.',
    daysAgo: 5,
  ),
  _f(id: 'f5', rating: 3, service: 'Subdivision Plan Review', daysAgo: 9),
];

final _card = StaffScorecard(
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
      RatingPoint(
        now.subtract(Duration(days: i * 7)),
        // Week i==5 is deliberately empty: the line must BREAK there rather
        // than dive to zero. Every OTHER week must carry a real average — an
        // accidental 0.0 with a non-zero count plots a legitimate crash to the
        // bottom of the axis, which is a different picture entirely.
        i == 5 ? 0 : [3.1, 3.4, 3.2, 3.9, 4.1, 4.2, 4.4, 4.6][7 - i],
        i == 5 ? 0 : 9,
      ),
  ];
}

// ── Provider stand-ins ──────────────────────────────────────────────────────

// The dashboard reads identity + three list providers; all four are stubbed so
// the tabbed / full layouts can be compared without a session.
class _FakeIdentity extends StaffIdentityNotifier {
  @override
  Future<StaffIdentity> build() async => const StaffIdentity(
        userId: 'me',
        email: 'rheinz@aparri.gov.ph',
        fullName: 'Engr. Rheinz Villanueva',
        title: 'Engineer II',
        department: 'Engineering Office',
        isExternal: false,
        isOnline: true,
        photoUrl: null,
      );
}

class _FakeConversations extends StaffConversationsNotifier {
  @override
  Future<List<StaffConversation>> build() async => const [];
}

class _FakeReports extends StaffReportsNotifier {
  @override
  Future<List<StaffReport>> build() async => const [];
}

class _FakeEndorsements extends StaffEndorsementsNotifier {
  @override
  Future<List<StaffReport>> build() async => const [];
}

// The ADMIN side of the approval loop: drafts waiting for a decision.
class _FakeReplies extends AdminStaffRepliesNotifier {
  @override
  Future<List<PendingStaffReply>> build() async => [
        PendingStaffReply(
          id: 'p1',
          suggestionId: '2',
          authorId: 'me',
          authorName: 'Engr. Rheinz Villanueva',
          authorPhotoUrl: null,
          department: 'Engineering Office',
          body: 'Thank you for reporting this. Our team has scheduled an '
              'inspection of the footbridge railing this week and will secure '
              'it immediately.',
          createdAt: DateTime.now().subtract(const Duration(hours: 5)),
          suggestionCategory: 'infrastructure',
          suggestionCategoryOther: null,
          suggestionDetails:
              'The footbridge railing near the school has been loose for '
              'weeks. Delikado po para sa mga bata.',
          suggestionCreatedAt:
              DateTime.now().subtract(const Duration(days: 4)),
        ),
        PendingStaffReply(
          id: 'p2',
          suggestionId: '5',
          authorId: 'b',
          authorName: 'Ana Marie Bautista',
          authorPhotoUrl: null,
          department: 'Sanitation Office',
          body: 'Noted po. We will add a collection run on Saturdays.',
          createdAt: DateTime.now().subtract(const Duration(hours: 30)),
          suggestionCategory: 'others',
          suggestionCategoryOther: 'Saturday garbage collection',
          suggestionDetails:
              'Sana po may Sabado na koleksyon ng basura sa Centro 3.',
          suggestionCreatedAt:
              DateTime.now().subtract(const Duration(days: 9)),
        ),
      ];
}

class _FakeSuggestions extends StaffSuggestionsNotifier {
  @override
  Future<List<StaffSuggestion>> build() async => _suggestions;
}

class _FakeFeedback extends StaffFeedbackNotifier {
  @override
  Future<List<StaffFeedback>> build() async => _feedback;
}

void main() {
  runApp(
    ProviderScope(
      overrides: [
        staffIdentityProvider.overrideWith(_FakeIdentity.new),
        staffConversationsProvider.overrideWith(_FakeConversations.new),
        staffReportsProvider.overrideWith(_FakeReports.new),
        staffEndorsementsProvider.overrideWith(_FakeEndorsements.new),
        adminStaffRepliesProvider.overrideWith(_FakeReplies.new),
        staffSuggestionsProvider.overrideWith(_FakeSuggestions.new),
        staffFeedbackProvider.overrideWith(_FakeFeedback.new),
        // The real one reads identity, which needs a session.
        staffHasFeedbackProvider.overrideWithValue(true),
        staffMyScorecardProvider.overrideWith((ref) async => _card),
        staffRatingTrendProvider.overrideWith((ref) async => _trend()),
      ],
      child: const _App(),
    ),
  );
}

class _App extends StatefulWidget {
  const _App();
  @override
  State<_App> createState() => _AppState();
}

class _AppState extends State<_App> {
  int _tab = 0;

  /// Forces a narrower MediaQuery than the window, so the one-column and
  /// two-pane branches can both be seen without resizing the browser.
  double? _forcedWidth;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Staff engagement preview',
      home: Scaffold(
        backgroundColor: StaffUi.pageBg,
        appBar: AppBar(
          backgroundColor: StaffUi.surface,
          title: const Text('Staff engagement preview',
              style: TextStyle(fontSize: 15)),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(86),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      for (final (i, label) in [
                        (0, 'Suggestions'),
                        (1, 'Feedback'),
                        (2, 'Performance'),
                        (3, 'Dashboard'),
                        (4, 'Admin approval'),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(label),
                            selected: _tab == i,
                            onSelected: (_) => setState(() => _tab = i),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final w in <double?>[null, 360, 600, 900, 1280])
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(w == null ? 'full' : '${w.toInt()}px'),
                              selected: _forcedWidth == w,
                              onSelected: (_) =>
                                  setState(() => _forcedWidth = w),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        body: LayoutBuilder(
          builder: (context, c) {
            final w = _forcedWidth ?? c.maxWidth;
            final page = switch (_tab) {
              0 => const StaffSuggestionsPage(),
              1 => const StaffFeedbackPage(),
              2 => _PerformanceTab(card: _card, trend: _trend()),
              3 => StaffOverviewPage(onNavigate: (_) {}),
              _ => const SingleChildScrollView(
                    padding: EdgeInsets.all(16),
                    child: StaffReplyApprovalsPanel(),
                  ),
            };
            return Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: w,
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    size: Size(w, c.maxHeight),
                  ),
                  child: page,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PerformanceTab extends StatefulWidget {
  final StaffScorecard card;
  final List<RatingPoint> trend;
  const _PerformanceTab({required this.card, required this.trend});

  @override
  State<_PerformanceTab> createState() => _PerformanceTabState();
}

class _PerformanceTabState extends State<_PerformanceTab> {
  LeaderboardMetric _metric = LeaderboardMetric.reportsResolved;

  @override
  Widget build(BuildContext context) {
    final peers = [
      widget.card,
      const StaffScorecard(
        userId: 'b',
        fullName: 'Ana Marie Bautista',
        photoUrl: null,
        department: 'Sanitation Office',
        reportsResolved: 51,
        chatRating: 4.2,
        chatRatingCount: 30,
        repliesApproved: 12,
        repliesRejected: 6,
        medianResponseHours: 40,
      ),
      const StaffScorecard(
        userId: 'c',
        fullName: 'Jose Cruz',
        photoUrl: null,
        department: "Mayor's Office",
        reportsResolved: 9,
        chatRating: 3.4,
        chatRatingCount: 11,
        repliesApproved: 22,
        repliesRejected: 1,
        medianResponseHours: 6.2,
      ),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          ScorecardPanel(card: widget.card, departmentRating: 3.8),
          const SizedBox(height: 14),
          RatingTrendPanel(points: widget.trend),
          const SizedBox(height: 14),
          StaffLeaderboardPanel(
            cards: peers,
            metric: _metric,
            onMetric: (m) => setState(() => _metric = m),
            title: 'All offices',
          ),
        ],
      ),
    );
  }
}
