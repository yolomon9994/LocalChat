import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/chat_file.dart';
import 'package:local_chat/services/chat_files_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'shortened Unicode filenames remain valid at punctuation boundaries',
    () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      for (final name in [
        '${'a' * 119}.pdf',
        '${'a' * 119} file.txt',
        '${'🙂' * 119}.pdf',
      ]) {
        final file = await ChatFile.fromBytes(name, bytes);
        expect(file.name.runes.length, lessThanOrEqualTo(120));
        expect(ChatFile.safeName(file.name), file.name);
        expect(ChatFile.parse(file.toJson()).name, file.name);
        await file.verify(bytes);
      }
    },
  );
  test(
    'file metadata rejects unsafe names, invalid hashes and size bounds',
    () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final file = await ChatFile.fromBytes('../report\u202e.pdf', bytes);
      expect(file.name, '_report_.pdf');
      expect(ChatFile.safeName('..'), 'attachment.bin');
      expect(ChatFile.safeName('x' * 130).length, 120);
      await file.verify(bytes);
      await expectLater(
        file.verify(Uint8List.fromList([1, 2, 4])),
        throwsFormatException,
      );
      for (final change in [
        {'name': '../a.pdf'},
        {'name': 'a\nb.pdf'},
        {'length': fileMaxBytes + 1},
        {'length': 0},
        {'digest': 'x' * 64},
        {'mime': 'text/html'},
      ]) {
        expect(
          () => ChatFile.parse({...file.toJson(), ...change}),
          throwsFormatException,
        );
      }
      await expectLater(
        ChatFile.fromBytes('empty', Uint8List(0)),
        throwsFormatException,
      );
    },
  );
  test(
    'Android file channel selects names and bytes, handles cancellation and saves explicitly',
    () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final calls = <MethodCall>[];
      var cancel = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AndroidChatFiles.channel, (call) async {
            calls.add(call);
            if (cancel) return call.method == 'save' ? false : null;
            return call.method == 'save'
                ? true
                : {'name': '../report.pdf', 'bytes': bytes};
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(AndroidChatFiles.channel, null),
      );
      const files = AndroidChatFiles();
      final chosen = await files.pick();
      expect(chosen!.name, '_report.pdf');
      expect(chosen.bytes, bytes);
      expect(await files.save(bytes, '../report.pdf'), isTrue);
      expect((calls.last.arguments as Map)['name'], '_report.pdf');
      expect((calls.last.arguments as Map)['bytes'], bytes);
      cancel = true;
      expect(await files.pick(), isNull);
      expect(await files.save(bytes, 'report.pdf'), isFalse);
      await expectLater(
        files.save(Uint8List(fileMaxBytes + 1), 'large'),
        throwsFormatException,
      );
    },
  );
}
