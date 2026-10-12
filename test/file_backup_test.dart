import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/chat_backup.dart';
import 'package:local_chat/core/chat_file.dart';
import 'package:local_chat/core/models.dart';
import 'package:local_chat/demo/demo_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'v4 encrypted backup restores files, deduplicates and retains destination identity',
    () async {
      final source = DemoStore(), destination = DemoStore();
      await source.open();
      await destination.open();
      await source.savePeer('peer', 'Peer');
      final bytes = Uint8List.fromList(utf8.encode("Private PDF bytes"));
      final message = ChatMessage(
        id: 'file-message',
        peerId: 'peer',
        text: 'File',
        timestamp: 1,
        outgoing: true,
        status: 'sending',
        file: await ChatFile.fromBytes('report.pdf', bytes),
      );
      await source.saveFileMessage(message, bytes);
      final data = await source.exportBackup();
      expect(data.toJson()['version'], 4);
      final codec = BackupCodec(
        deriveKey: (password, salt) async => Uint8List.fromList(
          (await Sha256().hash([...utf8.encode(password), ...salt])).bytes,
        ),
      );
      final file = await codec.encrypt(data, 'test password for file backups');
      expect(
        utf8.decode(file, allowMalformed: true),
        isNot(contains(base64Encode(bytes))),
      );
      final decoded = await codec.decrypt(
        file,
        'test password for file backups',
      );
      final identity = (await destination.identity.extractPublicKey()).bytes;
      expect((await destination.importBackup(decoded)).newMessages, 1);
      final restored = (await destination.messages('peer')).single;
      expect(restored.status, 'unconfirmed');
      expect(await destination.fileBytes(restored), bytes);
      expect((await destination.importBackup(decoded)).duplicates, 1);
      expect((await destination.identity.extractPublicKey()).bytes, identity);
      await destination.deleteConversation('peer');
      await expectLater(destination.fileBytes(restored), throwsFormatException);
    },
  );
  test('backup rejects bad file hash and old-version file fields', () async {
    final source = DemoStore();
    await source.open();
    await source.savePeer('peer', 'Peer');
    final bytes = Uint8List.fromList(utf8.encode("Private PDF bytes"));
    await source.saveFileMessage(
      ChatMessage(
        id: 'file',
        peerId: 'peer',
        text: 'File',
        timestamp: 1,
        outgoing: false,
        status: 'received',
        file: await ChatFile.fromBytes('report.pdf', bytes),
      ),
      bytes,
    );
    final data = await source.exportBackup();
    final bad = jsonDecode(jsonEncode(data.toJson())) as Map;
    ((bad['messages'] as List).single['file'] as Map)['digest'] = '0' * 64;
    await expectLater(BackupData.parse(bad), throwsFormatException);
    final older = data.toJson()..['version'] = 3;
    await expectLater(BackupData.parse(older), throwsFormatException);
    final other = DemoStore();
    await other.open();
    expect((await other.exportBackup()).toJson()['version'], 1);
  });
}
