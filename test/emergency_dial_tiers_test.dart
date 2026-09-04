import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/home/emergency/emergency_screen.dart';

/// The emergency screen dials on two tiers, and the difference is deliberate.
///
/// Every hotline in the list connects on one tap (ACTION_CALL) — that
/// immediacy is the feature. 911 and 112 are the exception: they open the
/// dialer pre-filled (ACTION_DIAL) so an accidental tap cannot place a live
/// call to emergency services.
///
/// Both tiers end in a platform intent a widget test cannot observe, so
/// nothing else in the suite would notice if the two were swapped, or if
/// CALL_PHONE were dropped from the manifest and every number quietly fell
/// back to the pre-fill path. This asserts the branch itself.
void main() {
  group('emergency numbers only pre-fill the dialer', () {
    test('911 does not place the call itself', () {
      expect(usesPreFilledDialer('911'), isTrue);
    });

    test('112 does not place the call itself', () {
      expect(usesPreFilledDialer('112'), isTrue);
    });
  });

  group('every listed hotline calls immediately', () {
    // Shapes drawn from the hotline list: landline, mobile, and the
    // hyphenated/spaced forms the directory actually stores.
    const listed = <String>[
      '09171234567',
      '(078) 888-0000',
      '078-888-0000',
      '1343',
      '117',
      '911911',
      '0912 345 6789',
    ];

    for (final number in listed) {
      test('$number goes straight through', () {
        expect(usesPreFilledDialer(number), isFalse);
      });
    }
  });

  test('the rule matches the whole number, not a prefix', () {
    // '911911' and '1123' contain an emergency number but are not one. A
    // startsWith/contains rewrite of this predicate would send a real hotline
    // down the pre-fill path and quietly break the feature.
    expect(usesPreFilledDialer('911911'), isFalse);
    expect(usesPreFilledDialer('1123'), isFalse);
    expect(usesPreFilledDialer('0911'), isFalse);
  });
}
