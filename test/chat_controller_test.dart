import 'dart:async';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/local_store.dart';
import 'package:local_chat/core/models.dart';
import 'package:local_chat/services/chat_controller.dart';
import 'package:local_chat/services/transport.dart';

class MemoryStore extends LocalStore {
  final saved = <String, ChatMessage>{};
  final people = <String, Conversation>{};
  final draftText = <String, String>{};
  @override
  Future<String> draft(String peer) async => draftText[peer] ?? '';
  @override
  Future<void> saveDraft(String peer, String text) async =>
      draftText[peer] = text;
  @override
  Future<void> open() async {
    identity = await Ed25519().newKeyPair();
  }

  @override
  Future<List<Conversation>> conversations() async => people.values.toList();
  @override
  Future<List<ChatMessage>> messages(String peer) async =>
      saved.values.where((m) => m.peerId == peer).toList();
  @override
  Future<void> savePeer(String id, String name) async {
    people[id] = Conversation(id, name, 0);
  }

  @override
  Future<void> saveMessage(ChatMessage message) async {
    saved.putIfAbsent(message.id, () => message);
  }

  @override
  Future<void> markRead(String peer) async {}

  @override
  Future<void> setStatus(String id, String peer, String status) async {
    final m = saved[id];
    if (m != null && m.peerId == peer && m.outgoing) {
      saved[id] = ChatMessage(
        id: id,
        peerId: peer,
        text: m.text,
        timestamp: m.timestamp,
        outgoing: true,
        status: status,
      );
    }
  }

  @override
  Future<void> clearHistory() async {
    saved.clear();
    people.clear();
    draftText.clear();
  }
}

class LinkedTransport implements Transport {
  final bus = StreamController<Map<String, dynamic>>.broadcast();
  late LinkedTransport other;
  bool dropAcks = false;
  bool failSend = false;
  Completer<void>? sendGate;
  final sent = <String>[];
  @override
  Stream<Map<String, dynamic>> get events => bus.stream;
  @override
  Future<void> start(String name) async {}
  @override
  Future<void> scan() async {}
  @override
  Future<void> connect(String address) async {
    bus.add({'type': 'connected'});
    other.bus.add({'type': 'connected'});
  }

  @override
  Future<void> send(String frame) async {
    await sendGate?.future;
    if (failSend) throw StateError('Socket write failed');
    sent.add(frame);
    if (!dropAcks) other.bus.add({'type': 'frame', 'frame': frame});
  }

  @override
  Future<void> disconnect() async {
    bus.add({'type': 'disconnected'});
    other.bus.add({'type': 'disconnected'});
  }

  @override
  Future<void> stop() async {}
}

