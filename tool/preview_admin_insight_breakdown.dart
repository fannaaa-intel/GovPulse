// Dev-only harness for the ADMIN dashboard AI tab's "View all" breakdown —
// the urgency-triage list ("All reports") and the sentiment list.
//
// Not part of the app: nothing under lib/ imports it, and it is never a build
// target for a shipped bundle.
//
//   flutter build web --release -t tool/preview_admin_insight_breakdown.dart
//   python -m http.server 57816 --directory build/web
//
// ── Why this exists ────────────────────────────────────────────────────────
// The admin console is login-gated and role-gated, so a fresh browser profile
// can never reach the dashboard, and the sheet is three interactions deep:
// dashboard → AI tab → "View all N". This overrides adminDashboardProvider
// with a canned NlpInsights carrying real-shaped Tagalog report text, so the
// list can be opened and READ at each width.
//
// ── What to look at ────────────────────────────────────────────────────────
//  * < 760 CSS px (and the mobile app at any width) → a PUSHED full screen with
//    a back chevron, mirroring Recent activity. Was a bottom sheet.
//  * >= 760 on web → a centred modal card: radius 20, elevation 24, max 680
//    wide, frosted backdrop, X pinned to the card's right edge.
//  * Every row: two-line description (the card preview clips to one), the
//    barangay on its own pinned line, a filled urgency badge, and a chevron
//    that brightens on hover.
//  * Long Tagalog descriptions and the escalation chip are the overflow risk —
//    watch the last two rows, which carry both.
//  * Rows echo their tap to the banner, so the deep link is verifiable.

import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:govpulse/core/services/web_splash.dart';
import 'package:govpulse/features/admin/pages/admin_overview_page.dart';
import 'package:govpulse/features/admin/providers/admin_dashboard_provider.dart';
import 'package:govpulse/features/admin/providers/admin_reports_provider.dart'
    show ReportStatus;
import 'package:govpulse/features/admin/theme/admin_ui.dart';

void main() {
  // index.html paints a branded splash that only Dart takes down; without this
  // the preview boots to "Getting things ready" forever.
  WidgetsFlutterBinding.ensureInitialized();
  WidgetsBinding.instance.addPostFrameCallback((_) => removeWebSplash());
  runApp(
    ProviderScope(
      overrides: [adminDashboardProvider.overrideWith(_FakeDashboard.new)],
      child: const _PreviewApp(),
    ),
  );
}

// ── Canned insight data ─────────────────────────────────────────────────────

DateTime _ago(Duration d) => DateTime.now().subtract(d);

FeedbackInsightItem _report({
  required String id,
  required String title,
  required String barangay,
  required String comment,
  required String urgency,
  required Duration age,
  String? escalation,
}) => FeedbackInsightItem(
  id: id,
  title: title,
  service: barangay,
  comment: comment,
  rating: 0,
  sentiment: 'neutral',
  urgency: urgency,
  aiLabeled: true,
  escalationNote: escalation,
  createdAt: _ago(age),
);

