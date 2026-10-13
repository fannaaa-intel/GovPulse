// Agency feedback across every screen it can appear on: phones (portrait and
// landscape), tablets, and desktop browser widths, at 1.0x and 1.3x text, with
// worst-case content. Each case runs inside the real page geometry: the report
// detail band for the citizen card (scaled by uiScaleWidth, as the screen
// does), and the Team page's padded 1120 column for the admin panel.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/theme/mobile_metrics.dart';
import 'package:govpulse/features/admin/providers/admin_agency_performance_provider.dart';
import 'package:govpulse/features/admin/widgets/admin_agency_performance.dart';
import 'package:govpulse/features/home/my_report/agency_rating_card.dart';

import '_responsive_matrix.dart';

class _Api extends AgencyRatingApi {
  final AgencyRatingStatus status;
  final bool fail;
  const _Api(this.status, {this.fail = false});

  @override
  Future<AgencyRatingStatus> load(String reportId) async {
    if (fail) throw Exception('offline');
    return status;
  }

  @override
  Future<AgencyRatingSaveResult> save(String r, int s, String? c) async =>
      const AgencyRatingSaveResult.ok();
}

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

const _longComment =
    'Dalawang linggo na po at wala pa ring tumitingin sa gumuhong culvert sa '
    'tabi ng paaralan. Delikado po ito sa mga batang dumadaan tuwing umaga. '
    'Sanapakabilisngpagtugonnaminpagdatingsamgaganitongproblemangkalsada.';

Widget _citizenPage(AgencyRatingApi api) => MaterialApp(
  home: Builder(
    builder: (context) {
      final w = uiScaleWidth(context);
      return Scaffold(
        body: SingleChildScrollView(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 816),
              child: Padding(
                padding: EdgeInsets.all(w * .04),
                child: AgencyRatingCard(reportId: 'r', w: w, api: api),
              ),
            ),
          ),
        ),
      );
    },
  ),
);

final _perf = AgencyPerformanceData(
  agencies: mergeWithCanonicalAgencies(const [
    AgencyPerformance(
      agency: 'DPWH',
      endorsements: 1240,
      awaiting: 310,
      received: 930,
      completed: 815,
      withdrawn: 47,
      avgDaysToReceive: 12.4,
      avgDaysToComplete: 148.6,
      ratings: 902,
      avgStars: 3.14,
    ),
    AgencyPerformance(
      agency: 'Provincial Disaster Risk Reduction and Management Office',
      endorsements: 3,
      received: 1,
    ),
  ]),
  recent: [
    AgencyComment(
      agency: 'DENR',
      stars: 1,
      comment: _longComment,
      state: 'endorsed',
      at: DateTime(2026, 10, 13),
    ),
    AgencyComment(
      agency: 'Provincial Disaster Risk Reduction and Management Office',
      stars: 4,
      comment: null,
      state: 'completed',
      at: DateTime(2026, 10, 12),
    ),
  ],
);

Widget _adminPage() => MaterialApp(
  home: Builder(
    builder: (context) {
      final pad = MediaQuery.sizeOf(context).width < 600 ? 14.0 : 24.0;
      return Scaffold(
        body: SingleChildScrollView(
          padding: EdgeInsets.all(pad),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: AgencyPerformanceView(data: _perf),
            ),
          ),
        ),
      );
    },
  ),
);

Future<void> _pickAndType(WidgetTester t) async {
  await t.tap(find.bySemanticsLabel('5 stars, Excellent'));
  await t.pumpAndSettle();
  await t.enterText(find.byType(TextField), _longComment);
  await t.pumpAndSettle();
}

Future<void> _openEdit(WidgetTester t) async {
  await t.tap(find.text('Edit'));
  await t.pumpAndSettle();
}

void main() {
  const unrated = AgencyRatingStatus(
    eligible: true,
    agency: 'DPWH',
    state: 'endorsed',
  );
  const rated = AgencyRatingStatus(
    eligible: true,
    agency: 'BFP',
    state: 'completed',
    stars: 2,
    comment: _longComment,
  );

  final cases = <(String, AgencyRatingApi, Future<void> Function(WidgetTester)?)>[
    ('form, star picked + long comment', const _Api(unrated), _pickAndType),
    ('saved summary, long comment', const _Api(rated), null),
    ('editing a saved rating', const _Api(rated), _openEdit),
    ('load error', const _Api(unrated, fail: true), null),
  ];

  for (final scale in [1.0, 1.3]) {
    for (final (label, api, after) in cases) {
      testWidgets('citizen card: $label @${scale}x — no overflow anywhere', (
        t,
      ) async {
        final failures = <String>[];
        for (final d in _everyScreen) {
          final errors = await pumpAt(
            t,
            d,
            () => _citizenPage(api),
            textScale: scale,
            after: after,
          );
          if (errors.isNotEmpty) failures.add('$d: ${errors.join(' | ')}');
        }
        expect(failures, isEmpty, reason: failures.join('\n'));
      });
    }

    testWidgets('admin panel @${scale}x — no overflow anywhere', (t) async {
      final failures = <String>[];
      for (final d in _everyScreen) {
        final errors = await pumpAt(t, d, _adminPage, textScale: scale);
        if (errors.isNotEmpty) failures.add('$d: ${errors.join(' | ')}');
      }
      expect(failures, isEmpty, reason: failures.join('\n'));
    });
  }

  testWidgets('every star stays a 44px target on the smallest phone', (t) async {
    await pumpAt(t, kSmallPhone, () => _citizenPage(const _Api(unrated)));
    for (var i = 1; i <= 5; i++) {
      final words = ['Poor', 'Fair', 'Okay', 'Good', 'Excellent'];
      final size = t.getSize(
        find.bySemanticsLabel('$i star${i == 1 ? '' : 's'}, ${words[i - 1]}'),
      );
      expect(size.width, greaterThanOrEqualTo(44), reason: 'star $i');
      expect(size.height, greaterThanOrEqualTo(44), reason: 'star $i');
    }
  });

  testWidgets('admin: a portrait tablet gets the table, a phone the cards', (t) async {
    await pumpAt(t, const Device('tablet', Size(768, 1024)), _adminPage);
    expect(find.text('AVG. TO COMPLETE'), findsOneWidget);
    await pumpAt(t, kModernPhone, _adminPage);
    expect(find.text('AVG. TO COMPLETE'), findsNothing);
    expect(find.text('Avg. to complete'), findsWidgets);
  });
}
