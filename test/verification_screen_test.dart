import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:local_chat/core/session_verification.dart';
import 'package:local_chat/demo/demo_transport.dart';
import 'package:local_chat/features/chat_screen.dart';
import 'package:local_chat/features/group_screen.dart';
import 'package:local_chat/features/home_screen.dart';
import 'package:local_chat/features/verification_screen.dart';
import 'package:local_chat/main.dart';
import 'package:local_chat/services/chat_controller.dart';
import 'group_test_support.dart';
import 'lock_test_support.dart';
import 'message_reply_test.dart' show ReplyStore;
import 'session_verification_test.dart';

class ScanHarness {
  ValueChanged<String>? detect;
  int mounted = 0, disposed = 0;
  Widget build(BuildContext context, ValueChanged<String> callback) {
    detect = callback;
    return FakeScanView(onMount: () => mounted++, onDispose: () => disposed++);
  }
}

class FakeScanView extends StatefulWidget {
  const FakeScanView({
    super.key,
    required this.onMount,
    required this.onDispose,
  });
  final VoidCallback onMount, onDispose;
  @override
  State<FakeScanView> createState() => _FakeScanViewState();
}

class _FakeScanViewState extends State<FakeScanView> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('Simulated camera preview');
}

void main() {
  late VerificationPair p;
  late ScanHarness camera;
  setUp(() async {
    if (kIsWeb) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            SystemChannels.contextMenu,
            (_) async => null,
          );
      await BrowserContextMenu.disableContextMenu();
    }
    p = await verificationPair();
    camera = ScanHarness();
  });
  tearDown(() async {
    await p.close();
    if (kIsWeb) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.contextMenu, null);
    }
  });
  Future<void> settleUi(WidgetTester t) async {
    await t.pumpAndSettle();
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await t.pumpAndSettle();
  }

  Future<void> expectQrPixels(WidgetTester t, VerificationQr expected) async {
    final custom = t.widget<CustomPaint>(
      find.byWidgetPredicate((w) => w is CustomPaint && w.painter is QrPainter),
    );
    final actual = custom.painter! as QrPainter;
    final view = t.widget<QrImageView>(find.byType(QrImageView));
    final reference = QrPainter(
      data: expected.encode,
      version: QrVersions.auto,
      errorCorrectionLevel: view.errorCorrectionLevel,
      gapless: view.gapless,
      eyeStyle: view.eyeStyle,
      dataModuleStyle: view.dataModuleStyle,
    );
    Future<Uint8List> pixels(QrPainter painter) async {
      final picture = painter.toPicture(256);
      final image = await picture.toImage(256, 256);
      try {
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        return Uint8List.fromList(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
      } finally {
        image.dispose();
        picture.dispose();
      }
    }

    await t.runAsync(() async {
      expect(await pixels(actual), await pixels(reference));
    });
  }

  Future<void> actions(
    WidgetTester t, {
    VerificationRequest? request,
    bool dark = false,
  }) async {
    await t.pumpWidget(
      MaterialApp(
        theme: dark ? ThemeData.dark() : ThemeData.light(),
        home: Scaffold(
          body: VerificationActions(
            controller: p.a,
            request: request ?? p.a.directVerification!,
            scannerBuilder: camera.build,
          ),
        ),
      ),
    );
    await settleUi(t);
  }

  Future<void> openScan(WidgetTester t) async {
    await actions(t);
    await t.tap(find.text('Scan QR'));
    await settleUi(t);
  }

  testWidgets(
    'Show QR renders the current directional payload in black and white without a camera',
    (t) async {
      await actions(t, dark: true);
      await t.tap(find.text('Show QR'));
      await settleUi(t);
      final qr = t.widget<QrImageView>(find.byType(QrImageView));
      await expectQrPixels(t, p.a.directVerification!.qr);
      expect(qr.backgroundColor, Colors.white);
      expect(qr.eyeStyle.color, Colors.black);
      expect(qr.dataModuleStyle.color, Colors.black);
      expect(camera.mounted, 0);
      expect(
        find.textContaining('Both phones must confirm'),
        findsNothing,
      ); // Explicit demo label.
      expect(find.textContaining('connection is simulated'), findsOneWidget);
      await t.ensureVisible(find.text('Back to manual verification'));
      await t.tap(find.text('Back to manual verification'));
      await settleUi(t);
      expect(find.byType(VerificationScreen), findsNothing);
      expect(p.a.localVerified, isFalse);
    },
  );
  testWidgets(
    'matching scan pauses the camera but requires explicit verification and the other peer',
    (t) async {
      await openScan(t);
      expect(camera.mounted, 1);
      camera.detect!(p.b.directVerification!.qr.encode);
      await settleUi(t);
      expect(find.text('QR matches this connection.'), findsOneWidget);
      expect(camera.disposed, 1);
      expect(p.a.localVerified, isFalse);
      await t.tap(find.text('Verify connection'));
      await settleUi(t);
      expect(p.a.localVerified, isTrue);
      expect(p.a.ready, isFalse);
      expect(find.byType(VerificationScreen), findsNothing);
      expect(p.a.directVerification, isNotNull);
      await t.runAsync(() => p.b.confirmCode());
      await settleUi(t);
      expect(p.a.ready, isTrue);
    },
  );
  testWidgets(
    'own, unrelated and oversized QR values remain untrusted and can retry',
    (t) async {
      await openScan(t);
      for (final raw in [
        p.a.directVerification!.qr.encode,
        'https://example.com',
        'x' * 4096,
      ]) {
        camera.detect!(raw);
        await settleUi(t);
        expect(find.textContaining('This QR does not match'), findsOneWidget);
        expect(find.text('Verify connection'), findsNothing);
        expect(p.a.localVerified, isFalse);
      }
      camera.detect!(p.b.directVerification!.qr.encode);
      await settleUi(t);
      expect(find.text('Verify connection'), findsOneWidget);
    },
  );
  testWidgets(
    'switching from a matched scan to Show QR clears the captured scan',
    (t) async {
      await openScan(t);
      final oldDetect = camera.detect!;
      oldDetect(p.b.directVerification!.qr.encode);
      await settleUi(t);
      await t.tap(find.text('Show my QR'));
      await settleUi(t);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('Verify connection'), findsNothing);
      oldDetect(p.b.directVerification!.qr.encode);
      await settleUi(t);
      expect(find.text('Verify connection'), findsNothing);
      await t.tap(find.text('Scan other phone'));
      await settleUi(t);
      expect(camera.mounted, 2);
      expect(p.a.localVerified, isFalse);
    },
  );
  testWidgets(
    'background return closes the scanner and rejects a stale capture',
    (t) async {
      await openScan(t);
      final oldDetect = camera.detect!;
      final raw = p.b.directVerification!.qr.encode;
      p.a.setAppForeground(false);
      p.a.setAppForeground(true);
      await settleUi(t);
      expect(find.byType(VerificationScreen), findsNothing);
      expect(camera.disposed, 1);
      oldDetect(raw);
      await settleUi(t);
      expect(p.a.localVerified, isFalse);
    },
  );
  testWidgets(
    'a confirm callback captured before locking cannot trust after unlock',
    (t) async {
      await openScan(t);
      camera.detect!(p.b.directVerification!.qr.encode);
      await settleUi(t);
      final button = t.widget<FilledButton>(
        find.ancestor(
          of: find.text('Verify connection'),
          matching: find.byType(FilledButton),
        ),
      );
      p.a.setAppAccess(false);
      p.a.setAppAccess(true);
      await settleUi(t);
      button.onPressed!();
      await settleUi(t);
      expect(p.a.localVerified, isFalse);
      expect(find.byType(VerificationScreen), findsNothing);
    },
  );
  testWidgets(
    'direct verification screen retains manual controls and Show QR while waiting for peer',
    (t) async {
      await t.pumpWidget(MaterialApp(home: ChatScreen(controller: p.a)));
      await settleUi(t);
      await t.ensureVisible(find.text('Show QR'));
      await t.tap(find.text('Show QR'));
      await settleUi(t);
      expect(find.byType(QrImageView), findsOneWidget);
      await t.ensureVisible(find.text('Back to manual verification'));
      await t.tap(find.text('Back to manual verification'));
      await settleUi(t);
      await t.ensureVisible(find.text('Codes match'));
      await t.tap(find.text('Codes match'));
      await settleUi(t);
      expect(p.a.localVerified, isTrue);
      expect(find.text('Waiting for the other phone'), findsOneWidget);
      await t.ensureVisible(find.text('Show QR'));
      await t.tap(find.text('Show QR'));
      await settleUi(t);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(p.a.ready, isFalse);
    },
  );
  testWidgets(
    'PIN removes the displayed QR and invalidates its old Back callback',
    (t) async {
      final lock = testLock();
      addTearDown(lock.dispose);
      await t.pumpWidget(LocalChatApp(controller: p.a, appLock: lock));
      await settleUi(t);
      await t.runAsync(() => lock.enable('123456'));
      await settleUi(t);
      Navigator.of(t.element(find.byType(HomeScreen))).push(
        MaterialPageRoute<void>(builder: (_) => ChatScreen(controller: p.a)),
      );
      await settleUi(t);
      await t.ensureVisible(find.text('Show QR'));
      await t.tap(find.text('Show QR'));
      await settleUi(t);
      final oldBack = t
          .widget<TextButton>(
            find.ancestor(
              of: find.text('Back to manual verification'),
              matching: find.byType(TextButton),
            ),
          )
          .onPressed!;
      lock.lock();
      await settleUi(t);
      expect(find.text('LocalChat locked'), findsOneWidget);
      expect(find.byType(QrImageView), findsNothing);
      await t.runAsync(() => lock.unlockPin('123456'));
      await settleUi(t);
      oldBack();
      await settleUi(t);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(p.a.localVerified, isFalse);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'unsupported platform offers manual fallback without starting the scanner',
    (t) async {
      final request = p.a.directVerification!;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => VerificationScreen(
                      controller: p.a,
                      request: request,
                      scan: true,
                    ),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Open'));
      await settleUi(t);
      expect(
        find.textContaining('Camera scanning is available on Android'),
        findsOneWidget,
      );
      expect(camera.mounted, 0);
      expect(p.a.localVerified, isFalse);
      await t.tap(find.text('Show my QR'));
      await settleUi(t);
      expect(find.byType(QrImageView), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
  testWidgets(
    'QR display fits a small screen with enlarged text and manual return',
    (t) async {
      t.view.physicalSize = const Size(320, 568);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final request = p.a.directVerification!;
      await t.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.8)),
            child: child!,
          ),
          home: Scaffold(
            body: VerificationActions(
              controller: p.a,
              request: request,
              scannerBuilder: camera.build,
            ),
          ),
        ),
      );
      await t.tap(find.text('Show QR'));
      await settleUi(t);
      expect(t.takeException(), isNull);
      await t.ensureVisible(find.text('Back to manual verification'));
      await t.ensureVisible(find.text('Back to manual verification'));
      await t.tap(find.text('Back to manual verification'));
      await settleUi(t);
      expect(find.byType(VerificationScreen), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'group QR actions select exactly one pending member and close after explicit verification',
    (t) async {
      final net = GroupNetwork();
      final store = ReplyStore();
      final root = ChatController(
        DemoTransport(),
        store,
        isDemo: true,
        groupTransport: FakeGroupTransport(net),
      );
      late VerificationRequest request, remote;
      await t.runAsync(() async {
        await root.initialize();
        net.controllers.add(root.groups);
        await root.groups.host('Room');
        final guest = await net.phone('Guest');
        await net.join(guest, verify: false);
        request = root.groups.verificationFor(root.groups.links.keys.single)!;
        remote = guest.verificationFor(guest.links.keys.single)!;
      });
      try {
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: GroupVerification(controller: root),
              ),
            ),
          ),
        );
        await settleUi(t);
        await t.tap(find.text('Show QR'));
        await settleUi(t);
        await expectQrPixels(t, request.qr);
        await t.ensureVisible(find.text('Back to manual verification'));
        await t.tap(find.text('Back to manual verification'));
        await settleUi(t);
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: VerificationActions(
                controller: root,
                request: request,
                scannerBuilder: camera.build,
              ),
            ),
          ),
        );
        await t.tap(find.text('Scan QR'));
        await settleUi(t);
        camera.detect!(remote.qr.encode);
        await settleUi(t);
        expect(root.groups.links.values.single.localVerified, isFalse);
        await t.tap(find.text('Verify connection'));
        await settleUi(t);
        expect(root.groups.links.values.single.localVerified, isTrue);
        expect(root.groups.links.values.single.admitted, isFalse);
        expect(find.byType(VerificationScreen), findsNothing);
      } finally {
        await t.pumpWidget(const SizedBox.shrink());
        await t.runAsync(() async {
          await root.groups.stop();
          net.controllers.remove(root.groups);
          root.dispose();
          await net.close();
        });
      }
    },
  );
}
