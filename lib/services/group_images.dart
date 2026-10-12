part of 'group_controller.dart';

/// A signed group envelope travels with each bounded, encrypted image offer.
/// Per-link image engines keep their own counters, chunks, receipts and timers.
class GroupImages {
  GroupImages(this.g);
  final GroupController g;
  final _links = <String, _GroupImageLink>{};
  int _access = 0, _selection = 0;
  bool picking = false;
  SecretBox? _pending;
  SecretKey? _pendingKey;
  String? pendingGroup, _pendingEpoch, _origin;
  String? notice;
  bool get available =>
      g.supportsImages &&
      g.members.length >= 2 &&
      g.members.every((m) => m.supportsImages);
  bool get canSend =>
      g.canSend &&
      available &&
      !picking &&
      _origin == null &&
      !_links.values.any((l) => l.engine.sending);
  List<({String member, String key, ImageProgress transfer})> get progress => [
    for (final link in _links.values)
      for (final p in link.engine.progress)
        (
          member: link.link.name,
          key: (p.outgoing ? link.outgoing : link.incoming)?.key ?? p.id,
          transfer: p,
        ),
  ];
  bool get waiting => _origin != null;
  void receiptsChanged() {
    if (_origin == null) return;
    final m = g.active?.messages.where((m) => m.key == _origin);
    if (m == null ||
        m.isEmpty ||
        !m.first.receipts.values.contains('pending')) {
      _origin = null;
    }
  }

  void accessChanged(bool pause) {
    _access++;
    if (pause) {
      for (final l in _links.values) {
        l.engine.requestCancel();
      }
    }
  }

  void discard() {
    _selection++;
    _pending = null;
    _pendingKey = null;
    pendingGroup = null;
    _pendingEpoch = null;
    g._notify();
  }

  Future<void> pick() async {
    if (!canSend) return;
    final group = g.active!.id, epoch = g.epoch, selection = _selection;
    picking = true;
    g.error = null;
    g._notify();
    try {
      final source = await g.imageFiles.pick();
      if (source == null || g._disposed) return;
      final bytes = await normalizeImage(source);
      final cipher = Xchacha20.poly1305Aead(),
          key = await Xchacha20.poly1305Aead().newSecretKey();
      final box = await cipher.encrypt(bytes, secretKey: key);
      if (g._disposed ||
          selection != _selection ||
          g.active?.id != group ||
          g.epoch != epoch) {
        return;
      }
      _pending = box;
      _pendingKey = key;
      pendingGroup = group;
      _pendingEpoch = epoch;
    } catch (_) {
      g.error =
          'Could not prepare this image. Source limit is 8 MiB; prepared images must fit 2 MiB.';
    } finally {
      picking = false;
      g._notify();
    }
  }

  Future<Uint8List?> review(String group) async {
    if (!g.canAct() ||
        pendingGroup != group ||
        g.active?.id != group ||
        _pendingEpoch != g.epoch ||
        _pending == null) {
      return null;
    }
    final access = _access, selection = _selection;
    final bytes = Uint8List.fromList(
      await Xchacha20.poly1305Aead().decrypt(
        _pending!,
        secretKey: _pendingKey!,
      ),
    );
    if (!g.canAct() ||
        access != _access ||
        selection != _selection ||
        g.active?.id != group ||
        g._disposed) {
      return null;
    }
    return bytes;
  }

  _GroupImageLink _link(GroupLink link) =>
      _links.putIfAbsent(link.id, () => _GroupImageLink(this, link));
  Future<bool> send(Uint8List bytes) async {
    final access = _access,
        group = g.active?.id,
        epoch = g.epoch,
        view = g.view;
    var accepted = false;
    await g._run(() async {
      if (!canSend ||
          group != g.active?.id ||
          epoch != g.epoch ||
          view != g.view ||
          access != _access) {
        return;
      }
      await validateImagePixels(bytes);
      final m = await GroupText.create(
        g.store.identity,
        g.store.name,
        group: group!,
        host: g.active!.host,
        epoch: epoch!,
        view: view,
        text: 'Image',
        targets: g.members.map((m) => m.id).toList(),
        imageBytes: bytes,
      );
      if (!canSend || access != _access || epoch != g.epoch || view != g.view) {
        return;
      }
      await g._persist(
        m.copy(receipts: {...m.receipts, g.selfId!: 'received'}),
      );
      g._attempted.add(m.key);
      _origin = m.key;
      notice = null;
      discard();
      accepted = true;
      if (!g.canAct() || access != _access) {
        await g._uncertain(m.key);
      } else if (g.hosting) {
        await _relay(m);
      } else {
        await _start(g.links.values.single, m);
      }
      g._notify();
    });
    return accepted;
  }

