import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import '../core/chat_image.dart';
import '../core/local_store.dart';
import '../core/models.dart';
import '../core/secure_session.dart';
import 'image_content.dart';

class ImageProgress {
  const ImageProgress(this.id, this.peer, this.total, this.done, this.outgoing);
  final String id, peer;
  final int total, done;
  final bool outgoing;
  double get fraction => done / total;
}

class _Sending {
  _Sending(this.message, this.bytes);
  final ChatMessage message;
  final Uint8List bytes;
  int done = 0, index = 0;
  String phase = 'offer';
}

class _Receiving {
  _Receiving(this.message);
  final ChatMessage message;
  final buffer = BytesBuilder(copy: false);
  int index = 0;
}

/// All protocol operations run on ChatController's existing sequence queue.
/// One acknowledged chunk at a time keeps cancellation and text responsive.
class ImageTransfers {
  ImageTransfers({
    required this.store,
    required this.peer,
    required this.canAct,
    required this.send,
    required this.enqueue,
    required this.changed,
    required this.persisted,
    this.timeout = const Duration(seconds: 30),
  });
  final LocalStore store;
  final String? Function() peer;
  final bool Function() canAct;
  final Future<void> Function(Map<String, dynamic>, bool origin) send;
  final Future<void> Function(Future<void> Function()) enqueue;
  final void Function() changed;
  final Future<void> Function(ChatMessage, bool inserted) persisted;
  final Duration timeout;
  _Sending? _out;
  _Receiving? _in;
  Timer? _outTimer, _inTimer;
  bool _cancelRequested = false, _disposed = false;
  final _ended = <String>[];
  String? notice;
  bool get sending => _out != null;
  List<ImageProgress> get progress => [
    if (_out != null)
      ImageProgress(
        _out!.message.id,
        _out!.message.peerId,
        _out!.bytes.length,
        _out!.done,
        true,
      ),
    if (_in != null)
      ImageProgress(
        _in!.message.id,
        _in!.message.peerId,
        _in!.message.image!.length,
        _in!.buffer.length,
        false,
      ),
  ];
  void requestCancel() {
    _cancelRequested = true;
  }

  void _remember(String id) {
    _ended.add(id);
    if (_ended.length > 8) _ended.removeAt(0);
  }

  void _watch(bool outgoing) {
    if (outgoing) {
      _outTimer?.cancel();
    } else {
      _inTimer?.cancel();
    }
    final id = outgoing ? _out?.message.id : _in?.message.id;
    late final Timer timer;
    timer = Timer(timeout, () {
      if (_disposed) return;
      unawaited(
        enqueue(() async {
          if (!identical(timer, outgoing ? _outTimer : _inTimer) ||
              id != (outgoing ? _out?.message.id : _in?.message.id)) {
            return;
          }
          notice = 'Image transfer timed out. Delivery is unconfirmed.';
          await _cancelOne(id!, outgoing, notifyPeer: true);
        }),
      );
    });
    if (outgoing) {
      _outTimer = timer;
    } else {
      _inTimer = timer;
    }
  }

  Future<bool> start(Uint8List bytes, {ChatMessage? retry}) async {
    final target = peer();
    if (!canAct() || target == null || _out != null) return false;
    _cancelRequested = false;
    notice = null;
    final image = await ChatImage.fromBytes(bytes);
    await validateImagePixels(bytes);
    if (!canAct() || target != peer()) return false;
    final message =
        retry ??
        ChatMessage(
          id: randomId(),
          peerId: target,
          text: 'Image',
          timestamp: DateTime.now().millisecondsSinceEpoch,
          outgoing: true,
          status: 'sending',
          image: image,
        );
    if (message.peerId != target ||
        !message.outgoing ||
        message.image == null) {
      return false;
    }
    _ended.remove(message.id);
    await message.image!.verify(bytes);
    if (retry == null) {
      await store.saveImageMessage(message, bytes);
    } else if (!await store.changeOutgoingStatus(message.id, target, [
      'unconfirmed',
    ], 'sending')) {
      return false;
    }
    _out = _Sending(message, Uint8List.fromList(bytes));
    await persisted(message, false);
    if (!canAct() || _cancelRequested) {
      await _cancelOne(message.id, true, notifyPeer: false);
      return true;
    }
    _watch(true);
    changed();
    try {
      await send({
        'type': 'imageOffer',
        'id': message.id,
        'timestamp': message.timestamp,
        'image': image.toJson(),
      }, true);
    } catch (_) {
      await stop();
      rethrow;
    }
    return true;
  }