/// The nine reports from the screenshots, verbatim — real Tagalog free text is
/// what exposes the truncation, not lorem ipsum.
final _urgencyItems = <FeedbackInsightItem>[
  _report(
    id: 'r1',
    title: 'Streetlight matters',
    barangay: 'Sanja',
    comment:
        'May natumbang puno na nakaharang sa daan pagkatapos ng malakas na '
        'hangin kagabi. Hindi madaanan ng mga sasakyan papuntang palengke.',
    urgency: 'high',
    age: const Duration(minutes: 18),
  ),
  _report(
    id: 'r2',
    title: 'Road & Infrastructure',
    barangay: 'Macanaya (Pescaria)',
    comment:
        'May malaking bitak at gumuguho na ang gilid ng national highway. '
        'Delikado sa mga motor lalo na kapag gabi at walang ilaw.',
    urgency: 'high',
    age: const Duration(minutes: 20),
    escalation: '3 similar open reports in Macanaya this week',
  ),
  _report(
    id: 'r3',
    title: 'Drainage & Flooding',
    barangay: 'Maura',
    comment:
        'Barado ang kanal sa tabi ng eskwelahan. Tuwing umuulan, bumabaha '
        'hanggang tuhod at hindi makadaan ang mga bata papasok.',
    urgency: 'high',
    age: const Duration(minutes: 23),
  ),
  _report(
    id: 'r4',
    title: 'Road & Infrastructure',
    barangay: 'Centro 5 (Pob.)',
    comment:
        'Malalim na lubak sa gitna ng kalsada malapit sa palengke. Delikado '
        'para sa mga tricycle at nadadapa na ang mga naglalakad.',
    urgency: 'high',
    age: const Duration(minutes: 26),
  ),
  _report(
    id: 'r5',
    title: 'Environment & Pollution',
    barangay: 'Macanaya (Pescaria)',
    comment:
        'Araw-araw may nagsusunog ng plastik sa bakanteng lote. Masangsang '
        'ang usok at nahihirapan huminga ang mga matatanda sa tabi.',
    urgency: 'medium',
    age: const Duration(minutes: 18),
  ),
  _report(
    id: 'r6',
    title: 'Streetlight Outage',
    barangay: 'Macanaya (Pescaria)',
    comment:
        'Tatlong poste ng ilaw ang patay sa kalyeng ito. Madilim at natatakot '
        'na dumaan ang mga estudyante pag-uwi ng gabi.',
    urgency: 'medium',
    age: const Duration(minutes: 22),
    escalation: '2 similar open reports nearby',
  ),
  _report(
    id: 'r7',
    title: 'Waste & Garbage',
    barangay: 'Punta',
    comment:
        'Hindi nakolekta ang basura sa aming kalye ng isang linggo na. '
        'Mabaho na at dinudumog ng langaw at daga.',
    urgency: 'medium',
    age: const Duration(minutes: 25),
  ),
  _report(
    id: 'r8',
    title: 'Noise complaint',
    barangay: 'Centro 3 (Pob.)',
    comment: 'Ang ingay ng karaoke ng kapitbahay hanggang madaling-araw.',
    urgency: 'low',
    age: const Duration(minutes: 21),
  ),
  _report(
    id: 'r9',
    title: 'Waste & Garbage',
    barangay: 'Macanaya (Pescaria)',
    comment:
        'Uncollected garbage piling up on our street for a week. Same as the '
        'other report but in English, to check mixed-language line breaks.',
    urgency: 'low',
    age: const Duration(minutes: 25),
  ),
];

/// Feedback rows exercise the other branch of the row: star ratings instead of
/// an urgency badge, and no barangay line.
final _sentimentItems = <FeedbackInsightItem>[
  FeedbackInsightItem(
    id: 'f1',
    title: 'Office of the Municipal Registrar',
    service: 'Birth certificate request',
    comment:
        'Ang bilis ng proseso ngayon, 20 minutes lang tapos na. Salamat sa '
        'staff na very accommodating.',
    rating: 5,
    sentiment: 'positive',
    urgency: 'low',
    aiLabeled: true,
    createdAt: _ago(const Duration(hours: 2)),
  ),
  FeedbackInsightItem(
    id: 'f2',
    title: 'Municipal Health Office',
    service: 'Medical certificate',
    comment: 'Okay naman pero matagal ang pila sa umaga.',
    rating: 3,
    sentiment: 'neutral',
    urgency: 'low',
    aiLabeled: true,
    createdAt: _ago(const Duration(hours: 5)),
  ),
  FeedbackInsightItem(
    id: 'f3',
    title: 'Business Permit and Licensing Office',
    service: 'Business permit renewal',
    comment:
        'Napakatagal ng proseso, balik-balik ako ng tatlong beses dahil kulang '
        'daw ang requirements pero hindi naman sinabi sa una.',
    rating: 1,
    sentiment: 'negative',
    urgency: 'high',
    aiLabeled: true,
    createdAt: _ago(const Duration(hours: 9)),
  ),
  FeedbackInsightItem(
    id: 'f4',
    title: 'Municipal Treasurer',
    service: 'Real property tax',
    comment: 'Maayos ang serbisyo.',
    rating: 4,
    sentiment: 'positive',
    urgency: 'low',
    aiLabeled: true,
    createdAt: _ago(const Duration(days: 1)),
  ),
  FeedbackInsightItem(
    id: 'f5',
    title: 'Civil Registry',
    service: '',
    comment: null,
    rating: 0,
    sentiment: 'neutral',
    urgency: 'low',
    aiLabeled: false,
    createdAt: _ago(const Duration(days: 2)),
  ),
];

