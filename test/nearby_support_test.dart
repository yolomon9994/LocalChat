import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/models.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'package:local_chat/services/chat_controller.dart';
import 'package:local_chat/services/nearby_support.dart';
import 'package:local_chat/services/transport.dart';
import 'chat_controller_test.dart' show LinkedTransport, settle;

class TestNearbyTools implements NearbyTools {
  NearbyStatus status = const NearbyStatus();
  Completer<void>? gate;
  final entered = Completer<void>();
  bool failCheck = false, failSettings = false;
  final opened = <NearbySettings>[];
  @override
  Future<NearbyStatus> check() async {
    if (!entered.isCompleted) entered.complete();
    await gate?.future;
    if (failCheck) throw StateError('Private status details');
    return status;
  }

  @override
  Future<void> openSettings(NearbySettings target) async {
    if (failSettings) throw StateError('Private settings details');
    opened.add(target);
  }
}

class RecoveryTransport implements Transport {
  final bus = StreamController<Map<String, dynamic>>.broadcast();
  int starts = 0, scans = 0, connects = 0, stops = 0;
  String? startFailure, scanFailure, connectFailure;
  void Function()? onStart;
  @override
  Stream<Map<String, dynamic>> get events => bus.stream;
  @override
  Future<void> start(String name) async {
    starts++;
    if (startFailure case final code?) {
      throw PlatformException(code: code, message: 'Private native details');
    }
    onStart?.call();
  }

  @override
  Future<void> scan() async {
    scans++;
    if (scanFailure case final code?) {
      throw PlatformException(code: code, message: 'Private native details');
    }
    bus.add({'type': 'scanning', 'active': false});
  }

  @override
  Future<void> connect(String address) async {
    connects++;
    if (connectFailure case final code?) {
      throw PlatformException(code: code, message: 'Private native details');
    }
  }

  @override
  Future<void> disconnect() async => bus.add({'type': 'disconnected'});
  @override
  Future<void> send(String frame) async {}
  @override
  Future<void> stop() async => stops++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RecoveryTransport t;
  late TestNearbyTools tools;
  late ChatController c;
  setUp(() async {
    t = RecoveryTransport();
    tools = TestNearbyTools();
    c = ChatController(t, DemoStore(), nearbyTools: tools);
    await c.initialize();
  });
  tearDown(() async {
    c.dispose();
    await t.bus.close();
  });

  test(
    'Readiness failures preserve saved data and block radio actions until fixed',
    () async {
      await c.store.savePeer('saved', 'Saved');
      await c.store.saveDraft('saved', 'Keep draft');
      for (final (status, issue) in [
        (const NearbyStatus(wifiEnabled: false), ConnectionIssue.wifiOff),
        (const NearbyStatus(supported: false), ConnectionIssue.unsupported),
        (
          const NearbyStatus(locationRequired: true, locationEnabled: false),
          ConnectionIssue.locationOff,
        ),
      ]) {
        tools.status = status;
        expect(await c.start(), isFalse);
        expect(c.connectionIssue, issue);
        expect(c.hasConnectionHelp, isTrue);
        expect(t.starts, 0);
        expect(await c.store.draft('saved'), 'Keep draft');
      }
      tools.status = const NearbyStatus();
      await c.refreshNearbyAccess();
      expect(c.error, isNull);
      expect(await c.start(), isTrue);
      expect(t.starts, 1);
      expect(t.scans, 1);
    },
  );

  test(
    'First start can request permission; grant refreshes status and later denial offers app settings',
    () async {
      tools.status = const NearbyStatus(permissionGranted: false);
      t.onStart = () => tools.status = const NearbyStatus();
      expect(await c.start(), isTrue);
      expect(c.nearbyStatus!.permissionGranted, isTrue);
      tools.status = const NearbyStatus(permissionGranted: false);
      expect(await c.scan(), isFalse);
      expect(c.connectionIssue, ConnectionIssue.permission);
      expect(c.connectionIssue!.settingsTarget, NearbySettings.permissions);
      await c.openNearbySettings(NearbySettings.permissions);
      expect(tools.opened, [NearbySettings.permissions]);
      expect(t.scans, 1);
      tools.status = const NearbyStatus();
      await c.refreshNearbyAccess();
      expect(await c.scan(), isTrue);
    },
  );

