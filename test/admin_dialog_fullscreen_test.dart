import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/admin/widgets/admin_dialog_back.dart';
import 'package:govpulse/features/admin/widgets/admin_responsive_dialog.dart';

/// The report-process dialogs are a modal on a desktop and a SCREEN on a phone.
///
/// On a 409px viewport the endorse modal left about 385px after its inset,
/// minus its own padding, to hold a search field and a 2-up grid of agency
/// cards — floating on a barrier showing roughly 12px either side. Nothing was
/// gained by the float and the grid paid for it twice, once in the inset and
/// once in the corner radius.
///
/// The chevron is the other half of the rule: a modal is dismissed by an ✕
/// because it floats over the page; a screen is dismissed by going back
/// because it is a place you navigated to. Getting that backwards is how a
/// fullscreen dialog starts feeling like a page you cannot leave.
void main() {
  Widget host(double width) => MediaQuery(
        data: MediaQueryData(size: Size(width, 800)),
        child: MaterialApp(
          home: Scaffold(
            body: AdminResponsiveDialog(
              title: 'Endorse to External Entity',
              subtitle: 'Send this report to the appropriate agency.',
              leading: const Icon(Icons.send_rounded),
              actions: [
                FilledButton(onPressed: () {}, child: const Text('Send')),
              ],
              child: const SizedBox(height: 200),
            ),
          ),
        ),
      );

  group('shape by viewport', () {
    testWidgets('a desktop viewport draws a rounded, inset modal',
        (tester) async {
      await tester.pumpWidget(host(900));

      final dialog = tester.widget<Dialog>(find.byType(Dialog));
      expect(dialog.insetPadding, isNot(EdgeInsets.zero),
          reason: 'a modal floats, so it keeps its inset');
      final shape = dialog.shape as RoundedRectangleBorder;
      expect(shape.borderRadius, isNot(BorderRadius.zero));
    });

    testWidgets('a tablet at 700 still gets the modal', (tester) async {
      // Above the threshold — the middle case that must not change.
      await tester.pumpWidget(host(700));
      expect(tester.widget<Dialog>(find.byType(Dialog)).insetPadding,
          isNot(EdgeInsets.zero));
    });

    testWidgets('just above the threshold is still a modal', (tester) async {
      await tester.pumpWidget(host(kAdminDialogFullscreenBelow + 1));
      expect(tester.widget<Dialog>(find.byType(Dialog)).insetPadding,
          isNot(EdgeInsets.zero));
    });

    testWidgets('just below the threshold fills the screen', (tester) async {
      await tester.pumpWidget(host(kAdminDialogFullscreenBelow - 1));

      final dialog = tester.widget<Dialog>(find.byType(Dialog));
      expect(dialog.insetPadding, EdgeInsets.zero,
          reason: 'a screen has no inset to float on');
      final shape = dialog.shape as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.zero,
          reason: 'and no corner, because it meets the screen edges');
    });

    testWidgets('a phone viewport fills the screen', (tester) async {
      await tester.pumpWidget(host(409));
      expect(tester.widget<Dialog>(find.byType(Dialog)).insetPadding,
          EdgeInsets.zero);
    });
  });

  group('the way out', () {
    testWidgets('a modal closes with an X, not a back chevron',
        (tester) async {
      await tester.pumpWidget(host(900));

      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      expect(find.byType(AdminDialogBack), findsNothing);
    });

    testWidgets('a screen goes back with a chevron, not an X',
        (tester) async {
      await tester.pumpWidget(host(409));

      expect(find.byType(AdminDialogBack), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsNothing,
          reason: 'two ways out in one header is one too many');
    });

    testWidgets('the leading glyph yields to the chevron on a screen',
        (tester) async {
      // Both in the same slot would read as a toolbar rather than a header.
      await tester.pumpWidget(host(409));
      expect(find.byIcon(Icons.send_rounded), findsNothing);

      await tester.pumpWidget(host(900));
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
    });
  });

  testWidgets('the action bar survives the narrowest phone', (tester) async {
    await tester.pumpWidget(host(320));

    expect(find.text('Send'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
