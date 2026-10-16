import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/models.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'package:local_chat/demo/demo_transport.dart';
import 'package:local_chat/services/chat_controller.dart';
import 'package:local_chat/services/nearby_support.dart';
import 'package:local_chat/services/reconnect_preferences.dart';
import 'package:local_chat/services/transport.dart';
import 'group_test_support.dart';

class RetryStorage extends MemoryReconnectStorage {
  bool failRead = false, failWrite = false;
  Completer<void>? gate;
  @override
  Future<String?> read() async {
    if (failRead) throw StateError('Private read failure');
    return super.read();
  }

  @override
  Future<void> write(String value) async {
    await gate?.future;
    if (failWrite) throw StateError('Private write failure');
    await super.write(value);
  }
}

class RetryNearbyTools implements NearbyTools {
  NearbyStatus status = const NearbyStatus();
  bool fail = false;
  int checks = 0;
  Completer<void>? gate, entered;
  @override
  Future<NearbyStatus> check() async {
    checks++;
    if (entered?.isCompleted == false) entered!.complete();
    await gate?.future;
    if (fail) throw StateError('Private check failure');
    return status;
  }

  @override
  Future<void> openSettings(NearbySettings target) async =>
      throw StateError('No automatic settings prompt');
}

class RetryTransport implements Transport {
  RetryTransport() {
    _listen();
  }
  DemoTransport demo = DemoTransport();
  StreamSubscription<Map<String, dynamic>>? subscription;
  final bus = StreamController<Map<String, dynamic>>.broadcast();
  final addresses = <String>[];
  final frames = <String>[];
  int failures = 0, disconnects = 0, scans = 0;
  bool quiet = false, replaceIdentity = false;
  bool failDisconnect = false;
  Completer<void>? connectGate, connectEntered;
  void _listen() => subscription = demo.events.listen(bus.add);
  @override
  Stream<Map<String, dynamic>> get events => bus.stream;
  @override
  Future<void> start(String name) => demo.start(name);
  @override
  Future<void> scan() async {
    scans++;
    bus.add({
      'type': 'peers',
      'peers': [
        {'address': 'demo-ava', 'name': 'Ava'},
      ],
    });
  }

  @override
  Future<void> connect(String address) async {
    addresses.add(address);
    if (connectEntered?.isCompleted == false) connectEntered!.complete();
    await connectGate?.future;
    if (failures > 0) {
      failures--;
      throw PlatformException(
        code: 'P2P_BUSY',
        message: 'Private radio failure',
      );
    }
    if (quiet) return;
    if (replaceIdentity) {
      await subscription?.cancel();
      demo = DemoTransport();
      _listen();
      await demo.start('Local');
      replaceIdentity = false;
    }
    await demo.connect(address);
  }

  @override
  Future<void> send(String frame) async {
    frames.add(frame);
    await demo.send(frame);
  }

  Future<void> lose({bool nativeError = false}) async {
    if (nativeError) bus.add({'type': 'error', 'code': 'CONNECTION_LOST'});
    await demo.disconnect();
    bus.add({'type': 'disconnected'});
  }

  @override
  Future<void> disconnect() async {
    disconnects++;
    if (failDisconnect) {
      throw PlatformException(
        code: 'SERVICE_STOPPED',
        message: 'Private native close failure',
      );
    }
    await demo.disconnect();
    bus.add({'type': 'disconnected'});
  }

  @override
  Future<void> stop() => demo.stop();
}

