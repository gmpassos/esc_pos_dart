import 'dart:convert';
import 'dart:typed_data';

import 'package:charset/charset.dart' as charset;

typedef CharsetEncoder = Converter<String, List<int>>;

typedef CharsetDecoder = Converter<List<int>, String>;

/// Returns the [CharsetEncoder] of the charset [name] (see [getCharsetCodePage]).
CharsetEncoder? getCharsetEncoder(String? name) =>
    getCharsetCodePage(name)?.encoder;

/// Returns the [CharsetDecoder] of the charset [name] (see [getCharsetCodePage]).
CharsetDecoder? getCharsetDecoder(String? name) =>
    getCharsetCodePage(name)?.decoder;

/// Returns the charset name of a printer code page [codePageName]
/// (as defined in the `CapabilityProfile`, e.g. `CP437`, `CP1252`,
/// `ISO_8859-15`), or `null` if not supported.
String? codePageCharset(String? codePageName) {
  if (codePageName == null) return null;
  var name = codePageName.trim().toUpperCase();

  String? charsetName;
  if (RegExp(r'^CP(87\d|12\d\d)$').hasMatch(name)) {
    // Windows code pages (`CP1252` -> `windows1252`):
    charsetName = 'windows${name.substring(2)}';
  } else if (name.startsWith('CP')) {
    charsetName = name.toLowerCase();
  } else {
    charsetName = switch (name) {
      'ISO_8859-1' || 'ISO-8859-1' || 'LATIN1' => 'windows1252',
      'ISO_8859-2' || 'ISO-8859-2' => 'latin-2',
      'ISO_8859-7' || 'ISO-8859-7' => 'greek',
      'ISO_8859-15' || 'ISO-8859-15' => 'latin-9',
      _ => null,
    };
  }

  return getCharsetCodePage(charsetName) != null ? charsetName : null;
}

/// Returns the [charset.CodePage] of the charset [name]
/// (e.g. `cp437`, `cp850`, `windows1252`, `latin-2`), or `null` if unknown.
charset.CodePage? getCharsetCodePage(String? name) {
  if (name == null) return null;
  name = name.trim().toLowerCase();
  if (name.isEmpty) return null;

  switch (name) {
    case 'latin-2':
      return charset.latin2;
    case 'latin-3':
      return charset.latin3;
    case 'latin-4':
      return charset.latin4;
    case 'cyrillic':
      return charset.latinCyrillic;
    case 'arabic':
      return charset.latinArabic;
    case 'greek':
      return charset.latinGreek;
    case 'hebrew':
      return charset.latinHebrew;
    case 'latin-5':
      return charset.latin5;
    case 'latin-6':
      return charset.latin6;
    case 'tis620':
      return charset.latinThai;
    case 'latin-7':
      return charset.latin7;
    case 'latin-8':
      return charset.latin8;
    case 'latin-9':
      return charset.latin9;
    case 'latin-10':
      return charset.latin10;

    case 'windows874':
      return charset.windows874;
    case 'windows1250':
      return charset.windows1250;
    case 'windows1251':
      return charset.windows1251;
    case 'windows1252':
    case 'latin-1':
      return charset.windows1252;
    case 'windows1253':
      return charset.windows1253;
    case 'windows1254':
      return charset.windows1254;
    case 'windows1255':
      return charset.windows1255;
    case 'windows1256':
      return charset.windows1256;
    case 'windows1257':
      return charset.windows1257;
    case 'windows1258':
      return charset.windows1258;

    case 'cp437':
      return charset.cp437;
    case 'cp737':
      return charset.cp737;
    case 'cp775':
      return charset.cp775;
    case 'cp850':
      return charset.cp850;
    case 'cp852':
      return charset.cp852;
    case 'cp855':
      return charset.cp855;
    case 'cp856':
      return charset.cp856;
    case 'cp857':
      return charset.cp857;
    case 'cp858':
      return charset.cp858;
    case 'cp860':
      return charset.cp860;
    case 'cp861':
      return charset.cp861;
    case 'cp862':
      return charset.cp862;
    case 'cp863':
      return charset.cp863;
    case 'cp864':
      return charset.cp864;
    case 'cp865':
      return charset.cp865;
    case 'cp866':
      return charset.cp866;
    case 'cp869':
      return charset.cp869;
    case 'cp922':
      return charset.cp922;
    case 'cp1046':
      return charset.cp1046;
    case 'cp1124':
      return charset.cp1124;
    case 'cp1125':
      return charset.cp1125;
    case 'cp1129':
      return charset.cp1129;
    case 'cp1133':
      return charset.cp1133;
    case 'cp1161':
      return charset.cp1161;
    case 'cp1162':
      return charset.cp1162;
    case 'cp1163':
      return charset.cp1163;

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
