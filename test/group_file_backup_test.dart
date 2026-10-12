import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/chat_backup.dart';
import 'package:local_chat/core/chat_file.dart';
import 'package:local_chat/core/chat_image.dart';
import 'package:local_chat/core/group_models.dart';
import 'package:local_chat/core/models.dart';
import 'package:local_chat/core/secure_session.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'image_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DemoStore source, destination;
  late GroupHistory history;
  late Uint8List bytes;
  setUp(() async {
    source = DemoStore();
    destination = DemoStore();
    await source.open();
    await destination.open();
    bytes = Uint8List.fromList(List.generate(40000, (i) => i % 251));
    final public = base64Encode(
          (await source.identity.extractPublicKey()).bytes,
        ),
        id = randomId();
    final m = await GroupText.create(
      source.identity,
      'File author',
      group: id,
      host: public,
      epoch: randomId(),
      view: 1,
      text: 'File',
      targets: [await identityId(public)],
      fileBytes: bytes,
      fileName: '../report?.pdf',
    );
    history = GroupHistory(
      id: id,
      title: 'Documents',
      host: public,
      messages: [m],
      updated: 1,
    );
    await source.saveGroupHistory(history);
  });
  test(
    'v6 mixed encrypted archive retains files, images, signatures, identity and duplicate read state',
    () async {
      final png = await testImage(), m = history.messages.single;
      final image = await GroupText.create(
        source.identity,
        'Image author',
        group: history.id,
        host: history.host,
        epoch: m.envelope['epoch'] as String,
        view: 1,
        text: 'Image',
        targets: m.targets,
        imageBytes: png,
      );
      await source.saveGroupHistory(history.copy(messages: [m, image]));
      await source.savePeer('peer', 'Peer');
      await source.saveImageMessage(
        ChatMessage(
          id: 'image',
          peerId: 'peer',
          text: 'Image',
          timestamp: 2,
          outgoing: false,
          status: 'received',
          image: await ChatImage.fromBytes(png),
        ),
        png,
      );
      await source.saveFileMessage(
        ChatMessage(
          id: 'file',
          peerId: 'peer',
          text: 'File',
          timestamp: 3,
          outgoing: false,
          status: 'received',
          file: await ChatFile.fromBytes('direct.bin', bytes),
        ),
        bytes,
      );
      final data = await source.exportBackup();
      expect(data.toJson()['version'], 6);
      final codec = BackupCodec(
        deriveKey: (password, salt) async => Uint8List.fromList(
          (await Sha256().hash([...utf8.encode(password), ...salt])).bytes,
        ),
      );
      final encoded = await codec.encrypt(data, 'group file backup password');
      expect(
        utf8.decode(encoded, allowMalformed: true),
        isNot(contains(m.file!.name)),
      );
      final identity = (await destination.identity.extractPublicKey()).bytes;
      final decoded = await codec.decrypt(
        encoded,
        'group file backup password',
      );
      expect((await destination.importBackup(decoded)).newMessages, 4);
      var restored = (await destination.groupHistories()).single;
      expect(restored.messages.first.fileBytes, bytes);
      expect(restored.messages.last.imageBytes, png);
      expect(
        restored.messages.first.envelope['signature'],
        m.envelope['signature'],
      );
      expect(
        restored.messages.first.receipts.values,
        everyElement('unconfirmed'),
      );
      await destination.saveGroupHistory(
        restored.copy(
          messages: restored.messages.map((m) => m.copy(read: true)).toList(),
        ),
      );
      expect((await destination.importBackup(decoded)).duplicates, 4);
      restored = (await destination.groupHistories()).single;
      expect(restored.messages.every((m) => m.read), isTrue);
      expect((await destination.identity.extractPublicKey()).bytes, identity);
      expect(
        await destination.fileBytes(
          (await destination.messages(
            'peer',
          )).singleWhere((m) => m.file != null),
        ),
        bytes,
      );
    },
  );
  test(
    'versions before v6 cannot contain group files and corrupted bytes reject before import',
    () async {
      final data = (await source.exportBackup()).toJson();
      for (final version in [2, 3, 4, 5]) {
        await expectLater(
          BackupData.parse({...data, 'version': version}),
          throwsFormatException,
        );
      }
      final corrupt = jsonDecode(jsonEncode(data)) as Map;
      final m =
          ((corrupt['groups'] as List).single['messages'] as List).single
              as Map;
      final damaged = base64Decode(m['fileData'] as String)..[20] ^= 1;
      m['fileData'] = base64Encode(damaged);
      await expectLater(BackupData.parse(corrupt), throwsFormatException);
      expect(await destination.groupHistories(), isEmpty);
    },
  );
  test(
    'filename signing, mixed attachment types and missing bytes are validated',
    () async {
      final m = history.messages.single;
      final renamed = jsonDecode(jsonEncode(m.toJson())) as Map;
      ((renamed['envelope'] as Map)['file'] as Map)['name'] = 'renamed.pdf';
      await expectLater(GroupText.parse(renamed), throwsFormatException);
      final missing = m.toJson()..remove('fileData');
      await expectLater(GroupText.parse(missing), throwsFormatException);
      expect(
        (await GroupText.parse(missing, requireFileData: false)).file,
        isNotNull,
      );
      final mixed = jsonDecode(jsonEncode(m.toJson())) as Map;
      (mixed['envelope'] as Map)['image'] = (await ChatImage.fromBytes(
        await testImage(),
      )).toJson();
      await expectLater(GroupText.parse(mixed), throwsFormatException);
      final traversal = jsonDecode(jsonEncode(m.toJson())) as Map;
      ((traversal['envelope'] as Map)['file'] as Map)['name'] =
          '../../escape.bin';
      await expectLater(GroupText.parse(traversal), throwsFormatException);
      final confusion = jsonDecode(jsonEncode(m.toJson())) as Map;
      (confusion['envelope'] as Map).remove('file');
      confusion.remove('fileData');
      await expectLater(GroupText.parse(confusion), throwsFormatException);
    },
  );
  test(
    'combined group attachment cap rejects oversized history without importing partial records',
    () async {
      final m = history.messages.single;
      final large = Uint8List(6 * 1024 * 1024);
      final messages = <GroupText>[];
      for (var i = 0; i < 3; i++) {
        messages.add(
          await GroupText.create(
            source.identity,
            'File author',
            group: history.id,
            host: history.host,
            epoch: m.envelope['epoch'] as String,
            view: 1,
            text: 'File',
            targets: m.targets,
            fileName: '$i.bin',
            fileBytes: large,
          ),
        );
      }
      await expectLater(
        GroupHistory.parse(history.copy(messages: messages).toJson()),
        throwsFormatException,
      );
      expect(await destination.groupHistories(), isEmpty);
    },
  );
}
