import 'dart:async';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import '../core/local_store.dart';
import '../demo/demo_group_transport.dart';
import '../core/models.dart';
import '../core/message_reply.dart';
import '../core/starred_message.dart';
import '../core/chat_backup.dart';
import 'backup_files.dart';
import '../core/secure_session.dart';
import '../core/session_verification.dart';
import 'transport.dart';
import 'draft_controller.dart';
import 'nearby_support.dart';
import 'chat_notifications.dart';
import 'background_connection.dart';
import 'group_controller.dart';
import 'group_transport.dart';
import 'image_files.dart';
import 'chat_files.dart';
import '../core/chat_file.dart';
import 'file_transfers.dart';
import 'image_content.dart';
import 'image_transfers.dart';
import 'action_feedback.dart';
import 'preview_privacy.dart';

class ChatController extends ChangeNotifier {
  ChatController(
    this.transport,
    this.store, {
    this.isDemo = false,
    this.supportsReplies = true,
    this.ackTimeout = const Duration(seconds: 30),
    this.connectionTimeout = const Duration(seconds: 90),
    NearbyTools? nearbyTools,
    ChatNotifications? notifications,
    BackgroundConnection? background,
    ActionFeedback? feedback,
    PreviewPrivacy? previewPrivacy,
    GroupTransport? groupTransport,
    ImageFiles? imageFiles,
    ChatFiles? chatFiles,
    this.fileTimeout = const Duration(seconds: 30),
    this.imageTimeout = const Duration(seconds: 30),
  }) : previewPrivacy =
           previewPrivacy ??
           PreviewPrivacy(
             transport is WifiDirectTransport
                 ? SecurePreviewPrivacyStorage()
                 : MemoryPreviewPrivacyStorage(),
           ),
       feedback =
           feedback ??
           ActionFeedback(
             transport is WifiDirectTransport
                 ? SecureFeedbackStorage()
                 : MemoryFeedbackStorage(),
             isDemo: isDemo,
           ),
       nearbyTools =
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
       imageFiles = imageFiles ?? createImageFiles(),
       chatFiles = chatFiles ?? createChatFiles(),
       _groupTransport =
           groupTransport ??
           (transport is WifiDirectTransport
               ? WifiGroupTransport()
               : UnavailableGroupTransport());
  final GroupTransport _groupTransport;
  final ActionFeedback feedback;
  final PreviewPrivacy previewPrivacy;
  void _previewChanged() {
    if (!_disposed) notifyListeners();
  }

  final bool supportsReplies;
  bool get simulatedGroups => isDemo && _groupTransport is DemoGroupTransport;
  bool get canUseGroups => !isDemo || simulatedGroups;
  final ImageFiles imageFiles;
  final Duration imageTimeout;
  bool remoteSupportsReplies = false;
  bool remoteSupportsImages = false;
  bool pickingImage = false;
  SecretBox? _pendingImage;
  SecretKey? _pendingImageKey;
  String? pendingImagePeer;
  int _imageSelectionRevision = 0;
  bool get canSendImage =>
      canSend &&
      remoteSupportsImages &&
      _appAccessible &&
      _appForeground &&
      !images.sending &&
      !files.sending &&
      !pickingImage &&
      !pickingFile;
  late final images = ImageTransfers(
    store: store,
    peer: () => connectedPeer,
    canAct: () =>
        !_disposed && initialized && ready && _appAccessible && _appForeground,
    send: _sendImagePayload,
    enqueue: _run,
    changed: notifyListeners,
    persisted: _imagePersisted,
    timeout: imageTimeout,
  );

  Future<void> _sendImagePayload(
    Map<String, dynamic> payload,
    bool origin,
  ) async {
    final session = _session;
    if (session == null || !ready) {
      throw const FormatException('Verify both phones first.');
    }
    final access = accessRevision;
    if (origin && (!_appAccessible || !_appForeground)) return;
    try {
      final frame = await session.encrypt(payload);
      if (!identical(session, _session) ||
          (origin &&
              (!_appAccessible ||
                  !_appForeground ||
                  access != accessRevision))) {
        await _disconnect();
        throw const FormatException(
          'Attachment transfer interrupted by app locking.',
        );
      }
      await transport.send(jsonEncode(frame));
    } catch (_) {
      if (identical(session, _session)) await _disconnect();
      rethrow;
    }
  }

