import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/chat_backup.dart';
import 'package:local_chat/core/contact_nickname.dart';
import 'package:local_chat/core/models.dart';
import 'package:local_chat/core/starred_message.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'package:local_chat/demo/demo_transport.dart';
import 'package:local_chat/services/chat_controller.dart';
import 'package:local_chat/services/chat_search_controller.dart';
import 'chat_backup_test.dart' show fastBackupKey;
import 'chat_controller_test.dart' show LinkedTransport, settle;
import 'starred_messages_test.dart'
    show signedStarGroup, starMessage, incomingStar;

class NicknameStore extends DemoStore {
  bool fail = false;
  Completer<void>? entered, release;
  @override
  Future<bool> setNickname(
    String peer,
    String? nickname, {
    bool Function()? isCurrent,
  }) async {
    entered?.complete();
    if (release != null) await release!.future;
    if (fail) throw StateError('private failure detail');
    return super.setNickname(peer, nickname, isCurrent: isCurrent);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'V11 mixed archives retain direct/group messages, stars and original names',
    () async {
      final source = DemoStore(), target = DemoStore();
      await source.open();
      await target.open();
      addTearDown(source.close);
      addTearDown(target.close);
      await source.savePeer('alice', 'Phone');
      await source.saveMessage(starMessage());
      await source.setMessageStarred(incomingStar, true);
      final group = await signedStarGroup(source);
      await source.saveGroupHistory(group);
      final groupStar = StarredMessage(
        target: group.id,
        id: group.messages.single.id,
        author: group.messages.single.author,
      );
      await source.setMessageStarred(groupStar, true);
      await source.setNickname('alice', 'Friend');
      final data = await BackupData.parse(
        (await source.exportBackup()).toJson(),
      );
      expect(data.toJson()['version'], 11);
      expect(data.stars, hasLength(2));
      await target.importBackup(data);
      expect((await target.conversations()).single.originalName, 'Phone');
      expect((await target.conversations()).single.name, 'Friend');
      expect(await target.starredMessages(), hasLength(2));
      expect(
        (await target.groupHistories()).single.messages.single.envelope,
        group.messages.single.envelope,
      );
    },
  );

  test(
    'Disposing the controller rejects a pending nickname before storage mutation',
    () async {
      final store = NicknameStore();
      final c = ChatController(DemoTransport(), store);
      await c.initialize();
      await store.savePeer('alice', 'Phone');
      store.entered = Completer<void>();
      store.release = Completer<void>();
      final pending = c.setNickname('alice', 'Discard');
      await store.entered!.future;
      c.dispose();
      store.release!.complete();
      expect(await pending, isFalse);
      expect((await store.conversations()).single.nickname, isNull);
      await store.close();
    },
  );
  test(
    'Nickname normalization bounds bytes, retains Unicode and rejects control characters',
    () {
      expect(normalizeContactNickname('  Friend سلام 👋  '), 'Friend سلام 👋');
      expect(normalizeContactNickname('  '), isNull);
      expect(normalizeContactNickname(null), isNull);
      expect(normalizeContactNickname('a' * 128), 'a' * 128);
      for (final bad in [
        'a' * 129,
        '👋' * 33,
        'line\nbreak',
        'a\tb',
        'a\u0000b',
        'a\u202eb',
      ]) {
        expect(() => normalizeContactNickname(bad), throwsFormatException);
      }
    },
  );

  test(
    'Demo preserves nicknames through new activity, organization and advertised name changes',
    () async {
      final s = DemoStore();
      await s.open();
      addTearDown(s.close);
      await s.savePeer('alice', 'Phone');
      await s.setNickname('alice', 'Friend');
      await s.savePeer('alice', 'New phone');
      await s.setPinned('alice', true);
      await s.setArchived('alice', true);
      await s.saveMessage(
        const ChatMessage(
          id: 'm',
          peerId: 'alice',
          text: 'Find me',
          timestamp: 1,
          outgoing: false,
          status: 'received',
        ),
      );
      final p = (await s.conversations()).single;
      expect(p.name, 'Friend');
      expect(p.originalName, 'New phone');
      expect(p.pinned && p.archived, isTrue);
      expect(p.unreadCount, 1);
      expect((await s.search('friend')).conversations.single.id, 'alice');
      expect((await s.search('new phone')).conversations.single.name, 'Friend');
      expect(
        (await s.search('find')).messages.single.conversation.name,
        'Friend',
      );
      await s.deleteConversation('alice');
      await s.savePeer('alice', 'Phone');
      expect((await s.conversations()).single.nickname, isNull);
    },
  );

  test(
    'V11 encrypted archive roundtrip, strict nicknames and old version fallback',
    () async {
      final s = DemoStore();
      await s.open();
      addTearDown(s.close);
      await s.savePeer('alice', 'Phone');
      await s.setNickname('alice', 'Friend');
      final data = await s.exportBackup();
      expect(data.toJson()['version'], 11);
      final codec = BackupCodec(deriveKey: fastBackupKey);
      final bytes = await codec.encrypt(data, 'password long enough');
      final decoded = await codec.decrypt(bytes, 'password long enough');
      expect(decoded.peers.single['nickname'], 'Friend');
      expect(decoded.peers.single['name'], 'Phone');
      for (final value in [null, 4, '', ' padded ', 'a' * 129, 'a\nb']) {
        final raw = jsonDecode(jsonEncode(data.toJson())) as Map;
        (raw['peers'] as List).single['nickname'] = value;
        await expectLater(BackupData.parse(raw), throwsFormatException);
      }
      final old = data.toJson()..['version'] = 10;
      await expectLater(BackupData.parse(old), throwsFormatException);
      await s.setNickname('alice', null);
      final legacy = await s.exportBackup();
      expect(legacy.toJson()['version'], 1);
      expect(
        (await BackupData.parse(
          legacy.toJson(),
        )).peers.single.containsKey('nickname'),
        isFalse,
      );
    },
  );

