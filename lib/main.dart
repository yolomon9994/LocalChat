import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'core/local_store.dart';
import 'demo/demo_store.dart';
import 'demo/demo_transport.dart';
import 'demo/demo_group_transport.dart';
import 'services/chat_controller.dart';
import 'services/transport.dart';
import 'features/home_screen.dart';
import 'features/app_lock_screen.dart';
import 'features/chat_screen.dart';
import 'features/group_screen.dart';
import 'services/app_lock_controller.dart';
import 'services/appearance_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = createController();
  runApp(LocalChatApp(controller: controller));
}

ChatController createController() => kIsWeb
    ? createDemoController()
    : ChatController(WifiDirectTransport(), LocalStore());

ChatController createDemoController() => ChatController(
  DemoTransport(),
  DemoStore(),
  isDemo: true,
  groupTransport: DemoGroupTransport(),
);

class LocalChatApp extends StatefulWidget {
  const LocalChatApp({
    super.key,
    required this.controller,
    this.appLock,
    this.appearance,
  });
  final ChatController controller;
  final AppLockController? appLock;
  final AppearanceController? appearance;
  @override
  State<LocalChatApp> createState() => _LocalChatAppState();
}

class _LocalChatAppState extends State<LocalChatApp>
    with WidgetsBindingObserver {
  late final AppLockController _lock =
      widget.appLock ??
      AppLockController.platform(isDemo: widget.controller.isDemo);
  bool _startedChat = false;
  late final AppearanceController _appearance =
      widget.appearance ??
      AppearanceController.platform(isDemo: widget.controller.isDemo);
  late final Listenable _changes = Listenable.merge([_lock, _appearance]);
  final _routes = RouteObserver<ModalRoute<dynamic>>();
  final _navigator = GlobalKey<NavigatorState>();
  bool _openingNotification = false;
  ChatController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    // Use Flutter's selectable-text menus so the browser demo exposes the
    // same full-message and selected-text copy actions as Android.
    if (kIsWeb) unawaited(BrowserContextMenu.disableContextMenu());
    WidgetsBinding.instance.addObserver(this);
    controller.setAppAccess(_lock.canAccess);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    controller.setAppForeground(
      lifecycle == null || lifecycle == AppLifecycleState.resumed,
    );
    if (lifecycle != null) _lock.lifecycle(lifecycle);
    _lock.addListener(_accessChanged);
    controller.addListener(_notificationChanged);
    controller.notifications.addListener(_notificationChanged);
    _appearance.addListener(_notificationChanged);
    unawaited(controller.notifications.initialize());
    unawaited(controller.background.initialize());
    unawaited(_lock.initialize());
    unawaited(_appearance.initialize());
  }

  void _accessChanged() {
    controller.setAppAccess(_lock.canAccess);
    if (_lock.canAccess && !_startedChat) {
      _startedChat = true;
      unawaited(controller.initialize());
    }
    _notificationChanged();
  }

  void _notificationChanged() {
    if (!mounted ||
        _openingNotification ||
        !_lock.canAccess ||
        _appearance.loading ||
        !controller.initialized ||
        !controller.appForeground ||
        controller.notifications.pendingPeer == null) {
      return;
    }
    _openingNotification = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final peer = controller.notifications.pendingPeer;
        if (!mounted ||
            peer == null ||
            !_lock.canAccess ||
            !controller.appForeground) {
          return;
        }
        final navigator = _navigator.currentState;
        if (navigator == null) return;
        final token = controller.accessRevision;
        if (peer.startsWith('group:')) {
          final id = peer.substring(6);
          final found = controller.groups.histories.where((g) => g.id == id);
          controller.notifications.consumeTap(peer);
          if (found.isEmpty) {
            ScaffoldMessenger.of(navigator.context).showSnackBar(
              const SnackBar(
                content: Text('This group history is no longer available.'),
              ),
            );
            return;
          }
          navigator.popUntil((route) => route.isFirst);
          unawaited(
            navigator.push(
              MaterialPageRoute<void>(
                builder: (_) => GroupChatScreen(
                  controller: controller,
                  id: id,
                  routeObserver: _routes,
                ),
              ),
            ),
          );
          return;
        }
        final matches = controller.conversations.where((c) => c.id == peer);
        if (matches.isEmpty) {
          controller.notifications.consumeTap(peer);
          ScaffoldMessenger.of(navigator.context).showSnackBar(
            const SnackBar(
              content: Text('This conversation is no longer available.'),
            ),
          );
          return;
        }
        final opened = await controller.viewHistory(
          matches.first,
          notificationAccessToken: token,
        );
        if (!mounted ||
            !_lock.canAccess ||
            !controller.appForeground ||
            controller.accessRevision != token ||
            controller.notifications.pendingPeer != peer ||
            _navigator.currentState != navigator) {
          return;
        }
        controller.notifications.consumeTap(peer);
        if (!opened) return;
        navigator.popUntil((route) => route.isFirst);
        unawaited(
          navigator.push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  ChatScreen(controller: controller, routeObserver: _routes),
            ),
          ),
        );
      } finally {
        _openingNotification = false;
        if (mounted) _notificationChanged();
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Stop read marking immediately, before locked routes are disposed.
    controller.setAppForeground(state == AppLifecycleState.resumed);
    _lock.lifecycle(state);
    _notificationChanged();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.setAppAccess(false);
    _lock.removeListener(_accessChanged);
    controller.removeListener(_notificationChanged);
    controller.notifications.removeListener(_notificationChanged);
    _appearance.removeListener(_notificationChanged);
    if (widget.appLock == null) _lock.dispose();
    if (widget.appearance == null) _appearance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _changes,
    builder: (context, _) => MaterialApp(
      title: 'LocalChat',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigator,
      navigatorObservers: [_routes],
      builder: (context, child) {
        // Remove the whole Navigator while locked. Pushed routes, dialogs,
        // keyboard shortcuts and the system back button cannot expose a chat.
        final content = _appearance.loading
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : _lock.canAccess
            ? child!
            : Navigator(
                key: const ValueKey('lock-navigator'),
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (_) => PopScope(
                    canPop: false,
                    child: ListenableBuilder(
                      listenable: _lock,
                      builder: (_, _) => _lock.covered
                          ? const Scaffold(
                              key: ValueKey('app-privacy-cover'),
                              body: Center(
                                child: Icon(
                                  Icons.lock_outline,
                                  semanticLabel: 'LocalChat hidden',
                                ),
                              ),
                            )
                          : AppLockScreen(lock: _lock),
                    ),
                  ),
                ),
              );
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: _appearance.textSize.applyTo(media.textScaler),
            highContrast: media.highContrast || _appearance.highContrast,
          ),
          child: controller.isDemo
              ? LayoutBuilder(
                  builder: (context, constraints) {
                    final notice = Material(
                      color: Theme.of(context).colorScheme.tertiaryContainer,
                      child: DefaultTextStyle.merge(
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onTertiaryContainer,
                        ),
                        child: const SafeArea(
                          bottom: false,
                          child: Padding(
                            padding: EdgeInsets.all(10),
                            child: Text(
                              'BROWSER DEMO — simulated devices and messages. '
                              'No real Wi-Fi Direct communication. '
                              'History and settings reset on reload.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    );
                    final largeText =
                        MediaQuery.textScalerOf(context).scale(14) > 21;
                    return Column(
                      children: [
                        if (largeText || constraints.maxHeight < 400)
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: constraints.maxHeight * .3,
                            ),
                            child: SingleChildScrollView(
                              primary: false,
                              child: notice,
                            ),
                          )
                        else
                          notice,
                        Expanded(child: content),
                      ],
                    );
                  },
                )
              : content,
        );
      },
      themeMode: _appearance.mode,
      theme: buildAppTheme(
        _appearance.palette,
        Brightness.light,
        highContrast: _appearance.highContrast,
      ),
      darkTheme: buildAppTheme(
        _appearance.palette,
        Brightness.dark,
        highContrast: _appearance.highContrast,
      ),
      highContrastTheme: buildAppTheme(
        _appearance.palette,
        Brightness.light,
        highContrast: true,
      ),
      highContrastDarkTheme: buildAppTheme(
        _appearance.palette,
        Brightness.dark,
        highContrast: true,
      ),
      home: HomeScreen(
        controller: controller,
        appLock: _lock,
        appearance: _appearance,
        routeObserver: _routes,
      ),
    ),
  );
}
