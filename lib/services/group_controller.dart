import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../core/group_models.dart';
import '../core/local_store.dart';
import '../core/secure_session.dart';
import 'group_transport.dart';
import 'draft_controller.dart';
import 'chat_notifications.dart';
import 'image_files.dart';
import 'attachment_transfers.dart';
import 'chat_files.dart';
import '../core/chat_file.dart';
import 'image_content.dart';
import '../core/models.dart';
import 'package:cryptography/cryptography.dart';

part 'group_images.dart';
part 'group_attachments.dart';
part 'group_files.dart';

class GroupLink {
  GroupLink(this.id, this.session);
  final String id;
  final SecureSession session;
  bool localVerified = false, remoteVerified = false, admitted = false;
  bool supportsImages = false;
  bool supportsFiles = false;
  Timer? timer;
  bool get verified => localVerified && remoteVerified;
  String get name => session.peerName ?? 'Connecting member';
}

class GroupController extends ChangeNotifier {
  GroupController(
    this.transport,
    this.store, {
    required this.prepare,
    required this.canAct,
    this.accessRevision,
    this.notifications,
    this.timeout = const Duration(seconds: 90),
    this.receiptTimeout = const Duration(seconds: 30),
    ImageFiles? imageFiles,
    ChatFiles? chatFiles,
    DraftController? drafts,
    this.imageTimeout = const Duration(seconds: 30),
    this.fileTimeout = const Duration(seconds: 30),
    this.supportsImages = true,
    this.supportsFiles = true,
  }) : imageFiles = imageFiles ?? createImageFiles(),
       chatFiles = chatFiles ?? createChatFiles(),
       drafts = drafts ?? DraftController(store),
       _ownsDrafts = drafts == null {
    this.drafts.addListener(_notify);
  }
  final GroupTransport transport;
  final LocalStore store;
  final DraftController drafts;
  final bool _ownsDrafts;
  final ChatNotifications? notifications;
  final Future<bool> Function() prepare;
  final bool Function() canAct;
  final int Function()? accessRevision;
  final Duration timeout, receiptTimeout;
  final Duration imageTimeout, fileTimeout;
  final bool supportsImages, supportsFiles;
  final ImageFiles imageFiles;
  final ChatFiles chatFiles;
  late final images = GroupImages(this);
  late final files = GroupFiles(this);
  Future<void> _queue = Future.value();
  Future<void> get idle => _queue;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  final links = <String, GroupLink>{};
  final _receiptTimers = <String, Timer>{};
  final _attempted = <String>{};
  List<GroupHistory> histories = [];
  List<GroupMember> members = [];
  List<Map<String, dynamic>> nearby = [];
  GroupHistory? active;
  String? epoch, selfId, selfPublic, error;
  String state = 'Offline';
  int view = 0;
  bool hosting = false, running = false, busy = false, _disposed = false;
  Object? _visible;
  String? _visibleId;
  Timer? _joinTimer;
  bool get connected =>
      active != null && (hosting || links.values.any((l) => l.admitted));
  bool get canSend =>
      !_disposed && connected && canAct() && !busy && _receiptTimers.length < 4;
  Future<void> _run(Future<void> Function() f) {
    final result = _queue.then((_) async {
      if (!_disposed) await f();
    });
    _queue = result.catchError((Object e) {
      if (!_disposed) {
        error = e is FormatException
            ? e.message
            : 'Group operation failed. Leave and try again.';
        _notify();
      }
    });
    return _queue;
  }