  Future<void> handle(Map<String, dynamic> p) async {
    final id = p['id'];
    if (id is! String || !RegExp(r'^[A-Za-z0-9_-]{24}$').hasMatch(id)) {
      throw const FormatException('Invalid image transfer ID.');
    }
    if (_ended.contains(id) && p['type'] != 'imageOffer') return;
    switch (p['type']) {
      case 'imageOffer':
        _ended.remove(id);
        final image = ChatImage.parse(p['image']);
        final stamp = p['timestamp'];
        if (stamp is! int || stamp < 0 || stamp > 8640000000000000) {
          throw const FormatException('Invalid image timestamp.');
        }
        if (!canAct() || _in != null || id == _out?.message.id) {
          _remember(id);
          await send({
            'type': 'imageResult',
            'id': id,
            'received': false,
          }, false);
          return;
        }
        if (_out == null) _cancelRequested = false;
        notice = null;
        _in = _Receiving(
          ChatMessage(
            id: id,
            peerId: peer()!,
            text: 'Image',
            timestamp: stamp,
            outgoing: false,
            status: 'received',
            image: image,
          ),
        );
        _watch(false);
        await send({'type': 'imageReady', 'id': id}, false);
      case 'imageReady':
        final out = _out;
        if (out == null || id != out.message.id || out.phase != 'offer') {
          throw const FormatException('Unexpected image acceptance.');
        }
        await _nextChunk();
      case 'imageChunk':
        final incoming = _in;
        if (incoming == null ||
            id != incoming.message.id ||
            p['index'] != incoming.index ||
            p['data'] is! String ||
            (p['data'] as String).length > imageChunkBytes * 4 ~/ 3) {
          throw const FormatException('Invalid image chunk.');
        }
        if (!canAct() || _cancelRequested) {
          await _cancelOne(id, false, notifyPeer: true);
          return;
        }
        final bytes = base64Decode(p['data'] as String);
        final expected = math.min(
          imageChunkBytes,
          incoming.message.image!.length - incoming.buffer.length,
        );
        if (expected <= 0 || bytes.length != expected) {
          throw const FormatException('Invalid image chunk length.');
        }
        incoming.buffer.add(bytes);
        final index = incoming.index++;
        _watch(false);
        await send({'type': 'imageChunkAck', 'id': id, 'index': index}, false);
      case 'imageChunkAck':
        final out = _out;
        if (out == null ||
            id != out.message.id ||
            out.phase != 'chunk' ||
            p['index'] != out.index) {
          throw const FormatException('Unexpected image chunk receipt.');
        }
        out.done = math.min(out.bytes.length, out.done + imageChunkBytes);
        out.index++;
        await _nextChunk();
      case 'imageComplete':
        final incoming = _in;
        if (incoming == null ||
            id != incoming.message.id ||
            incoming.buffer.length != incoming.message.image!.length) {
          throw const FormatException('Incomplete image transfer.');
        }
        if (!canAct() || _cancelRequested) {
          await _cancelOne(id, false, notifyPeer: true);
          return;
        }
        final bytes = incoming.buffer.takeBytes();
        await incoming.message.image!.verify(bytes);
        await validateImagePixels(bytes);
        if (!canAct() || _cancelRequested) {
          await _cancelOne(id, false, notifyPeer: true);
          return;
        }
        final inserted = await store.saveImageMessage(incoming.message, bytes);
        _inTimer?.cancel();
        _inTimer = null;
        _in = null;
        _remember(id);
        await persisted(incoming.message, inserted);
        await send({'type': 'imageResult', 'id': id, 'received': true}, false);
      case 'imageResult':
        final out = _out;
        if (out == null ||
            id != out.message.id ||
            p['received'] is! bool ||
            (p['received'] == true && out.phase != 'finish')) {
          throw const FormatException('Unexpected image delivery receipt.');
        }
        await store.changeOutgoingStatus(id, out.message.peerId, [
          'sending',
          'unconfirmed',
        ], p['received'] == true ? 'delivered' : 'unconfirmed');
        notice = p['received'] == true
            ? 'Image received by the other phone.'
            : 'Image was declined. Keep both phones unlocked in the foreground and try again.';
        _outTimer?.cancel();
        _outTimer = null;
        _out = null;
        _remember(id);
        await persisted(out.message, false);
      case 'imageCancel':
        if (_out?.message.id == id) {
          await _cancelOne(id, true, notifyPeer: false);
        }
        if (_in?.message.id == id) {
          await _cancelOne(id, false, notifyPeer: false);
        }
        notice = 'Image transfer cancelled. Delivery may be unconfirmed.';
      default:
        throw const FormatException('Unknown image transfer operation.');
    }
    changed();
  }

