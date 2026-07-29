import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/services/chat_service.dart';

/// Guards the ticket-reference format contract between Dart and Postgres.
///
/// `concern_tickets.reference_code` is constrained in the database by migration
/// 20260722000017 — a CHECK constraint and a BEFORE INSERT/UPDATE trigger both
/// pinning `^LGU-[0-9]{8}-[0-9A-HJKMNP-TV-Z]{6}$`. The Dart generator and that
/// regex are two independent copies of the same 32-character alphabet, and
/// nothing in the SQL verify suite can see the Dart side.
///
/// So: generate from the REAL generator (never a reimplementation — a
/// reimplementation would test itself) and assert the properties the database
/// will enforce. The generated corpus is also written to disk so the SQL side
/// can run every value against the live regex.
void main() {
  // Exactly the migration's character class, transcribed independently.
  final sqlRegex = RegExp(r'^LGU-[0-9]{8}-[0-9A-HJKMNP-TV-Z]{6}$');
  const excluded = ['I', 'L', 'O', 'U'];
  const sampleSize = 10000;

  group('reference alphabet', () {
    test('is exactly 32 unique characters', () {
      final a = ChatService.referenceAlphabetForTest;
      expect(a.length, 32, reason: 'base32 requires exactly 32 symbols');
      expect(a.split('').toSet().length, 32, reason: 'no duplicate symbols');
    });

    test('excludes the four ambiguous glyphs', () {
      final a = ChatService.referenceAlphabetForTest;
      for (final c in excluded) {
        expect(a.contains(c), isFalse, reason: '$c must not be in the alphabet');
      }
    });

    test('every alphabet character is accepted by the SQL character class', () {
      // Catches the inverse drift: a symbol Dart can emit that SQL rejects.
      final a = ChatService.referenceAlphabetForTest;
      for (final c in a.split('')) {
        expect(RegExp(r'^[0-9A-HJKMNP-TV-Z]$').hasMatch(c), isTrue,
            reason: 'Dart may emit "$c" but the SQL class rejects it');
      }
    });
  });

  group('generated references', () {
    late List<String> refs;

    setUpAll(() {
      refs = List.generate(
        sampleSize,
        (_) => ChatService.generateReferenceForTest(),
      );
    });

    test('all $sampleSize match the database regex', () {
      final bad = refs.where((r) => !sqlRegex.hasMatch(r)).toList();
      expect(bad, isEmpty,
          reason: 'these would be rejected by the CHECK constraint: '
              '${bad.take(5).toList()}');
    });

    test('all are exactly 19 characters', () {
      expect(refs.every((r) => r.length == 19), isTrue);
    });

    test('no tail contains an excluded glyph', () {
      for (final r in refs) {
        final tail = r.substring(13);
        for (final c in excluded) {
          expect(tail.contains(c), isFalse, reason: '$r contains $c');
        }
      }
    });

    test('indexing covers the whole alphabet — no off-by-one at either end', () {
      // A generator using nextInt(len - 1), or offsetting by one, would never
      // emit the first or last symbol. With 60,000 tail characters drawn over
      // 32 symbols, every symbol is overwhelmingly likely to appear; a missing
      // one means the index range is wrong, not that we were unlucky.
      final seen = <String>{};
      for (final r in refs) {
        seen.addAll(r.substring(13).split(''));
      }
      final alphabet = ChatService.referenceAlphabetForTest.split('').toSet();
      final missing = alphabet.difference(seen);
      expect(missing, isEmpty,
          reason: 'never emitted (index range bug): $missing');
      expect(seen.difference(alphabet), isEmpty,
          reason: 'emitted outside the alphabet');
    });

    test('references are not colliding at a rate that suggests weak entropy',
        () {
      // Not a uniqueness guarantee — a collision is legitimate at 32^6. This
      // catches a generator that is effectively constant or clock-derived,
      // which is what the old millisecond tail was.
      final unique = refs.toSet().length;
      expect(unique, greaterThan((sampleSize * 0.999).floor()),
          reason: 'only $unique/$sampleSize distinct — entropy is too low');
    });

    test('writes the corpus for the SQL cross-check', () {
      final out = Platform.environment['REF_CORPUS_OUT'];
      if (out == null) return; // only when the SQL gate asks for it
      File(out).writeAsStringSync(refs.join('\n'));
      expect(File(out).existsSync(), isTrue);
    });
  });
}
