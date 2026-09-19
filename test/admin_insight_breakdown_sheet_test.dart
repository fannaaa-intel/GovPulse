// Does the AI tab's "View all" breakdown survive every phone, both ways up, at
// large text — and does opening it actually reveal more than the card did?
//
// The sheet is the payoff for an insight: the bars claim "4 high urgency", and
// this list is the evidence. It used to be the card's own compact row reused at
// full size — 12px title, one clipped line of description, the urgency as bare
// coloured text — so opening it showed nothing the card had not already shown.
//
// Two things here are only provable by pumping the OPEN sheet, which is why
// every case drives `after`: a matrix that stops at the dashboard measures the
// collapsed card and reports a clean pass for a layout it never rendered.
//
//  * Overflow. Each row is a Row of [dot | text column | fixed trailing column]
//    with a two-line Tagalog description and, on two rows, an escalation chip.
//    The trailing column is a fixed 58/68px, so the text column absorbs every
//    width change — that is the piece that overflows if the numbers are wrong.
//  * The expanded/compact split. `narrow` drops the chevron on the phone sheet;
//    `expanded` is what promotes the description to two lines and the urgency
//    to a filled badge. A regression that silently passed `expanded: false`
//    would still lay out cleanly, so the split is asserted directly.
//
// The widget-test binding runs with `kIsWeb == false` and these sizes are all
// under the 640px cutoff, so the bottom-sheet branch is what these pump. The
// dialog branch was checked visually in
// tool/preview_admin_insight_breakdown.dart at 641, 1053 and 1280 px.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/admin/pages/admin_overview_page.dart';
import 'package:govpulse/features/admin/providers/admin_dashboard_provider.dart';
import 'package:govpulse/features/admin/providers/admin_reports_provider.dart';

import '_responsive_matrix.dart';

/// Serves fixed data so the page never reaches Supabase.
class _FakeDashboard extends AdminDashboardNotifier {
  _FakeDashboard(this.data);
  final AdminDashboardData data;

  @override
  Future<AdminDashboardData> build() async => data;

  @override
  Future<void> refresh() async {}
}

/// Reports with the longest realistic strings: a full category, a parenthesised
/// barangay, a two-sentence Tagalog description and — on two of them — a
/// cluster-escalation note. The probe is only as honest as its widest row.
List<FeedbackInsightItem> _reports() => [
  FeedbackInsightItem(
    id: 'r1',
    title: 'Road & Infrastructure',
    service: 'Macanaya (Pescaria)',
    comment:
        'May malaking bitak at gumuguho na ang gilid ng national highway. '
        'Delikado sa mga motor lalo na kapag gabi at walang ilaw.',
    rating: 0,
    sentiment: 'neutral',
    urgency: 'high',
    aiLabeled: true,
    escalationNote: '3 similar open reports in Macanaya this week',
    createdAt: DateTime.now().subtract(const Duration(minutes: 20)),
  ),
  FeedbackInsightItem(
    id: 'r2',
    title: 'Drainage & Flooding',
    service: 'Maura',
    comment:
        'Barado ang kanal sa tabi ng eskwelahan. Tuwing umuulan, bumabaha '
        'hanggang tuhod at hindi makadaan ang mga bata papasok.',
    rating: 0,
    sentiment: 'neutral',
    urgency: 'high',
    aiLabeled: true,
    createdAt: DateTime.now().subtract(const Duration(minutes: 23)),
  ),
  FeedbackInsightItem(
    id: 'r3',
    title: 'Environment & Pollution',
    service: 'Macanaya (Pescaria)',
    comment:
        'Araw-araw may nagsusunog ng plastik sa bakanteng lote. Masangsang '
        'ang usok at nahihirapan huminga ang mga matatanda sa tabi.',
    rating: 0,
    sentiment: 'neutral',
    urgency: 'medium',
    aiLabeled: true,
    escalationNote: '2 similar open reports nearby',
    createdAt: DateTime.now().subtract(const Duration(minutes: 18)),
  ),
  FeedbackInsightItem(
    id: 'r4',
    title: 'Waste & Garbage',
    service: 'Punta',
    comment: 'Hindi nakolekta ang basura sa aming kalye ng isang linggo na.',
    rating: 0,
    sentiment: 'neutral',
    urgency: 'medium',
    aiLabeled: true,
    createdAt: DateTime.now().subtract(const Duration(minutes: 25)),
  ),
  FeedbackInsightItem(
    id: 'r5',
    title: 'Noise complaint',
    service: 'Centro 3 (Pob.)',
    comment: 'Ang ingay ng karaoke ng kapitbahay hanggang madaling-araw.',
    rating: 0,
    sentiment: 'neutral',
    urgency: 'low',
    aiLabeled: true,
    createdAt: DateTime.now().subtract(const Duration(minutes: 21)),
  ),
  FeedbackInsightItem(
    id: 'r6',
    title: 'Streetlight Outage',
    service: 'Macanaya (Pescaria)',
    comment: 'Tatlong poste ng ilaw ang patay sa kalyeng ito.',
    rating: 0,
    sentiment: 'neutral',
    urgency: 'low',
    aiLabeled: true,
    createdAt: DateTime.now().subtract(const Duration(minutes: 22)),
  ),
  FeedbackInsightItem(
    id: 'r7',
    title: 'Public Safety',
    service: 'Centro 5 (Pob.)',
    comment: 'Walang ilaw sa may plaza, madilim tuwing gabi.',
    rating: 0,
    sentiment: 'neutral',
    urgency: 'low',
    aiLabeled: true,
    createdAt: DateTime.now().subtract(const Duration(minutes: 26)),
  ),
];

