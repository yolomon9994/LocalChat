import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/chat_backup.dart';
import 'package:local_chat/core/group_models.dart';
import 'package:local_chat/core/message_reply.dart';
import 'package:local_chat/core/models.dart';
import 'package:local_chat/core/secure_session.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'package:local_chat/services/chat_controller.dart';
import 'package:local_chat/services/draft_controller.dart';

import 'chat_controller_test.dart' show LinkedTransport, settle;
import 'group_draft_test.dart' show emptyGroup;
import 'group_test_support.dart';
import 'chat_backup_test.dart' show fastBackupKey;

const quote = MessageReply(
  id: 'original',
  outgoing: false,
  name: 'Alice',
  text: 'Original سلام 👋',
);

class ReplyStore extends DemoStore {
  bool _opened = false;
  @override
  Future<void> open() async {
    if (_opened) return;
    await super.open();
    _opened = true;
  }

  bool failState = false, failMessage = false;
  Completer<void>? messageGate, readGate;
  final readEntered = Completer<void>();
  @override
  Future<MessageReply?> draftReply(String id, {bool group = false}) async {
    if (readGate != null) {
      if (!readEntered.isCompleted) readEntered.complete();
      await readGate!.future;
    }
    return super.draftReply(id, group: group);
  }

  @override
  Future<void> saveDraftState(
    String id,
    String text,
    MessageReply? reply, {
    bool group = false,
  }) async {
    if (failState) throw StateError('Private storage detail');
    await super.saveDraftState(id, text, reply, group: group);
  }

  @override
  Future<void> saveOutgoingMessage(
    ChatMessage message, {
    bool clearDraft = false,
  }) async {
    await messageGate?.future;
    if (failMessage) throw StateError('Private message detail');
    await super.saveOutgoingMessage(message, clearDraft: clearDraft);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'reply previews bound UTF-8 without splitting Unicode and validate scope',
    () {
      final preview = MessageReply.preview('  ${'👋سلام' * 160}  ');
      expect(utf8.encode(preview).length, lessThanOrEqualTo(512));
      expect(preview, isNot(contains('\ufffd')));
      expect(MessageReply.parse(quote.toJson(), group: false), quote);
      expect(quote.reversed().outgoing, isTrue);
      for (final raw in [
        {...quote.toJson(), 'extra': 'unbound'},
        {...quote.toJson(), 'text': 'a' * 513},
        {...quote.toJson(), 'outgoing': 1},
        {...quote.toJson(), 'id': ''},
        {...quote.toJson(), 'name': ' '},
      ]) {
        expect(
          () => MessageReply.parse(raw, group: false),
          throwsFormatException,
        );
      }
      expect(
        () => MessageReply.parse(quote.toJson(), group: true),
        throwsFormatException,
      );
    },
  );

  test(
    'group signatures bind quote fields and reject insertion or removal',
    () async {
      final key = await Ed25519().newKeyPair();
      final public = base64Encode((await key.extractPublicKey()).bytes);
      final author = await identityId(public);
      final reference = MessageReply(
        id: randomId(),
        author: author,
        name: 'Alice',
        text: 'Older message',
      );
      Future<GroupText> create({MessageReply? reply}) => GroupText.create(
        key,
        'Bob',
        group: randomId(),
        host: public,
        epoch: randomId(),
        view: 1,
        text: 'Answer',
        targets: [author],
        reply: reply,
      );
      final m = await create(reply: reference);
      expect((await GroupText.parse(m.toJson())).reply, reference);
      for (final field in ['id', 'author', 'name', 'text']) {
        final changed = {
          ...reference.toJson(),
          field: field == 'author'
              ? 'f' * 64
              : field == 'id'
              ? randomId()
              : 'Modified',
        };
        await expectLater(
          GroupText.parse({
            ...m.toJson(),
            'envelope': {...m.envelope, 'reply': changed},
          }),
          throwsFormatException,
        );
      }
      final stripped = {...m.envelope}..remove('reply');
      await expectLater(
        GroupText.parse({...m.toJson(), 'envelope': stripped}),
        throwsFormatException,
      );
      final plain = await create();
      await expectLater(
        GroupText.parse({
          ...plain.toJson(),
          'envelope': {...plain.envelope, 'reply': reference.toJson()},
        }),
        throwsFormatException,
      );
    },
  );