  test(
    'Native busy, stale and scan failures are actionable without exposing raw exceptions',
    () async {
      t.startFailure = 'P2P_BUSY';
      expect(await c.start(), isFalse);
      expect(c.connectionIssue, ConnectionIssue.busy);
      expect(c.error, isNot(contains('Private')));
      t.startFailure = null;
      await c.start();
      await settle();
      c.peers = [const Peer('old', 'Old')];
      t.scanFailure = 'DISCOVERY';
      expect(await c.scan(), isFalse);
      expect(c.scanning, isFalse);
      expect(c.peers, isEmpty);
      expect(c.connectionIssue, ConnectionIssue.discovery);
      t.connectFailure = 'STALE_PEER';
      await c.store.savePeer('saved', 'Saved name');
      await c.viewHistory((await c.store.conversations()).single);
      expect(await c.connect(const Peer('old', 'Untrusted name')), isFalse);
      expect(c.state, isNot('Connecting'));
      expect(c.selectedPeer, 'saved');
      expect(c.selectedName, 'Saved name');
      expect(c.connectionIssue, ConnectionIssue.stalePeer);
      t.scanFailure = null;
      expect(await c.scan(), isTrue);
      expect(c.error, isNull);
    },
  );

  test(
    'Wi-Fi loss and stopped service reset scanning and advertising with explicit restart',
    () async {
      await c.start();
      c.scanning = true;
      c.peers = [const Peer('old', 'Old')];
      t.bus.add({'type': 'wifi', 'enabled': false});
      await settle();
      expect(c.started || c.scanning, isFalse);
      expect(c.peers, isEmpty);
      expect(c.connectionIssue, ConnectionIssue.wifiOff);
      expect(t.stops, greaterThan(0));
      expect(await c.start(), isTrue);
      t.bus.add({
        'type': 'error',
        'code': 'SERVICE_STOPPED',
        'message': 'Private details',
      });
      await settle();
      expect(c.started, isFalse);
      expect(c.connectionIssue, ConnectionIssue.serviceStopped);
      expect(await c.start(), isTrue);
    },
  );

  test(
    'Duplicate taps and lock during readiness check cannot start a radio action',
    () async {
      tools.gate = Completer<void>();
      final first = c.start();
      await tools.entered.future;
      expect(await c.start(), isFalse);
      expect(c.nearbyBusy, isTrue);
      c.setAppAccess(false);
      tools.gate!.complete();
      expect(await first, isFalse);
      expect(t.starts, 0);
      expect(c.nearbyBusy, isFalse);
      await c.openNearbySettings(NearbySettings.wifi);
      expect(tools.opened, isEmpty);
      c.setAppAccess(true);
      await settle();
      expect(await c.start(), isTrue);
    },
  );

  test(
    'Failed access checks and settings launches have recoverable generic guidance',
    () async {
      tools.failCheck = true;
      await c.refreshNearbyAccess();
      expect(c.connectionIssue, ConnectionIssue.status);
      expect(c.error, isNot(contains('Private')));
      tools.failCheck = false;
      await c.refreshNearbyAccess();
      expect(c.error, isNull);
      tools.failSettings = true;
      await c.openNearbySettings(NearbySettings.wifi);
      expect(c.connectionIssue, ConnectionIssue.settings);
      expect(c.nearbyBusy, isFalse);
      expect(c.error, isNot(contains('Private')));
    },
  );

  test(
    'Connection timeout clears pending verification and can retry without a stale deadline',
    () async {
      c.dispose();
      c = ChatController(
        t,
        DemoStore(),
        nearbyTools: tools,
        connectionTimeout: const Duration(milliseconds: 50),
      );
      await c.initialize();
      await c.start();
      await c.connect(const Peer('pending', 'Pending'));
      await settle();
      expect(c.connectionIssue, ConnectionIssue.timeout);
      expect(c.state, isNot('Connecting'));
      expect(c.localVerified || c.remoteVerified, isFalse);
      c.peers = [const Peer('pending', 'Pending')];
      expect(await c.reconnect(), isTrue);
      await c.disconnect();
      await settle();
      expect(c.connectionIssue, isNull);
    },
  );

