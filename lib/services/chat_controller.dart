import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../core/local_store.dart';
import '../core/models.dart';
import '../core/chat_backup.dart';
import 'backup_files.dart';
import '../core/secure_session.dart';
import 'transport.dart';
import 'draft_controller.dart';

class ChatController extends ChangeNotifier {
  ChatController(this.transport, this.store, {this.isDemo = false});
  final bool isDemo;
  final Transport transport;
  final LocalStore store;
  late final drafts = DraftController(store);
  late final backupFiles = createBackupFiles();
  // Only encrypted file bytes survive the system picker closing locked routes.
  Uint8List? pendingBackup;
  String? backupNotice;
  bool get appAccessible => _appAccessible;
  bool get appForeground => _appForeground;
  int accessRevision = 0;
  void backupFilePicked(Uint8List? bytes, {String? notice}) {
    pendingBackup = bytes;
    backupNotice = notice;
    notifyListeners();
  }

  StreamSubscription<Map<String, dynamic>>? _subscription;
  Future<void> _queue = Future<void>.value();
  SecureSession? _session;
  Timer? _timeout;
  final Map<String, Timer> _ackTimers = {};
  bool loading = true;
  bool initialized = false;
  bool started = false;
  bool scanning = false;
  bool localVerified = false;
  bool remoteVerified = false;
  String state = 'Offline';
  String? error;
  List<Peer> peers = [];
  List<Conversation> conversations = [];
  List<ChatMessage> messages = [];
  String? selectedPeer;
  String selectedName = '';
  int historyRevision = 0;
  Object? _visibleChat;
  bool _appAccessible = true;
  bool _appForeground = true;
  String get profileName => store.name;
  String? get code => _session?.verificationCode;
  String? get connectedPeer => _session?.peerId;
  bool get ready => localVerified && remoteVerified && _session != null;
  bool get canSend => ready && selectedPeer == connectedPeer;

  bool get _canReadSelected =>
      initialized &&
      _visibleChat != null &&
      _appAccessible &&
      _appForeground &&
      selectedPeer != null &&
      (selectedPeer != connectedPeer || ready);

  // Selection/connection alone does not mean a conversation is being read.
  // Route tokens keep disposal of an old screen from hiding a newer one.
  void setChatVisible(Object screen, bool visible) {
    if (visible) {
      if (identical(_visibleChat, screen)) return;
      _visibleChat = screen;
      _readVisible();
    } else if (identical(_visibleChat, screen)) {
      _visibleChat = null;
    }
  }

  void setAppAccess(bool accessible) {
    if (_appAccessible == accessible) return;
    _appAccessible = accessible;
    accessRevision++;
    _readVisible();
  }

  Future<BackupData> backupSnapshot() async {
    late BackupData result;
    Object? failure;
    await _run(() async {
      try {
        if (!initialized || !_appAccessible || !_appForeground) {
          throw const FormatException('Unlock the app before backing up.');
        }
        result = await drafts.exportBackup();
      } catch (e) {
        failure = e;
      }
    });
    if (failure != null) throw failure!;
    return result;
  }

  Future<BackupMerge> restoreBackup(
    BackupData data, {
    bool moveIdentity = false,
    required int accessToken,
  }) async {
    late BackupMerge result;
    Object? failure;
    await _run(() async {
      try {
        if (!initialized ||
            !_appAccessible ||
            !_appForeground ||
            accessToken != accessRevision) {
          throw const FormatException(
            'Unlock the app and preview the backup again.',
          );
        }
        if (moveIdentity) {
          await transport.stop();
          started = false;
          await _reset();
          selectedPeer = null;
          selectedName = '';
        }
        result = await drafts.importBackup(data, moveIdentity: moveIdentity);
        conversations = await store.conversations();
        if (selectedPeer != null) {
          messages = await store.messages(selectedPeer!);
        }
        historyRevision++;
        notifyListeners();
      } catch (e) {
        if (store.identityRecoveryRequired) {
          initialized = false;
          await transport.stop();
          await _reset();
          error =
              'Identity recovery needs a restart. Close and reopen LocalChat before connecting.';
          notifyListeners();
        }
        failure = e;
      }
    });
    if (failure != null) throw failure!;
    return result;
  }

