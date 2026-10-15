import 'dart:async';
import 'package:flutter/material.dart';
import '../core/models.dart';
import '../core/group_models.dart';
import '../core/starred_message.dart';
import '../services/chat_controller.dart';
import 'chat_screen.dart';
import 'group_screen.dart';

class StarredMessagesScreen extends StatefulWidget {
  const StarredMessagesScreen({
    super.key,
    required this.controller,
    this.routeObserver,
  });
  final ChatController controller;
  final RouteObserver<ModalRoute<dynamic>>? routeObserver;
  @override
  State<StarredMessagesScreen> createState() => _StarredMessagesScreenState();
}

class _SavedStar {
  const _SavedStar(this.star, this.title, {this.message, this.groupMessage});
  final StarredMessage star;
  final String title;
  final ChatMessage? message;
  final GroupText? groupMessage;
  int get timestamp => message?.timestamp ?? groupMessage!.timestamp;
  String get text =>
      message?.file?.name ??
      groupMessage?.file?.name ??
      (message?.image != null || groupMessage?.image != null
          ? 'Image'
          : message?.text ?? groupMessage!.text);
}

class _StarredMessagesScreenState extends State<StarredMessagesScreen> {
  final _items = <_SavedStar>[];
  Object? _stamp;
  int _generation = 0;
  bool _loading = true, _opening = false;
  String? _error;
  ChatController get c => widget.controller;
  bool get _allowed => c.initialized && c.appAccessible && c.appForeground;
  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
    _changed();
  }

  void _changed() {
    final stamp = (
      _allowed,
      c.historyRevision,
      c.groups.historyRevision,
      c.starsRevision,
      c.starsError,
    );
    if (_stamp == stamp) return;
    _stamp = stamp;
    final generation = ++_generation;
    if (!_allowed) {
      _items.clear();
      _loading = false;
      _error = null;
      if (mounted) setState(() {});
      return;
    }
    unawaited(_load(generation));
  }

  Future<void> _load(int generation) async {
    _loading = true;
    _error = null;
    if (mounted) setState(() {});
    try {
      final refs = c.starred.toList();
      final people = {for (final p in await c.store.conversations()) p.id: p};
      final groups = {for (final g in await c.store.groupHistories()) g.id: g};
      final histories = <String, List<ChatMessage>>{};
      final result = <_SavedStar>[];
      for (final star in refs) {
        if (!mounted || generation != _generation || !_allowed) return;
        if (star.group) {
          final g = groups[star.target];
          final matches = g?.messages.where(
            (m) => m.id == star.id && m.author == star.author,
          );
          if (g != null && matches!.isNotEmpty) {
            result.add(_SavedStar(star, g.title, groupMessage: matches.first));
          }
        } else {
          final peer = people[star.target];
          if (peer == null) continue;
          final history = histories[star.target] ??= await c.store.messages(
            star.target,
          );
          final matches = history.where(
            (m) => m.id == star.id && m.outgoing == star.outgoing,
          );
          if (matches.isNotEmpty) {
            result.add(_SavedStar(star, peer.name, message: matches.first));
          }
        }
      }
      result.sort((a, b) {
        final time = b.timestamp.compareTo(a.timestamp);
        return time != 0 ? time : a.star.key.compareTo(b.star.key);
      });
      if (!mounted || generation != _generation || !_allowed) return;
      _items
        ..clear()
        ..addAll(result);
      _error = c.starsError;
    } catch (_) {
      if (!mounted || generation != _generation) return;
      _items.clear();
      _error = 'Could not load starred messages. Try again.';
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _retry() async {
    await c.refreshStars();
    if (mounted && _allowed) await _load(++_generation);
  }

  Future<void> _unstar(_SavedStar item) async {
    if (!_allowed || _opening || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final interaction = c.interactionRevision;
    final ok = await c.setStarred(item.star, false);
    if (!ok &&
        mounted &&
        _allowed &&
        interaction == c.interactionRevision &&
        ModalRoute.of(context)?.isCurrent == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update this starred message. Try again.'),
        ),
      );
    }
  }

  Future<void> _open(_SavedStar item) async {
    if (!_allowed ||
        _opening ||
        !c.isStarred(item.star) ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final interaction = c.interactionRevision;
    setState(() => _opening = true);
    try {
      Widget? screen;
      if (item.star.group) {
        final matches = c.groups.histories.where(
          (g) => g.id == item.star.target,
        );
        if (matches.isNotEmpty &&
            matches.first.messages.any(
              (m) =>
                  m.key == item.groupMessage!.key &&
                  m.envelope['signature'] ==
                      item.groupMessage!.envelope['signature'],
            )) {
          screen = GroupChatScreen(
            controller: c,
            id: item.star.target,
            routeObserver: widget.routeObserver,
            focusMessageKey: item.groupMessage!.key,
            fromStar: true,
          );
        }
      } else {
        final peers = c.conversations.where((p) => p.id == item.star.target);
        if (peers.isNotEmpty &&
            await c.viewHistory(peers.first) &&
            c.messages.any(
              (m) =>
                  m.id == item.star.id &&
                  m.outgoing == item.star.outgoing &&
                  m.text == item.message!.text &&
                  m.timestamp == item.message!.timestamp,
            )) {
          screen = ChatScreen(
            controller: c,
            routeObserver: widget.routeObserver,
            focusMessage: item.message,
            fromStar: true,
          );
        }
      }
      if (!mounted ||
          !_allowed ||
          interaction != c.interactionRevision ||
          ModalRoute.of(context)?.isCurrent != true ||
          !c.isStarred(item.star)) {
        return;
      }
      if (screen == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This message is no longer available.')),
        );
        await _retry();
      } else {
        await Navigator.of(
          context,
        ).push<void>(MaterialPageRoute(builder: (_) => screen!));
      }
    } catch (_) {
      if (mounted &&
          _allowed &&
          interaction == c.interactionRevision &&
          ModalRoute.of(context)?.isCurrent == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open this message. Try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  void dispose() {
    _generation++;
    c.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Starred messages')),
    body: !_allowed
        ? const Center(
            child: Text('Return to the unlocked app to view starred messages.'),
          )
        : _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, textAlign: TextAlign.center),
                TextButton(onPressed: _retry, child: const Text('Retry')),
              ],
            ),
          )
        : _items.isEmpty
        ? const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No starred messages yet.\nLong press a message and choose Star.',
                textAlign: TextAlign.center,
              ),
            ),
          )
        : Column(
            children: [
              if (_opening) const LinearProgressIndicator(),
              Expanded(
                child: ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    final interaction = c.interactionRevision;
                    final author = item.message != null
                        ? item.message!.outgoing
                              ? 'You'
                              : item.title
                        : item.groupMessage!.author == c.groups.selfId
                        ? 'You'
                        : item.groupMessage!.name;
                    return ListTile(
                      key: ValueKey(('starred', item.star.key)),
                      leading: Icon(
                        item.star.group
                            ? Icons.groups_outlined
                            : Icons.chat_bubble_outline,
                      ),
                      title: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '$author: ${item.text}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        tooltip: 'Unstar message',
                        onPressed: _opening
                            ? null
                            : () {
                                if (interaction == c.interactionRevision) {
                                  unawaited(_unstar(item));
                                }
                              },
                        icon: const Icon(Icons.star),
                      ),
                      onTap: _opening
                          ? null
                          : () {
                              if (interaction == c.interactionRevision) {
                                unawaited(_open(item));
                              }
                            },
                    );
                  },
                ),
              ),
            ],
          ),
  );
}
