import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/chat_file.dart';
import 'package:local_chat/core/chat_image.dart' show imageChunkBytes;
import 'package:local_chat/core/models.dart';
import 'package:local_chat/core/secure_session.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'package:local_chat/demo/demo_transport.dart';
import 'package:local_chat/services/chat_controller.dart';
import 'package:local_chat/services/file_transfers.dart';
import 'package:local_chat/services/chat_files_base.dart';
import 'chat_controller_test.dart' show LinkedTransport, settle;

class FileStore extends DemoStore {
  bool failFiles = false;
  @override
  Future<bool> saveFileMessage(ChatMessage message, Uint8List bytes) async {
    if (failFiles) throw StateError('File persistence failed');
    return super.saveFileMessage(message, bytes);
  }
}

class GatedPicker implements ChatFiles {
  final result = Completer<SelectedFile?>();
  final saved = <SelectedFile>[];
  bool saveResult = true, failSave = false;
  @override
  Future<bool> save(Uint8List bytes, String name) async {
    if (failSave) throw StateError("test save failure");
    saved.add(SelectedFile(name, Uint8List.fromList(bytes)));
    return saveResult;
  }

  @override
  Future<SelectedFile?> pick() => result.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ChatController a, b;
  late LinkedTransport ta, tb;
  late FileStore sa, sb;
  late GatedPicker picker;
  late Uint8List bytes;
  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(done(), isTrue);
  }

  setUp(() async {
    bytes = Uint8List.fromList(List.generate(30000, (i) => i % 256));
    ta = LinkedTransport();
    tb = LinkedTransport();
    ta.other = tb;
    tb.other = ta;
    sa = FileStore();
    sb = FileStore();
    picker = GatedPicker();
    a = ChatController(
      ta,
      sa,
      chatFiles: picker,
      fileTimeout: const Duration(milliseconds: 400),
    );
    b = ChatController(tb, sb, fileTimeout: const Duration(milliseconds: 400));
    await a.initialize();
    await b.initialize();
    await a.connect(const Peer('B', 'Bob'));
    await settle();
    await a.confirmCode();
    await b.confirmCode();
    await settle();
  });
  tearDown(() async {
    a.dispose();
    b.dispose();
    await ta.bus.close();
    await tb.bus.close();
  });
  test(
    'real encrypted chunk transfer persists before receipt, supports text and preserves drafts',
    () async {
      expect(bytes.length, greaterThan(imageChunkBytes));
      expect(a.canSendFile, isTrue);
      await a.drafts.load(a.selectedPeer!);
      a.drafts.setText(a.selectedPeer!, 'Keep my text draft');
      expect(await a.sendFile(SelectedFile('notes.pdf', bytes)), isTrue);
      await a.sendText('Text alongside the file');
      await until(
        () => a.messages.any((m) => m.file != null && m.status == 'delivered'),
      );
      await until(
        () =>
            a.messages.length == 2 &&
            a.messages.every((m) => m.status == 'delivered'),
      );
      await until(() => b.messages.length == 2);
      final incoming = b.messages.singleWhere((m) => m.file != null);
      expect(await sb.fileBytes(incoming), bytes);
      expect(a.drafts.textFor(a.selectedPeer!), 'Keep my text draft');
      expect(
        ta.sent.every((frame) => utf8.encode(frame).length <= 65536),
        isTrue,
      );
      expect(ta.sent.where((frame) => frame.contains('notes.pdf')), isEmpty);
      expect(b.conversations.single.unreadCount, 2);
    },
  );
  test(
    'lost acceptance times out, leaves unconfirmed file and does not resume',
    () async {
      ta.dropAcks = true;
      await a.sendFile(SelectedFile('notes.pdf', bytes));
      await until(() => a.files.progress.isEmpty);
      expect(a.messages.single.status, 'unconfirmed');
      expect(b.messages, isEmpty);
      ta.dropAcks = false;
      await settle();
      expect(b.messages, isEmpty);
    },
  );
  test(
    'explicit retry reuses ID and receiver deduplicates a previously stored file',
    () async {
      await a.sendFile(SelectedFile('notes.pdf', bytes));
      await until(() => a.messages.single.status == 'delivered');
      final original = a.messages.single;
      await sa.setStatus(original.id, original.peerId, 'unconfirmed');
      final retry = (await sa.messages(original.peerId)).single;
      await a.sendFile(SelectedFile('notes.pdf', bytes), retry: retry);
      await until(() => a.messages.single.status == 'delivered');
      expect(b.messages.length, 1);
      expect(b.messages.single.id, original.id);
      expect(b.conversations.single.unreadCount, 1);
    },
  );
  test(
    'locking sender cancels partial transfer without transmitting remaining bytes',
    () async {
      tb.dropAcks = true;
      await a.sendFile(SelectedFile('notes.pdf', bytes));
      // Lock as soon as the receiver is waiting. A fixed drain delay can
      // outlast the deliberately short transfer timeout on a busy test host.
      await until(() => b.files.progress.isNotEmpty);
      expect(b.files.progress, isNotEmpty);
      a.setAppAccess(false);
      await until(() => a.files.progress.isEmpty && b.files.progress.isEmpty);
      expect(a.messages.single.status, 'unconfirmed');
      expect(b.messages, isEmpty);
      a.setAppAccess(true);
      await settle();
      expect(b.messages, isEmpty);
    },
  );
  test(
    'locked recipient declines file, sender cannot attach offline or before verification',
    () async {
      b.setAppAccess(false);
      await a.sendFile(SelectedFile('notes.pdf', bytes));
      await until(() => a.files.progress.isEmpty);
      expect(a.messages.single.status, 'unconfirmed');
      expect(b.messages, isEmpty);
      await a.disconnect();
      expect(await a.sendFile(SelectedFile('notes.pdf', bytes)), isFalse);
      await a.connect(const Peer('B', 'Bob'));
      await settle();
      expect(a.canSendFile, isFalse);
    },
  );
  test(
    'receiver storage failure never delivers or retains partial file',
    () async {
      sb.failFiles = true;
      await a.sendFile(SelectedFile('notes.pdf', bytes));
      await until(() => !a.ready);
      expect(a.messages.single.status, 'unconfirmed');
      expect(b.messages, isEmpty);
      expect(b.files.progress, isEmpty);
    },
  );
  test(
    'picker return while locked retains sealed selection, waits for unlock and explicit send',
    () async {
      final picking = a.pickFile();
      a.setAppForeground(false);
      a.setAppAccess(false);
      picker.result.complete(SelectedFile('notes.pdf', bytes));
      await picking;
      expect(a.pendingFilePeer, a.selectedPeer);
      expect(await a.reviewPendingFile(), isNull);
      expect(b.messages, isEmpty);
      a.setAppAccess(true);
      a.setAppForeground(true);
      await settle();
      final prepared = await a.reviewPendingFile();
      expect(prepared, isNotNull);
      expect(b.messages, isEmpty);
      await a.sendFile(prepared!);
      await until(() => a.messages.single.status == 'delivered');
      expect(a.pendingFilePeer, isNull);
    },
  );
  test(
    'invalid chunk order and forged contents are rejected without persistence',
    () async {
      final store = DemoStore();
      await store.open();
      await store.savePeer('peer', 'Peer');
      final sent = <Map<String, dynamic>>[];
      final receiver = FileTransfers(
        store: store,
        peer: () => 'peer',
        canAct: () => true,
        send: (payload, _) async => sent.add(payload),
        enqueue: (fn) => fn(),
        changed: () {},
        persisted: (_, _) async {},
      );
      addTearDown(receiver.dispose);
      final metadata = await ChatFile.fromBytes('notes.pdf', bytes),
          id = randomId();
      await receiver.handle({
        'type': 'fileOffer',
        'id': id,
        'timestamp': 1,
        'file': metadata.toJson(),
      });
      await expectLater(
        receiver.handle({
          'type': 'fileChunk',
          'id': id,
          'index': 1,
          'data': base64Encode(bytes.sublist(0, imageChunkBytes)),
        }),
        throwsFormatException,
      );
      await receiver.stop();
      final corrupt = Uint8List.fromList(bytes)..[bytes.length - 1] ^= 1;
      final second = randomId();
      await receiver.handle({
        'type': 'fileOffer',
        'id': second,
        'timestamp': 1,
        'file': metadata.toJson(),
      });
      for (
        var offset = 0, index = 0;
        offset < corrupt.length;
        offset += imageChunkBytes, index++
      ) {
        final end = (offset + imageChunkBytes).clamp(0, corrupt.length);
        await receiver.handle({
          'type': 'fileChunk',
          'id': second,
          'index': index,
          'data': base64Encode(corrupt.sublist(offset, end)),
        });
      }
      await expectLater(
        receiver.handle({'type': 'fileComplete', 'id': second}),
        throwsFormatException,
      );
      expect(await store.messages('peer'), isEmpty);
      expect(
        sent.where((p) => p['type'] == 'fileResult' && p['received'] == true),
        isEmpty,
      );
    },
  );
  test('file bounds reject oversized data and metadata declarations', () async {
    await expectLater(
      a.sendFile(SelectedFile('too-big.bin', Uint8List(fileMaxBytes + 1))),
      completes,
    );
    expect(a.messages, isEmpty);
    expect(b.messages, isEmpty);
    final meta = (await ChatFile.fromBytes('notes.pdf', bytes)).toJson()
      ..['length'] = fileMaxBytes + 1;
    expect(() => ChatFile.parse(meta), throwsFormatException);
  });
  test(
    'peer without file capability still supports text and disables files',
    () async {
      final c = ChatController(
        DemoTransport(supportsFiles: false),
        DemoStore(),
      );
      addTearDown(c.dispose);
      await c.initialize();
      await c.start();
      await c.connect(const Peer('demo-ava', 'Ava'));
      await settle();
      await c.confirmCode();
      await settle();
      expect(c.ready, isTrue);
      expect(c.canSendFile, isFalse);
      expect(await c.sendFile(SelectedFile('notes.pdf', bytes)), isFalse);
      expect(await c.sendText('Legacy text still works'), isTrue);
      await settle();
      expect(
        c.messages.any((m) => m.text == 'Legacy text still works'),
        isTrue,
      );
    },
  );
  test(
    'deleting chat while picker is open discards a late selection',
    () async {
      final picking = a.pickFile();
      await a.deleteConversation(a.selectedPeer!);
      picker.result.complete(SelectedFile('notes.pdf', bytes));
      await picking;
      expect(a.pendingFilePeer, isNull);
      expect(await sa.conversations(), isEmpty);
    },
  );
  test(
    'explicit offline export, cancellation, errors and lock gates',
    () async {
      await a.sendFile(SelectedFile('notes.pdf', bytes));
      await until(() => a.messages.single.status == 'delivered');
      final m = a.messages.single;
      await a.disconnect();
      a.setAppAccess(false);
      expect(await a.saveFileToPhone(m), isFalse);
      expect(picker.saved, isEmpty);
      a.setAppAccess(true);
      a.setAppForeground(false);
      expect(await a.saveFileToPhone(m), isFalse);
      a.setAppForeground(true);
      picker.saveResult = false;
      expect(await a.saveFileToPhone(m), isFalse);
      expect(picker.saved.single.bytes, bytes);
      expect(picker.saved.single.name, 'notes.pdf');
      picker.failSave = true;
      expect(await a.saveFileToPhone(m), isFalse);
      expect(a.error, contains('Could not save'));
      picker.failSave = false;
      picker.saveResult = true;
      expect(await a.saveFileToPhone(m), isTrue);
      expect((await sa.messages(m.peerId)).single.status, 'delivered');
    },
  );
  test('backgrounding cancels partial file without automatic resume', () async {
    tb.dropAcks = true;
    await a.sendFile(SelectedFile('notes.pdf', bytes));
    await settle();
    a.setAppForeground(false);
    await until(() => a.files.progress.isEmpty && b.files.progress.isEmpty);
    expect(a.messages.single.status, 'unconfirmed');
    a.setAppForeground(true);
    await settle();
    expect(b.messages, isEmpty);
  });
  test(
    'explicit cancel releases transfer and gates competing attachments',
    () async {
      tb.dropAcks = true;
      await a.sendFile(SelectedFile('notes.pdf', bytes));
      await settle();
      expect(a.canSendImage, isFalse);
      expect(a.canSendFile, isFalse);
      await a.cancelFileTransfers();
      await until(() => a.files.progress.isEmpty && b.files.progress.isEmpty);
      expect(a.messages.single.status, 'unconfirmed');
      expect(b.messages, isEmpty);
      expect(a.canSendImage && a.canSendFile, isTrue);
    },
  );
}
