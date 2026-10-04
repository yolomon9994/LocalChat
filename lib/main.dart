import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'core/local_store.dart';
import 'demo/demo_store.dart';
import 'demo/demo_transport.dart';
import 'services/chat_controller.dart';
import 'services/transport.dart';
import 'features/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = createController();
  runApp(LocalChatApp(controller: controller));
  controller.initialize();
}

ChatController createController() => kIsWeb
    ? ChatController(DemoTransport(), DemoStore(), isDemo: true)
    : ChatController(WifiDirectTransport(), LocalStore());

class LocalChatApp extends StatelessWidget {
  const LocalChatApp({super.key, required this.controller});
  final ChatController controller;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'LocalChat',
    debugShowCheckedModeBanner: false,
    builder: controller.isDemo
        ? (context, child) => Column(
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
              Expanded(child: child!),
            ],
          )
        : null,
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
    home: HomeScreen(controller: controller),
  );
}
