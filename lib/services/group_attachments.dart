part of 'group_controller.dart';

/// Shared signed group attachment relay and per-member completion receipts.
abstract class GroupAttachments<T> {
  GroupAttachments(this.g, this.fileMode);
  final bool fileMode;
  String get _kind => fileMode ? 'file' : 'image';
  String get _label => fileMode ? 'File' : 'Image';
  String get _wire => 'group$_label';
  bool _matches(GroupText m) => fileMode
      ? m.file != null && m.image == null
      : m.image != null && m.file == null;
  Map<String, Object?> _metadata(GroupText m) =>
      fileMode ? m.file!.toJson() : m.image!.toJson();
  Uint8List _content(GroupText m) => (fileMode ? m.fileBytes : m.imageBytes)!;
  Future<T?> _pickSource();
  Future<List<int>> _seal(T source);
  T _open(Uint8List bytes);
  Uint8List _bytesOf(T source);
  String? _nameOf(T source) => null;
  final GroupController g;
  final _links = <String, _GroupAttachmentLink>{};
  int _access = 0, _selection = 0;
  bool picking = false;
  SecretBox? _pending;
  SecretKey? _pendingKey;
  String? pendingGroup, _pendingEpoch, _origin;
  String? notice;
  bool get available =>
      (fileMode ? g.supportsFiles : g.supportsImages) &&
      g.members.length >= 2 &&
      g.members.every((m) => fileMode ? m.supportsFiles : m.supportsImages);
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
      final source = await _pickSource();
      if (source == null || g._disposed) return;
      final bytes = await _seal(source);
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
      g.error = fileMode
          ? 'Could not prepare this file. Choose a nonempty file up to 8 MiB.'
          : 'Could not prepare this image. Source limit is 8 MiB; prepared images must fit 2 MiB.';
    } finally {
      picking = false;
      g._notify();
    }
  }

  Future<T?> review(String group) async {
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
    return _open(bytes);
  }

  _GroupAttachmentLink _link(GroupLink link) =>
      _links.putIfAbsent(link.id, () => _GroupAttachmentLink(this, link));
  Future<bool> send(T source) async {
    final bytes = _bytesOf(source);
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
      if (fileMode) {
        await ChatFile.fromBytes(_nameOf(source)!, bytes);
      } else {
        await validateImagePixels(bytes);
      }
      final m = await GroupText.create(
        g.store.identity,
        g.store.name,
        group: group!,
        host: g.active!.host,
        epoch: epoch!,
        view: view,
        text: _label,
        targets: g.members.map((m) => m.id).toList(),
        imageBytes: fileMode ? null : bytes,
        fileBytes: fileMode ? bytes : null,
        fileName: _nameOf(source),
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
        await g._uncertain(m.key, reason: GroupDeliveryReason.interrupted);
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
        !(fileMode ? link.supportsFiles : link.supportsImages) ||
        transfer.engine.sending) {
      await _status(m, link.session.peerId!, false);
      return;
    }
    transfer.outgoing = m;
    try {
      final started = await transfer.engine.start(
        _content(m),
        retry: ChatMessage(
          id: m.id,
          peerId: link.session.peerId!,
          text: _label,
          timestamp: m.timestamp,
          outgoing: true,
          status: 'unconfirmed',
          image: m.image,
          file: m.file,
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
      final before = g.active!;
      final next = before.copy(
        messages: [
          for (final row in g.active!.messages)
            if (row.key == m.key)
              row.copy(receipts: {...row.receipts, member: 'unconfirmed'})
            else
              row,
        ],
      );
      await g.store.saveGroupHistory(next);
      g.delivery.record(before, next, GroupDeliveryReason.transferStopped);
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
                  'type': '${_wire}Status',
                  'key': m.key,
                  'member': member,
                  'status': 'unconfirmed',
                },
        );
      }
    } else if (!g.hosting &&
        member == g.links.values.firstOrNull?.session.peerId) {
      if (!received) {
        await g._uncertain(m.key, reason: GroupDeliveryReason.transferStopped);
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
    if (g.active == null) throw FormatException('No group $_kind session');
    if (p['type'] == '${_wire}Status') {
      if (g.hosting ||
          p['status'] != 'unconfirmed' ||
          p['key'] is! String ||
          p['member'] is! String) {
        throw const FormatException('Invalid attachment status');
      }
      final m = g.active!.messages.where((m) => m.key == p['key']);
      if (m.isNotEmpty && g._attempted.contains(p['key'])) {
        if (!_matches(m.first) || !m.first.targets.contains(p['member'])) {
          throw const FormatException('Wrong attachment receipt');
        }
        await _status(m.first, p['member'] as String, false);
      }
      return;
    }
    if (p['type'] == '${_wire}Abort') {
      if (!g.hosting || p['key'] is! String) {
        throw const FormatException('Invalid group attachment cancellation');
      }
      final m = g.active!.messages.where((m) => m.key == p['key']);
      if (m.isEmpty) return;
      if (!_matches(m.first) || m.first.author != link.session.peerId) {
        throw const FormatException('Wrong attachment author');
      }
      for (final l in _links.values.toList()) {
        if (l.outgoing?.key == p['key']) await l.engine.cancel();
      }
      await g._uncertain(
        p['key'] as String,
        reason: GroupDeliveryReason.transferStopped,
      );
      return;
    }
    final transfer = _link(link);
    final payload = {
      ...p,
      'type': (p['type'] as String).replaceFirst(_wire, _kind),
    };
    if (p['type'] == '${_wire}Offer') {
      final m = await GroupText.parse(
        {
          'envelope': p['message'],
          'receipts': <String, String>{},
          'read': false,
        },
        requireImageData: false,
        requireFileData: false,
      );
      if (!_matches(m) ||
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
        throw const FormatException('Wrong group attachment author/session');
      }
      if (m.envelope['view'] != g.view || !available) {
        await g._send(link, {
          'type': '${_wire}Result',
          'id': m.id,
          'received': false,
        });
        return;
      }
      final targets = g.members.map((m) => m.id).toList()..sort();
      if (jsonEncode(targets) != jsonEncode(m.targets)) {
        throw const FormatException('Wrong group attachment recipients');
      }
      if (!transfer.engine.progress.any((p) => !p.outgoing)) {
        transfer.incoming = m;
      }
      payload[_kind] = _metadata(m);
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
          'type': '${_wire}Abort',
          'key': origin,
        });
      } catch (_) {
        await g._stop();
      }
    }
    if (origin != null) {
      await g._uncertain(origin, reason: GroupDeliveryReason.transferStopped);
    }
    notice =
        'Group $_kind transfer stopped. Some members may already have received it.';
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

