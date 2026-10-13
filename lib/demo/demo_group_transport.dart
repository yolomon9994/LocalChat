import 'dart:async';

import '../services/group_controller.dart';
import '../services/group_transport.dart';
import 'demo_store.dart';

/// A private, in-tab network of real protocol controllers. Remote people,
/// confirmations and receipts are simulated; no platform/network APIs are used.
class DemoGroupTransport implements GroupTransport {
  DemoGroupTransport({this.replyDelay = const Duration(milliseconds: 450)});
  final Duration replyDelay;
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final _stores = <String, _PeerStore>{};
  _DemoWorld? _world;
  bool _disposed = false;
  int _generation = -2;
  @override
  Stream<Map<String, dynamic>> get events => _events.stream.where(
    (event) =>
        _world?.live == true && event['generation'] == _world?.local.generation,
  );

  _DemoWorld _begin() {
    if (_disposed) throw StateError('The group demo has closed.');
    _world?.close();
    final world = _DemoWorld(_events, --_generation, replyDelay, _stores);
    _world = world;
    return world;
  }

  @override
  Future<void> host(String name, String title) async {
    final world = _begin();
    world.host = world.local;
    world.title = title;
    for (final name in ['Ava (Demo)', 'Noah (Demo)']) {
      final peer = await world.peer(name);
      if (!world.live) return;
      await peer.controller.discover();
      if (!world.live) return;
      await peer.controller.join('demo-group');
    }
  }

  @override
  Future<void> discover(String name) async {
    final world = _begin();
    final host = await world.peer('Ava (Demo host)');
    if (!world.live) return;
    final saved = host.controller.histories;
    await host.controller.host(
      'Weekend plans (Demo)',
      previous: saved.isEmpty ? null : saved.first,
    );
    if (!world.live) return;
    final guest = await world.peer('Noah (Demo)');
    if (!world.live) return;
    await guest.controller.discover();
    if (!world.live) return;
    await guest.controller.join('demo-group');
    if (world.live) world.local.discoverNow();
  }

  @override
  Future<void> join(String address) async {
    final world = _world;
    if (world == null ||
        !world.live ||
        address != 'demo-group' ||
        world.host == world.local) {
      throw const FormatException('Find a simulated group first.');
    }
    world.local.joinNow(address);
  }

  @override
  Future<void> send(String link, String frame) async {
    final world = _world;
    if (world == null) throw StateError('No simulated group connected.');
    world.local.sendNow(link, frame);
  }

  @override
  Future<void> closeLink(String link) async => _world?.local.drop(link);
  @override
  Future<void> stop() async {
    _world?.close();
    _world = null;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    _stores.clear();
    await _events.close();
  }
}

/// Keep simulated identities/history stable within this tab across mode changes.
class _PeerStore extends DemoStore {
  bool _opened = false;
  @override
  Future<void> open() async {
    if (_opened) return;
    await super.open();
    _opened = true;
  }
}

class _DemoWorld {
  _DemoWorld(
    StreamController<Map<String, dynamic>> events,
    int generation,
    this.delay,
    this.stores,
  ) {
    local = _DemoEndpoint(this, events, generation);
  }
  final Duration delay;
  final Map<String, _PeerStore> stores;
  late final _DemoEndpoint local;
  _DemoEndpoint? host;
  String title = 'Weekend plans (Demo)';
  String? humanId;
  bool live = true;
  int nextLink = 0;
  final peers = <_DemoPeer>[];
  Future<_DemoPeer> peer(String name) async {
    final store = stores[name] ??= _PeerStore();
    await store.open();
    store.name = name;
    final endpoint = _DemoEndpoint(
      this,
      StreamController<Map<String, dynamic>>.broadcast(),
      local.generation,
    );
    final controller = GroupController(
      endpoint,
      store,
      prepare: () async => live,
      canAct: () => live,
    );
    final peer = _DemoPeer(this, endpoint, controller);
    if (!live) {
      controller.dispose();
      await endpoint.eventsController.close();
      return peer;
    }
    peers.add(peer);
    await controller.initialize();
    if (!live) return peer;
    peer.seen.addAll(
      controller.histories.expand((h) => h.messages.map((m) => m.key)),
    );
    controller.addListener(peer.changed);
    return peer;
  }

  void close() {
    if (!live) return;
    live = false;
    local.dropAll();
    for (final peer in peers) {
      peer.dispose();
    }
    peers.clear();
  }
}

