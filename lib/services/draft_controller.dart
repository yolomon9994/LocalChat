import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/local_store.dart';
import '../core/chat_backup.dart';
import '../core/models.dart';
import '../core/group_models.dart';

typedef _DraftTarget = (String, bool);

/// Owns draft writes beyond a chat route's lifetime. The separate queue keeps
/// typing off the protocol queue and orders saves, send cleanup and deletion.
class DraftController extends ChangeNotifier {
  DraftController(this.store);
  final LocalStore store;
  final _text = <_DraftTarget, String>{};
  final _loaded = <_DraftTarget>{};
  final _loading = <_DraftTarget>{};
  final _errors = <_DraftTarget, String>{};
  final _revisions = <_DraftTarget, int>{};
  Future<void> _queue = Future<void>.value();
  int _epoch = 0;
  final _targetEpochs = <_DraftTarget, int>{};
  (int, int) _generation(_DraftTarget peer) =>
      (_epoch, _targetEpochs[peer] ?? 0);
  int _nextRevision = 0;
  bool _disposed = false;

  String textFor(String peer, {bool group = false}) =>
      _text[(peer, group)] ?? '';
  bool isLoaded(String peer, {bool group = false}) =>
      _loaded.contains((peer, group));
  String? errorFor(String peer, {bool group = false}) => _errors[(peer, group)];
  int revisionFor(String peer, {bool group = false}) =>
      _revisions[(peer, group)] ?? 0;
  Future<void> get settled => _queue;
  Future<void> _accept(
    _DraftTarget peer,
    Future<void> Function(bool) save, {
    int? draftRevision,
    String? draftText,
    bool Function()? canAccept,
  }) {
    final generation = _generation(peer);
    return _enqueue(() async {
      if (generation != _generation(peer) || canAccept?.call() == false) {
        throw const FormatException('This conversation has been deleted.');
      }
      final clear =
          draftRevision != null &&
          _loaded.contains(peer) &&
          (_revisions[peer] ?? 0) == draftRevision &&
          (_text[peer] ?? '') == draftText;
      await save(clear);
      if (clear &&
          generation == _generation(peer) &&
          (_revisions[peer] ?? 0) == draftRevision) {
        _text[peer] = '';
        _revisions[peer] = ++_nextRevision;
        _errors.remove(peer);
        _notify();
      }
    });
  }

  Future<void> acceptOutgoing(
    ChatMessage message, {
    int? draftRevision,
    String? draftText,
    bool Function()? canAccept,
  }) => _accept(
    (message.peerId, false),
    (clear) => store.saveOutgoingMessage(message, clearDraft: clear),
    draftRevision: draftRevision,
    draftText: draftText,
    canAccept: canAccept,
  );

  Future<void> acceptGroupOutgoing(
    GroupHistory history, {
    int? draftRevision,
    String? draftText,
    bool Function()? canAccept,
  }) => _accept(
    (history.id, true),
    (clear) => store.saveOutgoingGroupHistory(history, clearDraft: clear),
    draftRevision: draftRevision,
    draftText: draftText,
    canAccept: canAccept,
  );

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
      final revisions = Map<_DraftTarget, int>.from(_revisions);
      result = await store.importBackup(data, moveIdentity: moveIdentity);
      void restore(Map<String, Object?> draft, bool group) {
        final peer = (draft[group ? 'group' : 'peer'] as String, group);
        // Preserve edits made while storage work was in flight.
        if (_loaded.contains(peer) &&
            (_text[peer] ?? '').isEmpty &&
            (_revisions[peer] ?? 0) == (revisions[peer] ?? 0)) {
          _text[peer] = draft['text'] as String;
          _revisions[peer] = ++_nextRevision;
        }
      }

      for (final draft in result.data.drafts) {
        restore(draft, false);
      }
      for (final draft in result.data.groupDrafts) {
        restore(draft, true);
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

  Future<void> load(String id, {bool group = false}) async {
    final peer = (id, group);
    if (_loaded.contains(peer) || !_loading.add(peer)) return;
    final generation = _generation(peer);
    await _enqueue(() async {
      try {
        if (generation != _generation(peer)) return;
        final text = group ? await store.groupDraft(id) : await store.draft(id);
        if (generation != _generation(peer)) return;
        _text[peer] = text;
        _loaded.add(peer);
        _errors.remove(peer);
      } catch (_) {
        if (generation == _generation(peer)) {
          _errors[peer] = 'Could not load this draft. Please retry.';
        }
      } finally {
        if (generation == _generation(peer)) _loading.remove(peer);
        _notify();
      }
    });
  }

  void setText(String id, String text, {bool group = false}) {
    final peer = (id, group);
    if (!_loaded.contains(peer) || text == (_text[peer] ?? '')) return;
    _text[peer] = text;
    _revisions[peer] = ++_nextRevision;
    _notify();
    unawaited(_save(peer, text, _generation(peer), _revisions[peer]!));
  }

  Future<void> _save(
    _DraftTarget peer,
    String text,
    (int, int) generation,
    int revision,
  ) => _enqueue(() async {
    if (generation != _generation(peer) || revision != _revisions[peer]) return;
    try {
      if (peer.$2) {
        await store.saveGroupDraft(peer.$1, text);
      } else {
        await store.saveDraft(peer.$1, text);
      }
      if (generation == _generation(peer) && revision == _revisions[peer]) {
        _errors.remove(peer);
      }
    } catch (_) {
      if (generation == _generation(peer) && revision == _revisions[peer]) {
        _errors[peer] = 'Draft not saved on this device. Please retry.';
      }
    }
    _notify();
  });

  Future<void> retry(String id, {bool group = false}) =>
      isLoaded(id, group: group)
      ? _save(
          (id, group),
          textFor(id, group: group),
          _generation((id, group)),
          revisionFor(id, group: group),
        )
      : load(id, group: group);

  Future<void> clearAfterSend(String peer, int revision) async {
    if (!isLoaded(peer) || revisionFor(peer) != revision) return;
    setText(peer, '');
    await settled;
  }

  Future<void> clearHistory() => _enqueue(() async {
    await store.clearHistory();
    _epoch++;
    _targetEpochs.clear();
    _text.clear();
    _loaded.clear();
    _loading.clear();
    _errors.clear();
    _revisions.clear();
    _notify();
  });

  Future<void> _delete(String id, bool group) => _enqueue(() async {
    if (group) {
      await store.deleteGroupHistory(id);
    } else {
      await store.deleteConversation(id);
    }
    final peer = (id, group);
    _targetEpochs[peer] = (_targetEpochs[peer] ?? 0) + 1;
    _text.remove(peer);
    _loaded.remove(peer);
    _loading.remove(peer);
    _errors.remove(peer);
    _revisions.remove(peer);
    _notify();
  });
  Future<void> deleteConversation(String peer) => _delete(peer, false);
  Future<void> deleteGroupHistory(String id) => _delete(id, true);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