class _GroupAttachmentLink {
  _GroupAttachmentLink(this.hub, this.link);
  final GroupAttachments<dynamic> hub;
  final GroupLink link;
  GroupText? incoming, outgoing;
  late final engine = AttachmentTransfers(
    fileMode: hub.fileMode,
    store: _GroupAttachmentStore(this),
    peer: () => link.session.peerId,
    canAct: () =>
        hub.g.canAct() &&
        identical(hub.g.links[link.id], link) &&
        link.admitted,
    send: (p, origin) async {
      final g = hub.g, access = hub._access;
      if (!identical(g.links[link.id], link)) {
        throw const FormatException('Attachment member left');
      }
      if (origin && !g.canAct()) return;
      final payload = {
        ...p,
        'type': (p['type'] as String).replaceFirst(hub._kind, hub._wire),
        if (p['type'] == '${hub._kind}Offer') 'message': outgoing!.envelope,
      }..remove(hub._kind);
      final frame = await link.session.encrypt(payload);
      if (origin && (!g.canAct() || access != hub._access) ||
          !identical(g.links[link.id], link)) {
        await g._drop(link.id);
        throw const FormatException('Group attachment access changed');
      }
      await g.transport.send(link.id, jsonEncode(frame));
    },
    enqueue: hub.g._run,
    changed: hub.g._notify,
    timeout: hub.fileMode ? hub.g.fileTimeout : hub.g.imageTimeout,
    persisted: (m, inserted) async {
      if (!m.outgoing && inserted && hub.g.hosting) await hub._relay(incoming!);
      hub.g._notify();
    },
  );
}

/// The shared engine persists into encrypted group history, never direct chats.
class _GroupAttachmentStore extends LocalStore {
  _GroupAttachmentStore(this.owner);
  final _GroupAttachmentLink owner;
  @override
  Future<bool> saveImageMessage(ChatMessage message, Uint8List bytes) =>
      _save(message, bytes, false);
  @override
  Future<bool> saveFileMessage(ChatMessage message, Uint8List bytes) =>
      _save(message, bytes, true);
  Future<bool> _save(
    ChatMessage message,
    Uint8List bytes,
    bool fileMode,
  ) async {
    final m = owner.incoming;
    if (fileMode != owner.hub.fileMode ||
        message.outgoing ||
        m == null ||
        m.id != message.id ||
        !owner.hub._matches(m)) {
      throw const FormatException('Invalid attachment binding');
    }
    if (fileMode) {
      await m.file!.verify(bytes);
    } else {
      await m.image!.verify(bytes);
    }
    final g = owner.hub.g;
    owner.incoming = m.copy(
      imageBytes: fileMode ? null : Uint8List.fromList(bytes),
      fileBytes: fileMode ? Uint8List.fromList(bytes) : null,
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
