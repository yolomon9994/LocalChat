import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/models.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'package:local_chat/services/chat_controller.dart';
import 'chat_controller_test.dart' show LinkedTransport, settle;

class OutboxStore extends DemoStore {
  bool failAccept = false, failTransition = false;
  Completer<void>? transitionGate;
  final transitionEntered = Completer<void>();
  @override
  Future<void> saveOutgoingMessage(
    ChatMessage message, {
    bool clearDraft = false,
  }) async {
    if (failAccept) throw StateError('Private storage failure');
    await super.saveOutgoingMessage(message, clearDraft: clearDraft);
  }

  @override
  Future<bool> changeOutgoingStatus(
    String id,
    String peer,
    List<String> from,
    String to,
  ) async {
    if (to == 'sending') {
      if (!transitionEntered.isCompleted) transitionEntered.complete();
      await transitionGate?.future;
      if (failTransition) throw StateError('Private transition failure');
    }
    return super.changeOutgoingStatus(id, peer, from, to);
  }
}

void main() {
  late ChatController a, b;
  late LinkedTransport ta, tb;
  late OutboxStore sa;
  late DemoStore sb;
  Future<void> connect({bool verify = true}) async {
    await a.connect(const Peer('B', 'Bob'));
    await settle();
    if (verify) {
      await a.confirmCode();
      await b.confirmCode();
      await settle();
    }
  }

  setUp(() async {
    ta = LinkedTransport();
    tb = LinkedTransport();
    ta.other = tb;
    tb.other = ta;
    sa = OutboxStore();
    sb = DemoStore();
    a = ChatController(ta, sa);
    b = ChatController(tb, sb);
    await a.initialize();
    await b.initialize();
    await connect();
    await a.disconnect();
    await settle();
  });
  tearDown(() async {
    a.dispose();
    b.dispose();
    await ta.bus.close();
    await tb.bus.close();
  });

  test(
    'Offline acceptance clears only its draft and queues encrypted-protocol-ready text for a known peer',
    () async {
      final peer = a.selectedPeer!;
      await a.drafts.load(peer);
      a.drafts.setText(peer, '  Pending سلام 👋\ntext  ');
      final frames = ta.sent.length;
      expect(
        await a.sendText('  Pending سلام 👋\ntext  ', queueIfOffline: true),
        isTrue,
      );
      expect(a.drafts.textFor(peer), '');
      expect(await sa.draft(peer), '');
      expect(a.messages.single.text, 'Pending سلام 👋\ntext');
      expect(a.messages.single.status, 'queued');
      expect(a.messages.single.id.length, 24);
      expect(a.conversations.single.queuedCount, 1);
      expect(ta.sent.length, frames);
      expect(b.messages, isEmpty);
      a.selectedPeer = 'unknown';
      expect(
        await a.sendText('Cannot trust a name', queueIfOffline: true),
        isFalse,
      );
      expect(await sa.messages('unknown'), isEmpty);
    },
  );

  test(
    'Storage failure and UTF-8 validation preserve drafts and add no message',
    () async {
      final peer = a.selectedPeer!;
      await a.drafts.load(peer);
      a.drafts.setText(peer, 'Keep my draft');
      sa.failAccept = true;
      expect(await a.sendText('Keep my draft', queueIfOffline: true), isFalse);
      expect(a.messages, isEmpty);
      expect(a.drafts.textFor(peer), 'Keep my draft');
      expect(a.error, isNot(contains('Private')));
      sa.failAccept = false;
      a.drafts.setText(peer, '界' * 1400);
      expect(await a.sendText('界' * 1400, queueIfOffline: true), isFalse);
      expect(a.drafts.textFor(peer), '界' * 1400);
      expect(a.messages, isEmpty);
    },
  );

  test(
    'Both confirmations are required before ordered queued delivery; archive and unread choices survive',
    () async {
      await a.setArchived(a.selectedPeer!, true);
      await a.sendText('First queued', queueIfOffline: true);
      await a.sendText('Second queued', queueIfOffline: true);
      await connect(verify: false);
      expect(a.messages.every((m) => m.status == 'queued'), isTrue);
      await a.confirmCode();
      await settle();
      expect(sb.messages(b.selectedPeer!), completion(isEmpty));
      await b.confirmCode();
      await settle();
      expect(b.messages.map((m) => m.text), ['First queued', 'Second queued']);
      expect(a.messages.every((m) => m.status == 'delivered'), isTrue);
      expect(a.conversations.single.archived, isTrue);
      expect(a.conversations.single.queuedCount, 0);
      expect(b.conversations.single.unreadCount, 2);
      expect(ta.sent.join(), isNot(contains('First queued')));
    },
  );

  test(
    'Lost ACK requires explicit retry after reconnect and does not duplicate or mark read twice',
    () async {
      await connect();
      tb.dropAcks = true;
      await a.sendText('Maybe already received');
      await settle();
      expect(b.messages.length, 1);
      final original = a.messages.single;
      await a.disconnect();
      await settle();
      expect(a.messages.single.status, 'unconfirmed');
      tb.dropAcks = false;
      await connect();
      expect(a.messages.single.status, 'unconfirmed');
      expect(b.messages.length, 1);
      expect(await a.retryMessage(a.messages.single), isTrue);
      await settle();
      expect(a.messages.single.status, 'delivered');
      expect(a.messages.single.id, original.id);
      expect(a.messages.single.timestamp, original.timestamp);
      expect(b.messages.length, 1);
      expect(b.conversations.single.unreadCount, 1);
      expect(await a.retryMessage(original), isFalse);
    },
  );

  test('Late authenticated ACK confirms a timeout without resending', () async {
    // Replace the sender before connecting; preserve its local identity/history.
    a.dispose();
    a = ChatController(ta, sa, ackTimeout: const Duration(milliseconds: 100));
    // DemoStore.open normally resets demo identity. The empty store is safe here;
    // a fresh handshake learns it before this test's only message.
    await a.initialize();
    await connect();
    tb.dropAcks = true;
    await a.sendText('Late acknowledgement');
    await settle();
    expect(a.messages.single.status, 'unconfirmed');
    final before = ta.sent.length;
    ta.bus.add({'type': 'frame', 'frame': tb.sent.last});
    await settle();
    expect(a.messages.single.status, 'delivered');
    expect(ta.sent.length, before);
  });

  test(
    'Verified outbox waits while locked/backgrounded and resumes after both gates open',
    () async {
      await a.sendText('Wait for unlock', queueIfOffline: true);
      await connect(verify: false);
      await a.confirmCode();
      a.setAppForeground(false);
      a.setAppAccess(false);
      await b.confirmCode();
      await settle();
      expect(a.ready, isTrue);
      expect(a.messages.single.status, 'queued');
      expect(b.messages, isEmpty);
      a.setAppForeground(true);
      await settle();
      expect(b.messages, isEmpty);
      a.setAppAccess(true);
      await settle();
      expect(a.messages.single.status, 'delivered');
    },
  );

  test(
    'Lock during a durable sending transition restores queued state without a wire send',
    () async {
      await a.sendText('Lock during storage', queueIfOffline: true);
      sa.transitionGate = Completer<void>();
      await connect(verify: false);
      await a.confirmCode();
      await b.confirmCode();
      await sa.transitionEntered.future;
      a.setAppAccess(false);
      sa.transitionGate!.complete();
      await settle();
      expect(a.messages.single.status, 'queued');
      expect(b.messages, isEmpty);
      a.setAppAccess(true);
      await settle();
      expect(a.messages.single.status, 'delivered');
    },
  );

  test(
    'A failed durable sending transition pauses and Resume sends once after storage recovers',
    () async {
      await a.sendText('Storage retry', queueIfOffline: true);
      sa.failTransition = true;
      await connect();
      expect(a.outboxPaused, isTrue);
      expect(a.messages.single.status, 'queued');
      expect(b.messages, isEmpty);
      expect(a.error, isNot(contains('Private')));
      sa.failTransition = false;
      await a.resumeOutbox();
      await settle();
      expect(a.messages.single.status, 'delivered');
      expect(b.messages.length, 1);
    },
  );

  test(
    'Cancel removes only unsent outgoing records; clearing history cannot resurrect the queue',
    () async {
      await a.sendText('Cancel me', queueIfOffline: true);
      await a.sendText('Keep me', queueIfOffline: true);
      final cancelled = a.messages.first;
      expect(await a.cancelQueuedMessage(cancelled), isTrue);
      expect(a.messages.single.text, 'Keep me');
      expect(await a.cancelQueuedMessage(cancelled), isFalse);
      await a.clearHistory();
      await connect();
      expect(a.messages, isEmpty);
      expect(b.messages, isEmpty);
      expect(a.conversations.single.queuedCount, 0);
    },
  );

  test(
    'Only the verified identity drains, even when a different saved chat is selected',
    () async {
      final bob = a.conversations.single;
      await sa.savePeer('another-identity', 'Another');
      await a.viewHistory(const Conversation('another-identity', 'Another', 0));
      await a.sendText('Only for Another', queueIfOffline: true);
      await a.viewHistory(bob);
      await a.sendText('Only for Bob', queueIfOffline: true);
      await connect(verify: false);
      await a.confirmCode();
      await a.viewHistory(const Conversation('another-identity', 'Another', 0));
      await b.confirmCode();
      await settle();
      expect(b.messages.single.text, 'Only for Bob');
      expect(a.messages.single.text, 'Only for Another');
      expect(a.messages.single.status, 'queued');
    },
  );

  test(
    'At most four attempts wait for ACK; disconnect retains unsent records without automatic retries',
    () async {
      for (var i = 0; i < 6; i++) {
        await a.sendText('Queued $i', queueIfOffline: true);
      }
      await connect(verify: false);
      await a.confirmCode();
      a.setAppAccess(false);
      await b.confirmCode();
      await settle();
      tb.dropAcks = true;
      a.setAppAccess(true);
      await settle();
      expect(a.messages.where((m) => m.status == 'sending').length, 4);
      expect(a.messages.where((m) => m.status == 'queued').length, 2);
      expect(b.messages.length, 4);
      await a.disconnect();
      await settle();
      tb.dropAcks = false;
      await connect();
      expect(a.messages.where((m) => m.status == 'unconfirmed').length, 4);
      expect(a.messages.where((m) => m.status == 'delivered').length, 2);
      expect(b.messages.length, 6);
    },
  );

  test(
    'Conflicting received IDs close the connection rather than acknowledging different text',
    () async {
      await a.sendText('Original queued text', queueIfOffline: true);
      final outgoing = a.messages.single;
      await sb.saveMessage(
        ChatMessage(
          id: outgoing.id,
          peerId: b.selectedPeer!,
          text: 'Conflicting saved copy',
          timestamp: outgoing.timestamp,
          outgoing: false,
          status: 'received',
        ),
      );
      await connect();
      expect(b.error, contains('Security check failed'));
      expect(b.ready, isFalse);
      expect(a.messages.single.status, 'unconfirmed');
      expect(b.messages.single.text, 'Conflicting saved copy');
    },
  );
}
