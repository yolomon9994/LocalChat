part of 'chat_controller.dart';

class _ReconnectTarget {
  const _ReconnectTarget(this.device, this.identity);
  final Peer device;
  final String identity;
}

enum _ReconnectPhase { waiting, connecting, verifying }

class _ReconnectRun {
  _ReconnectRun(this.target, this.interaction);
  final _ReconnectTarget target;
  final int interaction;
  int attempts = 0;
  _ReconnectPhase phase = _ReconnectPhase.waiting;
  Duration delay = Duration.zero;
}

extension _AutomaticReconnect on ChatController {
  bool _autoCurrent(_ReconnectRun run) =>
      identical(_autoRun, run) &&
      !_disposed &&
      initialized &&
      reconnectPreferences.enabled &&
      !reconnectPreferences.loading &&
      _appAccessible &&
      _appForeground &&
      started &&
      !groups.running &&
      run.interaction == interactionRevision;

  void _reconnectSettingsChanged() {
    if (!reconnectPreferences.enabled && _autoRun != null) {
      unawaited(cancelAutomaticReconnect());
    }
    if (reconnectPreferences.enabled &&
        !reconnectPreferences.saving &&
        ready &&
        _appAccessible &&
        _appForeground) {
      _rememberReconnectTarget();
    }
    notifyListeners();
  }

  bool _endAutomatic(String? notice) {
    final run = _autoRun;
    final ownsConnection = run != null && run.phase != _ReconnectPhase.waiting;
    _autoTimer?.cancel();
    _autoTimer = null;
    _autoRun = null;
    if (run != null) {
      _rejectAutoConnections = true;
      _autoNoticePeer = run.target.identity;
      _autoNotice = notice;
    }
    _eligibleReconnect = null;
    return ownsConnection;
  }

  Future<void> _cancelAutomatic({String? notice}) {
    final close = _endAutomatic(notice);
    notifyListeners();
    if (!close) return Future.value();
    // Interrupt Android pairing promptly even if a channel callback is pending.
    // Protocol/session cleanup remains serialized with frame processing.
    unawaited(transport.disconnect().catchError((Object _) {}));
    return _run(() async {
      if (_rejectAutoConnections) await _closeAutomaticConnection();
    });
  }

  Future<bool> _closeAutomaticConnection() async {
    try {
      await _disconnect();
      return true;
    } catch (_) {
      _endAutomatic(
        'Automatic reconnection stopped. Restart Nearby before connecting again.',
      );
      started = false;
      scanning = false;
      peers = [];
      state = 'Offline';
      _showConnectionIssue(ConnectionIssue.serviceStopped);
      notifyListeners();
      return false;
    }
  }

  void _manualReconnectIntent() {
    _rejectAutoConnections = false;
    _autoNotice = null;
    _autoNoticePeer = null;
    _outgoingDevice = null;
    _eligibleReconnect = null;
  }

  void _rememberReconnectTarget() {
    final device = _outgoingDevice;
    if (device != null && connectedPeer != null) {
      _eligibleReconnect = _ReconnectTarget(device, connectedPeer!);
    }
    _autoTimer?.cancel();
    _autoTimer = null;
    _autoRun = null;
    _autoNotice = null;
    _autoNoticePeer = null;
  }

  void _recoverAutomatic(_ReconnectTarget? target) {
    final run = _autoRun;
    if (run != null) {
      if (run.phase == _ReconnectPhase.waiting) return;
      if (run.phase == _ReconnectPhase.verifying) {
        _endAutomatic(
          'Connection ended before verification. Connect again from Nearby.',
        );
        return;
      }
      _scheduleAutomatic(run);
    } else if (target != null &&
        reconnectPreferences.enabled &&
        !reconnectPreferences.loading &&
        _appAccessible &&
        _appForeground &&
        started &&
        !groups.running &&
        !_disposed) {
      _scheduleAutomatic(_ReconnectRun(target, interactionRevision));
    }
  }

  void _scheduleAutomatic(_ReconnectRun run) {
    _autoTimer?.cancel();
    _autoRun = run;
    if (!_autoCurrent(run)) {
      _endAutomatic(
        'Automatic reconnection stopped. Connect again from Nearby.',
      );
      return;
    }
    if (run.attempts >= reconnectDelays.length) {
      _endAutomatic(
        'Automatic reconnection finished after 3 attempts. Scan again in Nearby, then connect and compare fresh codes.',
      );
      return;
    }
    run.phase = _ReconnectPhase.waiting;
    run.delay = reconnectDelays[run.attempts];
    _autoTimer = Timer(run.delay, () {
      unawaited(_run(() => _attemptAutomatic(run)));
    });
    notifyListeners();
  }

  Future<void> _attemptAutomatic(_ReconnectRun run) async {
    if (!_autoCurrent(run)) return;
    if (_session != null || state == 'Connecting' || nearbyBusy) {
      _endAutomatic(
        'Automatic reconnection stopped. Use Nearby to connect again.',
      );
      notifyListeners();
      return;
    }
    run.phase = _ReconnectPhase.connecting;
    run.attempts++;
    nearbyBusy = true;
    notifyListeners();
    var checked = false;
    try {
      final status = await nearbyTools.check();
      if (!_autoCurrent(run)) return;
      checked = true;
      nearbyStatus = status;
      if (status.issue case final issue?) {
        _showConnectionIssue(issue);
        _endAutomatic(
          'Automatic reconnection stopped. Resolve Nearby access, then connect again.',
        );
        return;
      }
      final matches = peers.where(
        (p) => p.address == run.target.device.address,
      );
      if (matches.isEmpty) {
        _showConnectionIssue(ConnectionIssue.stalePeer);
        _endAutomatic(
          'This device is no longer listed. Scan again in Nearby and connect manually.',
        );
        return;
      }
      _outgoingDevice = matches.first;
      if (hasConnectionHelp) error = null;
      connectionIssue = null;
      state = 'Connecting';
      _armTimeout();
      await transport.connect(matches.first.address);
      if (!_autoCurrent(run)) await _closeAutomaticConnection();
    } catch (e) {
      if (!identical(_autoRun, run)) return;
      if (!checked) {
        _showConnectionIssue(ConnectionIssue.status);
        _endAutomatic('Could not check Nearby access. Connect again manually.');
        return;
      }
      final issue = ConnectionIssue.fromCode(
        e is PlatformException ? e.code : null,
      );
      if (!await _closeAutomaticConnection()) return;
      if (!_autoCurrent(run)) return;
      _showConnectionIssue(issue);
      if (issue == ConnectionIssue.connection ||
          issue == ConnectionIssue.busy ||
          issue == ConnectionIssue.lost ||
          issue == ConnectionIssue.timeout) {
        _scheduleAutomatic(run);
      } else {
        _endAutomatic(
          'Automatic reconnection stopped. Check Nearby, then connect again.',
        );
      }
    } finally {
      nearbyBusy = false;
      notifyListeners();
    }
  }
}
