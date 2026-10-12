import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

const imageMaxBytes = 2 * 1024 * 1024;
const imageSourceMaxBytes = 8 * 1024 * 1024;
const imageMaxDimension = 1600;
const imageChunkBytes = 12288;

class ChatImage {
  const ChatImage(this.width, this.height, this.length, this.digest);
  final int width, height, length;
  final String digest;
  Map<String, Object?> toJson() => {
    'mime': 'image/png',
    'width': width,
    'height': height,
    'length': length,
    'digest': digest,
  };
  static ChatImage parse(Object? raw) {
    if (raw is! Map ||
        raw['mime'] != 'image/png' ||
        raw['width'] is! int ||
        raw['height'] is! int ||
        raw['length'] is! int ||
        raw['digest'] is! String) {
      throw const FormatException('Invalid image metadata.');
    }
    final image = ChatImage(
      raw['width'] as int,
      raw['height'] as int,
      raw['length'] as int,
      raw['digest'] as String,
    );
    if (image.width < 1 ||
        image.height < 1 ||
        image.width > imageMaxDimension ||
        image.height > imageMaxDimension ||
        image.length < 33 ||
        image.length > imageMaxBytes ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(image.digest)) {
      throw const FormatException('Image exceeds the supported limits.');
    }
    return image;
  }

  static Future<ChatImage> fromBytes(Uint8List bytes) async {
    if (bytes.length < 33 ||
        bytes.length > imageMaxBytes ||
        base64Encode(bytes.sublist(0, 8)) != 'iVBORw0KGgo=' ||
        ascii.decode(bytes.sublist(12, 16), allowInvalid: true) != 'IHDR') {
      throw const FormatException('Choose a supported image (maximum 2 MiB).');
    }
    final data = ByteData.sublistView(bytes);
    final digest = (await Sha256().hash(
      bytes,
    )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return parse({
      'mime': 'image/png',
      'width': data.getUint32(16),
      'height': data.getUint32(20),
      'length': bytes.length,
      'digest': digest,
    });
  }

  Future<void> verify(Uint8List bytes) async {
    final actual = await fromBytes(bytes);
    if (jsonEncode(actual.toJson()) != jsonEncode(toJson())) {
      throw const FormatException('Image contents do not match metadata.');
    }
  }
}
