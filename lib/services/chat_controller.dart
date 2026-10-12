import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import '../core/local_store.dart';
import '../core/models.dart';
import '../core/chat_backup.dart';
import 'backup_files.dart';
import '../core/secure_session.dart';
import 'transport.dart';
import 'draft_controller.dart';
import 'nearby_support.dart';
import 'chat_notifications.dart';
import 'background_connection.dart';
import 'group_controller.dart';
import 'group_transport.dart';

class ChatController extends ChangeNotifier {
  ChatController(
    this.transport,
    this.store, {
    this.isDemo = false,
    this.ackTimeout = const Duration(seconds: 30),
    this.connectionTimeout = const Duration(seconds: 90),
    NearbyTools? nearbyTools,
    ChatNotifications? notifications,
    BackgroundConnection? background,
    GroupTransport? groupTransport,
  }) : nearbyTools =
           nearbyTools ??
           (transport is WifiDirectTransport
               ? const AndroidNearbyTools()
               : const DemoNearbyTools()),
       notifications =
           notifications ??
           ChatNotifications(
             transport is WifiDirectTransport
                 ? AndroidNotificationPlatform()
                 : MemoryNotificationPlatform(),
             isDemo: isDemo,
           ),
       background =
           background ??
           BackgroundConnection(
             transport is WifiDirectTransport
                 ? const AndroidBackgroundPlatform()
                 : MemoryBackgroundPlatform(),
             isDemo: isDemo,
           ),
       _groupTransport =
           groupTransport ??
           (transport is WifiDirectTransport
               ? WifiGroupTransport()
               : UnavailableGroupTransport());
  final GroupTransport _groupTransport;
  late final groups = GroupController(
    _groupTransport,
    store,
    prepare: _prepareGroup,
    notifications: notifications,
    canAct: () => initialized && !_disposed && _appAccessible && _appForeground,
  );
  Future<bool> _prepareGroup() => _nearbyAction(() async {
    await _disconnect();
    await transport.stop();
    // Reuse the established Android permission flow before changing radio mode.
    await transport.start(store.name);
    await transport.stop();
    started = false;
    scanning = false;
    peers = [];
    state = 'Group mode';
  }, allowPermissionRequest: true);
  final ChatNotifications notifications;
  final BackgroundConnection background;
  int? _transportGeneration;
  final bool isDemo;
  final Duration ackTimeout;
  final Duration connectionTimeout;
  final NearbyTools nearbyTools;
  NearbyStatus? nearbyStatus;
  ConnectionIssue? connectionIssue;
  Peer? lastNearbyPeer;
  bool nearbyBusy = false;
  bool _checkingAccess = false;
  bool get canUseNearby =>
      initialized &&
      !_disposed &&
      _appAccessible &&
      _appForeground &&
      !nearbyBusy;
  bool get canScan =>
      canUseNearby &&
      started &&
      !scanning &&
      _session == null &&
      state != 'Connecting';
  bool get canReconnect =>
      canUseNearby &&
      started &&
      _session == null &&
      state != 'Connecting' &&
      lastNearbyPeer != null &&
      peers.any((p) => p.address == lastNearbyPeer!.address);
  bool get hasConnectionHelp =>
      connectionIssue != null && error == connectionIssue!.title;
  String get queueWaitingReason => outboxPaused
      ? 'Resolve the storage error, then tap Resume outbox in this chat.'
      : selectedPeer == connectedPeer && ready
      ? 'Queued messages send in order while the app is unlocked and in the foreground.'
      : !started
      ? 'Open Nearby and tap Go nearby, then connect to this phone.'
      : selectedPeer == connectedPeer && !ready
      ? 'Both phones must compare the fresh code and tap Codes match.'
      : 'Reconnect to this phone from Nearby and verify the fresh code on both phones.';
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
  final _attemptedIds = <String>{};
  final _pausedOutboxes = <String>{};
  bool _drainScheduled = false;
  bool _disposed = false;
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
  bool get canSubmit =>
      initialized &&
      _appAccessible &&
      _appForeground &&
      selectedPeer != null &&
      (canSend || conversations.any((p) => p.id == selectedPeer));
  bool get outboxPaused =>
      selectedPeer != null && _pausedOutboxes.contains(selectedPeer);
  int get queuedCount =>
      messages.where((m) => m.outgoing && m.status == 'queued').length;

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
    notifications.setAccessible(_appAccessible && _appForeground);
    accessRevision++;
    unawaited(groups.accessChanged());
    _readVisible();
    if (accessible) {
      _requestBackground();
      unawaited(refreshNearbyAccess());
      _requestDrain();
    }
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
    await groups.stop();
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
        await groups.initialize();
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
    unawaited(groups.accessChanged());
    notifications.setAccessible(_appAccessible && _appForeground);
    _readVisible();
    // Refresh relative activity labels after time spent outside the app.
    if (foreground) notifyListeners();
    if (foreground) {
      unawaited(notifications.refreshPermission());
      unawaited(background.refresh());
      _requestBackground();
      unawaited(refreshNearbyAccess());
      _requestDrain();
    }
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
      await groups.initialize();
      groups.addListener(_groupChanged);
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