  Future<void> _imagePersisted(ChatMessage message, bool inserted) async {
    historyRevision++;
    if (inserted && !message.outgoing) {
      final target = message.peerId;
      unawaited(
        notifications.incoming(
          target,
          _session?.peerName ?? 'Nearby phone',
          message.file != null ? 'File' : 'Image',
          isReading: () => selectedPeer == target && _canReadSelected,
        ),
      );
    }
    try {
      await _refresh();
    } catch (_) {
      error = 'Attachment saved. Reopen this chat to refresh history.';
    }
    notifyListeners();
  }

  void discardPendingImage() {
    _imageSelectionRevision++;
    _pendingImage = null;
    _pendingImageKey = null;
    pendingImagePeer = null;
    notifyListeners();
  }

  Future<void> pickImage() async {
    if (!canSendImage || selectedPeer == null) return;
    final target = selectedPeer!;
    final selection = _imageSelectionRevision;
    pickingImage = true;
    error = null;
    notifyListeners();
    try {
      final source = await imageFiles.pick();
      if (source == null || _disposed) return;
      final bytes = await normalizeImage(source);
      final cipher = Xchacha20.poly1305Aead();
      final key = await cipher.newSecretKey();
      final box = await cipher.encrypt(bytes, secretKey: key);
      if (_disposed ||
          selection != _imageSelectionRevision ||
          !(await store.conversations()).any((p) => p.id == target)) {
        return;
      }
      _pendingImageKey = key;
      _pendingImage = box;
      pendingImagePeer = target;
    } catch (_) {
      error =
          'Could not prepare this image. Choose an image under 8 MiB; prepared images must be under 2 MiB.';
    } finally {
      pickingImage = false;
      notifyListeners();
    }
  }

  Future<Uint8List?> reviewPendingImage() async {
    if (!_appAccessible ||
        !_appForeground ||
        selectedPeer != pendingImagePeer ||
        _pendingImage == null ||
        _pendingImageKey == null) {
      return null;
    }
    final access = accessRevision;
    final selection = _imageSelectionRevision;
    final bytes = Uint8List.fromList(
      await Xchacha20.poly1305Aead().decrypt(
        _pendingImage!,
        secretKey: _pendingImageKey!,
      ),
    );
    if (_disposed ||
        selection != _imageSelectionRevision ||
        selectedPeer != pendingImagePeer ||
        !_appAccessible ||
        !_appForeground ||
        access != accessRevision) {
      return null;
    }
    return bytes;
  }

  Future<bool> sendImage(Uint8List bytes, {ChatMessage? retry}) async {
    final target = selectedPeer, access = accessRevision;
    var accepted = false;
    await _run(() async {
      if (!canSendImage ||
          selectedPeer != target ||
          access != accessRevision ||
          (retry != null && retry.peerId != target)) {
        return;
      }
      error = null;
      accepted = await images.start(bytes, retry: retry);
      if (accepted && pendingImagePeer == target) discardPendingImage();
    });
    return accepted;
  }

  Future<void> cancelImageTransfers() {
    images.requestCancel();
    return _run(images.cancel);
  }

  void _pauseImages() {
    images.requestCancel();
    if (images.progress.isNotEmpty) unawaited(_run(images.cancel));
  }

  final ChatFiles chatFiles;
  final Duration fileTimeout;
  bool remoteSupportsFiles = false;
  bool pickingFile = false;
  SecretBox? _pendingFile;
  SecretKey? _pendingFileKey;
  String? pendingFilePeer;
  int _fileSelectionRevision = 0;
  bool get canSendFile =>
      canSend &&
      remoteSupportsFiles &&
      _appAccessible &&
      _appForeground &&
      !files.sending &&
      !images.sending &&
      !pickingFile &&
      !pickingImage;
  late final files = FileTransfers(
    store: store,
    peer: () => connectedPeer,
    canAct: () =>
        !_disposed && initialized && ready && _appAccessible && _appForeground,
    send: _sendImagePayload,
    enqueue: _run,
    changed: notifyListeners,
    persisted: _imagePersisted,
    timeout: fileTimeout,
  );

  void discardPendingFile() {
    _fileSelectionRevision++;
    _pendingFile = null;
    _pendingFileKey = null;
    pendingFilePeer = null;
    notifyListeners();
  }

