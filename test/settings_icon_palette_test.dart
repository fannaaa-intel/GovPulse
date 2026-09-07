// Settings tiles use ONE accent, and red means danger.
//
// Three tiles — Contact Support, Location, App Version — were tinted
// AppColors.green, and the Set/Update Password tile carried Facebook's brand
// blue (0xFF1877F2). None of the four was saying anything the others were
// not: they are ordinary navigation rows sitting between blue ones.
//
// The tell was in `_buildTile` itself. It tints the glyph and its 12%-alpha
// wash with `iconBgColor`, but the box's BORDER is hardcoded to
// `AppColors.primaryBlue` — so a green tile rendered a green icon inside a
// blue-bordered box. The green was never a deliberate second accent; it was
// drift.
//
// Red is different and stays: Log Out and Delete Account are the only rows
// here that destroy something, and they take their colour from the separate
// `danger` / kLogoutTint path, not from `iconBgColor`.
//
// This reads the source because the tiles are built by a private method on a
// State, behind auth and profile loading that a widget test cannot reach
// without standing up Supabase. The value being pinned is a literal in the
// file, so the file is the honest thing to assert against.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File(
    'lib/features/home/settings/settings_screen.dart',
  ).readAsStringSync();

  test('no settings tile is tinted green', () {
    expect(
      source.contains('iconBgColor: AppColors.green'),
      isFalse,
      reason:
          'A tile is green again. _buildTile draws a blue border regardless, '
          'so a green glyph lands inside a blue box.',
    );
  });

  test('no settings tile carries a third-party brand colour', () {
    expect(
      source.contains('iconBgColor: const Color(0xFF1877F2)'),
      isFalse,
      reason: 'Facebook blue is back on the password tile.',
    );
  });

  test('every tile accent is the app blue', () {
    final accents = RegExp(
      r'iconBgColor: ([^,\n]+),',
    ).allMatches(source).map((m) => m.group(1)!.trim()).toList();

    // The parameter declaration itself is not a call site.
    accents.removeWhere((a) => a == 'iconBgColor');

    expect(accents, isNotEmpty, reason: 'the tiles moved; retarget this test');
    expect(
      accents.toSet(),
      {'AppColors.primaryBlue'},
      reason: 'Settings tiles must share one accent.',
    );
  });

  test('the danger rows still read as danger', () {
    // Log Out and Delete Account do not go through iconBgColor, so the sweep
    // above must not have flattened them.
    expect(source.contains('AppColors.red'), isTrue);
    expect(source.contains('kLogoutTint'), isTrue);
  });
}
