import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/services/local_assistant.dart';

// The offline assistant cannot read public.lgu_facts, so a question about who
// the mayor is has no answer available to it. What it must NOT do is invent a
// name, and what it should not do is fall through to the generic "ano po ang
// maitutulong ko" reply, which reads as if the question was not understood.
//
// The online path is the mirror of this: chat-agent gets the same facts from
// the lgu_facts table and answers properly. These tests pin the offline half.
void main() {
  group('LocalAssistant — questions about Aparri officials', () {
    const officialsQuestions = [
      'sino ang mayor ng aparri',
      'Sino ang mayor?',
      'sinong mayor natin',
      'who is the mayor of aparri',
      'sino ang vice mayor',
      'sino ang alkalde ng aparri',
      'sino ang mga konsehal',
      'sangguniang bayan members',
    ];

    for (final q in officialsQuestions) {
      test('"$q" asks the citizen to reconnect instead of guessing', () {
        final reply = LocalAssistant.reply(q);

        // It must acknowledge it needs a connection for this class of question.
        expect(
          reply.toLowerCase(),
          anyOf(contains('internet'), contains('koneksyon')),
          reason: 'should explain the answer needs a connection',
        );

        // And it must route them somewhere real rather than dead-ending.
        expect(reply.toLowerCase(), contains('municipal hall'));

        // No action tag: this is a question, not a report/agent/end intent.
        expect(reply, isNot(contains('[ACTION:')));
      });
    }

    test('does not fabricate a name for the mayor', () {
      final reply = LocalAssistant.reply('sino ang mayor ng aparri').toLowerCase();

      // The failure this guards against is a hardcoded officials list that goes
      // stale at the next election with nobody watching. The honest reply names
      // no person, so the giveaway is a title followed by a name.
      expect(reply, isNot(matches(RegExp(r'mayor\s+(ay\s+)?si\s+\w'))));
      expect(reply, isNot(contains('ang mayor ay ')));
    });

    test(
      'a business permit question still reaches the permit answer, not this one',
      () {
        // "mayor's permit" contains "mayor". The officials entry sits later in
        // the keyword list and matches on first-match-wins, so this pins that
        // the earlier, more specific permit entry is the one that fires.
        final reply = LocalAssistant.reply('paano kumuha ng mayors permit');

        expect(reply.toLowerCase(), contains('permit'));
        expect(reply.toLowerCase(), isNot(contains('internet')));
      },
    );
  });
}