Future<void> retryUntil(bool Function() done) async {
  for (var i = 0; i < 500 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(done(), isTrue);
}

Future<ChatController> retryController(
  RetryTransport transport, {
  RetryStorage? storage,
  RetryNearbyTools? tools,
  bool enabled = true,
  bool verify = true,
  List<Duration> delays = const [
    Duration(milliseconds: 40),
    Duration(milliseconds: 80),
    Duration(milliseconds: 120),
  ],
  Duration timeout = const Duration(seconds: 2),
}) async {
  final c = ChatController(
    transport,
    DemoStore(),
    isDemo: true,
    nearbyTools: tools ?? RetryNearbyTools(),
    reconnectPreferences: ReconnectPreferences(storage ?? RetryStorage()),
    reconnectDelays: delays,
    connectionTimeout: timeout,
    groupTransport: FakeGroupTransport(GroupNetwork()),
  );
  await c.initialize();
  if (enabled) await c.setAutomaticReconnectEnabled(true);
  await c.start();
  await retryUntil(() => c.peers.isNotEmpty);
  await c.connect(c.peers.single);
  await retryUntil(() => c.code != null);
  if (verify) {
    await c.confirmCode();
    await retryUntil(() => c.ready);
  }
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final controllers = <ChatController>[];
  Future<ChatController> keep(Future<ChatController> value) async {
    final c = await value;
    controllers.add(c);
    return c;
  }

  tearDown(() {
    for (final c in controllers) {
      c.dispose();
    }
    controllers.clear();
  });

  test(
    'Preference defaults off, persists opt-in and rejects malformed/read failures',
    () async {
      final storage = RetryStorage();
      final p = ReconnectPreferences(storage);
      await p.initialize();
      expect(p.enabled, isFalse);
      await p.setEnabled(true);
      expect(jsonDecode(storage.value!), {'v': 1, 'enabled': true});
      final restarted = ReconnectPreferences(storage);
      await restarted.initialize();
      expect(restarted.enabled, isTrue);
      p.dispose();
      restarted.dispose();
      for (final value in [
        'bad',
        '{}',
        '{"v":2,"enabled":true}',
        '{"v":1,"enabled":1}',
        '{"v":1,"enabled":true,"extra":0}',
      ]) {
        final p = ReconnectPreferences(RetryStorage()..value = value);
        await p.initialize();
        expect(p.enabled, isFalse);
        expect(p.error, isNotNull);
        p.dispose();
      }
      final failed = ReconnectPreferences(RetryStorage()..failRead = true);
      await failed.initialize();
      expect(failed.enabled, isFalse);
      expect(failed.loading, isFalse);
      failed.dispose();
    },
  );
  test(
    'Preference failed/overlapping saves retain applied value and late disposal is harmless',
    () async {
      final storage = RetryStorage();
      final p = ReconnectPreferences(storage);
      await p.initialize();
      storage.failWrite = true;
      expect(await p.setEnabled(true), isFalse);
      expect(p.enabled, isFalse);
      expect(p.error, isNot(contains('Private')));
      storage.failWrite = false;
      storage.gate = Completer<void>();
      final pending = p.setEnabled(true);
      expect(await p.setEnabled(false), isFalse);
      p.dispose();
      storage.gate!.complete();
      expect(await pending, isTrue);
      expect(p.enabled, isFalse);
    },
  );
  test('Off by default never reconnects after a verified loss', () async {
    final t = RetryTransport();
    final c = await keep(retryController(t, enabled: false));
    await t.lose();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(t.addresses.length, 1);
    expect(c.automaticReconnectActive, isFalse);
  });
  test(
    'Re-enabling the setting arms the still-live selected verified connection',
    () async {
      final t = RetryTransport();
      final c = await keep(retryController(t));
      expect(await c.setAutomaticReconnectEnabled(false), isTrue);
      expect(await c.setAutomaticReconnectEnabled(true), isTrue);
      await t.lose();
      await retryUntil(() => t.addresses.length == 2 && c.code != null);
      expect(c.automaticReconnectActive, isTrue);
      expect(c.ready, isFalse);
    },
  );
  test(
    'Reconnect pins identity and waits for a fresh comparison before draining the original outbox',
    () async {
      final t = RetryTransport();
      final c = await keep(retryController(t));
      final identity = c.connectedPeer!, oldCode = c.code!;
      await t.lose(nativeError: true);
      await retryUntil(() => c.automaticReconnectActive);
      expect(
        await c.sendText('Queued while offline', queueIfOffline: true),
        isTrue,
      );
      await c.drafts.load(identity);
      c.drafts.setText(identity, 'Keep this draft');
      await c.drafts.settled;
      await retryUntil(() => t.addresses.length == 2 && c.code != null);
      expect(c.connectedPeer, identity);
      expect(c.code, isNot(oldCode));
      expect(c.ready, isFalse);
      expect(c.automaticReconnectStatus, contains('Compare the fresh code'));
      final queued = (await c.store.messages(
        identity,
      )).singleWhere((m) => m.outgoing);
      expect(queued.status, 'queued');
      expect(t.frames.where((f) => jsonDecode(f)['kind'] == 'hello').length, 2);
      await c.confirmCode();
      await retryUntil(
        () =>
            c.ready &&
            c.messages.any((m) => m.id == queued.id && m.status == 'delivered'),
      );
      expect(c.messages.singleWhere((m) => m.outgoing).id, queued.id);
      expect(c.drafts.textFor(identity), 'Keep this draft');
      expect(c.automaticReconnectActive, isFalse);
    },
  );
  test(
    'Three failed attempts exhaust the burst and duplicate loss events cannot reset its budget',
    () async {
      final t = RetryTransport();
      final c = await keep(retryController(t));
      t.failures = 20;
      await t.lose(nativeError: true);
      await retryUntil(
        () => t.addresses.length == 4 && !c.automaticReconnectActive,
      );
      await t.lose();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(t.addresses, everyElement('demo-ava'));
      expect(t.addresses.length, 4);
      expect(c.automaticReconnectStatus, contains('after 3 attempts'));
      expect(c.error, isNot(contains('Private')));
    },
  );
  test(
    'A connection request that never forms times out within the same three-attempt budget',
    () async {
      final t = RetryTransport();
      final c = await keep(
        retryController(t, timeout: const Duration(milliseconds: 150)),
      );
      t.quiet = true;
      await t.lose();
      await retryUntil(
        () => t.addresses.length == 4 && !c.automaticReconnectActive,
      );
      expect(c.ready, isFalse);
      expect(c.automaticReconnectStatus, contains('3 attempts'));
    },
  );
  test(
    'Fresh-code verification timeout ends the burst without another automatic pairing',
    () async {
      final t = RetryTransport();
      final c = await keep(
        retryController(t, timeout: const Duration(milliseconds: 200)),
      );
      await t.lose();
      await retryUntil(() => t.addresses.length == 2 && c.code != null);
      await retryUntil(() => !c.automaticReconnectActive);
      expect(c.connectionIssue, ConnectionIssue.timeout);
      expect(t.addresses.length, 2);
      expect(c.ready, isFalse);
    },
  );
  test(
    'A vanished address never falls back to a matching public name',
    () async {
      final t = RetryTransport();
      final c = await keep(retryController(t));
      await t.lose();
      await retryUntil(() => c.automaticReconnectActive);
      c.peers = [const Peer('different-address', 'Ava')];
      await retryUntil(() => !c.automaticReconnectActive);
      expect(t.addresses.length, 1);
      expect(c.connectionIssue, ConnectionIssue.stalePeer);
      expect(c.automaticReconnectStatus, contains('Scan again'));
    },
  );
  test(
    'A changed identity at the same address closes before displaying or confirming its code',
    () async {
      final t = RetryTransport();
      final c = await keep(retryController(t));
      final original = c.connectedPeer;
      t.replaceIdentity = true;
      await t.lose();
      await retryUntil(
        () => t.addresses.length == 2 && !c.automaticReconnectActive,
      );
      expect(c.ready, isFalse);
      expect(c.code, isNull);
      expect(c.directVerification, isNull);
      expect(c.automaticReconnectStatus, contains('identity changed'));
      expect((await c.store.conversations()).map((p) => p.id), [original]);
    },
  );
  test(
    'Cancel while waiting prevents attempts, and an old token cannot cancel a later connection',
    () async {
      final t = RetryTransport();
      final c = await keep(retryController(t));
      await t.lose();
      await retryUntil(() => c.automaticReconnectActive);
      final old = c.automaticReconnectToken!;
      await c.cancelAutomaticReconnect(token: old);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(t.addresses.length, 1);
      await c.connect(c.peers.single);
      await retryUntil(() => c.code != null);
      await c.confirmCode();
      await retryUntil(() => c.ready);
      await c.cancelAutomaticReconnect(token: old);
      expect(c.ready, isTrue);
    },
  );
  for (final lock in [false, true]) {
    test(
      '${lock ? 'Lock' : 'Background'} during readiness invalidates queued retries even after a quick return',
      () async {
        final t = RetryTransport(), tools = RetryNearbyTools();
        final c = await keep(retryController(t, tools: tools));
        tools.gate = Completer<void>();
        tools.entered = Completer<void>();
        await t.lose();
        await tools.entered!.future;
        if (lock) {
          c.setAppAccess(false);
          c.setAppAccess(true);
        } else {
          c.setAppForeground(false);
          c.setAppForeground(true);
        }
        tools.gate!.complete();
        await Future<void>.delayed(const Duration(milliseconds: 350));
        expect(t.addresses.length, 1);
        expect(c.automaticReconnectActive, isFalse);
        expect(c.ready, isFalse);
      },
    );
  }
  test(
    'Cancel pending native connect rejects its late connection and confirmation callbacks',
    () async {
      final t = RetryTransport();
      final c = await keep(retryController(t));
      t.connectGate = Completer<void>();
      t.connectEntered = Completer<void>();
      await t.lose();
      await t.connectEntered!.future;
      final stopping = c.cancelAutomaticReconnect();
      expect(c.automaticReconnectActive, isFalse);
      t.connectGate!.complete();
      await stopping;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(c.ready, isFalse);
      expect(c.directVerification, isNull);
      expect(await c.confirmCode(), isFalse);
      expect(t.addresses.length, 2);
    },
  );
  test(
    'Manual disconnect and an unverified initial loss never start automatic pairing',
    () async {
      final t = RetryTransport();
      final c = await keep(retryController(t));
      await c.disconnect();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(t.addresses.length, 1);
      await c.connect(c.peers.single);
      await retryUntil(() => c.code != null);
      await t.lose();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(t.addresses.length, 2);
      expect(c.automaticReconnectActive, isFalse);
    },
  );
  test(
    'Prerequisite and status failures stop retries without requesting permissions or opening settings',
    () async {
      for (final status in [
        const NearbyStatus(wifiEnabled: false),
        const NearbyStatus(permissionGranted: false),
        const NearbyStatus(supported: false),
        const NearbyStatus(locationRequired: true, locationEnabled: false),
      ]) {
        final t = RetryTransport(), tools = RetryNearbyTools();
        final c = await keep(retryController(t, tools: tools));
        tools.status = status;
        await t.lose();
        await retryUntil(
          () =>
              c.automaticReconnectStatus != null && !c.automaticReconnectActive,
        );
        expect(t.addresses.length, 1);
        expect(c.connectionIssue, status.issue);
      }
      final t = RetryTransport(), tools = RetryNearbyTools();
      final c = await keep(retryController(t, tools: tools));
      tools.fail = true;
      await t.lose();
      await retryUntil(
        () => c.automaticReconnectStatus != null && !c.automaticReconnectActive,
      );
      expect(c.connectionIssue, ConnectionIssue.status);
      expect(t.addresses.length, 1);
    },
  );
  test(
    'A failed disable save still cancels the current burst without silently resuming it',
    () async {
      final t = RetryTransport(), storage = RetryStorage();
      final c = await keep(retryController(t, storage: storage));
      await t.lose();
      await retryUntil(() => c.automaticReconnectActive);
      storage.failWrite = true;
      expect(await c.setAutomaticReconnectEnabled(false), isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(c.reconnectPreferences.enabled, isTrue);
      expect(c.automaticReconnectActive, isFalse);
      expect(t.addresses.length, 1);
      storage.failWrite = false;
      expect(await c.setAutomaticReconnectEnabled(false), isTrue);
    },
  );
  test(
    'Group mode and deleting the retry target cancel waiting automatic work',
    () async {
      final t = RetryTransport();
      final c = await keep(retryController(t));
      await t.lose();
      await retryUntil(() => c.automaticReconnectActive);
      expect(await c.groups.host('Group mode'), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(c.automaticReconnectActive, isFalse);
      expect(t.addresses.length, 1);
      await c.start();
      await retryUntil(() => c.peers.isNotEmpty);
      await c.connect(c.peers.single);
      await retryUntil(() => c.code != null);
      await c.confirmCode();
      await retryUntil(() => c.ready);
      final peer = c.connectedPeer!;
      await t.lose();
      await retryUntil(() => c.automaticReconnectActive);
      expect(await c.deleteConversation(peer), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(t.addresses.length, 2);
      expect(c.automaticReconnectActive, isFalse);
    },
  );
  test(
    'Native cleanup failure stops a failed attempt with generic recovery instead of stranding its budget',
    () async {
      final t = RetryTransport();
      final c = await keep(retryController(t));
      t.failures = 20;
      t.failDisconnect = true;
      await t.lose();
      await retryUntil(
        () => t.addresses.length == 2 && !c.automaticReconnectActive,
      );
      expect(c.connectionIssue, ConnectionIssue.serviceStopped);
      expect(c.started, isFalse);
      expect(c.error, isNot(contains('Private')));
      expect(c.ready, isFalse);
    },
  );
  test(
    'Cancel during verification tolerates failed native cleanup without exposing a usable code',
    () async {
      final t = RetryTransport();
      final c = await keep(retryController(t));
      await t.lose();
      await retryUntil(() => t.addresses.length == 2 && c.code != null);
      final request = c.directVerification!;
      t.failDisconnect = true;
      await c.cancelAutomaticReconnect();
      expect(c.automaticReconnectActive, isFalse);
      expect(c.code, isNull);
      expect(c.connectionIssue, ConnectionIssue.serviceStopped);
      expect(await c.confirmCode(request: request), isFalse);
      t.bus.add({'type': 'frame', 'frame': 'late rejected frame'});
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(c.error, isNot(contains('Private')));
    },
  );
  for (final loseWhileAway in [false, true]) {
    test(
      'Queued loss ${loseWhileAway ? 'during' : 'before'} background cannot start retries after return',
      () async {
        final t = RetryTransport(), tools = RetryNearbyTools();
        final c = await keep(retryController(t, tools: tools));
        tools.gate = Completer<void>();
        tools.entered = Completer<void>();
        final checking = c.refreshNearbyAccess();
        await tools.entered!.future;
        if (loseWhileAway) c.setAppForeground(false);
        await t.lose();
        // Capture the lifecycle revision while the controller queue is held.
        await Future<void>.delayed(Duration.zero);
        if (!loseWhileAway) c.setAppForeground(false);
        c.setAppForeground(true);
        tools.gate!.complete();
        await checking;
        await Future<void>.delayed(const Duration(milliseconds: 350));
        expect(c.automaticReconnectActive, isFalse);
        expect(t.addresses.length, 1);
      },
    );
  }
  test(
    'A reciprocal incoming reconnect cancels the waiting timer and still requires fresh verification',
    () async {
      final t = RetryTransport();
      final c = await keep(retryController(t));
      final oldCode = c.code;
      await t.lose();
      await retryUntil(() => c.automaticReconnectActive);
      await t.demo.connect('demo-ava');
      await retryUntil(() => c.code != null);
      expect(c.code, isNot(oldCode));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(t.addresses.length, 1);
      expect(c.ready, isFalse);
      expect(c.automaticReconnectStatus, contains('Compare the fresh code'));
      await c.confirmCode();
      await retryUntil(() => c.ready);
      expect(c.automaticReconnectActive, isFalse);
    },
  );
  test(
    'Scan overrides a waiting burst without scheduling another connection',
    () async {
      final t = RetryTransport();
      final c = await keep(retryController(t));
      await t.lose();
      await retryUntil(() => c.automaticReconnectActive);
      expect(await c.scan(), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(t.addresses.length, 1);
      expect(c.automaticReconnectActive, isFalse);
      expect(c.canReconnect, isTrue);
    },
  );
  test(
    'A restarted opt-in has no remembered target and incoming sessions do not create an automatic target',
    () async {
      final storage = RetryStorage()..value = '{"v":1,"enabled":true}';
      final t = RetryTransport();
      final c = ChatController(
        t,
        DemoStore(),
        isDemo: true,
        reconnectPreferences: ReconnectPreferences(storage),
        reconnectDelays: const [
          Duration(milliseconds: 40),
          Duration(milliseconds: 80),
          Duration(milliseconds: 120),
        ],
      );
      controllers.add(c);
      await c.initialize();
      expect(c.reconnectPreferences.enabled, isTrue);
      await c.start();
      // A remote phone initiates; no device was selected in this controller.
      await t.demo.connect('demo-ava');
      await retryUntil(() => c.code != null);
      await c.confirmCode();
      await retryUntil(() => c.ready);
      await t.lose();
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(t.addresses, isEmpty);
      expect(c.automaticReconnectActive, isFalse);
    },
  );
  test('Backup data excludes the opt-in, retry target and timers', () async {
    final t = RetryTransport();
    final c = await keep(retryController(t));
    await t.lose();
    await retryUntil(() => c.automaticReconnectActive);
    final data = (await c.backupSnapshot()).toJson();
    expect(data.containsKey('automaticReconnect'), isFalse);
    expect(jsonEncode(data), isNot(contains('automatic_reconnect_v1')));
    expect(jsonEncode(data), isNot(contains('reconnectDelays')));
    expect(c.reconnectPreferences.enabled, isTrue);
  });
  test(
    'Security failures and disposal never create a reconnect loop',
    () async {
      final t = RetryTransport(), tools = RetryNearbyTools();
      final c = await keep(retryController(t, tools: tools));
      t.bus.add({'type': 'frame', 'frame': 'invalid'});
      await retryUntil(() => c.connectionIssue == ConnectionIssue.security);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(t.addresses.length, 1);
      await c.connect(c.peers.single);
      await retryUntil(() => c.code != null);
      await c.confirmCode();
      await retryUntil(() => c.ready);
      tools.gate = Completer<void>();
      tools.entered = Completer<void>();
      await t.lose();
      await tools.entered!.future;
      controllers.remove(c);
      c.dispose();
      tools.gate!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(t.addresses.length, 2);
    },
  );
}
