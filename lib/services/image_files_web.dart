import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;
import '../core/chat_image.dart';
import 'image_files_base.dart';

ImageFiles createImageFiles() => BrowserImageFiles();

class BrowserImageFiles implements ImageFiles {
  @override
  Future<Uint8List?> pick() async {
    final result = Completer<Uint8List?>();
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..accept = 'image/*';
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
        if (file.size > imageSourceMaxBytes) {
          result.completeError(
            const FormatException('Choose an image under 8 MiB.'),
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
              const FormatException('Could not read this image.'),
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
}