  test(
    'Import transfers new contacts and identity but preserves existing or removed nicknames',
    () async {
      final source = DemoStore(), target = DemoStore();
      await source.open();
      await target.open();
      addTearDown(source.close);
      addTearDown(target.close);
      await source.savePeer('alice', 'Phone');
      await source.setNickname('alice', 'Imported');
      final data = await source.exportBackup();
      await target.importBackup(data, moveIdentity: true);
      expect(
        (await target.identity.extractPublicKey()).bytes,
        (await source.identity.extractPublicKey()).bytes,
      );
      expect((await target.conversations()).single.name, 'Imported');
      await target.setNickname('alice', 'Local');
      await target.importBackup(data);
      expect((await target.conversations()).single.name, 'Local');
      await target.setNickname('alice', null);
      await target.importBackup(data);
      expect((await target.conversations()).single.nickname, isNull);
      await expectLater(
        target.importBackup(data, moveIdentity: true),
        throwsFormatException,
      );
    },
  );

  test(
    'Controller saves refresh labels/search while keeping original reply author and drafts',
    () async {
      final c = ChatController(DemoTransport(), NicknameStore());
      // Use the actual controller-owned store.
      final store = c.store;
      await c.initialize();
      addTearDown(c.dispose);
      await store.savePeer('alice', 'Phone');
      c.conversations = await store.conversations();
      await c.viewHistory(c.conversations.single);
      await c.drafts.load('alice');
      c.drafts.setText('alice', 'Unsent');
      final search = ChatSearchController(c, debounce: Duration.zero);
      addTearDown(search.dispose);
      search.setQuery('Friend');
      await settle();
      expect(search.results.conversations, isEmpty);
      expect(await c.setNickname('alice', 'Friend'), isTrue);
      await settle();
      expect(search.results.conversations.single.name, 'Friend');
      expect(c.selectedDisplayName, 'Friend');
      expect(c.selectedName, 'Phone');
      expect(c.drafts.textFor('alice'), 'Unsent');
    },
  );

  test(
    'Controller rejects unavailable/stale saves and permits generic-error retry',
    () async {
      final s = NicknameStore();
      final c = ChatController(DemoTransport(), s);
      await c.initialize();
      addTearDown(c.dispose);
      await s.savePeer('alice', 'Phone');
      s.fail = true;
      expect(await c.setNickname('alice', 'Friend'), isFalse);
      expect(c.error, 'Could not save the nickname. Please try again.');
      s.fail = false;
      expect(await c.setNickname('alice', 'Friend'), isTrue);
      expect(c.error, isNull);
      expect(await c.setNickname('missing', 'Friend'), isFalse);
      s.entered = Completer<void>();
      s.release = Completer<void>();
      final pending = c.setNickname('alice', 'Discard');
      await s.entered!.future;
      c.setAppForeground(false);
      c.setAppForeground(true);
      s.release!.complete();
      expect(await pending, isFalse);
      expect((await s.conversations()).single.name, 'Friend');
      c.setAppAccess(false);
      expect(await c.setNickname('alice', 'Locked'), isFalse);
      c.setAppAccess(true);
      expect(
        await c.setNickname('alice', 'Covered', isCurrent: () => false),
        isFalse,
      );
    },
  );

  test(
    'Local nickname never changes peer names, session trust or outgoing reply metadata',
    () async {
      final ta = LinkedTransport(), tb = LinkedTransport();
      ta.other = tb;
      tb.other = ta;
      final a = ChatController(ta, DemoStore()),
          b = ChatController(tb, DemoStore());
      addTearDown(() async {
        a.dispose();
        b.dispose();
        await ta.bus.close();
        await tb.bus.close();
      });
      await a.initialize();
      await b.initialize();
      await a.start();
      await b.start();
      await a.connect(const Peer('b', 'Bob'));
      await settle();
      await a.confirmCode();
      await b.confirmCode();
      await settle();
      final original = a.selectedName, code = a.code;
      await b.sendText('Original text');
      await settle();
      expect(await a.setNickname(a.selectedPeer!, 'PRIVATE NICKNAME'), isTrue);
      expect(a.selectedName, original);
      expect(a.selectedDisplayName, 'PRIVATE NICKNAME');
      expect(a.ready && b.ready, isTrue);
      expect(a.code, code);
      expect(await a.replyTo(a.messages.single), isTrue);
      final reply = a.drafts.replyFor(a.selectedPeer!)!;
      expect(reply.name, original);
      await a.sendText('Reply');
      await settle();
      expect(b.messages.last.reply!.name, original);
      expect(b.selectedDisplayName, isNot('PRIVATE NICKNAME'));
    },
  );
}
