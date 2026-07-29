import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:govpulse/core/services/chat_service.dart';
import 'package:govpulse/core/widgets/Home/Chat-agent/chat_models.dart';

/// Guards the collision-retry loop's failure selectivity.
///
/// `_withUniqueRef` exists because `reference_code` is UNIQUE and the generator
/// is random. It must retry a genuine collision (SQLSTATE 23505) and NOTHING
/// else — a 4-attempt loop in front of a rate limiter turns one blocked request
/// into four, and swallowing a real error would hide it behind a generic
/// "could not allocate a reference".
///
/// Every rate limiter in this schema (`rl_*`, `check_user_restriction`) raises
/// with the default P0001, and no function in the database raises 23505, so the
/// only thing that can reach the retry branch is an actual unique violation.
void main() {
  PostgrestException pg(String code) =>
      PostgrestException(message: 'boom $code', code: code);

  test('a collision is retried up to the attempt cap, then rethrown as-is', () async {
    var calls = 0;
    await expectLater(
      ChatService.withUniqueRefForTest((_) async {
        calls++;
        throw pg('23505');
      }),
      // The ORIGINAL exception surfaces, not a generic wrapper — the caller's
      // error handling should see the real cause on final failure.
      throwsA(isA<PostgrestException>().having((e) => e.code, 'code', '23505')),
    );
    expect(calls, ChatService.refAttemptsForTest,
        reason: 'should have used exactly the attempt cap');
  });

  test('succeeds on a later attempt with a DIFFERENT reference each time', () async {
    final seen = <String>[];
    final result = await ChatService.withUniqueRefForTest((ref) async {
      seen.add(ref);
      if (seen.length < 3) throw pg('23505');
      return 'ok';
    });
    expect(result, 'ok');
    expect(seen.length, 3);
    expect(seen.toSet().length, 3,
        reason: 'each retry must draw a fresh reference, not reuse the failed one');
  });

  group('propagates immediately without consuming attempts', () {
    test('rate-limit rejection (P0001)', () async {
      var calls = 0;
      await expectLater(
        ChatService.withUniqueRefForTest((_) async {
          calls++;
          throw PostgrestException(
              message: 'daily limit reached', code: 'P0001');
        }),
        throwsA(isA<PostgrestException>()
            .having((e) => e.code, 'code', 'P0001')
            .having((e) => e.message, 'message', contains('daily limit'))),
      );
      expect(calls, 1, reason: 'a rate limiter must never be hammered');
    });

    test('RLS denial (42501)', () async {
      var calls = 0;
      await expectLater(
        ChatService.withUniqueRefForTest((_) async {
          calls++;
          throw pg('42501');
        }),
        throwsA(isA<PostgrestException>().having((e) => e.code, 'code', '42501')),
      );
      expect(calls, 1);
    });

    test('CHECK-constraint violation (23514) — a bad reference format', () async {
      // If the Dart format ever drifts from the migration's allowlist, this is
      // what comes back. Retrying would just fail three more times, identically.
      var calls = 0;
      await expectLater(
        ChatService.withUniqueRefForTest((_) async {
          calls++;
          throw pg('23514');
        }),
        throwsA(isA<PostgrestException>().having((e) => e.code, 'code', '23514')),
      );
      expect(calls, 1);
    });

    test('TicketException (not a PostgrestException at all)', () async {
      var calls = 0;
      await expectLater(
        ChatService.withUniqueRefForTest((_) async {
          calls++;
          throw const TicketException('nope');
        }),
        throwsA(isA<TicketException>()),
      );
      expect(calls, 1);
    });

    test('a transport error (non-Postgrest)', () async {
      var calls = 0;
      await expectLater(
        ChatService.withUniqueRefForTest((_) async {
          calls++;
          throw StateError('socket closed');
        }),
        throwsA(isA<StateError>()),
      );
      expect(calls, 1);
    });
  });

  test('a successful first attempt calls create exactly once', () async {
    var calls = 0;
    final r = await ChatService.withUniqueRefForTest((ref) async {
      calls++;
      return ref;
    });
    expect(calls, 1);
    expect(RegExp(r'^LGU-[0-9]{8}-[0-9A-HJKMNP-TV-Z]{6}$').hasMatch(r), isTrue);
  });
}
