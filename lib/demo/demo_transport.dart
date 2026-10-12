import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import '../core/secure_session.dart';
import '../services/transport.dart';
import '../core/chat_image.dart';

/// A peer entirely inside this process. No channels, sockets or network calls.
/// Real protocol frames exercise the shared controller, but the peer's trust
/// confirmation and all delivery acknowledgements are simulated.
class DemoTransport implements Transport {
  DemoTransport({this.supportsImages = true});
  final bool supportsImages;
  static const devices = {'demo-ava': 'Ava (Demo)', 'demo-noah': 'Noah (Demo)'};
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final _identities = <String, SimpleKeyPair>{};
  SecureSession? _peer;
  bool _started = false;
  bool _verified = false;
  int _generation = 0;
  int _reply = 0;
  ChatImage? _image;
  String? _imageId;
  BytesBuilder? _imageBytes;
  int _imageIndex = 0;

  @override
  Stream<Map<String, dynamic>> get events => _events.stream;

  @override
  Future<void> start(String name) async => _started = true;

  @override
  Future<void> scan() async {
    if (!_started) throw StateError('Tap Go nearby first.');
    final generation = _generation;
    _events.add({'type': 'scanning', 'active': true});
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!_started || generation != _generation) return;
    _events.add({
      'type': 'peers',
      'peers': [
        for (final device in devices.entries)
          {'address': device.key, 'name': device.value},
      ],
    });
    _events.add({'type': 'scanning', 'active': false});
  }

  @override
  Future<void> connect(String address) async {
    if (!_started || !devices.containsKey(address)) {
      throw StateError('Select a simulated nearby device.');
    }
    final generation = ++_generation;
    final identity = _identities[address] ??= await Ed25519().newKeyPair();
    final peer = await SecureSession.create(identity, devices[address]!);
    if (!_started || generation != _generation) return;
    _peer = peer;
    _verified = false;
    _reply = 0;
    _events.add({'type': 'connected'});
  }

  Future<void> _emitPayload(
    SecureSession peer,
    Map<String, dynamic> payload,
  ) async {
    final frame = await peer.encrypt(payload);
    if (!identical(_peer, peer)) return;
    _events.add({'type': 'frame', 'frame': jsonEncode(frame)});
  }

  Future<void> _message(SecureSession peer, String text) => _emitPayload(peer, {
    'type': 'text',
    'id': randomId(),
    'timestamp': DateTime.now().millisecondsSinceEpoch,
    'text': text,
  });

  @override
  Future<void> send(String frame) async {
    final peer = _peer;
    if (peer == null) throw StateError('No simulated peer connected.');
    final decoded = Map<String, dynamic>.from(jsonDecode(frame) as Map);
    if (decoded['kind'] == 'hello') {
      await peer.acceptHello(decoded);
      if (identical(_peer, peer)) {
        _events.add({'type': 'frame', 'frame': jsonEncode(peer.hello)});
      }
      return;
    }
    final payload = await peer.decrypt(decoded);
    switch (payload['type']) {
      case 'verified':
        _verified = true;
        await _emitPayload(peer, {
          'type': 'verified',
          if (supportsImages) 'features': ['image-v1'],
        });
        await _message(
          peer,
          'Hello from a simulated friend! Send a message to try the chat. '
          'Everything here stays in this browser tab until you reload.',
        );
      case 'text':
        if (!_verified) throw StateError('Confirm the demo code first.');
        await _emitPayload(peer, {'type': 'ack', 'id': payload['id']});
        await Future<void>.delayed(const Duration(milliseconds: 600));
        if (!identical(_peer, peer)) return;
        const replies = [
          'Got your message! This reply and the delivery status are simulated.',
          'Try disconnecting and reopening this conversation from saved history.',
          'You can also change your display name or delete demo history in Settings.',
        ];
        await _message(peer, replies[_reply++ % replies.length]);
      case 'ack':
        // The demo peer has no persistent outbox.
        break;
      case 'imageOffer':
        if (!_verified) throw StateError('Confirm the demo code first.');
        _image = ChatImage.parse(payload['image']);
        _imageId = payload['id'] as String;
        _imageBytes = BytesBuilder(copy: false);
        _imageIndex = 0;
        await _emitPayload(peer, {'type': 'imageReady', 'id': _imageId});
      case 'imageChunk':
        if (payload['id'] != _imageId ||
            payload['index'] != _imageIndex ||
            _imageBytes == null) {
          throw const FormatException('Invalid demo image chunk.');
        }
        final bytes = base64Decode(payload['data'] as String);
        if (_imageBytes!.length + bytes.length > _image!.length) {
          throw const FormatException('Demo image limit exceeded.');
        }
        _imageBytes!.add(bytes);
        await _emitPayload(peer, {
          'type': 'imageChunkAck',
          'id': _imageId,
          'index': _imageIndex++,
        });
      case 'imageComplete':
        if (payload['id'] != _imageId ||
            _image == null ||
            _imageBytes == null) {
          throw const FormatException('No demo image transfer.');
        }
        await _image!.verify(_imageBytes!.takeBytes());
        await _emitPayload(peer, {
          'type': 'imageResult',
          'id': _imageId,
          'received': true,
        });
        _image = null;
        _imageId = null;
        _imageBytes = null;
      case 'imageCancel':
        _image = null;
        _imageId = null;
        _imageBytes = null;
      default:
        throw const FormatException('Unsupported demo payload');
    }
  }

  @override
  Future<void> disconnect() async {
    ++_generation;
    _peer = null;
    _verified = false;
    _image = null;
    _imageId = null;
    _imageBytes = null;
    // ChatController resets state after an intentional disconnect. Emitting
    // another event here would leave a redundant reset queued during disposal.
  }

  @override
  Future<void> stop() async {
    _started = false;
    await disconnect();
  }
}