Future<void> settle() async {
  // Drain async cryptography, database and event queues, with a bounded wait.
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  late ChatController a;
  late ChatController b;
  late LinkedTransport ta;
  late LinkedTransport tb;
  setUp(() async {
    ta = LinkedTransport();
    tb = LinkedTransport();
    ta.other = tb;
    tb.other = ta;
    a = ChatController(ta, MemoryStore());
    b = ChatController(tb, MemoryStore());
    await a.initialize();
    await b.initialize();
    await a.start();
    await b.start();
    await a.connect(const Peer('B', 'Bob'));
    await settle();
  });
  tearDown(() async {
    a.dispose();
    b.dispose();
    await ta.bus.close();
    await tb.bus.close();
  });
  test(
    'Sending is blocked until BOTH peers explicitly compare codes',
    () async {
      expect(a.code, b.code);
      expect(a.code, isNotNull);
      await a.sendText('blocked');
      expect(a.messages, isEmpty);
      a.dismissError();
      await a.confirmCode();
      await settle();
      expect(a.canSend, isFalse);
      expect(b.canSend, isFalse);
      await b.confirmCode();
      await settle();
      expect(a.canSend, isTrue);
      expect(b.canSend, isTrue);
      final peer = a.selectedPeer!;
      await a.drafts.load(peer);
      a.drafts.setText(peer, 'Hello offline 👋');
      expect(await a.sendText('Hello offline 👋'), isTrue);
      expect(a.drafts.textFor(peer), '');
      expect(await a.store.draft(peer), '');
      await settle();
      expect(a.messages.single.status, 'delivered');
      expect(b.messages.single.text, 'Hello offline 👋');
      expect(b.messages.single.outgoing, isFalse);
      expect(ta.sent.join(), isNot(contains('Hello offline')));
    },
  );
  test(
    'Loss of connection preserves unconfirmed outgoing message and clears verification',
    () async {
      await a.confirmCode();
      await b.confirmCode();
      await settle();
      tb.dropAcks = true;
      await a.sendText('Maybe delivered');
      await settle();
      expect(a.messages.single.status, 'sending');
      await a.disconnect();
      await settle();
      expect(a.messages.single.status, 'unconfirmed');
      expect(a.canSend, isFalse);
      expect(b.ready, isFalse);
    },
  );
  test('Socket send failure fails closed and preserves message', () async {
    await a.confirmCode();
    await b.confirmCode();
    await settle();
    ta.failSend = true;
    final peer = a.selectedPeer!;
    await a.drafts.load(peer);
    a.drafts.setText(peer, 'Keep this');
    expect(await a.sendText('Keep this'), isFalse);
    expect(a.drafts.textFor(peer), 'Keep this');
    expect(await a.store.draft(peer), 'Keep this');
    await settle();
    expect(a.messages.single.status, 'unconfirmed');
    expect(a.ready, isFalse);
    expect(a.error, contains('Socket write failed'));
  });
  test(
    'Successful send preserves newer edits made while the write is pending',
    () async {
      await a.confirmCode();
      await b.confirmCode();
      await settle();
      final peer = a.selectedPeer!;
      await a.drafts.load(peer);
      a.drafts.setText(peer, 'First draft');
      await a.drafts.settled;
      ta.sendGate = Completer<void>();
      final send = a.sendText('First draft');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      a.drafts.setText(peer, 'New edit');
      a.drafts.setText(
        peer,
        'First draft',
      ); // Same text, a new editing revision.
      ta.sendGate!.complete();
      expect(await send, isTrue);
      await settle();
      await a.drafts.settled;
      expect(a.drafts.textFor(peer), 'First draft');
      expect(await a.store.draft(peer), 'First draft');
    },
  );

  test(
    'A queued selection change prevents sending a draft to the wrong peer',
    () async {
      await a.confirmCode();
      await b.confirmCode();
      await settle();
      final peer = a.selectedPeer!;
      await a.drafts.load(peer);
      a.drafts.setText(peer, 'Only for this peer');
      final opening = a.viewHistory(
        const Conversation('another', 'Another', 0),
      );
      final send = a.sendText('Only for this peer');
      await opening;
      expect(await send, isFalse);
      expect(a.drafts.textFor(peer), 'Only for this peer');
      expect((a.store as MemoryStore).saved, isEmpty);
    },
  );

  test('Malformed wire input closes the connection', () async {
    ta.bus.add({'type': 'frame', 'frame': '{broken json'});
    await settle();
    expect(a.ready, isFalse);
    expect(a.connectedPeer, isNull);
    expect(a.error, contains('Security check failed'));
  });
  test(
    'New text recreates a conversation after history is cleared during a session',
    () async {
      await a.confirmCode();
      await b.confirmCode();
      await settle();
      await a.clearHistory();
      expect(a.conversations, isEmpty);
      await a.sendText('A new start');
      await settle();
      expect(a.conversations.length, 1);
      expect(a.messages.single.text, 'A new start');
      expect(a.messages.single.status, 'delivered');
    },
  );
  test(
    'UTF-8 byte limit rejects oversized text and a corrected retry clears the error',
    () async {
      await a.confirmCode();
      await b.confirmCode();
      await settle();
      final peer = a.selectedPeer!;
      await a.drafts.load(peer);
      a.drafts.setText(peer, '界' * 1400);
      expect(await a.sendText('界' * 1400), isFalse);
      expect(a.drafts.textFor(peer), '界' * 1400);
      expect(a.error, contains('4096'));
      expect(a.messages, isEmpty);
      a.drafts.setText(peer, 'Short retry');
      expect(await a.sendText('Short retry'), isTrue);
      expect(a.drafts.textFor(peer), '');
      await settle();
      expect(a.error, isNull);
      expect(a.messages.single.status, 'delivered');
    },
  );
  test(
    'Reconnection requires fresh verification and restores conversation history',
    () async {
      await a.confirmCode();
      await b.confirmCode();
      await settle();
      await a.sendText('Saved');
      await settle();
      final code = a.code;
      await a.disconnect();
      await settle();
      await a.connect(const Peer('B', 'Bob'));
      await settle();
      expect(a.messages.single.text, 'Saved');
      expect(a.code, isNot(code));
      expect(a.canSend, isFalse);
      expect(b.canSend, isFalse);
    },
  );
}
