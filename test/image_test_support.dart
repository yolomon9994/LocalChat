import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

Future<Uint8List> testImage({int size = 80}) async {
  final pixels = Uint8List(size * size * 4);
  final random = Random(42);
  for (var i = 0; i < pixels.length; i += 4) {
    pixels[i] = random.nextInt(256);
    pixels[i + 1] = random.nextInt(256);
    pixels[i + 2] = random.nextInt(256);
    pixels[i + 3] = 255;
  }
  final result = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    size,
    size,
    ui.PixelFormat.rgba8888,
    result.complete,
  );
  final image = await result.future;
  try {
    final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}
