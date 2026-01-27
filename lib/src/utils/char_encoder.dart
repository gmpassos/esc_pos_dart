import 'dart:convert';
import 'dart:typed_data';

import 'package:charset/charset.dart' as charset;

typedef CharsetEncoder = Converter<String, List<int>>;

CharsetEncoder? getCharsetEncoder(String? name) {
  if (name == null) return null;
  name = name.trim().toLowerCase();
  if (name.isEmpty) return null;

  switch (name) {
    case 'latin-2':
      return charset.latin2.encoder;
    case 'latin-3':
      return charset.latin3.encoder;
    case 'latin-4':
      return charset.latin4.encoder;
    case 'cyrillic':
      return charset.latinCyrillic.encoder;
    case 'arabic':
      return charset.latinArabic.encoder;
    case 'greek':
      return charset.latinGreek.encoder;
    case 'hebrew':
      return charset.latinHebrew.encoder;
    case 'latin-5':
      return charset.latin5.encoder;
    case 'latin-6':
      return charset.latin6.encoder;
    case 'tis620':
      return charset.latinThai.encoder;
    case 'latin-7':
      return charset.latin7.encoder;
    case 'latin-8':
      return charset.latin8.encoder;
    case 'latin-9':
      return charset.latin9.encoder;
    case 'latin-10':
      return charset.latin10.encoder;

    case 'windows874':
      return charset.windows874.encoder;
    case 'windows1250':
      return charset.windows1250.encoder;
    case 'windows1251':
      return charset.windows1251.encoder;
    case 'windows1252':
    case 'latin-1':
      return charset.windows1252.encoder;
    case 'windows1253':
      return charset.windows1253.encoder;
    case 'windows1254':
      return charset.windows1254.encoder;
    case 'windows1255':
      return charset.windows1255.encoder;
    case 'windows1256':
      return charset.windows1256.encoder;
    case 'windows1257':
      return charset.windows1257.encoder;
    case 'windows1258':
      return charset.windows1258.encoder;

    case 'cp437':
      return charset.cp437.encoder;
    case 'cp737':
      return charset.cp737.encoder;
    case 'cp775':
      return charset.cp775.encoder;
    case 'cp850':
      return charset.cp850.encoder;
    case 'cp852':
      return charset.cp852.encoder;
    case 'cp855':
      return charset.cp855.encoder;
    case 'cp856':
      return charset.cp856.encoder;
    case 'cp857':
      return charset.cp857.encoder;
    case 'cp858':
      return charset.cp858.encoder;
    case 'cp860':
      return charset.cp860.encoder;
    case 'cp861':
      return charset.cp861.encoder;
    case 'cp862':
      return charset.cp862.encoder;
    case 'cp863':
      return charset.cp863.encoder;
    case 'cp864':
      return charset.cp864.encoder;
    case 'cp865':
      return charset.cp865.encoder;
    case 'cp866':
      return charset.cp866.encoder;
    case 'cp869':
      return charset.cp869.encoder;
    case 'cp922':
      return charset.cp922.encoder;
    case 'cp1046':
      return charset.cp1046.encoder;
    case 'cp1124':
      return charset.cp1124.encoder;
    case 'cp1125':
      return charset.cp1125.encoder;
    case 'cp1129':
      return charset.cp1129.encoder;
    case 'cp1133':
      return charset.cp1133.encoder;
    case 'cp1161':
      return charset.cp1161.encoder;
    case 'cp1162':
      return charset.cp1162.encoder;
    case 'cp1163':
      return charset.cp1163.encoder;

    default:
      return null;
  }
}

/// Encodes the `String` [s] into bytes.
///
/// If an explicit [encoder] is provided, it is used first.
/// Otherwise, if [charset] is provided, a matching encoder is resolved
/// via `getCharsetEncoder(charset)`.
///
/// If encoding with the resolved encoder fails or no encoder is available,
/// the function falls back to [latin1]. If [latin1] encoding also fails,
/// it finally falls back to [utf8].
Uint8List encodeChars(String s, {CharsetEncoder? encoder, String? charset}) {
  encoder ??= getCharsetEncoder(charset);

  try {
    if (encoder != null) {
      var bs = encoder.convert(s);
      return bs is Uint8List ? bs : Uint8List.fromList(bs);
    }
  } catch (_) {}

  try {
    return latin1.encode(s);
  } catch (_) {
    return utf8.encode(s);
  }
}