  Future<void> pickFile() async {
    if (!canSendFile || selectedPeer == null) return;
    final target = selectedPeer!;
    final selection = _fileSelectionRevision;
    pickingFile = true;
    error = null;
    notifyListeners();
    try {
      final source = await chatFiles.pick();
      if (source == null || _disposed) return;
      final meta = await ChatFile.fromBytes(source.name, source.bytes);
      final bytes = utf8.encode(
        jsonEncode({'name': meta.name, 'data': base64Encode(source.bytes)}),
      );
      final cipher = Xchacha20.poly1305Aead();
      final key = await cipher.newSecretKey();
      final box = await cipher.encrypt(bytes, secretKey: key);
      if (_disposed ||
          selection != _fileSelectionRevision ||
          !(await store.conversations()).any((p) => p.id == target)) {
        return;
      }
      _pendingFileKey = key;
      _pendingFile = box;
      pendingFilePeer = target;
    } catch (_) {
      error =
          'Could not prepare this file. Choose a nonempty file up to 8 MiB.';
    } finally {
      pickingFile = false;
      notifyListeners();
    }
  }

  Future<SelectedFile?> reviewPendingFile() async {
    if (!_appAccessible ||
        !_appForeground ||
        selectedPeer != pendingFilePeer ||
        _pendingFile == null ||
        _pendingFileKey == null) {
      return null;
    }
    final access = accessRevision;
    final selection = _fileSelectionRevision;
    final bytes = Uint8List.fromList(
      await Xchacha20.poly1305Aead().decrypt(
        _pendingFile!,
        secretKey: _pendingFileKey!,
      ),
    );
    if (_disposed ||
        selection != _fileSelectionRevision ||
        selectedPeer != pendingFilePeer ||
        !_appAccessible ||
        !_appForeground ||
        access != accessRevision) {
      return null;
    }
    final raw = jsonDecode(utf8.decode(bytes)) as Map;
    return SelectedFile(
      raw['name'] as String,
      base64Decode(raw['data'] as String),
    );
  }

  Future<bool> sendFile(SelectedFile selection, {ChatMessage? retry}) async {
    final target = selectedPeer, access = accessRevision;
    var accepted = false;
    await _run(() async {
      if (!canSendFile ||
          selectedPeer != target ||
          access != accessRevision ||
          (retry != null && retry.peerId != target)) {
        return;
      }
      error = null;
      accepted = await files.start(
        selection.bytes,
        name: selection.name,
        retry: retry,
      );
      if (accepted && pendingFilePeer == target) discardPendingFile();
    });
    return accepted;
  }

  Future<void> cancelFileTransfers() {
    files.requestCancel();
    return _run(files.cancel);
  }

  void _pauseFiles() {
    files.requestCancel();
    if (files.progress.isNotEmpty) unawaited(_run(files.cancel));
  }

  Future<bool> saveFileToPhone(ChatMessage message) async {
    if (_disposed || !appAccessible || !appForeground) return false;
    final access = accessRevision;
    try {
      final bytes = await store.fileBytes(message);
      if (_disposed ||
          !appAccessible ||
          !appForeground ||
          access != accessRevision) {
        return false;
      }
      // Explicitly authorized export may finish while the system picker is open.
      return await chatFiles.save(bytes, message.file!.name);
    } catch (_) {
      error =
          'Could not save this file. Try again and choose a writable folder.';
      notifyListeners();
      return false;
    }
  }

