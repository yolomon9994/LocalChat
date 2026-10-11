import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/models.dart';
import 'package:local_chat/core/secure_session.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'package:local_chat/services/background_connection.dart';
import 'package:local_chat/services/chat_controller.dart';
import 'package:local_chat/services/chat_notifications.dart';

import 'chat_controller_test.dart' show LinkedTransport, settle;

class GatedBackgroundPlatform extends MemoryBackgroundPlatform {
  Completer<void>? gate;
  bool fail = false;
  @override
  Future<Map<String, dynamic>> start(int? generation) async {
    await gate?.future;
    if (fail) throw PlatformException(code: 'BACKGROUND');
    return super.start(generation);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Background preference and startup', () {
    late GatedBackgroundPlatform platform;
    late BackgroundConnection b;
    setUp(() async {
      platform = GatedBackgroundPlatform();
      b = BackgroundConnection(platform);
      await b.initialize();
    });
    tearDown(() => b.dispose());
    test(
      'Off by default; enabling only stores the choice until a verified session',
      () async {
        expect(b.enabled, false);
        expect(b.active, false);
        await b.setEnabled(true);
        expect(platform.enabled, true);
        expect(platform.starts, 0);
        await b.protect(1, canStart: () => false, sameConnection: () => true);
        expect(platform.starts, 0);
        await b.protect(1, canStart: () => true, sameConnection: () => true);
        expect(b.active, true);
        await b.setEnabled(false);
        expect(platform.enabled, false);
        expect(platform.active, false);
      },
    );
    test(
      'Denied notification access leaves mode off; later grant permits opt-in',
      () async {
        platform.allowed = false;
        await b.setEnabled(true);
        expect(b.enabled, false);
        expect(b.error, contains('Allow Android notifications'));
        platform.allowed = true;
        await b.setEnabled(true);
        expect(b.enabled, true);
        expect(b.error, null);
      },
    );
    test(
      'Loss during startup cannot mark a replacement or closed session active',
      () async {
        await b.setEnabled(true);
        platform.gate = Completer<void>();
        var same = true;
        final start = b.protect(
          7,
          canStart: () => true,
          sameConnection: () => same,
        );
        await settle();
        same = false;
        b.connectionEnded(unexpected: true);
        platform.gate!.complete();
        await start;
        await settle();
        expect(b.active, false);
        expect(platform.active, false);
        platform.gate = null;
        await b.protect(8, canStart: () => true, sameConnection: () => true);
        expect(b.active, true);
        expect(platform.starts, 2);
      },
    );
    test(
      'An authorized foreground start can finish after locking/backgrounding',
      () async {
        await b.setEnabled(true);
        platform.gate = Completer<void>();
        var foreground = true;
        final start = b.protect(
          7,
          canStart: () => foreground,
          sameConnection: () => true,
        );
        await settle();
        foreground = false;
        platform.gate!.complete();
        await start;
        expect(b.active, true);
        await b.protect(
          7,
          canStart: () => foreground,
          sameConnection: () => true,
        );
        expect(platform.starts, 1);
      },
    );
    test(
      'Notification Stop invalidates pending startup and disables the choice',
      () async {
        await b.setEnabled(true);
        platform.gate = Completer<void>();
        final start = b.protect(
          7,
          canStart: () => true,
          sameConnection: () => true,
        );
        await settle();
        b.nativeStatus({
          'enabled': false,
          'active': false,
          'allowed': true,
          'reason': 'user',
        });
        platform.gate!.complete();
        await start;
        expect(b.enabled, false);
        expect(b.active, false);
        expect(platform.active, false);
        expect(b.notice, contains('notification'));
      },
    );
    test(
      'Start failure offers retry; restart reads preference without automatic activation',
      () async {
        await b.setEnabled(true);
        platform.fail = true;
        await b.protect(1, canStart: () => true, sameConnection: () => true);
        expect(b.active, false);
        expect(b.error, isNotNull);
        platform.fail = false;
        await b.protect(1, canStart: () => true, sameConnection: () => true);
        expect(b.active, true);
        expect(b.error, null);
        await platform.stop();
        final restarted = BackgroundConnection(platform);
        addTearDown(restarted.dispose);
        await restarted.initialize();
        expect(restarted.enabled, true);
        expect(restarted.active, false);
        expect(platform.starts, 1);
      },
    );
  });

  group('Verified controller lifecycle', () {
    late ChatController a, b;
    late LinkedTransport ta, tb;
    late GatedBackgroundPlatform platform;
    late MemoryNotificationPlatform notifications;
    setUp(() async {
      ta = LinkedTransport();
      tb = LinkedTransport();
      ta.other = tb;
      tb.other = ta;
      platform = GatedBackgroundPlatform();
      notifications = MemoryNotificationPlatform();
      a = ChatController(ta, DemoStore());
      b = ChatController(
        tb,
        DemoStore(),
        background: BackgroundConnection(platform),
        notifications: ChatNotifications(notifications),
      );
      await b.background.initialize();
      await b.notifications.initialize();
      await b.notifications.setEnabled(true);
      await a.initialize();
      await b.initialize();
      await b.setBackgroundEnabled(true);
      await a.connect(const Peer('B', 'Bob'));
      await settle();
    });
    tearDown(() async {
      a.dispose();
      b.dispose();
      await ta.bus.close();
      await tb.bus.close();
    });
    Future<void> verify() async {
      await a.confirmCode();
      await b.confirmCode();
      await settle();
    }

    test(
      'Both fresh confirmations required; toggling never scans or connects',
      () async {
        expect(platform.starts, 0);
        await a.confirmCode();
        await settle();
        expect(platform.starts, 0);
        await b.confirmCode();
        await settle();
        expect(b.background.active, true);
        expect(platform.starts, 1);
        await a.disconnect();
        await settle();
        expect(b.background.active, false);
        await a.connect(const Peer('B', 'Bob'));
        await settle();
        expect(platform.starts, 1);
        expect(b.ready, false);
        await verify();
        expect(platform.starts, 2);
      },
    );
    test(
      'Last confirmation received while locked waits for foreground unlock',
      () async {
        await b.confirmCode();
        b.setAppAccess(false);
        b.setAppForeground(false);
        await a.confirmCode();
        await settle();
        expect(b.ready, true);
        expect(platform.starts, 0);
        b.setAppForeground(true);
        await settle();
        expect(platform.starts, 0);
        b.setAppAccess(true);
        await settle();
        expect(platform.starts, 1);
      },
    );
    test(
      'Locked background receives persist and ACK; outbox waits for foreground unlock',
      () async {
        await verify();
        b.setAppForeground(false);
        b.setAppAccess(false);
        await b.store.saveDraft(b.selectedPeer!, 'Keep this draft');
        await b.store.saveOutgoingMessage(
          ChatMessage(
            id: randomId(),
            peerId: b.selectedPeer!,
            text: 'Queued until unlocked',
            timestamp: 1,
            outgoing: true,
            status: 'queued',
          ),
        );
        await b.viewConnected();
        await a.sendText('Received while away');
        await settle();
        expect(b.background.active, true);
        expect(a.messages.single.status, 'delivered');
        expect(b.conversations.single.unreadCount, 1);
        expect(notifications.alerts.values.single.text, null);
        expect(b.messages.singleWhere((m) => m.outgoing).status, 'queued');
        b.setAppForeground(true);
        await settle();
        expect(b.messages.singleWhere((m) => m.outgoing).status, 'queued');
        b.setAppAccess(true);
        await settle();
        expect(b.messages.singleWhere((m) => m.outgoing).status, 'delivered');
        expect(await b.store.draft(b.selectedPeer!), 'Keep this draft');
      },
    );
    test(
      'Native Stop works while locked and preserves history/drafts without restart',
      () async {
        await verify();
        await a.sendText('Saved');
        await settle();
        final peer = b.selectedPeer!;
        await b.store.saveDraft(peer, 'Unfinished');
        b.setAppForeground(false);
        b.setAppAccess(false);
        platform.active = false;
        platform.enabled = false;
        tb.bus.add({
          'type': 'backgroundStatus',
          'enabled': false,
          'active': false,
          'allowed': true,
          'reason': 'user',
        });
        tb.bus.add({'type': 'backgroundStopped', 'reason': 'user'});
        await settle();
        expect(b.ready, false);
        expect(b.started, false);
        expect(b.background.enabled, false);
        expect(b.messages.single.text, 'Saved');
        expect(await b.store.draft(peer), 'Unfinished');
        b.setAppForeground(true);
        b.setAppAccess(true);
        await settle();
        expect(platform.starts, 1);
        expect(b.connectedPeer, null);
        expect(b.background.notice, contains('notification'));
      },
    );
    test(
      'Service failure does not break messaging; connection loss leaves retry guidance',
      () async {
        platform.fail = true;
        await verify();
        expect(b.ready, true);
        expect(b.background.error, isNotNull);
        await a.sendText('Still delivered');
        await settle();
        expect(a.messages.single.status, 'delivered');
        platform.fail = false;
        await b.retryBackground();
        expect(b.background.active, true);
        await a.disconnect();
        await settle();
        expect(b.background.active, false);
        expect(b.background.notice, contains('Reconnect'));
        expect(b.messages.single.text, 'Still delivered');
      },
    );
  });

  test(
    'Android channel keeps generation, permission and fixed settings destinations separate',
    () async {
      const channel = MethodChannel('dev.localchat/background');
      const notificationChannel = MethodChannel('dev.localchat/notifications');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'status' || call.method == 'start') {
          return {
            'enabled': true,
            'active': call.method == 'start',
            'allowed': true,
            'batteryExempt': true,
          };
        }
        return null;
      });
      messenger.setMockMethodCallHandler(
        notificationChannel,
        (_) async => false,
      );
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      addTearDown(
        () => messenger.setMockMethodCallHandler(notificationChannel, null),
      );
      const platform = AndroidBackgroundPlatform();
      await platform
          .requestPermission(); // Messages channel may be blocked independently.
      expect((await platform.status())['allowed'], true);
      await platform.configure(true);
      await platform.start(42);
      await platform.frameProcessed(42);
      await platform.openSettings('battery');
      await platform.openSettings('notifications');
      await platform.stop();
      expect(calls.singleWhere((c) => c.method == 'start').arguments, {
        'generation': 42,
      });
      expect(calls.singleWhere((c) => c.method == 'frameProcessed').arguments, {
        'generation': 42,
      });
      expect(
        calls.where((c) => c.method == 'openSettings').map((c) => c.arguments),
        [
          {'target': 'battery'},
          {'target': 'notifications'},
        ],
      );
    },
  );
}
