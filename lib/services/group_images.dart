part of 'group_controller.dart';

class GroupImages extends GroupAttachments<Uint8List> {
  GroupImages(GroupController g) : super(g, false);
  @override
  Future<Uint8List?> _pickSource() => g.imageFiles.pick();
  @override
  Future<List<int>> _seal(Uint8List source) => normalizeImage(source);
  @override
  Uint8List _open(Uint8List bytes) => bytes;
  @override
  Uint8List _bytesOf(Uint8List source) => source;
}