  late final groups = GroupController(
    _groupTransport,
    store,
    drafts: drafts,
    accessRevision: () => accessRevision,
    replyAccessRevision: () => interactionRevision,
    imageFiles: imageFiles,
    chatFiles: chatFiles,
    prepare: _prepareGroup,
    notifications: notifications,
    background: background,
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
      : ready &&
            !remoteSupportsReplies &&
            messages.any((m) => m.status == 'queued' && m.reply != null)
      ? 'A queued reply needs the updated app on both phones. Update the other phone, or cancel that queued reply to send later messages.'
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
  int interactionRevision = 0;
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
  String get selectedDisplayName {
    for (final p in conversations) {
      if (p.id == selectedPeer) return p.name;
    }
    return selectedName;
  }

  String selectedName = '';
  int historyRevision = 0;
  List<StarredMessage> starred = const [];
  final _starredKeys = <StarredMessage>{};
  int starsRevision = 0;
  String? starsError;
  bool _starsLoading = false;
  Future<void>? _starsLoad;
  int _starsGeneration = 0;
  (int, int)? _starsStamp;
  bool isStarred(StarredMessage s) => _starredKeys.contains(s);
  void _replaceStars(List<StarredMessage> result) {
    final keys = result.toSet();
    if (setEquals(_starredKeys, keys)) return;
    starred = List.unmodifiable(result);
    _starredKeys
      ..clear()
      ..addAll(keys);
    starsRevision++;
  }

  Future<void> refreshStars() {
    if (_starsLoad != null) return _starsLoad!;
    if (_disposed || !initialized) return Future.value();
    return _starsLoad = _readStarredMessages();
  }

  Future<void> _readStarredMessages() async {
    if (_disposed || !initialized || _starsLoading) return;
    _starsLoading = true;
    final generation = ++_starsGeneration;
    _starsStamp = (historyRevision, groups.historyRevision);
    try {
      final result = await store.starredMessages();
      if (!_disposed &&
          generation == _starsGeneration &&
          _starsStamp == (historyRevision, groups.historyRevision)) {
        _replaceStars(result);
        starsError = null;
      }
    } catch (_) {
      if (!_disposed) {
        starsError = 'Could not load starred messages. Try again.';
      }
    } finally {
      _starsLoading = false;
      _starsLoad = null;
      if (!_disposed) notifyListeners();
    }
  }

  Future<bool> setStarred(StarredMessage s, bool value) async {
    final interaction = interactionRevision;
    var success = false;
    await _run(() async {
      if (_disposed ||
          !initialized ||
          !appAccessible ||
          !appForeground ||
          interaction != interactionRevision) {
        return;
      }
      try {
        _starsGeneration++;
        success = await store.setMessageStarred(s, value);
        if (!success) throw const FormatException('Message no longer saved.');
        _replaceStars(await store.starredMessages());
        starsError = null;
      } catch (_) {
        success = false;
        starsError = 'Could not update this starred message. Try again.';
      }
      notifyListeners();
    });
    return success;
  }

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
  bool get canSubmitText =>
      canSubmit &&
      (selectedPeer == null ||
          drafts.replyFor(selectedPeer!) == null ||
          !canSend ||
          remoteSupportsReplies);
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
    if (!accessible) {
      _pauseImages();
      _pauseFiles();
    }
    notifications.setAccessible(_appAccessible && _appForeground);
    accessRevision++;
    interactionRevision++;
    unawaited(groups.accessChanged());
    _readVisible();
    notifyListeners();
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
    interactionRevision++;
    if (!foreground) {
      _pauseImages();
      _pauseFiles();
    }
    unawaited(groups.accessChanged());
    notifications.setAccessible(_appAccessible && _appForeground);
    _readVisible();
    // Cancel search immediately on background; refresh activity on return.
    notifyListeners();
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
      await feedback.initialize();
      await previewPrivacy.initialize();
      previewPrivacy.addListener(_previewChanged);
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
        final token = event['generation'] as int?;
        if (token != null && token < 0) {
          if (groups.transportGeneration == token) await groups.stop();
          break;
        }
        if (token != null && token != _transportGeneration) break;
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
        remoteSupportsReplies =
            payload['features'] is List &&
            (payload['features'] as List).contains('reply-v1');
        remoteSupportsImages =
            payload['features'] is List &&
            (payload['features'] as List).contains('image-v1');
        remoteSupportsFiles =
            payload['features'] is List &&
            (payload['features'] as List).contains('file-v1');
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
        final reply = payload.containsKey('reply')
            ? MessageReply.parse(payload['reply'], group: false).reversed()
            : null;
        if (reply != null && (!supportsReplies || !remoteSupportsReplies)) {
          throw const FormatException('Unsupported message reply');
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
            reply: reply,
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
      case 'fileOffer':
      case 'fileReady':
      case 'fileChunk':
      case 'fileChunkAck':
      case 'fileComplete':
      case 'fileResult':
      case 'fileCancel':
        if (!ready || !remoteSupportsFiles) {
          throw const FormatException('Unsupported file transfer.');
        }
        await files.handle(payload);
      case 'imageOffer':
      case 'imageReady':
      case 'imageChunk':
      case 'imageChunkAck':
      case 'imageComplete':
      case 'imageResult':
      case 'imageCancel':
        if (!ready || !remoteSupportsImages) {
          throw const FormatException('Unsupported image transfer.');
        }
        await images.handle(payload);
      default:
        throw const FormatException('Unsupported payload type');
    }
  }