  void _showConnectionIssue(ConnectionIssue issue) {
    connectionIssue = issue;
    error = issue.title;
  }

  Future<void> refreshNearbyAccess() async {
    if (!canUseNearby || _checkingAccess) return;
    _checkingAccess = true;
    await _run(() async {
      try {
        if (!_appAccessible || !_appForeground || _disposed) return;
        final status = await nearbyTools.check();
        if (!_appAccessible || !_appForeground || _disposed) return;
        nearbyStatus = status;
        if (status.issue != null) {
          unawaited(groups.stop());
          if (_session != null || state == 'Connecting') await _disconnect();
          if (status.issue == ConnectionIssue.wifiOff) {
            await transport.stop();
            started = false;
            scanning = false;
            peers = [];
            state = 'Offline';
          }
          _showConnectionIssue(status.issue!);
        } else if (connectionIssue?.isPrerequisite == true ||
            connectionIssue == ConnectionIssue.status) {
          if (hasConnectionHelp) error = null;
          connectionIssue = null;
        }
      } catch (_) {
        _showConnectionIssue(ConnectionIssue.status);
      } finally {
        _checkingAccess = false;
        notifyListeners();
        _requestDrain();
      }
    });
  }

  Future<bool> _nearbyAction(
    Future<void> Function() action, {
    bool allowPermissionRequest = false,
    bool scanningAction = false,
    bool connectingAction = false,
  }) async {
    if (!canUseNearby) return false;
    final access = accessRevision;
    nearbyBusy = true;
    notifyListeners();
    var success = false;
    await _run(() async {
      try {
        if (access != accessRevision ||
            !_appAccessible ||
            !_appForeground ||
            _disposed) {
          return;
        }
        error = null;
        connectionIssue = null;
        nearbyStatus = await nearbyTools.check();
        if (access != accessRevision ||
            !_appAccessible ||
            !_appForeground ||
            _disposed) {
          return;
        }
        final issue = nearbyStatus!.issue;
        if (issue != null &&
            !(allowPermissionRequest && issue == ConnectionIssue.permission)) {
          if (_session != null || state == 'Connecting') await _disconnect();
          if (issue == ConnectionIssue.wifiOff) {
            await transport.stop();
            started = false;
            scanning = false;
            peers = [];
            state = 'Offline';
          }
          _showConnectionIssue(issue);
          return;
        }
        await action();
        success = true;
      } catch (e) {
        if (connectingAction) await _reset();
        if (scanningAction) scanning = false;
        final issue = ConnectionIssue.fromCode(
          e is PlatformException ? e.code : null,
          scanning: scanningAction,
        );
        if (issue == ConnectionIssue.serviceStopped ||
            issue == ConnectionIssue.wifiOff) {
          started = false;
          scanning = false;
          peers = [];
          state = 'Offline';
        }
        _showConnectionIssue(issue);
      } finally {
        nearbyBusy = false;
        notifyListeners();
      }
    });
    return success;
  }

  Future<bool> start() async {
    await groups.stop();
    return _startNearby();
  }

  Future<bool> _startNearby() => _nearbyAction(
    () async {
      await transport.start(store.name);
      nearbyStatus = await nearbyTools.check();
      started = true;
      state = 'Available nearby';
      peers = [];
      if (_appAccessible && _appForeground) await transport.scan();
    },
    allowPermissionRequest: true,
    scanningAction: true,
  );

  Future<bool> scan() async {
    if (!canScan) return false;
    return _nearbyAction(() async {
      peers = [];
      await transport.scan();
    }, scanningAction: true);
  }

