import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/chat_image.dart';
import 'package:local_chat/core/models.dart';
import 'package:local_chat/core/secure_session.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'package:local_chat/demo/demo_transport.dart';
import 'package:local_chat/services/chat_controller.dart';
import 'package:local_chat/services/image_transfers.dart';
import 'package:local_chat/services/image_files_base.dart';
import 'chat_controller_test.dart' show LinkedTransport, settle;
import 'image_test_support.dart';

class ImageStore extends DemoStore {
  bool failImages = false;
  @override
  Future<bool> saveImageMessage(ChatMessage message, Uint8List bytes) async {
    if (failImages) throw StateError('Image persistence failed');
    return super.saveImageMessage(message, bytes);
  }
}

class GatedPicker implements ImageFiles {
  final result = Completer<Uint8List?>();
  @override
  Future<Uint8List?> pick() => result.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ChatController a, b;
  late LinkedTransport ta, tb;
  late ImageStore sa, sb;
  late GatedPicker picker;
  late Uint8List bytes;
  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(done(), isTrue);
  }

  setUp(() async {
    bytes = await testImage();
    ta = LinkedTransport();
    tb = LinkedTransport();
    ta.other = tb;
    tb.other = ta;
    sa = ImageStore();
    sb = ImageStore();
    picker = GatedPicker();
    a = ChatController(
      ta,
      sa,
      imageFiles: picker,
      imageTimeout: const Duration(milliseconds: 400),
    );
    b = ChatController(tb, sb, imageTimeout: const Duration(milliseconds: 400));
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
      expect(a.canSendImage, isTrue);
      await a.drafts.load(a.selectedPeer!);
      a.drafts.setText(a.selectedPeer!, 'Keep my text draft');
      expect(await a.sendImage(bytes), isTrue);
      await a.sendText('Text alongside the image');
      await until(
        () => a.messages.any((m) => m.image != null && m.status == 'delivered'),
      );
      await until(
        () =>
            a.messages.length == 2 &&
            a.messages.every((m) => m.status == 'delivered'),
      );
      await until(() => b.messages.length == 2);
      final incoming = b.messages.singleWhere((m) => m.image != null);
      expect(await sb.imageBytes(incoming), bytes);
      expect(a.drafts.textFor(a.selectedPeer!), 'Keep my text draft');
      expect(
        ta.sent.every((frame) => utf8.encode(frame).length <= 65536),
        isTrue,
      );
      expect(ta.sent.where((frame) => frame.contains('image/png')), isEmpty);
      expect(b.conversations.single.unreadCount, 2);
    },
  );
  test(
    'lost acceptance times out, leaves unconfirmed image and does not resume',
    () async {
      ta.dropAcks = true;
      await a.sendImage(bytes);
      await until(() => a.images.progress.isEmpty);
      expect(a.messages.single.status, 'unconfirmed');
      expect(b.messages, isEmpty);
      ta.dropAcks = false;
      await settle();
      expect(b.messages, isEmpty);
    },
  );
  test(
    'explicit retry reuses ID and receiver deduplicates a previously stored image',
    () async {
      await a.sendImage(bytes);
      await until(() => a.messages.single.status == 'delivered');
      final original = a.messages.single;
      await sa.setStatus(original.id, original.peerId, 'unconfirmed');
      final retry = (await sa.messages(original.peerId)).single;
      await a.sendImage(bytes, retry: retry);
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
      await a.sendImage(bytes);
      await settle();
      expect(b.images.progress, isNotEmpty);
      a.setAppAccess(false);
      await until(() => a.images.progress.isEmpty && b.images.progress.isEmpty);
      expect(a.messages.single.status, 'unconfirmed');
      expect(b.messages, isEmpty);
      a.setAppAccess(true);
      await settle();
      expect(b.messages, isEmpty);
    },
  );
  test(
    'locked recipient declines image, sender cannot attach offline or before verification',
    () async {
      b.setAppAccess(false);
      await a.sendImage(bytes);
      await until(() => a.images.progress.isEmpty);
      expect(a.messages.single.status, 'unconfirmed');
      expect(b.messages, isEmpty);
      await a.disconnect();
      expect(await a.sendImage(bytes), isFalse);
      await a.connect(const Peer('B', 'Bob'));
      await settle();
      expect(a.canSendImage, isFalse);
    },
  );
  test(
    'receiver storage failure never delivers or retains partial image',
    () async {
      sb.failImages = true;
      await a.sendImage(bytes);
      await until(() => !a.ready);
      expect(a.messages.single.status, 'unconfirmed');
      expect(b.messages, isEmpty);
      expect(b.images.progress, isEmpty);
    },
  );
  test(
    'picker return while locked retains sealed selection, waits for unlock and explicit send',
    () async {
      final picking = a.pickImage();
      a.setAppForeground(false);
      a.setAppAccess(false);
      picker.result.complete(bytes);
      await picking;
      expect(a.pendingImagePeer, a.selectedPeer);
      expect(await a.reviewPendingImage(), isNull);
      expect(b.messages, isEmpty);
      a.setAppAccess(true);
      a.setAppForeground(true);
      await settle();
      final prepared = await a.reviewPendingImage();
      expect(prepared, isNotNull);
      expect(b.messages, isEmpty);
      await a.sendImage(prepared!);
      await until(() => a.messages.single.status == 'delivered');
      expect(a.pendingImagePeer, isNull);
    },
  );
  test(
    'invalid chunk order and forged contents are rejected without persistence',
    () async {
      final store = DemoStore();
      await store.open();
      await store.savePeer('peer', 'Peer');
      final sent = <Map<String, dynamic>>[];
      final receiver = ImageTransfers(
        store: store,
        peer: () => 'peer',
        canAct: () => true,
        send: (payload, _) async => sent.add(payload),
        enqueue: (fn) => fn(),
        changed: () {},
        persisted: (_, _) async {},
      );
      addTearDown(receiver.dispose);
      final metadata = await ChatImage.fromBytes(bytes), id = randomId();
      await receiver.handle({
        'type': 'imageOffer',
        'id': id,
        'timestamp': 1,
        'image': metadata.toJson(),
      });
      await expectLater(
        receiver.handle({
          'type': 'imageChunk',
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
        'type': 'imageOffer',
        'id': second,
        'timestamp': 1,
        'image': metadata.toJson(),
      });
      for (
        var offset = 0, index = 0;
        offset < corrupt.length;
        offset += imageChunkBytes, index++
      ) {
        final end = (offset + imageChunkBytes).clamp(0, corrupt.length);
        await receiver.handle({
          'type': 'imageChunk',
          'id': second,
          'index': index,
          'data': base64Encode(corrupt.sublist(offset, end)),
        });
      }
      await expectLater(
        receiver.handle({'type': 'imageComplete', 'id': second}),
        throwsFormatException,
      );
      expect(await store.messages('peer'), isEmpty);
      expect(
        sent.where((p) => p['type'] == 'imageResult' && p['received'] == true),
        isEmpty,
      );
    },
  );
  test('image bounds reject oversized data and pixel declarations', () async {
    await expectLater(a.sendImage(Uint8List(imageMaxBytes + 1)), completes);
    expect(a.messages, isEmpty);
    expect(b.messages, isEmpty);
    final meta = (await ChatImage.fromBytes(bytes)).toJson()
      ..['width'] = imageMaxDimension + 1;
    expect(() => ChatImage.parse(meta), throwsFormatException);
  });
  test(
    'peer without image capability still supports text and disables images',
    () async {
      final c = ChatController(
        DemoTransport(supportsImages: false),
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
      expect(c.canSendImage, isFalse);
      expect(await c.sendImage(bytes), isFalse);
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
      final picking = a.pickImage();
      await a.deleteConversation(a.selectedPeer!);
      picker.result.complete(bytes);
      await picking;
      expect(a.pendingImagePeer, isNull);
      expect(await sa.conversations(), isEmpty);
    },
  );
}