  VerificationRequest? get directVerification {
    final session = _session;
    final qr = session?.verificationQr(VerificationScope.direct);
    if (_disposed ||
        !initialized ||
        !_appAccessible ||
        !_appForeground ||
        session == null ||
        qr == null ||
        ready ||
        selectedPeer != session.peerId) {
      return null;
    }
    return VerificationRequest(
      owner: this,
      sessionToken: session,
      interactionRevision: interactionRevision,
      qr: qr,
      peerName: session.peerName ?? 'Nearby phone',
    );
  }

  bool verificationCurrent(VerificationRequest request) {
    if (request.qr.scope == VerificationScope.group) {
      return groups.verificationCurrent(request);
    }
    final current = directVerification;
    return current != null &&
        request.linkId == null &&
        identical(request.owner, this) &&
        identical(request.sessionToken, current.sessionToken) &&
        request.interactionRevision == interactionRevision &&
        request.qr == current.qr;
  }

  bool canConfirmVerification(VerificationRequest request) =>
      verificationCurrent(request) &&
      (request.qr.scope == VerificationScope.group
          ? groups.canConfirmVerification(request)
          : !localVerified);
  Future<bool> confirmVerification(
    VerificationRequest request,
    String scanned,
  ) => request.qr.scope == VerificationScope.group
      ? groups.confirm(request.linkId ?? '', request: request, scanned: scanned)
      : confirmCode(request: request, scanned: scanned);

  Future<bool> confirmCode({
    VerificationRequest? request,
    String? scanned,
  }) async {
    final captured = request ?? directVerification;
    if (captured == null || captured.qr.scope != VerificationScope.direct) {
      return false;
    }
    var success = false;
    await _run(() async {
      if (!canConfirmVerification(captured) ||
          (scanned != null && !captured.qr.matchesRemote(scanned))) {
        return;
      }
      error = null;
      final session = _session!;
      try {
        final frame = await session.encrypt({
          'type': 'verified',
          'features': ['image-v1', 'file-v1', if (supportsReplies) 'reply-v1'],
        });
        if (!canConfirmVerification(captured)) {
          if (identical(session, _session)) await _disconnect();
          return;
        }
        await transport.send(jsonEncode(frame));
        if (!canConfirmVerification(captured)) {
          if (identical(session, _session)) await _disconnect();
          return;
        }
        localVerified = true;
        await _updateReady();
        success = true;
      } catch (_) {
        if (identical(session, _session)) await _disconnect();
        rethrow;
      }
      notifyListeners();
    });
    return success;
  }

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
    if (groups.backgroundReady) {
      final epoch = groups.epoch;
      final token = groups.transportGeneration;
      bool same() =>
          !_disposed &&
          groups.backgroundReady &&
          groups.epoch == epoch &&
          groups.transportGeneration == token;
      return background.protect(
        token,
        groupLinks: groups.links.values
            .where((l) => l.admitted)
            .map((l) => l.id)
            .toList(),
        canStart: () => same() && _appAccessible && _appForeground,
        sameConnection: same,
      );
    }
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

  Future<bool> replyTo(ChatMessage message) async {
    final peer = selectedPeer, access = interactionRevision;
    bool allowed() =>
        !_disposed &&
        initialized &&
        appAccessible &&
        appForeground &&
        selectedPeer == peer &&
        peer == message.peerId &&
        access == interactionRevision &&
        supportsReplies &&
        message.text.trim().isNotEmpty &&
        messages.any(
          (m) =>
              m.id == message.id &&
              m.outgoing == message.outgoing &&
              m.peerId == peer &&
              m.text == message.text &&
              m.image == null &&
              m.file == null,
        );
    if (!allowed()) return false;
    await drafts.load(peer!);
    if (!allowed() || !drafts.isLoaded(peer)) return false;
    final name = (message.outgoing ? profileName : selectedName).trim();
    try {
      drafts.setReply(
        peer,
        MessageReply(
          id: message.id,
          outgoing: message.outgoing,
          name: name.isEmpty ? (message.outgoing ? 'You' : 'Peer') : name,
          text: MessageReply.preview(message.text),
        ),
      );
    } on FormatException {
      error = 'Could not select this message for a reply.';
      notifyListeners();
      return false;
    }
    return true;
  }

