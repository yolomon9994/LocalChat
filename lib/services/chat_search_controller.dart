import 'dart:async';
import 'package:flutter/foundation.dart';

import '../core/models.dart';
import '../core/group_search.dart';
import 'chat_controller.dart';

class ChatSearchController extends ChangeNotifier {
  ChatSearchController(
    this.chat, {
    this.groupId,
    this.debounce = const Duration(milliseconds: 300),
  }) {
    _revision = chat.historyRevision;
    _groupRevision = chat.groups.historyRevision;
    _access = chat.accessRevision;
    _available = chat.appAccessible && chat.appForeground;
    chat.addListener(_historyChanged);
    chat.groups.addListener(_historyChanged);
  }
  final ChatController chat;
  final String? groupId;
  final Duration debounce;
  late int _revision;
  late int _groupRevision, _access;
  late bool _available;
  int _generation = 0;
  bool _disposed = false;
  Timer? _timer;
  String query = '';
  bool loading = false;
  String? error;
  LocalSearchResults results = const LocalSearchResults();
  GroupSearchResults groupResults = const GroupSearchResults();

  void setQuery(String value) {
    final trimmed = value.trim();
    if (trimmed == query) return;
    query = trimmed;
    _schedule();
  }

  void retry() => _schedule(immediate: true);

  void _historyChanged() {
    final available = chat.appAccessible && chat.appForeground;
    if (_revision == chat.historyRevision &&
        _groupRevision == chat.groups.historyRevision &&
        _access == chat.accessRevision &&
        _available == available) {
      return;
    }
    _revision = chat.historyRevision;
    _groupRevision = chat.groups.historyRevision;
    _access = chat.accessRevision;
    _available = available;
    if (!chat.appAccessible) query = '';
    _schedule(immediate: true);
  }

  void _schedule({bool immediate = false}) {
    if (_disposed) return;
    _timer?.cancel();
    final generation = ++_generation;
    results = const LocalSearchResults();
    groupResults = const GroupSearchResults();
    error = null;
    loading = query.isNotEmpty && chat.appAccessible && chat.appForeground;
    notifyListeners();
    if (!loading) return;
    final needle = query;
    _timer = Timer(
      immediate ? Duration.zero : debounce,
      () => _search(generation, needle),
    );
  }

  Future<void> _search(int generation, String needle) async {
    final access = chat.accessRevision;
    bool cancelled() =>
        _disposed ||
        generation != _generation ||
        access != chat.accessRevision ||
        !chat.appAccessible ||
        !chat.appForeground;
    try {
      if (cancelled()) return;
      final found = groupId == null
          ? await chat.store.search(needle, isCancelled: cancelled)
          : const LocalSearchResults();
      if (cancelled()) return;
      final groupFound = await searchGroupHistories(
        chat.groups.histories,
        needle,
        groupId: groupId,
        isCancelled: cancelled,
      );
      if (cancelled()) return;
      results = found;
      groupResults = groupFound;
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
    chat.groups.removeListener(_historyChanged);
    results = const LocalSearchResults();
    groupResults = const GroupSearchResults();
    super.dispose();
  }
}
