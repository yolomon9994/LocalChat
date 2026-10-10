import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/models.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'package:local_chat/demo/demo_transport.dart';
import 'package:local_chat/features/app_lock_screen.dart';
import 'package:local_chat/features/appearance_settings.dart';
import 'package:local_chat/features/chat_screen.dart';
import 'package:local_chat/features/home_screen.dart';
import 'package:local_chat/features/settings_screen.dart';
import 'package:local_chat/main.dart';
import 'package:local_chat/services/appearance_controller.dart';
import 'package:local_chat/services/chat_controller.dart';

import 'lock_test_support.dart';

class FailingAppearanceStorage extends MemoryAppearanceStorage {
  bool failRead = false;
  bool failWrite = false;
  @override
  Future<String?> read() async {
    if (failRead) throw StateError('Read failed');
    return super.read();
  }

  @override
  Future<void> write(String value) async {
    if (failWrite) throw StateError('Write failed');
    await super.write(value);
  }
}

double contrast(Color a, Color b) {
  final x = a.computeLuminance();
  final y = b.computeLuminance();
  return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
}

void main() {
  test(
    'Mode and palette persist together across controller restarts',
    () async {
      final storage = MemoryAppearanceStorage();
      final c = AppearanceController(storage);
      addTearDown(c.dispose);
      await c.initialize();
      expect(c.mode, ThemeMode.dark);
      expect(c.palette, AppPalette.mint);
      expect(await c.setMode(ThemeMode.system), isTrue);
      expect(await c.setPalette(AppPalette.purple), isTrue);
      final restored = AppearanceController(storage);
      addTearDown(restored.dispose);
      await restored.initialize();
      expect(restored.mode, ThemeMode.system);
      expect(restored.palette, AppPalette.purple);
      expect(await restored.setMode(ThemeMode.light), isTrue);
      final next = AppearanceController(storage);
      addTearDown(next.dispose);
      await next.initialize();
      expect(next.mode, ThemeMode.light);
      expect(next.palette, AppPalette.purple);
    },
  );

  test(
    'Unreadable or invalid preferences fall back and can be repaired',
    () async {
      for (final saved in [
        'not json',
        '{"version":2,"mode":"light","palette":"blue"}',
        '{"version":1,"mode":"light","palette":"unknown"}',
        null,
      ]) {
        final storage = FailingAppearanceStorage()
          ..value = saved
          ..failRead = saved == null;
        final c = AppearanceController(storage);
        addTearDown(c.dispose);
        await c.initialize();
        expect(c.loading, isFalse);
        expect(c.mode, ThemeMode.dark);
        expect(c.palette, AppPalette.mint);
        expect(c.error, isNotNull);
        storage.failRead = false;
        expect(await c.setMode(ThemeMode.light), isTrue);
        expect(c.error, isNull);
        final restored = AppearanceController(storage);
        addTearDown(restored.dispose);
        await restored.initialize();
        expect(restored.mode, ThemeMode.light);
        expect(restored.error, isNull);
      }
    },
  );

  test(
    'Failed writes preserve the applied and saved theme and allow retry',
    () async {
      final storage = FailingAppearanceStorage();
      final c = AppearanceController(storage);
      addTearDown(c.dispose);
      await c.initialize();
      await c.setPalette(AppPalette.blue);
      final saved = storage.value;
      storage.failWrite = true;
      expect(await c.setMode(ThemeMode.light), isFalse);
      expect(await c.setPalette(AppPalette.amber), isFalse);
      expect(c.mode, ThemeMode.dark);
      expect(c.palette, AppPalette.blue);
      expect(storage.value, saved);
      expect(c.saving, isFalse);
      expect(c.error, isNotNull);
      storage.failWrite = false;
      expect(await c.setMode(ThemeMode.light), isTrue);
      expect(c.error, isNull);
    },
  );

  testWidgets('System mode tracks device brightness; fixed modes override it', (
    tester,
  ) async {
    final c = ChatController(DemoTransport(), DemoStore(), isDemo: true);
    addTearDown(c.dispose);
    final appearance = AppearanceController(
      MemoryAppearanceStorage(),
      isDemo: true,
    );
    addTearDown(appearance.dispose);
    addTearDown(
      tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
    );
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.light;
    await tester.pumpWidget(
      LocalChatApp(controller: c, appearance: appearance),
    );
    await tester.pumpAndSettle();
    Brightness brightness() =>
        Theme.of(tester.element(find.byType(HomeScreen))).brightness;
    expect(brightness(), Brightness.dark);
    await appearance.setMode(ThemeMode.system);
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.light);
    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.dark;
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.dark);
    await appearance.setMode(ThemeMode.light);
    await tester.pumpAndSettle();
    expect(brightness(), Brightness.light);
  });

  testWidgets(
    'Settings applies themes without losing routes, edits or lock coverage',
    (tester) async {
      final c = ChatController(DemoTransport(), DemoStore(), isDemo: true);
      addTearDown(c.dispose);
      final appearance = AppearanceController(
        MemoryAppearanceStorage(),
        isDemo: true,
      );
      addTearDown(appearance.dispose);
      final lock = testLock();
      addTearDown(lock.dispose);
      await tester.pumpWidget(
        LocalChatApp(controller: c, appLock: lock, appearance: appearance),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nearby-destination')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      final nameField = find.byType(TextField).first;
      await tester.enterText(nameField, 'Unsaved name');
      final nameController = tester.widget<TextField>(nameField).controller!;
      final settingsScroll = find
          .descendant(
            of: find.descendant(
              of: find.byType(SettingsScreen),
              matching: find.byType(ListView),
            ),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('theme-mode')),
        150,
        scrollable: settingsScroll,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('theme-mode')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Light').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('palette-purple')),
        100,
        scrollable: settingsScroll,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('palette-purple')));
      await tester.pumpAndSettle();
      final expected = buildAppTheme(
        AppPalette.purple,
        Brightness.light,
      ).colorScheme;
      expect(appearance.mode, ThemeMode.light);
      expect(appearance.palette, AppPalette.purple);
      expect(
        Theme.of(tester.element(find.byType(SettingsScreen))).colorScheme,
        expected,
      );
      expect(nameController.text, 'Unsaved name');
      expect(find.textContaining('BROWSER DEMO'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );
      expect(
        Theme.of(tester.element(find.byType(HomeScreen))).colorScheme,
        expected,
      );
      await lock.enable('123456');
      lock.lifecycle(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsNothing);
      expect(
        Theme.of(tester.element(find.byType(AppLockScreen))).colorScheme,
        expected,
      );
      lock.lifecycle(AppLifecycleState.resumed);
      await lock.unlockPin('123456');
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      expect(
        Theme.of(tester.element(find.byType(HomeScreen))).colorScheme,
        expected,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Incoming and outgoing messages have readable contrast in every theme',
    (tester) async {
      final c = ChatController(DemoTransport(), DemoStore(), isDemo: true);
      addTearDown(c.dispose);
      c.selectedPeer = 'saved';
      c.selectedName = 'Friend';
      c.messages = [
        for (final outgoing in [false, true])
          ChatMessage(
            id: '$outgoing',
            peerId: 'saved',
            text: outgoing ? 'Outgoing' : 'Incoming',
            timestamp: 1,
            outgoing: outgoing,
            status: 'delivered',
          ),
      ];
      for (final palette in AppPalette.values) {
        for (final brightness in Brightness.values) {
          final theme = buildAppTheme(palette, brightness);
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: ChatScreen(controller: c),
            ),
          );
          await tester.pumpAndSettle();
          for (final message in ['Incoming', 'Outgoing']) {
            final finder = find.widgetWithText(SelectableText, message);
            final text = tester.widget<SelectableText>(finder);
            final bubble = tester.widget<Container>(
              find.ancestor(of: finder, matching: find.byType(Container)).first,
            );
            final background = (bubble.decoration! as BoxDecoration).color!;
            expect(
              contrast(text.style!.color!, background),
              greaterThanOrEqualTo(4.5),
              reason: '$palette $brightness $message',
            );
          }
          expect(
            contrast(
              theme.colorScheme.onPrimaryContainer,
              theme.colorScheme.primaryContainer,
            ),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrast(
              theme.colorScheme.onTertiaryContainer,
              theme.colorScheme.tertiaryContainer,
            ),
            greaterThanOrEqualTo(4.5),
          );
          expect(tester.takeException(), isNull);
        }
      }
    },
  );

  testWidgets('Appearance controls fit a small screen with enlarged text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final appearance = AppearanceController(
      MemoryAppearanceStorage(),
      isDemo: true,
    );
    addTearDown(appearance.dispose);
    await appearance.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 568),
            textScaler: TextScaler.linear(1.5),
          ),
          child: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(20),
              children: [AppearanceSettings(appearance: appearance)],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('palette-amber')),
      100,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('palette-amber')));
    await tester.pumpAndSettle();
    expect(appearance.palette, AppPalette.amber);
    expect(tester.takeException(), isNull);
  });
}
