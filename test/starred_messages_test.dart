import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/chat_backup.dart';
import 'package:local_chat/core/chat_file.dart';
import 'package:local_chat/core/group_models.dart';
import 'package:local_chat/core/models.dart';
import 'package:local_chat/core/message_reply.dart';
import 'package:local_chat/core/secure_session.dart';
import 'package:local_chat/core/starred_message.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'package:local_chat/demo/demo_transport.dart';
import 'package:local_chat/services/chat_controller.dart';
import 'chat_backup_test.dart' show fastBackupKey;
import 'group_draft_test.dart' show emptyGroup;
import 'message_reply_test.dart' show ReplyStore;

const incomingStar = StarredMessage(
  target: 'alice',
  id: 'same',
  outgoing: false,
);
const outgoingStar = StarredMessage(
  target: 'alice',
  id: 'same',
  outgoing: true,
);
ChatMessage starMessage({
  bool outgoing = false,
  String text = 'Saved message',
  String status = 'received',
}) => ChatMessage(
  id: 'same',
  peerId: 'alice',
  text: text,
  timestamp: 10,
  outgoing: outgoing,
  status: status,
);

class StarStore extends ReplyStore {
  bool failStars = false, failStarWrite = false;
  Completer<void>? historyGate, starsGate;
  final historyEntered = Completer<void>();
  @override
  Future<List<StarredMessage>> starredMessages() async {
    final result = await super.starredMessages();
    final gate = starsGate;
    starsGate = null;
    await gate?.future;
    if (failStars) throw StateError('Private storage detail');
    return result;
  }

  @override
  Future<bool> setMessageStarred(StarredMessage s, bool value) async {
    if (failStarWrite) throw StateError('Private storage detail');
    return super.setMessageStarred(s, value);
  }

  @override
  Future<List<ChatMessage>> messages(String peer) async {
    if (historyGate != null) {
      if (!historyEntered.isCompleted) historyEntered.complete();
      await historyGate!.future;
    }
    return super.messages(peer);
  }
}

