import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/services/local_assistant.dart';

// chat-agent returns a NON-2xx on a Groq 429 on purpose, so functions.invoke
// throws and ChatService falls back to this on-device assistant. That design is
// right — the citizen still gets a real answer instead of a dead end.
//
// What was wrong is the WORDING. Both causes produced the same "offline mode"
// apology, so a throttled AI told the citizen their connection was down. They
// then go debug wifi that was never broken, over a wait that is usually
// seconds — and the server had already said how many.
//
// These pin the two apologies apart, and pin the thing that matters most: the
// fallback stays equally USEFUL either way. Only the apology differs.
void main() {
  // A message the knowledge base deliberately has no entry for, so reply()
  // reaches the no-match fallback. If the KB ever grows an entry that matches
  // this, these tests would silently stop testing the fallback — hence a
  // nonsense string rather than a plausible civic question.
  const noMatch = 'zzz qqq xyzzy plugh';

  group('LocalAssistant — busy (throttled) vs offline (no connection)', () {
    test('offline keeps the connection wording', () {
      final reply = LocalAssistant.reply(noMatch).toLowerCase();

      expect(reply, contains('offline'));
      // Still routes somewhere useful rather than dead-ending.
      expect(reply, contains('barangay clearance'));
    });

    test('busy does NOT tell the citizen they are offline', () {
      final reply = LocalAssistant.reply(noMatch, busy: true).toLowerCase();

      // The whole point: their internet is fine, so never say otherwise.
      expect(
        reply,
        isNot(contains('offline')),
        reason: 'the AI was reachable but throttled — the citizen is not offline',
      );
      expect(reply, isNot(contains('koneksyon')));
      expect(reply, isNot(contains('connection')));
    });

    test('busy does not blame citizen traffic for our own quota', () {
      final reply = LocalAssistant.reply(noMatch, busy: true).toLowerCase();

      // chat-agent's own history records this mistake: the quota is our API
      // key's, not a crowd of citizens. Saying "marami pong gumagamit" invents
      // a cause and makes the LGU look overwhelmed when it is not.
      expect(reply, isNot(contains('marami pong gumagamit')));
    });

    test('busy stays exactly as useful as offline', () {
      final busy = LocalAssistant.reply(noMatch, busy: true).toLowerCase();

      // Same service list — the fallback must not get thinner just because the
      // reason changed.
      for (final service in [
        'barangay clearance',
        'cedula',
        'business permit',
        'psa documents',
        'national id',
      ]) {
        expect(busy, contains(service), reason: 'missing "$service"');
      }
      expect(busy, contains('talk to a person'));
    });

    test('the server retry hint is shown when it sent one', () {
      final reply = LocalAssistant.reply(noMatch, busy: true, retryAfterSeconds: 7);

      expect(reply, contains('7'));
    });

    test('no retry hint invented when the server did not send one', () {
      final reply = LocalAssistant.reply(noMatch, busy: true);

      // The suffix is the only place a duration appears, so its absence is the
      // assertion. Never guess a wait the upstream did not state.
      expect(reply, isNot(contains('segundo')));
      expect(reply, isNot(contains('seconds')));
    });

    test('a nonsense or negative retry hint is ignored, not printed', () {
      for (final bad in [0, -1]) {
        final reply = LocalAssistant.reply(
          noMatch,
          busy: true,
          retryAfterSeconds: bad,
        );
        expect(reply, isNot(contains('$bad')));
      }
    });

    test('an absurd retry hint is capped rather than shown verbatim', () {
      // A provider that says "wait an hour" must not turn into a message
      // telling a citizen to wait 3600 seconds.
      final reply = LocalAssistant.reply(
        noMatch,
        busy: true,
        retryAfterSeconds: 3600,
      );

      expect(reply, isNot(contains('3600')));
      expect(reply, contains('60'));
    });

    test('a real answer is returned unchanged regardless of the reason', () {
      // busy/offline only affect the no-match apology. A question the assistant
      // can actually answer must be answered identically either way, with no
      // apology bolted on.
      const answerable = 'paano kumuha ng barangay clearance';
      final offline = LocalAssistant.reply(answerable);
      final busy = LocalAssistant.reply(answerable, busy: true);

      expect(busy, equals(offline));
      expect(busy.toLowerCase(), isNot(contains('offline')));
    });

    test('action-tag intents are unaffected by the busy flag', () {
      // END/AGENT/REPORT routing happens before the fallback, so the tag must
      // survive — a throttled AI must not break "talk to a person".
      expect(LocalAssistant.reply('salamat po', busy: true), contains('[ACTION:END]'));
      expect(
        LocalAssistant.reply('gusto ko po makausap ang staff', busy: true),
        contains('[ACTION:AGENT]'),
      );
    });
  });
}
