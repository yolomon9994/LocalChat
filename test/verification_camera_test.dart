import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:local_chat/features/verification_camera.dart';

class FakeVerificationCamera extends MobileScannerPlatform {
  final captures = StreamController<BarcodeCapture?>.broadcast();
  final torch = StreamController<TorchState>.broadcast();
  final zoom = StreamController<double>.broadcast();
  int starts = 0, stops = 0, disposals = 0;
  bool denied = false;
  Completer<void>? permissionGate;
  StartOptions? options;
  @override
  Stream<BarcodeCapture?> get barcodesStream => captures.stream;
  @override
  Stream<TorchState> get torchStateStream => torch.stream;
  @override
  Stream<double> get zoomScaleStateStream => zoom.stream;
  @override
  Widget buildCameraView() =>
      const ColoredBox(color: Colors.black, child: Text('Camera preview'));
  @override
  Future<MobileScannerViewAttributes> start(StartOptions startOptions) async {
    starts++;
    options = startOptions;
    await permissionGate?.future;
    if (denied) {
      throw const MobileScannerException(
        errorCode: MobileScannerErrorCode.permissionDenied,
      );
    }
    return const MobileScannerViewAttributes(
      cameraDirection: CameraFacing.back,
      currentTorchMode: TorchState.off,
      size: Size(640, 480),
      numberOfCameras: 1,
    );
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }

  @override
  Future<void> updateScanWindow(Rect? window) async {}
}

void main() {
  late MobileScannerPlatform previous;
  late FakeVerificationCamera fake;
  setUp(() {
    previous = MobileScannerPlatform.instance;
    fake = FakeVerificationCamera();
    MobileScannerPlatform.instance = fake;
  });
  tearDown(() async {
    MobileScannerPlatform.instance = previous;
    await fake.captures.close();
    await fake.torch.close();
    await fake.zoom.close();
  });
  Future<void> settle(WidgetTester t) async {
    await t.pumpAndSettle();
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await t.pumpAndSettle();
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    await settle(t);
  }

  testWidgets(
    'camera starts only QR detection without returning frames and disposes on exit',
    (t) async {
      final values = <String>[];
      await t.pumpWidget(
        MaterialApp(
          home: SizedBox(
            height: 300,
            child: VerificationCamera(onDetected: values.add),
          ),
        ),
      );
      await settle(t);
      expect(fake.starts, 1);
      expect(fake.options!.formats, [BarcodeFormat.qrCode]);
      expect(fake.options!.returnImage, isFalse);
      fake.captures.add(
        const BarcodeCapture(
          barcodes: [
            Barcode(rawValue: 'scan value', format: BarcodeFormat.qrCode),
          ],
        ),
      );
      await settle(t);
      expect(values, ['scan value']);
      await close(t);
      expect(fake.stops, greaterThanOrEqualTo(1));
      expect(fake.disposals, 1);
      fake.captures.add(
        const BarcodeCapture(barcodes: [Barcode(rawValue: 'obsolete')]),
      );
      await settle(t);
      expect(values, ['scan value']);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets(
    'denied camera permission shows a generic manual fallback',
    (t) async {
      fake.denied = true;
      await t.pumpWidget(
        MaterialApp(home: VerificationCamera(onDetected: (_) {})),
      );
      await settle(t);
      expect(find.textContaining('Camera unavailable.'), findsOneWidget);
      expect(find.textContaining('compare the codes manually'), findsOneWidget);
      expect(t.takeException(), isNull);
      await close(t);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets(
    'pending permission after disposal is stopped before a replacement scanner starts',
    (t) async {
      fake.permissionGate = Completer<void>();
      final gate = fake.permissionGate!;
      await t.pumpWidget(
        MaterialApp(
          home: VerificationCamera(
            key: const ValueKey('old'),
            onDetected: (_) {},
          ),
        ),
      );
      await t.pump();
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await t.pump();
      expect(fake.starts, 1);
      await t.pumpWidget(
        MaterialApp(
          home: VerificationCamera(
            key: const ValueKey('next'),
            onDetected: (_) {},
          ),
        ),
      );
      await t.pump();
      expect(fake.starts, 1);
      fake.permissionGate = null;
      gate.complete();
      await settle(t);
      expect(fake.disposals, 1);
      expect(fake.starts, 2);
      expect(fake.stops, greaterThanOrEqualTo(1));
      await close(t);
      expect(fake.disposals, 2);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets(
    'inactive camera stops without automatically resuming an expired scan',
    (t) async {
      final values = <String>[];
      await t.pumpWidget(
        MaterialApp(home: VerificationCamera(onDetected: values.add)),
      );
      await settle(t);
      expect(fake.starts, 1);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await settle(t);
      expect(fake.stops, greaterThanOrEqualTo(1));
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      fake.captures.add(
        const BarcodeCapture(barcodes: [Barcode(rawValue: 'late')]),
      );
      await settle(t);
      expect(fake.starts, 1);
      expect(values, isEmpty);
      await close(t);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets(
    'scan stream errors stop the camera and keep exception details private',
    (t) async {
      await t.pumpWidget(
        MaterialApp(home: VerificationCamera(onDetected: (_) {})),
      );
      await settle(t);
      fake.captures.addError(StateError('Private native detail'));
      await settle(t);
      expect(find.textContaining('Camera unavailable.'), findsOneWidget);
      expect(find.textContaining('Private native detail'), findsNothing);
      expect(fake.stops, greaterThanOrEqualTo(1));
      await close(t);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
