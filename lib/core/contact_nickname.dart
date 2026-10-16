import 'dart:convert';

/// Null/blank removes a local nickname. Bound UTF-8 bytes and reject controls.
String? normalizeContactNickname(String? value) {
  final text = value?.trim();
  if (text == null || text.isEmpty) return null;
  if (utf8.encode(text).length > 128 ||
      text.runes.any(
        (r) =>
            r < 32 ||
            (r >= 127 && r <= 159) ||
            r == 0x2028 ||
            r == 0x2029 ||
            (r >= 0x202a && r <= 0x202e) ||
            (r >= 0x2066 && r <= 0x2069),
      )) {
    throw const FormatException(
      'Use a single-line nickname of up to 128 UTF-8 bytes.',
    );
  }
  return text;
}
