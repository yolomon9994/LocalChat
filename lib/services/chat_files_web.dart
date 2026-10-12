import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import '../core/chat_file.dart';
import 'chat_files_base.dart';

ChatFiles createChatFiles() => BrowserChatFiles();

class BrowserChatFiles implements ChatFiles {
  @override
  Future<SelectedFile?> pick() async {
    final result = Completer<SelectedFile?>();
    final input = web.HTMLInputElement()..type = 'file';
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
        if (file.size < 1 || file.size > fileMaxBytes) {
          result.completeError(
            const FormatException('Choose a nonempty file up to 8 MiB.'),
          );
          return;
        }
        unawaited(() async {
          try {
            result.complete(
              SelectedFile(
                ChatFile.safeName(file.name),
                (await file.arrayBuffer().toDart).toDart.asUint8List(),
              ),
            );
          } catch (_) {
            result.completeError(
              const FormatException('Could not read this file.'),
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
    if (bytes.isEmpty || bytes.length > fileMaxBytes) {
      throw const FormatException('Invalid file size.');
    }
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'application/octet-stream'),
    );
    final url = web.URL.createObjectURL(blob);
    final link = web.HTMLAnchorElement()
      ..href = url
      ..download = ChatFile.safeName(filename);
    web.document.body!.append(link);
    link.click();
    link.remove();
    Timer(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
    return true;
  }
}