  /// True means accepted into local encrypted history, not delivered. The draft
  /// is removed atomically with acceptance, so a failed write is retried by ID.
  Future<bool> sendText(String text, {bool queueIfOffline = false}) async {
    final intendedPeer = selectedPeer;
    final access = accessRevision;
    final interaction = interactionRevision;
    final reply = intendedPeer == null ? null : drafts.replyFor(intendedPeer);
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
          (reply != null && interaction != interactionRevision) ||
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
      if (reply != null) {
        MessageReply.parse(reply.toJson(), group: false);
        if (!supportsReplies || (canSend && !remoteSupportsReplies)) {
          throw const FormatException(
            'Replies require the updated app on both phones.',
          );
        }
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
            reply: reply,
          ),
          draftRevision: draftRevision,
          draftText: rawText,
          canAccept: () =>
              initialized &&
              _appAccessible &&
              _appForeground &&
              access == accessRevision &&
              (reply == null || interaction == interactionRevision),
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
      m.image == null &&
      m.file == null &&
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
      if (message.reply != null && !remoteSupportsReplies) {
        error =
            'Queued reply needs the updated app on both phones. Update the peer or cancel this reply.';
        notifyListeners();
        return;
      }
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
        if (outgoing.reply != null) 'reply': outgoing.reply!.toJson(),
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
      selectedName = peer.originalName;
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
    if (images.progress.isNotEmpty) await images.cancel();
    if (files.progress.isNotEmpty) await files.cancel();
    discardPendingFile();
    discardPendingImage();
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

  Future<bool> setNickname(
    String peer,
    String? nickname, {
    bool Function()? isCurrent,
  }) async {
    final revision = interactionRevision;
    var success = false;
    await _run(() async {
      if (_disposed ||
          !initialized ||
          !appAccessible ||
          !appForeground ||
          revision != interactionRevision ||
          isCurrent?.call() == false) {
        return;
      }
      error = null;
      try {
        success = await store.setNickname(
          peer,
          nickname,
          isCurrent: () =>
              !_disposed &&
              appAccessible &&
              appForeground &&
              revision == interactionRevision &&
              isCurrent?.call() != false,
        );
        if (_disposed) return;
        if (!success &&
            (revision != interactionRevision || isCurrent?.call() == false)) {
          return;
        }
        if (!success) throw StateError('Missing contact');
        conversations = await store.conversations();
        historyRevision++;
      } catch (_) {
        success = false;
        error = 'Could not save the nickname. Please try again.';
      }
      if (!_disposed) notifyListeners();
    });
    return success;
  }

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
        if (pendingImagePeer == peer || pickingImage) discardPendingImage();
        if (pendingFilePeer == peer || pickingFile) discardPendingFile();
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
    remoteSupportsReplies = false;
    remoteSupportsImages = false;
    remoteSupportsFiles = false;
    try {
      try {
        await files.stop();
      } finally {
        await images.stop();
      }
    } catch (_) {
      error =
          'Could not save interrupted attachment status. Reopen the app before retrying.';
    }
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
    if (!_disposed) {
      if (initialized &&
          !_starsLoading &&
          _starsStamp != (historyRevision, groups.historyRevision)) {
        unawaited(refreshStars());
      }
      super.notifyListeners();
    }
  }

  @override
  void dispose() {
    files.dispose();
    _pendingFile = null;
    _pendingFileKey = null;
    pendingFilePeer = null;
    images.dispose();
    _pendingImage = null;
    _pendingImageKey = null;
    pendingImagePeer = null;
    groups.removeListener(_groupChanged);
    groups.dispose();
    if (_groupTransport is DemoGroupTransport) {
      unawaited(_groupTransport.dispose());
    }
    _disposed = true;
    drafts.dispose();
    notifications.dispose();
    feedback.dispose();
    previewPrivacy.removeListener(_previewChanged);
    previewPrivacy.dispose();
    background.dispose();
    _timeout?.cancel();
    for (final timer in _ackTimers.values) {
      timer.cancel();
    }
    unawaited(_subscription?.cancel());
    unawaited(transport.stop());
    super.dispose();
  }

  String? _groupProtectionKey;
  void _groupChanged() {
    if (_disposed) return;
    final admitted =
        groups.links.values.where((l) => l.admitted).map((l) => l.id).toList()
          ..sort();
    final key = groups.backgroundReady
        ? '${groups.epoch}/${groups.transportGeneration}/${admitted.join(',')}'
        : null;
    if (key != _groupProtectionKey) {
      _groupProtectionKey = key;
      if (!groups.backgroundReady && background.protectsGroup) {
        background.connectionEnded(group: true, unexpected: groups.running);
      }
      _requestBackground();
    }
    notifyListeners();
  }
}
