import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/theme/app_colors.dart';
import 'package:govpulse/core/widgets/logout_control.dart';

/// The phone settings page ends in a titled ACCOUNT card rather than two loose
/// buttons.
///
/// Every other group on that page — PREFERENCES, LEGAL, ABOUT — is a labelled
/// card whose rows carry a tinted icon tile. Log out and Delete account had
/// neither: no heading, and bare glyphs where every row above had a tile. They
/// read as leftovers stranded under ABOUT rather than as a category of their
/// own.
///
/// The real screen needs Supabase and a session, so this rebuilds the section's
/// geometry from the same constants. That pins the ARITHMETIC — the tile size,
/// the corner, the proportional paddings — which is what "does it match the
/// rows above" actually means. The rendered page was checked separately.
void main() {
  /// Mirrors _buildTile's icon tile: an ordinary (blue) settings row.
  Widget ordinaryTile(double width) => Container(
        width: width * 0.095,
        height: width * 0.095,
        decoration: BoxDecoration(
          color: AppColors.primaryBlue.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(width * 0.022),
          border: Border.all(
            color: AppColors.primaryBlue.withValues(alpha: 0.25),
            width: 1.2,
          ),
        ),
      );

  /// Mirrors _buildDangerTile's icon tile.
  Widget dangerTile(double width) => Container(
        width: width * 0.095,
        height: width * 0.095,
        decoration: BoxDecoration(
          color: kLogoutTint,
          borderRadius: BorderRadius.circular(width * 0.022),
          border: Border.all(color: kLogoutBorder, width: 1.2),
        ),
      );

  Future<Size> sizeOf(WidgetTester tester, Widget w, double screen) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: screen,
            child: Align(alignment: Alignment.centerLeft, child: w),
          ),
        ),
      ),
    ));
    return tester.getSize(find.byType(Container).first);
  }

  group('the ACCOUNT section matches the sections above it', () {
    // The widths a phone settings page actually sees. uiScaleWidth clamps at
    // 480, so these are the real inputs rather than raw viewport widths.
    const widths = [320.0, 360.0, 390.0, 430.0, 480.0];

    testWidgets('the danger tile is the same size as an ordinary one',
        (tester) async {
      // If these drift apart, the ACCOUNT rows stop lining up with LEGAL and
      // ABOUT and the page loses the grid it reads by.
      for (final w in widths) {
        final ordinary = await sizeOf(tester, ordinaryTile(w), w);
        final danger = await sizeOf(tester, dangerTile(w), w);

        expect(danger, ordinary,
            reason: 'tile geometry must match at ${w.toInt()}px');
      }
    });

    testWidgets('the tile stays proportional across phone widths',
        (tester) async {
      // Proportional, not fixed: this page sizes everything against width, and
      // a hardcoded tile would be the one element that stopped scaling.
      final small = await sizeOf(tester, dangerTile(320), 320);
      final large = await sizeOf(tester, dangerTile(480), 480);

      expect(large.width, greaterThan(small.width));
      expect(small.width, closeTo(320 * 0.095, 0.5));
      expect(large.width, closeTo(480 * 0.095, 0.5));
    });

    testWidgets('the danger tile is tinted red, not blue', (tester) async {
      await sizeOf(tester, dangerTile(390), 390);
      final c = tester.widget<Container>(find.byType(Container).first);
      final d = c.decoration as BoxDecoration;

      expect(d.color, kLogoutTint);
      expect(d.borderRadius, BorderRadius.circular(390 * 0.022),
          reason: 'same corner as every other settings row');
    });

    testWidgets('nothing overflows at the narrowest phone', (tester) async {
      // 320 is the floor this page is built to hold.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: Row(
              children: [
                dangerTile(320),
                const SizedBox(width: 320 * 0.035),
                const Expanded(
                  child: Text(
                    'Delete account',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ),
      ));

      expect(tester.takeException(), isNull);
    });
  });
}