  Future<void> initialize() => _run(() async {
    selfPublic = base64Encode((await store.identity.extractPublicKey()).bytes);
    selfId = await identityId(selfPublic!);
    await _reload();
    for (final g in histories.toList()) {
      if (g.messages.any((m) => m.receipts.values.contains('pending'))) {
        await store.saveGroupHistory(
          g.copy(
            messages: [
              for (final m in g.messages)
                m.copy(
                  receipts: {
                    for (final e in m.receipts.entries)
                      e.key: e.value == 'pending' ? 'unconfirmed' : e.value,
                  },
                ),
            ],
          ),
        );
      }
    }
    await _reload();
    _subscription ??= transport.events.listen(
      (event) => unawaited(_run(() => _event(event))),
      onError: (Object e) => unawaited(
        _run(() async {
          await _stop();
          error = 'Group transport stopped. Reconnect and verify again.';
          _notify();
        }),
      ),
    );
    _notify();
  });
  Future<void> _reload() async {
    histories = await store.groupHistories();
    if (active != null) {
      final matches = histories.where((g) => g.id == active!.id);
      if (matches.isNotEmpty) active = matches.first;
    }
  }

  Future<void> refreshHistory() => _run(() async {
    await _reload();
    _notify();
  });
  Future<bool> host(String title, {GroupHistory? previous}) async {
    var success = false;
    await _run(() async {
      if (!canAct() || busy) return;
      title = title.trim();
      if (title.isEmpty || title.length > 64) {
        throw const FormatException('Use a group name with 1–64 characters.');
      }
      if (previous != null && previous!.host != selfPublic) {
        throw const FormatException(
          'Only the original host can reopen this group.',
        );
      }
      busy = true;
      error = null;
      _notify();
      try {
        await _stop();
        if (!await prepare() || !canAct()) return;
        if (previous != null) {
          final current = histories.where((g) => g.id == previous!.id);
          if (current.isEmpty) {
            throw const FormatException('This group has been deleted.');
          }
          previous = current.first;
          if (previous!.host != selfPublic) {
            throw const FormatException(
              'Only the original host can reopen this group.',
            );
          }
          title = previous!.title;
        }
        epoch = randomId();
        view = 1;
        hosting = true;
        running = true;
        members = [
          GroupMember(
            selfId!,
            store.name,
            selfPublic!,
            supportsImages: supportsImages,
            supportsFiles: supportsFiles,
          ),
        ];
        active =
            previous ??
            GroupHistory(id: randomId(), title: title, host: selfPublic!);
        await store.saveGroupHistory(active!);
        await _reload();
        state = 'Hosting • waiting for verified members';
        await transport.host(store.name, title);
        if (!canAct()) {
          await _stop();
          return;
        }
        success = true;
      } catch (_) {
        await _stop();
        rethrow;
      } finally {
        busy = false;
        _notify();
      }
    });
    return success;
  }

  Future<void> discover() => _run(() async {
    if (!canAct() || busy || connected) return;
    busy = true;
    error = null;
    _notify();
    try {
      await _stop();
      if (!await prepare() || !canAct()) return;
      running = true;
      state = 'Finding group hosts';
      nearby = [];
      await transport.discover(store.name);
      if (!canAct()) await _stop();
    } catch (_) {
      await _stop();
      rethrow;
    } finally {
      busy = false;
      _notify();
    }
  });
  Future<bool> join(String address) async {
    var success = false;
    await _run(() async {
      if (!canAct() ||
          !running ||
          state == 'Joining host' ||
          links.isNotEmpty ||
          connected ||
          busy ||
          !nearby.any((p) => p['address'] == address)) {
        return;
      }
      busy = true;
      error = null;
      _notify();
      try {
        state = 'Joining host';
        _joinTimer?.cancel();
        _joinTimer = Timer(
          timeout,
          () => unawaited(
            _run(() async {
              if (!connected) {
                await _stop();
                error = 'Joining timed out. Find the host and verify again.';
                _notify();
              }
            }),
          ),
        );
        await transport.join(address);
        success = true;
      } catch (_) {
        await _stop();
        rethrow;
      } finally {
        busy = false;
        _notify();
      }
    });
    return success;
  }

