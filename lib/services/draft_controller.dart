import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/local_store.dart';
import '../core/chat_backup.dart';
import '../core/models.dart';

/// Owns draft writes beyond a chat route's lifetime. The separate queue keeps
/// typing off the protocol queue and orders saves, send cleanup and deletion.
class DraftController extends ChangeNotifier {
  DraftController(this.store);
  final LocalStore store;
  final _text = <String, String>{};
  final _loaded = <String>{};
  final _loading = <String>{};
  final _errors = <String, String>{};
  final _revisions = <String, int>{};
  Future<void> _queue = Future<void>.value();
  int _epoch = 0;
  final _peerEpochs = <String, int>{};
  (int, int) _generation(String peer) => (_epoch, _peerEpochs[peer] ?? 0);
  int _nextRevision = 0;
  bool _disposed = false;

  String textFor(String peer) => _text[peer] ?? '';
  bool isLoaded(String peer) => _loaded.contains(peer);
  String? errorFor(String peer) => _errors[peer];
  int revisionFor(String peer) => _revisions[peer] ?? 0;
  Future<void> get settled => _queue;
  Future<void> acceptOutgoing(
    ChatMessage message, {
    int? draftRevision,
    String? draftText,
    bool Function()? canAccept,
  }) {
    final peer = message.peerId, generation = _generation(message.peerId);
    return _enqueue(() async {
      if (generation != _generation(peer) || canAccept?.call() == false) {
        throw const FormatException('This conversation has been deleted.');
      }
      final clear =
          draftRevision != null &&
          isLoaded(peer) &&
          revisionFor(peer) == draftRevision &&
          textFor(peer) == draftText;
      await store.saveOutgoingMessage(message, clearDraft: clear);
      if (clear &&
          generation == _generation(peer) &&
          revisionFor(peer) == draftRevision) {
        _text[peer] = '';
        _revisions[peer] = ++_nextRevision;
        _errors.remove(peer);
        _notify();
      }
    });
  }

  Future<BackupData> exportBackup() async {
    late BackupData data;
    await _enqueue(() async {
      if (_errors.isNotEmpty) {
        throw const FormatException(
          'Resolve draft save/load errors before exporting.',
        );
      }
      data = await store.exportBackup();
    });
    return data;
  }

  Future<BackupMerge> importBackup(
    BackupData data, {
    bool moveIdentity = false,
  }) async {
    late BackupMerge result;
    await _enqueue(() async {
      if (_errors.isNotEmpty) {
        throw const FormatException(
          'Resolve draft save/load errors before importing.',
        );
      }
      final revisions = Map<String, int>.from(_revisions);
      result = await store.importBackup(data, moveIdentity: moveIdentity);
      for (final draft in result.data.drafts) {
        final peer = draft['peer'] as String;
        // Preserve edits made while storage work was in flight.
        if (_loaded.contains(peer) &&
            textFor(peer).isEmpty &&
            revisionFor(peer) == (revisions[peer] ?? 0)) {
          _text[peer] = draft['text'] as String;
          _revisions[peer] = ++_nextRevision;
        }
      }
      _notify();
    });
    return result;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final result = _queue.then((_) => action());
    // Failures are handled at their source; keep later work usable regardless.
    _queue = result.catchError((Object _) {});
    return result;
  }

  Future<void> load(String peer) async {
    if (_loaded.contains(peer) || !_loading.add(peer)) return;
    final generation = _generation(peer);
    await _enqueue(() async {
      if (generation != _generation(peer)) return;
      try {
        final text = await store.draft(peer);
        if (generation != _generation(peer)) return;
        _text[peer] = text;
        _loaded.add(peer);
        _errors.remove(peer);
      } catch (_) {
        if (generation == _generation(peer)) {
          _errors[peer] = 'Could not load this draft. Please retry.';
        }
      } finally {
        _loading.remove(peer);
        _notify();
      }
    });
  }

  void setText(String peer, String text) {
    if (!_loaded.contains(peer) || text == textFor(peer)) return;
    _text[peer] = text;
    _revisions[peer] = ++_nextRevision;
    _notify();
    unawaited(_save(peer, text, _generation(peer), revisionFor(peer)));
  }

  Future<void> _save(
    String peer,
    String text,
    (int, int) generation,
    int revision,
  ) => _enqueue(() async {
    if (generation != _generation(peer) || revision != revisionFor(peer)) {
      return;
    }
    try {
      await store.saveDraft(peer, text);
      if (generation == _generation(peer) && revision == revisionFor(peer)) {
        _errors.remove(peer);
      }
    } catch (_) {
      if (generation == _generation(peer)) {
        _errors[peer] = 'Draft not saved on this device. Please retry.';
      }
    }
    _notify();
  });

  Future<void> retry(String peer) => isLoaded(peer)
      ? _save(peer, textFor(peer), _generation(peer), revisionFor(peer))
      : load(peer);

  Future<void> clearAfterSend(String peer, int revision) async {
    if (!isLoaded(peer) || revisionFor(peer) != revision) return;
    setText(peer, '');
    await settled;
  }

  Future<void> clearHistory() => _enqueue(() async {
    await store.clearHistory();
    _epoch++;
    _peerEpochs.clear();
    _text.clear();
    _loaded.clear();
    _loading.clear();
    _errors.clear();
    _revisions.clear();
    _notify();
  });

  Future<void> deleteConversation(String peer) => _enqueue(() async {
    await store.deleteConversation(peer);
    _peerEpochs[peer] = (_peerEpochs[peer] ?? 0) + 1;
    _text.remove(peer);
    _loaded.remove(peer);
    _loading.remove(peer);
    _errors.remove(peer);
    _revisions.remove(peer);
    _notify();
  });

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