  void setAppForeground(bool foreground) {
    if (_appForeground == foreground) return;
    _appForeground = foreground;
    _readVisible();
    // Refresh relative activity labels after time spent outside the app.
    if (foreground) notifyListeners();
  }

  void _readVisible() {
    if (!_canReadSelected) return;
    unawaited(
      _run(() async {
        // Recheck after earlier frame writes, lock or navigation events.
        if (!_canReadSelected) return;
        await _refresh();
        notifyListeners();
      }),
    );
  }

  // One queue owns protocol counters, writes and state. Async stream listeners
  // otherwise overlap when several socket frames arrive in the same read.
  Future<void> _run(Future<void> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.catchError((Object e, StackTrace s) async {
      error = e is FormatException ? e.message : e.toString();
      notifyListeners();
    });
    return _queue;
  }

  Future<void> initialize() => _run(() async {
    if (initialized) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      await store.open();
      conversations = await store.conversations();
      historyRevision++;
      _subscription = transport.events.listen(
        (event) {
          unawaited(_run(() => _event(event)));
        },
        onError: (Object e) {
          error = e.toString();
          notifyListeners();
        },
      );
      initialized = true;
    } finally {
      loading = false;
      notifyListeners();
    }
  });

  Future<void> start() => _run(() async {
    if (!initialized) {
      throw StateError('Local storage is unavailable. Retry setup.');
    }
    error = null;
    await transport.start(store.name);
    started = true;
    state = 'Available nearby';
    notifyListeners();
    await transport.scan();
  });
  Future<void> scan() => _run(() async {
    error = null;
    peers = [];
    await transport.scan();
    notifyListeners();
  });
  Future<void> connect(Peer peer) => _run(() async {
    error = null;
    if (_session != null || state == 'Connecting') await _disconnect();
    selectedName = peer.name;
    state = 'Connecting';
    _armTimeout();
    notifyListeners();
    try {
      await transport.connect(peer.address);
    } catch (_) {
      await _reset();
      rethrow;
    }
  });

  void _armTimeout() {
    _timeout?.cancel();
    _timeout = Timer(const Duration(seconds: 90), () {
      unawaited(
        _run(() async {
          error = 'Connection or verification timed out. Try again.';
          await _disconnect();
        }),
      );
    });
  }

  Future<void> _event(Map<String, dynamic> event) async {
    if (store.identityRecoveryRequired) return;
    switch (event['type']) {
      case 'peers':
        peers = (event['peers'] as List)
            .map((p) => Peer(p['address'] as String, p['name'] as String))
            .toList();
      case 'scanning':
        scanning = event['active'] == true;
      case 'connected':
        if (_session != null) {
          await _disconnect();
          return;
        }
        _session = await SecureSession.create(store.identity, store.name);
        localVerified = false;
        remoteVerified = false;
        state = 'Exchanging keys';
        _armTimeout();
        await transport.send(jsonEncode(_session!.hello));
      case 'frame':
        try {
          await _frame(event['frame'] as String);
        } catch (_) {
          error = 'Security check failed. Connection closed.';
          await _disconnect();
        }
      case 'disconnected':
        await _reset();
      case 'error':
        error = event['message'] as String;
        if (state == 'Connecting' || _session != null) await _disconnect();
      case 'wifi':
        if (event['enabled'] != true) {
          error = 'Turn on Wi-Fi to use nearby chat.';
          await _disconnect();
        }
    }
    notifyListeners();
  }

  Future<void> _frame(String raw) async {
    if (utf8.encode(raw).length > 65536 || _session == null) {
      throw const FormatException('Unexpected frame');
    }
    final frame = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    if (frame['kind'] == 'hello') {
      await _session!.acceptHello(frame);
      selectedPeer = connectedPeer;
      selectedName = _session!.peerName!;
      messages = await store.messages(selectedPeer!);
      state = 'Compare security codes';
      return;
    }
    final payload = await _session!.decrypt(frame);
    switch (payload['type']) {
      case 'verified':
        if (remoteVerified) {
          throw const FormatException('Repeated verification');
        }
        remoteVerified = true;
        await _updateReady();
      case 'text':
        if (!ready) throw const FormatException('Peer has not been verified');
        final text = payload['text'];
        final id = payload['id'];
        final timestamp = payload['timestamp'];
        if (text is! String ||
            text.trim().isEmpty ||
            utf8.encode(text).length > 4096 ||
            id is! String ||
            !RegExp(r'^[A-Za-z0-9_-]{24}$').hasMatch(id) ||
            timestamp is! int ||
            timestamp < 0 ||
            timestamp > 8640000000000000) {
          throw const FormatException('Invalid text message');
        }
        await store.savePeer(connectedPeer!, _session!.peerName!);
        await store.saveMessage(
          ChatMessage(
            id: id,
            peerId: connectedPeer!,
            text: text,
            timestamp: timestamp,
            outgoing: false,
            status: 'received',
          ),
        );
        historyRevision++;
        await _sendPayload({'type': 'ack', 'id': id});
        await _refresh();
      case 'ack':
        if (!ready || payload['id'] is! String) {
          throw const FormatException('Invalid acknowledgement');
        }
        final id = payload['id'] as String;
        final timer = _ackTimers.remove(id);
        if (timer != null) {
          timer.cancel();
          await store.setStatus(id, connectedPeer!, 'delivered');
          await _refresh();
        }
      default:
        throw const FormatException('Unsupported payload type');
    }
  }

  Future<void> confirmCode() => _run(() async {
    if (code == null || localVerified) return;
    error = null;
    try {
      await _sendPayload({'type': 'verified'});
      localVerified = true;
      await _updateReady();
    } catch (_) {
      await _disconnect();
      rethrow;
    }
    notifyListeners();
  });
  Future<void> _updateReady() async {
    if (ready) {
      _timeout?.cancel();
      state = 'Encrypted • verified';
      await store.savePeer(connectedPeer!, _session!.peerName!);
      historyRevision++;
      await _refresh();
    } else {
      state = localVerified
          ? 'Waiting for peer verification'
          : 'Compare security codes';
    }
  }

  Future<void> _sendPayload(Map<String, dynamic> payload) async {
    await transport.send(jsonEncode(await _session!.encrypt(payload)));
  }

  Future<bool> sendText(String text) async {
    final intendedPeer = selectedPeer;
    final draftRevision =
        intendedPeer == null ||
            !drafts.isLoaded(intendedPeer) ||
            drafts.textFor(intendedPeer) != text
        ? null
        : drafts.revisionFor(intendedPeer);
    var sent = false;
    await _run(() async {
      error = null;
      if (!canSend ||
          selectedPeer != intendedPeer ||
          !_appAccessible ||
          !_appForeground) {
        throw StateError('Verify both phones before sending');
      }
      text = text.trim();
      if (text.isEmpty || utf8.encode(text).length > 4096) {
        throw StateError('Messages must be 1–4096 UTF-8 bytes');
      }
      final id = randomId();
      final peer = connectedPeer!;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      await store.savePeer(peer, _session!.peerName!);
      await store.saveMessage(
        ChatMessage(
          id: id,
          peerId: peer,
          text: text,
          timestamp: timestamp,
          outgoing: true,
          status: 'sending',
        ),
      );
      historyRevision++;
      try {
        await _sendPayload({
          'type': 'text',
          'id': id,
          'timestamp': timestamp,
          'text': text,
        });
        sent = true;
        _ackTimers[id] = Timer(const Duration(seconds: 30), () {
          unawaited(
            _run(() async {
              _ackTimers.remove(id);
              await store.setStatus(id, peer, 'unconfirmed');
              await _refresh();
              notifyListeners();
            }),
          );
        });
      } catch (_) {
        await store.setStatus(id, peer, 'unconfirmed');
        await _disconnect();
        rethrow;
      } finally {
        await _refresh();
        notifyListeners();
      }
    });
    // A route may have closed, locked, or switched peers during the send.
    // Clear only the captured draft; newer edits belong to another send.
    if (sent && intendedPeer != null && draftRevision != null) {
      await drafts.clearAfterSend(intendedPeer, draftRevision);
    }
    return sent;
  }

  Future<void> _refresh() async {
    if (selectedPeer != null) messages = await store.messages(selectedPeer!);
    // Only clear read state after the visible history has decrypted successfully.
    if (_canReadSelected) await store.markRead(selectedPeer!);
    conversations = await store.conversations();
  }

  Future<bool> viewHistory(Conversation peer) async {
    var opened = false;
    await _run(() async {
      error = null;
      final history = await store.messages(peer.id);
      final summaries = await store.conversations();
      if (!summaries.any((p) => p.id == peer.id)) {
        throw StateError('This conversation has been deleted.');
      }
      selectedPeer = peer.id;
      selectedName = peer.name;
      messages = history;
      conversations = summaries;
      if (_canReadSelected) {
        await store.markRead(peer.id);
        conversations = await store.conversations();
      }
      opened = true;
      notifyListeners();
    });
    return opened;
  }

  Future<void> viewConnected() => _run(() async {
    if (connectedPeer == null) return;
    selectedPeer = connectedPeer;
    selectedName = _session!.peerName!;
    await _refresh();
    notifyListeners();
  });
  Future<void> rename(String name) => _run(() async {
    error = null;
    name = name.trim();
    if (name.isEmpty || name.length > 32) {
      throw StateError('Use a name with 1–32 characters');
    }
    if (started) {
      await _disconnect();
      await transport.stop();
      started = false;
    }
    await store.rename(name);
    notifyListeners();
  });
  Future<void> clearHistory() => _run(() async {
    await drafts.clearHistory();
    historyRevision++;
    messages = [];
    conversations = [];
    // An offline conversation no longer exists after deletion. Keep only the
    // active session selected, so a draft cannot be left in an unreachable chat.
    selectedPeer = connectedPeer;
    selectedName = connectedPeer == null ? '' : _session!.peerName!;
    notifyListeners();
  });

  Future<bool> setPinned(String peer, bool pinned) =>
      _manageConversation(() => store.setPinned(peer, pinned));

  Future<bool> setArchived(String peer, bool archived) =>
      _manageConversation(() => store.setArchived(peer, archived));

  Future<bool> _manageConversation(Future<bool> Function() action) async {
    var success = false;
    await _run(() async {
      error = null;
      try {
        if (!await action()) throw StateError('Conversation no longer exists');
        conversations = await store.conversations();
        historyRevision++;
        success = true;
      } catch (_) {
        error = 'Could not update this chat. Please try again.';
      }
      notifyListeners();
    });
    return success;
  }

  Future<bool> deleteConversation(String peer) async {
    var success = false;
    await _run(() async {
      error = null;
      try {
        if (connectedPeer == peer) await _disconnect();
        await drafts.deleteConversation(peer);
        historyRevision++;
        if (selectedPeer == peer) {
          selectedPeer = null;
          selectedName = '';
          messages = [];
        }
        conversations = await store.conversations();
        success = true;
      } catch (_) {
        error = 'Could not delete this chat. Please try again.';
      }
      notifyListeners();
    });
    return success;
  }

  Future<void> _reset() async {
    _timeout?.cancel();
    final peer = connectedPeer;
    for (final entry in _ackTimers.entries) {
      entry.value.cancel();
      if (peer != null) await store.setStatus(entry.key, peer, 'unconfirmed');
    }
    _ackTimers.clear();
    _session = null;
    localVerified = false;
    remoteVerified = false;
    state = started ? 'Available nearby' : 'Offline';
    await _refresh();
  }

  Future<void> _disconnect() async {
    try {
      await transport.disconnect();
    } finally {
      await _reset();
      notifyListeners();
    }
  }

  Future<void> disconnect() => _run(_disconnect);
  void dismissError() {
    error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    drafts.dispose();
    _timeout?.cancel();
    for (final timer in _ackTimers.values) {
      timer.cancel();
    }
    unawaited(_subscription?.cancel());
    unawaited(transport.stop());
    super.dispose();
  }
}
