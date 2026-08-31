import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/theme/app_colors.dart';
import 'package:govpulse/core/widgets/logout_control.dart';

/// Logout was drawn seven different ways across admin, staff and citizen, with
/// THREE spellings live at once — "Log out", "Logout", "Sign Out" — which is
/// three different actions as far as a reader is concerned. Some had a divider
/// separating them from the ordinary settings above, some sat flush against
/// "Change password" as though they were the same kind of thing.
///
/// These pin the shared control's contract: one label, a tinted ground that
/// gives the row an edge, and an icon-only form that survives a collapsing
/// rail without overflowing.
void main() {
  Widget host(Widget child, {double width = 400}) => MaterialApp(
        home: Scaffold(
          body: Center(child: SizedBox(width: width, child: child)),
        ),
      );

  group('LogoutTile', () {
    testWidgets('uses the one agreed label', (tester) async {
      await tester.pumpWidget(host(LogoutTile(onLogout: () {})));

      expect(find.text('Log out'), findsOneWidget);
      // The two spellings this replaced.
      expect(find.text('Logout'), findsNothing);
      expect(find.text('Sign Out'), findsNothing);
    });

    testWidgets('carries a tinted ground, not just red text', (tester) async {
      // Red text alone was already in use and was not enough — the row still
      // read as one more entry in a list. The tint is what gives it an edge.
      await tester.pumpWidget(host(LogoutTile(onLogout: () {})));

      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(LogoutTile),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.color, kLogoutTint);
    });

    testWidgets('carries no trailing chevron', (tester) async {
      // A chevron promises a NEXT screen — it is what "Change password" and
      // "Edit profile" carry, because those open something. Logout opens
      // nothing: it acts, and the session ends. Borrowing the affordance made
      // the one row that behaves differently look like all the others.
      await tester.pumpWidget(host(LogoutTile(onLogout: () {})));

      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
      expect(find.byIcon(Icons.arrow_forward_ios_rounded), findsNothing);
      // The logout glyph itself stays.
      expect(find.byIcon(Icons.logout_rounded), findsOneWidget);
    });

    testWidgets('fires its callback', (tester) async {
      var taps = 0;
      await tester.pumpWidget(host(LogoutTile(onLogout: () => taps++)));

      await tester.tap(find.byType(LogoutTile));
      await tester.pump();

      expect(taps, 1);
    });

    testWidgets('compact drops the label and keeps the icon', (tester) async {
      // The collapsed rail case. Both consoles animate their rail 72 <-> 244
      // and derive `collapsed` from the LIVE width, so this form has to hold
      // at the narrow end of that animation.
      await tester.pumpWidget(
        host(LogoutTile(onLogout: () {}, compact: true), width: 64),
      );

      expect(find.text('Log out'), findsNothing);
      expect(find.byIcon(Icons.logout_rounded), findsOneWidget);
      expect(tester.takeException(), isNull,
          reason: 'a collapsed rail must not overflow');
    });

    testWidgets('survives a 56px rail without overflowing', (tester) async {
      // Narrower than either console's collapsed rail, so the assertion has
      // margin rather than sitting exactly on the real value.
      await tester.pumpWidget(
        host(LogoutTile(onLogout: () {}, compact: true), width: 56),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the expanded form holds at a narrow phone width',
        (tester) async {
      await tester.pumpWidget(host(LogoutTile(onLogout: () {}), width: 280));

      expect(find.text('Log out'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('is announced as a button to a screen reader', (tester) async {
      // Asserted on the merged SemanticsNode rather than with
      // bySemanticsLabel: the tile merges its icon, label and chevron into one
      // node, and the finder matches a Semantics WIDGET's own label, which a
      // merged subtree does not expose as its own element.
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(LogoutTile(onLogout: () {})));

      expect(
        tester.getSemantics(find.byType(LogoutTile)),
        matchesSemantics(
          label: 'Log out',
          isButton: true,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
        ),
      );
      handle.dispose();
    });
  });

  group('LogoutMenuRow', () {
    testWidgets('uses the same label and the danger colour', (tester) async {
      await tester.pumpWidget(host(const LogoutMenuRow()));

      expect(find.text('Log out'), findsOneWidget);
      final text = tester.widget<Text>(find.text('Log out'));
      expect(text.style?.color, AppColors.red);
    });

    testWidgets('renders its icon in a tinted disc', (tester) async {
      // The citizen dropdown already did this; admin and staff drew a bare
      // glyph, so the same action looked like two different controls.
      await tester.pumpWidget(host(const LogoutMenuRow()));

      expect(find.byIcon(Icons.logout_rounded), findsOneWidget);
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(LogoutMenuRow),
              matching: find.byType(Container),
            )
            .first,
      );
      final d = container.decoration as BoxDecoration;
      expect(d.color, kLogoutTint);
      expect(d.shape, BoxShape.circle);
    });

    testWidgets('fits a narrow popup menu', (tester) async {
      await tester.pumpWidget(host(const LogoutMenuRow(), width: 180));
      expect(tester.takeException(), isNull);
    });
  });
}