final _data = AdminDashboardData(
  totalReports: 9,
  reportsThisWeek: 9,
  reportsWeekDeltaPct: 12,
  pendingVerification: 1,
  resolutionRate: 0.33,
  resolutionRateDeltaPts: 2,
  statusCounts: const {
    ReportStatus.pending: 5,
    ReportStatus.underReview: 2,
    ReportStatus.resolved: 2,
  },
  topCategories: const [
    CategoryStat(label: 'Road & Infrastructure', count: 2, share: 0.22),
    CategoryStat(label: 'Waste & Garbage', count: 2, share: 0.22),
  ],
  reportDates: [for (var i = 0; i < 9; i++) _ago(Duration(days: i))],
  satisfaction: SatisfactionStats.empty,
  nlp: NlpInsights(
    analyzed: 5,
    aiClassified: 4,
    positive: 2,
    neutral: 2,
    negative: 1,
    reportsAnalyzed: 9,
    reportsAiClassified: 9,
    urgentHigh: 4,
    urgentMedium: 3,
    urgentLow: 2,
    recentAvg: 3.4,
    priorAvg: 3.0,
    forecastRating: 3.6,
    trend: InsightTrend.improving,
    focus: const [],
    sentimentItems: _sentimentItems,
    urgencyItems: _urgencyItems,
  ),
  recentActivity: const [],
);

/// Serves the canned data so the page never reaches Supabase — the same seam
/// the dashboard widget test uses.
class _FakeDashboard extends AdminDashboardNotifier {
  @override
  Future<AdminDashboardData> build() async => _data;

  @override
  Future<void> refresh() async {}
}

// ── Harness ─────────────────────────────────────────────────────────────────

class _PreviewApp extends StatefulWidget {
  const _PreviewApp();
  @override
  State<_PreviewApp> createState() => _PreviewAppState();
}

@JS('previewWidth')
external JSAny? get _previewWidth;

/// Reads the capture harness's requested width, defaulting to the laptop case.
double _seedWidth() {
  final v = _previewWidth;
  if (v == null) return 1280;
  return (v as JSNumber).toDartDouble;
}

class _PreviewAppState extends State<_PreviewApp> {
  // 759/761 straddle kRecentActivityModalMinWidth, the pushed-screen vs modal
  // cutoff this sheet now shares with Recent activity; 360 is the tightest
  // phone worth supporting, and 1280 is a laptop window. 640 is kept because it
  // was the OLD cutoff - it must now render a pushed screen, not a dialog.
  // Seeded from a `window.previewWidth` global so a headless capture can pick
  // the width without having to land a synthetic click on a canvas-rendered
  // chip. Not a query parameter: Flutter's default hash URL strategy rewrites
  // the location on boot and strips `?w=` before any Dart code can read it.
  double _width = _seedWidth();
  String _lastNav = 'no navigation yet';

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF1F2937),
        body: Column(
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final w in const [
                          360.0,
                          475.0,
                          640.0,
                          759.0,
                          761.0,
                          1280.0,
                        ])
                          FilledButton(
                            onPressed: () => setState(() => _width = w),
                            style: FilledButton.styleFrom(
                              backgroundColor: _width == w
                                  ? Colors.white
                                  : Colors.white24,
                              foregroundColor: _width == w
                                  ? Colors.black
                                  : Colors.white,
                            ),
                            child: Text('${w.toInt()} px'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Open the AI tab → "View all 9".   onNavigate → $_lastNav',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: SizedBox(
                  width: _width,
                  child: ClipRect(
                    child: Builder(
                      builder: (outer) {
                        final mq = MediaQuery.of(outer);
                        return MediaQuery(
                          // The launcher reads MediaQuery width, so the
                          // override is what decides sheet vs dialog.
                          data: mq.copyWith(
                            size: Size(_width, mq.size.height - 120),
                          ),
                          child: Container(
                            color: AdminUi.pageBg,
                            child: Navigator(
                              onGenerateRoute: (_) => MaterialPageRoute(
                                builder: (_) => AdminOverviewPage(
                                  selectedIndex: 0,
                                  onNavigate: (i, {String? highlightId}) {
                                    setState(() {
                                      _lastNav =
                                          'tab $i · highlight: '
                                          '${highlightId ?? 'none'}';
                                    });
                                  },
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
