import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/models.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'package:local_chat/demo/demo_transport.dart';
import 'package:local_chat/services/chat_controller.dart';
import 'package:local_chat/services/chat_search_controller.dart';
import 'chat_controller_test.dart' show LinkedTransport, settle;

class FailingManagementStore extends DemoStore {
  bool fail = true;
  @override
  Future<bool> setPinned(String peer, bool value) async {
    if (fail) throw StateError('Private storage detail');
    return super.setPinned(peer, value);
  }

  @override
  Future<void> deleteConversation(String peer) async {
    if (fail) throw StateError('Private storage detail');
    await super.deleteConversation(peer);
  }
}

void main() {
  test(
    'Archiving survives live incoming text; deleting active chat disconnects and keeps other history',
    () async {
      final ta = LinkedTransport(), tb = LinkedTransport();
      ta.other = tb;
      tb.other = ta;
      final a = ChatController(ta, DemoStore()),
          b = ChatController(tb, DemoStore());
      addTearDown(() async {
        a.dispose();
        b.dispose();
        await ta.bus.close();
        await tb.bus.close();
      });
      await a.initialize();
      await b.initialize();
      await a.start();
      await b.start();
      await a.connect(const Peer('b', 'Bob'));
      await settle();
      await a.confirmCode();
      await b.confirmCode();
      await settle();
      final peer = b.selectedPeer!;
      await b.drafts.load(peer);
      b.drafts.setText(peer, 'Unsent');
      await b.store.savePeer('other', 'Other');
      await b.store.saveDraft('other', 'Other draft');
      expect(await b.setPinned(peer, true), isTrue);
      expect(await b.setArchived(peer, true), isTrue);
      await a.sendText('Incoming to archive');
      await settle();
      final archived = b.conversations.singleWhere((p) => p.id == peer);
      expect(archived.archived, isTrue);
      expect(archived.pinned, isTrue);
      expect(archived.unreadCount, 1);
      expect(await b.deleteConversation(peer), isTrue);
      await settle();
      expect(b.connectedPeer, isNull);
      expect(a.connectedPeer, isNull);
      expect(b.selectedPeer, isNull);
      expect(await b.store.messages(peer), isEmpty);
      expect(await b.store.draft(peer), '');
      expect(b.conversations.single.id, 'other');
      expect(await b.store.draft('other'), 'Other draft');
      expect(a.messages.single.text, 'Incoming to archive');
    },
  );

  test(
    'Failures preserve state and draft; deletion invalidates search and stale opens',
    () async {
      final store = FailingManagementStore();
      final c = ChatController(DemoTransport(), store, isDemo: true);
      addTearDown(c.dispose);
      await c.initialize();
      await store.savePeer('alice', 'Alice');
      final peer = (await store.conversations()).single;
      await c.viewHistory(peer);
      await c.drafts.load('alice');
      c.drafts.setText('alice', 'Keep draft');
      await c.drafts.settled;
      expect(await c.setPinned('alice', true), isFalse);
      expect(c.conversations.single.pinned, isFalse);
      expect(c.error, isNot(contains('Private')));
      expect(await c.deleteConversation('alice'), isFalse);
      expect(c.selectedPeer, 'alice');
      expect(c.drafts.textFor('alice'), 'Keep draft');
      final search = ChatSearchController(c, debounce: Duration.zero);
      addTearDown(search.dispose);
      search.setQuery('Alice');
      await settle();
      expect(search.results.conversations.length, 1);
      store.fail = false;
      expect(await c.setPinned('alice', true), isTrue);
      expect(await c.setArchived('alice', true), isTrue);
      await settle();
      expect(search.results.conversations.single.archived, isTrue);
      expect(await c.deleteConversation('alice'), isTrue);
      await settle();
      expect(search.results.conversations, isEmpty);
      expect(await c.viewHistory(peer), isFalse);
      expect(c.selectedPeer, isNull);
      expect(await c.setPinned('alice', true), isFalse);
    },
  );
}
