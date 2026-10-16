import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_chat/core/models.dart';
import 'package:local_chat/demo/demo_transport.dart';
import 'package:local_chat/features/action_feedback.dart';
import 'package:local_chat/features/chat_screen.dart';
import 'package:local_chat/features/feedback_settings.dart';
import 'package:local_chat/features/group_screen.dart';
import 'package:local_chat/features/settings_screen.dart';
import 'package:local_chat/features/verification_screen.dart';
import 'package:local_chat/services/action_feedback.dart';
import 'package:local_chat/services/chat_controller.dart';
import 'package:local_chat/services/group_controller.dart';
import 'action_feedback_test.dart';
import 'chat_controller_test.dart' show LinkedTransport, settle;
import 'group_test_support.dart';
import 'message_reply_test.dart' show ReplyStore;

void main() {
  late FakeActionHaptics haptics;
  late FailingFeedbackStorage storage;
  late ActionFeedback feedback;
  late ReplyStore store;
  late ChatController c;
  late GroupNetwork net;
  setUp(() async {
    if (kIsWeb) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            SystemChannels.contextMenu,
            (_) async => null,
          );
      await BrowserContextMenu.disableContextMenu();
    }
    haptics = FakeActionHaptics();
    storage = FailingFeedbackStorage();
    feedback = ActionFeedback(storage, haptics: haptics);
    store = ReplyStore();
    net = GroupNetwork();
    c = ChatController(
      DemoTransport(),
      store,
      feedback: feedback,
      groupTransport: FakeGroupTransport(net),
    );
    await c.initialize();
    net.controllers.add(c.groups);
    await feedback.setEnabled(true);
  });
  tearDown(() async {
    net.controllers.remove(c.groups);
    await net.close();
    c.dispose();
    if (kIsWeb) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.contextMenu, null);
    }
  });
  Future<void> turn(WidgetTester t) async {
    // Peer cryptography uses real time; controller continuations and layout
    // also need widget frames before protocol queues can finish.
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 30));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
    }
    await t.pumpAndSettle();
  }

  Future<void> show(WidgetTester t, Widget home) async {
    await t.pumpWidget(MaterialApp(home: home));
    await turn(t);
  }

  Future<void> tapVisible(WidgetTester t, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      await t.scrollUntilVisible(
        finder,
        200,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await t.ensureVisible(finder);
    await t.pumpAndSettle();
    expect(finder.hitTestable(), findsOneWidget);
    await t.tap(finder);
    await turn(t);
  }

  Future<void> openSaved(WidgetTester t) async {
    await t.runAsync(() async {
      await store.savePeer('alice', 'Alice');
      c.conversations = await store.conversations();
      await c.viewHistory(c.conversations.single);
      await c.drafts.load('alice');
    });
    await show(t, ChatScreen(controller: c));
  }

  testWidgets(
    'settings persist opt-in, test explicitly and recover from a failed save',
    (t) async {
      await feedback.setEnabled(false);
      await show(t, SettingsScreen(controller: c));
      expect(feedback.enabled, isFalse);
      expect(haptics.calls, 0);
      await tapVisible(t, find.byKey(const ValueKey('vibration-feedback')));
      expect(feedback.enabled, isTrue);
      expect(haptics.calls, 0);
      await tapVisible(t, find.byKey(const ValueKey('try-vibration')));
      expect(haptics.calls, 1);
      storage.failWrite = true;
      await tapVisible(t, find.byKey(const ValueKey('vibration-feedback')));
      expect(feedback.enabled, isTrue);
      expect(
        find.text('Could not save vibration feedback. Please try again.'),
        findsOneWidget,
      );
      storage.failWrite = false;
      await tapVisible(t, find.byKey(const ValueKey('vibration-feedback')));
      expect(feedback.enabled, isFalse);
      expect(haptics.calls, 1);
    },
  );

  testWidgets(
    'accepted local text pulses once; failures and programmatic work do not',
    (t) async {
      await openSaved(t);
      final composer = find.widgetWithText(
        TextField,
        'Draft (verify both phones to send)',
      );
      // The controller's composer label is allowed to describe its offline state.
      final input = composer.evaluate().isEmpty
          ? find.byType(TextField).last
          : composer;
      await t.enterText(input, 'Local accepted text');
      await t.tap(find.byTooltip('Queue message'));
      await t.runAsync(settle);
      await turn(t);
      expect(haptics.calls, 1);
      expect(c.messages.single.text, 'Local accepted text');
      expect(c.messages.single.status, 'queued');
      final programmatic = c.sendText(
        'Programmatic outbox work',
        queueIfOffline: true,
      );
      await turn(t);
      await t.runAsync(settle);
      await turn(t);
      expect(await programmatic, isTrue);
      expect(haptics.calls, 1);
      store.failMessage = true;
      await t.enterText(find.byType(TextField).last, 'Failed save');
      await t.tap(find.byTooltip('Queue message'));
      await t.runAsync(settle);
      await turn(t);
      expect(haptics.calls, 1);
      expect(c.messages.length, 2);
      store.failMessage = false;
      haptics.fail = true;
      await t.tap(find.byTooltip('Queue message'));
      await t.runAsync(settle);
      await turn(t);
      expect(haptics.calls, 2);
      expect(c.messages.length, 3);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'foreground, lock, covered route and disposal invalidate pending feedback',
    (t) async {
      for (final reason in ['background', 'lock', 'covered', 'disposed']) {
        BuildContext? actionContext;
        await show(
          t,
          Builder(
            builder: (context) {
              actionContext = context;
              return const Scaffold(body: Text('Action'));
            },
          ),
        );
        final gate = Completer<bool>();
        final result = withActionFeedback(actionContext!, c, () => gate.future);
        if (reason == 'background') {
          c.setAppForeground(false);
          c.setAppForeground(true);
        } else if (reason == 'lock') {
          c.setAppAccess(false);
          c.setAppAccess(true);
        } else if (reason == 'covered') {
          Navigator.of(actionContext!).push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Covered')),
            ),
          );
          await turn(t);
        } else {
          await t.pumpWidget(const SizedBox.shrink());
        }
        gate.complete(true);
        expect(await result, isTrue);
        await turn(t);
        expect(haptics.calls, 0);
        await t.pumpWidget(const SizedBox.shrink());
        await turn(t);
      }
    },
  );

  testWidgets(
    'a pending native pulse never delays success or queues another pulse',
    (t) async {
      BuildContext? actionContext;
      await show(
        t,
        Builder(
          builder: (context) {
            actionContext = context;
            return const Scaffold();
          },
        ),
      );
      haptics.gate = Completer<void>();
      expect(
        await withActionFeedback(actionContext!, c, () async => true),
        isTrue,
      );
      expect(haptics.calls, 1);
      expect(
        await withActionFeedback(actionContext!, c, () async => true),
        isTrue,
      );
      expect(haptics.calls, 1);
      haptics.gate!.complete();
      await turn(t);
      expect(haptics.calls, 1);
    },
  );

  testWidgets('demo remains silent even with an injected supported adapter', (
    t,
  ) async {
    final demoHaptics = FakeActionHaptics();
    final f = ActionFeedback(MemoryFeedbackStorage(), haptics: demoHaptics);
    final demo = ChatController(
      DemoTransport(),
      ReplyStore(),
      isDemo: true,
      feedback: f,
    );
    addTearDown(demo.dispose);
    await t.runAsync(demo.initialize);
    await f.setEnabled(true);
    BuildContext? actionContext;
    await show(
      t,
      Builder(
        builder: (context) {
          actionContext = context;
          return Scaffold(body: FeedbackSettings(controller: demo));
        },
      ),
    );
    expect(find.textContaining('Demo preference only'), findsOneWidget);
    expect(
      t
          .widget<TextButton>(find.byKey(const ValueKey('try-vibration')))
          .onPressed,
      isNull,
    );
    expect(
      await withActionFeedback(actionContext!, demo, () async => true),
      isTrue,
    );
    expect(demoHaptics.calls, 0);
  });

  testWidgets(
    'manual group confirmation and a signed group send each give one local pulse',
    (t) async {
      late final GroupController guest;
      await t.runAsync(() async {
        await c.groups.host('Feedback room');
        guest = await net.phone('Guest');
        await net.join(guest, verify: false);
      });
      await show(
        t,
        Scaffold(
          body: SingleChildScrollView(child: GroupVerification(controller: c)),
        ),
      );
      await tapVisible(t, find.widgetWithText(FilledButton, 'Codes match'));
      await turn(t);
      await turn(t);
      expect(haptics.calls, 1);
      expect(c.groups.links.values.single.localVerified, isTrue);
      expect(c.groups.links.values.single.admitted, isFalse);
      await t.runAsync(() => guest.confirm(guest.links.keys.single));
      await turn(t);
      expect(c.groups.members, hasLength(2));
      await show(t, GroupChatScreen(controller: c, id: c.groups.active!.id));
      await t.enterText(
        find.byKey(const ValueKey('group-message-composer')),
        'Group action feedback',
      );
      await t.tap(find.byTooltip('Send group message'));
      await turn(t);
      await turn(t);
      expect(haptics.calls, 2);
      expect(c.groups.active!.messages.single.text, 'Group action feedback');
      await turn(t);
      await turn(t);
      expect(haptics.calls, 2);
    },
  );

  testWidgets(
    'QR confirmation gives feedback only after the explicit Verify action',
    (t) async {
      final qh = FakeActionHaptics();
      final qf = ActionFeedback(MemoryFeedbackStorage(), haptics: qh);
      late final LinkedTransport ta, tb;
      late final ChatController a, b;
      await t.runAsync(() async {
        ta = LinkedTransport();
        tb = LinkedTransport();
        ta.other = tb;
        tb.other = ta;
        a = ChatController(ta, ReplyStore(), feedback: qf);
        b = ChatController(tb, ReplyStore());
        await a.initialize();
        await b.initialize();
        await qf.setEnabled(true);
        await a.start();
        await b.start();
        await a.connect(const Peer('B', 'Bob'));
        await settle();
      });
      addTearDown(() async {
        a.dispose();
        b.dispose();
        await ta.bus.close();
        await tb.bus.close();
      });
      ValueChanged<String>? detected;
      await show(
        t,
        Scaffold(
          body: VerificationActions(
            controller: a,
            request: a.directVerification!,
            scannerBuilder: (_, callback) {
              detected = callback;
              return const Text('Fake camera');
            },
          ),
        ),
      );
      await t.tap(find.text('Scan QR'));
      await turn(t);
      detected!(b.directVerification!.qr.encode);
      await turn(t);
      expect(qh.calls, 0);
      expect(a.localVerified, isFalse);
      await tapVisible(t, find.text('Verify connection'));
      await t.runAsync(settle);
      await turn(t);
      expect(a.localVerified, isTrue);
      expect(a.ready, isFalse);
      expect(qh.calls, 1);
    },
  );

  testWidgets('feedback settings fit a small screen with enlarged text', (
    t,
  ) async {
    await t.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 568),
            textScaler: TextScaler.linear(2.34),
          ),
          child: Scaffold(
            body: ListView(children: [FeedbackSettings(controller: c)]),
          ),
        ),
      ),
    );
    await turn(t);
    await tapVisible(t, find.byKey(const ValueKey('try-vibration')));
    expect(haptics.calls, 1);
    expect(t.takeException(), isNull);
  });
}