  Future<void> _nextChunk() async {
    final out = _out!;
    if (!canAct() || _cancelRequested) {
      await _cancelOne(out.message.id, true, notifyPeer: true);
      return;
    }
    _watch(true);
    if (out.done == out.bytes.length) {
      out.phase = 'finish';
      await send({'type': 'imageComplete', 'id': out.message.id}, true);
    } else {
      out.phase = 'chunk';
      await send({
        'type': 'imageChunk',
        'id': out.message.id,
        'index': out.index,
        'data': base64Encode(
          out.bytes.sublist(
            out.done,
            math.min(out.bytes.length, out.done + imageChunkBytes),
          ),
        ),
      }, true);
    }
  }

  Future<void> _cancelOne(
    String id,
    bool outgoing, {
    required bool notifyPeer,
  }) async {
    final message = outgoing ? _out?.message : _in?.message;
    if (message == null || message.id != id) return;
    if (outgoing) {
      _outTimer?.cancel();
      _outTimer = null;
      _out = null;
    } else {
      _inTimer?.cancel();
      _inTimer = null;
      _in = null;
    }
    _remember(id);
    try {
      if (outgoing) {
        await store.changeOutgoingStatus(id, message.peerId, [
          'sending',
        ], 'unconfirmed');
        await persisted(message, false);
      }
    } finally {
      if (notifyPeer && peer() != null) {
        await send({'type': 'imageCancel', 'id': id}, false);
      }
      changed();
    }
  }

  Future<void> cancel() async {
    requestCancel();
    final out = _out?.message.id, incoming = _in?.message.id;
    notice = 'Image transfer cancelled. Delivery may be unconfirmed.';
    try {
      if (out != null) await _cancelOne(out, true, notifyPeer: true);
    } finally {
      if (incoming != null) await _cancelOne(incoming, false, notifyPeer: true);
    }
  }

  Future<void> stop() async {
    _outTimer?.cancel();
    _inTimer?.cancel();
    final out = _out;
    _out = null;
    _in = null;
    _ended.clear();
    _cancelRequested = true;
    if (out != null) {
      await store.changeOutgoingStatus(out.message.id, out.message.peerId, [
        'sending',
      ], 'unconfirmed');
      notice =
          'Connection ended. Image delivery is unconfirmed; nothing resumes automatically.';
    }
    changed();
  }

  void dispose() {
    _disposed = true;
    _outTimer?.cancel();
    _inTimer?.cancel();
    _out = null;
    _in = null;
  }
}
