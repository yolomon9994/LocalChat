import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/secure_session.dart';

Future<(SecureSession, SecureSession)> pair() async {
  final a = await SecureSession.create(await Ed25519().newKeyPair(), 'Alice');
  final b = await SecureSession.create(await Ed25519().newKeyPair(), 'Bob');
  await a.acceptHello(b.hello);
  await b.acceptHello(a.hello);
  return (a, b);
}

void main() {
  test(
    'Both peers derive matching code; encrypted Unicode text works both ways',
    () async {
      final (a, b) = await pair();
      expect(a.verificationCode, b.verificationCode);
      expect(a.peerId, isNot(b.peerId));
      final frame = await a.encrypt({'type': 'text', 'text': 'Hello 👋 سلام'});
      expect(jsonEncode(frame), isNot(contains('Hello')));
      expect(await b.decrypt(frame), {'type': 'text', 'text': 'Hello 👋 سلام'});
      expect(await a.decrypt(await b.encrypt({'type': 'ack', 'id': '123'})), {
        'type': 'ack',
        'id': '123',
      });
    },
  );
  test(
    'Signed handshake rejects identity, key, challenge and display-name tampering',
    () async {
      for (final field in ['identity', 'ephemeral', 'challenge', 'name']) {
        final a = await SecureSession.create(
          await Ed25519().newKeyPair(),
          'Alice',
        );
        final b = await SecureSession.create(
          await Ed25519().newKeyPair(),
          'Bob',
        );
        final hello = Map<String, dynamic>.from(b.hello);
        hello[field] = field == 'name'
            ? 'Mallory'
            : base64Encode(randomBytes(32));
        await expectLater(
          a.acceptHello(hello),
          throwsA(isA<FormatException>()),
        );
      }
    },
  );
  test(
    'Replay, sequence modification and wrong session are rejected',
    () async {
      final (a, b) = await pair();
      final frame = await a.encrypt({'type': 'text', 'text': 'one'});
      await b.decrypt(frame);
      await expectLater(b.decrypt(frame), throwsA(isA<FormatException>()));
      final next = await a.encrypt({'type': 'text', 'text': 'two'});
      await expectLater(
        b.decrypt({...next, 'seq': 3}),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        b.decrypt({...next, 'session': 'different'}),
        throwsA(isA<FormatException>()),
      );
      expect((await b.decrypt(next))['text'], 'two');
    },
  );
  test(
    'Ciphertext tampering is rejected without advancing receive sequence',
    () async {
      final (a, b) = await pair();
      final frame = await a.encrypt({'type': 'text', 'text': 'secret'});
      final bytes = base64Decode(frame['body'] as String);
      bytes[0] ^= 1;
      await expectLater(
        b.decrypt({...frame, 'body': base64Encode(bytes)}),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
      expect((await b.decrypt(frame))['text'], 'secret');
    },
  );
  test(
    'Fresh sessions change keys and verification codes, even with same identities',
    () async {
      final alice = await Ed25519().newKeyPair();
      final bob = await Ed25519().newKeyPair();
      final a = await SecureSession.create(alice, 'Alice');
      final b = await SecureSession.create(bob, 'Bob');
      await a.acceptHello(b.hello);
      await b.acceptHello(a.hello);
      final a2 = await SecureSession.create(alice, 'Alice');
      final b2 = await SecureSession.create(bob, 'Bob');
      await a2.acceptHello(b2.hello);
      await b2.acceptHello(a2.hello);
      expect(a2.peerId, a.peerId);
      expect(a2.verificationCode, isNot(a.verificationCode));
      await expectLater(
        b2.decrypt(await a.encrypt({'type': 'text', 'text': 'old'})),
        throwsA(isA<FormatException>()),
      );
    },
  );
  test('Reflection and repeated hello are rejected', () async {
    final a = await SecureSession.create(await Ed25519().newKeyPair(), 'Alice');
    await expectLater(a.acceptHello(a.hello), throwsA(isA<FormatException>()));
    final (b, c) = await pair();
    await expectLater(b.acceptHello(c.hello), throwsA(isA<FormatException>()));
  });
}
