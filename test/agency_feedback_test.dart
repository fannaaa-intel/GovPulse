// Panel revision item 3 — citizen ratings of external agencies, and the admin
// "Agency performance" panel. The SQL side is proven by
// supabase/diagnostics/verify_20261013000000.sql; this covers the two widgets.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/admin/providers/admin_agency_performance_provider.dart';
import 'package:govpulse/features/admin/widgets/admin_agency_performance.dart';
import 'package:govpulse/features/home/my_report/agency_rating_card.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

class _FakeApi extends AgencyRatingApi {
  AgencyRatingStatus status;
  Object? loadError;
  final List<(int, String?)> saves = [];
  AgencyRatingSaveResult Function() answer = () =>
      const AgencyRatingSaveResult.ok();
  Completer<void>? gate;
  int loads = 0;

  _FakeApi(this.status);

  @override
  Future<AgencyRatingStatus> load(String reportId) async {
    loads++;
    if (loadError != null) throw loadError!;
    return status;
  }

  @override
  Future<AgencyRatingSaveResult> save(
    String reportId,
    int stars,
    String? comment,
  ) async {
    saves.add((stars, comment));
    if (gate != null) await gate!.future;
    return answer();
  }
}

Future<void> _pumpCard(
  WidgetTester t,
  _FakeApi api, {
  double width = 390,
  double textScale = 1.0,
}) async {
  t.view.physicalSize = Size(width, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 900),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            // The page's scale width is capped at 480 (kUiScaleMaxWidth).
            child: AgencyRatingCard(
              reportId: 'r1',
              w: width > 480 ? 480 : width,
              api: api,
            ),
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Finder _button(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(FilledButton));

bool _enabled(WidgetTester t, String label) =>
    t.widget<FilledButton>(_button(label)).onPressed != null;

const _endorsed = AgencyRatingStatus(
  eligible: true,
  agency: 'DPWH',
  state: 'endorsed',
);

void main() {
  group('Citizen agency rating card', () {
    testWidgets('takes no space when there is nothing to rate', (t) async {
      await _pumpCard(t, _FakeApi(AgencyRatingStatus.ineligible));
      expect(find.textContaining('How did'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('says plainly when the agency has not acknowledged it yet', (
      t,
    ) async {
      await _pumpCard(t, _FakeApi(_endorsed));
      expect(find.text('How did DPWH handle this?'), findsOneWidget);
      expect(
        find.textContaining("hasn't confirmed receiving your report yet"),
        findsOneWidget,
      );
      expect(
        find.text('Only LGU administrators see ratings, not the agency.'),
        findsOneWidget,
      );
    });

    testWidgets('send stays disabled until a star is picked, then saves once', (
      t,
    ) async {
      final api = _FakeApi(_endorsed);
      await _pumpCard(t, api);

      expect(find.text('Tap a star to rate'), findsOneWidget);
      expect(_enabled(t, 'Send rating'), isFalse);

      await t.tap(find.bySemanticsLabel('4 stars, Good'));
      await t.pumpAndSettle();
      expect(find.text('Good'), findsOneWidget);
      expect(_enabled(t, 'Send rating'), isTrue);

      await t.enterText(find.byType(TextField), '  fixed the pothole  ');
      await t.tap(_button('Send rating'));
      await t.pumpAndSettle();

      expect(api.saves, [(4, 'fixed the pothole')]);
      expect(
        find.text('Thank you. Your rating was sent to the LGU.'),
        findsOneWidget,
      );
      // Saved: the form folds into a summary with an Edit control.
      expect(find.text('Your rating of DPWH'), findsOneWidget);
      expect(find.text('“fixed the pothole”'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.text('Edit'), findsOneWidget);
    });

    testWidgets('a double tap inside one frame saves only once', (t) async {
      final api = _FakeApi(_endorsed)..gate = Completer<void>();
      await _pumpCard(t, api);
      await t.tap(find.bySemanticsLabel('5 stars, Excellent'));
      await t.pumpAndSettle();

      final onPressed = t.widget<FilledButton>(_button('Send rating')).onPressed!;
      onPressed();
      onPressed();
      api.gate!.complete();
      await t.pumpAndSettle();

      expect(api.saves, hasLength(1));
    });

    testWidgets('an existing rating opens prefilled, as an edit', (t) async {
      final api = _FakeApi(
        const AgencyRatingStatus(
          eligible: true,
          agency: 'BFP',
          state: 'completed',
          stars: 2,
          comment: 'slow',
        ),
      );
      await _pumpCard(t, api);
      // Opens as a summary, not an open form.
      expect(find.text('Your rating of BFP'), findsOneWidget);
      expect(find.text('Fair'), findsOneWidget);
      expect(find.text('“slow”'), findsOneWidget);
      expect(
        find.textContaining('has marked the work on your report as done'),
        findsOneWidget,
      );
      expect(find.byType(FilledButton), findsNothing);

      await t.tap(find.text('Edit'));
      await t.pumpAndSettle();
      expect(find.text('slow'), findsOneWidget); // prefilled in the field
      expect(_enabled(t, 'Update rating'), isFalse); // nothing changed yet

      await t.tap(find.bySemanticsLabel('3 stars, Okay'));
      await t.pumpAndSettle();
      expect(_enabled(t, 'Update rating'), isTrue);

      // Cancel throws the draft away and shows the saved rating again.
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(find.text('Fair'), findsOneWidget);
      expect(api.saves, isEmpty);
    });

    testWidgets('the daily limit is explained, not swallowed', (t) async {
      final api = _FakeApi(_endorsed)
        ..answer = () => const AgencyRatingSaveResult.failed('rate_limited');
      await _pumpCard(t, api);
      await t.tap(find.bySemanticsLabel('1 star, Poor'));
      await t.pumpAndSettle();
      await t.tap(_button('Send rating'));
      await t.pumpAndSettle();
      expect(
        find.textContaining('changed ratings many times today'),
        findsOneWidget,
      );
    });

    testWidgets('a withdrawn endorsement reloads and the card goes away', (
      t,
    ) async {
      final api = _FakeApi(_endorsed);
      api.answer = () {
        api.status = AgencyRatingStatus.ineligible;
        return const AgencyRatingSaveResult.failed('withdrawn');
      };
      await _pumpCard(t, api);
      await t.tap(find.bySemanticsLabel('2 stars, Fair'));
      await t.pumpAndSettle();
      await t.tap(_button('Send rating'));
      await t.pumpAndSettle();
      expect(api.loads, 2);
      expect(find.textContaining('How did'), findsNothing);
    });

    testWidgets('a failed load shows Retry instead of vanishing', (t) async {
      final api = _FakeApi(_endorsed)..loadError = Exception('offline');
      await _pumpCard(t, api);
      expect(find.text("Couldn't load the agency rating."), findsOneWidget);

      api.loadError = null;
      await t.tap(find.text('Retry'));
      await t.pumpAndSettle();
      expect(find.text('How did DPWH handle this?'), findsOneWidget);
    });

    test('only a missing function means "nothing to rate"', () {
      expect(
        AgencyRatingApi.isFunctionMissing(
          const PostgrestException(message: 'not found', code: 'PGRST202'),
        ),
        isTrue,
      );
      expect(
        AgencyRatingApi.isFunctionMissing(
          const PostgrestException(message: 'denied', code: '42501'),
        ),
        isFalse,
      );
    });

    testWidgets('fits a 320px phone at 1.3x text with a long comment', (
      t,
    ) async {
      final api = _FakeApi(
        AgencyRatingStatus(
          eligible: true,
          agency: 'DENR',
          state: 'received',
          stars: 5,
          comment: 'Napakabilis ng pagtugon ' * 18,
        ),
      );
      await _pumpCard(t, api, width: 320, textScale: 1.3);
      expect(t.takeException(), isNull);
      await t.tap(find.text('Edit'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.text('Update rating'), findsOneWidget);
    });

    testWidgets('narrow card stacks the footer; wide card keeps one row', (
      t,
    ) async {
      Future<double> buttonWidth(double width) async {
        final api = _FakeApi(_endorsed);
        await _pumpCard(t, api, width: width);
        await t.tap(find.bySemanticsLabel('4 stars, Good'));
        await t.pumpAndSettle();
        return t.getSize(_button('Send rating')).width;
      }

      // 390 screen, 16px page padding: the card is 358 wide → full-width button.
      expect(await buttonWidth(390), greaterThan(300));
      // A web report band: the button sits beside the note at its own width.
      expect(await buttonWidth(820), lessThan(220));
    });
  });

  group('Admin agency performance', () {
    test('every canonical agency appears, extras after them', () {
      final merged = mergeWithCanonicalAgencies(const [
        AgencyPerformance(agency: 'Old Agency', endorsements: 1),
        AgencyPerformance(agency: 'DOH', endorsements: 3, completed: 2),
      ]);
      expect(merged.map((a) => a.agency), [
        'DPWH',
        'DENR',
        'DOH',
        'BFP',
        'PNP',
        'Old Agency',
      ]);
      expect(merged[2].completed, 2);
      expect(merged[0].receivedShare, isNull);
    });

    final data = AgencyPerformanceData(
      agencies: mergeWithCanonicalAgencies(const [
        AgencyPerformance(
          agency: 'DPWH',
          endorsements: 4,
          awaiting: 1,
          received: 3,
          completed: 2,
          withdrawn: 1,
          avgDaysToReceive: 1.5,
          avgDaysToComplete: 6,
          ratings: 3,
          avgStars: 3.67,
        ),
      ]),
      recent: [
        AgencyComment(
          agency: 'DPWH',
          stars: 2,
          comment: 'Took a week to even look at it. ' * 6,
          state: 'endorsed',
          at: DateTime(2026, 10, 13),
        ),
        AgencyComment(
          agency: 'DPWH',
          stars: 5,
          comment: null,
          state: 'completed',
          at: DateTime(2026, 10, 12),
        ),
      ],
    );

    Future<void> pumpPanel(WidgetTester t, double width, double scale) async {
      t.view.physicalSize = Size(width, 1600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 1600),
              textScaler: TextScaler.linear(scale),
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(14),
                child: AgencyPerformanceView(data: data),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
    }

    testWidgets('wide: a table with shares, timings and stars', (t) async {
      await pumpPanel(t, 1120, 1.0);
      expect(t.takeException(), isNull);
      expect(find.text('AVG. TO COMPLETE'), findsOneWidget);
      expect(find.text('6 days'), findsOneWidget);
      expect(find.text('1.5 days'), findsOneWidget);
      expect(find.text('3.7'), findsOneWidget);
      expect(find.text('1 awaiting receipt · 1 withdrawn'), findsOneWidget);
      // The four agencies with nothing yet still show, as facts.
      expect(find.text('No ratings yet'), findsNWidgets(4));
      expect(find.text('PNP'), findsOneWidget);
      expect(find.textContaining('rated before receipt'), findsOneWidget);
      expect(find.textContaining('rated after completion'), findsOneWidget);
    });

    for (final (w, s) in [(360.0, 1.3), (600.0, 1.0), (699.0, 1.3)]) {
      testWidgets('narrow ${w.toInt()}px @${s}x: cards, no overflow', (
        t,
      ) async {
        await pumpPanel(t, w, s);
        expect(t.takeException(), isNull);
        expect(find.text('AVG. TO COMPLETE'), findsNothing);
        expect(find.text('Avg. to complete'), findsNWidgets(5));
      });
    }

    testWidgets('no ratings yet reads as a fact, not a blank', (t) async {
      t.view.physicalSize = const Size(1120, 1200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AgencyPerformanceView(
              data: AgencyPerformanceData(
                agencies: mergeWithCanonicalAgencies(const []),
                recent: const [],
              ),
            ),
          ),
        ),
      );
      expect(find.text('No citizen has rated an agency yet.'), findsOneWidget);
      expect(find.text('No ratings yet'), findsNWidgets(5));
    });
  });
}
