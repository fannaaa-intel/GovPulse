import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/widgets/web/web_glass_card.dart';

/// Auth screens are a card on a page at desktop widths, and the page itself on
/// a phone.
///
/// Every auth screen is ONE form on an otherwise empty backdrop, so on a phone
/// browser the frosted card was a frame drawn around content that already
/// filled the screen — a rim, a gutter and 40px of card padding all spent
/// before the first field, on a 390px viewport.
///
/// The decision lives in [WebGlassCard] rather than at each call site because
/// eight screens mount it — login, signup, the Facebook username step, guest,
/// and four reset/verification steps through WebAuthCard — and a per-screen
/// flag would be seven chances to miss one.
void main() {
  Widget host(double width, {bool alwaysCard = false}) => MediaQuery(
        data: MediaQueryData(size: Size(width, 800)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: WebGlassCard(
            alwaysCard: alwaysCard,
            child: const SizedBox(height: 200),
          ),
        ),
      );

  /// The card's own Container — the one carrying the surface decoration.
  BoxDecoration decorationOf(WidgetTester tester) {
    final c = tester.widgetList<Container>(find.byType(Container)).firstWhere(
          (c) => c.decoration is BoxDecoration,
        );
    return c.decoration as BoxDecoration;
  }

  group('WebGlassCard shape by viewport', () {
    testWidgets('a desktop viewport keeps the rim, radius and shadow',
        (tester) async {
      await tester.pumpWidget(host(900));
      final d = decorationOf(tester);

      expect(d.borderRadius, isNotNull);
      expect(d.border, isNotNull);
      expect(d.boxShadow, isNotNull);
      expect(d.boxShadow, isNotEmpty);
    });

    testWidgets('a tablet viewport still keeps the card', (tester) async {
      // 700 is above the threshold — the two-panel hero layout starts at 1000,
      // so this is the middle case that must NOT change.
      await tester.pumpWidget(host(700));
      final d = decorationOf(tester);

      expect(d.borderRadius, isNotNull);
      expect(d.border, isNotNull);
    });

    testWidgets('just above the threshold is still a card', (tester) async {
      await tester.pumpWidget(host(kAuthFullBleedBelow + 1));
      expect(decorationOf(tester).borderRadius, isNotNull);
    });

    testWidgets('just below the threshold drops the card chrome',
        (tester) async {
      await tester.pumpWidget(host(kAuthFullBleedBelow - 1));
      final d = decorationOf(tester);

      expect(d.borderRadius, isNull, reason: 'a full-bleed page has no corner');
      expect(d.border, isNull, reason: 'and no rim to draw against the edge');
      expect(d.boxShadow, isNull, reason: 'nothing to lift it off');
      // The gradient stays: the backdrop behind it keeps its glows either way,
      // and a transparent form over them is unreadable.
      expect(d.gradient, isNotNull);
    });

    testWidgets('a phone viewport is full bleed', (tester) async {
      await tester.pumpWidget(host(390));
      expect(decorationOf(tester).borderRadius, isNull);
    });

    testWidgets('the narrowest phone is full bleed and does not overflow',
        (tester) async {
      await tester.pumpWidget(host(320));

      expect(decorationOf(tester).borderRadius, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('alwaysCard overrides the width decision', (tester) async {
      // The escape hatch, for a surface that is genuinely a card ON something.
      await tester.pumpWidget(host(320, alwaysCard: true));
      expect(decorationOf(tester).borderRadius, isNotNull);
    });
  });

  group('bleedOrCentre', () {
    testWidgets('centres when not bleeding', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: bleedOrCentre(false, const SizedBox(height: 100)),
        ),
      ));
      expect(find.byType(Center), findsAtLeastNWidgets(1));
    });

    testWidgets('fills, rather than centring, when bleeding', (tester) async {
      // Center pins the scroll child to its own height, so the surface would
      // stop where the form stops and the backdrop would show through above
      // and below — which reads as a very wide card, not a page.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: bleedOrCentre(true, const SizedBox(height: 100)),
        ),
      ));

      final box = tester.getSize(find.byType(SizedBox).first);
      expect(box.height, greaterThan(100),
          reason: 'the bleeding branch stretches to the viewport');
    });
  });
}
