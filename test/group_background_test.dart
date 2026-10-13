import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/models.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'package:local_chat/demo/demo_transport.dart';
import 'package:local_chat/services/background_connection.dart';
import 'package:local_chat/services/chat_controller.dart';
import 'package:local_chat/services/chat_notifications.dart';
import 'background_connection_test.dart' show GatedBackgroundPlatform;
import 'group_test_support.dart';

class GroupBackgroundPlatform extends GatedBackgroundPlatform {
  int attempts = 0;
  final processed = <int>[];
  final updates = <(int, List<String>)>[];
  Completer<void>? syncGate;
  @override
  Future<Map<String, dynamic>> start(int? generation) async {
    attempts++;
    return super.start(generation);
  }

  @override
  Future<void> setGroupLinks(int generation, List<String> links) async {
    await syncGate?.future;
    updates.add((generation, List.of(links)));
    await super.setGroupLinks(generation, links);
  }

  @override
  Future<void> frameProcessed(int generation) async =>
      processed.add(generation);
}

class BackgroundRadio extends DemoTransport {
  final bus = StreamController<Map<String, dynamic>>.broadcast();
  late final StreamSubscription<Map<String, dynamic>> _forward;
  BackgroundRadio() {
    _forward = super.events.listen(bus.add);
  }
  @override
  Stream<Map<String, dynamic>> get events => bus.stream;
  Future<void> close() async {
    await _forward.cancel();
    await bus.close();
  }
}

class GroupBackgroundRig {
  final net = GroupNetwork();
  final phones = <ChatController>[];
  final platforms = <GroupBackgroundPlatform>[];
  final radios = <BackgroundRadio>[];
  final groupRadios = <FakeGroupTransport>[];
  final alerts = <MemoryNotificationPlatform>[];
  Future<ChatController> phone(String name, {bool enabled = true}) async {
    final platform = GroupBackgroundPlatform(), radio = BackgroundRadio();
    final groups = FakeGroupTransport(net)..holdReceived = true;
    final notifications = MemoryNotificationPlatform();
    final c = ChatController(
      radio,
      DemoStore(),
      isDemo: true,
      groupTransport: groups,
      background: BackgroundConnection(platform),
      notifications: ChatNotifications(notifications),
    );
    await c.initialize();
    await c.background.initialize();
    await c.notifications.initialize();
    c.store.name = name;
    await c.notifications.setEnabled(true);
    await c.notifications.setPreviews(true);
    if (enabled) await c.setBackgroundEnabled(true);
    phones.add(c);
    platforms.add(platform);
    radios.add(radio);
    groupRadios.add(groups);
    alerts.add(notifications);
    net.controllers.add(c.groups);
    return c;
  }

  Future<void> settle() async {
    await net.settle();
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }

