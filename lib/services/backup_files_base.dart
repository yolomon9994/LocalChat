import 'dart:typed_data';

abstract class BackupFiles {
  Future<Uint8List?> pick();
  Future<bool> save(Uint8List bytes, String filename);
}
