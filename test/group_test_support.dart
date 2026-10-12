import 'dart:async';
import 'package:local_chat/services/group_transport.dart';
import 'package:local_chat/services/group_controller.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'package:local_chat/services/image_files.dart';

class GroupNetwork {
  FakeGroupTransport? host;
  int next = 0;
  final controllers = <GroupController>[];
  Future<GroupController> phone(
    String name, {
    DemoStore? store,
    bool Function()? canAct,
    Duration receiptTimeout = const Duration(seconds: 30),
    Duration timeout = const Duration(seconds: 90),
    ImageFiles? imageFiles,
    bool supportsImages = true,
    Duration imageTimeout = const Duration(seconds: 30),
  }) async {
    store ??= DemoStore();
    await store.open();
    store.name = name;
    final transport = FakeGroupTransport(this);
    final c = GroupController(
      transport,
      store,
      prepare: () async => true,
      canAct: canAct ?? () => true,
      receiptTimeout: receiptTimeout,
      timeout: timeout,
      imageFiles: imageFiles,
      supportsImages: supportsImages,
      imageTimeout: imageTimeout,
    );
    controllers.add(c);
    await c.initialize();
    return c;
  }

  Future<void> settle() async {
    for (var i = 0; i < 25; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 3));
      for (final c in controllers) {
        await c.idle;
      }
    }
  }

  Future<void> join(GroupController guest, {bool verify = true}) async {
    await guest.discover();
    await settle();
    await guest.join('host');
    await settle();
    if (verify) {
      final h = controllers.firstWhere((c) => c.hosting);
      final link = h.links.values.firstWhere(
        (l) => l.session.peerId == guest.selfId,
      );
      await h.confirm(link.id);
      await guest.confirm(guest.links.keys.single);
      await settle();
    }
  }

  Future<void> close() async {
    for (final c in controllers) {
      await c.stop();
      c.dispose();
    }
  }
}

class FakeGroupTransport implements GroupTransport {
  FakeGroupTransport(this.network);
  final GroupNetwork network;
  final bus = StreamController<Map<String, dynamic>>.broadcast();
  final links = <String, (FakeGroupTransport, String)>{};
  final frames = <String>[];
  bool dropOutgoing = false;
  Completer<void>? gate;
  @override
  Stream<Map<String, dynamic>> get events => bus.stream;
  @override
  Future<void> host(String name, String title) async {
    network.host = this;
  }

  @override
  Future<void> discover(String name) async {
    bus.add({
      'type': 'peers',
      'peers': network.host == null
          ? []
          : [
              {'address': 'host', 'name': 'Host', 'title': 'Test group'},
            ],
    });
  }

  @override
  Future<void> join(String address) async {
    final host = network.host!;
    final id = (++network.next).toString();
    links['g$id'] = (host, 'h$id');
    host.links['h$id'] = (this, 'g$id');
    bus.add({'type': 'connected', 'link': 'g$id'});
    host.bus.add({'type': 'connected', 'link': 'h$id'});
  }

  @override
  Future<void> send(String link, String frame) async {
    await gate?.future;
    final target = links[link];
    if (target == null) throw StateError('Disconnected');
    frames.add(frame);
    if (!dropOutgoing) {
      target.$1.bus.add({'type': 'frame', 'link': target.$2, 'frame': frame});
    }
  }

  @override
  Future<void> closeLink(String link) async {
    final target = links.remove(link);
    if (target != null) {
      target.$1.links.remove(target.$2);
      target.$1.bus.add({'type': 'disconnected', 'link': target.$2});
    }
  }

  @override
  Future<void> stop() async {
    for (final key in links.keys.toList()) {
      await closeLink(key);
    }
    if (identical(network.host, this)) network.host = null;
  }
}
