import 'dart:convert';
import 'dart:typed_data';

/// Encodes the `String` [s] into bytes. Attempts to encode using [latin1],
/// and, in case of an error, falls back to [utf8].
Uint8List encodeChars(String s) {
  try {
    return latin1.encode(s);
  } catch (_) {
    return utf8.encode(s);
  }
}
