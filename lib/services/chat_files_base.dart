import 'dart:typed_data';
export 'dart:typed_data';

class SelectedFile {
  const SelectedFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

abstract class ChatFiles {
  Future<SelectedFile?> pick();
  Future<bool> save(Uint8List bytes, String name);
}
