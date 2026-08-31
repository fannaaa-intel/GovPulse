import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/theme/app_colors.dart';
import 'package:govpulse/features/admin/widgets/report_detail_kit.dart';

/// [DetailActionButton] is the ONE control behind every irreversible action in
/// the report consoles — accept, reject, endorse, reopen, download, return to
/// triage. Each one is a network round trip, and until this test existed the
/// button could only grey out: it never said *which* action was running, and it
/// leaned entirely on the call site remembering to fold the pane's busy flag
/// into `onTap`.
///
/// These tests pin both halves — the visible spinner, and the refusal to fire
/// twice — because the second one is the part that turns a double-click into
/// two writes.
void main() {
  Widget host(Widget child) => MaterialApp(
        home: Scaffold(body: Center(child: SizedBox(width: 320, child: child))),
      );

  group('DetailActionButton busy state', () {
    testWidgets('idle shows its icon and no spinner', (tester) async {
      await tester.pumpWidget(host(
        DetailActionButton(
          label: 'Accept Report',
          icon: Icons.check_circle_rounded,
          color: AppColors.green,
          onTap: () {},
        ),
      ));

      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('busy swaps the icon for a spinner, keeping the label',
        (tester) async {
      await tester.pumpWidget(host(
        DetailActionButton(
          label: 'Accept Report',
          icon: Icons.check_circle_rounded,
          color: AppColors.green,
          busy: true,
          onTap: () {},
        ),
      ));

      // The spinner replaces the icon rather than joining it, so the button
      // does not change width mid-action.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
      // The label must survive — a bare spinner loses which action is running.
      expect(find.text('Accept Report'), findsOneWidget);
    });

    testWidgets('busy refuses the press even when onTap is still wired',
        (tester) async {
      // The call site deliberately does NOT null out onTap here. The guard has
      // to live in the button, or every one of the nine call sites becomes a
      // place the double-write bug can come back.
      var taps = 0;
      await tester.pumpWidget(host(
        DetailActionButton(
          label: 'Endorse to external entity',
          icon: Icons.forward_to_inbox_rounded,
          color: AppColors.primaryBlue,
          busy: true,
          onTap: () => taps++,
        ),
      ));

      await tester.tap(find.byType(DetailActionButton));
      await tester.pump();

      expect(taps, 0, reason: 'a busy button must not fire its action');
    });

    testWidgets('outlined busy button keeps its colour, not disabled grey',
        (tester) async {
      // A busy control that greys out reads as "unavailable" rather than
      // "working" — the spinner is the signal, so the chrome stays lit.
      await tester.pumpWidget(host(
        DetailActionButton(
          label: 'Change endorsement',
          icon: Icons.swap_horiz_rounded,
          color: AppColors.primaryBlue,
          outlined: true,
          busy: true,
          onTap: () {},
        ),
      ));

      final spinner = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(spinner.color, AppColors.primaryBlue,
          reason: 'an outlined button spins in its own colour, not white');
    });

    testWidgets('filled busy button spins in white', (tester) async {
      await tester.pumpWidget(host(
        DetailActionButton(
          label: 'Download Report',
          icon: Icons.download_rounded,
          color: AppColors.primaryBlue,
          busy: true,
          onTap: () {},
        ),
      ));

      final spinner = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(spinner.color, Colors.white);
    });

    testWidgets('an idle button still fires normally', (tester) async {
      var taps = 0;
      await tester.pumpWidget(host(
        DetailActionButton(
          label: 'Reopen Report',
          icon: Icons.restart_alt_rounded,
          color: AppColors.primaryBlue,
          onTap: () => taps++,
        ),
      ));

      await tester.tap(find.byType(DetailActionButton));
      await tester.pump();

      expect(taps, 1);
    });
  });
}
