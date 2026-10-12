import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/chat_backup.dart';
import 'package:local_chat/core/group_models.dart';
import 'package:local_chat/core/secure_session.dart';
import 'package:local_chat/demo/demo_store.dart';

void main() {
  late DemoStore source, destination;
  late GroupHistory history;
  setUp(() async {
    source = DemoStore();
    destination = DemoStore();
    await source.open();
    await destination.open();
    final public = base64Encode(
      (await source.identity.extractPublicKey()).bytes,
    );
    final id = randomId();
    final m = await GroupText.create(
      source.identity,
      'Source',
      group: id,
      host: public,
      epoch: randomId(),
      view: 1,
      text: 'Group secret سلام',
      targets: [await identityId(public)],
    );
    history = GroupHistory(
      id: id,
      title: 'Family',
      host: public,
      messages: [m],
      updated: m.timestamp,
    );
    await source.saveGroupHistory(history);
  });
  test(
    'v2 payload with groups round trips encrypted file and merges without pending sends',
    () async {
      final data = await source.exportBackup();
      expect(data.toJson()['version'], 2);
      final codec = BackupCodec(
        deriveKey: (password, salt) async => Uint8List.fromList(
          (await Sha256().hash([...utf8.encode(password), ...salt])).bytes,
        ),
      );
      final file = await codec.encrypt(data, 'test password for backups');
      expect(
        utf8.decode(file, allowMalformed: true),
        isNot(contains('Group secret')),
      );
      final decoded = await codec.decrypt(file, 'test password for backups');
      final identity = await destination.identity.extractPublicKey();
      final merged = await destination.importBackup(decoded);
      expect(merged.newChats, 1);
      expect(merged.newMessages, 1);
      final copy = (await destination.groupHistories()).single;
      expect(copy.messages.single.text, history.messages.single.text);
      expect(copy.messages.single.receipts.values, everyElement('unconfirmed'));
      expect(
        (await destination.identity.extractPublicKey()).bytes,
        identity.bytes,
      );
      final second = await destination.importBackup(decoded);
      expect(second.newChats, 0);
      expect(second.newMessages, 0);
      expect(second.duplicates, 1);
    },
  );
  test(
    'old v1 backups still parse; signatures and group references are validated before import',
    () async {
      final old = await destination.exportBackup();
      expect(old.toJson()['version'], 1);
      expect((await BackupData.parse(old.toJson())).groups, isEmpty);
      final bad = (await source.exportBackup()).toJson();
      final g = (bad['groups'] as List).single as Map;
      final message = (g['messages'] as List).single as Map;
      (message['envelope'] as Map)['text'] = 'tampered';
      await expectLater(BackupData.parse(bad), throwsFormatException);
      expect(await destination.groupHistories(), isEmpty);
      await expectLater(
        BackupData.parse({...old.toJson(), 'groups': []}),
        throwsFormatException,
      );
    },
  );
  test(
    'existing group records and read state win; new signed records merge',
    () async {
      final public = history.host;
      final newer = await GroupText.create(
        source.identity,
        'Source',
        group: history.id,
        host: public,
        epoch: randomId(),
        view: 1,
        text: 'second',
        targets: [await identityId(public)],
      );
      await destination.saveGroupHistory(
        history.copy(
          messages: [
            history.messages.single.copy(
              read: true,
              receipts: {await identityId(public): 'received'},
            ),
          ],
        ),
      );
      await source.saveGroupHistory(
        history.copy(messages: [...history.messages, newer]),
      );
      final merged = await destination.importBackup(
        await source.exportBackup(),
      );
      expect(merged.newChats, 0);
      expect(merged.newMessages, 1);
      expect(merged.duplicates, 1);
      final copy = (await destination.groupHistories()).single;
      expect(copy.messages.first.read, true);
      expect(copy.messages.first.receipts.values, everyElement('received'));
      expect(copy.messages.last.text, 'second');
    },
  );
  test(
    'identity transfer requires no group history and transfers host identity to an empty phone',
    () async {
      await destination.saveGroupHistory(history);
      await expectLater(
        destination.importBackup(
          await source.exportBackup(),
          moveIdentity: true,
        ),
        throwsFormatException,
      );
      await destination.clearHistory();
      await destination.importBackup(
        await source.exportBackup(),
        moveIdentity: true,
      );
      expect(
        base64Encode((await destination.identity.extractPublicKey()).bytes),
        history.host,
      );
      expect((await destination.groupHistories()).single.id, history.id);
    },
  );
}