  Future<void> _start(GroupLink link, GroupText m) async {
    final transfer = _link(link);
    if (!g.canAct() ||
        !link.admitted ||
        !link.supportsImages ||
        transfer.engine.sending) {
      await _status(m, link.session.peerId!, false);
      return;
    }
    transfer.outgoing = m;
    try {
      final started = await transfer.engine.start(
        m.imageBytes!,
        retry: ChatMessage(
          id: m.id,
          peerId: link.session.peerId!,
          text: 'Image',
          timestamp: m.timestamp,
          outgoing: true,
          status: 'unconfirmed',
          image: m.image,
        ),
      );
      if (!started) await _status(m, link.session.peerId!, false);
    } catch (_) {
      await _status(m, link.session.peerId!, false);
      await g._drop(link.id);
    }
  }

  Future<void> _relay(GroupText m) async {
    for (final id in m.targets) {
      if (id == g.selfId || id == m.author) continue;
      final links = g.links.values.where(
        (l) => l.admitted && l.session.peerId == id,
      );
      if (links.isEmpty) {
        await _status(m, id, false);
      } else {
        await _start(links.first, m);
      }
    }
  }

  Future<void> _status(GroupText record, String member, bool received) async {
    final found = g.active?.messages.where((m) => m.key == record.key);
    if (found == null ||
        found.isEmpty ||
        record.envelope['group'] != g.active!.id) {
      return;
    }
    final m = found.first;
    if (!m.targets.contains(member) ||
        m.receipts[member] == 'received' && !received) {
      return;
    }
    if (received) {
      await g._receipt(m.key, member);
    } else {
      final next = g.active!.copy(
        messages: [
          for (final row in g.active!.messages)
            if (row.key == m.key)
              row.copy(receipts: {...row.receipts, member: 'unconfirmed'})
            else
              row,
        ],
      );
      await g.store.saveGroupHistory(next);
      g.active = next;
      await g._reload();
      receiptsChanged();
    }
    if (g.hosting && m.author != g.selfId) {
      final author = g.links.values.where(
        (l) => l.admitted && l.session.peerId == m.author,
      );
      if (author.isNotEmpty) {
        await g._send(
          author.first,
          received
              ? {'type': 'groupReceipt', 'key': m.key, 'member': member}
              : {
                  'type': 'groupImageStatus',
                  'key': m.key,
                  'member': member,
                  'status': 'unconfirmed',
                },
        );
      }
    } else if (!g.hosting &&
        member == g.links.values.firstOrNull?.session.peerId) {
      if (!received) {
        await g._uncertain(m.key);
      } else if (g.active!.messages
          .firstWhere((row) => row.key == m.key)
          .receipts
          .values
          .contains('pending')) {
        g._receiptTimers.remove(m.key)?.cancel();
        g._receiptTimers[m.key] = Timer(
          g.receiptTimeout,
          () => unawaited(
            g._run(() async {
              await g._uncertain(m.key);
              g._notify();
            }),
          ),
        );
      }
    }
  }

  Future<void> handle(GroupLink link, Map<String, dynamic> p) async {
    if (g.active == null) throw const FormatException('No group image session');
    if (p['type'] == 'groupImageStatus') {
      if (g.hosting ||
          p['status'] != 'unconfirmed' ||
          p['key'] is! String ||
          p['member'] is! String) {
        throw const FormatException('Invalid image status');
      }
      final m = g.active!.messages.where((m) => m.key == p['key']);
      if (m.isNotEmpty && g._attempted.contains(p['key'])) {
        if (m.first.image == null || !m.first.targets.contains(p['member'])) {
          throw const FormatException('Wrong image receipt');
        }
        await _status(m.first, p['member'] as String, false);
      }
      return;
    }
    if (p['type'] == 'groupImageAbort') {
      if (!g.hosting || p['key'] is! String) {
        throw const FormatException('Invalid group image cancellation');
      }
      final m = g.active!.messages.where((m) => m.key == p['key']);
      if (m.isEmpty) return;
      if (m.first.image == null || m.first.author != link.session.peerId) {
        throw const FormatException('Wrong image author');
      }
      for (final l in _links.values.toList()) {
        if (l.outgoing?.key == p['key']) await l.engine.cancel();
      }
      await g._uncertain(p['key'] as String);
      return;
    }
    final transfer = _link(link);
    final payload = {
      ...p,
      'type': (p['type'] as String).replaceFirst('groupImage', 'image'),
    };
    if (p['type'] == 'groupImageOffer') {
      final m = await GroupText.parse({
        'envelope': p['message'],
        'receipts': <String, String>{},
        'read': false,
      }, requireImageData: false);
      if (m.image == null ||
          p['id'] != m.id ||
          p['timestamp'] != m.timestamp ||
          m.envelope['group'] != g.active!.id ||
          m.envelope['host'] != g.active!.host ||
          m.envelope['epoch'] != g.epoch ||
          !m.targets.contains(g.selfId) ||
          !g.members.any(
            (a) => a.id == m.author && a.public == m.envelope['author'],
          ) ||
          g.hosting && m.author != link.session.peerId) {
        throw const FormatException('Wrong group image author/session');
      }
      if (m.envelope['view'] != g.view || !available) {
        await g._send(link, {
          'type': 'groupImageResult',
          'id': m.id,
          'received': false,
        });
        return;
      }
      final targets = g.members.map((m) => m.id).toList()..sort();
      if (jsonEncode(targets) != jsonEncode(m.targets)) {
        throw const FormatException('Wrong group image recipients');
      }
      if (!transfer.engine.progress.any((p) => !p.outgoing)) {
        transfer.incoming = m;
      }
      payload['image'] = m.image!.toJson();
    }
    await transfer.engine.handle(payload);
  }

