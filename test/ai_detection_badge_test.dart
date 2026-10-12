import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/widgets/ai_detection_badge.dart';

/// The AI badge used to be a bare 🚩 that stayed hidden below 30%, so a
/// reviewer never saw the score itself (2026-10-12). These pin the percentage
/// display and the band edges the thumbnail and the viewer meter share.
void main() {
  group('bands', () {
    test('edges sit exactly at 30% and 70%', () {
      expect(aiBandFor(0.0), AiBand.real);
      expect(aiBandFor(0.299), AiBand.real);
      expect(aiBandFor(0.30), AiBand.possible);
      expect(aiBandFor(0.70), AiBand.possible);
      expect(aiBandFor(0.701), AiBand.likely);
      expect(aiBandFor(1.0), AiBand.likely);
    });
  });

  group('when anything is shown', () {
    test('a LOW score is shown now, not hidden', () {
      expect(AiDetectionBadge.shouldShow(0.06, 'completed'), isTrue);
    });
    test('legacy rows with no status still show their score', () {
      expect(AiDetectionBadge.shouldShow(0.5, null), isTrue);
    });
    test('pending, failed and unscored show nothing', () {
      expect(AiDetectionBadge.shouldShow(0.9, 'pending'), isFalse);
      expect(AiDetectionBadge.shouldShow(0.9, 'failed'), isFalse);
      expect(AiDetectionBadge.shouldShow(null, 'completed'), isFalse);
    });
    test('an out-of-range score is not drawn as a bogus percentage', () {
      expect(AiDetectionBadge.shouldShow(1.4, 'completed'), isFalse);
      expect(AiDetectionBadge.shouldShow(-0.1, 'completed'), isFalse);
    });
  });

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
        MaterialApp(home: Scaffold(body: Center(child: child))),
      );

  testWidgets('the thumbnail pill prints the percentage', (tester) async {
    await pump(tester,
        const AiDetectionBadge(score: 0.86, status: 'completed', compact: true));
    expect(find.text('AI 86%'), findsOneWidget);
  });

  testWidgets('the full badge names the band', (tester) async {
    await pump(tester, const AiDetectionBadge(score: 0.06, status: 'completed'));
    expect(find.text('Likely real · 6%'), findsOneWidget);
  });

  testWidgets('the viewer meter shows the number and the verdict',
      (tester) async {
    await pump(tester, const AiLikelihoodMeter(score: 0.48, status: 'completed'));
    expect(find.text('48%'), findsOneWidget);
    expect(find.text('Possibly AI'), findsWidgets);
  });
}
