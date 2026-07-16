// AdminResultsCard is the shell every admin table sits in, and every one of
// those tables starts with an opaque header band. These pin the reason that
// band used to square off the card's top corners.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/admin/theme/admin_ui.dart';
import 'package:govpulse/features/admin/widgets/admin_submission_ui.dart';

/// A stand-in for a table header: an opaque band flush against the card's top
/// edge, which is what collides with the rounded corner.
const _header = ColoredBox(
  color: AdminUi.subtle,
  child: SizedBox(width: double.infinity, height: 40),
);

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(
        backgroundColor: AdminUi.pageBg,
        body: Center(child: SizedBox(width: 400, child: child)),
      ),
    );

void main() {
  testWidgets('the card clips its child to the rounded corners',
      (tester) async {
    await tester.pumpWidget(_host(const AdminResultsCard(child: _header)));
    await tester.pumpAndSettle();

    // The clip has to be live, otherwise the header's square corners sit proud
    // of the card's curve.
    final clip = tester.widget<ClipPath>(
      find.descendant(
        of: find.byType(AdminResultsCard),
        matching: find.byType(ClipPath),
      ),
    );
    expect(clip.clipBehavior, isNot(Clip.none));
  });

  // Regression: the border used to live in `decoration`, which a Container
  // paints BEHIND its child — so the header's opaque fill covered the card's
  // top border and corners. Painting it in the foreground puts it back on top.
  testWidgets('the border paints over the child, not under it', (tester) async {
    await tester.pumpWidget(_host(const AdminResultsCard(child: _header)));
    await tester.pumpAndSettle();

    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(AdminResultsCard),
            matching: find.byType(Container),
          )
          .first,
    );

    final foreground = container.foregroundDecoration as BoxDecoration?;
    expect(
      foreground?.border,
      isNotNull,
      reason: 'the border must be a foreground decoration to survive an '
          'opaque child painted against the top edge',
    );

    // ...and the background must keep the radius, since the clip is derived
    // from it.
    final background = container.decoration as BoxDecoration?;
    expect(background?.borderRadius, isNotNull);
    expect(
      background?.border,
      isNull,
      reason: 'a border here would paint behind the child again',
    );
  });
}
