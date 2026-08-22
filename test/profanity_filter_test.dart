import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/moderation/profanity_filter.dart';

void main() {
  group('every root in the lexicon is actually reachable', () {
    // The regression that motivated this file: roots were hand-"normalized",
    // and seven carried doubled letters the input normalizer collapses away,
    // so they could never be matched. Five had no sibling covering for them —
    // typing the slur in full passed clean.
    const previouslyDead = [
      'asshole',
      'pussy',
      'nigger',
      'faggot',
      'giddan',
      'ukinnam',
      'okinnam',
    ];

    for (final term in previouslyDead) {
      test('"$term" is flagged', () {
        expect(ProfanityFilter.contains(term), isTrue);
      });
    }

    test('a doubled-letter root added in future spelling still works', () {
      // 'motherfucker' has no doubles; 'asshole' does. Both must behave the
      // same way now that the lexicon is normalized by code rather than hand.
      expect(ProfanityFilter.contains('what an ASSHOLE'), isTrue);
      expect(ProfanityFilter.contains('what a motherfucker'), isTrue);
    });
  });

  group('still catches what it always caught', () {
    for (final t in ['fuck', 'shit', 'gago', 'putangina', 'tangina']) {
      test('"$t"', () => expect(ProfanityFilter.contains(t), isTrue));
    }

    test('leetspeak evasion', () {
      expect(ProfanityFilter.contains('g4g0'), isTrue);
    });

    test('padded-repeat evasion', () {
      expect(ProfanityFilter.contains('puuuutaaangina'), isTrue);
    });

    test('letter-spaced evasion', () {
      expect(ProfanityFilter.contains('p u t a n g i n a'), isTrue);
    });
  });

  group('does not flag innocent text', () {
    const clean = [
      'The road in Barangay Macanaya needs repair',
      'reputation',
      'assist',
      'assessment',
      'classic',
      'passion',
      'massage',
      'tanggapan',
      'Please pass the document',
      // Collapsing 'nigger' produces 'niger'; the country must survive it.
      'Nigeria',
      'a Nigerian delegation visited',
    ];

    for (final t in clean) {
      test('"$t"', () => expect(ProfanityFilter.contains(t), isFalse));
    }
  });

  group('masking', () {
    test('replaces the word and keeps the rest verbatim', () {
      expect(
        ProfanityFilter.maskForDisplay('you are a gago, sir!'),
        'you are a ****, sir!',
      );
    });

    test('masks a previously-dead root too', () {
      expect(ProfanityFilter.maskForDisplay('what an asshole'),
          'what an *******');
    });

    test('leaves clean text untouched', () {
      const s = 'The streetlight on Rizal St. is broken.';
      expect(ProfanityFilter.maskForDisplay(s), s);
    });
  });
}
