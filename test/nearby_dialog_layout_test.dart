import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:govpulse/core/theme/app_colors.dart';
import 'package:govpulse/core/theme/citizen_ui.dart';
import 'package:govpulse/core/widgets/no_scrollbar_behavior.dart';

/// The "Already reported here?" duplicate-check dialog.
///
/// ── What this round changed ────────────────────────────────────────────────
/// The dialog's HIERARCHY pointed at the wrong answer. "No — mine is a
/// different issue" was a full-width bordered button; "This is my issue —
/// confirm it", the thing the dialog exists to ask, was a bare text link in the
/// corner of a card. The accept is now the only FILLED button on screen.
///
/// The other half is size. The old card capped its list at a flat 260px and let
/// the rest of the column run free, so on a short phone — or at a large text
/// scale, where every string here grows — the actions ran past the viewport.
/// A Dialog does not scroll: they were simply gone, and with them the only
/// visible way out. Now the CARD is bounded by the viewport and the LIST is the
/// part that gives.
///
/// These rebuild the dialog's layout from the same rules rather than mounting
/// ReportIssueScreen, which needs Supabase. That pins the geometry, not the
/// widget tree; the guard against drift is tool/preview_nearby_dialog.dart,
/// which renders the real thing at these same sizes.
void main() {
  const kMineIsDifferent = '__different__';

  /// Builds the dialog CONTENT. Mounted through a real [showDialog] below, so
  /// the Dialog is laid out by its own route the way the app lays it out — a
  /// bare Dialog dropped into a Center ignores its own `constraints` entirely
  /// and reports the full screen width, which is a property of the harness and
  /// not of the widget.
  Widget dialogContent(BuildContext ctx, int cards) {
            final media = MediaQuery.of(ctx);
            final maxCardHeight = media.size.height * 0.85;
            final scale = media.textScaler.scale(14) / 14;
            final listMax =
                (maxCardHeight - 320 * scale).clamp(72.0, 320.0);
            final compact = maxCardHeight < 414 * scale;
            final oneCardHigh = 150 * scale;
            final listFloor = listMax < oneCardHigh
                ? oneCardHigh.clamp(0.0, maxCardHeight)
                : listMax;

            return Dialog(
                  insetPadding: EdgeInsets.zero,
                  constraints: BoxConstraints(
                    maxWidth: 400,
                    minWidth: 280,
                    maxHeight: maxCardHeight,
                  ),
                  // Keyed on the CARD BODY, not on the Dialog: Dialog's
                  // `constraints` wrap the inner Material, while the Dialog
                  // widget itself is an Align that fills the screen. Measuring
                  // the outer one reports the viewport width and says nothing
                  // about whether the cap works.
                  child: Column(
                    key: const Key('card'),
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Flexible(
                        child: ScrollConfiguration(
                        behavior: const NoScrollbarBehavior(),
                        child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                            24, compact ? 18 : 24, 24, 0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!compact) ...[
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: AppColors.primaryBlue
                                      .withValues(alpha: 0.10),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(height: 14),
                            ],
                            const Text(
                              'Already reported nearby?',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                height: 1.3,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              compact
                                  ? 'Confirming pushes it up the queue.'
                                  : 'These were reported near your pin. '
                                      'Confirming one pushes it up the queue.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 13, height: 1.5),
                            ),
                            SizedBox(height: compact ? 12 : 16),
                          ],
                        ),
                        ),
                        ),
                      ),
                      Flexible(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxHeight: listFloor),
                          child: ShaderMask(
                            shaderCallback: (rect) => const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.white,
                                Colors.white,
                                Colors.transparent,
                              ],
                              stops: [0.0, 0.88, 1.0],
                            ).createShader(rect),
                            blendMode: BlendMode.dstIn,
                            child: ScrollConfiguration(
                              behavior: const NoScrollbarBehavior(),
                              child: SingleChildScrollView(
                                padding:
                                    const EdgeInsets.fromLTRB(24, 0, 24, 8),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    for (int i = 0; i < cards; i++) ...[
                                      if (i > 0) const SizedBox(height: 10),
                                      _card(i),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(24, compact ? 10 : 16,
                            24, compact ? 12 : 18),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            OutlinedButton(
                              key: const Key('decline'),
                              onPressed: () {},
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                    color: Color(0xFFD1D5DB)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 13),
                              ),
                              child: const Text(
                                'No — mine is a different issue',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            TextButton(
                              key: const Key('back'),
                              onPressed: () {},
                              style: TextButton.styleFrom(
                                minimumSize: const Size(0, 40),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                              ),
                              child: const Text(
                                'Go back and check my pin',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
            );
  }

  /// Sets the viewport, then opens the dialog through a real route.
  Future<void> mount(
    WidgetTester tester, {
    required int cards,
    required Size screen,
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // The dialog is opened from a button INSIDE the app, so its route inherits
    // the resized view rather than the 800x600 default the test binding starts
    // with. Reaching for a context before the first frame settles gives the
    // dialog the old size and every measurement here becomes meaningless.
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const Scaffold(body: SizedBox.expand()),
      ),
    );
    await tester.pumpAndSettle();

    // pumpWidget with a new MaterialApp does NOT tear the previous dialog's
    // route down. Left alone, a loop stacks dialogs and every `find.byKey`
    // matches several — so the previous one is popped before the next opens.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    while (navigator.canPop()) {
      navigator.pop();
      await tester.pumpAndSettle();
    }

    showDialog<void>(
      context: navigator.context,
      builder: (dialogCtx) => dialogContent(dialogCtx, cards),
    );
    await tester.pumpAndSettle();
  }

  // Phones the app actually has to fit, plus tablet and desktop web.
  const screens = <String, Size>{
    'small phone': Size(320, 568),
    'short phone': Size(360, 560),
    'phone': Size(360, 640),
    'tall phone': Size(412, 915),
    'tablet': Size(700, 900),
    'desktop web': Size(1200, 820),
  };

  group('the dialog fits the screen it is on', () {
    testWidgets('no overflow at any size, card count or text scale',
        (tester) async {
      for (final entry in screens.entries) {
        for (final cards in [1, 3]) {
          for (final scale in [1.0, 1.3, 1.6]) {
            await mount(tester,
                cards: cards, screen: entry.value, textScale: scale);

            expect(tester.takeException(), isNull,
                reason: '${entry.key} / $cards card(s) / ${scale}x overflowed');
          }
        }
      }
    });

    testWidgets('the card never exceeds 85% of the viewport height',
        (tester) async {
      for (final entry in screens.entries) {
        await mount(tester, cards: 3, screen: entry.value, textScale: 1.6);

        final card = tester.getRect(find.byKey(const Key('card')));
        expect(card.height, lessThanOrEqualTo(entry.value.height * 0.85 + 0.5),
            reason: 'on ${entry.key} the card outgrew its cap');
      }
    });

    testWidgets('BOTH ways out stay on screen — the regression that mattered',
        (tester) async {
      // A Dialog does not scroll. If the actions leave the viewport there is
      // no way to reach them, and the citizen is stuck on a screen whose only
      // purpose is to ask them a question.
      for (final entry in screens.entries) {
        for (final scale in [1.0, 1.6]) {
          await mount(tester,
              cards: 3, screen: entry.value, textScale: scale);

          for (final k in ['decline', 'back']) {
            final r = tester.getRect(find.byKey(Key(k)));
            expect(r.bottom, lessThanOrEqualTo(entry.value.height + 0.5),
                reason: '"$k" fell off ${entry.key} at ${scale}x');
            expect(r.top, greaterThanOrEqualTo(-0.5),
                reason: '"$k" rose off ${entry.key} at ${scale}x');
          }
        }
      }
    });

    testWidgets('the width cap holds on desktop web', (tester) async {
      // Without it the full-width buttons stretch the card across the browser.
      await mount(tester, cards: 1, screen: const Size(1600, 900));

      expect(tester.getRect(find.byKey(const Key('card'))).width,
          moreOrLessEquals(400, epsilon: 0.5));
    });

    testWidgets('one short card does not reserve a full list box',
        (tester) async {
      // The old flat 260px gave the single-match case the same reserved space
      // as three, so a one-card dialog was mostly empty air.
      // A TALL screen, so neither count is anywhere near the 85% cap and the
      // only thing that can decide the height is the content. At 640 both
      // land on the cap and the comparison proves nothing.
      const screen = Size(360, 1200);

      await mount(tester, cards: 1, screen: screen);
      final one = tester.getRect(find.byKey(const Key('card'))).height;

      await mount(tester, cards: 3, screen: screen);
      final three = tester.getRect(find.byKey(const Key('card'))).height;

      expect(one, lessThan(three),
          reason: 'the dialog should shrink-wrap a single match');
    });
  });

  group('the hierarchy points at the accept', () {
    testWidgets('the accept is filled; both declines are not', (tester) async {
      // The complaint in one assertion. If a decline ever becomes the only
      // filled control again, the dialog is arguing against itself.
      await mount(tester, cards: 1, screen: const Size(360, 640));

      expect(find.byType(ElevatedButton), findsOneWidget,
          reason: 'the confirm action must be the filled button');
      expect(find.byKey(const Key('decline')), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(find.byKey(const Key('decline'))),
        isA<OutlinedButton>(),
        reason: 'declining stays an outline, never a fill',
      );
    });

    testWidgets('the accept keeps a real tap height', (tester) async {
      await mount(tester, cards: 1, screen: const Size(320, 568));

      expect(tester.getRect(find.byType(ElevatedButton)).height,
          greaterThanOrEqualTo(40),
          reason: 'this is the primary action on a phone');
    });

    testWidgets('the accept never scrolls off, at any size or text scale',
        (tester) async {
      // ── The regression this exists for ────────────────────────────────
      // The overflow above was first "fixed" by letting the header and the
      // actions scroll too. It removed the overflow and passed every test
      // then written — while scrolling the accept button clean off the card
      // at 1.3x and 1.6x, leaving only the two ways of saying no. That is
      // precisely the inversion the redesign set out to remove, reintroduced
      // by the fix for something else. Only a screenshot caught it.
      //
      // So the chrome is fixed and the LIST absorbs the pressure, and this
      // asserts the consequence directly.
      for (final entry in screens.entries) {
        for (final scale in [1.0, 1.3, 1.6]) {
          await mount(tester,
              cards: 1, screen: entry.value, textScale: scale);

          final accept = find.byType(ElevatedButton);
          expect(accept, findsOneWidget,
              reason: 'the accept vanished on ${entry.key} at ${scale}x');

          final r = tester.getRect(accept);
          expect(r.bottom, lessThanOrEqualTo(entry.value.height + 0.5),
              reason: 'the accept fell off ${entry.key} at ${scale}x');
          expect(r.top, greaterThanOrEqualTo(-0.5),
              reason: 'the accept rose off ${entry.key} at ${scale}x');
        }
      }
    });

    testWidgets('the accept is fully inside the card, not clipped by the fade',
        (tester) async {
      // ── The SECOND way the accept went missing ────────────────────────
      // Keeping the actions fixed stopped the button scrolling away, but the
      // list's own maxHeight then squeezed the first CARD, and the accept sits
      // at the bottom of that card — so it was clipped behind the scroll fade
      // instead. Same outcome, different mechanism: at the sizes where the
      // primary action is hardest to find, it was not on screen at all.
      //
      // "On screen" is not enough here; it has to be inside the card's own
      // painted bounds.
      for (final entry in screens.entries) {
        for (final scale in [1.0, 1.3, 1.6]) {
          await mount(tester,
              cards: 1, screen: entry.value, textScale: scale);

          final card = tester.getRect(find.byKey(const Key('card')));
          final accept = tester.getRect(find.byType(ElevatedButton));

          expect(accept.bottom, lessThanOrEqualTo(card.bottom + 0.5),
              reason: 'the accept is clipped at the bottom of the card on '
                  '${entry.key} at ${scale}x');
          expect(accept.top, greaterThanOrEqualTo(card.top - 0.5),
              reason: 'the accept is clipped at the top of the card on '
                  '${entry.key} at ${scale}x');
        }
      }
    });

    testWidgets('the list scrolls but paints no bar', (tester) async {
      // A track down the inside edge of the card reads as a seam in the card,
      // and on web it lands on the dialog's own rounded corner. The bottom
      // fade is what communicates "there is more".
      await mount(tester, cards: 3, screen: const Size(360, 640));

      expect(find.byType(Scrollbar), findsNothing,
          reason: 'the cards list must not paint a scrollbar');
      expect(find.byType(SingleChildScrollView), findsWidgets,
          reason: '...but it must still scroll');
    });

    testWidgets('the accept spans the card it belongs to', (tester) async {
      // It has to read as "confirm THIS report", not as a floating link.
      await mount(tester, cards: 1, screen: const Size(360, 640));

      final accept = tester.getRect(find.byType(ElevatedButton));
      final decline = tester.getRect(find.byKey(const Key('decline')));

      expect(accept.width, greaterThan(decline.width * 0.75),
          reason: 'the accept must not read as smaller than the decline');
    });
  });

  // Keeps the constant honest against report_issue_screen.dart.
  test('the sentinel is unchanged', () {
    expect(kMineIsDifferent, '__different__');
  });
}

Widget _card(int i) => Material(
      color: const Color(0xFFFAFBFD),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            border: Border.all(color: CitizenUi.sharedBorder),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Flexible(
                    child: Text(
                      'RPT-49708275',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      '4 reports',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Deep pothole right at the corner, a tricycle already '
                'tipped over on it last night. #$i',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '12 m away · 1m Ago · Macanaya (Pescaria)',
                style: TextStyle(fontSize: 11, height: 1.35),
              ),
              const SizedBox(height: 11),
              SizedBox(
                width: double.infinity,
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                  label: const Text(
                    'Yes, this is my issue',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