AdminDashboardData _data() {
  final reports = _reports();
  return AdminDashboardData(
    totalReports: reports.length,
    reportsThisWeek: reports.length,
    reportsWeekDeltaPct: 12,
    pendingVerification: 1,
    resolutionRate: 0.33,
    resolutionRateDeltaPts: 2,
    statusCounts: const {ReportStatus.pending: 5, ReportStatus.underReview: 2},
    topCategories: const [
      CategoryStat(label: 'Road & Infrastructure', count: 2, share: 0.29),
    ],
    reportDates: [
      for (var i = 0; i < reports.length; i++)
        DateTime.now().subtract(Duration(days: i)),
    ],
    satisfaction: SatisfactionStats.empty,
    nlp: NlpInsights(
      analyzed: 0,
      aiClassified: 0,
      positive: 0,
      neutral: 0,
      negative: 0,
      reportsAnalyzed: reports.length,
      reportsAiClassified: reports.length,
      urgentHigh: 2,
      urgentMedium: 2,
      urgentLow: 3,
      recentAvg: null,
      priorAvg: null,
      forecastRating: null,
      trend: InsightTrend.unknown,
      focus: const [],
      urgencyItems: reports,
    ),
    recentActivity: const [],
  );
}

Widget _app() => ProviderScope(
  overrides: [
    adminDashboardProvider.overrideWith(() => _FakeDashboard(_data())),
  ],
  // The Scaffold is load-bearing, not decoration: without one the page lays
  // out against an unbounded width and the Recent activity card reports a
  // ~99,000px overflow that has nothing to do with what is under test.
  child: MaterialApp(
    home: Scaffold(
      body: AdminOverviewPage(
        selectedIndex: 0,
        onNavigate: (_, {highlightId}) {},
      ),
    ),
  ),
);

/// Reaches the AI tab and opens the breakdown. Returns false when the layout
/// never got there, so a case can skip rather than pass vacuously.
///
/// The link is matched by its COUNT ("View all 7"), never by a bare
/// "View all": the Recent activity card carries one of those too, and tapping
/// that one opens a different feed entirely — which then reports its own
/// unrelated overflow and blames this sheet for it.
Future<bool> _openSheet(WidgetTester tester) async {
  final ai = find.text('AI');
  if (ai.evaluate().isEmpty) return false;
  await tester.tap(ai.first, warnIfMissed: false);
  await tester.pumpAndSettle();

  final viewAll = find.text('View all ${_reports().length}');
  if (viewAll.evaluate().isEmpty) return false;
  await tester.ensureVisible(viewAll.first);
  await tester.pumpAndSettle();
  await tester.tap(viewAll.first, warnIfMissed: false);
  await tester.pumpAndSettle();
  return find.text('All reports').evaluate().isNotEmpty;
}

void main() {
  group('the breakdown sheet lays out', () {
    for (final device in kAllPhones) {
      testWidgets('on ${device.name} without overflow', (tester) async {
        final errors = await pumpAt(
          tester,
          device,
          _app,
          after: (t) async => _openSheet(t),
        );
        expect(errors, isEmpty, reason: errors.join('\n'));
      });
    }

    // Tagalog runs half again as long as English and Android's Largest font
    // scales past this, so the tightest phone at 1.3x is the real worst case.
    testWidgets('on a small phone at textScale 1.3', (tester) async {
      final errors = await pumpAt(
        tester,
        kSmallPhone,
        _app,
        textScale: 1.3,
        after: (t) async => _openSheet(t),
      );
      expect(errors, isEmpty, reason: errors.join('\n'));
    });
  });

  testWidgets('opening it reveals more than the card showed', (tester) async {
    await pumpAt(tester, kPhone, _app, after: (t) async => _openSheet(t));
    if (find.text('All reports').evaluate().isEmpty) return;

    final rows = tester
        .widgetList<Widget>(
          find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_BreakdownRow',
          ),
        )
        .toList();
    expect(rows, isNotEmpty, reason: 'nothing rendered a breakdown row');

    // The card stays mounted BEHIND the sheet, so both forms are legitimately
    // in the tree at once. What matters is that the split exists: the sheet's
    // rows are expanded (two-line description, filled badge) and the card's
    // stay compact. A regression that reused the compact row in the sheet
    // still lays out cleanly, so this is what actually catches it.
    final expanded = rows.where((r) => (r as dynamic).expanded == true);
    final compact = rows.where((r) => (r as dynamic).expanded != true);
    expect(
      expanded,
      isNotEmpty,
      reason: "the sheet rendered the card's compact row",
    );
    expect(
      compact,
      isNotEmpty,
      reason: 'the card behind the sheet should still be compact',
    );

    // The phone sheet drops the chevron: there is no hover on touch, and at
    // 320px those pixels belong to the description instead.
    for (final row in expanded) {
      expect(
        (row as dynamic).narrow,
        isTrue,
        reason: 'the phone sheet kept the chevron',
      );
    }

    // The full description is present, not just the card's clipped line.
    // findsWidgets, not findsOneWidget: the card behind the sheet carries its
    // own compact copy of the same sentence.
    expect(
      find.textContaining('Delikado sa mga motor lalo na kapag gabi'),
      findsWidgets,
    );
    // The escalation reason is the point of the note; it must survive whole.
    expect(
      find.textContaining('Escalated — 3 similar open reports in Macanaya'),
      findsWidgets,
    );
    // The urgency reads as a priority, capitalised in its badge.
    expect(find.text('High'), findsWidgets);
  });
}
