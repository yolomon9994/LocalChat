import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'package:local_chat/core/models.dart';
import 'package:local_chat/services/chat_controller.dart';
import 'package:local_chat/services/chat_notifications.dart';

import 'chat_controller_test.dart' show LinkedTransport, settle;

class RecordingNotifications extends MemoryNotificationPlatform {
  int posted = 0;
  bool fail = false;
  @override
  Future<void> show(String peer, {String? name, String? text}) async {
    if (fail) throw StateError('Notification manager unavailable');
    posted++;
    await super.show(peer, name: name, text: text);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Notification settings and privacy', () {
    late RecordingNotifications platform;
    late ChatNotifications n;
    setUp(() async {
      platform = RecordingNotifications();
      n = ChatNotifications(platform);
      await n.initialize();
    });
    tearDown(() => n.dispose());
    test('Opt-in defaults; generic alerts never pass sender or body', () async {
      n.setAccessible(true);
      await n.incoming('alice', 'Alice', 'Secret', isReading: () => false);
      expect(platform.posted, 0);
      expect(n.previews, false);
      await n.setEnabled(true);
      await n.incoming('alice', 'Alice', 'Secret', isReading: () => false);
      expect(platform.alerts['alice'], (name: null, text: null));
      await n.setEnabled(false);
      expect(platform.alerts, isEmpty);
    });
    test(
      'Opt-in previews redact existing alerts and future locked alerts',
      () async {
        await n.setEnabled(true);
        await n.setPreviews(true);
        n.setAccessible(true);
        await n.incoming('alice', 'Alice', 'Secret', isReading: () => false);
        expect(platform.alerts['alice'], (name: 'Alice', text: 'Secret'));
        n.setAccessible(false);
        await n.refreshPermission(); // Wait for privacy work.
        expect(platform.alerts['alice'], (name: null, text: null));
        await n.incoming('bob', 'Bob', 'Hidden', isReading: () => false);
        expect(platform.alerts['bob'], (name: null, text: null));
        n.setAccessible(true);
        await n.incoming('bob', 'Bob', 'Visible', isReading: () => false);
        await n.setPreviews(false);
        expect(
          platform.alerts.values.every((a) => a.text == null && a.name == null),
          true,
        );
      },
    );
    test(
      'Permission denied preserves choice; later grant is refreshed',
      () async {
        platform.allowed = false;
        await n.setEnabled(true);
        expect(n.enabled, true);
        expect(n.allowed, false);
        await n.incoming('alice', 'Alice', 'Secret', isReading: () => false);
        expect(platform.alerts, isEmpty);
        platform.allowed = true;
        await n.refreshPermission();
        expect(n.allowed, true);
        await n.incoming('alice', 'Alice', 'Secret', isReading: () => false);
        expect(platform.alerts.length, 1);
      },
    );
    test('Suppress current chat; other peers get independent alerts', () async {
      await n.setEnabled(true);
      await n.incoming('alice', 'Alice', 'Reading', isReading: () => true);
      expect(platform.posted, 0);
      await n.incoming('alice', 'Alice', 'One', isReading: () => false);
      await n.incoming('bob', 'Bob', 'Two', isReading: () => false);
      await n.cancel('alice');
      expect(platform.alerts.keys, ['bob']);
      await n.cancel(null);
      expect(platform.alerts, isEmpty);
    });
    test('Native failures stay in notification settings and recover', () async {
      await n.setEnabled(true);
      platform.fail = true;
      await n.incoming('alice', 'Alice', 'One', isReading: () => false);
      expect(n.error, isNotNull);
      platform.fail = false;
      await n.setEnabled(true);
      await n.incoming('alice', 'Alice', 'Two', isReading: () => false);
      expect(n.error, isNull);
      expect(platform.alerts.length, 1);
    });
  });

  group('Verified incoming messages', () {
    late ChatController a, b;
    late LinkedTransport ta, tb;
    late RecordingNotifications platform;
    setUp(() async {
      ta = LinkedTransport();
      tb = LinkedTransport();
      ta.other = tb;
      tb.other = ta;
      platform = RecordingNotifications();
      a = ChatController(ta, DemoStore());
      b = ChatController(
        tb,
        DemoStore(),
        notifications: ChatNotifications(platform),
      );
      await b.notifications.initialize();
      await b.notifications.setEnabled(true);
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
      'Alert once after persistence; ACK retry does not create another alert',
      () async {
        tb.dropAcks = true;
        await a.sendText('Original');
        await settle();
        expect(platform.posted, 1);
        expect(b.conversations.single.unreadCount, 1);
        await a.disconnect();
        await settle();
        tb.dropAcks = false;
        await a.connect(const Peer('B', 'Bob'));
        await settle();
        await a.confirmCode();
        await b.confirmCode();
        await settle();
        await a.retryMessage(a.messages.single);
        await settle();
        expect(a.messages.single.status, 'delivered');
        expect(b.messages.length, 1);
        expect(b.conversations.single.unreadCount, 1);
        expect(platform.posted, 1);
      },
    );
    test(
      'Visible chat clears alert; background and lock still notify generically',
      () async {
        await a.sendText('Off screen');
        await settle();
        expect(platform.alerts.length, 1);
        final screen = Object();
        b.setChatVisible(screen, true);
        await settle();
        expect(platform.alerts, isEmpty);
        await a.sendText('Reading');
        await settle();
        expect(platform.posted, 1);
        b.setAppForeground(false);
        await a.sendText('Background');
        await settle();
        expect(platform.posted, 2);
        expect(b.conversations.single.unreadCount, 1);
        b.setAppAccess(false);
        b.setAppForeground(true);
        await a.sendText('Locked');
        await settle();
        expect(platform.posted, 3);
        expect(platform.alerts.values.single.text, null);
      },
    );
    test(
      'Notification manager failure does not disconnect or prevent ACK',
      () async {
        platform.fail = true;
        await a.sendText('Persisted despite notification failure');
        await settle();
        expect(a.messages.single.status, 'delivered');
        expect(b.ready, true);
        expect(b.error, null);
        expect(
          b.messages.single.text,
          'Persisted despite notification failure',
        );
        expect(b.notifications.error, isNotNull);
      },
    );
    test(
      'Deleting history clears displayed and pending notifications',
      () async {
        await a.sendText('Delete me');
        await settle();
        platform.tapEvents.add(b.selectedPeer!);
        await settle();
        expect(b.notifications.pendingPeer, isNotNull);
        await b.clearHistory();
        await settle();
        expect(platform.alerts, isEmpty);
        expect(b.notifications.pendingPeer, null);
      },
    );
  });

  test(
    'Android bridge reads cold and warm taps, and sends generic payloads',
    () async {
      const channel = MethodChannel('dev.localchat/notifications');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      var pending = 'cold-peer';
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'settings') {
          return {'enabled': true, 'previews': false, 'allowed': true};
        }
        if (call.method == 'takeTap') {
          final value = pending;
          pending = '';
          return value;
        }
        return null;
      });
      final n = ChatNotifications(AndroidNotificationPlatform());
      addTearDown(n.dispose);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await n.initialize();
      expect(n.pendingPeer, 'cold-peer');
      n.consumeTap('cold-peer');
      pending = 'warm-peer';
      final done = Completer<void>();
      messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('tapAvailable'),
        ),
        (_) => done.complete(),
      );
      await done.future;
      expect(n.pendingPeer, 'warm-peer');
      n.setAccessible(true);
      await n.incoming(
        'peer',
        'Secret name',
        'Secret body',
        isReading: () => false,
      );
      expect(calls.singleWhere((c) => c.method == 'show').arguments, {
        'peer': 'peer',
        'name': null,
        'text': null,
      });
    },
  );
}
