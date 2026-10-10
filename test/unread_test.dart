import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/models.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'package:local_chat/services/chat_controller.dart';

import 'chat_controller_test.dart' show LinkedTransport, settle;

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
    a = ChatController(ta, DemoStore());
    b = ChatController(tb, DemoStore());
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
    'Receiving off-screen is unread; selection alone does not clear it',
    () async {
      await a.sendText('First');
      await a.sendText('Second');
      await settle();
      expect(a.conversations.single.unreadCount, 0);
      expect(b.conversations.single.unreadCount, 2);
      expect(b.conversations.single.latestMessage!.text, 'Second');
      await b.viewHistory(b.conversations.single);
      await b.viewConnected();
      expect(b.conversations.single.unreadCount, 2);
      final screen = Object();
      b.setChatVisible(screen, true);
      await settle();
      expect(b.conversations.single.unreadCount, 0);
      await a.sendText('While reading');
      await settle();
      expect(b.messages.last.text, 'While reading');
      expect(b.conversations.single.unreadCount, 0);
      b.setChatVisible(screen, false);
      await a.sendText('After leaving');
      await settle();
      expect(b.conversations.single.unreadCount, 1);
    },
  );

  test(
    'Lock and foreground gates recheck queued reads and preserve new unread messages',
    () async {
      await a.sendText('Waiting');
      await settle();
      final screen = Object();
      b.setChatVisible(screen, true);
      b.setAppAccess(false); // Lock before the queued read runs.
      await settle();
      expect(b.conversations.single.unreadCount, 1);
      await a.sendText('While locked');
      await settle();
      expect(b.conversations.single.unreadCount, 2);
      b.setAppAccess(true);
      await settle();
      expect(b.conversations.single.unreadCount, 0);
      b.setAppForeground(false);
      await a.sendText('In background');
      await settle();
      expect(b.conversations.single.unreadCount, 1);
      // Disposing an old route cannot hide its replacement.
      final replacement = Object();
      b.setChatVisible(replacement, true);
      b.setChatVisible(screen, false);
      b.setAppForeground(true);
      await settle();
      expect(b.conversations.single.unreadCount, 0);
    },
  );

  test(
    'Verification hides unread history; viewing another peer never reads the active peer',
    () async {
      await a.sendText('Before reconnect');
      await settle();
      await a.disconnect();
      await settle();
      await a.connect(const Peer('B', 'Bob'));
      await settle();
      final screen = Object();
      b.setChatVisible(screen, true);
      await b.viewConnected();
      expect(b.ready, isFalse);
      expect(b.conversations.single.unreadCount, 1);
      await a.confirmCode();
      await b.confirmCode();
      await settle();
      expect(b.conversations.single.unreadCount, 0);
      final activePeer = b.connectedPeer!;
      await b.store.savePeer('saved', 'Other friend');
      await b.store.saveMessage(
        const ChatMessage(
          id: 'saved-message',
          peerId: 'saved',
          text: 'Other history',
          timestamp: 1,
          outgoing: false,
          status: 'received',
        ),
      );
      await b.viewHistory(const Conversation('saved', 'Other friend', 1));
      await a.sendText('Active peer while reading elsewhere');
      await settle();
      expect(b.messages.single.text, 'Other history');
      expect(
        b.conversations.singleWhere((p) => p.id == 'saved').unreadCount,
        0,
      );
      expect(
        b.conversations.singleWhere((p) => p.id == activePeer).unreadCount,
        1,
      );
      await b.viewConnected();
      expect(
        b.conversations.singleWhere((p) => p.id == activePeer).unreadCount,
        0,
      );
    },
  );
}
