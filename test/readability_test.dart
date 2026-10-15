import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/models.dart';
import 'package:local_chat/core/message_reply.dart';
import 'package:local_chat/demo/demo_store.dart';
import 'package:local_chat/demo/demo_transport.dart';
import 'package:local_chat/features/app_lock_screen.dart';
import 'package:local_chat/features/appearance_settings.dart';
import 'package:local_chat/features/chat_screen.dart';
import 'package:local_chat/features/group_screen.dart';
import 'package:local_chat/features/home_screen.dart';
import 'package:local_chat/features/settings_screen.dart';
import 'package:local_chat/features/message_reply_card.dart';
import 'package:local_chat/features/message_bubble_content.dart';
import 'package:local_chat/main.dart';
import 'package:local_chat/services/appearance_controller.dart';
import 'package:local_chat/services/chat_controller.dart';
import 'appearance_test.dart' show FailingAppearanceStorage, contrast;
import 'group_draft_test.dart' show emptyGroup;
import 'group_search_test.dart' show searchText;
import 'lock_test_support.dart';
import 'message_reply_test.dart' show ReplyStore;

class PendingAppearanceStorage extends FailingAppearanceStorage {
  Completer<void>? gate;
  int writes = 0;
  @override
  Future<void> write(String value) async {
    writes++;
    await gate?.future;
    await super.write(value);
  }
}

class NonlinearTestScaler extends TextScaler {
  const NonlinearTestScaler();
  @override
  double scale(double size) => size * (size < 20 ? 1.8 : 1.2);
  @override
  double get textScaleFactor => 1.8;
}