  Future<void> confirm(String linkId) => _run(() async {
    final link = links[linkId];
    if (!canAct() ||
        link == null ||
        link.localVerified ||
        link.session.verificationCode == null) {
      return;
    }
    try {
      await _send(link, {
        'type': 'groupVerified',
        'version': 1,
        'features': [
          if (supportsImages) 'group-image-v1',
          if (supportsFiles) 'group-file-v1',
        ],
      });
      link.localVerified = true;
      await _admit(link);
    } catch (_) {
      await _drop(linkId);
      rethrow;
    }
    _notify();
  });
  Future<void> reject(String id) => _run(() async {
    if (canAct()) await _drop(id);
    _notify();
  });
  Future<void> _send(GroupLink link, Map<String, dynamic> payload) async {
    if (!identical(links[link.id], link)) {
      throw const FormatException('Group member disconnected');
    }
    await transport.send(
      link.id,
      jsonEncode(await link.session.encrypt(payload)),
    );
  }

  Future<void> _broadcast(
    Map<String, dynamic> payload, {
    String? except,
  }) async {
    final failed = <String>[];
    for (final link in links.values.toList()) {
      if (!link.admitted || link.session.peerId == except) continue;
      try {
        await _send(link, payload);
      } catch (_) {
        failed.add(link.id);
      }
    }
    for (final id in failed) {
      await _drop(id, announce: false);
    }
    if (failed.isNotEmpty && hosting) await _roster();
  }

  Future<void> _roster() async {
    if (!hosting || active == null) return;
    await images.membershipChanged();
    await files.membershipChanged();
    view++;
    await _broadcast({
      'type': 'groupRoster',
      'version': 1,
      'group': active!.id,
      'title': active!.title,
      'host': selfPublic,
      'epoch': epoch,
      'view': view,
      'members': members.map((m) => m.toJson()).toList(),
    });
  }

  Future<void> _admit(GroupLink link) async {
    if (!hosting || !link.verified || link.admitted || !canAct()) return;
    final member = await GroupMember.parse({
      'id': link.session.peerId,
      'name': link.name,
      'public': linkRemotePublic(link),
      'images': link.supportsImages,
      'files': link.supportsFiles,
    });
    if (members.length >= groupLimit || members.any((m) => m.id == member.id)) {
      await _drop(link.id);
      return;
    }
    link.admitted = true;
    link.timer?.cancel();
    members = [...members, member];
    state = 'Hosting • ${members.length} verified members';
    await _roster();
  }

  final _publicByLink = <String, String>{};
  String linkRemotePublic(GroupLink link) => _publicByLink[link.id]!;
  Future<void> accessChanged() {
    final pause = !canAct();
    images.accessChanged(pause);
    files.accessChanged(pause);
    return _run(() async {
      if (pause) await images.cancel();
      if (pause) await files.cancel();
      if (canAct() && hosting) {
        for (final link in links.values.toList()) {
          await _admit(link);
        }
      }
      if (_visible != null && canAct()) await _readVisible();
      _notify();
    });
  }

  Future<void> _event(Map<String, dynamic> event) async {
    switch (event['type']) {
      case 'peers':
        nearby = (event['peers'] as List)
            .map((p) => Map<String, dynamic>.from(p as Map))
            .toList();
        state = nearby.isEmpty
            ? 'No nearby groups found'
            : 'Choose a nearby host';
      case 'connected':
        final id = event['link'] as String;
        if (!running ||
            links.containsKey(id) ||
            (hosting ? links.length >= groupLimit - 1 : links.isNotEmpty)) {
          await transport.closeLink(id);
          return;
        }
        final link = GroupLink(
          id,
          await SecureSession.create(store.identity, store.name),
        );
        links[id] = link;
        link.timer = Timer(
          timeout,
          () => unawaited(
            _run(() async {
              if (identical(links[id], link) && !link.admitted) {
                await _drop(id);
                error = 'Member verification timed out.';
                _notify();
              }
            }),
          ),
        );
        await transport.send(id, jsonEncode(link.session.hello));
      case 'frame':
        final id = event['link'] as String;
        final link = links[id];
        if (link == null) return;
        try {
          await _frame(link, event['frame'] as String);
        } catch (_) {
          await _drop(id);
          error =
              'A group link failed verification or storage. Reconnect and compare fresh codes.';
        }
      case 'disconnected':
        await _drop(event['link'] as String, close: false);
      case 'stopped':
        await _stop();
        error =
            'Group connection ended. History is saved; reconnect and verify again.';
      case 'error':
        await _stop();
        error =
            'Group connection failed. Check Wi-Fi and Nearby permission, then try again.';
    }
    _notify();
  }

