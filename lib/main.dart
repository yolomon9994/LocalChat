import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'core/local_store.dart';
import 'demo/demo_store.dart';
import 'demo/demo_transport.dart';
import 'services/chat_controller.dart';
import 'services/transport.dart';
import 'features/home_screen.dart';
import 'features/app_lock_screen.dart';
import 'services/app_lock_controller.dart';
import 'services/appearance_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = createController();
  runApp(LocalChatApp(controller: controller));
}

ChatController createController() => kIsWeb
    ? ChatController(DemoTransport(), DemoStore(), isDemo: true)
    : ChatController(WifiDirectTransport(), LocalStore());

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
  ChatController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller.setAppAccess(_lock.canAccess);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    controller.setAppForeground(
      lifecycle == null || lifecycle == AppLifecycleState.resumed,
    );
    _lock.addListener(_accessChanged);
    unawaited(_lock.initialize());
    unawaited(_appearance.initialize());
  }

  void _accessChanged() {
    controller.setAppAccess(_lock.canAccess);
    if (_lock.canAccess && !_startedChat) {
      _startedChat = true;
      unawaited(controller.initialize());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Stop read marking immediately, before locked routes are disposed.
    controller.setAppForeground(state == AppLifecycleState.resumed);
    _lock.lifecycle(state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.setAppAccess(false);
    _lock.removeListener(_accessChanged);
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
                      builder: (_, _) => AppLockScreen(lock: _lock),
                    ),
                  ),
                ),
              );
        return controller.isDemo
            ? Column(
                children: [
                  Material(
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
                  ),
                  Expanded(child: content),
                ],
              )
            : content;
      },
      themeMode: _appearance.mode,
      theme: buildAppTheme(_appearance.palette, Brightness.light),
      darkTheme: buildAppTheme(_appearance.palette, Brightness.dark),
      home: HomeScreen(
        controller: controller,
        appLock: _lock,
        appearance: _appearance,
        routeObserver: _routes,
      ),
    ),
  );
}
