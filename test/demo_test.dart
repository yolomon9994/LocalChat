import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/models.dart';
import 'package:local_chat/core/local_store.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'package:local_chat/demo/demo_transport.dart';
import 'package:local_chat/features/settings_screen.dart';
import 'package:local_chat/main.dart';
import 'package:local_chat/services/chat_controller.dart';
import 'package:local_chat/services/transport.dart';

Future<void> waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Demo state did not settle');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  test('Startup selects the browser demo only on web', () {
    final c = createController();
    expect(c.isDemo, kIsWeb);
    expect(
      c.transport,
      kIsWeb ? isA<DemoTransport>() : isA<WifiDirectTransport>(),
    );
    expect(c.store, kIsWeb ? isA<DemoStore>() : isA<LocalStore>());
    if (!kIsWeb) expect(c.store, isNot(isA<DemoStore>()));
    // The uninitialized Android controller has no resources to release;
    // disposing it would invoke a native channel in a unit-test environment.
    if (kIsWeb) c.dispose();
  });
  test(
    'Demo supports discovery, verification, replies and in-memory history',
    () async {
      final store = DemoStore();
      final c = ChatController(DemoTransport(), store, isDemo: true);
      addTearDown(c.dispose);
      await c.initialize();
      expect(c.initialized, isTrue);
      expect(c.profileName, 'You (Demo)');
      await c.start();
      await waitFor(() => c.peers.length == 2 && !c.scanning);
      final ava = c.peers.first;
      await c.connect(ava);
      await waitFor(() => c.code != null);
      final firstCode = c.code;
      final avaId = c.connectedPeer;
      await c.sendText('blocked');
      expect(c.canSend, isFalse);
      expect(c.messages, isEmpty);
      await c.confirmCode();
      await waitFor(() => c.ready && c.messages.isNotEmpty);
      await c.sendText('Hello demo 👋');
      await waitFor(() => c.messages.length == 3);
      expect(c.messages.where((m) => m.outgoing).single.status, 'delivered');
      expect(c.messages.last.text, contains('simulated'));
      await c.disconnect();
      expect(c.canSend, isFalse);
      await c.viewHistory(c.conversations.single);
      expect(c.messages.length, 3);
      await c.connect(ava);
      await waitFor(() => c.code != null);
      expect(c.connectedPeer, avaId);
      expect(c.code, isNot(firstCode));
      expect(c.canSend, isFalse);
      await c.confirmCode();
      await waitFor(() => c.ready && c.messages.length == 4);
      await c.connect(c.peers.last);
      await waitFor(() => c.code != null && c.connectedPeer != avaId);
      await c.confirmCode();
      await waitFor(() => c.ready && c.conversations.length == 2);
      expect(c.messages.length, 1);
      await c.viewHistory(c.conversations.firstWhere((p) => p.id == avaId));
      expect(c.canSend, isFalse);
      expect(c.messages.length, 4);
      await c.viewConnected();
      expect(c.canSend, isTrue);
      await c.clearHistory();
      expect(c.messages, isEmpty);
      expect(c.conversations, isEmpty);
      await c.sendText('After deleting history');
      await waitFor(() => c.messages.length == 2);
      expect(c.messages.first.status, 'delivered');
      await c.rename('New demo name');
      expect(c.started, isFalse);
      expect(c.canSend, isFalse);
      expect(c.profileName, 'New demo name');
      final fresh = DemoStore();
      await fresh.open();
      expect(fresh.name, 'You (Demo)');
      expect(await fresh.conversations(), isEmpty);
    },
  );

  testWidgets('Browser notice stays visible through chat and settings', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final c = ChatController(DemoTransport(), DemoStore(), isDemo: true);
    await c.initialize();
    addTearDown(c.dispose);
    await tester.pumpWidget(LocalChatApp(controller: c));
    await tester.pumpAndSettle();
    expect(find.textContaining('BROWSER DEMO'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nearby-destination')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Go nearby'), 100);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go nearby'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Ava (Demo)'), 100);
    await Scrollable.ensureVisible(
      tester.element(find.text('Ava (Demo)')),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ava (Demo)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('BROWSER DEMO'), findsOneWidget);
    expect(find.textContaining('Demo verification:'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Codes match'));
    await tester.tap(find.text('Codes match'));
    await tester.pumpAndSettle();
    expect(find.textContaining('simulated peer and delivery'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.enterText(find.byType(TextField), 'A message between tabs');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(
      c.conversations.map((peer) => peer.name),
      contains('Ava (Demo)'),
      reason: 'State: ${c.state}; error: ${c.error}',
    );
    expect(
      c.messages.where((message) => message.outgoing).single.status,
      'delivered',
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    await tester.tap(find.byKey(const ValueKey('chats-destination')));
    await tester.pumpAndSettle();
    expect(find.text('Your chats'), findsOneWidget);
    expect(find.text('Nearby devices'), findsNothing);
    expect(c.ready, isTrue);
    await tester.scrollUntilVisible(
      find.text('Ava (Demo)'),
      100,
      scrollable: find.descendant(
        of: find.byKey(const PageStorageKey('chats-list')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ava (Demo)'));
    await tester.pumpAndSettle();
    expect(find.text('A message between tabs'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );
    await tester.ensureVisible(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('A message between tabs'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await c.disconnect();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Ava (Demo)'),
      100,
      scrollable: find.descendant(
        of: find.byKey(const PageStorageKey('chats-list')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ava (Demo)'));
    await tester.pumpAndSettle();
    expect(find.text('A message between tabs'), findsOneWidget);
    expect(c.canSend, isFalse);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.textContaining('BROWSER DEMO'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Temporary demo history'),
      100,
      scrollable: find
          .descendant(
            of: find.byType(SettingsScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Temporary demo history'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('Demo store scopes matching IDs by peer and direction', () async {
    final store = DemoStore();
    await store.open();
    for (final peer in ['a', 'b']) {
      await store.savePeer(peer, peer);
      for (final outgoing in [true, false]) {
        await store.saveMessage(
          ChatMessage(
            id: 'same-id',
            peerId: peer,
            text: '$peer/$outgoing',
            timestamp: 1,
            outgoing: outgoing,
            status: 'received',
          ),
        );
      }
    }
    await store.setStatus('same-id', 'a', 'delivered');
    final a = await store.messages('a');
    final b = await store.messages('b');
    expect(a.length, 2);
    expect(b.length, 2);
    expect(a.firstWhere((m) => m.outgoing).status, 'delivered');
    expect(a.firstWhere((m) => !m.outgoing).status, 'received');
    expect(b.every((m) => m.status == 'received'), isTrue);
    expect(
      (await store.conversations()).map((p) => p.unreadCount),
      everyElement(1),
    );
    await store.markRead('a');
    await store.saveMessage(
      const ChatMessage(
        id: 'same-id',
        peerId: 'a',
        text: 'duplicate',
        timestamp: 2,
        outgoing: false,
        status: 'received',
      ),
    );
    final summaries = await store.conversations();
    expect(summaries.singleWhere((p) => p.id == 'a').unreadCount, 0);
    expect(summaries.singleWhere((p) => p.id == 'b').unreadCount, 1);
    expect(
      summaries.singleWhere((p) => p.id == 'a').latestMessage!.text,
      'a/false',
    );
  });
}
