import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/chat_backup.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'package:local_chat/demo/demo_transport.dart';
import 'package:local_chat/features/backup_screen.dart';
import 'package:local_chat/features/home_screen.dart';
import 'package:local_chat/main.dart';
import 'package:local_chat/services/backup_files.dart';
import 'package:local_chat/services/appearance_controller.dart';
import 'package:local_chat/services/chat_controller.dart';
import 'chat_backup_test.dart' show fastBackupKey, sampleBackup;
import 'lock_test_support.dart';

class MemoryBackupFiles implements BackupFiles {
  Uint8List? picked, saved;
  String? filename;
  Completer<Uint8List?>? waiting;
  @override
  Future<Uint8List?> pick() => waiting?.future ?? Future.value(picked);
  @override
  Future<bool> save(Uint8List bytes, String name) async {
    saved = bytes;
    filename = name;
    return true;
  }
}

Future<void> openBackups(
  WidgetTester tester,
  ChatController c,
  MemoryBackupFiles files,
  BackupCodec codec,
) async {
  Navigator.of(tester.element(find.byType(HomeScreen))).push(
    MaterialPageRoute<void>(
      builder: (_) => BackupScreen(controller: c, files: files, codec: codec),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tapBackup(WidgetTester tester, String label) async {
  final target = find.text(label);
  await tester.scrollUntilVisible(
    target,
    200,
    scrollable: find
        .descendant(
          of: find.byType(BackupScreen),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> enterPassword(
  WidgetTester tester,
  String password, {
  bool confirm = false,
}) async {
  final input = find.byKey(const ValueKey('backup-password'));
  await tester.scrollUntilVisible(
    input,
    -200,
    scrollable: find
        .descendant(
          of: find.byType(BackupScreen),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.enterText(input, password);
  if (confirm) {
    await tester.enterText(
      find.byKey(const ValueKey('backup-confirm')),
      password,
    );
  }
  tester.testTextInput.hide();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Export checks confirmation and saves encrypted data; import previews, cancels and deduplicates',
    (tester) async {
      final c = ChatController(DemoTransport(), DemoStore(), isDemo: true);
      addTearDown(c.dispose);
      final files = MemoryBackupFiles(),
          codec = BackupCodec(deriveKey: fastBackupKey);
      await c.initialize();
      final identity = (await c.store.exportBackup()).owner;
      await tester.pumpWidget(LocalChatApp(controller: c));
      await tester.pumpAndSettle();
      await openBackups(tester, c, files, codec);
      await enterPassword(tester, 'a long password');
      await tapBackup(tester, 'Export encrypted backup');
      expect(files.saved, isNull);
      expect(find.text('Backup passwords do not match.'), findsOneWidget);
      await enterPassword(tester, 'a long password', confirm: true);
      await tapBackup(tester, 'Export encrypted backup');
      expect(files.filename, endsWith('.lcbackup'));
      expect(
        (await codec.decrypt(files.saved!, 'a long password')).owner,
        identity,
      );
      files.picked = await codec.encrypt(
        await sampleBackup(),
        'a long password',
      );
      await tapBackup(tester, 'Choose backup file');
      await enterPassword(tester, 'a wrong password');
      await tapBackup(tester, 'Preview import');
      expect(await c.store.conversations(), isEmpty);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('backup-notice')),
        -200,
        scrollable: find
            .descendant(
              of: find.byType(BackupScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.textContaining('Check the password'), findsOneWidget);
      await enterPassword(tester, 'a long password');
      await tapBackup(tester, 'Preview import');
      expect(find.text('Import preview'), findsOneWidget);
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse,
      );
      await tapBackup(tester, 'Cancel import');
      expect(await c.store.conversations(), isEmpty);
      await tapBackup(tester, 'Choose backup file');
      await enterPassword(tester, 'a long password');
      await tapBackup(tester, 'Preview import');
      await tapBackup(tester, 'Import history');
      expect(c.conversations.single.id, 'alice');
      expect((await c.store.exportBackup()).owner, identity);
      expect(await c.store.draft('alice'), '  draft\n👋  ');
      await tapBackup(tester, 'Choose backup file');
      await enterPassword(tester, 'a long password');
      await tapBackup(tester, 'Preview import');
      expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile))
            .onChanged,
        isNull,
      );
      await tapBackup(tester, 'Import history');
      expect((await c.store.messages('alice')).length, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Identity import fits small screens and large text and requires explicit selection',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      // Exercise the phone layout with memory doubles for platform services.
      final c = ChatController(DemoTransport(), DemoStore());
      final lock = testLock();
      addTearDown(lock.dispose);
      final appearance = AppearanceController(MemoryAppearanceStorage());
      addTearDown(appearance.dispose);
      addTearDown(c.dispose);
      await c.initialize();
      final codec = BackupCodec(deriveKey: fastBackupKey),
          source = await sampleBackup();
      final files = MemoryBackupFiles()
        ..picked = await codec.encrypt(source, 'a long password');
      await tester.pumpWidget(
        LocalChatApp(controller: c, appLock: lock, appearance: appearance),
      );
      await tester.pumpAndSettle();
      await openBackups(tester, c, files, codec);
      await tapBackup(tester, 'Choose backup file');
      await enterPassword(tester, 'a long password');
      await tapBackup(tester, 'Preview import');
      await tapBackup(tester, 'Transfer messaging identity');
      await tapBackup(tester, 'Import and transfer identity');
      expect((await c.store.exportBackup()).owner, source.owner);
      expect(c.started, isFalse);
      expect(c.connectedPeer, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Locking a pending file picker clears passwords; encrypted selection survives unlock',
    (tester) async {
      final c = ChatController(DemoTransport(), DemoStore(), isDemo: true);
      addTearDown(c.dispose);
      final lock = testLock();
      addTearDown(lock.dispose);
      final codec = BackupCodec(deriveKey: fastBackupKey);
      final bytes = await codec.encrypt(
        await sampleBackup(),
        'a long password',
      );
      final files = MemoryBackupFiles()..waiting = Completer<Uint8List?>();
      await tester.pumpWidget(LocalChatApp(controller: c, appLock: lock));
      await tester.pumpAndSettle();
      await lock.enable('123456');
      await tester.pumpAndSettle();
      await openBackups(tester, c, files, codec);
      final choose = find.text('Choose backup file');
      await tester.scrollUntilVisible(
        choose,
        200,
        scrollable: find
            .descendant(
              of: find.byType(BackupScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(choose);
      await tester.pumpAndSettle();
      await tester.tap(choose);
      await tester.pump();
      lock.lock();
      await tester.pumpAndSettle();
      expect(find.byType(BackupScreen), findsNothing);
      files.waiting!.complete(bytes);
      await tester.pumpAndSettle();
      expect(c.pendingBackup, bytes);
      expect(c.conversations, isEmpty);
      await lock.unlockPin('123456');
      await tester.pumpAndSettle();
      await openBackups(tester, c, files, codec);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('backup-password')))
            .controller!
            .text,
        '',
      );
      await enterPassword(tester, 'a long password');
      await tapBackup(tester, 'Preview import');
      expect(find.text('Import preview'), findsOneWidget);
      lock.lock();
      await tester.pumpAndSettle();
      expect(find.text('Import preview'), findsNothing);
      expect(c.conversations, isEmpty);
      expect(c.pendingBackup, bytes);
    },
  );

  test(
    'Controller rejects a preview from an earlier unlock and refreshes draft/search state after import',
    () async {
      final c = ChatController(DemoTransport(), DemoStore(), isDemo: true);
      addTearDown(c.dispose);
      await c.initialize();
      final source = await sampleBackup(), token = c.accessRevision;
      c.setAppAccess(false);
      c.setAppAccess(true);
      await expectLater(
        c.restoreBackup(source, accessToken: token),
        throwsFormatException,
      );
      expect(c.conversations, isEmpty);
      await c.drafts.load('alice');
      final revision = c.historyRevision;
      await c.restoreBackup(source, accessToken: c.accessRevision);
      expect(c.historyRevision, greaterThan(revision));
      expect(c.drafts.textFor('alice'), '  draft\n👋  ');
      expect(c.conversations.single.unreadCount, 1);
      expect((await c.store.search('Secret')).messages.length, 1);
    },
  );

  test(
    'Android file channel carries only encrypted bytes and handles cancellation and limits',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel('dev.localchat/backup');
      final bytes = await BackupCodec(
        deriveKey: fastBackupKey,
      ).encrypt(await sampleBackup(), 'a long password');
      final native = AndroidBackupFiles();
      var cancel = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'pick') return cancel ? null : bytes;
            expect(call.method, 'save');
            expect((call.arguments as Map)['bytes'], bytes);
            expect((call.arguments as Map)['name'], 'backup.lcbackup');
            return !cancel;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      expect(await native.pick(), bytes);
      expect(await native.save(bytes, 'backup.lcbackup'), isTrue);
      cancel = true;
      expect(await native.pick(), isNull);
      expect(await native.save(bytes, 'backup.lcbackup'), isFalse);
      await expectLater(
        native.save(Uint8List(backupMaxFile + 1), 'too-large'),
        throwsFormatException,
      );
    },
  );
}
