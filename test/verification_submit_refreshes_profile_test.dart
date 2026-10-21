// Finishing the verification wizard inserts a `verification_submissions` row
// with status 'pending' and then leaves for Home. `userProfileProvider` is an
// AsyncNotifier that is NOT re-read on navigation, so unless something
// invalidates it the whole app keeps serving the profile it fetched before the
// submission - status 'none'.
//
// The web arm did invalidate it. The mobile arm did not: it went straight to
// `Navigator.pushAndRemoveUntil`, HomePage rebuilt from the stale profile, and
// the card offered "Verify Now" to a citizen whose row already said 'pending'.
// (Both platforms already render the pending state correctly - mobile as
// "Verification In Progress", web as "Under Review" - so the stale provider
// was the entire bug on both surfaces.)
//
// The screen needs a camera and a live Supabase session, so the success
// dialog's callback cannot be pumped here. What this pins is that NEITHER arm
// loses its refresh: the success handler must invalidate the provider before
// it navigates, on web and on mobile alike.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Strips `//` comments, so the markers below anchor on CODE. The handler is
/// heavily commented and several of those comments name `pushAndRemoveUntil`
/// and `goClearingPageless` before the statements themselves appear.
String _stripComments(String s) =>
    s.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

/// The body of `_showSuccessDialog`'s `onDone`, which holds both arms.
String _onDoneBody(String raw) {
  final src = _stripComments(raw);
  final start = src.indexOf('void _showSuccessDialog()');
  expect(
    start,
    isNot(-1),
    reason: '_showSuccessDialog was renamed; this test needs updating.',
  );
  // Up to the end of the dialog call is plenty - both arms live inside it.
  final end = src.indexOf('transitionBuilder:', start);
  expect(end, isNot(-1), reason: 'Could not find the end of the dialog call.');
  return src.substring(start, end);
}

void main() {
  late String body;

  setUpAll(() {
    final src = File(
      'lib/features/profileVerification/verification_face_scan_screen.dart',
    ).readAsStringSync();
    body = _onDoneBody(src);
  });

  test('both navigation arms invalidate the profile before leaving', () {
    final invalidations = RegExp(
      r'invalidate\(\s*userProfileProvider\s*\)',
    ).allMatches(body).length;

    expect(
      invalidations,
      greaterThanOrEqualTo(2),
      reason:
          'The verification success handler must refresh userProfileProvider on '
          'BOTH the web and the mobile path. Only $invalidations invalidation(s) '
          'found: the arm without one sends the citizen to a Home built from '
          'the profile cached before they submitted, so the card still says '
          '"Verify Now" instead of "Verification In Progress".',
    );
  });

  test('the mobile arm refreshes BEFORE it navigates', () {
    // Ordering matters: pushAndRemoveUntil tears this route down, so an
    // invalidate placed after it may never run.
    final push = body.indexOf('pushAndRemoveUntil');
    expect(
      push,
      isNot(-1),
      reason: 'The mobile arm no longer uses pushAndRemoveUntil.',
    );

    final before = RegExp(
      r'invalidate\(\s*userProfileProvider\s*\)',
    ).allMatches(body.substring(0, push)).length;

    expect(
      before,
      greaterThanOrEqualTo(2),
      reason:
          'The mobile invalidate must come before pushAndRemoveUntil, which '
          'disposes this route. Found only $before before the push.',
    );
  });

  test('the web arm still clears the wizard rather than pushing HomePage', () {
    // Guards the fix this file sits next to: web must not fall into the mobile
    // push, which mounts the legacy mobile surface in a browser and desyncs
    // go_router's match list.
    final web = body.indexOf('if (kIsWeb)');
    final push = body.indexOf('pushAndRemoveUntil');
    expect(web, isNot(-1), reason: 'The web arm is gone.');
    expect(
      body.indexOf('goClearingPageless', web),
      lessThan(push),
      reason:
          'The web arm must leave via goClearingPageless, before the '
          'mobile pushAndRemoveUntil.',
    );
  });
}