Future<GroupHistory> signedStarGroup(DemoStore store) async {
  final group = await emptyGroup(store);
  final author = await identityId(group.host);
  final message = await GroupText.create(
    store.identity,
    'Member',
    group: group.id,
    host: group.host,
    epoch: randomId(),
    view: 1,
    text: 'Group saved text',
    targets: [author],
  );
  return group.copy(messages: [message], pinned: true, archived: true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('star references strictly separate target, direction and author', () {
    expect(StarredMessage.parse(incomingStar.toJson()), incomingStar);
    expect(incomingStar, isNot(outgoingStar));
    for (final raw in [
      null,
      {},
      {'target': 'alice', 'id': 'same', 'outgoing': 1},
      {'target': '', 'id': 'same', 'outgoing': false},
      {'target': 'alice', 'id': 'same', 'author': 'invalid'},
      {...incomingStar.toJson(), 'author': 'a' * 64},
    ]) {
      expect(() => StarredMessage.parse(raw), throwsFormatException);
    }
    expect(
      StarredMessage(target: 'room', id: 'same', author: 'a' * 64),
      isNot(StarredMessage(target: 'room', id: 'same', author: 'b' * 64)),
    );
  });
  test(
    'demo stars are idempotent, local and preserve history, drafts and organization',
    () async {
      final store = DemoStore();
      await store.open();
      await store.savePeer('alice', 'Alice');
      await store.saveMessage(starMessage());
      await store.saveMessage(starMessage(outgoing: true));
      await store.saveDraft('alice', 'Unsent draft');
      await store.setArchived('alice', true);
      await store.setPinned('alice', true);
      final before = await store.exportBackup();
      expect(await store.setMessageStarred(incomingStar, true), isTrue);
      await store.setMessageStarred(incomingStar, true);
      expect(await store.starredMessages(), [incomingStar]);
      final after = await store.exportBackup();
      expect(after.messages, before.messages);
      expect(after.drafts, before.drafts);
      expect(after.peers, before.peers);
      await store.setMessageStarred(outgoingStar, true);
      await store.setMessageStarred(incomingStar, false);
      expect(await store.starredMessages(), [outgoingStar]);
      expect(
        await store.setMessageStarred(
          const StarredMessage(target: 'missing', id: 'same', outgoing: false),
          true,
        ),
        isFalse,
      );
    },
  );
  test(
    'group stars survive receipts and history saves and delete with their group',
    () async {
      final store = DemoStore();
      await store.open();
      final group = await signedStarGroup(store);
      await store.saveGroupHistory(group);
      final star = StarredMessage(
        target: group.id,
        id: group.messages.single.id,
        author: group.messages.single.author,
      );
      await store.setMessageStarred(star, true);
      await store.saveGroupHistory(
        group.copy(messages: [group.messages.single.copy(read: true)]),
      );
      expect(await store.starredMessages(), [star]);
      expect((await store.groupHistories()).single.archived, isTrue);
      await store.deleteGroupHistory(group.id);
      expect(await store.starredMessages(), isEmpty);
      expect(await store.setMessageStarred(star, true), isFalse);
    },
  );
  test(
    'v10 encrypted archives restore mixed direct, file and signed group stars',
    () async {
      final source = DemoStore();
      await source.open();
      await source.savePeer('alice', 'Alice');
      await source.saveMessage(starMessage());
      await source.setMessageStarred(incomingStar, true);
      await source.saveDraftState(
        'alice',
        '',
        const MessageReply(
          id: 'same',
          outgoing: false,
          name: 'Alice',
          text: 'Saved message',
        ),
      );
      await source.saveMessage(
        const ChatMessage(
          id: 'answer',
          peerId: 'alice',
          text: 'Quoted answer',
          timestamp: 11,
          outgoing: true,
          status: 'delivered',
          reply: MessageReply(
            id: 'same',
            outgoing: false,
            name: 'Alice',
            text: 'Saved message',
          ),
        ),
      );
      final bytes = Uint8List.fromList([1, 2, 3]);
      final file = await ChatFile.fromBytes('saved.bin', bytes);
      final message = ChatMessage(
        id: 'file',
        peerId: 'alice',
        text: 'File',
        timestamp: 12,
        outgoing: true,
        status: 'delivered',
        file: file,
      );
      await source.saveFileMessage(message, bytes);
      final fileStar = const StarredMessage(
        target: 'alice',
        id: 'file',
        outgoing: true,
      );
      await source.setMessageStarred(fileStar, true);
      final group = await signedStarGroup(source);
      await source.saveGroupHistory(group);
      final groupStar = StarredMessage(
        target: group.id,
        id: group.messages.single.id,
        author: group.messages.single.author,
      );
      await source.setMessageStarred(groupStar, true);
      final data = await source.exportBackup();
      expect(data.toJson()['version'], 10);
      final codec = BackupCodec(deriveKey: fastBackupKey);
      final restored = await codec.decrypt(
        await codec.encrypt(data, 'long enough password'),
        'long enough password',
      );
      final destination = DemoStore();
      await destination.open();
      final seed = (await destination.exportBackup()).seed;
      await destination.importBackup(restored);
      expect(
        await destination.starredMessages(),
        unorderedEquals([incomingStar, fileStar, groupStar]),
      );
      expect((await destination.exportBackup()).seed, seed);
      expect(await destination.draftReply('alice'), isNotNull);
      expect((await destination.messages('alice'))[1].reply, isNotNull);
      expect(
        await destination.fileBytes((await destination.messages('alice')).last),
        bytes,
      );
      await destination.setMessageStarred(incomingStar, false);
      await destination.importBackup(
        restored,
      ); // Archives add stars, without unstar tombstones.
      expect(await destination.starredMessages(), contains(incomingStar));
      final moving = DemoStore();
      await moving.open();
      await moving.importBackup(restored, moveIdentity: true);
      expect((await moving.exportBackup()).seed, restored.seed);
      expect(await moving.starredMessages(), hasLength(3));
    },
  );
  test(
    'backups reject dangling, duplicate and downgraded stars while old versions still import',
    () async {
      final store = DemoStore();
      await store.open();
      await store.savePeer('alice', 'Alice');
      await store.saveMessage(starMessage());
      final old = await store.exportBackup();
      expect(old.toJson()['version'], 1);
      expect((await BackupData.parse(old.toJson())).stars, isEmpty);
      await store.setMessageStarred(incomingStar, true);
      final data = await store.exportBackup(),
          raw = (await store.exportBackup()).toJson();
      for (final invalid in [
        {...raw, 'version': 9},
        {...raw, 'messages': []},
        {
          ...raw,
          'stars': [...data.stars, ...data.stars],
        },
        {
          ...raw,
          'stars': [
            const StarredMessage(
              target: 'alice',
              id: 'same',
              outgoing: true,
            ).toJson(),
          ],
        },
        {...raw, 'stars': List.filled(5001, incomingStar.toJson())},
      ]) {
        await expectLater(BackupData.parse(invalid), throwsFormatException);
      }
    },
  );
  test(
    'import never attaches a source star to a conflicting destination original',
    () async {
      final source = DemoStore();
      await source.open();
      await source.savePeer('alice', 'Alice');
      await source.saveMessage(starMessage());
      await source.setMessageStarred(incomingStar, true);
      final destination = DemoStore();
      await destination.open();
      await destination.savePeer('alice', 'Alice');
      await destination.saveMessage(
        starMessage(text: 'Different destination body'),
      );
      final plan = await destination.importBackup(await source.exportBackup());
      expect(plan.conflicts, 1);
      expect(await destination.starredMessages(), isEmpty);
      expect(
        (await destination.messages('alice')).single.text,
        'Different destination body',
      );
      await destination.setMessageStarred(incomingStar, true);
      await destination.importBackup(await source.exportBackup());
      expect(await destination.starredMessages(), [incomingStar]);
    },
  );
  test(
    'queued cancellation, conversation deletion and clear remove matching stars only',
    () async {
      final store = DemoStore();
      await store.open();
      await store.savePeer('alice', 'Alice');
      await store.saveMessage(starMessage());
      await store.saveMessage(starMessage(outgoing: true, status: 'queued'));
      await store.setMessageStarred(incomingStar, true);
      await store.setMessageStarred(outgoingStar, true);
      expect(await store.deleteQueuedMessage('same', 'alice'), isTrue);
      expect(await store.starredMessages(), [incomingStar]);
      await store.deleteConversation('alice');
      expect(await store.starredMessages(), isEmpty);
      await store.savePeer('alice', 'Alice');
      await store.saveMessage(starMessage());
      await store.setMessageStarred(incomingStar, true);
      await store.clearHistory();
      expect(await store.starredMessages(), isEmpty);
    },
  );
  test(
    'controller rejects stars while locked/background and stale queued work after return',
    () async {
      final store = StarStore();
      final chat = ChatController(DemoTransport(), store, isDemo: true);
      addTearDown(chat.dispose);
      await chat.initialize();
      await store.savePeer('alice', 'Alice');
      await store.saveMessage(starMessage());
      chat.setAppAccess(false);
      expect(await chat.setStarred(incomingStar, true), isFalse);
      chat.setAppAccess(true);
      chat.setAppForeground(false);
      expect(await chat.setStarred(incomingStar, true), isFalse);
      chat.setAppForeground(true);
      store.historyGate = Completer<void>();
      final opening = chat.viewHistory((await store.conversations()).single);
      await store.historyEntered.future;
      final stale = chat.setStarred(incomingStar, true);
      chat.setAppForeground(false);
      chat.setAppForeground(true);
      store.historyGate!.complete();
      await opening;
      expect(await stale, isFalse);
      expect(await store.starredMessages(), isEmpty);
      expect(await chat.setStarred(incomingStar, true), isTrue);
      expect(chat.isStarred(incomingStar), isTrue);
    },
  );
  test(
    'controller reports generic storage errors and reloads stars after deletion',
    () async {
      final store = StarStore();
      final c = ChatController(DemoTransport(), store, isDemo: true);
      addTearDown(c.dispose);
      await c.initialize();
      await c.refreshStars();
      await store.savePeer('alice', 'Alice');
      await store.saveMessage(starMessage());
      store.failStarWrite = true;
      expect(await c.setStarred(incomingStar, true), isFalse);
      expect(c.starsError, isNot(contains('Private')));
      store.failStarWrite = false;
      expect(await c.setStarred(incomingStar, true), isTrue);
      expect(c.starsError, isNull);
      await c.deleteConversation('alice');
      await c.refreshStars();
      expect(c.starred, isEmpty);
      store.failStars = true;
      await c.refreshStars();
      expect(c.starsError, contains('Could not load'));
      store.failStars = false;
      await c.refreshStars();
      expect(c.starsError, isNull);
    },
  );
  test(
    'a delayed star refresh cannot restore an unstarred cached reference',
    () async {
      final store = StarStore();
      final chat = ChatController(DemoTransport(), store, isDemo: true);
      addTearDown(chat.dispose);
      await chat.initialize();
      await chat.refreshStars();
      await store.savePeer('alice', 'Alice');
      await store.saveMessage(starMessage());
      await chat.setStarred(incomingStar, true);
      final gate = Completer<void>();
      store.starsGate = gate;
      final stale = chat.refreshStars();
      await Future<void>.delayed(Duration.zero);
      await chat.setStarred(incomingStar, false);
      expect(chat.starred, isEmpty);
      gate.complete();
      await stale;
      expect(chat.starred, isEmpty);
    },
  );
}
