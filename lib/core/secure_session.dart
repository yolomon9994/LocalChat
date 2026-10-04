import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';

List<int> randomBytes(int count) {
  final random = Random.secure();
  return List<int>.generate(count, (_) => random.nextInt(256));
}

String randomId() => base64UrlEncode(randomBytes(18));
String hex(List<int> bytes) =>
    bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();

/// Experimental protocol v1. See docs/SECURITY.md before making security claims.
class SecureSession {
  SecureSession._(this.identity, this.ephemeral, this.hello);
  final SimpleKeyPair identity;
  final SimpleKeyPair ephemeral;
  final Map<String, dynamic> hello;
  String? peerId;
  String? peerName;
  String? verificationCode;
  String? sessionId;
  SecretKey? _sendKey;
  SecretKey? _receiveKey;
  int _sent = 0;
  int _received = 0;
  static final _cipher = Xchacha20.poly1305Aead();

  static List<int> _helloBytes(Map<String, dynamic> h) => utf8.encode(
    jsonEncode([
      'LocalChat/hello/1',
      h['identity'],
      h['ephemeral'],
      h['challenge'],
      h['name'],
    ]),
  );

  static Future<SecureSession> create(
    SimpleKeyPair identity,
    String name,
  ) async {
    final ephemeral = await X25519().newKeyPair();
    final hello = <String, dynamic>{
      'v': 1,
      'kind': 'hello',
      'identity': base64Encode((await identity.extractPublicKey()).bytes),
      'ephemeral': base64Encode((await ephemeral.extractPublicKey()).bytes),
      'challenge': base64Encode(randomBytes(32)),
      'name': name,
    };
    hello['signature'] = base64Encode(
      (await Ed25519().sign(_helloBytes(hello), keyPair: identity)).bytes,
    );
    return SecureSession._(identity, ephemeral, hello);
  }

  Future<void> acceptHello(Map<String, dynamic> remote) async {
    if (_sendKey != null) throw const FormatException('Repeated handshake');
    if (remote['v'] != 1 ||
        remote['kind'] != 'hello' ||
        remote['name'] is! String ||
        (remote['name'] as String).isEmpty ||
        (remote['name'] as String).length > 32) {
      throw const FormatException('Invalid handshake');
    }
    final public = base64Decode(remote['identity'] as String);
    final ephemeralPublic = base64Decode(remote['ephemeral'] as String);
    final challenge = base64Decode(remote['challenge'] as String);
    final signature = base64Decode(remote['signature'] as String);
    if (public.length != 32 ||
        ephemeralPublic.length != 32 ||
        challenge.length != 32 ||
        signature.length != 64 ||
        remote['identity'] == hello['identity']) {
      throw const FormatException('Invalid peer keys');
    }
    if (!await Ed25519().verify(
      _helloBytes(remote),
      signature: Signature(
        signature,
        publicKey: SimplePublicKey(public, type: KeyPairType.ed25519),
      ),
    )) {
      throw const FormatException('Invalid peer signature');
    }
    final localFirst =
        (hello['identity'] as String).compareTo(remote['identity'] as String) <
        0;
    final transcript = <int>[
      ...utf8.encode('LocalChat/transcript/1'),
      ..._helloBytes(localFirst ? hello : remote),
      ..._helloBytes(localFirst ? remote : hello),
    ];
    final digest = (await Sha256().hash(transcript)).bytes;
    final shared = await X25519().sharedSecretKey(
      keyPair: ephemeral,
      remotePublicKey: SimplePublicKey(
        ephemeralPublic,
        type: KeyPairType.x25519,
      ),
    );
    if ((await shared.extractBytes()).every((v) => v == 0)) {
      throw const FormatException('Invalid key agreement');
    }
    Future<SecretKey> derive(String label) =>
        Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
          secretKey: shared,
          nonce: digest,
          info: utf8.encode('LocalChat/1/$label'),
        );
    _sendKey = await derive(localFirst ? 'low-to-high' : 'high-to-low');
    _receiveKey = await derive(localFirst ? 'high-to-low' : 'low-to-high');
    sessionId = hex(digest);
    peerId = hex((await Sha256().hash(public)).bytes);
    peerName = remote['name'] as String;
    // 80 bits, bound to BOTH identities, ephemeral keys, names and challenges.
    final code = hex(
      (await Sha256().hash([
        ...utf8.encode('LocalChat/SAS/1'),
        ...digest,
      ])).bytes.sublist(0, 10),
    );
    verificationCode = List.generate(
      5,
      (i) => code.substring(i * 4, i * 4 + 4),
    ).join(' ');
  }

  Future<Map<String, dynamic>> encrypt(Map<String, dynamic> payload) async {
    if (_sendKey == null) throw StateError('Handshake incomplete');
    final sequence = ++_sent;
    final aad = utf8.encode(
      jsonEncode(['LocalChat/frame/1', sessionId, sequence]),
    );
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode(payload)),
      secretKey: _sendKey!,
      aad: aad,
    );
    return {
      'v': 1,
      'kind': 'sealed',
      'session': sessionId,
      'seq': sequence,
      'nonce': base64Encode(box.nonce),
      'body': base64Encode(box.cipherText),
      'tag': base64Encode(box.mac.bytes),
    };
  }

  Future<Map<String, dynamic>> decrypt(Map<String, dynamic> frame) async {
    if (_receiveKey == null ||
        frame['v'] != 1 ||
        frame['kind'] != 'sealed' ||
        frame['session'] != sessionId ||
        frame['seq'] != _received + 1) {
      throw const FormatException('Invalid, replayed or out-of-order frame');
    }
    final nonce = base64Decode(frame['nonce'] as String);
    final tag = base64Decode(frame['tag'] as String);
    if (nonce.length != 24 || tag.length != 16) {
      throw const FormatException('Invalid ciphertext');
    }
    final clear = await _cipher.decrypt(
      SecretBox(
        base64Decode(frame['body'] as String),
        nonce: nonce,
        mac: Mac(tag),
      ),
      secretKey: _receiveKey!,
      aad: utf8.encode(
        jsonEncode(['LocalChat/frame/1', sessionId, frame['seq']]),
      ),
    );
    final payload = Map<String, dynamic>.from(
      jsonDecode(utf8.decode(clear)) as Map,
    );
    _received++;
    return payload;
  }
}
