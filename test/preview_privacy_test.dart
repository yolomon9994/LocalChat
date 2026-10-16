import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/services/preview_privacy.dart';
import 'package:local_chat/services/chat_notifications.dart';

class TestPreviewStorage extends MemoryPreviewPrivacyStorage {
  bool failRead = false, failWrite = false;
  Completer<void>? gate;
  @override
  Future<String?> read() async {
    if (failRead) throw StateError('private failure');
    return super.read();
  }

  @override
  Future<void> write(String value) async {
    await gate?.future;
    if (failWrite) throw StateError('private failure');
    await super.write(value);
  }
}

class TestPreviewNotifications extends MemoryNotificationPlatform {
  bool failConfigure = false;
  Completer<void>? gate, entered;
  final payloads = <({String? name, String? text})>[];
  @override
  Future<void> configure({
    required bool enabled,
    required bool previews,
    NotificationPreview? previewMode,
  }) async {
    entered?.complete();
    await gate?.future;
    if (failConfigure) throw StateError('private failure');
    await super.configure(
      enabled: enabled,
      previews: previews,
      previewMode: previewMode,
    );
  }

  @override
  Future<void> show(String peer, {String? name, String? text}) async {
    payloads.add((name: name, text: text));
    await super.show(peer, name: name, text: text);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'A rapid background/return redacts old previews and cannot replay a stale access grant',
    () async {
      final platform = TestPreviewNotifications();
      final n = ChatNotifications(platform);
      addTearDown(n.dispose);
      await n.initialize();
      await n.setEnabled(true);
      n.setAccessible(true);
      await n.setPreviewMode(NotificationPreview.message);
      await n.incoming('peer', 'Name', 'Secret', isReading: () => false);
      n.setAccessible(false);
      n.setAccessible(true);
      await n.refreshPermission();
      expect(platform.alerts['peer'], (name: null, text: null));
      n.setAccessible(true);
      n.setAccessible(false);
      await n.refreshPermission();
      expect(platform.accessible, isFalse);
    },
  );
  test(
    'Chat-list default preserves existing previews; hidden preference survives restart',
    () async {
      final storage = TestPreviewStorage(),
          p = PreviewPrivacy(TestPreviewStorage());
      expect(p.hidden, isTrue);
      await p.initialize();
      expect(p.hidden, isFalse);
      p.dispose();
      final saved = PreviewPrivacy(storage);
      addTearDown(saved.dispose);
      await saved.initialize();
      await saved.setHidden(true);
      expect(jsonDecode(storage.value!), {'v': 1, 'hidden': true});
      final restart = PreviewPrivacy(storage);
      addTearDown(restart.dispose);
      await restart.initialize();
      expect(restart.hidden, isTrue);
    },
  );
  test(
    'Unreadable and malformed chat preferences hide content and permit explicit repair',
    () async {
      for (final value in [
        'bad',
        '{}',
        '{"v":2,"hidden":false}',
        '{"v":1,"hidden":"false"}',
        '{"v":1,"hidden":false,"extra":1}',
      ]) {
        final storage = TestPreviewStorage()..value = value;
        final p = PreviewPrivacy(storage);
        await p.initialize();
        expect(p.hidden, isTrue);
        expect(p.error, isNotNull);
        expect(await p.setHidden(false), isTrue);
        expect(p.error, isNull);
        p.dispose();
      }
      final storage = TestPreviewStorage()..failRead = true;
      final p = PreviewPrivacy(storage);
      addTearDown(p.dispose);
      await p.initialize();
      expect(p.hidden, isTrue);
      expect(p.loading, isFalse);
    },
  );
  test(
    'Chat preference failures preserve applied value, serialize writes and tolerate disposal',
    () async {
      final storage = TestPreviewStorage();
      final p = PreviewPrivacy(storage);
      await p.initialize();
      await p.setHidden(true);
      storage.failWrite = true;
      expect(await p.setHidden(false), isFalse);
      expect(p.hidden, isTrue);
      expect(p.error, isNotNull);
      storage.failWrite = false;
      storage.gate = Completer<void>();
      final pending = p.setHidden(false);
      expect(await p.setHidden(true), isFalse);
      p.dispose();
      storage.gate!.complete();
      expect(await pending, isTrue);
      expect(p.hidden, isTrue);
    },
  );
  test(
    'Legacy notification booleans migrate; unknown explicit modes stay hidden',
    () {
      expect(
        NotificationPreview.parse({'previews': true}),
        NotificationPreview.message,
      );
      expect(
        NotificationPreview.parse({'previews': false}),
        NotificationPreview.hidden,
      );
      expect(
        NotificationPreview.parse({'previews': true, 'previewMode': 'sender'}),
        NotificationPreview.sender,
      );
      for (final bad in [null, 3, 'unknown']) {
        expect(
          NotificationPreview.parse({'previews': true, 'previewMode': bad}),
          NotificationPreview.hidden,
        );
      }
    },
  );
  test(
    'All three modes gate the raw notification payload and background always omits both fields',
    () async {
      final platform = TestPreviewNotifications();
      final c = ChatNotifications(platform);
      addTearDown(c.dispose);
      await c.initialize();
      await c.setEnabled(true);
      c.setAccessible(true);
      for (final mode in NotificationPreview.values) {
        await c.setPreviewMode(mode);
        await c.incoming(
          'peer',
          'Private name',
          'Private body',
          isReading: () => false,
        );
        expect(platform.payloads.last, (
          name: mode == NotificationPreview.hidden ? null : 'Private name',
          text: mode == NotificationPreview.message ? 'Private body' : null,
        ));
        c.setAccessible(false);
        await c.incoming(
          'peer',
          'Private name',
          'Private body',
          isReading: () => false,
        );
        expect(platform.payloads.last, (name: null, text: null));
        c.setAccessible(true);
      }
    },
  );
  test(
    'Mode changes redact current alerts, preserve routing and never reconstruct old plaintext',
    () async {
      final platform = TestPreviewNotifications();
      final n = ChatNotifications(platform);
      addTearDown(n.dispose);
      await n.initialize();
      await n.setEnabled(true);
      n.setAccessible(true);
      await n.setPreviewMode(NotificationPreview.message);
      await n.incoming('peer', 'Name', 'Secret', isReading: () => false);
      await n.setPreviewMode(NotificationPreview.sender);
      expect(platform.alerts['peer'], (name: null, text: null));
      await n.incoming('peer', 'Name', 'Secret', isReading: () => false);
      expect(platform.alerts['peer'], (name: 'Name', text: null));
      expect(
        platform.previews,
        isFalse,
      ); // Safe legacy fallback for sender-only.
      final restoredPlatform = MemoryNotificationPlatform()
        ..enabled = platform.enabled
        ..previews = platform.previews
        ..savedPreviewMode = platform.savedPreviewMode;
      final restarted = ChatNotifications(restoredPlatform);
      await restarted.initialize();
      expect(restarted.previewMode, NotificationPreview.sender);
      restarted.dispose();
      expect((await platform.settings())['previewMode'], 'sender');
    },
  );
  test(
    'Failed or pending restrictive changes cannot emit a body and block overlapping settings',
    () async {
      final platform = TestPreviewNotifications();
      final n = ChatNotifications(platform);
      addTearDown(n.dispose);
      await n.initialize();
      await n.setEnabled(true);
      n.setAccessible(true);
      await n.setPreviewMode(NotificationPreview.message);
      await n.incoming('peer', 'Name', 'Secret', isReading: () => false);
      platform.gate = Completer<void>();
      platform.entered = Completer<void>();
      platform.failConfigure = true;
      final setting = n.setPreviewMode(NotificationPreview.sender);
      await platform.entered!.future;
      await n.setPreviewMode(
        NotificationPreview.message,
      ); // Busy: cannot weaken the pending choice.
      final incoming = n.incoming(
        'peer',
        'Name',
        'Secret',
        isReading: () => false,
      );
      platform.gate!.complete();
      await setting;
      await incoming;
      expect(n.previewMode, NotificationPreview.message);
      expect(n.error, isNotNull);
      expect(platform.payloads.last.text, isNull);
      expect(platform.alerts['peer'], (name: null, text: null));
      platform.gate = null;
      platform.entered = null;
      platform.failConfigure = false;
      await n.setPreviewMode(NotificationPreview.sender);
      expect(n.error, isNull);
      await n.incoming('peer', 'Name', 'Secret', isReading: () => false);
      expect(platform.alerts['peer'], (name: 'Name', text: null));
    },
  );
  test(
    'Android bridge persists the explicit mode and never sends a sender-only body',
    () async {
      const channel = MethodChannel('dev.localchat/notifications');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'settings') {
          return {'enabled': true, 'previewMode': 'sender', 'allowed': true};
        }
        return null;
      });
      final n = ChatNotifications(AndroidNotificationPlatform());
      addTearDown(n.dispose);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await n.initialize();
      n.setAccessible(true);
      await n.setPreviewMode(NotificationPreview.sender);
      await n.incoming('peer', 'Name', 'Secret', isReading: () => false);
      expect(calls.lastWhere((c) => c.method == 'configure').arguments, {
        'enabled': true,
        'previews': false,
        'previewMode': 'sender',
      });
      expect(calls.lastWhere((c) => c.method == 'show').arguments, {
        'peer': 'peer',
        'name': 'Name',
        'text': null,
      });
    },
  );
}
