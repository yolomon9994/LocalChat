import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/chat_backup.dart';
import 'package:local_chat/core/chat_image.dart';
import 'package:local_chat/core/models.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'image_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'v3 encrypted backup restores images, deduplicates and retains destination identity',
    () async {
      final source = DemoStore(), destination = DemoStore();
      await source.open();
      await destination.open();
      await source.savePeer('peer', 'Peer');
      final bytes = await testImage();
      final message = ChatMessage(
        id: 'image-message',
        peerId: 'peer',
        text: 'Image',
        timestamp: 1,
        outgoing: true,
        status: 'sending',
        image: await ChatImage.fromBytes(bytes),
      );
      await source.saveImageMessage(message, bytes);
      final data = await source.exportBackup();
      expect(data.toJson()['version'], 3);
      final codec = BackupCodec(
        deriveKey: (password, salt) async => Uint8List.fromList(
          (await Sha256().hash([...utf8.encode(password), ...salt])).bytes,
        ),
      );
      final file = await codec.encrypt(data, 'test password for image backups');
      expect(
        utf8.decode(file, allowMalformed: true),
        isNot(contains(base64Encode(bytes))),
      );
      final decoded = await codec.decrypt(
        file,
        'test password for image backups',
      );
      final identity = (await destination.identity.extractPublicKey()).bytes;
      expect((await destination.importBackup(decoded)).newMessages, 1);
      final restored = (await destination.messages('peer')).single;
      expect(restored.status, 'unconfirmed');
      expect(await destination.imageBytes(restored), bytes);
      expect((await destination.importBackup(decoded)).duplicates, 1);
      expect((await destination.identity.extractPublicKey()).bytes, identity);
      await destination.deleteConversation('peer');
      await expectLater(
        destination.imageBytes(restored),
        throwsFormatException,
      );
    },
  );
  test('backup rejects bad image hash and old-version image fields', () async {
    final source = DemoStore();
    await source.open();
    await source.savePeer('peer', 'Peer');
    final bytes = await testImage();
    await source.saveImageMessage(
      ChatMessage(
        id: 'image',
        peerId: 'peer',
        text: 'Image',
        timestamp: 1,
        outgoing: false,
        status: 'received',
        image: await ChatImage.fromBytes(bytes),
      ),
      bytes,
    );
    final data = await source.exportBackup();
    final bad = jsonDecode(jsonEncode(data.toJson())) as Map;
    ((bad['messages'] as List).single['image'] as Map)['digest'] = '0' * 64;
    await expectLater(BackupData.parse(bad), throwsFormatException);
    final older = data.toJson()..['version'] = 1;
    await expectLater(BackupData.parse(older), throwsFormatException);
    final other = DemoStore();
    await other.open();
    expect((await other.exportBackup()).toJson()['version'], 1);
  });
}