  Future<void> _frame(GroupLink link, String raw) async {
    if (utf8.encode(raw).length > 65536) {
      throw const FormatException('Group frame too large');
    }
    final frame = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    if (frame['kind'] == 'hello') {
      await link.session.acceptHello(frame);
      _publicByLink[link.id] = frame['identity'] as String;
      state = 'Compare the code with ${link.name}';
      return;
    }
    final p = await link.session.decrypt(frame);
    if (p['type'] == 'groupVerified') {
      if (p['version'] != 1 || link.remoteVerified) {
        throw const FormatException('Invalid group verification');
      }
      link.remoteVerified = true;
      link.supportsImages =
          p['features'] is List &&
          (p['features'] as List).contains('group-image-v1');
      link.supportsFiles =
          p['features'] is List &&
          (p['features'] as List).contains('group-file-v1');
      await _admit(link);
      return;
    }
    if (!link.verified) throw const FormatException('Unverified group member');
    if (p['type'] is String && (p['type'] as String).startsWith('groupFile')) {
      if (!link.admitted || !link.supportsFiles || !supportsFiles) {
        throw const FormatException('Unsupported group file');
      }
      await files.handle(link, p);
      return;
    }
    if ((p['type'] as Object?) is String &&
        (p['type'] as String).startsWith('groupImage')) {
      if (!link.admitted || !link.supportsImages || !supportsImages) {
        throw const FormatException('Unsupported group image');
      }
      await images.handle(link, p);
      return;
    }
    switch (p['type']) {
      case 'groupRoster':
        if (hosting ||
            p['version'] != 1 ||
            !groupIdValid(p['group']) ||
            !groupIdValid(p['epoch']) ||
            p['host'] != linkRemotePublic(link) ||
            p['title'] is! String ||
            (p['title'] as String).trim().isEmpty ||
            (p['title'] as String).length > 64 ||
            p['view'] is! int ||
            (p['view'] as int) <= view ||
            (p['view'] as int) > 1000000000 ||
            p['members'] is! List ||
            (p['members'] as List).length > groupLimit) {
          throw const FormatException('Invalid group membership');
        }
        if (active != null &&
            (p['group'] != active!.id || p['epoch'] != epoch)) {
          throw const FormatException('Group session changed');
        }
        final roster = <GroupMember>[];
        for (final m in p['members'] as List) {
          roster.add(await GroupMember.parse(m as Map));
        }
        if (roster.map((m) => m.id).toSet().length != roster.length ||
            !roster.any((m) => m.id == selfId) ||
            !roster.any((m) => m.id == link.session.peerId)) {
          throw const FormatException('Invalid group membership');
        }
        final id = p['group'] as String;
        final old = histories.where((g) => g.id == id);
        if (old.isNotEmpty && old.first.host != p['host']) {
          throw const FormatException('Group host changed');
        }
        active = old.isEmpty
            ? GroupHistory(
                id: id,
                title: p['title'] as String,
                host: p['host'] as String,
              )
            : old.first;
        await images.membershipChanged();
        await files.membershipChanged();
        members = roster;
        epoch = p['epoch'] as String;
        view = p['view'] as int;
        await store.saveGroupHistory(active!);
        await _reload();
        link.admitted = true;
        link.timer?.cancel();
        _joinTimer?.cancel();
        state = 'Joined • ${members.length} verified members';
      case 'groupText':
        if (active == null || !link.admitted) {
          throw const FormatException('No admitted group');
        }
        final m = await GroupText.parse({
          'envelope': p['message'],
          'receipts': <String, String>{},
          'read': false,
        });
        if (m.image != null || m.file != null) {
          throw const FormatException('Use group attachment transfers');
        }
        if (m.envelope['group'] != active!.id ||
            m.envelope['host'] != active!.host ||
            m.envelope['epoch'] != epoch ||
            !m.targets.contains(selfId) ||
            !members.any(
              (a) => a.id == m.author && a.public == m.envelope['author'],
            )) {
          throw const FormatException('Wrong group or author');
        }
        if (hosting && m.author != link.session.peerId) {
          throw const FormatException('Forged sender');
        }
        if (m.envelope['view'] != view) {
          if (hosting) {
            await _send(link, {'type': 'groupRejected', 'key': m.key});
            return;
          }
          throw const FormatException('Stale membership');
        }
        final targetIds = members.map((m) => m.id).toList()..sort();
        if (jsonEncode(m.targets) != jsonEncode(targetIds)) {
          throw const FormatException('Wrong recipients');
        }
        if (hosting) {
          final saved = m.copy(
            receipts: {
              for (final id in m.targets)
                id: id == selfId || id == m.author ? 'received' : 'pending',
            },
          );
          final inserted = await _persist(saved);
          if (inserted) {
            _receiptTimers[m.key] = Timer(
              receiptTimeout,
              () => unawaited(
                _run(() async {
                  await _uncertain(m.key);
                  _notify();
                }),
              ),
            );
            await _broadcast({
              'type': 'groupText',
              'message': m.envelope,
            }, except: m.author);
          }
          await _send(link, {
            'type': 'groupReceipt',
            'key': m.key,
            'member': selfId,
          });
        } else {
          await _persist(m);
          await _send(link, {
            'type': 'groupReceipt',
            'key': m.key,
            'member': selfId,
          });
        }
      case 'groupReceipt':
        final key = p['key'], member = p['member'];
        if (!link.admitted || key is! String || member is! String) {
          throw const FormatException('Invalid receipt');
        }
        if (hosting && member != link.session.peerId) {
          throw const FormatException('Forged receipt');
        }
        final message = active?.messages.where((m) => m.key == key);
        if (message == null || message.isEmpty) return;
        final m = message.first;
        if (hosting && (m.image != null || m.file != null)) {
          throw const FormatException(
            'Attachment receipts must complete their transfer',
          );
        }
        if (!m.targets.contains(member) ||
            !members.any((m) => m.id == member)) {
          throw const FormatException('Wrong receipt member');
        }
        // The host can report receipts, but cannot change a signed message's author.
        if (!hosting && !_attempted.contains(key)) return;
        await _receipt(key, member);
        if (hosting && m.author != selfId) {
          final authorLinks = links.values.where(
            (l) => l.admitted && l.session.peerId == m.author,
          );
          if (authorLinks.isNotEmpty) {
            await _send(authorLinks.first, {
              'type': 'groupReceipt',
              'key': key,
              'member': member,
            });
          }
        }
      case 'groupRejected':
        if (hosting || !link.admitted || p['key'] is! String) {
          throw const FormatException('Invalid rejection');
        }
        await _uncertain(p['key'] as String);
        error =
            'Membership changed before delivery. Check the member list and send again.';
      default:
        throw const FormatException('Unsupported group payload');
    }
  }

