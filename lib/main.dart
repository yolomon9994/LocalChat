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

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = createController();
  runApp(LocalChatApp(controller: controller));
}

ChatController createController() => kIsWeb
    ? ChatController(DemoTransport(), DemoStore(), isDemo: true)
    : ChatController(WifiDirectTransport(), LocalStore());

class LocalChatApp extends StatefulWidget {
  const LocalChatApp({super.key, required this.controller, this.appLock});
  final ChatController controller;
  final AppLockController? appLock;
  @override
  State<LocalChatApp> createState() => _LocalChatAppState();
}

class _LocalChatAppState extends State<LocalChatApp>
    with WidgetsBindingObserver {
  late final AppLockController _lock =
      widget.appLock ??
      AppLockController.platform(isDemo: widget.controller.isDemo);
  bool _startedChat = false;
  ChatController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lock.addListener(_accessChanged);
    unawaited(_lock.initialize());
  }

  void _accessChanged() {
    if (_lock.canAccess && !_startedChat) {
      _startedChat = true;
      unawaited(controller.initialize());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _lock.lifecycle(state);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lock.removeListener(_accessChanged);
    if (widget.appLock == null) _lock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _lock,
    builder: (context, _) => MaterialApp(
      title: 'LocalChat',
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        // Remove the whole Navigator while locked. Pushed routes, dialogs,
        // keyboard shortcuts and the system back button cannot expose a chat.
        final content = _lock.canAccess
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
                  Expanded(child: content),
                ],
              )
            : content;
      },
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff48d8b0),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xff101716),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
        ),
        appBarTheme: const AppBarTheme(centerTitle: false),
      ),
      home: HomeScreen(controller: controller, appLock: _lock),
    ),
  );
}
