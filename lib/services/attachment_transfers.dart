import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import '../core/chat_image.dart';
import '../core/chat_file.dart';
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
class AttachmentTransfers {
  AttachmentTransfers({
    required this.fileMode,
    required this.store,
    required this.peer,
    required this.canAct,
    required this.send,
    required this.enqueue,
    required this.changed,
    required this.persisted,
    this.timeout = const Duration(seconds: 30),
  });
  final bool fileMode;
  String get _kind => fileMode ? 'file' : 'image';
  String get _label => fileMode ? 'File' : 'Image';
  int _length(ChatMessage m) => fileMode ? m.file!.length : m.image!.length;
  Future<void> _verify(ChatMessage m, Uint8List bytes) async {
    if (fileMode) {
      await m.file!.verify(bytes);
    } else {
      await m.image!.verify(bytes);
      await validateImagePixels(bytes);
    }
  }

  Future<bool> _save(ChatMessage m, Uint8List bytes) => fileMode
      ? store.saveFileMessage(m, bytes)
      : store.saveImageMessage(m, bytes);
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
        _length(_in!.message),
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
          notice = '$_label transfer timed out. Delivery is unconfirmed.';
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

  Future<bool> start(
    Uint8List bytes, {
    ChatMessage? retry,
    String? name,
  }) async {
    final target = peer();
    if (!canAct() || target == null || _out != null) return false;
    _cancelRequested = false;
    notice = null;
    final image = fileMode ? null : await ChatImage.fromBytes(bytes);
    final file = fileMode
        ? await ChatFile.fromBytes(
            name ?? retry?.file?.name ?? 'attachment.bin',
            bytes,
          )
        : null;
    if (!canAct() || target != peer()) return false;
    final message =
        retry ??
        ChatMessage(
          id: randomId(),
          peerId: target,
          text: _label,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          outgoing: true,
          status: 'sending',
          image: image,
          file: file,
        );
    if (message.peerId != target ||
        !message.outgoing ||
        (fileMode
            ? message.file == null || message.image != null
            : message.image == null || message.file != null)) {
      return false;
    }
    _ended.remove(message.id);
    await _verify(message, bytes);
    if (retry == null) {
      await _save(message, bytes);
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
        'type': '${_kind}Offer',
        'id': message.id,
        'timestamp': message.timestamp,
        _kind: fileMode ? message.file!.toJson() : message.image!.toJson(),
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
      throw FormatException('Invalid $_kind transfer ID.');
    }
    if (_ended.contains(id) && p['type'] != '${_kind}Offer') return;
    final type = p['type'];
    if (type is! String || !type.startsWith(_kind)) {
      throw FormatException('Wrong attachment type.');
    }
    switch (type.substring(_kind.length)) {
      case 'Offer':
        _ended.remove(id);
        final image = fileMode ? null : ChatImage.parse(p['image']);
        final file = fileMode ? ChatFile.parse(p['file']) : null;
        final stamp = p['timestamp'];
        if (stamp is! int || stamp < 0 || stamp > 8640000000000000) {
          throw FormatException('Invalid $_kind timestamp.');
        }
        if (!canAct() || _in != null || id == _out?.message.id) {
          _remember(id);
          await send({
            'type': '${_kind}Result',
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
            text: _label,
            timestamp: stamp,
            outgoing: false,
            status: 'received',
            image: image,
            file: file,
          ),
        );
        _watch(false);
        await send({'type': '${_kind}Ready', 'id': id}, false);
      case 'Ready':
        final out = _out;
        if (out == null || id != out.message.id || out.phase != 'offer') {
          throw FormatException('Unexpected $_kind acceptance.');
        }
        await _nextChunk();
      case 'Chunk':
        final incoming = _in;
        if (incoming == null ||
            id != incoming.message.id ||
            p['index'] != incoming.index ||
            p['data'] is! String ||
            (p['data'] as String).length > imageChunkBytes * 4 ~/ 3) {
          throw FormatException('Invalid $_kind chunk.');
        }
        if (!canAct() || _cancelRequested) {
          await _cancelOne(id, false, notifyPeer: true);
          return;
        }
        final bytes = base64Decode(p['data'] as String);
        final expected = math.min(
          imageChunkBytes,
          _length(incoming.message) - incoming.buffer.length,
        );
        if (expected <= 0 || bytes.length != expected) {
          throw FormatException('Invalid $_kind chunk length.');
        }
        incoming.buffer.add(bytes);
        final index = incoming.index++;
        _watch(false);
        await send({
          'type': '${_kind}ChunkAck',
          'id': id,
          'index': index,
        }, false);
      case 'ChunkAck':
        final out = _out;
        if (out == null ||
            id != out.message.id ||
            out.phase != 'chunk' ||
            p['index'] != out.index) {
          throw FormatException('Unexpected $_kind chunk receipt.');
        }
        out.done = math.min(out.bytes.length, out.done + imageChunkBytes);
        out.index++;
        await _nextChunk();
      case 'Complete':
        final incoming = _in;
        if (incoming == null ||
            id != incoming.message.id ||
            incoming.buffer.length != _length(incoming.message)) {
          throw FormatException('Incomplete $_kind transfer.');
        }
        if (!canAct() || _cancelRequested) {
          await _cancelOne(id, false, notifyPeer: true);
          return;
        }
        final bytes = incoming.buffer.takeBytes();
        await _verify(incoming.message, bytes);
        if (!canAct() || _cancelRequested) {
          await _cancelOne(id, false, notifyPeer: true);
          return;
        }
        final inserted = await _save(incoming.message, bytes);
        _inTimer?.cancel();
        _inTimer = null;
        _in = null;
        _remember(id);
        await persisted(incoming.message, inserted);
        await send({
          'type': '${_kind}Result',
          'id': id,
          'received': true,
        }, false);
      case 'Result':
        final out = _out;
        if (out == null ||
            id != out.message.id ||
            p['received'] is! bool ||
            (p['received'] == true && out.phase != 'finish')) {
          throw FormatException('Unexpected $_kind delivery receipt.');
        }
        await store.changeOutgoingStatus(id, out.message.peerId, [
          'sending',
          'unconfirmed',
        ], p['received'] == true ? 'delivered' : 'unconfirmed');
        notice = p['received'] == true
            ? '$_label received by the other phone.'
            : '$_label was declined. Keep both phones unlocked in the foreground and try again.';
        _outTimer?.cancel();
        _outTimer = null;
        _out = null;
        _remember(id);
        await persisted(out.message, false);
      case 'Cancel':
        if (_out?.message.id == id) {
          await _cancelOne(id, true, notifyPeer: false);
        }
        if (_in?.message.id == id) {
          await _cancelOne(id, false, notifyPeer: false);
        }
        notice = '$_label transfer cancelled. Delivery may be unconfirmed.';
      default:
        throw FormatException('Unknown $_kind transfer operation.');
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
      await send({'type': '${_kind}Complete', 'id': out.message.id}, true);
    } else {
      out.phase = 'chunk';
      await send({
        'type': '${_kind}Chunk',
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
        await send({'type': '${_kind}Cancel', 'id': id}, false);
      }
      changed();
    }
  }

  Future<void> cancel() async {
    requestCancel();
    final out = _out?.message.id, incoming = _in?.message.id;
    notice = '$_label transfer cancelled. Delivery may be unconfirmed.';
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
          'Connection ended. $_label delivery is unconfirmed; nothing resumes automatically.';
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
