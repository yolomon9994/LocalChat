import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/models.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'package:local_chat/demo/demo_transport.dart';
import 'package:local_chat/services/chat_controller.dart';
import 'package:local_chat/services/chat_search_controller.dart';

class PendingSearchStore extends DemoStore {
  final pending = <(String, Completer<LocalSearchResults>, bool Function()?)>[];
  @override
  Future<LocalSearchResults> search(
    String query, {
    bool Function()? isCancelled,
    int limit = 100,
  }) {
    final request = Completer<LocalSearchResults>();
    pending.add((query, request, isCancelled));
    return request.future;
  }
}

class FailingSearchStore extends DemoStore {
  bool fail = true;
  @override
  Future<LocalSearchResults> search(
    String query, {
    bool Function()? isCancelled,
    int limit = 100,
  }) async {
    if (fail) throw StateError('Unavailable');
    return super.search(query, isCancelled: isCancelled, limit: limit);
  }
}

Future<void> searchTurn() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  test(
    'New queries, clearing and disposal cancel old results and errors',
    () async {
      final store = PendingSearchStore();
      final chat = ChatController(DemoTransport(), store, isDemo: true);
      addTearDown(chat.dispose);
      await chat.initialize();
      final search = ChatSearchController(chat, debounce: Duration.zero);
      search.setQuery('old');
      await searchTurn();
      search.setQuery('new');
      await searchTurn();
      expect(store.pending[0].$3!(), isTrue);
      store.pending[1].$2.complete(
        const LocalSearchResults(
          conversations: [Conversation('new', 'New', 1)],
        ),
      );
      await searchTurn();
      store.pending[0].$2.completeError(StateError('Stale error'));
      await searchTurn();
      expect(search.results.conversations.single.id, 'new');
      expect(search.error, isNull);
      search.setQuery('clear me');
      await searchTurn();
      search.setQuery('');
      store.pending[2].$2.complete(
        const LocalSearchResults(
          conversations: [Conversation('old', 'Old', 1)],
        ),
      );
      await searchTurn();
      expect(search.results.conversations, isEmpty);
      expect(search.loading, isFalse);
      search.setQuery('dispose me');
      await searchTurn();
      search.dispose();
      expect(store.pending[3].$3!(), isTrue);
      store.pending[3].$2.completeError(StateError('After disposal'));
      await searchTurn();
    },
  );

  test(
    'A failed search can retry and history deletion invalidates results',
    () async {
      final store = FailingSearchStore();
      final chat = ChatController(DemoTransport(), store, isDemo: true);
      addTearDown(chat.dispose);
      await chat.initialize();
      await store.savePeer('alice', 'Alice');
      final search = ChatSearchController(chat, debounce: Duration.zero);
      addTearDown(search.dispose);
      search.setQuery('alice');
      await searchTurn();
      expect(search.error, isNotNull);
      expect(search.loading, isFalse);
      store.fail = false;
      search.retry();
      await searchTurn();
      expect(search.error, isNull);
      expect(search.results.conversations.single.id, 'alice');
      await chat.clearHistory();
      await searchTurn();
      expect(search.results.conversations, isEmpty);
    },
  );
}
