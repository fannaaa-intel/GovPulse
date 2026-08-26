import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:govpulse/core/services/chat_service.dart';
import 'package:govpulse/core/widgets/Home/Chat-agent/chat_models.dart';

/// Seeds [box] with a conversation already in a TERMINAL stage.
///
/// [ChatService.startNewConversation] is a no-op unless `isTerminal` — the
/// button it backs only exists once a chat has ended — so a service left on the
/// default `greeting` stage would skip `_resetAll` entirely and the scoping
/// assertion below would pass without ever running the code it guards.
/// Writing the stage into the box makes `_loadCache` restore it on bind, which
/// reaches the same state the app does without poking at private fields.
Future<void> seedTerminalConversation(String boxName) async {
  final b = await Hive.openBox(boxName);
  await b.putAll({
    'messages': const <dynamic>[],
    'stage': ConversationStage.ticketCreated.index,
  });
  await b.close();
}

/// Guards the per-user scoping of the chat cache's Hive box name.
///
/// Chat history is stored per account by suffixing the box name with the uid
/// (`chat_cache__<uid>`). The scoping is invisible from the outside — nothing
/// in the UI shows which box is bound — so the only way it stays correct is a
/// test that asserts the name directly.
///
/// The bug this locks down: `_resetAll` rebound the service to the BARE
/// `chat_cache` for both of its reasons. That is right for `logout` but wrong
/// for `userRequested` (starting a new conversation), where the user is still
/// signed in — every `_persist()` after that wrote their messages into the
/// shared box, which is also the box read when NOBODY is signed in. The next
/// account on the device, and any signed-out visitor, read them back.
void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('govpulse_chat_scope');
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  tearDown(() {
    ChatService.setUserScopeForTest(null);
  });

  group('box naming', () {
    test('is suffixed with the uid while signed in', () {
      ChatService.setUserScopeForTest('user-alice');
      expect(ChatService.scopedForTest('chat_cache'), 'chat_cache__user-alice');
    });

    test('falls back to the bare name when signed out', () {
      ChatService.setUserScopeForTest(null);
      expect(ChatService.scopedForTest('chat_cache'), 'chat_cache');
    });

    test('two accounts never resolve to the same box', () {
      ChatService.setUserScopeForTest('user-alice');
      final alice = ChatService.scopedForTest('chat_cache');
      ChatService.setUserScopeForTest('user-bob');
      final bob = ChatService.scopedForTest('chat_cache');
      expect(alice, isNot(bob));
    });
  });

  group('starting a new conversation', () {
    test('keeps the box scoped to the signed-in user', () async {
      await seedTerminalConversation('chat_cache__user-alice');
      await ChatService.onUserAuthenticated('user-alice');
      expect(ChatService.I.isTerminal, isTrue,
          reason: 'startNewConversation is a no-op unless the chat has ended, '
              'so the assertion below would be vacuous without this');
      expect(
        ChatService.I.activeBoxNameForTest,
        'chat_cache__user-alice',
        reason: 'signing in must bind to the per-user box',
      );

      await ChatService.I.startNewConversation();

      // THE REGRESSION. This used to be the bare 'chat_cache'.
      expect(
        ChatService.I.activeBoxNameForTest,
        'chat_cache__user-alice',
        reason: 'a new conversation must not drop the user scope — doing so '
            'points writes at the box shared by every account on the device',
      );
    });

    test('a second account does not inherit the first account\'s box', () async {
      await seedTerminalConversation('chat_cache__user-alice');
      await ChatService.onUserAuthenticated('user-alice');
      expect(ChatService.I.isTerminal, isTrue);
      await ChatService.I.startNewConversation();

      await ChatService.onUserSignedOut();
      await ChatService.onUserAuthenticated('user-bob');

      expect(ChatService.I.activeBoxNameForTest, 'chat_cache__user-bob');
      expect(
        ChatService.I.activeBoxNameForTest,
        isNot(contains('alice')),
        reason: 'bob must never be bound to a box holding alice\'s messages',
      );
    });
  });

  group('purgeLegacyUnscopedBoxes', () {
    test('deletes the pre-fix shared boxes and leaves scoped ones alone',
        () async {
      final leaked = await Hive.openBox('chat_cache');
      await leaked.put('messages', ['alice private message']);
      await leaked.close();

      final mine = await Hive.openBox('chat_cache__user-alice');
      await mine.put('messages', ['my own message']);
      await mine.close();

      await ChatService.purgeLegacyUnscopedBoxes();

      final afterLeak = await Hive.openBox('chat_cache');
      expect(
        afterLeak.get('messages'),
        isNull,
        reason: 'the shared box is where leaked history lives; it must be gone',
      );

      final afterMine = await Hive.openBox('chat_cache__user-alice');
      expect(
        afterMine.get('messages'),
        ['my own message'],
        reason: 'a per-user box is live data and must survive the purge',
      );
    });

    test('is safe to run when nothing is there', () async {
      await ChatService.purgeLegacyUnscopedBoxes();
      await ChatService.purgeLegacyUnscopedBoxes();
    });
  });
}