  Future<bool> connect(Peer peer) async {
    await groups.stop();
    return _connectNearby(peer);
  }

  Future<bool> _connectNearby(Peer peer) => _nearbyAction(() async {
    if (_session != null || state == 'Connecting') await _disconnect();
    final previousPeer = selectedPeer, previousName = selectedName;
    lastNearbyPeer = peer;
    selectedPeer = null;
    messages = [];
    selectedName = peer.name;
    state = 'Connecting';
    _armTimeout();
    notifyListeners();
    try {
      await transport.connect(peer.address);
    } catch (_) {
      selectedPeer = previousPeer;
      selectedName = previousName;
      rethrow;
    }
  }, connectingAction: true);

  Future<bool> reconnect() async {
    if (!canReconnect) {
      if (canUseNearby) {
        _showConnectionIssue(ConnectionIssue.stalePeer);
        notifyListeners();
      }
      return false;
    }
    return connect(
      peers.firstWhere((p) => p.address == lastNearbyPeer!.address),
    );
  }

  Future<void> openNearbySettings(NearbySettings target) async {
    if (!canUseNearby || isDemo) return;
    nearbyBusy = true;
    notifyListeners();
    try {
      await nearbyTools.openSettings(target);
    } catch (_) {
      _showConnectionIssue(ConnectionIssue.settings);
    } finally {
      nearbyBusy = false;
      notifyListeners();
    }
  }

  void _armTimeout() {
    _timeout?.cancel();
    late final Timer timer;
    timer = Timer(connectionTimeout, () {
      unawaited(
        _run(() async {
          if (_disposed || !identical(_timeout, timer) || ready) return;
          await _disconnect();
          _showConnectionIssue(ConnectionIssue.timeout);
          notifyListeners();
        }),
      );
    });
    _timeout = timer;
  }

