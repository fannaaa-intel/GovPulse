import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:govpulse/core/services/chat_service.dart';
import 'package:govpulse/core/services/local_assistant.dart';
import 'package:govpulse/core/widgets/Home/Chat-agent/chat_models.dart';

/// The live staff chat was removed in the 2026-10-12 panel revision. Two
/// things have to hold on a citizen's phone that ran the OLD build:
///
///  * a conversation cached mid-handoff must not come back as one — there is
///    no staff on the other end and nothing would ever end it;
///  * asking for a person must be answered with where to go instead, in the
///    citizen's language, and never with "connecting you to staff".
void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('govpulse_no_live_chat');
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('a cached live-chat stage', () {
    // Every stage that only existed for the staff handoff. Indices are what
    // Hive holds, which is why the enum keeps these values at all.
    const retired = [
      ConversationStage.awaitingCategory,
      ConversationStage.awaitingDetails,
      ConversationStage.submitting,
      ConversationStage.ticketCreated,
      ConversationStage.connectedToAgent,
      ConversationStage.confirmingContact,
      ConversationStage.correctingContact,
    ];

    for (final stage in retired) {
      test('${stage.name} restores as an ended conversation', () async {
        final uid = 'user-${stage.name}';
        final b = await Hive.openBox('chat_cache__$uid');
        await b.putAll({
          'messages': const <dynamic>[],
          'stage': stage.index,
          'lastTicketId': 'old-ticket',
        });
        await b.close();

        await ChatService.onUserAuthenticated(uid);

        expect(ChatService.I.stage, ConversationStage.ended);
        expect(ChatService.I.isTerminal, isTrue,
            reason: 'the citizen must be offered "Start new conversation", '
                'not a composer wired to a ticket nobody reads');
        await ChatService.onUserSignedOut();
      });
    }

    test('a live stage still restores as itself', () async {
      // Control: the mapping must not swallow the stages that remain valid.
      const uid = 'user-asking';
      final b = await Hive.openBox('chat_cache__$uid');
      await b.putAll({
        'messages': const <dynamic>[],
        'stage': ConversationStage.askingQuestion.index,
      });
      await b.close();

      await ChatService.onUserAuthenticated(uid);
      expect(ChatService.I.stage, ConversationStage.askingQuestion);
      await ChatService.onUserSignedOut();
    });
  });

  group('asking for a person', () {
    const requests = {
      'tagalog': 'gusto ko po makausap ang staff',
      'ilocano': 'kayat ko ti makisarita iti staff, pangngaasi',
      'english': 'can i talk to a real person please',
    };

    requests.forEach((lang, message) {
      test('is still recognised ($lang)', () {
        expect(LocalAssistant.reply(message), startsWith('[ACTION:AGENT]'));
      });

      test('points to the forms and never promises a connection ($lang)', () {
        final reply = LocalAssistant.noLiveStaff(message).toLowerCase();
        expect(reply, contains('report issue'));
        expect(reply, contains('suggestion'));
        expect(reply, contains('feedback'));
        for (final promise in ['ikonekta', 'iyasideg', 'connect you']) {
          expect(reply, isNot(contains(promise)));
        }
      });
    });
  });
}
