import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/services/image_files_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Android image picker channel returns selected bytes or cancellation',
    () async {
      const channel = MethodChannel('dev.localchat/images');
      final calls = <MethodCall>[];
      final bytes = Uint8List.fromList([1, 2, 3]);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return calls.length == 1 ? bytes : null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      expect(await const AndroidImageFiles().pick(), bytes);
      expect(await const AndroidImageFiles().pick(), isNull);
      expect(calls.map((c) => c.method), ['pick', 'pick']);
    },
  );
}