  test(
    'Reconnect preserves queued history and waits for both fresh confirmations; vanished address requires scan',
    () async {
      final aTransport = LinkedTransport(), bTransport = LinkedTransport();
      aTransport.other = bTransport;
      bTransport.other = aTransport;
      final a = ChatController(aTransport, DemoStore(), nearbyTools: tools);
      final b = ChatController(bTransport, DemoStore());
      addTearDown(() async {
        a.dispose();
        b.dispose();
        await aTransport.bus.close();
        await bTransport.bus.close();
      });
      await a.initialize();
      await b.initialize();
      await a.start();
      await b.start();
      await a.connect(const Peer('B', 'Bob'));
      await settle();
      await a.confirmCode();
      await b.confirmCode();
      await settle();
      final oldCode = a.code;
      await a.disconnect();
      await settle();
      await a.sendText('Waiting for reconnection', queueIfOffline: true);
      a.peers = [const Peer('B', 'Bob')];
      expect(await a.reconnect(), isTrue);
      await settle();
      expect(a.code, isNot(oldCode));
      expect(a.ready, isFalse);
      await a.confirmCode();
      await settle();
      expect(b.messages, isEmpty);
      expect(a.messages.single.status, 'queued');
      await b.confirmCode();
      await settle();
      expect(a.messages.single.status, 'delivered');
      expect(b.messages.single.text, 'Waiting for reconnection');
      await a.disconnect();
      await settle();
      a.peers = [];
      expect(await a.reconnect(), isFalse);
      expect(a.connectionIssue, ConnectionIssue.stalePeer);
      expect(a.messages.single.status, 'delivered');
    },
  );

  test(
    'Returning from settings detects revoked permission and ends verified session',
    () async {
      final ta = LinkedTransport(), tb = LinkedTransport();
      ta.other = tb;
      tb.other = ta;
      final a = ChatController(ta, DemoStore(), nearbyTools: tools),
          b = ChatController(tb, DemoStore());
      addTearDown(() async {
        a.dispose();
        b.dispose();
        await ta.bus.close();
        await tb.bus.close();
      });
      await a.initialize();
      await b.initialize();
      await a.connect(const Peer('B', 'Bob'));
      await settle();
      await a.confirmCode();
      await b.confirmCode();
      await settle();
      final peer = a.selectedPeer!;
      await a.drafts.load(peer);
      a.drafts.setText(peer, 'Kept after permission change');
      await a.drafts.settled;
      a.setAppForeground(false);
      tools.status = const NearbyStatus(permissionGranted: false);
      a.setAppForeground(true);
      await settle();
      expect(a.ready, isFalse);
      expect(a.connectionIssue, ConnectionIssue.permission);
      expect(await a.store.draft(peer), 'Kept after permission change');
      expect(a.conversations.single.id, peer);
    },
  );

  test(
    'Android channel reads typed status and launches only the requested settings destination',
    () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AndroidNearbyTools.channel, (call) async {
            calls.add(call);
            if (call.method == 'status') {
              return {
                'supported': true,
                'wifiEnabled': true,
                'permissionGranted': false,
                'locationRequired': true,
                'locationEnabled': false,
              };
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(AndroidNearbyTools.channel, null),
      );
      const native = AndroidNearbyTools();
      final status = await native.check();
      expect(status.issue, ConnectionIssue.permission);
      for (final target in NearbySettings.values) {
        await native.openSettings(target);
      }
      expect(calls.skip(1).map((c) => c.arguments['target']), [
        'wifi',
        'permissions',
        'location',
      ]);
      expect(calls.skip(1).every((c) => c.method == 'openSettings'), isTrue);
    },
  );
}
