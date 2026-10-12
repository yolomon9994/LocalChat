import 'package:local_chat/services/chat_files.dart';

class MemoryGroupFiles implements ChatFiles {
  MemoryGroupFiles(this.selection);
  final SelectedFile? selection;
  final saved = <SelectedFile>[];
  bool result = true, fail = false;
  @override
  Future<SelectedFile?> pick() async => selection;
  @override
  Future<bool> save(Uint8List bytes, String name) async {
    if (fail) throw StateError('Provider failed');
    if (result) saved.add(SelectedFile(name, Uint8List.fromList(bytes)));
    return result;
  }
}
