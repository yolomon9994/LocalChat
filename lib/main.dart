import 'package:flutter/material.dart';
import 'core/local_store.dart';
import 'services/chat_controller.dart';
import 'services/transport.dart';
import 'features/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = ChatController(WifiDirectTransport(), LocalStore());
  runApp(LocalChatApp(controller: controller));
  controller.initialize();
}

class LocalChatApp extends StatelessWidget {
  const LocalChatApp({super.key, required this.controller});
  final ChatController controller;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'LocalChat',
    debugShowCheckedModeBanner: false,
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
