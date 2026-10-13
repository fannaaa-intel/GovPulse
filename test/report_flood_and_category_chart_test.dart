// Report-flood hardening (20261014000000) and the reports-by-category chart.
// The SQL rules are proven by supabase/diagnostics/verify_20261014000000.sql;
// this covers the Dart side: the chart's bucketing, the surge grouping, and
// every new surface at every screen size the app and the console run on.

import 'package:flutter/material.dart';
import 'dart:ui' show Tristate;

import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/admin/providers/admin_dashboard_provider.dart';
import 'package:govpulse/features/admin/providers/admin_reports_provider.dart';
import 'package:govpulse/features/admin/widgets/report_category_trend.dart';
import 'package:govpulse/features/admin/widgets/report_detail_kit.dart'
    show ChipDensity;
import 'package:govpulse/features/admin/widgets/report_flood_widgets.dart';
import 'package:govpulse/features/home/Quick-action/Report/already_reported_dialog.dart';

import '_responsive_matrix.dart';

const _desktop = [
  Device('small laptop', Size(1024, 768)),
  Device('laptop', Size(1280, 800)),
  Device('desktop', Size(1440, 900)),
  Device('full HD', Size(1920, 1080)),
];

List<Device> get _everyScreen => [
  ...kAllPhones,
  kTablet,
  kTablet.rotated,
  ..._desktop,
];

final _now = DateTime(2026, 10, 13, 15);

ReportPoint _p(int daysAgo, String cat) =>
    (at: _now.subtract(Duration(days: daysAgo)), category: cat);

AdminReport _report(
  String id, {
  String cat = 'drainage',
  String label = 'Drainage & Flooding',
  String? barangay = 'Centro 1',
  ReportStatus status = ReportStatus.pending,
  String? assignedTo,
  bool surge = true,
  int similar = 4,
  int recent = 5,
  String? duplicateOf,
  int hoursAgo = 1,
}) => AdminReport(
  id: id,
  shortId: id.toUpperCase().padRight(8, '0').substring(0, 8),
  categoryKey: cat,
  category: label,
  barangay: barangay,
  address: null,
  remarks: 'probe',
  status: status,
  isAnonymous: false,
  submitterName: 'Citizen',
  submitterPhotoUrl: null,
  submitterRole: 'citizen',
  mediaCount: 1,
  createdAt: _now.subtract(Duration(hours: hoursAgo)),
  assignedToDepartment: assignedTo,
  assignedAt: assignedTo == null ? null : _now,
  duplicateOf: duplicateOf,
  similarCount: similar,
  recentSimilarCount: recent,
  isSurge: surge,
);

