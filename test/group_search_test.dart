import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/group_models.dart';
import 'package:local_chat/core/group_search.dart';
import 'package:local_chat/core/models.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'package:local_chat/demo/demo_transport.dart';
import 'package:local_chat/services/chat_controller.dart';
import 'package:local_chat/services/chat_search_controller.dart';
import 'chat_search_controller_test.dart' show PendingSearchStore, searchTurn;
import 'group_draft_test.dart' show emptyGroup;
import 'group_test_support.dart';
import 'package:local_chat/core/secure_session.dart';

GroupText searchText(String id, String text, int timestamp, {String? author}) =>
    GroupText({
      'id': id,
      'authorId': author ?? 'a' * 64,
      'name': 'Member',
      'text': text,
      'timestamp': timestamp,
      'targets': <String>[],
    });

void main() {
  test(
    'received signed group messages refresh an active archived search without reading it',
    () async {
      final net = GroupNetwork();
      final chat = ChatController(
        DemoTransport(),
        DemoStore(),
        isDemo: true,
        groupTransport: FakeGroupTransport(net),
      );
      addTearDown(chat.dispose);
      await chat.initialize();
      net.controllers.add(chat.groups);
      expect(await chat.groups.host('Room'), isTrue);
      final guest = await net.phone('Guest');
      addTearDown(() async {
        await guest.stop();
        guest.dispose();
      });
      await net.join(guest);
      await chat.groups.setArchived(chat.groups.active!.id, true);
      final search = ChatSearchController(chat, debounce: Duration.zero);
      addTearDown(search.dispose);
      search.setQuery('incoming needle');
      await searchTurn();
      expect(search.groupResults.messages, isEmpty);
      expect(await guest.sendText('Incoming NEEDLE'), isTrue);
      await net.settle();
      await searchTurn();
      final hit = search.groupResults.messages.single;
      expect(hit.author, guest.selfId);
      expect(hit.group.archived, isTrue);
      expect(chat.groups.active!.unread, 1);
      expect(chat.groups.connected, isTrue);
    },
  );

  test(
    'backup imports refresh existing search and keep imported drafts out of results',
    () async {
      final chat = ChatController(DemoTransport(), DemoStore(), isDemo: true);
      addTearDown(chat.dispose);
      await chat.initialize();
      final source = DemoStore();
      await source.open();
      final group = await emptyGroup(source);
      final message = await GroupText.create(
        source.identity,
        source.name,
        group: group.id,
        host: group.host,
        epoch: randomId(),
        view: 1,
        text: 'Transferred needle',
        targets: [await identityId(group.host)],
      );
      await source.saveGroupHistory(group.copy(messages: [message]));
      await source.saveGroupDraft(group.id, 'Draft secret');
      final search = ChatSearchController(chat, debounce: Duration.zero);
      addTearDown(search.dispose);
      search.setQuery('transferred');
      await searchTurn();
      expect(search.groupResults.messages, isEmpty);
      await chat.restoreBackup(
        await source.exportBackup(),
        accessToken: chat.accessRevision,
      );
      await searchTurn();
      expect(search.groupResults.messages.single.key, message.key);
      search.setQuery('draft secret');
      await searchTurn();
      expect(search.groupResults.messages, isEmpty);
      expect(await chat.store.groupDraft(group.id), 'Draft secret');
    },
  );
  test(
    'literal Unicode text and group names include archived groups without changing state',
    () async {
      final messages = [
        searchText('same', 'Hello سلام 👋 %_\nEND', 2),
        searchText('same', 'hello again', 3, author: 'b' * 64),
      ];
      final history = GroupHistory(
        id: 'room',
        title: 'HELLO friends',
        host: '',
        messages: messages,
        archived: true,
        pinned: true,
      );
      final result = await searchGroupHistories([history], '  hElLo  ');
      expect(result.groups.single.archived, isTrue);
      expect(result.messages.map((m) => m.key).toSet().length, 2);
      expect(result.messages.first.timestamp, 3);
      expect(
        (await searchGroupHistories([history], 'سلام 👋')).messages.single.text,
        contains('سلام 👋'),
      );
      expect((await searchGroupHistories([history], '%_')).messages.length, 1);
      expect(
        (await searchGroupHistories([history], '%other')).messages,
        isEmpty,
      );
      expect(history.messages.every((m) => !m.read), isTrue);
      expect(history.pinned && history.archived, isTrue);
    },
  );

  test(
    'newest global limit ignores pin order and scopes by room with stable ties',
    () async {
      final first = GroupHistory(
        id: 'b',
        title: 'Room',
        host: '',
        pinned: true,
        messages: List.generate(120, (i) => searchText('$i', 'match', i)),
      );
      final second = GroupHistory(
        id: 'a',
        title: 'Room',
        host: '',
        messages: [
          searchText('old', 'match', 1),
          searchText('last', 'match', 119),
        ],
      );
      final result = await searchGroupHistories([first, second], 'match');
      expect(result.messages.length, 100);
      expect(result.hasMoreMessages, isTrue);
      expect(result.messages.first.group.id, 'a');
      expect(result.messages.last.timestamp, 21);
      final scoped = await searchGroupHistories(
        [first, second],
        'match',
        groupId: 'a',
      );
      expect(scoped.messages.length, 2);
      expect(scoped.groups, isEmpty);
      expect(scoped.hasMoreMessages, isFalse);
      expect(
        (await searchGroupHistories(
          [first],
          'match',
          groupId: 'missing',
        )).messages,
        isEmpty,
      );
      expect(
        (await searchGroupHistories([first], 'match', limit: 0)).messages,
        isEmpty,
      );
      expect((await searchGroupHistories([first], '   ')).messages, isEmpty);
    },
  );

  test('scan yields and cancellation discards partial matches', () async {
    final group = GroupHistory(
      id: 'room',
      title: 'Room',
      host: '',
      messages: List.generate(1000, (i) => searchText('$i', 'match', i)),
    );
    var cancel = false;
    final work = searchGroupHistories(
      [group],
      'match',
      isCancelled: () => cancel,
    );
    cancel = true;
    expect((await work).messages, isEmpty);
    expect(
      (await searchGroupHistories(
        [group],
        'match',
        isCancelled: () => true,
      )).messages,
      isEmpty,
    );
  });

  test(
    'file names and image labels match without searching or retaining contents',
    () async {
      final file = GroupText({
        ...searchText('file', 'File', 1).envelope,
        'file': {
          'name': 'Meeting_notes.txt',
          'length': 6,
          'digest': 'a' * 64,
          'mime': 'application/octet-stream',
        },
      }, fileBytes: Uint8List.fromList('secret'.codeUnits));
      final group = GroupHistory(
        id: 'room',
        title: 'Room',
        host: '',
        messages: [file, searchText('image', 'Image', 2)],
      );
      expect(
        (await searchGroupHistories([group], 'notes')).messages.single.text,
        'File: Meeting_notes.txt',
      );
      expect((await searchGroupHistories([group], 'secret')).messages, isEmpty);
      expect(
        (await searchGroupHistories([group], 'image')).messages.single.key,
        endsWith('/image'),
      );
    },
  );

  test(
    'global and scoped controllers isolate direct chats and drafts and refresh changes',
    () async {
      final store = DemoStore();
      final chat = ChatController(DemoTransport(), store, isDemo: true);
      addTearDown(chat.dispose);
      await chat.initialize();
      var group = (await emptyGroup(
        store,
      )).copy(messages: [searchText('one', 'needle', 1)], archived: true);
      await store.saveGroupHistory(group);
      await store.saveGroupDraft(group.id, 'draft-only secret');
      await store.savePeer(group.id, 'Direct needle');
      await store.saveMessage(
        ChatMessage(
          id: 'one',
          peerId: group.id,
          text: 'needle',
          timestamp: 2,
          outgoing: false,
          status: 'received',
        ),
      );
      await chat.groups.refreshHistory();
      final global = ChatSearchController(chat, debounce: Duration.zero);
      final scoped = ChatSearchController(
        chat,
        groupId: group.id,
        debounce: Duration.zero,
      );
      addTearDown(global.dispose);
      addTearDown(scoped.dispose);
      global.setQuery('needle');
      scoped.setQuery('needle');
      await searchTurn();
      expect(global.results.messages.length, 1);
      expect(global.groupResults.messages.length, 1);
      expect(scoped.results.messages, isEmpty);
      expect(scoped.groupResults.messages.single.group.archived, isTrue);
      expect(chat.groups.histories.single.unread, 1);
      group = group.copy(
        messages: [...group.messages, searchText('two', 'new needle', 3)],
      );
      await store.saveGroupHistory(group);
      await chat.groups.refreshHistory();
      await searchTurn();
      expect(scoped.groupResults.messages.length, 2);
      await chat.groups.setArchived(group.id, false);
      await searchTurn();
      expect(
        scoped.groupResults.messages.every((m) => !m.group.archived),
        isTrue,
      );
      scoped.setQuery('draft-only');
      await searchTurn();
      expect(scoped.groupResults.messages, isEmpty);
      expect(await store.groupDraft(group.id), 'draft-only secret');
      await chat.groups.delete(group.id);
      await searchTurn();
      expect(global.groupResults.messages, isEmpty);
      expect(global.results.messages.length, 1);
    },
  );

  test(
    'background clears results, resumes query, and lock discards pending work and query',
    () async {
      final store = PendingSearchStore();
      final chat = ChatController(DemoTransport(), store, isDemo: true);
      addTearDown(chat.dispose);
      await chat.initialize();
      final group = (await emptyGroup(
        store,
      )).copy(messages: [searchText('one', 'secret', 1)]);
      await store.saveGroupHistory(group);
      await chat.groups.refreshHistory();
      final search = ChatSearchController(chat, debounce: Duration.zero);
      addTearDown(search.dispose);
      search.setQuery('secret');
      await searchTurn();
      chat.setAppForeground(false);
      expect(store.pending.first.$3!(), isTrue);
      store.pending.first.$2.complete(const LocalSearchResults());
      await searchTurn();
      expect(search.groupResults.messages, isEmpty);
      expect(search.loading, isFalse);
      chat.setAppForeground(true);
      await searchTurn();
      store.pending.last.$2.complete(const LocalSearchResults());
      await searchTurn();
      expect(search.groupResults.messages.length, 1);
      search.retry();
      await searchTurn();
      final pending = store.pending.last;
      chat.setAppAccess(false);
      chat.setAppAccess(true);
      expect(pending.$3!(), isTrue);
      pending.$2.completeError(StateError('private detail'));
      await searchTurn();
      expect(search.query, '');
      expect(search.groupResults.messages, isEmpty);
      expect(search.results.messages, isEmpty);
      expect(search.error, isNull);
    },
  );

  test(
    'new group revision cancels an older scan waiting on direct storage',
    () async {
      final store = PendingSearchStore();
      final chat = ChatController(DemoTransport(), store, isDemo: true);
      addTearDown(chat.dispose);
      await chat.initialize();
      final search = ChatSearchController(chat, debounce: Duration.zero);
      search.setQuery('match');
      await searchTurn();
      final old = store.pending.single;
      await store.saveGroupHistory(
        (await emptyGroup(
          store,
        )).copy(messages: [searchText('new', 'match', 1)]),
      );
      await chat.groups.refreshHistory();
      await searchTurn();
      expect(old.$3!(), isTrue);
      store.pending.last.$2.complete(const LocalSearchResults());
      await searchTurn();
      old.$2.completeError(StateError('obsolete'));
      await searchTurn();
      expect(search.groupResults.messages.single.key, endsWith('/new'));
      expect(search.error, isNull);
      search.setQuery('other');
      await searchTurn();
      expect(search.groupResults.messages, isEmpty);
      search.dispose();
      store.pending.last.$2.complete(const LocalSearchResults());
      await searchTurn();
    },
  );
}
