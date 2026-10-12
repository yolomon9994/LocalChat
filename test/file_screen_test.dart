import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/chat_file.dart';
import 'package:local_chat/core/models.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'package:local_chat/demo/demo_transport.dart';
import 'package:local_chat/features/chat_screen.dart';
import 'package:local_chat/features/chat_file_bubble.dart';
import 'package:local_chat/features/app_lock_screen.dart';
import 'package:local_chat/main.dart';
import 'package:local_chat/services/chat_controller.dart';
import 'package:local_chat/services/appearance_controller.dart';
import 'package:local_chat/services/chat_notifications.dart';
import 'package:local_chat/services/chat_files_base.dart';
import 'lock_test_support.dart';

class FixedPicker implements ChatFiles {
  FixedPicker(this.bytes);
  final Uint8List bytes;
  @override
  Future<SelectedFile?> pick() async => SelectedFile('report.pdf', bytes);
  @override
  Future<bool> save(Uint8List bytes, String name) async => true;
}

void main() {
  testWidgets(
    'small phone and enlarged text can review and discard a file without sending',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      late ChatController c;
      await tester.runAsync(() async {
        final bytes = Uint8List.fromList([1, 2, 3, 4]);
        c = ChatController(
          DemoTransport(),
          DemoStore(),
          isDemo: true,
          chatFiles: FixedPicker(bytes),
        );
        await c.initialize();
        await c.start();
        await c.connect(const Peer('demo-ava', 'Ava'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await c.confirmCode();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 568),
              textScaler: TextScaler.linear(1.8),
            ),
            child: ChatScreen(controller: c),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Attach file'));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      expect(find.text('Send file?'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Discard'),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(c.pendingFilePeer, isNull);
      expect(c.messages.where((m) => m.file != null), isEmpty);
    },
  );
  testWidgets(
    'offline file save needs confirmation and app lock removes its dialog',
    (tester) async {
      late ChatController c;
      final lock = testLock();
      final appearance = AppearanceController(MemoryAppearanceStorage());
      await tester.runAsync(() async {
        final store = DemoStore();
        await store.open();
        await store.savePeer('peer', 'Nearby friend');
        final bytes = Uint8List.fromList([1, 2, 3, 4]);
        await store.saveFileMessage(
          ChatMessage(
            id: 'file',
            peerId: 'peer',
            text: 'File',
            timestamp: 1,
            outgoing: false,
            status: 'received',
            file: await ChatFile.fromBytes('report.pdf', bytes),
          ),
          bytes,
        );
        c = ChatController(
          DemoTransport(),
          store,
          isDemo: true,
          notifications: ChatNotifications(
            MemoryNotificationPlatform()..launchPeer = 'peer',
            isDemo: true,
          ),
        );
        await c.initialize();
        await lock.initialize();
        await lock.enable('123456');
      });
      addTearDown(c.dispose);
      addTearDown(lock.dispose);
      addTearDown(appearance.dispose);
      await tester.pumpWidget(
        LocalChatApp(controller: c, appLock: lock, appearance: appearance),
      );
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'App PIN'),
        '123456',
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Unlock'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(() async {
          await tester.pump(const Duration(milliseconds: 100));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
      }
      await tester.pumpAndSettle();
      expect(find.byType(ChatFileBubble), findsOneWidget);
      await tester.tap(find.text('Save to phone'));
      await tester.pumpAndSettle();
      expect(find.text('Save file to phone?'), findsOneWidget);
      expect(find.textContaining('outside LocalChat'), findsOneWidget);
      lock.lock();
      await tester.pumpAndSettle();
      expect(find.byType(AppLockScreen), findsOneWidget);
      expect(find.text('Save file to phone?'), findsNothing);
      expect(find.byType(ChatFileBubble), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
