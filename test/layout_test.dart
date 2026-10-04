import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/features/chat_screen.dart';
import 'package:local_chat/features/settings_screen.dart';
import 'package:local_chat/main.dart';
import 'package:local_chat/services/chat_controller.dart';
import 'chat_controller_test.dart' show LinkedTransport, MemoryStore;

class PreviewController extends ChatController {
  PreviewController() : super(LinkedTransport(), MemoryStore()) {
    loading = false;
    initialized = true;
    selectedPeer = 'preview';
    selectedName = 'Nearby friend';
  }
  @override
  String? get connectedPeer => 'preview';
  @override
  String? get code => 'a123 b456 c789 d012 e345';
}

void main() {
  testWidgets('Home and settings remain usable on a small screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final c = PreviewController();
    addTearDown(c.dispose);
    await tester.pumpWidget(LocalChatApp(controller: c));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Verification fits a small phone with enlarged text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final c = PreviewController();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 568),
            textScaler: TextScaler.linear(1.3),
          ),
          child: ChatScreen(controller: c),
        ),
      ),
    );
    expect(find.text('Codes match'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
