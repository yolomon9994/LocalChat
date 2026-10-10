import 'dart:async';
import 'package:flutter/foundation.dart';

import '../core/models.dart';
import 'chat_controller.dart';

class ChatSearchController extends ChangeNotifier {
  ChatSearchController(
    this.chat, {
    this.debounce = const Duration(milliseconds: 300),
  }) {
    _revision = chat.historyRevision;
    chat.addListener(_historyChanged);
  }
  final ChatController chat;
  final Duration debounce;
  late int _revision;
  int _generation = 0;
  bool _disposed = false;
  Timer? _timer;
  String query = '';
  bool loading = false;
  String? error;
  LocalSearchResults results = const LocalSearchResults();

  void setQuery(String value) {
    final trimmed = value.trim();
    if (trimmed == query) return;
    query = trimmed;
    _schedule();
  }

  void retry() => _schedule(immediate: true);

  void _historyChanged() {
    if (_revision == chat.historyRevision) return;
    _revision = chat.historyRevision;
    _schedule(immediate: true);
  }

  void _schedule({bool immediate = false}) {
    if (_disposed) return;
    _timer?.cancel();
    final generation = ++_generation;
    results = const LocalSearchResults();
    error = null;
    loading = query.isNotEmpty;
    notifyListeners();
    if (!loading) return;
    final needle = query;
    _timer = Timer(
      immediate ? Duration.zero : debounce,
      () => _search(generation, needle),
    );
  }

  Future<void> _search(int generation, String needle) async {
    bool cancelled() => _disposed || generation != _generation;
    try {
      final found = await chat.store.search(needle, isCancelled: cancelled);
      if (cancelled()) return;
      results = found;
    } catch (_) {
      if (cancelled()) return;
      error = 'Could not search saved chats. Please try again.';
    }
    loading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    chat.removeListener(_historyChanged);
    results = const LocalSearchResults();
    super.dispose();
  }
}