  Future<void> cancel({bool announce = true}) async {
    if (progress.isEmpty && !waiting) return;
    for (final l in _links.values) {
      l.engine.requestCancel();
    }
    final origin = _origin;
    for (final l in _links.values.toList()) {
      try {
        await l.engine.cancel();
      } catch (_) {
        await g._drop(l.link.id);
      }
    }
    if (announce && !g.hosting && origin != null && g.links.isNotEmpty) {
      try {
        await g._send(g.links.values.single, {
          'type': 'groupImageAbort',
          'key': origin,
        });
      } catch (_) {
        await g._stop();
      }
    }
    if (origin != null) await g._uncertain(origin);
    notice =
        'Group image transfer stopped. Some members may already have received it.';
    g._notify();
  }

  Future<void> cancelByUser() {
    for (final l in _links.values) {
      l.engine.requestCancel();
    }
    return g._run(() => cancel());
  }

  Future<void> membershipChanged() async {
    discard();
    if (progress.isNotEmpty || waiting) await cancel(announce: false);
  }

  Future<void> drop(String id) async {
    final l = _links.remove(id);
    if (l == null) return;
    try {
      await l.engine.stop();
    } finally {
      l.engine.dispose();
    }
  }

  void stop() {
    for (final l in _links.values) {
      l.engine.dispose();
    }
    _links.clear();
    _origin = null;
    notice = null;
    _access++;
    discard();
  }
}

class _GroupImageLink {
  _GroupImageLink(this.hub, this.link);
  final GroupImages hub;
  final GroupLink link;
  GroupText? incoming, outgoing;
  late final engine = ImageTransfers(
    store: _GroupImageStore(this),
    peer: () => link.session.peerId,
    canAct: () =>
        hub.g.canAct() &&
        identical(hub.g.links[link.id], link) &&
        link.admitted,
    send: (p, origin) async {
      final g = hub.g, access = hub._access;
      if (!identical(g.links[link.id], link)) {
        throw const FormatException('Image member left');
      }
      if (origin && !g.canAct()) return;
      final payload = {
        ...p,
        'type': (p['type'] as String).replaceFirst('image', 'groupImage'),
        if (p['type'] == 'imageOffer') 'message': outgoing!.envelope,
      }..remove('image');
      final frame = await link.session.encrypt(payload);
      if (origin && (!g.canAct() || access != hub._access) ||
          !identical(g.links[link.id], link)) {
        await g._drop(link.id);
        throw const FormatException('Group image access changed');
      }
      await g.transport.send(link.id, jsonEncode(frame));
    },
    enqueue: hub.g._run,
    changed: hub.g._notify,
    timeout: hub.g.imageTimeout,
    persisted: (m, inserted) async {
      if (!m.outgoing && inserted && hub.g.hosting) await hub._relay(incoming!);
      hub.g._notify();
    },
  );
}

/// The shared engine persists into encrypted group history, never direct chats.
class _GroupImageStore extends LocalStore {
  _GroupImageStore(this.owner);
  final _GroupImageLink owner;
  @override
  Future<bool> saveImageMessage(ChatMessage message, Uint8List bytes) async {
    final m = owner.incoming;
    if (message.outgoing || m == null || m.id != message.id) {
      throw const FormatException('Invalid image binding');
    }
    await m.image!.verify(bytes);
    final g = owner.hub.g;
    owner.incoming = m.copy(
      imageBytes: Uint8List.fromList(bytes),
      receipts: g.hosting
          ? {
              for (final id in m.targets)
                id: id == g.selfId || id == m.author ? 'received' : 'pending',
            }
          : m.receipts,
    );
    return g._persist(owner.incoming!);
  }

  @override
  Future<bool> changeOutgoingStatus(
    String id,
    String peer,
    List<String> from,
    String to,
  ) async {
    final m = owner.outgoing;
    if (m == null || m.id != id || peer != owner.link.session.peerId) {
      return false;
    }
    if (to != 'sending') await owner.hub._status(m, peer, to == 'delivered');
    return true;
  }
}
