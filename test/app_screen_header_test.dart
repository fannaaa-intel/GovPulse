// Pins AppScreenHeader to the Settings sub-screen header it was transcribed
// from — the one in the Terms of Service screenshot: white bar, chevron chip,
// blue w700 title.
//
// Companion to app_back_chevron_test.dart. That file pins the chip; this one
// pins the bar around it, because the Profile Verification screen differed in
// BOTH — a platform AppBar arrow AND a 16px w500 title on a grey bar.
//
// These are the values used by About / Privacy Policy / Terms of Service /
// Contact Support / Edit Profile / My Submissions / the Change Password steps:
//
//   bar       white, padding LTRB(w*.04, w*.04, w*.04, w*.035)
//   shadow    black @ 5%, blur 8, offset (0, 2)
//   gap       w * 0.035 between chip and title
//   title     w * 0.052, w700, AppColors.primaryBlue, letterSpacing -0.3
//
// If a case fails, check whether SETTINGS moved. If it did, update both
// together; if it did not, this widget drifted and should be put back.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:govpulse/core/theme/app_colors.dart';
import 'package:govpulse/core/widgets/app_back_chevron.dart';
import 'package:govpulse/core/widgets/app_screen_header.dart';

const double _w = 390;

Future<void> _pump(WidgetTester tester, {String title = 'Terms of Service'}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Column(
          children: [AppScreenHeader(title: title, width: _w)],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('carries the Settings chevron, not a bespoke one', (tester) async {
    await _pump(tester);
    // The chip is not re-implemented here — same widget, so it cannot drift
    // away from Settings independently of app_back_chevron_test.
    expect(find.byType(AppBackChevron), findsOneWidget);
  });

  testWidgets('title matches the Settings title style', (tester) async {
    await _pump(tester);

    final style = tester.widget<Text>(find.text('Terms of Service')).style!;
    expect(style.fontSize, _w * 0.052);
    expect(style.fontWeight, FontWeight.w700);
    expect(style.color, AppColors.primaryBlue);
    expect(style.letterSpacing, -0.3);
  });

  testWidgets('white bar with the Settings shadow', (tester) async {
    await _pump(tester);

    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(AppScreenHeader),
            matching: find.byType(Container),
          )
          .first,
    );
    final d = container.decoration! as BoxDecoration;
    expect(d.color, Colors.white);
    expect(d.boxShadow!.single.blurRadius, 8);
    expect(d.boxShadow!.single.offset, const Offset(0, 2));
  });

  testWidgets('chip and title are separated by the Settings gap',
      (tester) async {
    await _pump(tester);

    final chip = tester.getRect(find.byType(AppBackChevron));
    final title = tester.getRect(find.text('Terms of Service'));
    expect(title.left - chip.right, closeTo(_w * 0.035, 0.01));
  });

  testWidgets('a long title ellipsises rather than overflowing',
      (tester) async {
    // "Profile Verification" is the widest title to use this header and was the
    // reason the title is Expanded. An unbounded Text in that Row overflows on
    // a small phone instead of truncating.
    await _pump(tester, title: 'Profile Verification and Identity Checks');

    expect(tester.takeException(), isNull);
    final text = tester.widget<Text>(
      find.text('Profile Verification and Identity Checks'),
    );
    expect(text.overflow, TextOverflow.ellipsis);
    expect(text.maxLines, 1);
  });
}
