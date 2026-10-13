// Preview target for agency feedback (panel revision item 3, 2026-10-14).
//
//   flutter build web --release -t tool/preview_agency_feedback.dart -o build/preview_agency_feedback
//
// No Supabase: the citizen card runs on a fake AgencyRatingApi, and the admin
// panel is the provider-free AgencyPerformanceView fed sample rows. Shows the
// card at phone width (w=390) and at the web report band (w=480, the
// uiScaleWidth cap), then the admin panel as a table (1120) and as cards (390).
import 'package:flutter/material.dart';
import 'package:govpulse/core/services/web_splash.dart';
import 'package:govpulse/features/admin/providers/admin_agency_performance_provider.dart';
import 'package:govpulse/features/admin/widgets/admin_agency_performance.dart';
import 'package:govpulse/features/home/my_report/agency_rating_card.dart';

void main() {
  runApp(
    const MaterialApp(debugShowCheckedModeBanner: false, home: _Preview()),
  );
  WidgetsBinding.instance.endOfFrame.then((_) => removeWebSplash());
}

class _Fake extends AgencyRatingApi {
  final AgencyRatingStatus? status;
  const _Fake(this.status);

  @override
  Future<AgencyRatingStatus> load(String reportId) async {
    if (status == null) throw Exception('offline');
    return status!;
  }

  @override
  Future<AgencyRatingSaveResult> save(String r, int s, String? c) async =>
      const AgencyRatingSaveResult.ok();
}

const _unrated = AgencyRatingStatus(
  eligible: true,
  agency: 'DPWH',
  state: 'endorsed',
);
const _rated = AgencyRatingStatus(
  eligible: true,
  agency: 'BFP',
  state: 'completed',
  stars: 4,
  comment: 'They came the same day and cleared the blocked hydrant.',
);

final _data = AgencyPerformanceData(
  agencies: mergeWithCanonicalAgencies(const [
    AgencyPerformance(
      agency: 'DPWH',
      endorsements: 6,
      awaiting: 2,
      received: 4,
      completed: 3,
      withdrawn: 1,
      avgDaysToReceive: 2.4,
      avgDaysToComplete: 11.5,
      ratings: 4,
      avgStars: 2.75,
    ),
    AgencyPerformance(
      agency: 'BFP',
      endorsements: 2,
      received: 2,
      completed: 2,
      avgDaysToReceive: 0.3,
      avgDaysToComplete: 1,
      ratings: 2,
      avgStars: 4.5,
    ),
  ]),
  recent: [
    AgencyComment(
      agency: 'DPWH',
      stars: 2,
      comment: 'Two weeks and nobody has looked at the collapsed culvert yet.',
      state: 'endorsed',
      at: DateTime(2026, 10, 13),
    ),
    AgencyComment(
      agency: 'BFP',
      stars: 4,
      comment: 'They came the same day and cleared the blocked hydrant.',
      state: 'completed',
      at: DateTime(2026, 10, 12),
    ),
    AgencyComment(
      agency: 'DPWH',
      stars: 5,
      comment: null,
      state: 'completed',
      at: DateTime(2026, 10, 9),
    ),
  ],
);

class _Preview extends StatelessWidget {
  const _Preview();

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 18),
    child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
  );

  Widget _card(AgencyRatingStatus? s, double w, String id, {double? width}) =>
      Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: SizedBox(
      width: width ?? w,
      child: AgencyRatingCard(reportId: id, w: w, api: _Fake(s)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 24,
              crossAxisAlignment: WrapCrossAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Phone 320 (w=320, card 294)'),
                    _card(_unrated, 320, 'p1', width: 294),
                    _card(_rated, 320, 'p2', width: 294),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Phone 390 (w=390, card 358)'),
                    _card(_unrated, 390, 'a', width: 358),
                    _card(_rated, 390, 'b', width: 358),
                    _card(null, 390, 'c', width: 358),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Web report band (770 wide, w=480 cap)'),
                    _card(_unrated, 480, 'd', width: 770),
                    _card(_rated, 480, 'e', width: 770),
                  ],
                ),
              ],
            ),
            _label('Admin — Agency performance, wide (1120)'),
            SizedBox(width: 1120, child: AgencyPerformanceView(data: _data)),
            _label('Admin — tablet (718)'),
            SizedBox(width: 718, child: AgencyPerformanceView(data: _data)),
            _label('Admin — Agency performance, phone (362)'),
            SizedBox(width: 362, child: AgencyPerformanceView(data: _data)),
          ],
        ),
      ),
    );
  }
}
