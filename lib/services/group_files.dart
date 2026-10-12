part of 'group_controller.dart';

class GroupFiles extends GroupAttachments<SelectedFile> {
  GroupFiles(GroupController g) : super(g, true);
  @override
  Future<SelectedFile?> _pickSource() => g.chatFiles.pick();
  @override
  Future<List<int>> _seal(SelectedFile source) async {
    final meta = await ChatFile.fromBytes(source.name, source.bytes);
    return utf8.encode(
      jsonEncode({'name': meta.name, 'data': base64Encode(source.bytes)}),
    );
  }

  @override
  SelectedFile _open(Uint8List bytes) {
    final raw = jsonDecode(utf8.decode(bytes)) as Map;
    return SelectedFile(
      raw['name'] as String,
      base64Decode(raw['data'] as String),
    );
  }

  @override
  Uint8List _bytesOf(SelectedFile source) => source.bytes;
  @override
  String _nameOf(SelectedFile source) => source.name;

  Future<bool> saveToPhone(String groupId, GroupText message) async {
    if (g._disposed || !g.canAct() || message.file == null) return false;
    final access = _access;
    try {
      final histories = await g.store.groupHistories();
      final found = histories.where((h) => h.id == groupId);
      if (found.isEmpty) return false;
      final rows = found.first.messages.where((m) => m.key == message.key);
      if (rows.isEmpty ||
          rows.first.file == null ||
          rows.first.fileBytes == null) {
        return false;
      }
      final stored = rows.first;
      await stored.file!.verify(stored.fileBytes!);
      if (g._disposed || !g.canAct() || access != _access) return false;
      // Explicit export may finish while the system destination picker is open.
      return await g.chatFiles.save(stored.fileBytes!, stored.file!.name);
    } catch (_) {
      g.error =
          'Could not save this file. Try again and choose a writable folder.';
      g._notify();
      return false;
    }
  }
}
