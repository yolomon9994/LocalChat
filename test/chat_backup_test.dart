import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/chat_backup.dart';
import 'package:local_chat/core/models.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'package:local_chat/services/draft_controller.dart';

Future<Uint8List> fastBackupKey(String password, Uint8List salt) async =>
    Uint8List.fromList(
      (await Sha256().hash([...salt, ...utf8.encode(password)])).bytes,
    );

Future<BackupData> sampleBackup() async {
  final store = DemoStore();
  await store.open();
  await store.savePeer('alice', 'Alice سلام');
  await store.setPinned('alice', true);
  await store.saveMessage(
    const ChatMessage(
      id: 'one',
      peerId: 'alice',
      text: 'Secret سلام 👋',
      timestamp: 1,
      outgoing: false,
      status: 'received',
    ),
  );
  await store.saveDraft('alice', '  draft\n👋  ');
  return store.exportBackup();
}

class BlockingBackupStore extends DemoStore {
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<BackupMerge> importBackup(
    BackupData data, {
    bool moveIdentity = false,
  }) async {
    entered.complete();
    await release.future;
    return super.importBackup(data, moveIdentity: moveIdentity);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Import preserves a newer draft edit or deletion queued during storage work',
    () async {
      final data = await sampleBackup(), store = BlockingBackupStore();
      await store.open();
      await store.savePeer('alice', 'Alice');
      final drafts = DraftController(store);
      addTearDown(drafts.dispose);
      await drafts.load('alice');
      final importing = drafts.importBackup(data);
      await store.entered.future;
      drafts.setText('alice', 'New text while importing');
      drafts.setText('alice', '');
      store.release.complete();
      await importing;
      await drafts.settled;
      expect(drafts.textFor('alice'), '');
      expect(await store.draft('alice'), '');
    },
  );
  test(
    'Password encryption round-trips every field with fresh salt and nonce',
    () async {
      final codec = BackupCodec(deriveKey: fastBackupKey),
          data = await sampleBackup();
      final first = await codec.encrypt(data, 'a long password'),
          second = await codec.encrypt(data, 'a long password');
      expect(first, isNot(second));
      expect(
        utf8.decode(first, allowMalformed: true),
        isNot(contains('Secret')),
      );
      expect(
        utf8.decode(first, allowMalformed: true),
        isNot(contains(data.seed)),
      );
      expect(
        (await codec.decrypt(first, 'a long password')).toJson(),
        data.toJson(),
      );
      await expectLater(
        codec.decrypt(first, 'a wrong password'),
        throwsFormatException,
      );
      for (final offset in [9, 25, 49, 65, first.length - 1]) {
        final corrupt = Uint8List.fromList(first);
        corrupt[offset] ^= 1;
        await expectLater(
          codec.decrypt(corrupt, 'a long password'),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'Production KDF and archive work together outside the widget thread',
    () async {
      final codec = BackupCodec(), data = await sampleBackup();
      final bytes = await codec.encrypt(data, 'production password');
      expect(
        (await codec.decrypt(bytes, 'production password')).owner,
        data.owner,
      );
    },
  );
  test(
    'Bad password, header, size and version fail before doing KDF work',
    () async {
      var calls = 0;
      final codec = BackupCodec(
        deriveKey: (p, s) async {
          calls++;
          return fastBackupKey(p, s);
        },
      );
      final data = await sampleBackup();
      await expectLater(codec.encrypt(data, 'short'), throwsFormatException);
      await expectLater(
        codec.decrypt(Uint8List(65), 'a long password'),
        throwsFormatException,
      );
      await expectLater(
        codec.decrypt(Uint8List(backupMaxFile + 1), 'a long password'),
        throwsFormatException,
      );
      await expectLater(
        codec.decrypt(Uint8List(66), 'a long password'),
        throwsFormatException,
      );
      final unsupported = Uint8List.fromList([
        76,
        67,
        66,
        65,
        67,
        75,
        85,
        80,
        2,
        ...List.filled(57, 0),
      ]);
      await expectLater(
        codec.decrypt(unsupported, 'a long password'),
        throwsFormatException,
      );
      expect(calls, 0);
    },
  );
  test(
    'Payload validation rejects duplicate, orphan, malformed and oversized records',
    () async {
      final data = await sampleBackup(), raw = data.toJson();
      final variants = [
        {...raw, 'owner': 'wrong'},
        {
          ...raw,
          'seed': base64Encode([1, 2]),
        },
        {
          ...raw,
          'peers': [...data.peers, ...data.peers],
        },
        {
          ...raw,
          'messages': [...data.messages, ...data.messages],
        },
        {
          ...raw,
          'messages': [
            {...data.messages.first, 'peer': 'missing'},
          ],
        },
        {
          ...raw,
          'messages': [
            {...data.messages.first, 'outgoing': 1},
          ],
        },
        {
          ...raw,
          'messages': [
            {...data.messages.first, 'text': 'x' * 4097},
          ],
        },
        {
          ...raw,
          'drafts': [
            {'peer': 'missing', 'text': 'draft'},
          ],
        },
        {
          ...raw,
          'drafts': [...data.drafts, ...data.drafts],
        },
        {...raw, 'peers': List.filled(5001, data.peers.first)},
      ];
      for (final variant in variants) {
        await expectLater(BackupData.parse(variant), throwsFormatException);
      }
    },
  );
  test(
    'Merge preserves conflicting text and distinguishes direction; demo identity transfer is explicit',
    () async {
      final source = await sampleBackup(), destination = DemoStore();
      await destination.open();
      await destination.savePeer('alice', 'My name');
      await destination.saveMessage(
        const ChatMessage(
          id: 'one',
          peerId: 'alice',
          text: 'Existing conflicting text',
          timestamp: 1,
          outgoing: false,
          status: 'received',
        ),
      );
      final result = await destination.importBackup(source);
      expect(result.conflicts, 1);
      expect(result.newMessages, 0);
      expect(
        (await destination.messages('alice')).single.text,
        'Existing conflicting text',
      );
      expect((await destination.conversations()).single.name, 'My name');
      await expectLater(
        destination.importBackup(source, moveIdentity: true),
        throwsFormatException,
      );
      final empty = DemoStore();
      await empty.open();
      final old = (await empty.exportBackup()).owner;
      await empty.importBackup(source, moveIdentity: true);
      expect((await empty.exportBackup()).owner, source.owner);
      expect(source.owner, isNot(old));
      expect((await empty.conversations()).single.pinned, isTrue);
      expect((await empty.conversations()).single.unreadCount, 1);
      final phone = await BackupData.parse({...source.toJson(), 'demo': false});
      await expectLater(empty.importBackup(phone), throwsFormatException);
    },
  );
}