  group('reply drafts and archives', () {
    late ReplyStore store;
    late DraftController drafts;
    setUp(() async {
      store = ReplyStore();
      await store.open();
      await store.savePeer('alice', 'Alice');
      drafts = DraftController(store);
      await drafts.load('alice');
    });
    tearDown(() => drafts.dispose());

    test('quote-only draft persists and cancel preserves typed text', () async {
      drafts.setReply('alice', quote);
      await drafts.settled;
      final restored = DraftController(store);
      addTearDown(restored.dispose);
      await restored.load('alice');
      expect(restored.replyFor('alice'), quote);
      expect(restored.textFor('alice'), '');
      restored.setText('alice', 'Answer');
      restored.setReply('alice', null);
      await restored.settled;
      expect(await store.draft('alice'), 'Answer');
      expect(await store.draftReply('alice'), isNull);
    });

    test(
      'failed quote save blocks backup and retries without losing state',
      () async {
        store.failState = true;
        drafts.setReply('alice', quote);
        drafts.setText('alice', 'Preserved answer');
        await drafts.settled;
        expect(drafts.errorFor('alice'), isNotNull);
        expect(drafts.replyFor('alice'), quote);
        await expectLater(drafts.exportBackup(), throwsFormatException);
        store.failState = false;
        await drafts.retry('alice');
        expect(await store.draftReply('alice'), quote);
        expect(await store.draft('alice'), 'Preserved answer');
        expect(drafts.errorFor('alice'), isNull);
      },
    );

    test(
      'atomic acceptance keeps a newer reply and text edited during a write',
      () async {
        drafts.setReply('alice', quote);
        drafts.setText('alice', 'First answer');
        await drafts.settled;
        store.messageGate = Completer<void>();
        final pending = drafts.acceptOutgoing(
          const ChatMessage(
            id: 'answer',
            peerId: 'alice',
            text: 'First answer',
            timestamp: 1,
            outgoing: true,
            status: 'queued',
            reply: quote,
          ),
          draftRevision: drafts.revisionFor('alice'),
          draftText: 'First answer',
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        const newer = MessageReply(
          id: 'new',
          outgoing: true,
          name: 'Me',
          text: 'New target',
        );
        drafts.setReply('alice', newer);
        drafts.setText('alice', 'Newer answer');
        store.messageGate!.complete();
        await pending;
        await drafts.settled;
        expect((await store.messages('alice')).single.reply, quote);
        expect(await store.draftReply('alice'), newer);
        expect(await store.draft('alice'), 'Newer answer');
      },
    );

    test(
      'v9 backup retains direct and group quotes and isolated quote-only drafts',
      () async {
        final group = await emptyGroup(store, id: randomId());
        final self = await identityId(group.host);
        final groupQuote = MessageReply(
          id: randomId(),
          author: self,
          name: 'Host',
          text: 'Group original',
        );
        final m = await GroupText.create(
          store.identity,
          'Host',
          group: group.id,
          host: group.host,
          epoch: randomId(),
          view: 1,
          text: 'Group answer',
          targets: [self],
          reply: groupQuote,
        );
        await store.saveGroupHistory(group.copy(messages: [m]));
        await store.saveMessage(
          const ChatMessage(
            id: 'answer',
            peerId: 'alice',
            text: 'Answer',
            timestamp: 1,
            outgoing: true,
            status: 'queued',
            reply: quote,
          ),
        );
        drafts.setReply('alice', quote);
        await drafts.load(group.id, group: true);
        drafts.setReply(group.id, groupQuote, group: true);
        await drafts.settled;
        final snapshot = await drafts.exportBackup();
        expect(snapshot.toJson()['version'], 9);
        final validated = await BackupData.parse(snapshot.toJson());
        final codec = BackupCodec(deriveKey: fastBackupKey);
        final encrypted = await codec.encrypt(
          validated,
          'a strong backup password',
        );
        final decrypted = await codec.decrypt(
          encrypted,
          'a strong backup password',
        );
        expect(decrypted.toJson(), validated.toJson());
        final destination = DemoStore();
        await destination.open();
        final destinationId = await identityId(
          base64Encode((await destination.identity.extractPublicKey()).bytes),
        );
        await destination.importBackup(validated);
        expect((await destination.messages('alice')).single.reply, quote);
        expect(
          (await destination.messages('alice')).single.status,
          'unconfirmed',
        );
        expect(await destination.draftReply('alice'), quote);
        expect(await destination.draftReply(group.id, group: true), groupQuote);
        expect(
          (await destination.groupHistories()).single.messages.single.reply,
          groupQuote,
        );
        expect(
          await identityId(
            base64Encode((await destination.identity.extractPublicKey()).bytes),
          ),
          destinationId,
        );
        await expectLater(
          BackupData.parse({...snapshot.toJson(), 'version': 8}),
          throwsFormatException,
        );
      },
    );

    test(
      'backup merging treats changed quotes as conflicts and preserves destination draft',
      () async {
        await store.saveMessage(
          const ChatMessage(
            id: 'answer',
            peerId: 'alice',
            text: 'Answer',
            timestamp: 1,
            outgoing: true,
            status: 'delivered',
            reply: quote,
          ),
        );
        drafts.setReply('alice', quote);
        await drafts.settled;
        final snapshot = await store.exportBackup();
        final incoming = await BackupData.parse({
          ...snapshot.toJson(),
          'messages': [
            {
              ...snapshot.messages.single,
              'reply': {...quote.toJson(), 'text': 'Changed'},
            },
          ],
          'drafts': [
            {
              ...snapshot.drafts.single,
              'reply': {...quote.toJson(), 'text': 'Changed'},
            },
          ],
        });
        final plan = planBackup(snapshot, incoming);
        expect(plan.conflicts, 1);
        expect(plan.keptDrafts, 1);
        await store.importBackup(incoming);
        expect((await store.messages('alice')).single.reply, quote);
        expect(await store.draftReply('alice'), quote);
      },
    );

    test(
      'accepting plain text cannot clear a selected quote that was not sent',
      () async {
        drafts.setReply('alice', quote);
        drafts.setText('alice', 'Plain answer');
        await drafts.settled;
        await drafts.acceptOutgoing(
          const ChatMessage(
            id: 'plain',
            peerId: 'alice',
            text: 'Plain answer',
            timestamp: 1,
            outgoing: true,
            status: 'queued',
          ),
          draftText: 'Plain answer',
          draftRevision: drafts.revisionFor('alice'),
        );
        expect(await store.draftReply('alice'), quote);
        expect(drafts.textFor('alice'), 'Plain answer');
      },
    );

    test(
      'deleting history removes quote drafts and cannot resurrect queued edits',
      () async {
        drafts.setReply('alice', quote);
        await drafts.deleteConversation('alice');
        await drafts.settled;
        expect(drafts.replyFor('alice'), isNull);
        expect(await store.draftReply('alice'), isNull);
        expect((await store.exportBackup()).drafts, isEmpty);
      },
    );
  });

  group('verified direct reply delivery', () {
    late ChatController a, b;
    late ReplyStore store;
    late LinkedTransport ta, tb;
    Future<void> connect() async {
      await a.connect(const Peer('B', 'Bob'));
      await settle();
      await a.confirmCode();
      await b.confirmCode();
      await settle();
    }

    setUp(() async {
      ta = LinkedTransport();
      tb = LinkedTransport();
      ta.other = tb;
      tb.other = ta;
      store = ReplyStore();
      a = ChatController(
        ta,
        store,
        ackTimeout: const Duration(milliseconds: 40),
      );
      b = ChatController(tb, ReplyStore());
      await a.initialize();
      await b.initialize();
      await connect();
      expect(await a.sendText('Original سلام 👋'), isTrue);
      await settle();
    });
    tearDown(() async {
      a.dispose();
      b.dispose();
      await ta.bus.close();
      await tb.bus.close();
    });

    test(
      'received and self-authored references reverse direction and clear only accepted draft',
      () async {
        final original = b.messages.single;
        expect(await b.replyTo(original), isTrue);
        b.drafts.setText(b.selectedPeer!, 'Answer');
        expect(await b.sendText('Answer'), isTrue);
        await settle();
        final received = a.messages.last;
        expect(received.reply!.id, original.id);
        expect(received.reply!.outgoing, isTrue);
        expect(received.reply!.text, original.text);
        expect(b.drafts.replyFor(b.selectedPeer!), isNull);
        expect(b.drafts.textFor(b.selectedPeer!), '');
        expect(await b.replyTo(b.messages.last), isTrue);
        expect(await b.sendText('Reply to my answer'), isTrue);
        await settle();
        expect(a.messages.last.reply!.outgoing, isFalse);
        expect(a.messages.last.reply!.text, 'Answer');
      },
    );

    test(
      'offline reply is retained for a legacy peer and plain text remains usable',
      () async {
        await a.disconnect();
        await settle();
        expect(await a.replyTo(a.messages.single), isTrue);
        a.drafts.setText(a.selectedPeer!, 'Queued answer');
        expect(await a.sendText('Queued answer', queueIfOffline: true), isTrue);
        b.dispose();
        b = ChatController(tb, b.store, supportsReplies: false);
        await b.initialize();
        await connect();
        expect(a.remoteSupportsReplies, isFalse);
        expect(a.messages.last.status, 'queued');
        expect(b.messages.where((m) => m.text == 'Queued answer'), isEmpty);
        expect(await a.cancelQueuedMessage(a.messages.last), isTrue);
        expect(await a.sendText('Plain text still works'), isTrue);
        await settle();
        expect(b.messages.last.text, 'Plain text still works');
      },
    );

    test(
      'retry retains original reply ID and metadata without duplicate unread',
      () async {
        expect(await a.replyTo(a.messages.single), isTrue);
        tb.dropAcks = true;
        expect(await a.sendText('Answer'), isTrue);
        await settle();
        final reply = a.messages.last;
        expect(reply.status, 'unconfirmed');
        final unread = b.conversations.single.unreadCount;
        tb.dropAcks = false;
        await a.disconnect();
        await settle();
        await connect();
        expect(await a.retryMessage(reply), isTrue);
        await settle();
        expect(a.messages.last.id, reply.id);
        expect(a.messages.last.reply, reply.reply);
        expect(b.messages.length, 2);
        expect(b.conversations.single.unreadCount, unread);
        expect(a.messages.last.status, 'delivered');
      },
    );

    test(
      'background and return while loading a draft reject an obsolete reply action',
      () async {
        store.readGate = Completer<void>();
        final pending = a.replyTo(a.messages.single);
        await store.readEntered.future;
        a.setAppForeground(false);
        a.setAppForeground(true);
        store.readGate!.complete();
        expect(await pending, isFalse);
        expect(a.drafts.replyFor(a.selectedPeer!), isNull);
      },
    );

    test(
      'failed message acceptance keeps both quote and answer for retry',
      () async {
        expect(await a.replyTo(a.messages.single), isTrue);
        final peer = a.selectedPeer!;
        a.drafts.setText(peer, 'Saved answer');
        await a.drafts.settled;
        store.failMessage = true;
        expect(await a.sendText('Saved answer'), isFalse);
        expect(a.drafts.replyFor(peer), isNotNull);
        expect(a.drafts.textFor(peer), 'Saved answer');
        store.failMessage = false;
        expect(await a.sendText('Saved answer'), isTrue);
        await settle();
        expect(a.drafts.replyFor(peer), isNull);
      },
    );
  });

  group('hosted group replies', () {
    late GroupNetwork net;
    setUp(() => net = GroupNetwork());
    tearDown(() => net.close());
    test(
      'a modified signed group quote closes only the bad link without persistence or relay',
      () async {
        final host = await net.phone('Host');
        final bob = await net.phone('Bob');
        final cara = await net.phone('Cara');
        await host.host('Room');
        await net.join(bob);
        await net.join(cara);
        final reference = MessageReply(
          id: randomId(),
          author: host.selfId!,
          name: 'Host',
          text: 'Quoted text',
        );
        final message = await GroupText.create(
          bob.store.identity,
          'Bob',
          group: host.active!.id,
          host: host.active!.host,
          epoch: host.epoch!,
          view: host.view,
          text: 'Answer',
          targets: host.members.map((m) => m.id).toList(),
          reply: reference,
        );
        final link = bob.links.values.single;
        final frame = await link.session.encrypt({
          'type': 'groupText',
          'message': {
            ...message.envelope,
            'reply': {...reference.toJson(), 'text': 'Tampered quote'},
          },
        });
        await bob.transport.send(link.id, jsonEncode(frame));
        await net.settle();
        expect(host.active!.messages, isEmpty);
        expect(cara.active!.messages, isEmpty);
        expect(host.members.any((m) => m.id == bob.selfId), isFalse);
        expect(cara.connected, isTrue);
        expect(await host.sendText('Still connected'), isTrue);
        await net.settle();
        expect(cara.active!.messages.single.text, 'Still connected');
      },
    );
    test(
      'signed replies relay to all members and quote authors outside the current roster',
      () async {
        final host = await net.phone('Host');
        final bob = await net.phone('Bob');
        final cara = await net.phone('Cara');
        await host.host('Room');
        await net.join(bob);
        await net.join(cara);
        expect(await bob.sendText('Original'), isTrue);
        await net.settle();
        final original = host.active!.messages.single;
        expect(await host.replyTo(host.active!.id, original), isTrue);
        final reference = host.drafts.replyFor(host.active!.id, group: true)!;
        expect(await host.sendText('Answer', reply: reference), isTrue);
        await net.settle();
        expect(cara.active!.messages.last.reply, reference);
        expect(bob.active!.messages.last.reply!.author, bob.selfId);
        expect(
          host.active!.messages.last.receipts.values.every(
            (s) => s == 'received',
          ),
          isTrue,
        );
        await bob.stop();
        await net.settle();
        expect(
          await host.sendText('Reply after author left', reply: reference),
          isTrue,
        );
        await net.settle();
        expect(cara.active!.messages.last.reply, reference);
      },
    );

    test(
      'one legacy member disables replies while preserving drafts and ordinary group text',
      () async {
        final host = await net.phone('Host');
        final old = await net.phone('Old', supportsReplies: false);
        await host.host('Room');
        await net.join(old);
        expect(await host.sendText('Original'), isTrue);
        await net.settle();
        expect(
          await host.replyTo(host.active!.id, host.active!.messages.single),
          isTrue,
        );
        final reference = host.drafts.replyFor(host.active!.id, group: true)!;
        expect(host.repliesAvailable, isFalse);
        expect(
          await host.sendText('Unsupported answer', reply: reference),
          isFalse,
        );
        expect(host.drafts.replyFor(host.active!.id, group: true), reference);
        expect(await host.sendText('Plain group text'), isTrue);
        await net.settle();
        expect(old.active!.messages.last.text, 'Plain group text');
      },
    );
  });
}