  Future<bool> _persist(
    GroupText message, {
    bool outgoingText = false,
    int? draftRevision,
    String? draftText,
  }) async {
    final group = active!;
    final old = group.messages.where((m) => m.key == message.key);
    if (old.isNotEmpty) {
      if (old.first.envelope['signature'] != message.envelope['signature']) {
        throw const FormatException('Conflicting group message');
      }
      return false;
    }
    if (group.messages.length >= 10000) {
      throw const FormatException(
        'Group history is full. Export and delete it before continuing.',
      );
    }
    if (message.image != null || message.file != null) {
      if (message.image != null && message.imageBytes == null ||
          message.file != null && message.fileBytes == null) {
        throw const FormatException('Incomplete group attachment');
      }
      if (group.messages.fold<int>(
                0,
                (n, m) => n + (m.image?.length ?? 0) + (m.file?.length ?? 0),
              ) +
              (message.image?.length ?? 0) +
              (message.file?.length ?? 0) >
          groupAttachmentHistoryMaxBytes) {
        throw const FormatException(
          'Group attachment history is full (16 MiB). Export and delete it before continuing.',
        );
      }
    }
    final next = group.copy(
      messages: [
        ...group.messages,
        message.copy(
          read:
              message.author == selfId ||
              (_visible != null && _visibleId == group.id && canAct()),
        ),
      ],
      updated: DateTime.now().millisecondsSinceEpoch,
    );
    if (outgoingText) {
      await drafts.acceptGroupOutgoing(
        next,
        draftRevision: draftRevision,
        draftText: draftText,
        canAccept: () => canSend && active?.id == next.id,
      );
    } else {
      await store.saveGroupHistory(next);
    }
    active = next;
    await _reload();
    if (message.author != selfId) {
      unawaited(
        notifications?.incoming(
          'group:${group.id}',
          group.title,
          message.text,
          isReading: () =>
              _visible != null && _visibleId == group.id && canAct(),
        ),
      );
    }
    return true;
  }

