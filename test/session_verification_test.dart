import 'dart:async';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/models.dart';
import 'package:local_chat/core/secure_session.dart';
import 'package:local_chat/core/session_verification.dart';
import 'package:local_chat/services/chat_controller.dart';
import 'chat_controller_test.dart' show LinkedTransport, settle;
import 'message_reply_test.dart' show ReplyStore;
import 'group_test_support.dart';

class VerificationStore extends ReplyStore {
  Completer<void>? historyGate;
  final entered = Completer<void>();
  @override
  Future<List<ChatMessage>> messages(String peer) async {
    if (historyGate != null) {
      if (!entered.isCompleted) entered.complete();
      await historyGate!.future;
    }
    return super.messages(peer);
  }
}

class VerificationTransport extends LinkedTransport {
  final sendEntered = Completer<void>();
  @override
  Future<void> send(String frame) async {
    if (sendGate != null && !sendEntered.isCompleted) sendEntered.complete();
    await super.send(frame);
  }
}

class VerificationPair {
  VerificationPair(this.a, this.b, this.ta, this.tb);
  final ChatController a, b;
  final LinkedTransport ta, tb;
  Future<void> close() async {
    a.dispose();
    b.dispose();
    await ta.bus.close();
    await tb.bus.close();
  }
}

Future<VerificationPair> verificationPair({
  VerificationStore? store,
  Duration timeout = const Duration(seconds: 90),
}) async {
  final ta = VerificationTransport(), tb = VerificationTransport();
  ta.other = tb;
  tb.other = ta;
  final a = ChatController(
    ta,
    store ?? VerificationStore(),
    isDemo: true,
    connectionTimeout: timeout,
  );
  final b = ChatController(tb, VerificationStore(), isDemo: true);
  await a.initialize();
  await b.initialize();
  await a.start();
  await b.start();
  await a.connect(const Peer('B', 'Bob'));
  await settle();
  return VerificationPair(a, b, ta, tb);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('QR parser bounds shape, version, scope and canonical full digests', () {
    final qr = VerificationQr(
      scope: VerificationScope.direct,
      session: '1' * 64,
      sender: '2' * 64,
      receiver: '3' * 64,
    );
    expect(VerificationQr.parse(qr.encode), qr);
    final raw = jsonDecode(qr.encode) as Map;
    for (final invalid in [
      '',
      'https://example.com',
      ' ' * 513,
      '🙂' * 200,
      jsonEncode({...raw, 'v': 2}),
      jsonEncode({...raw, 'mode': 'login'}),
      jsonEncode({...raw, 'session': '1' * 20}),
      jsonEncode({...raw, 'from': 'A' * 64}),
      jsonEncode({...raw, 'to': null}),
      jsonEncode({...raw, 'from': raw['to']}),
      jsonEncode({...raw, 'extra': true}),
      jsonEncode({'v': 1}),
      '[]',
    ]) {
      expect(() => VerificationQr.parse(invalid), throwsFormatException);
      expect(qr.matchesRemote(invalid), isFalse);
    }
  });
  test(
    'real handshakes produce reciprocal public QR values without private key material',
    () async {
      final a = await SecureSession.create(
        await Ed25519().newKeyPair(),
        'Alice',
      );
      final b = await SecureSession.create(await Ed25519().newKeyPair(), 'Bob');
      expect(a.verificationQr(VerificationScope.direct), isNull);
      await a.acceptHello(b.hello);
      await b.acceptHello(a.hello);
      final aq = a.verificationQr(VerificationScope.direct)!,
          bq = b.verificationQr(VerificationScope.direct)!;
      expect(aq.session, bq.session);
      expect(aq.sender, bq.receiver);
      expect(aq.matchesRemote(bq.encode), isTrue);
      expect(bq.matchesRemote(aq.encode), isTrue);
      expect(aq.matchesRemote(aq.encode), isFalse);
      expect(
        aq.matchesRemote(b.verificationQr(VerificationScope.group)!.encode),
        isFalse,
      );
      expect(utf8.encode(aq.encode).length, lessThanOrEqualTo(512));
      expect(
        jsonDecode(aq.encode).keys,
        unorderedEquals(['type', 'v', 'mode', 'session', 'from', 'to']),
      );
      expect(
        aq.encode,
        isNot(
          contains(base64Encode(await a.identity.extractPrivateKeyBytes())),
        ),
      );
      expect(
        aq.encode,
        isNot(
          contains(base64Encode(await a.ephemeral.extractPrivateKeyBytes())),
        ),
      );
      for (final field in ['session', 'from', 'to']) {
        final changed = Map<String, dynamic>.from(jsonDecode(bq.encode) as Map)
          ..[field] = '4' * 64;
        expect(aq.matchesRemote(jsonEncode(changed)), isFalse);
      }
    },
  );
  test(
    'fresh handshakes with the same identities reject previous QR payloads',
    () async {
      final ia = await Ed25519().newKeyPair(),
          ib = await Ed25519().newKeyPair();
      final a = await SecureSession.create(ia, 'A'),
          b = await SecureSession.create(ib, 'B');
      await a.acceptHello(b.hello);
      await b.acceptHello(a.hello);
      final old = b.verificationQr(VerificationScope.direct)!.encode;
      final nextA = await SecureSession.create(ia, 'A'),
          nextB = await SecureSession.create(ib, 'B');
      await nextA.acceptHello(nextB.hello);
      await nextB.acceptHello(nextA.hello);
      expect(
        nextA.verificationQr(VerificationScope.direct)!.matchesRemote(old),
        isFalse,
      );
    },
  );
  test(
    'direct scan needs explicit local confirmation and both peers before messaging',
    () async {
      final p = await verificationPair();
      addTearDown(p.close);
      final ar = p.a.directVerification!, br = p.b.directVerification!;
      final before = p.ta.sent.length;
      for (final wrong in [
        ar.qr.encode,
        '{}',
        'https://example.com',
        VerificationQr(
          scope: VerificationScope.group,
          session: br.qr.session,
          sender: br.qr.sender,
          receiver: br.qr.receiver,
        ).encode,
      ]) {
        expect(await p.a.confirmVerification(ar, wrong), isFalse);
      }
      expect(p.ta.sent.length, before);
      expect(p.a.localVerified, isFalse);
      expect(await p.a.sendText('Not trusted yet'), isFalse);
      expect(await p.a.confirmVerification(ar, br.qr.encode), isTrue);
      await settle();
      expect(p.a.localVerified, isTrue);
      expect(p.a.ready, isFalse);
      expect(p.b.remoteVerified, isTrue);
      expect(p.b.localVerified, isFalse);
      expect(
        p.a.directVerification,
        isNotNull,
      ); // The other phone can scan back.
      expect(
        await p.b.confirmVerification(br, p.a.directVerification!.qr.encode),
        isTrue,
      );
      await settle();
      expect(p.a.ready, isTrue);
      expect(p.b.ready, isTrue);
      expect(await p.a.sendText('QR verified text'), isTrue);
      await settle();
      expect(p.b.messages.single.text, 'QR verified text');
      expect(p.a.messages.single.status, 'delivered');
      expect(p.a.directVerification, isNull);
      expect(await p.a.confirmVerification(ar, br.qr.encode), isFalse);
    },
  );
  test(
    'QR confirmation interoperates with a peer using manual confirmation',
    () async {
      final p = await verificationPair();
      addTearDown(p.close);
      expect(
        await p.a.confirmVerification(
          p.a.directVerification!,
          p.b.directVerification!.qr.encode,
        ),
        isTrue,
      );
      await p.b.confirmCode();
      await settle();
      expect(p.a.ready, isTrue);
      expect(p.b.ready, isTrue);
    },
  );
  test(
    'old requests and old scans cannot verify a reconnected direct session',
    () async {
      final p = await verificationPair();
      addTearDown(p.close);
      final old = p.a.directVerification!,
          raw = p.b.directVerification!.qr.encode;
      await p.a.disconnect();
      await settle();
      await p.a.connect(const Peer('B', 'Bob'));
      await settle();
      final next = p.a.directVerification!, remote = p.b.directVerification!;
      expect(next.qr.sender, old.qr.sender);
      expect(next.qr.session, isNot(old.qr.session));
      expect(await p.a.confirmVerification(old, raw), isFalse);
      expect(await p.a.confirmVerification(old, remote.qr.encode), isFalse);
      expect(await p.a.confirmVerification(next, raw), isFalse);
      expect(p.a.localVerified, isFalse);
      expect(await p.a.confirmVerification(next, remote.qr.encode), isTrue);
    },
  );
  test(
    'direct requests expire on lock and foreground loss even after returning',
    () async {
      final p = await verificationPair();
      addTearDown(p.close);
      var request = p.a.directVerification!;
      final raw = p.b.directVerification!.qr.encode;
      p.a.setAppAccess(false);
      expect(p.a.directVerification, isNull);
      p.a.setAppAccess(true);
      expect(await p.a.confirmVerification(request, raw), isFalse);
      request = p.a.directVerification!;
      p.a.setAppForeground(false);
      p.a.setAppForeground(true);
      expect(await p.a.confirmVerification(request, raw), isFalse);
      expect(
        await p.a.confirmVerification(p.a.directVerification!, raw),
        isTrue,
      );
    },
  );
  test(
    'changing the selected conversation invalidates the captured verification',
    () async {
      final p = await verificationPair();
      addTearDown(p.close);
      final request = p.a.directVerification!,
          raw = p.b.directVerification!.qr.encode;
      await p.a.store.savePeer('other', 'Other');
      await p.a.viewHistory(
        (await p.a.store.conversations()).firstWhere((v) => v.id == 'other'),
      );
      expect(p.a.directVerification, isNull);
      expect(await p.a.confirmVerification(request, raw), isFalse);
      expect(p.a.localVerified, isFalse);
    },
  );
  test(
    'queued direct confirmation rechecks privacy before emitting a verified frame',
    () async {
      final p = await verificationPair();
      // Queue a history load on the actual controller store.
      final actual = p.a.store as VerificationStore;
      addTearDown(p.close);
      final request = p.a.directVerification!,
          raw = p.b.directVerification!.qr.encode;
      await actual.savePeer('other', 'Other');
      actual.historyGate = Completer<void>();
      final opening = p.a.viewHistory(
        (await actual.conversations()).firstWhere((v) => v.id == 'other'),
      );
      await actual.entered.future;
      final confirming = p.a.confirmVerification(request, raw);
      p.a.setAppForeground(false);
      p.a.setAppForeground(true);
      actual.historyGate!.complete();
      await opening;
      expect(await confirming, isFalse);
      expect(p.a.localVerified, isFalse);
    },
  );
  test(
    'privacy loss during an in-flight confirmation closes that direct session',
    () async {
      final p = await verificationPair();
      addTearDown(p.close);
      final request = p.a.directVerification!,
          raw = p.b.directVerification!.qr.encode;
      p.ta.sendGate = Completer<void>();
      final confirming = p.a.confirmVerification(request, raw);
      await (p.ta as VerificationTransport).sendEntered.future;
      p.a.setAppAccess(false);
      p.ta.sendGate!.complete();
      await confirming;
      await settle();
      expect(p.a.localVerified, isFalse);
      expect(p.a.connectedPeer, isNull);
      expect(p.a.ready, isFalse);
      expect(p.b.ready, isFalse);
    },
  );
  test('verification timeout invalidates its QR request', () async {
    final p = await verificationPair(timeout: const Duration(seconds: 2));
    addTearDown(p.close);
    final request = p.a.directVerification!,
        raw = p.b.directVerification!.qr.encode;
    await Future<void>.delayed(const Duration(milliseconds: 2100));
    await settle();
    expect(p.a.verificationCurrent(request), isFalse);
    expect(await p.a.confirmVerification(request, raw), isFalse);
  });
  test(
    'group QR checks only admit after both ends confirm and preserve signed delivery',
    () async {
      final net = GroupNetwork();
      addTearDown(net.close);
      final h = await net.phone('Host'), g = await net.phone('Guest');
      await h.host('Room');
      await net.join(g, verify: false);
      final hr = h.verificationFor(h.links.keys.single)!,
          gr = g.verificationFor(g.links.keys.single)!;
      expect(
        await h.confirm(hr.linkId!, request: hr, scanned: hr.qr.encode),
        isFalse,
      );
      expect(
        await h.confirm(hr.linkId!, request: hr, scanned: gr.qr.encode),
        isTrue,
      );
      await net.settle();
      expect(h.links.values.single.localVerified, isTrue);
      expect(h.links.values.single.admitted, isFalse);
      expect(h.verificationFor(hr.linkId!), isNotNull);
      expect(
        await g.confirm(gr.linkId!, request: gr, scanned: hr.qr.encode),
        isTrue,
      );
      await net.settle();
      expect(h.members, hasLength(2));
      expect(g.connected, isTrue);
      expect(await g.sendText('Signed QR group text'), isTrue);
      await net.settle();
      expect(h.active!.messages.single.text, 'Signed QR group text');
      expect(g.active!.messages.single.receipts[h.selfId], 'received');
    },
  );
  test(
    'another pending group member cannot verify the selected link',
    () async {
      final net = GroupNetwork();
      addTearDown(net.close);
      final h = await net.phone('Host'),
          bob = await net.phone('Bob'),
          eve = await net.phone('Eve');
      await h.host('Room');
      await net.join(bob, verify: false);
      await net.join(eve, verify: false);
      final bl = h.links.values.firstWhere(
        (l) => l.session.peerId == bob.selfId,
      );
      final el = h.links.values.firstWhere(
        (l) => l.session.peerId == eve.selfId,
      );
      final request = h.verificationFor(bl.id)!;
      expect(
        await h.confirm(
          bl.id,
          request: request,
          scanned: eve.verificationFor(eve.links.keys.single)!.qr.encode,
        ),
        isFalse,
      );
      expect(bl.localVerified, isFalse);
      expect(el.localVerified, isFalse);
      expect(
        await h.confirm(
          el.id,
          request: request,
          scanned: bob.verificationFor(bob.links.keys.single)!.qr.encode,
        ),
        isFalse,
      );
      expect(
        await h.confirm(
          bl.id,
          request: request,
          scanned: bob.verificationFor(bob.links.keys.single)!.qr.encode,
        ),
        isTrue,
      );
    },
  );
  test(
    'rehosting a room rejects requests and QR payloads from its previous epoch',
    () async {
      final net = GroupNetwork();
      addTearDown(net.close);
      final h = await net.phone('Host'), g = await net.phone('Guest');
      await h.host('Room');
      await net.join(g, verify: false);
      final old = h.verificationFor(h.links.keys.single)!,
          raw = g.verificationFor(g.links.keys.single)!.qr.encode;
      final room = h.active!;
      await h.stop();
      await g.stop();
      await net.settle();
      await h.host('Room', previous: room);
      await net.join(g, verify: false);
      final next = h.verificationFor(h.links.keys.single)!;
      expect(h.verificationCurrent(old), isFalse);
      expect(await h.confirm(old.linkId!, request: old, scanned: raw), isFalse);
      expect(
        await h.confirm(next.linkId!, request: next, scanned: raw),
        isFalse,
      );
      expect(h.links.values.single.localVerified, isFalse);
    },
  );
  test(
    'group confirmation rechecks the interaction revision after a foreground return',
    () async {
      var revision = 0;
      final net = GroupNetwork();
      addTearDown(net.close);
      final h = await net.phone('Host', accessRevision: () => revision),
          g = await net.phone('Guest');
      await h.host('Room');
      await net.join(g, verify: false);
      final old = h.verificationFor(h.links.keys.single)!,
          raw = g.verificationFor(g.links.keys.single)!.qr.encode;
      revision += 2;
      expect(await h.confirm(old.linkId!, request: old, scanned: raw), isFalse);
      expect(await h.confirm(old.linkId!, scanned: raw), isTrue);
    },
  );
  test(
    'privacy loss during an in-flight group confirmation drops only that link',
    () async {
      var accessible = true;
      final net = GroupNetwork();
      addTearDown(net.close);
      final h = await net.phone('Host', canAct: () => accessible),
          g = await net.phone('Guest');
      await h.host('Room');
      await net.join(g, verify: false);
      final request = h.verificationFor(h.links.keys.single)!,
          raw = g.verificationFor(g.links.keys.single)!.qr.encode;
      final transport = h.transport as FakeGroupTransport;
      transport.gate = Completer<void>();
      transport.gateEntered = Completer<void>();
      final confirming = h.confirm(
        request.linkId!,
        request: request,
        scanned: raw,
      );
      await transport.gateEntered!.future;
      accessible = false;
      transport.gate!.complete();
      await confirming;
      await net.settle();
      expect(h.links, isEmpty);
      expect(g.connected, isFalse);
    },
  );
}
