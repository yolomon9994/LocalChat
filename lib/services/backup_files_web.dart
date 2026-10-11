import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;
import '../core/chat_backup.dart';
import 'backup_files_base.dart';

BackupFiles createBackupFiles() => BrowserBackupFiles();

class BrowserBackupFiles implements BackupFiles {
  @override
  Future<Uint8List?> pick() async {
    final result = Completer<Uint8List?>();
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..accept = '.lcbackup';
    input.style.display = 'none';
    web.document.body!.append(input);
    input.addEventListener(
      'cancel',
      ((web.Event _) {
        if (!result.isCompleted) result.complete(null);
      }).toJS,
    );
    input.addEventListener(
      'change',
      ((web.Event _) {
        final file = input.files?.item(0);
        if (file == null) {
          result.complete(null);
          return;
        }
        if (file.size > backupMaxFile) {
          result.completeError(
            const FormatException('Backup exceeds the 20 MB limit.'),
          );
          return;
        }
        unawaited(() async {
          try {
            result.complete(
              (await file.arrayBuffer().toDart).toDart.asUint8List(),
            );
          } catch (_) {
            result.completeError(
              const FormatException('Could not read backup file.'),
            );
          }
        }());
      }).toJS,
    );
    input.click();
    try {
      return await result.future;
    } finally {
      input.remove();
    }
  }

  @override
  Future<bool> save(Uint8List bytes, String filename) async {
    if (bytes.length > backupMaxFile) {
      throw const FormatException('Backup exceeds the 20 MB limit.');
    }
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'application/octet-stream'),
    );
    final url = web.URL.createObjectURL(blob);
    final link = web.HTMLAnchorElement()
      ..href = url
      ..download = filename;
    web.document.body!.append(link);
    link.click();
    link.remove();
    Timer(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
    return true;
  }
}