  Future<bool> sendText(
    String text, {
    int? draftRevision,
    String? draftText,
  }) async {
    final intendedGroup = active?.id;
    var sent = false;
    await _run(() async {
      if (!canSend || active?.id != intendedGroup) return;
      text = text.trim();
      if (text.isEmpty || utf8.encode(text).length > 4096) {
        throw const FormatException('Messages must be 1–4096 UTF-8 bytes.');
      }
      if (members.length < 2) {
        throw const FormatException('Wait for a verified member to join.');
      }
      final m = await GroupText.create(
        store.identity,
        store.name,
        group: active!.id,
        host: active!.host,
        epoch: epoch!,
        view: view,
        text: text,
        targets: members.map((m) => m.id).toList(),
      );
      if (!canSend) return;
      await _persist(
        m.copy(receipts: {...m.receipts, selfId!: 'received'}),
        outgoingText: true,
        draftRevision: draftRevision,
        draftText: draftText,
      );
      _attempted.add(m.key);
      _receiptTimers[m.key] = Timer(
        receiptTimeout,
        () => unawaited(
          _run(() async {
            await _uncertain(m.key);
            _notify();
          }),
        ),
      );
      if (canAct()) {
        try {
          if (hosting) {
            await _broadcast({'type': 'groupText', 'message': m.envelope});
          } else {
            await _send(links.values.first, {
              'type': 'groupText',
              'message': m.envelope,
            });
          }
        } catch (_) {
          await _uncertain(m.key);
          error = 'Message saved; delivery is unconfirmed.';
        }
      } else {
        await _uncertain(m.key);
      }
      sent = true;
      _notify();
    });
    return sent;
  }

  Future<void> _receipt(String key, String member) async {
    if (active == null) return;
    final next = active!.copy(
      messages: [
        for (final m in active!.messages)
          if (m.key == key)
            m.copy(receipts: {...m.receipts, member: 'received'})
          else
            m,
      ],
    );
    await store.saveGroupHistory(next);
    active = next;
    await _reload();
    if (next.messages
        .firstWhere((m) => m.key == key)
        .receipts
        .values
        .every((s) => s == 'received')) {
      _receiptTimers.remove(key)?.cancel();
    }
    images.receiptsChanged();
    files.receiptsChanged();
  }

  Future<void> _uncertain(String key) async {
    _receiptTimers.remove(key)?.cancel();
    if (active == null) return;
    final next = active!.copy(
      messages: [
        for (final m in active!.messages)
          if (m.key == key)
            m.copy(
              receipts: {
                for (final e in m.receipts.entries)
                  e.key: e.value == 'pending' ? 'unconfirmed' : e.value,
              },
            )
          else
            m,
      ],
    );
    await store.saveGroupHistory(next);
    active = next;
    await _reload();
    images.receiptsChanged();
    files.receiptsChanged();
  }

