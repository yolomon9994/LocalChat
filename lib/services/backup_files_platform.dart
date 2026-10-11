import 'package:flutter/services.dart';
import '../core/chat_backup.dart';
import 'backup_files_base.dart';

BackupFiles createBackupFiles() => AndroidBackupFiles();

class AndroidBackupFiles implements BackupFiles {
  static const _channel = MethodChannel('dev.localchat/backup');
  @override
  Future<Uint8List?> pick() async {
    final bytes = await _channel.invokeMethod<Uint8List>('pick');
    if (bytes != null && bytes.length > backupMaxFile) {
      throw const FormatException('Backup exceeds the 20 MB limit.');
    }
    return bytes;
  }

  @override
  Future<bool> save(Uint8List bytes, String filename) async {
    if (bytes.length > backupMaxFile) {
      throw const FormatException('Backup exceeds the 20 MB limit.');
    }
    return await _channel.invokeMethod<bool>('save', {
          'bytes': bytes,
          'name': filename,
        }) ??
        false;
  }
}