void main() {
  // ── The chart's numbers ────────────────────────────────────────────────────
  group('CategoryTrend.build', () {
    test(
      '30 days: one point per day, today last, unknown keys fold to Others',
      () {
        final t = CategoryTrend.build(
          [
            _p(0, 'drainage'),
            _p(0, 'drainage'),
            _p(29, 'road'),
            _p(30, 'road'), // one day outside the range
            _p(3, 'flying_saucer'), // not a category the app knows
            _p(-1, 'waste'), // tomorrow (clock skew) — outside the range
          ],
          days: 30,
          now: _now,
        );
        expect(t.bucketDays, 1);
        expect(t.bucketCount, 30);
        expect(t.bucketStarts.last, DateTime(2026, 10, 13));
        expect(t.counts['drainage']!.last, 2);
        expect(t.counts['road']!.first, 1);
        expect(t.totals['road'], 1);
        expect(t.totals['others'], 1);
        expect(t.totals['waste'], 0);
        expect(t.total, 4);
        expect(t.bucketLabel(29), '13 Oct');
      },
    );

    test(
      '90 days: one point per WEEK, and the totals still cover exactly 90 days',
      () {
        final t = CategoryTrend.build(
          [
            _p(0, 'road'),
            _p(6, 'road'),
            _p(7, 'road'),
            _p(89, 'waste'),
            _p(90, 'waste'),
          ],
          days: 90,
          now: _now,
        );
        expect(t.bucketDays, 7);
        expect(t.bucketCount, 13); // 12 full weeks + a 6-day one
        expect(t.totals['road'], 3);
        expect(t.totals['waste'], 1); // day 90 is outside "the last 90 days"
        expect(t.counts['waste']!.first, 1);
        expect(t.bucketLabel(0), startsWith('Week of '));
      },
    );

    test('every category keeps its own colour, in a fixed order', () {
      expect(kReportCategorySeries.map((s) => s.key), [
        'road',
        'waste',
        'drainage',
        'streetlight',
        'environment',
        'others',
      ]);
      expect(kReportCategorySeries.map((s) => s.color).toSet(), hasLength(6));
    });
  });

  // ── The chart widget ───────────────────────────────────────────────────────
  final points = [
    for (var i = 0; i < 30; i++) ...[
      if (i % 2 == 0) _p(i, 'drainage'),
      if (i % 3 == 0) _p(i, 'road'),
      if (i % 5 == 0) _p(i, 'waste'),
    ],
    _p(2, 'environment'),
  ];

  Widget chartIn(double maxWidth, {int days = 30, List<ReportPoint>? data}) =>
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: ReportCategoryTrend(
                  points: data ?? points,
                  days: days,
                  now: _now,
                ),
              ),
            ),
          ),
        ),
      );

  group('ReportCategoryTrend', () {
    testWidgets('a legend names every category with its total', (t) async {
      await pumpAt(
        t,
        const Device('laptop', Size(1280, 900)),
        () => chartIn(800),
      );
      for (final s in kReportCategorySeries) {
        expect(find.text(s.label), findsOneWidget, reason: s.label);
      }
      expect(
        find.bySemanticsLabel(RegExp(r'^Drainage & Flooding, 15 reports')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'^Streetlight Outage, 0 reports$')),
        findsOneWidget,
      );
      expect(find.textContaining('reports in 30 days'), findsOneWidget);
      expect(
        find.text('Most reported: Drainage & Flooding (15, 47%)'),
        findsOneWidget,
      );
    });

    testWidgets('tapping a category highlights it; tapping again clears it', (
      t,
    ) async {
      await pumpAt(
        t,
        const Device('laptop', Size(1280, 900)),
        () => chartIn(800),
      );
      Finder item() =>
          find.bySemanticsLabel(RegExp(r'^Road & Infrastructure,'));
      bool selected() =>
          t.getSemantics(item()).flagsCollection.isSelected == Tristate.isTrue;
      expect(selected(), isFalse);
      await t.tap(item());
      await t.pump();
      expect(selected(), isTrue);
      await t.tap(item());
      await t.pump();
      expect(selected(), isFalse);
    });

    testWidgets('a phone legend is a grid of short names', (t) async {
      await pumpAt(t, kModernPhone, () => chartIn(800));
      for (final s in kReportCategorySeries) {
        expect(find.text(s.shortLabel), findsOneWidget, reason: s.shortLabel);
      }
      expect(find.text('Road & Infrastructure'), findsNothing);
      final road = t.getTopLeft(find.text('Road'));
      final waste = t.getTopLeft(find.text('Waste'));
      expect(waste.dy, road.dy, reason: 'two to a row');
    });

    testWidgets('a tie names every leader', (t) async {
      await pumpAt(
        t,
        const Device('laptop', Size(1280, 900)),
        () => chartIn(
          800,
          data: [
            _p(1, 'road'),
            _p(2, 'road'),
            _p(1, 'waste'),
            _p(3, 'waste'),
            _p(1, 'others'),
          ],
        ),
      );
      expect(
        find.text(
          'Most reported: Road & Infrastructure and Waste & Garbage (2 each)',
        ),
        findsOneWidget,
      );
    });

    testWidgets('nothing in range reads as a fact, not an empty frame', (
      t,
    ) async {
      await pumpAt(t, kModernPhone, () => chartIn(800, data: const []));
      expect(find.text('No reports in the last 30 days.'), findsOneWidget);
    });

    for (final scale in [1.0, 1.3]) {
      for (final days in [7, 30, 90]) {
        testWidgets('no overflow anywhere — $days days @${scale}x', (t) async {
          final failures = <String>[];
          for (final d in _everyScreen) {
            final errors = await pumpAt(
              t,
              d,
              () => chartIn(1120, days: days),
              textScale: scale,
            );
            if (errors.isNotEmpty) failures.add('$d: ${errors.join(' | ')}');
          }
          expect(failures, isEmpty, reason: failures.join('\n'));
        });
      }
    }
  });

  // ── Surge grouping ─────────────────────────────────────────────────────────
  group('groupSurges', () {
    test('one group per category + barangay, biggest first', () {
      final groups = groupSurges([
        _report('a1', hoursAgo: 3),
        _report('a2', hoursAgo: 2),
        _report('a3', hoursAgo: 1),
        _report('b1', cat: 'road', label: 'Road & Infrastructure', recent: 7),
        _report('n1', surge: false), // similar but not a surge
        _report('d1', duplicateOf: 'a1'), // already merged
      ]);
      expect(groups, hasLength(2));
      expect(groups.first.representative.id, 'b1');
      expect(groups.first.recentCount, 7);
      expect(groups.last.recentCount, 5);
    });

    test('the ticket to open is one still on the triage desk', () {
      final groups = groupSurges([
        _report(
          'old',
          hoursAgo: 9,
          status: ReportStatus.underReview,
          assignedTo: 'Engineering Office',
        ),
        _report('new', hoursAgo: 1),
      ]);
      expect(groups.single.representative.id, 'new');
    });
  });

  // ── Admin flood widgets ────────────────────────────────────────────────────
  Widget banner() => MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ReportSurgeBanner(
          surges: groupSurges([
            _report('a1'),
            _report(
              'b1',
              cat: 'environment',
              label: 'Environment & Pollution',
              barangay: 'Barangay San Antonio de Padua Poblacion Norte',
              recent: 12,
            ),
            _report(
              'c1',
              cat: 'waste',
              label: 'Waste & Garbage',
              barangay: 'Bulala',
            ),
            _report(
              'e1',
              cat: 'road',
              label: 'Road & Infrastructure',
              barangay: 'Maura',
            ),
          ]),
          onReview: (_) {},
        ),
      ),
    ),
  );

  group('ReportSurgeBanner', () {
    testWidgets('names the issue, the place and the count, and caps at three', (
      t,
    ) async {
      await pumpAt(t, kModernPhone, banner);
      expect(find.text('Many reports about the same issue'), findsOneWidget);
      expect(find.text('Review'), findsNWidgets(3));
      expect(find.textContaining('+1 more group'), findsOneWidget);
      expect(
        find.textContaining('Environment & Pollution', findRichText: true),
        findsOneWidget,
      );
    });

    for (final scale in [1.0, 1.3]) {
      testWidgets('no overflow anywhere @${scale}x', (t) async {
        final failures = <String>[];
        for (final d in _everyScreen) {
          final errors = await pumpAt(t, d, banner, textScale: scale);
          if (errors.isNotEmpty) failures.add('$d: ${errors.join(' | ')}');
        }
        expect(failures, isEmpty, reason: failures.join('\n'));
      });
    }
  });

  testWidgets(
    'SimilarReportsChip: words when there is room, a count, then a glyph',
    (t) async {
      await t.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SimilarReportsChip(4),
                SimilarReportsChip(4, density: ChipDensity.compact),
                SimilarReportsChip(4, density: ChipDensity.icon, surge: true),
              ],
            ),
          ),
        ),
      );
      expect(find.text('4 similar'), findsOneWidget);
      expect(find.text('+4'), findsOneWidget);
      expect(find.byIcon(Icons.copy_all_rounded), findsNWidgets(3));
    },
  );

  // ── Citizen: "You already reported this" ───────────────────────────────────
  Widget dialogHost(void Function(AlreadyReportedChoice?) onResult) =>
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => onResult(
                  await showAlreadyReportedDialog(
                    context,
                    shortRef: 'AB12CD34',
                    filedAt: DateTime.now(),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

  test('filedAgo reads as words', () {
    final now = DateTime(2026, 10, 13, 9);
    expect(filedAgo(DateTime(2026, 10, 13, 1), now), 'today');
    expect(filedAgo(DateTime(2026, 10, 12, 23), now), 'yesterday');
    expect(filedAgo(DateTime(2026, 10, 10), now), '3 days ago');
    expect(filedAgo(DateTime(2026, 9, 20), now), '3 weeks ago');
  });

  group('AlreadyReportedDialog', () {
    testWidgets(
      'explains, offers the report they have, and never "file anyway"',
      (t) async {
        AlreadyReportedChoice? got;
        await pumpAt(t, kModernPhone, () => dialogHost((c) => got = c));
        await t.tap(find.text('open'));
        await t.pumpAndSettle();
        expect(find.text('You already reported this'), findsOneWidget);
        expect(
          find.textContaining('RPT-AB12CD34 · still open'),
          findsOneWidget,
        );
        expect(find.textContaining('different'), findsNothing);
        await t.tap(find.text('View my reports'));
        await t.pumpAndSettle();
        expect(got, AlreadyReportedChoice.viewMine);

        await t.tap(find.text('open'));
        await t.pumpAndSettle();
        await t.tap(find.text('Go back and edit'));
        await t.pumpAndSettle();
        expect(got, AlreadyReportedChoice.editDraft);
      },
    );

    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('both actions stay on screen everywhere @${scale}x', (
        t,
      ) async {
        final failures = <String>[];
        for (final d in _everyScreen) {
          final errors = await pumpAt(
            t,
            d,
            () => dialogHost((_) {}),
            textScale: scale,
            after: (t) async {
              await t.tap(find.text('open'));
              await t.pumpAndSettle();
            },
          );
          if (errors.isNotEmpty) failures.add('$d: ${errors.join(' | ')}');
          for (final label in ['View my reports', 'Go back and edit']) {
            final r = t.getRect(find.text(label));
            if (r.bottom > d.size.height || r.top < 0) {
              failures.add('$d: "$label" off screen at ${r.top}');
            }
          }
        }
        expect(failures, isEmpty, reason: failures.join('\n'));
      });
    }
  });
}
