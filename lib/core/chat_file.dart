import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

const fileMaxBytes = 8 * 1024 * 1024;

/// File contents remain opaque. Names never become filesystem paths.
class ChatFile {
  const ChatFile(this.name, this.length, this.digest);
  final String name, digest;
  final int length;
  static final _unsafe = RegExp(
    r'[\\/\x00-\x1f\x7f-\x9f<>:"|?*\u202a-\u202e\u2066-\u2069]',
  );

  static String safeName(String value) {
    // Truncate before trimming so the result remains canonical at the boundary.
    // Count Unicode code points, avoiding a split surrogate pair.
    var name = String.fromCharCodes(
      value.replaceAll(_unsafe, '_').runes.take(120),
    ).trim();
    name = name.replaceAll(RegExp(r'^[. ]+|[. ]+$'), '');
    if (name.isEmpty) name = 'attachment.bin';
    return name;
  }

  Map<String, Object?> toJson() => {
    'name': name,
    'mime': 'application/octet-stream',
    'length': length,
    'digest': digest,
  };

  static ChatFile parse(Object? raw) {
    if (raw is! Map ||
        raw['name'] is! String ||
        raw['length'] is! int ||
        raw['digest'] is! String ||
        raw['mime'] != 'application/octet-stream') {
      throw const FormatException('Invalid file metadata.');
    }
    final file = ChatFile(
      raw['name'] as String,
      raw['length'] as int,
      raw['digest'] as String,
    );
    if (file.name != safeName(file.name) ||
        file.length < 1 ||
        file.length > fileMaxBytes ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(file.digest)) {
      throw const FormatException(
        'Invalid filename or file size (maximum 8 MiB).',
      );
    }
    return file;
  }

  static Future<ChatFile> fromBytes(String name, Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > fileMaxBytes) {
      throw const FormatException('Choose a nonempty file up to 8 MiB.');
    }
    final digest = (await Sha256().hash(
      bytes,
    )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return ChatFile(safeName(name), bytes.length, digest);
  }

  Future<void> verify(Uint8List bytes) async {
    parse(toJson());
    final actual = await fromBytes(name, bytes);
    if (actual.length != length || actual.digest != digest) {
      throw const FormatException('File contents do not match metadata.');
    }
  }
}
