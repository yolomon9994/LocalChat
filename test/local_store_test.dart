import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/local_store.dart';
import 'package:local_chat/core/models.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  if (Platform.isLinux) {
    open.overrideFor(
      OperatingSystem.linux,
      () => DynamicLibrary.open('libsqlite3.so.0'),
    );
  }
  databaseFactory = createDatabaseFactoryFfi(noIsolate: true);
  late LocalStore store;
  late String databasePath;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    databasePath = path.join(await getDatabasesPath(), 'localchat.db');
    await deleteDatabase(databasePath);
    store = LocalStore();
    await store.open();
    await store.savePeer('alice', 'Alice');
  });
  tearDown(() async {
    await store.close();
    await deleteDatabase(databasePath);
  });
  ChatMessage message({String peer = 'alice', bool outgoing = true}) =>
      ChatMessage(
        id: 'id-1',
        peerId: peer,
        text: 'Private text سلام 👋',
        timestamp: 1000,
        outgoing: outgoing,
        status: 'sending',
      );
  test(
    'SQLite contains ciphertext; reopening preserves identity, text and delivery uncertainty',
    () async {
      final identity = base64Encode(
        (await store.identity.extractPublicKey()).bytes,
      );
      await store.saveMessage(message());
      final db = await openDatabase(databasePath);
      final row = (await db.query('messages')).single;
      expect(row['body'], isNot(contains('Private text')));
      expect(base64Decode(row['body'] as String).length, greaterThan(40));
      await store.close();
      store = LocalStore();
      await store.open();
      expect(
        base64Encode((await store.identity.extractPublicKey()).bytes),
        identity,
      );
      expect(
        (await store.messages('alice')).single.text,
        'Private text سلام 👋',
      );
      expect((await store.messages('alice')).single.status, 'unconfirmed');
    },
  );
  test(
    'Message IDs are scoped by peer and direction; acknowledgements only affect outbound message',
    () async {
      await store.savePeer('bob', 'Bob');
      await store.saveMessage(message());
      await store.saveMessage(message(outgoing: false));
      await store.saveMessage(message(peer: 'bob'));
      await store.saveMessage(message(outgoing: false)); // Duplicate receive.
      await store.setStatus('id-1', 'alice', 'delivered');
      final alice = await store.messages('alice');
      expect(alice.length, 2);
      expect(alice.singleWhere((m) => m.outgoing).status, 'delivered');
      expect(alice.singleWhere((m) => !m.outgoing).status, 'sending');
      expect((await store.messages('bob')).single.status, 'sending');
    },
  );
  test('Modified stored ciphertext fails authentication', () async {
    await store.saveMessage(message());
    final db = await openDatabase(databasePath);
    final row = (await db.query('messages')).single;
    final bytes = base64Decode(row['body'] as String);
    bytes[24] ^= 1;
    await db.update('messages', {'body': base64Encode(bytes)});
    await expectLater(
      store.messages('alice'),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });
  test(
    'History deletion removes conversations and messages but keeps identity',
    () async {
      await store.saveMessage(message());
      final key = (await store.identity.extractPublicKey()).bytes;
      await store.clearHistory();
      expect(await store.conversations(), isEmpty);
      expect(await store.messages('alice'), isEmpty);
      expect((await store.identity.extractPublicKey()).bytes, key);
    },
  );
}