void main() {
  test(
    'v1 preferences migrate without losing theme and all four choices persist',
    () async {
      final storage = MemoryAppearanceStorage()
        ..value = '{"version":1,"mode":"system","palette":"purple"}';
      final c = AppearanceController(storage);
      addTearDown(c.dispose);
      await c.initialize();
      expect(c.mode, ThemeMode.system);
      expect(c.palette, AppPalette.purple);
      expect(c.textSize, AppTextSize.system);
      expect(c.highContrast, isFalse);
      expect(c.error, isNull);
      await c.setTextSize(AppTextSize.largest);
      await c.setHighContrast(true);
      await c.setPalette(AppPalette.amber);
      await c.setMode(ThemeMode.light);
      expect((jsonDecode(storage.value!) as Map)['version'], 2);
      final next = AppearanceController(storage);
      addTearDown(next.dispose);
      await next.initialize();
      expect(next.mode, ThemeMode.light);
      expect(next.palette, AppPalette.amber);
      expect(next.textSize, AppTextSize.largest);
      expect(next.highContrast, isTrue);
      await next.setTextSize(AppTextSize.system);
      expect(next.highContrast, isTrue);
      expect(next.mode, ThemeMode.light);
      expect(next.palette, AppPalette.amber);
    },
  );

  test(
    'invalid v2 readability fields reject the whole record and allow repair',
    () async {
      for (final fields in [
        <String, dynamic>{},
        {'textSize': 'unknown', 'highContrast': true},
        {'textSize': 'largest', 'highContrast': 'true'},
        {'textSize': 1.3, 'highContrast': true},
        {'textSize': 'larger', 'highContrast': null},
      ]) {
        final storage = MemoryAppearanceStorage()
          ..value = jsonEncode({
            'version': 2,
            'mode': 'light',
            'palette': 'blue',
            ...fields,
          });
        final c = AppearanceController(storage);
        addTearDown(c.dispose);
        await c.initialize();
        expect(c.error, isNotNull);
        expect(c.mode, ThemeMode.dark);
        expect(c.palette, AppPalette.mint);
        expect(c.textSize, AppTextSize.system);
        expect(c.highContrast, isFalse);
        expect(await c.setHighContrast(true), isTrue);
        final next = AppearanceController(storage);
        addTearDown(next.dispose);
        await next.initialize();
        expect(next.error, isNull);
        expect(next.highContrast, isTrue);
      }
    },
  );

  test(
    'failed and overlapping writes preserve all applied and saved preferences',
    () async {
      final storage = PendingAppearanceStorage();
      final c = AppearanceController(storage);
      addTearDown(c.dispose);
      await c.initialize();
      await c.setPalette(AppPalette.blue);
      await c.setTextSize(AppTextSize.larger);
      final saved = storage.value;
      storage.failWrite = true;
      expect(await c.setTextSize(AppTextSize.largest), isFalse);
      expect(await c.setHighContrast(true), isFalse);
      expect(c.textSize, AppTextSize.larger);
      expect(c.highContrast, isFalse);
      expect(storage.value, saved);
      storage.failWrite = false;
      storage.gate = Completer<void>();
      final saving = c.setHighContrast(true);
      expect(c.saving, isTrue);
      final writes = storage.writes;
      expect(await c.setTextSize(AppTextSize.largest), isFalse);
      expect(storage.writes, writes);
      storage.gate!.complete();
      expect(await saving, isTrue);
      expect(c.palette, AppPalette.blue);
      expect(c.textSize, AppTextSize.larger);
      expect(c.highContrast, isTrue);
      expect(c.error, isNull);
    },
  );

  test(
    'text presets preserve nonlinear device scaling without reducing or capping it',
    () {
      const system = NonlinearTestScaler();
      expect(AppTextSize.system.applyTo(system), same(system));
      for (final size in AppTextSize.values) {
        final scaler = size.applyTo(system);
        for (final font in [12.0, 18.0, 36.0]) {
          expect(
            scaler.scale(font),
            closeTo(system.scale(font) * size.multiplier, .00001),
          );
          expect(scaler.scale(font), greaterThanOrEqualTo(system.scale(font)));
        }
        expect(scaler, size.applyTo(system));
        expect(
          size.applyTo(const TextScaler.linear(3)).scale(14),
          closeTo(42 * size.multiplier, .00001),
        );
      }
    },
  );

  late ReplyStore store;
  late ChatController c;
  late AppearanceController appearance;
  setUp(() async {
    if (kIsWeb) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            SystemChannels.contextMenu,
            (_) async => null,
          );
      await BrowserContextMenu.disableContextMenu();
    }
    store = ReplyStore();
    c = ChatController(DemoTransport(), store);
    await c.initialize();
    appearance = AppearanceController(MemoryAppearanceStorage());
    await appearance.initialize();
  });
  tearDown(() {
    c.dispose();
    appearance.dispose();
    if (kIsWeb) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.contextMenu, null);
    }
  });

  void deviceText(WidgetTester t, double scale) {
    t.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  }

  Future<void> visibleTap(WidgetTester t, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      final settings = find.descendant(
        of: find.byType(SettingsScreen),
        matching: find.byType(Scrollable),
      );
      await t.scrollUntilVisible(
        finder,
        200,
        scrollable: settings.evaluate().isNotEmpty
            ? settings.first
            : find.byType(Scrollable).first,
      );
    }
    await t.ensureVisible(finder);
    await t.pumpAndSettle();
    expect(finder.hitTestable(), findsOneWidget);
    await t.tap(finder);
    await t.pumpAndSettle();
  }

  testWidgets(
    'settings changes retain route, profile edit, tab and lock readability',
    (t) async {
      deviceText(t, 1.4);
      final lock = testLock();
      addTearDown(lock.dispose);
      await t.pumpWidget(
        LocalChatApp(controller: c, appLock: lock, appearance: appearance),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('nearby-destination')));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Settings'));
      await t.pumpAndSettle();
      final name = t
          .widget<TextField>(find.byType(TextField).first)
          .controller!;
      name.text = 'Unsaved profile';
      await visibleTap(t, find.byKey(const ValueKey('appearance-text-size')));
      await t.tap(find.text(AppTextSize.largest.label).last);
      await t.pumpAndSettle();
      await visibleTap(
        t,
        find.byKey(const ValueKey('appearance-high-contrast')),
      );
      final settings = t.element(find.byType(SettingsScreen));
      expect(
        MediaQuery.textScalerOf(settings).scale(14),
        closeTo(14 * 1.4 * 1.3, .0001),
      );
      expect(MediaQuery.highContrastOf(settings), isTrue);
      expect(
        Theme.of(settings).colorScheme,
        buildAppTheme(
          AppPalette.mint,
          Brightness.dark,
          highContrast: true,
        ).colorScheme,
      );
      expect(name.text, 'Unsaved profile');
      await t.pageBack();
      await t.pumpAndSettle();
      expect(
        t.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );
      await t.runAsync(() => lock.enable('123456'));
      lock.lock();
      await t.pumpAndSettle();
      expect(find.byType(HomeScreen), findsNothing);
      final locked = t.element(find.byType(AppLockScreen));
      expect(MediaQuery.textScalerOf(locked).scale(14), closeTo(25.48, .0001));
      expect(MediaQuery.highContrastOf(locked), isTrue);
      await t.runAsync(() => lock.unlockPin('123456'));
      await t.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      await appearance.setTextSize(AppTextSize.system);
      await t.pumpAndSettle();
      expect(
        MediaQuery.textScalerOf(t.element(find.byType(HomeScreen))).scale(14),
        closeTo(19.6, .0001),
      );
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'device high contrast follows brightness and cannot be disabled by the app switch',
    (t) async {
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      addTearDown(t.platformDispatcher.clearPlatformBrightnessTestValue);
      final lock = testLock();
      addTearDown(lock.dispose);
      await appearance.setMode(ThemeMode.system);
      await appearance.setPalette(AppPalette.purple);
      await t.pumpWidget(
        LocalChatApp(controller: c, appLock: lock, appearance: appearance),
      );
      await t.pumpAndSettle();
      for (final brightness in Brightness.values) {
        t.platformDispatcher.platformBrightnessTestValue = brightness;
        t.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(highContrast: true);
        await t.pumpAndSettle();
        final context = t.element(find.byType(HomeScreen));
        expect(appearance.highContrast, isFalse);
        expect(MediaQuery.highContrastOf(context), isTrue);
        expect(
          Theme.of(context).colorScheme,
          buildAppTheme(
            AppPalette.purple,
            brightness,
            highContrast: true,
          ).colorScheme,
        );
      }
      t.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures();
      await t.pumpAndSettle();
      final context = t.element(find.byType(HomeScreen));
      expect(MediaQuery.highContrastOf(context), isFalse);
      expect(
        Theme.of(context).colorScheme,
        buildAppTheme(AppPalette.purple, Brightness.light).colorScheme,
      );
    },
  );

  testWidgets('all enhanced palettes strengthen text and control contrast', (
    t,
  ) async {
    for (final palette in AppPalette.values) {
      for (final brightness in Brightness.values) {
        final base = buildAppTheme(palette, brightness).colorScheme;
        final enhanced = buildAppTheme(
          palette,
          brightness,
          highContrast: true,
        ).colorScheme;
        expect(enhanced, isNot(base));
        for (final pair in [
          (enhanced.onSurface, enhanced.surface),
          (enhanced.onSurface, enhanced.surfaceContainerHigh),
          (enhanced.onSurface, enhanced.surfaceContainerHighest),
          (enhanced.onSurfaceVariant, enhanced.surfaceContainer),
          (enhanced.onPrimary, enhanced.primary),
          (enhanced.onPrimaryContainer, enhanced.primaryContainer),
          (enhanced.onTertiaryContainer, enhanced.tertiaryContainer),
          (enhanced.error, enhanced.surface),
          (enhanced.onErrorContainer, enhanced.errorContainer),
        ]) {
          expect(
            contrast(pair.$1, pair.$2),
            greaterThanOrEqualTo(7),
            reason: '$palette $brightness $pair',
          );
        }
        expect(
          contrast(enhanced.outline, enhanced.surface),
          greaterThanOrEqualTo(3),
        );
        expect(
          contrast(enhanced.primary, enhanced.surface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(enhanced.onPrimaryContainer, enhanced.primaryContainer),
          greaterThanOrEqualTo(
            contrast(base.onPrimaryContainer, base.primaryContainer),
          ),
        );
      }
    }
  });

  testWidgets(
    'small screen settings and PIN remain usable with OS text plus largest preset',
    (t) async {
      await t.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => t.binding.setSurfaceSize(null));
      deviceText(t, 1.8);
      await appearance.setTextSize(AppTextSize.largest);
      await appearance.setHighContrast(true);
      final lock = testLock();
      addTearDown(lock.dispose);
      await t.pumpWidget(
        LocalChatApp(controller: c, appLock: lock, appearance: appearance),
      );
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Settings'));
      await t.pumpAndSettle();
      await visibleTap(t, find.byKey(const ValueKey('appearance-text-size')));
      expect(find.text(AppTextSize.largest.label), findsWidgets);
      await t.tap(find.text(AppTextSize.larger.label).last);
      await t.pumpAndSettle();
      await visibleTap(t, find.byKey(const ValueKey('appearance-text-size')));
      await t.tap(find.text(AppTextSize.largest.label).last);
      await t.pumpAndSettle();
      await visibleTap(
        t,
        find.byKey(const ValueKey('appearance-readability-preview')),
      );
      await t.pumpAndSettle();
      expect(find.text('Readability preview'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.runAsync(() => lock.enable('123456'));
      lock.lock();
      await t.pumpAndSettle();
      await visibleTap(t, find.widgetWithText(FilledButton, 'Unlock'));
      expect(find.byType(AppLockScreen), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'browser demo notice and home fit the combined largest text setting',
    (t) async {
      await t.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => t.binding.setSurfaceSize(null));
      deviceText(t, 1.8);
      await appearance.setTextSize(AppTextSize.largest);
      final demo = ChatController(DemoTransport(), DemoStore(), isDemo: true);
      addTearDown(demo.dispose);
      // WebCrypto must complete outside widget fake time before Home's loading
      // indicator can settle; production startup uses the browser's real clock.
      await t.runAsync(demo.initialize);
      final lock = testLock();
      addTearDown(lock.dispose);
      await t.pumpWidget(
        LocalChatApp(controller: demo, appLock: lock, appearance: appearance),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('BROWSER DEMO'), findsOneWidget);
      await t.tap(find.byTooltip('Settings'));
      await t.pumpAndSettle();
      await visibleTap(
        t,
        find.byKey(const ValueKey('appearance-readability-preview')),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'direct and group saved messages use enhanced contrast and keep drafts',
    (t) async {
      final group = (await t.runAsync(() async {
        await store.savePeer('alice', 'Alice');
        await store.saveMessage(
          ChatMessage(
            id: 'a' * 24,
            peerId: 'alice',
            text: 'Saved incoming',
            timestamp: 1,
            outgoing: false,
            status: 'received',
          ),
        );
        c.conversations = await store.conversations();
        await c.viewHistory(c.conversations.single);
        await c.drafts.load('alice');
        c.drafts.setText('alice', 'Direct unfinished');
        final group = (await emptyGroup(store)).copy(
          messages: [
            searchText('b' * 24, 'Group incoming', 2),
            searchText('c' * 24, 'Group outgoing', 3, author: c.groups.selfId),
          ],
        );
        await store.saveGroupHistory(group);
        await c.groups.refreshHistory();
        await c.drafts.load(group.id, group: true);
        c.drafts.setText(group.id, 'Group unfinished', group: true);
        await c.drafts.settled;
        return group;
      }))!;
      await appearance.setTextSize(AppTextSize.larger);
      await appearance.setHighContrast(true);
      final lock = testLock();
      addTearDown(lock.dispose);
      await t.pumpWidget(
        LocalChatApp(controller: c, appLock: lock, appearance: appearance),
      );
      await t.pumpAndSettle();
      final navigator = Navigator.of(t.element(find.byType(HomeScreen)));
      navigator.push(
        MaterialPageRoute<void>(builder: (_) => ChatScreen(controller: c)),
      );
      await t.pumpAndSettle();
      expect(
        find.widgetWithText(SelectableText, 'Saved incoming'),
        findsOneWidget,
      );
      final directContext = t.element(find.byType(ChatScreen));
      expect(
        MediaQuery.textScalerOf(directContext).scale(14),
        closeTo(16.1, .0001),
      );
      expect(
        Theme.of(directContext).colorScheme,
        buildAppTheme(
          AppPalette.mint,
          Brightness.dark,
          highContrast: true,
        ).colorScheme,
      );
      await t.pageBack();
      await t.pumpAndSettle();
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => GroupChatScreen(controller: c, id: group.id),
        ),
      );
      await t.pumpAndSettle();
      for (final text in ['Group incoming', 'Group outgoing']) {
        await t.ensureVisible(find.widgetWithText(SelectableText, text));
        await t.pumpAndSettle();
        final rendered = t.widget<SelectableText>(
          find.widgetWithText(SelectableText, text),
        );
        final container = t.widget<Container>(
          find
              .ancestor(
                of: find.widgetWithText(SelectableText, text),
                matching: find.byType(Container),
              )
              .first,
        );
        final background = (container.decoration! as BoxDecoration).color!;
        expect(
          contrast(rendered.style!.color!, background),
          greaterThanOrEqualTo(7),
        );
      }
      expect(c.drafts.textFor('alice'), 'Direct unfinished');
      expect(c.drafts.textFor(group.id, group: true), 'Group unfinished');
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'saving disables readability controls and a failed write offers retry',
    (t) async {
      final storage = PendingAppearanceStorage();
      final pending = AppearanceController(storage);
      addTearDown(pending.dispose);
      await pending.initialize();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(children: [AppearanceSettings(appearance: pending)]),
          ),
        ),
      );
      storage.gate = Completer<void>();
      storage.failWrite = true;
      final save = pending.setHighContrast(true);
      await t.pump();
      expect(
        t
            .widget<SwitchListTile>(
              find.byKey(const ValueKey('appearance-high-contrast')),
            )
            .onChanged,
        isNull,
      );
      expect(
        t
            .widget<DropdownButton<AppTextSize>>(
              find.byKey(const ValueKey('appearance-text-size')),
            )
            .onChanged,
        isNull,
      );
      storage.gate!.complete();
      expect(await save, isFalse);
      await t.pumpAndSettle();
      expect(
        find.text('Could not save appearance settings. Please try again.'),
        findsOneWidget,
      );
      expect(pending.highContrast, isFalse);
      storage.gate = null;
      storage.failWrite = false;
      await visibleTap(
        t,
        find.byKey(const ValueKey('appearance-high-contrast')),
      );
      expect(pending.highContrast, isTrue);
      expect(pending.error, isNull);
    },
  );

  testWidgets(
    'reply card icons retain their own surface contrast inside an outgoing bubble',
    (t) async {
      final theme = buildAppTheme(
        AppPalette.mint,
        Brightness.dark,
        highContrast: true,
      );
      final colors = theme.colorScheme;
      await t.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: MessageBubbleContent(
              foreground: colors.onPrimaryContainer,
              child: MessageReplyCard(
                reply: MessageReply(
                  id: 'a' * 24,
                  text: 'Quoted text',
                  name: 'Alice',
                  outgoing: false,
                ),
                name: 'Alice',
                onCancel: () {},
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      for (final icon in [Icons.reply, Icons.close]) {
        expect(
          contrast(
            t.widget<Icon>(find.byIcon(icon)).color!,
            colors.surfaceContainer,
          ),
          greaterThanOrEqualTo(7),
        );
      }
      expect(t.takeException(), isNull);
    },
  );
}
