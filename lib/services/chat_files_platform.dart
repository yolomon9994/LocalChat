import 'package:flutter/services.dart';
import '../core/chat_file.dart';
import 'chat_files_base.dart';

ChatFiles createChatFiles() => const AndroidChatFiles();

class AndroidChatFiles implements ChatFiles {
  const AndroidChatFiles();
  static const channel = MethodChannel('dev.localchat/files');
  @override
  Future<SelectedFile?> pick() async {
    final result = await channel.invokeMapMethod<String, dynamic>('pick');
    if (result == null) return null;
    final bytes = result['bytes'];
    final name = result['name'];
    if (name is! String ||
        bytes is! Uint8List ||
        bytes.isEmpty ||
        bytes.length > fileMaxBytes) {
      throw const FormatException('Could not read this file (maximum 8 MiB).');
    }
    return SelectedFile(ChatFile.safeName(name), bytes);
  }

  @override
  Future<bool> save(Uint8List bytes, String name) async {
    if (bytes.isEmpty || bytes.length > fileMaxBytes) {
      throw const FormatException('Invalid file size.');
    }
    return await channel.invokeMethod<bool>('save', {
          'bytes': bytes,
          'name': ChatFile.safeName(name),
        }) ??
        false;
  }
}