  Future<void> close({bool stopGroups = true}) async {
    if (stopGroups) {
      for (final c in phones) {
        await c.groups.stop();
      }
    }
    for (final c in phones) {
      c.dispose();
    }
    for (final radio in radios) {
      await radio.close();
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GroupBackgroundRig rig;
  late ChatController host, guest;
  setUp(() async {
    rig = GroupBackgroundRig();
    host = await rig.phone('Host');
    guest = await rig.phone('Guest');
    await host.groups.host('Private room');
  });
  tearDown(() => rig.close());

  test(
    'empty hosting, discovery and one-sided verification never start protection',
    () async {
      expect(rig.platforms.every((p) => p.starts == 0), isTrue);
      await rig.net.join(guest.groups, verify: false);
      expect(rig.platforms.every((p) => p.starts == 0), isTrue);
      await host.groups.confirm(host.groups.links.keys.single);
      await rig.settle();
      expect(rig.platforms.every((p) => p.starts == 0), isTrue);
      await guest.groups.confirm(guest.groups.links.keys.single);
      await rig.settle();
      expect(host.background.active && guest.background.active, isTrue);
      expect(
        host.background.protectsGroup && guest.background.protectsGroup,
        isTrue,
      );
      expect(rig.platforms[0].groupLinks, host.groups.links.keys.toList());
      expect(rig.platforms[0].starts, 1);
    },
  );

  test(
    'admission completed while locked waits for foreground unlock',
    () async {
      await rig.net.join(guest.groups, verify: false);
      await guest.groups.confirm(guest.groups.links.keys.single);
      guest.setAppAccess(false);
      guest.setAppForeground(false);
      await host.groups.confirm(host.groups.links.keys.single);
      await rig.settle();
      expect(guest.groups.backgroundReady, isTrue);
      expect(rig.platforms[1].starts, 0);
      guest.setAppForeground(true);
      await rig.settle();
      expect(rig.platforms[1].starts, 0);
      guest.setAppAccess(true);
      await rig.settle();
      expect(rig.platforms[1].starts, 1);
    },
  );

  test(
    'locked host receives signed text, relays to another guest and preserves privacy and drafts',
    () async {
      await rig.net.join(guest.groups);
      final other = await rig.phone('Other');
      await rig.net.join(other.groups);
      await rig.settle();
      final id = host.groups.active!.id;
      await host.drafts.load(id, group: true);
      host.drafts.setText(id, 'Unfinished', group: true);
      await host.drafts.settled;
      await host.groups.setArchived(id, true);
      await host.groups.setPinned(id, true);
      host.groups.setVisible(Object(), id, true);
      host.setAppForeground(false);
      host.setAppAccess(false);
      await rig.settle();
      expect(await host.groups.sendText('Blocked new send'), isFalse);
      expect(host.groups.images.canSend || host.groups.files.canSend, isFalse);
      expect(await guest.groups.sendText('Private relayed text'), isTrue);
      await rig.settle();
      expect(host.groups.active!.messages.single.text, 'Private relayed text');
      expect(other.groups.active!.messages.single.text, 'Private relayed text');
      expect(
        guest.groups.active!.messages.single.receipts.values.every(
          (s) => s == 'received',
        ),
        isTrue,
      );
      expect(host.groups.active!.unread, 1);
      expect(
        host.groups.active!.archived && host.groups.active!.pinned,
        isTrue,
      );
      expect(await host.store.groupDraft(id), 'Unfinished');
      expect(rig.alerts[0].alerts.values.single.text, isNull);
      expect(rig.alerts[0].alerts.values.single.name, isNull);
      expect(host.background.active, isTrue);
      expect(rig.platforms[0].starts, 1);
      expect(rig.platforms[0].processed, isNotEmpty);
    },
  );

  test(
    'locked guest receives and acknowledges while visible-chat read and originating sends stay gated',
    () async {
      await rig.net.join(guest.groups);
      await rig.settle();
      guest.groups.setVisible(Object(), guest.groups.active!.id, true);
      guest.setAppAccess(false);
      guest.setAppForeground(false);
      await rig.settle();
      await host.groups.sendText('Screen-off message');
      await rig.settle();
      expect(guest.groups.active!.unread, 1);
      expect(
        host.groups.active!.messages.single.receipts[guest.groups.selfId],
        'received',
      );
      expect(rig.alerts[1].alerts.values.single.text, isNull);
      expect(await guest.groups.sendText('Do not send'), isFalse);
      expect(guest.background.active, isTrue);
      guest.setAppForeground(true);
      await rig.settle();
      expect(guest.groups.active!.unread, 1);
      guest.setAppAccess(true);
      await rig.settle();
      expect(guest.groups.active!.unread, 0);
    },
  );

  test(
    'turning protection off preserves foreground group messaging and opt-in can start again',
    () async {
      await rig.net.join(guest.groups);
      await rig.settle();
      await host.setBackgroundEnabled(false);
      await rig.settle();
      expect(host.background.active, isFalse);
      expect(host.groups.connected, isTrue);
      await guest.groups.sendText('Still delivered');
      await rig.settle();
      expect(host.groups.active!.messages.single.text, 'Still delivered');
      expect(rig.platforms[0].starts, 1);
      await host.setBackgroundEnabled(true);
      await rig.settle();
      expect(host.background.active, isTrue);
      expect(rig.platforms[0].starts, 2);
    },
  );

  test(
    'notification Stop while locked ends the room and disables preference without losing history or drafts',
    () async {
      await rig.net.join(guest.groups);
      await host.groups.sendText('Keep history');
      await rig.settle();
      final id = host.groups.active!.id,
          token = host.groups.transportGeneration!;
      await host.store.saveGroupDraft(id, 'Keep draft');
      host.setAppForeground(false);
      host.setAppAccess(false);
      rig.platforms[0].enabled = false;
      rig.platforms[0].active = false;
      rig.radios[0].bus.add({
        'type': 'backgroundStatus',
        'generation': token,
        'enabled': false,
        'active': false,
        'allowed': true,
        'reason': 'user',
      });
      rig.radios[0].bus.add({
        'type': 'backgroundStopped',
        'generation': token,
        'reason': 'user',
      });
      await rig.settle();
      expect(host.groups.running || guest.groups.running, isFalse);
      expect(host.background.enabled, isFalse);
      expect(host.groups.histories.single.messages.single.text, 'Keep history');
      expect(await host.store.groupDraft(id), 'Keep draft');
      host.setAppForeground(true);
      host.setAppAccess(true);
      await rig.settle();
      expect(rig.platforms[0].starts, 1);
      expect(host.background.notice, contains('notification'));
    },
  );

  test(
    'one member leaving keeps protection; losing the last verified member ends it despite a pending join',
    () async {
      await rig.net.join(guest.groups);
      final other = await rig.phone('Other');
      await rig.net.join(other.groups);
      await rig.settle();
      await guest.groups.stop();
      await rig.settle();
      expect(host.background.active, isTrue);
      expect(rig.platforms[0].groupLinks, host.groups.links.keys.toList());
      final pending = await rig.phone('Pending');
      await rig.net.join(pending.groups, verify: false);
      await other.groups.stop();
      await rig.settle();
      expect(host.groups.running, isTrue);
      expect(host.groups.backgroundReady, isFalse);
      expect(host.groups.links, isNotEmpty);
      expect(host.background.active, isFalse);
      expect(host.background.notice, contains('Group chats'));
      expect(rig.platforms[0].starts, 1);
    },
  );

  test(
    'startup failure leaves messaging usable and retries only on an explicit recovery trigger',
    () async {
      rig.platforms[0].fail = true;
      await rig.net.join(guest.groups);
      await rig.settle();
      expect(host.background.active, isFalse);
      expect(host.background.error, isNotNull);
      final attempts = rig.platforms[0].attempts;
      await guest.groups.sendText('Foreground still works');
      await rig.settle();
      expect(
        host.groups.active!.messages.single.text,
        'Foreground still works',
      );
      expect(rig.platforms[0].attempts, attempts);
      rig.platforms[0].fail = false;
      await host.retryBackground();
      await rig.settle();
      expect(host.background.active, isTrue);
      expect(host.background.error, isNull);
    },
  );

  test(
    'blocked Connection notifications leave the group usable and grant plus Retry starts protection',
    () async {
      rig.platforms[0].allowed = false;
      await rig.net.join(guest.groups);
      await rig.settle();
      expect(host.groups.connected, isTrue);
      expect(host.background.active, isFalse);
      expect(host.background.error, contains('Connection channel'));
      rig.platforms[0].allowed = true;
      await host.retryBackground();
      await rig.settle();
      expect(host.background.active, isTrue);
    },
  );

  test(
    'background hosting keeps pending guests outside its protected verified links until fresh approval',
    () async {
      await rig.net.join(guest.groups);
      await rig.settle();
      final protected = List.of(rig.platforms[0].groupLinks);
      host.setAppAccess(false);
      host.setAppForeground(false);
      final pending = await rig.phone('Pending');
      await rig.net.join(pending.groups, verify: false);
      await pending.groups.confirm(pending.groups.links.keys.single);
      final link = host.groups.links.values.singleWhere(
        (l) => l.session.peerId == pending.groups.selfId,
      );
      await host.groups.confirm(link.id);
      await rig.settle();
      expect(link.localVerified || link.admitted, isFalse);
      expect(rig.platforms[0].groupLinks, protected);
      host.setAppForeground(true);
      host.setAppAccess(true);
      await rig.settle();
      await host.groups.confirm(link.id);
      await rig.settle();
      expect(link.admitted, isTrue);
      expect(rig.platforms[0].groupLinks.length, 2);
      expect(rig.platforms[0].starts, 1);
    },
  );

  test(
    'deleting the active group ends protection and keeps unrelated direct history and drafts',
    () async {
      await rig.net.join(guest.groups);
      await rig.settle();
      await host.store.savePeer('other', 'Other friend');
      await host.store.saveDraft('other', 'Other draft');
      final id = host.groups.active!.id;
      await host.groups.delete(id);
      await rig.settle();
      expect(host.background.active || host.groups.running, isFalse);
      expect(host.background.enabled, isTrue);
      expect(host.groups.histories, isEmpty);
      expect((await host.store.conversations()).single.id, 'other');
      expect(await host.store.draft('other'), 'Other draft');
    },
  );

  test('loss during pending start cannot protect an ended room', () async {
    rig.platforms[0].gate = Completer<void>();
    await rig.net.join(guest.groups);
    await rig.settle();
    expect(host.background.busy, isTrue);
    await host.groups.stop();
    rig.platforms[0].gate!.complete();
    await rig.settle();
    expect(host.background.active || rig.platforms[0].active, isFalse);
    expect(host.groups.running, isFalse);
  });

  test(
    'a foreground-authorized group start may complete after backgrounding without authorizing new sends',
    () async {
      rig.platforms[0].gate = Completer<void>();
      await rig.net.join(guest.groups);
      await rig.settle();
      host.setAppForeground(false);
      host.setAppAccess(false);
      rig.platforms[0].gate!.complete();
      await rig.settle();
      expect(host.background.active, isTrue);
      expect(await host.groups.sendText('Blocked'), isFalse);
    },
  );

  test(
    'room replacement and stale native Stop/status cannot affect the newer protected room',
    () async {
      await rig.net.join(guest.groups);
      await rig.settle();
      final old = host.groups.transportGeneration!;
      final history = host.groups.active!;
      await host.groups.host(history.title, previous: history);
      await rig.net.join(guest.groups);
      await rig.settle();
      final current = host.groups.transportGeneration!;
      expect(current, isNot(old));
      rig.radios[0].bus.add({
        'type': 'backgroundStatus',
        'generation': old,
        'active': false,
        'enabled': false,
        'allowed': true,
        'reason': 'user',
      });
      rig.radios[0].bus.add({
        'type': 'backgroundStopped',
        'generation': old,
        'reason': 'user',
      });
      await rig.settle();
      expect(host.groups.transportGeneration, current);
      expect(host.background.enabled && host.background.active, isTrue);
      await guest.groups.sendText('New room text');
      await rig.settle();
      expect(host.groups.active!.messages.single.text, 'New room text');
    },
  );

  test(
    'late direct disconnect cleanup cannot stop protected group connections',
    () async {
      await rig.net.join(guest.groups);
      await rig.settle();
      rig.radios[0].bus.add({'type': 'disconnected'});
      rig.radios[0].bus.add({
        'type': 'backgroundStopped',
        'generation': 123,
        'reason': 'user',
      });
      await rig.settle();
      expect(host.background.active, isTrue);
      expect(host.groups.connected, isTrue);
    },
  );

  test(
    'switching to direct and back closes the previous protection and requires fresh group confirmations',
    () async {
      await rig.net.join(guest.groups);
      await rig.settle();
      final saved = host.groups.active!;
      await host.start();
      await host.connect(const Peer('demo-ava', 'Ava'));
      await rig.settle();
      expect(host.groups.running, isFalse);
      expect(host.background.active, isFalse);
      await host.confirmCode();
      await rig.settle();
      expect(host.ready, isTrue);
      expect(host.background.active, isTrue);
      expect(host.background.protectsGroup, isFalse);
      await host.groups.host(saved.title, previous: saved);
      await rig.settle();
      expect(host.background.active, isFalse);
      await rig.net.join(guest.groups);
      await rig.settle();
      expect(host.background.active && host.background.protectsGroup, isTrue);
      expect(host.ready, isFalse);
    },
  );

  test(
    'held frames release after ignored stale/unknown and malformed messages',
    () async {
      await rig.net.join(guest.groups);
      await rig.settle();
      rig.platforms[0].processed.clear();
      final token = host.groups.transportGeneration!,
          link = host.groups.links.keys.single;
      rig.groupRadios[0].bus.add({
        'type': 'frame',
        'generation': token - 1,
        'held': true,
        'link': link,
        'frame': 'stale',
      });
      rig.groupRadios[0].bus.add({
        'type': 'frame',
        'generation': token,
        'held': true,
        'link': 'missing',
        'frame': 'ignored',
      });
      await rig.settle();
      expect(rig.platforms[0].processed, [token - 1, token]);
      expect(host.groups.connected, isTrue);
      rig.groupRadios[0].bus.add({
        'type': 'frame',
        'generation': token,
        'held': true,
        'link': link,
        'frame': '{broken',
      });
      await rig.settle();
      expect(rig.platforms[0].processed.last, token);
      expect(host.groups.backgroundReady, isFalse);
    },
  );

  test(
    'group authorization synchronization is cancellable and isolated from direct cleanup',
    () async {
      final platform = GroupBackgroundPlatform();
      final b = BackgroundConnection(platform);
      addTearDown(b.dispose);
      await b.initialize();
      await b.setEnabled(true);
      platform.syncGate = Completer<void>();
      var same = true;
      final start = b.protect(
        -10,
        groupLinks: ['verified'],
        canStart: () => true,
        sameConnection: () => same,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      b.connectionEnded(); // unrelated direct cleanup
      expect(b.protectsGroup, isTrue);
      same = false;
      b.connectionEnded(group: true);
      platform.syncGate!.complete();
      await start;
      expect(platform.starts, 0);
      expect(b.active, isFalse);
    },
  );

  test(
    'Android background bridge sends bounded group authorization with the room generation',
    () async {
      const channel = MethodChannel('dev.localchat/background');
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await const AndroidBackgroundPlatform().setGroupLinks(-42, [
        'epoch-1',
        'epoch-2',
      ]);
      expect(calls.single.method, 'groupLinks');
      expect(calls.single.arguments, {
        'generation': -42,
        'links': ['epoch-1', 'epoch-2'],
      });
    },
  );
}
