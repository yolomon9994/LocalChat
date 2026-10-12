import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/chat_backup.dart';
import 'package:local_chat/core/group_models.dart';
import 'package:local_chat/core/chat_file.dart';
import 'package:local_chat/core/models.dart';
import 'package:local_chat/core/secure_session.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'image_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DemoStore source, destination;
  late GroupHistory history;
  setUp(() async {
    source = DemoStore();
    destination = DemoStore();
    await source.open();
    await destination.open();
    final public = base64Encode(
          (await source.identity.extractPublicKey()).bytes,
        ),
        id = randomId();
    final image = await GroupText.create(
      source.identity,
      'Photographer',
      group: id,
      host: public,
      epoch: randomId(),
      view: 1,
      text: 'Image',
      targets: [await identityId(public)],
      imageBytes: await testImage(),
    );
    history = GroupHistory(
      id: id,
      title: 'Pictures',
      host: public,
      messages: [image],
      updated: 1,
    );
    await source.saveGroupHistory(history);
  });
  test(
    'v5 encrypted backup restores group images, signatures, duplicates and destination identity',
    () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      await source.savePeer('peer', 'Peer');
      await source.saveFileMessage(
        ChatMessage(
          id: 'file',
          peerId: 'peer',
          text: 'File',
          timestamp: 1,
          outgoing: false,
          status: 'received',
          file: await ChatFile.fromBytes('file.bin', bytes),
        ),
        bytes,
      );
      final data = await source.exportBackup();
      expect(data.toJson()['version'], 5);
      final codec = BackupCodec(
        deriveKey: (password, salt) async => Uint8List.fromList(
          (await Sha256().hash([...utf8.encode(password), ...salt])).bytes,
        ),
      );
      final file = await codec.encrypt(data, 'test password for group images');
      expect(
        utf8.decode(file, allowMalformed: true),
        isNot(contains(base64Encode(history.messages.single.imageBytes!))),
      );
      final identity = (await destination.identity.extractPublicKey()).bytes;
      final decoded = await codec.decrypt(
        file,
        'test password for group images',
      );
      expect((await destination.importBackup(decoded)).newMessages, 2);
      final restored =
          (await destination.groupHistories()).single.messages.single;
      expect(restored.imageBytes, history.messages.single.imageBytes);
      expect(restored.receipts.values, everyElement('unconfirmed'));
      expect((await destination.importBackup(decoded)).duplicates, 2);
      expect((await destination.identity.extractPublicKey()).bytes, identity);
      expect(
        await destination.fileBytes(
          (await destination.messages('peer')).single,
        ),
        bytes,
      );
      await destination.deleteGroupHistory(history.id);
      expect(await destination.groupHistories(), isEmpty);
    },
  );
  test(
    'old payload versions cannot contain group images; data and metadata tampering fail before import',
    () async {
      final data = (await source.exportBackup()).toJson();
      for (final version in [2, 3, 4]) {
        await expectLater(
          BackupData.parse({...data, 'version': version}),
          throwsFormatException,
        );
      }
      final corrupt = jsonDecode(jsonEncode(data)) as Map;
      final m =
          ((corrupt['groups'] as List).single['messages'] as List).single
              as Map;
      final bytes = base64Decode(m['imageData'] as String)..[40] ^= 1;
      m['imageData'] = base64Encode(bytes);
      await expectLater(BackupData.parse(corrupt), throwsFormatException);
      expect(await destination.groupHistories(), isEmpty);
    },
  );
  test(
    'signed image metadata rejects modification, text-type confusion and missing complete bytes',
    () async {
      final raw =
          jsonDecode(jsonEncode(history.messages.single.toJson())) as Map;
      ((raw['envelope'] as Map)['image'] as Map)['width'] = 1;
      await expectLater(GroupText.parse(raw), throwsFormatException);
      final missing = history.messages.single.toJson()..remove('imageData');
      await expectLater(GroupText.parse(missing), throwsFormatException);
      expect(
        (await GroupText.parse(missing, requireImageData: false)).image,
        isNotNull,
      );
      final confusion =
          jsonDecode(jsonEncode(history.messages.single.toJson())) as Map;
      (confusion['envelope'] as Map).remove('image');
      confusion.remove('imageData');
      await expectLater(GroupText.parse(confusion), throwsFormatException);
    },
  );
}