  Future<void> _drop(
    String id, {
    bool close = true,
    bool announce = true,
  }) async {
    final link = links.remove(id);
    _publicByLink.remove(id);
    if (link == null) return;
    link.timer?.cancel();
    for (final hub in <GroupAttachments<dynamic>>[images, files]) {
      try {
        await hub.drop(id);
      } catch (_) {
        error = 'Attachment delivery is unconfirmed.';
      }
    }
    if (close) {
      try {
        await transport.closeLink(id);
      } catch (_) {}
    }
    if (hosting && link.admitted) {
      members = members.where((m) => m.id != link.session.peerId).toList();
      if (announce) await _roster();
      state = 'Hosting • ${members.length} verified members';
    } else if (!hosting) {
      await _stop();
      error = 'The host disconnected. History is saved; join and verify again.';
    }
  }

  Future<void> stop() => _run(() async {
    await _stop();
    _notify();
  });
  Future<void> _stop() async {
    images.stop();
    files.stop();
    _joinTimer?.cancel();
    _joinTimer = null;
    for (final l in links.values) {
      l.timer?.cancel();
    }
    links.clear();
    _publicByLink.clear();
    for (final timer in _receiptTimers.values) {
      timer.cancel();
    }
    _receiptTimers.clear();
    _attempted.clear();
    try {
      if (active != null) {
        final next = active!.copy(
          messages: [
            for (final m in active!.messages)
              m.copy(
                receipts: {
                  for (final e in m.receipts.entries)
                    e.key: e.value == 'pending' ? 'unconfirmed' : e.value,
                },
              ),
          ],
        );
        await store.saveGroupHistory(next);
      }
    } finally {
      try {
        await transport.stop();
      } finally {
        active = null;
        hosting = false;
        running = false;
        epoch = null;
        view = 0;
        members = [];
        nearby = [];
        state = 'Offline';
        await _reload();
      }
    }
  }

  void setVisible(Object route, String id, bool visible) {
    if (visible) {
      _visible = route;
      _visibleId = id;
      unawaited(_run(_readVisible));
    } else if (identical(_visible, route)) {
      _visible = null;
      _visibleId = null;
    }
  }

  Future<void> _readVisible() async {
    if (_visible == null || !canAct()) return;
    final found = histories.where((g) => g.id == _visibleId);
    if (found.isEmpty || found.first.unread == 0) return;
    await store.saveGroupHistory(
      found.first.copy(
        messages: found.first.messages.map((m) => m.copy(read: true)).toList(),
      ),
    );
    unawaited(notifications?.cancel('group:${found.first.id}'));
    await _reload();
    _notify();
  }

  Future<bool> setPinned(String id, bool pinned) =>
      _manageGroup(() => store.setGroupPinned(id, pinned));

  Future<bool> setArchived(String id, bool archived) =>
      _manageGroup(() => store.setGroupArchived(id, archived));

  Future<bool> _manageGroup(Future<bool> Function() action) async {
    final access = accessRevision?.call();
    var success = false;
    await _run(() async {
      if (!canAct() || access != accessRevision?.call()) return;
      error = null;
      try {
        if (!await action()) throw StateError('Group no longer exists');
        await _reload();
        success = true;
      } catch (_) {
        error = 'Could not update this group. Please try again.';
      }
      _notify();
    });
    return success;
  }

  Future<void> delete(String id) => _run(() async {
    if (!canAct()) return;
    if (active?.id == id) await _stop();
    await drafts.deleteGroupHistory(id);
    await _reload();
    _notify();
    unawaited(notifications?.cancel('group:$id'));
  });
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    images.stop();
    files.stop();
    drafts.removeListener(_notify);
    if (_ownsDrafts) drafts.dispose();
    _disposed = true;
    _subscription?.cancel();
    _joinTimer?.cancel();
    for (final l in links.values) {
      l.timer?.cancel();
    }
    for (final t in _receiptTimers.values) {
      t.cancel();
    }
    unawaited(transport.stop().catchError((Object _) {}));
    super.dispose();
  }
}