class _DemoPeer {
  _DemoPeer(this.world, this.endpoint, this.controller);
  final _DemoWorld world;
  final _DemoEndpoint endpoint;
  final GroupController controller;
  final confirming = <String>{};
  final seen = <String>{};
  final timers = <Timer>{};
  bool greeted = false;
  int replies = 0;

  void changed() {
    if (!world.live) return;
    for (final link in controller.links.values) {
      if (endpoint.links[link.id]?.$1 == world.local &&
          link.session.peerId != null) {
        world.humanId = link.session.peerId;
      }
      if (!link.localVerified &&
          link.session.verificationCode != null &&
          confirming.add(link.id)) {
        // Only the remote simulated participant confirms automatically. The
        // visible local controller still requires its explicit Codes match tap.
        unawaited(controller.confirm(link.id));
      }
    }
    final human = world.humanId;
    if (human == null || !controller.members.any((m) => m.id == human)) return;
    if (!greeted && controller.canSend) {
      greeted = true;
      _reply(
        'Hello from ${controller.store.name}! This group, its members and receipts are simulated. Everything resets when you reload this tab.',
      );
    }
    for (final message in controller.active?.messages ?? []) {
      if (!seen.add(message.key) || message.author != human) continue;
      const replies = [
        'Got it! This reply and the member receipts are simulated.',
        'Try group search, saving a draft, pinning or archiving this chat.',
        'You can end the demo group and reopen its saved history while offline.',
      ];
      _reply(replies[this.replies++ % replies.length]);
    }
  }

  void _reply(String text) {
    late final Timer timer;
    timer = Timer(world.delay, () {
      timers.remove(timer);
      if (world.live &&
          controller.canSend &&
          controller.members.any((m) => m.id == world.humanId)) {
        unawaited(controller.sendText(text));
      }
    });
    timers.add(timer);
  }

  void dispose() {
    controller.removeListener(changed);
    for (final timer in timers) {
      timer.cancel();
    }
    timers.clear();
    controller.dispose();
    endpoint.dropAll();
    unawaited(endpoint.eventsController.close());
  }
}

class _DemoEndpoint implements GroupTransport {
  _DemoEndpoint(this.world, this.eventsController, this.generation);
  final _DemoWorld world;
  final StreamController<Map<String, dynamic>> eventsController;
  final int generation;
  final links = <String, (_DemoEndpoint, String)>{};
  @override
  Stream<Map<String, dynamic>> get events => eventsController.stream;
  void emit(Map<String, dynamic> event) {
    if (world.live && !eventsController.isClosed) {
      eventsController.add({'generation': generation, ...event});
    }
  }

  @override
  Future<void> host(String name, String title) async {
    world.host = this;
    world.title = title;
  }

  void discoverNow() => emit({
    'type': 'peers',
    'peers': [
      if (world.host != null)
        {
          'address': 'demo-group',
          'name': world.host == world.local
              ? 'You (Demo host)'
              : 'Ava (Demo host)',
          'title': world.title,
        },
    ],
  });
  @override
  Future<void> discover(String name) async => discoverNow();
  void joinNow(String address) {
    final host = world.host;
    if (!world.live ||
        host == null ||
        host == this ||
        address != 'demo-group') {
      throw const FormatException('The simulated host is no longer available.');
    }
    if (host.links.length >= 7 || links.isNotEmpty) {
      throw StateError('Demo group is full.');
    }
    final sequence = ++world.nextLink;
    final guestId = 'demo-$generation-g$sequence',
        hostId = 'demo-$generation-h$sequence';
    links[guestId] = (host, hostId);
    host.links[hostId] = (this, guestId);
    emit({'type': 'connected', 'link': guestId, 'generation': generation});
    host.emit({
      'type': 'connected',
      'link': hostId,
      'generation': host.generation,
    });
  }

  @override
  Future<void> join(String address) async => joinNow(address);
  void sendNow(String id, String frame) {
    final target = links[id];
    if (!world.live || target == null) {
      throw StateError('Simulated member disconnected.');
    }
    target.$1.emit({
      'type': 'frame',
      'link': target.$2,
      'frame': frame,
      'generation': target.$1.generation,
      'held': false,
    });
  }

  @override
  Future<void> send(String link, String frame) async => sendNow(link, frame);
  void drop(String id) {
    final target = links.remove(id);
    if (target == null) return;
    target.$1.links.remove(target.$2);
    target.$1.emit({'type': 'disconnected', 'link': target.$2});
  }

  void dropAll() {
    for (final id in links.keys.toList()) {
      drop(id);
    }
  }

  @override
  Future<void> closeLink(String link) async => drop(link);
  @override
  Future<void> stop() async => dropAll();
}
