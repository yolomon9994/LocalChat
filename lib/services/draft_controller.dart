import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/local_store.dart';

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
  int _nextRevision = 0;
  bool _disposed = false;

  String textFor(String peer) => _text[peer] ?? '';
  bool isLoaded(String peer) => _loaded.contains(peer);
  String? errorFor(String peer) => _errors[peer];
  int revisionFor(String peer) => _revisions[peer] ?? 0;
  Future<void> get settled => _queue;
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
    final epoch = _epoch;
    await _enqueue(() async {
      if (epoch != _epoch) return;
      try {
        final text = await store.draft(peer);
        if (epoch != _epoch) return;
        _text[peer] = text;
        _loaded.add(peer);
        _errors.remove(peer);
      } catch (_) {
        if (epoch == _epoch) {
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
    unawaited(_save(peer, text, _epoch, revisionFor(peer)));
  }

  Future<void> _save(String peer, String text, int epoch, int revision) =>
      _enqueue(() async {
        if (epoch != _epoch || revision != revisionFor(peer)) return;
        try {
          await store.saveDraft(peer, text);
          if (epoch == _epoch && revision == revisionFor(peer)) {
            _errors.remove(peer);
          }
        } catch (_) {
          if (epoch == _epoch) {
            _errors[peer] = 'Draft not saved on this device. Please retry.';
          }
        }
        _notify();
      });

  Future<void> retry(String peer) => isLoaded(peer)
      ? _save(peer, textFor(peer), _epoch, revisionFor(peer))
      : load(peer);

  Future<void> clearAfterSend(String peer, int revision) async {
    if (!isLoaded(peer) || revisionFor(peer) != revision) return;
    setText(peer, '');
    await settled;
  }

  Future<void> clearHistory() => _enqueue(() async {
    await store.clearHistory();
    _epoch++;
    _text.clear();
    _loaded.clear();
    _loading.clear();
    _errors.clear();
    _revisions.clear();
    _notify();
  });

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
