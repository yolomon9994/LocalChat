import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/services/group_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Android group methods preserve member link IDs and keep direct channels separate',
    () async {
      final calls = <MethodCall>[];
      const channel = MethodChannel('dev.localchat/groups');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final transport = WifiGroupTransport();
      await transport.host('Host', 'Friends');
      await transport.discover('Guest');
      await transport.join('address');
      await transport.send('epoch-7', 'sealed frame');
      await transport.closeLink('epoch-7');
      await transport.stop();
      expect(calls.map((c) => c.method), [
        'host',
        'discover',
        'join',
        'send',
        'close',
        'stop',
      ]);
      expect(calls.first.arguments, {'name': 'Host', 'title': 'Friends'});
      expect(calls[3].arguments, {'link': 'epoch-7', 'frame': 'sealed frame'});
      expect(calls[4].arguments, {'link': 'epoch-7'});
    },
  );
}
