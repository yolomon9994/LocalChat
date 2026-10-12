import 'dart:typed_data';
import 'dart:ui' as ui;
import '../core/chat_image.dart';

/// Re-encoding strips source metadata; only the first frame is sent.
Future<Uint8List> normalizeImage(Uint8List source) async {
  if (source.isEmpty || source.length > imageSourceMaxBytes) {
    throw const FormatException('Choose an image under 8 MiB.');
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(source);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (descriptor.width * descriptor.height > 40000000) {
      throw const FormatException('Choose an image under 40 megapixels.');
    }
    final scale =
        imageMaxDimension /
        (descriptor.width > descriptor.height
            ? descriptor.width
            : descriptor.height);
    codec = await descriptor.instantiateCodec(
      targetWidth: scale < 1
          ? (descriptor.width * scale).round().clamp(1, imageMaxDimension)
          : descriptor.width,
      targetHeight: scale < 1
          ? (descriptor.height * scale).round().clamp(1, imageMaxDimension)
          : descriptor.height,
    );
    image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw const FormatException('Could not prepare this image.');
    }
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    await ChatImage.fromBytes(bytes);
    return bytes;
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}

Future<void> validateImagePixels(Uint8List bytes) async {
  await ChatImage.fromBytes(bytes);
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    if (codec.frameCount != 1) {
      throw const FormatException('Animated images are unsupported.');
    }
    final frame = await codec.getNextFrame();
    frame.image.dispose();
  } finally {
    codec.dispose();
  }
}