  Future<void> _event(Map<String, dynamic> event) async {
    if (_disposed || store.identityRecoveryRequired) return;
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
        if (hasConnectionHelp) error = null;
        connectionIssue = null;
        _transportGeneration = event['generation'] as int?;
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
          await _disconnect();
          _showConnectionIssue(ConnectionIssue.security);
        } finally {
          unawaited(background.frameProcessed(event['generation'] as int?));
        }
      case 'backgroundStatus':
        background.nativeStatus(event);
      case 'backgroundStopped':
        await transport.stop();
        started = false;
        scanning = false;
        peers = [];
        await _reset();
        if (event['reason'] == 'system') {
          _showConnectionIssue(ConnectionIssue.lost);
        }
      case 'disconnected':
        final unexpected = _session != null || state == 'Connecting';
        background.connectionEnded(unexpected: unexpected);
        await _reset();
        if (unexpected && connectionIssue == null) {
          _showConnectionIssue(ConnectionIssue.lost);
        }
      case 'error':
        if (state == 'Connecting' || _session != null) await _disconnect();
        final issue = ConnectionIssue.fromCode(event['code'] as String?);
        if (issue == ConnectionIssue.serviceStopped ||
            issue == ConnectionIssue.wifiOff) {
          started = false;
          scanning = false;
          peers = [];
          state = 'Offline';
        }
        _showConnectionIssue(issue);
      case 'wifi':
        if (event['enabled'] != true) {
          await transport.stop();
          started = false;
          scanning = false;
          peers = [];
          await _disconnect();
          _showConnectionIssue(ConnectionIssue.wifiOff);
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
        final inserted = await store.saveMessage(
          ChatMessage(
            id: id,
            peerId: connectedPeer!,
            text: text,
            timestamp: timestamp,
            outgoing: false,
            status: 'received',
          ),
        );
        if (inserted) {
          final peer = connectedPeer!;
          unawaited(
            notifications.incoming(
              peer,
              _session!.peerName!,
              text,
              isReading: () => selectedPeer == peer && _canReadSelected,
            ),
          );
        }
        historyRevision++;
        await _sendPayload({'type': 'ack', 'id': id});
        await _refresh();
      case 'ack':
        if (!ready || payload['id'] is! String) {
          throw const FormatException('Invalid acknowledgement');
        }
        final id = payload['id'] as String;
        // A late authenticated ACK still confirms a timed-out attempt in this
        // session. Unknown IDs (including restored history) are never confirmed.
        if (_attemptedIds.contains(id)) {
          try {
            await store.changeOutgoingStatus(id, connectedPeer!, [
              'sending',
              'unconfirmed',
              'queued',
            ], 'delivered');
            _attemptedIds.remove(id);
            _ackTimers.remove(id)?.cancel();
            historyRevision++;
            await _refresh();
            _requestDrain();
          } catch (_) {
            _pausedOutboxes.add(connectedPeer!);
            error =
                'Could not save delivery confirmation. This message may be unconfirmed.';
          }
        }
      default:
        throw const FormatException('Unsupported payload type');
    }
  }

  Future<void> confirmCode() => _run(() async {
    if (code == null || localVerified || !_appAccessible || !_appForeground) {
      return;
    }
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
      _timeout = null;
      state = 'Encrypted • verified';
      await store.savePeer(connectedPeer!, _session!.peerName!);
      historyRevision++;
      await _refresh();
      _pausedOutboxes.remove(connectedPeer!);
      _requestDrain();
      _requestBackground();
    } else {
      state = localVerified
          ? 'Waiting for peer verification'
          : 'Compare security codes';
    }
  }

  Future<void> _sendPayload(Map<String, dynamic> payload) async {
    await transport.send(jsonEncode(await _session!.encrypt(payload)));
  }

  Future<void> setBackgroundEnabled(bool enabled) async {
    if (!_appAccessible || !_appForeground) return;
    await background.setEnabled(enabled);
    _requestBackground();
  }

  Future<void> retryBackground() async {
    await background.refresh();
    await _protectBackground();
  }

  void _requestBackground() => unawaited(_protectBackground());
  Future<void> _protectBackground() {
    final session = _session;
    return background.protect(
      _transportGeneration,
      canStart: () =>
          !_disposed &&
          ready &&
          identical(_session, session) &&
          _appAccessible &&
          _appForeground,
      sameConnection: () => !_disposed && ready && identical(_session, session),
    );
  }

  /// True means accepted into local encrypted history, not delivered. The draft
  /// is removed atomically with acceptance, so a failed write is retried by ID.
  Future<bool> sendText(String text, {bool queueIfOffline = false}) async {
    final intendedPeer = selectedPeer;
    final access = accessRevision;
    final draftRevision =
        intendedPeer == null ||
            !drafts.isLoaded(intendedPeer) ||
            drafts.textFor(intendedPeer) != text
        ? null
        : drafts.revisionFor(intendedPeer);
    var accepted = false;
    await _run(() async {
      error = null;
      if (!initialized ||
          access != accessRevision ||
          selectedPeer != intendedPeer ||
          intendedPeer == null ||
          !_appAccessible ||
          !_appForeground) {
        throw const FormatException(
          'Open an unlocked saved chat before sending.',
        );
      }
      final savedPeer = (await store.conversations()).any(
        (p) => p.id == intendedPeer,
      );
      if (!canSend && (!queueIfOffline || !savedPeer)) {
        throw const FormatException('Verify both phones before sending');
      }
      final rawText = text;
      text = text.trim();
      if (text.isEmpty || utf8.encode(text).length > 4096) {
        throw StateError('Messages must be 1–4096 UTF-8 bytes');
      }
      final id = randomId();
      final peer = intendedPeer;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      if (canSend && !savedPeer) {
        await store.savePeer(peer, _session!.peerName!);
      }
      try {
        await drafts.acceptOutgoing(
          ChatMessage(
            id: id,
            peerId: peer,
            text: text,
            timestamp: timestamp,
            outgoing: true,
            status: 'queued',
          ),
          draftRevision: draftRevision,
          draftText: rawText,
          canAccept: () =>
              initialized &&
              _appAccessible &&
              _appForeground &&
              access == accessRevision,
        );
      } catch (_) {
        throw const FormatException(
          'Could not save this message. Your draft is kept; please retry.',
        );
      }
      accepted = true;
      historyRevision++;
      try {
        await _refresh();
      } catch (_) {
        error =
            'Message saved locally. Reopen this chat to refresh its history.';
      } finally {
        notifyListeners();
        _requestDrain();
      }
    });
    return accepted;
  }

  bool _canDrain(String peer) =>
      !_disposed &&
      initialized &&
      ready &&
      peer == connectedPeer &&
      _appAccessible &&
      _appForeground &&
      !_pausedOutboxes.contains(peer) &&
      nearbyStatus?.issue == null &&
      _ackTimers.length < 4;

  bool _validOutgoing(ChatMessage m) =>
      m.outgoing &&
      RegExp(r'^[A-Za-z0-9_-]{24}$').hasMatch(m.id) &&
      m.text.trim().isNotEmpty &&
      utf8.encode(m.text).length <= 4096 &&
      m.timestamp >= 0 &&
      m.timestamp <= 8640000000000000;

  void _requestDrain() {
    final peer = connectedPeer;
    if (peer == null || !_canDrain(peer) || _drainScheduled) return;
    _drainScheduled = true;
    unawaited(
      _run(() async {
        _drainScheduled = false;
        await _drainNext();
      }),
    );
  }

  void _watchAcknowledgement(ChatMessage message) {
    _ackTimers.remove(message.id)?.cancel();
    late final Timer timer;
    timer = Timer(ackTimeout, () {
      unawaited(
        _run(() async {
          if (_disposed || !identical(_ackTimers[message.id], timer)) return;
          _ackTimers.remove(message.id);
          try {
            await store.changeOutgoingStatus(message.id, message.peerId, [
              'sending',
            ], 'unconfirmed');
            historyRevision++;
            await _refresh();
          } catch (_) {
            _pausedOutboxes.add(message.peerId);
            error =
                'Could not update message status. Reconnect or resume the outbox after resolving storage errors.';
          }
          notifyListeners();
          _requestDrain();
        }),
      );
    });
    _ackTimers[message.id] = timer;
  }

  Future<void> _drainNext() async {
    final peer = connectedPeer;
    if (peer == null || !_canDrain(peer)) return;
    ChatMessage? message;
    try {
      final pending = await store.queuedMessages(peer);
      if (pending.isEmpty || !_canDrain(peer)) return;
      message = pending.first;
      if (!_validOutgoing(message)) {
        throw const FormatException('Invalid queued message');
      }
      if (!await store.changeOutgoingStatus(message.id, peer, [
        'queued',
      ], 'sending')) {
        return;
      }
      // Access can change synchronously while the durable transition awaits IO.
      if (!_canDrain(peer)) {
        await store.changeOutgoingStatus(message.id, peer, [
          'sending',
        ], 'queued');
        await _refresh();
        notifyListeners();
        return;
      }
    } catch (_) {
      _pausedOutboxes.add(peer);
      error =
          'Could not load or update queued messages. Resolve the storage issue, then resume the outbox.';
      notifyListeners();
      return;
    }
    final outgoing = message;
    _attemptedIds.add(outgoing.id);
    _watchAcknowledgement(outgoing);
    historyRevision++;
    try {
      final access = accessRevision;
      final frame = await _session!.encrypt({
        'type': 'text',
        'id': outgoing.id,
        'timestamp': outgoing.timestamp,
        'text': outgoing.text,
      });
      if (!_appAccessible || !_appForeground || access != accessRevision) {
        // Encryption consumed a sequence number, so discard this session rather
        // than transmitting after lock or leaving a gap in its frame sequence.
        await store.changeOutgoingStatus(outgoing.id, peer, [
          'sending',
        ], 'queued');
        _ackTimers.remove(outgoing.id)?.cancel();
        _attemptedIds.remove(outgoing.id);
        await _disconnect();
        return;
      }
      await transport.send(jsonEncode(frame));
    } catch (_) {
      error =
          'Send interrupted. This message is unconfirmed; reconnect and verify before retrying it.';
      await _disconnect();
      return;
    }
    try {
      await _refresh();
    } catch (_) {
      error = 'Message sent. Reopen this chat to refresh its history.';
    }
    notifyListeners();
    _requestDrain();
  }

  Future<bool> retryMessage(ChatMessage message) async {
    var queued = false;
    final access = accessRevision;
    await _run(() async {
      error = null;
      if (!_appAccessible ||
          !_appForeground ||
          access != accessRevision ||
          selectedPeer != message.peerId ||
          !initialized ||
          !_validOutgoing(message)) {
        error =
            'Open this chat after unlocking to retry a valid outgoing message.';
      } else {
        try {
          queued = await store.changeOutgoingStatus(
            message.id,
            message.peerId,
            ['unconfirmed'],
            'queued',
          );
          if (!queued) {
            error = 'This message is no longer unconfirmed.';
          } else {
            historyRevision++;
            await _refresh();
            _requestDrain();
          }
        } catch (_) {
          error = 'Could not queue this retry. Please try again.';
        }
      }
      notifyListeners();
    });
    return queued;
  }

  Future<bool> cancelQueuedMessage(ChatMessage message) async {
    var cancelled = false;
    final access = accessRevision;
    await _run(() async {
      error = null;
      if (!_appAccessible ||
          !_appForeground ||
          access != accessRevision ||
          selectedPeer != message.peerId ||
          !message.outgoing ||
          !initialized) {
        return;
      }
      try {
        cancelled = await store.deleteQueuedMessage(message.id, message.peerId);
        if (!cancelled) {
          error = 'This message has already started sending or was removed.';
        } else {
          historyRevision++;
          await _refresh();
          _requestDrain();
        }
      } catch (_) {
        error = 'Could not cancel this queued message. Please retry.';
      }
      notifyListeners();
    });
    return cancelled;
  }

  Future<void> resumeOutbox() => _run(() async {
    if (!_appAccessible ||
        !_appForeground ||
        !initialized ||
        selectedPeer == null) {
      return;
    }
    _pausedOutboxes.remove(selectedPeer);
    error = null;
    await _refresh();
    notifyListeners();
    _requestDrain();
  });

  Future<void> _refresh() async {
    if (selectedPeer != null) messages = await store.messages(selectedPeer!);
    // Only clear read state after the visible history has decrypted successfully.
    if (_canReadSelected) {
      await store.markRead(selectedPeer!);
      unawaited(notifications.cancel(selectedPeer!));
    }
    conversations = await store.conversations();
  }

  Future<bool> viewHistory(
    Conversation peer, {
    int? notificationAccessToken,
  }) async {
    var opened = false;
    await _run(() async {
      if (notificationAccessToken != null &&
          (!_appAccessible ||
              !_appForeground ||
              notificationAccessToken != accessRevision ||
              notifications.pendingPeer != peer.id)) {
        return;
      }
      error = null;
      final history = await store.messages(peer.id);
      final summaries = await store.conversations();
      if (!summaries.any((p) => p.id == peer.id)) {
        throw StateError('This conversation has been deleted.');
      }
      if (notificationAccessToken != null) {
        if (!_appAccessible ||
            !_appForeground ||
            notificationAccessToken != accessRevision ||
            notifications.pendingPeer != peer.id) {
          return;
        }
        _visibleChat = null;
      }
      selectedPeer = peer.id;
      selectedName = peer.name;
      messages = history;
      conversations = summaries;
      if (_canReadSelected) {
        await store.markRead(peer.id);
        unawaited(notifications.cancel(peer.id));
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
  Future<void> rename(String name) async {
    await groups.stop();
    await _rename(name);
  }

  Future<void> _rename(String name) => _run(() async {
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
  Future<void> clearHistory() async {
    await groups.stop();
    await _clearHistory();
  }

  Future<void> _clearHistory() => _run(() async {
    await drafts.clearHistory();
    await groups.refreshHistory();
    unawaited(notifications.cancel(null));
    for (final timer in _ackTimers.values) {
      timer.cancel();
    }
    _ackTimers.clear();
    _attemptedIds.clear();
    _pausedOutboxes.clear();
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
        unawaited(notifications.cancel(peer));
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
    background.connectionEnded();
    _transportGeneration = null;
    _timeout?.cancel();
    _timeout = null;
    final peer = connectedPeer;
    final pending = _ackTimers.entries.toList();
    _ackTimers.clear();
    _attemptedIds.clear();
    _session = null;
    localVerified = false;
    remoteVerified = false;
    state = started ? 'Available nearby' : 'Offline';
    for (final entry in pending) {
      entry.value.cancel();
      if (peer != null) {
        try {
          await store.changeOutgoingStatus(entry.key, peer, [
            'sending',
          ], 'unconfirmed');
        } catch (_) {
          error =
              'Connection closed. Message status needs recovery; reopen the app before retrying.';
        }
      }
    }
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
    connectionIssue = null;
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    groups.removeListener(_groupChanged);
    groups.dispose();
    _disposed = true;
    drafts.dispose();
    notifications.dispose();
    background.dispose();
    _timeout?.cancel();
    for (final timer in _ackTimers.values) {
      timer.cancel();
    }
    unawaited(_subscription?.cancel());
    unawaited(transport.stop());
    super.dispose();
  }

  void _groupChanged() {
    if (!_disposed) notifyListeners();
  }
}
