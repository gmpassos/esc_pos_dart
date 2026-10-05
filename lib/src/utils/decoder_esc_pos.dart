import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:image/image.dart' show Image, ColorRgb8, fill;

import 'barcode.dart';
import 'decoder.dart';
import 'generator_esc_pos.dart' show CharCodeTableEscPos;

/// How [DecoderEscPos] decodes text bytes into a [String].
enum EscPosTextDecoding {
  /// Decodes text as `latin1` (default).
  latin1,

  /// Decodes text with the character code table selected by `ESC t n`
  /// (see [CharCodeTableEscPos]), or [DecoderEscPos.defaultCodeTable].
  codeTable,
}

/// A warning produced while decoding (see [DecoderEscPos.warnings]).
class DecoderWarning {
  /// The absolute offset (in bytes) of the related command.
  final int offset;

  /// The warning code (`unknown_command`, `invalid_parameter`, `truncated`).
  final String code;

  final String message;

  const DecoderWarning(this.offset, this.code, this.message);

  Map<String, dynamic> toJson() =>
      {'offset': offset, 'code': code, 'message': message};

  @override
  String toString() => 'DecoderWarning{offset: $offset, $code: $message}';
}

class _NeedMore implements Exception {
  const _NeedMore();
}

class _InvalidCommand implements Exception {
  final String message;

  const _InvalidCommand(this.message);
}

/// A bounds-checked reader: throws [_NeedMore] when the data ends
/// in the middle of a command.
class _Reader {
  final List<int> buf;
  final int end;
  final bool isFinal;
  int pos;

  _Reader(this.buf, this.pos, {required this.isFinal}) : end = buf.length;

  bool get hasMore => pos < end;

  int get remaining => end - pos;

  void need(int n) {
    if (remaining < n) throw const _NeedMore();
  }

  int u8() {
    need(1);
    return buf[pos++];
  }

  int u16le() {
    need(2);
    var v = buf[pos] | (buf[pos + 1] << 8);
    pos += 2;
    return v;
  }

  int u32le() {
    need(4);
    var v = buf[pos] |
        (buf[pos + 1] << 8) |
        (buf[pos + 2] << 16) |
        (buf[pos + 3] << 24);
    pos += 4;
    return v;
  }

  List<int> take(int n) {
    need(n);
    var l = buf.sublist(pos, pos + n);
    pos += n;
    return l;
  }

  void skip(int n) {
    need(n);
    pos += n;
  }

  /// Returns the next byte without consuming it, or `null` at the end of
  /// the data (only when [isFinal], otherwise more data is needed).
  int? peek() {
    if (pos < end) return buf[pos];
    if (isFinal) return null;
    throw const _NeedMore();
  }

  /// Takes the bytes until [terminator] (consumed, not returned).
  List<int> takeUntil(int terminator, int maxLength) {
    for (var i = pos; i < end; ++i) {
      if (buf[i] == terminator) {
        var l = buf.sublist(pos, i);
        pos = i + 1;
        return l;
      }
      if (i - pos >= maxLength) {
        throw _InvalidCommand('Data without terminator ($terminator) '
            'in the first $maxLength bytes');
      }
    }
    throw const _NeedMore();
  }
}

/// Decodes ESC/POS commands from received print data,
/// extracting text, formatting, and control instructions.
///
/// - Batch: [decode] (the whole data).
/// - Streaming: [add] chunks, then [close].
/// - In [lenient] mode decoding never throws: unknown commands are emitted
///   as [CommandEscPosUnknown] and a truncated command at the end of the data
///   as [CommandEscPosTruncated] (see [warnings]).
///   Otherwise (strict, default) a [FormatException] is thrown.
class DecoderEscPos extends Decoder<CommandEscPos> {
  static const _esc = 0x1B;
  static const _gs = 0x1D;
  static const _fs = 0x1C;
  static const _dle = 0x10;
  static const _endJob = 0x0C;

  /// If `true` never throws (see [warnings]).
  final bool lenient;

  /// How text bytes are decoded.
  final EscPosTextDecoding textDecoding;

  /// The code table (`ESC t n`) used before any `ESC t` command,
  /// when [textDecoding] is [EscPosTextDecoding.codeTable].
  final int defaultCodeTable;

  /// If `true`, a text run with bytes `>= 0x80` that is valid UTF-8
  /// is decoded as UTF-8.
  final bool detectUtf8;

  /// The maximum length of a NUL-terminated barcode data (`GS k m d1...dk NUL`).
  final int maxBarcodeDataLength;

  DecoderEscPos({
    this.lenient = false,
    this.textDecoding = EscPosTextDecoding.latin1,
    this.defaultCodeTable = 0,
    this.detectUtf8 = false,
    this.maxBarcodeDataLength = 255,
  });

  final List<CommandEscPos> _output = [];

  /// All decoded commands since the last [reset].
  List<CommandEscPos> get commands => List.unmodifiable(_output);

  final List<DecoderWarning> _warnings = [];

  /// The decoding warnings since the last [reset].
  List<DecoderWarning> get warnings => List.unmodifiable(_warnings);

  /// Pending bytes of an incomplete command (streaming, see [add]).
  List<int> _buf = <int>[];
  int _bufPos = 0;
  int _bufOffset = 0;

  /// The total of bytes consumed (decoded) since the last [reset].
  int get consumedBytes => _bufOffset + _bufPos;

  /// The bytes of an incomplete command waiting for more data (see [add]).
  List<int> get pendingBytes => _buf.sublist(_bufPos);

  int? _codeTable;

  int? _qrModel;
  int? _qrSize;
  int? _qrCorrection;
  List<int>? _qrData;

  ({
    int widthDots,
    int height,
    int scaleX,
    int scaleY,
    List<int> data
  })? _graphics;

  @override
  void reset() {
    _output.clear();
    _warnings.clear();
    _textBuffer = null;
    _buf = <int>[];
    _bufPos = 0;
    _bufOffset = 0;
    _codeTable = null;
    _qrModel = null;
    _qrSize = null;
    _qrCorrection = null;
    _qrData = null;
    _graphics = null;
  }

  List<int>? _textBuffer;

  void _flushText() {
    var text = _textBuffer;
    if (text != null && text.isNotEmpty) {
      var s = _decodeText(text);
      _output.add(CommandEscPosText(s));
    }
    _textBuffer = null;
  }

  String _decodeText(List<int> bytes) {
    if (detectUtf8 && bytes.any((b) => b >= 0x80)) {
      try {
        return utf8.decode(bytes);
      } catch (_) {}
    }

    if (textDecoding == EscPosTextDecoding.codeTable) {
      var table = _codeTable ?? defaultCodeTable;
      var decoder = CharCodeTableEscPos.fromCode(table)?.decoder;
      if (decoder != null) {
        try {
          return decoder.convert(bytes);
        } catch (_) {}
      }
    }

    return latin1.decode(bytes);
  }

  /// Decodes the [serial] data (from [offset] with [length]) as a complete
  /// block of data: a command truncated at the end is handled as
  /// [CommandEscPosTruncated] ([lenient]) or throws a [FormatException].
  ///
  /// Returns the decoded commands.
  @override
  List<CommandEscPos> decode(List<int> serial, {int offset = 0, int? length}) {
    length ??= serial.length - offset;
    if (length <= 0) return [];

    var length0 = _output.length;

    _buf.addAll(offset == 0 && length == serial.length
        ? serial
        : serial.sublist(offset, offset + length));

    _process(isFinal: true);
    _flushText();

    return _output.sublist(length0);
  }

  /// Adds a [chunk] of a data stream. A command split between chunks is
  /// decoded when its remaining bytes are added. Call [close] at the end.
  ///
  /// Returns the decoded commands.
  List<CommandEscPos> add(List<int> chunk) {
    var length0 = _output.length;

    if (chunk.isNotEmpty) {
      _buf.addAll(chunk);
      _process(isFinal: false);
    }

    return _output.sublist(length0);
  }

  /// Ends a data stream (see [add]): flushes the pending text and handles
  /// an incomplete command at the end.
  ///
  /// Returns the decoded commands.
  List<CommandEscPos> close() {
    var length0 = _output.length;

    _process(isFinal: true);
    _flushText();

    return _output.sublist(length0);
  }

  void _process({required bool isFinal}) {
    var r = _Reader(_buf, _bufPos, isFinal: isFinal);

    while (r.hasMore) {
      var start = r.pos;
      try {
        _decodeNext(r, start);
      } on _NeedMore {
        if (!isFinal) {
          _bufPos = start;
          _compact();
          return;
        }
        _onTruncated(r, start);
      } on _InvalidCommand catch (e) {
        _onInvalid(r, start, e.message);
      }
    }

    _bufPos = r.pos;
    _compact();
  }

  void _compact() {
    if (_bufPos >= _buf.length) {
      _bufOffset += _buf.length;
      _buf = <int>[];
      _bufPos = 0;
    } else if (_bufPos > 4096 && _bufPos > _buf.length ~/ 2) {
      _bufOffset += _bufPos;
      _buf = _buf.sublist(_bufPos);
      _bufPos = 0;
    }
  }

  void _warn(int start, String code, String message) {
    _warnings.add(DecoderWarning(_bufOffset + start, code, message));
  }

  void _onTruncated(_Reader r, int start) {
    var bytes = _buf.sublist(start);
    var offset = _bufOffset + start;

    if (!lenient) {
      throw FormatException(
          'Truncated ESC/POS command at offset $offset: $bytes');
    }

    _flushText();
    _output.add(CommandEscPosTruncated(bytes));
    _warn(start, 'truncated', 'Truncated command: ${_hex(bytes)}');
    r.pos = r.end;
  }

  void _onInvalid(_Reader r, int start, String message) {
    if (!lenient) {
      throw FormatException(message);
    }

    // Skip only the command prefix and its code (the parameters are unknown):
    r.pos = start + 2 <= r.end ? start + 2 : r.end;

    var bytes = _buf.sublist(start, r.pos);
    _flushText();
    _output.add(CommandEscPosUnknown(bytes));
    _warn(start, 'invalid_command', '$message (${_hex(bytes)})');
  }

  void _unknown(String prefix, int c1) =>
      throw _InvalidCommand('Unknown $prefix char: $c1');

  void _decodeNext(_Reader r, int start) {
    var c0 = r.u8();

    switch (c0) {
      case _esc:
        _flushText();
        _decodeEsc(r);
      case _gs:
        _flushText();
        _decodeGs(r);
      case _fs:
        _flushText();
        _decodeFs(r);
      case _dle:
        _flushText();
        _decodeDle(r);
      case _endJob:
        _flushText();
        _output.add(const CommandEscPosEndJob());
      default:
        {
          // Ignorable control chars (except HT, LF, CR):
          if (lenient && c0 < 0x20 && c0 != 9 && c0 != 10 && c0 != 13) {
            return;
          }
          var text = _textBuffer ??= [];
          text.add(c0);
        }
    }
  }

  void _generic(String name, [List? parameters]) =>
      _output.add(CommandEscPosGeneric(name, parameters: parameters));

  void _decodeEsc(_Reader r) {
    var c1 = r.u8();

    switch (c1) {
      case 0x40: // ESC @
        _codeTable = null;
        _output.add(const CommandEscPosReset());
      case 0x74: // ESC t n
        var n = r.u8();
        _codeTable = n;
        _output.add(CommandEscPosTable(n));
      case 0x4D: // ESC M n
        var n = r.u8();
        _output.add(CommandEscPosFont(
          a: _eq0(n) ? true : null,
          b: _eq1(n) || n == 2 || n == 0x32 ? true : null,
        ));
      case 0x61: // ESC a n
        var n = r.u8() & 0x03;
        _output.add(CommandEscPosAlign(
          left: n == 0 ? true : null,
          center: n == 1 ? true : null,
          right: n == 2 ? true : null,
        ));
      case 0x45: // ESC E n
        _output.add(CommandEscPosBold(on: (r.u8() & 0x01) == 1));
      case 0x47: // ESC G n
        _output.add(CommandEscPosDoubleStrike(on: (r.u8() & 0x01) == 1));
      case 0x2D: // ESC - n
        _output.add(CommandEscPosUnderline(r.u8() & 0x03));
      case 0x21: // ESC ! n
        _output.add(CommandEscPosPrintMode(r.u8()));
      case 0x56: // ESC V n
        _output.add(CommandEscPosTurn90(on: (r.u8() & 0x03) != 0));
      case 0x7B: // ESC { n
        _output.add(CommandEscPosUpsideDown(on: (r.u8() & 0x01) == 1));
      case 0x64: // ESC d n
        _output.add(CommandEscPosFeed(r.u8()));
      case 0x4A: // ESC J n
        _output.add(CommandEscPosFeedDots(r.u8()));
      case 0x4B: // ESC K n
        _generic('reverse_feed_dots', [r.u8()]);
      case 0x65: // ESC e n
        _generic('reverse_feed', [r.u8()]);
      case 0x33: // ESC 3 n
        _generic('lines_spacing', [r.u8()]);
      case 0x32: // ESC 2
        _generic('lines_spacing:1/6');
      case 0x30: // ESC 0
        _generic('lines_spacing:1/8');
      case 0x24: // ESC $ nL nH
        var nL = r.u8();
        var nH = r.u8();
        _generic('absolute_pos', [nL, nH]);
      case 0x5C: // ESC \ nL nH
        var nL = r.u8();
        var nH = r.u8();
        _generic('relative_pos', [nL, nH]);
      case 0x2A: // ESC * m nL nH d1...dk
        _decodeBitImage(r);
      case 0x42: // ESC B n t
        var n = r.u8();
        var t = r.u8();
        _output.add(CommandEscPosBeep(n, t));
      case 0x70: // ESC p m t1 t2
        var m = r.u8();
        var t1 = r.u8();
        var t2 = r.u8();
        _output.add(CommandEscPosDrawer(m & 0x01, t1, t2));
      case 0x52: // ESC R n
        _output.add(CommandEscPosIntlCharset(r.u8()));
      case 0x63: // ESC c x n
        var x = r.u8();
        var n = r.u8();
        _generic('esc_c', [x, n]);
      case 0x75: // ESC u n
        _output.add(CommandEscPosStatusRequest('esc_u', r.u8()));
      case 0x76: // ESC v
        _output.add(CommandEscPosStatusRequest('esc_v', 0));
      case 0x20: // ESC SP n
        _generic('right_spacing', [r.u8()]);
      case 0x25: // ESC % n
        _generic('user_charset', [r.u8()]);
      case 0x3D: // ESC = n
        _generic('peripheral', [r.u8()]);
      case 0x3F: // ESC ? n
        _generic('cancel_user_char', [r.u8()]);
      case 0x55: // ESC U n
        _generic('unidirectional', [r.u8()]);
      case 0x54: // ESC T n
        _generic('print_direction', [r.u8()]);
      case 0x72: // ESC r n
        _generic('color', [r.u8()]);
      case 0x44: // ESC D n1...nk NUL
        _generic('tab_positions', [r.takeUntil(0, 32)]);
      case 0x4C: // ESC L
        _generic('page_mode');
      case 0x53: // ESC S
        _generic('standard_mode');
      case 0x0C: // ESC FF
        _generic('print_page');
      case 0x3C: // ESC <
        _generic('return_home');
      case 0x57: // ESC W xL xH yL yH dxL dxH dyL dyH
        _generic('page_area', [r.take(8)]);
      case 0x69: // ESC i
      case 0x6D: // ESC m
        _output.add(CommandEscPosCut(full: false));
      case 0x26: // ESC & y c1 c2 [x d1...d(y*x)]...
        var y = r.u8();
        var c1 = r.u8();
        var c2 = r.u8();
        for (var c = c1; c <= c2; ++c) {
          var x = r.u8();
          r.skip(y * x);
        }
        _generic('user_chars', [y, c1, c2]);
      case 0x28: // ESC ( fn pL pH d...
        var fn = r.u8();
        var len = r.u16le();
        var data = r.take(len);
        _generic('esc(${String.fromCharCode(fn)}', [data]);
      default:
        _unknown('ESC', c1);
    }
  }

  void _decodeBitImage(_Reader r) {
    /*
    | m  | Mode                   | Vertical NO. of Dots | Vertical Direction Dot Density | Horizontal Dot Density | Direction Number of Data (K) |
    |----|------------------------|----------------------|--------------------------------|------------------------|------------------------------|
    | 0  | 8-dot single-density   | 8                    | 60 DPI                         | 90 DPI                 | nL + nH × 256                |
    | 1  | 8-dot double-density   | 8                    | 60 DPI                         | 180 DPI                | nL + nH × 256                |
    | 32 | 24-dot single-density  | 24                   | 180 DPI                        | 90 DPI                 | (nL + nH × 256) × 3          |
    | 33 | 24-dot double-density  | 24                   | 180 DPI                        | 180 DPI                | (nL + nH × 256) × 3          |
    [dpi : dots per 25.4 mm]
     */
    var mode = r.u8();
    var nL = r.u8();
    var nH = r.u8();

    var k = nL + (nH * 256);

    int dataLength;
    if (mode == 0 || mode == 1) {
      dataLength = k;
    } else if (mode == 32 || mode == 33) {
      dataLength = k * 3;
    } else {
      throw _InvalidCommand('Invalid bit image mode: $mode');
    }

    var imgData = r.take(dataLength);

    var lineBreak = false;

    var nextByte = r.peek();
    if (nextByte == 13) {
      lineBreak = true;
      r.skip(1);
      nextByte = r.peek();
    }

    if (nextByte == 10) {
      lineBreak = true;
      r.skip(1);
    }

    _output.add(CommandEscPosBitImage(
      mode,
      nL,
      nH,
      imgData,
      lineBreak: lineBreak,
    ));
  }

  void _decodeGs(_Reader r) {
    var c1 = r.u8();

    switch (c1) {
      case 0x56: // GS V m [n]
        var m = r.u8();
        switch (m) {
          case 0 || 0x30:
            _output.add(CommandEscPosCut(full: true));
          case 1 || 0x31:
            _output.add(CommandEscPosCut(full: false));
          case 65 || 97 || 103:
            _output.add(CommandEscPosCut(full: true, feed: r.u8()));
          case 66 || 98 || 104:
            _output.add(CommandEscPosCut(full: false, feed: r.u8()));
          default:
            throw _InvalidCommand('Invalid cut parameter: $m');
        }
      case 0x21: // GS ! n
        var n = r.u8();
        _output.add(CommandEscPosFontSize(
          widthSize: ((n >> 4) & 0x07) + 1,
          heightSize: (n & 0x07) + 1,
        ));
      case 0x42: // GS B n
        _output.add(CommandEscPosReverse(on: (r.u8() & 0x01) == 1));
      case 0x76: // GS v 0 m xL xH yL yH d1...dk
        var c2 = r.u8();
        if (c2 != 0x30) {
          throw _InvalidCommand('Invalid GS v char: $c2');
        }
        var m = r.u8();
        var widthBytes = r.u16le();
        var height = r.u16le();
        var data = r.take(widthBytes * height);
        _output
            .add(CommandEscPosRasterImage(m & 0x03, widthBytes, height, data));
      case 0x28: // GS ( X pL pH d...
        var fn = r.u8();
        var len = r.u16le();
        var data = r.take(len);
        switch (fn) {
          case 0x4C: // GS ( L
            _decodeGraphics(data);
          case 0x6B: // GS ( k
            _decode2DCode(data);
          default:
            _generic('gs(${String.fromCharCode(fn)}', [len]);
        }
      case 0x38: // GS 8 L p1 p2 p3 p4 d...
        var fn = r.u8();
        var len = r.u32le();
        var data = r.take(len);
        if (fn == 0x4C) {
          _decodeGraphics(data);
        } else {
          _generic('gs8${String.fromCharCode(fn)}', [len]);
        }
      case 0x6B: // GS k m ...
        var m = r.u8();
        List<int> data;
        if (m <= 6) {
          data = r.takeUntil(0, maxBarcodeDataLength);
        } else if (m >= 65 && m <= 79) {
          var n = r.u8();
          data = r.take(n);
        } else {
          throw _InvalidCommand('Invalid barcode type: $m');
        }
        _output.add(CommandEscPosBarcode(m, data));
      case 0x48: // GS H n
        _output.add(CommandEscPosBarcodeSetting('hri_position', r.u8()));
      case 0x66: // GS f n
        _output.add(CommandEscPosBarcodeSetting('hri_font', r.u8()));
      case 0x68: // GS h n
        _output.add(CommandEscPosBarcodeSetting('height', r.u8()));
      case 0x77: // GS w n
        _output.add(CommandEscPosBarcodeSetting('width', r.u8()));
      case 0x61: // GS a n
        _output.add(CommandEscPosStatusRequest('asb', r.u8()));
      case 0x72: // GS r n
        _output.add(CommandEscPosStatusRequest('gs_r', r.u8()));
      case 0x49: // GS I n
        _output.add(CommandEscPosStatusRequest('gs_i', r.u8()));
      case 0x24: // GS $ nL nH
        _generic('absolute_vertical_pos', r.take(2));
      case 0x5C: // GS \ nL nH
        _generic('relative_vertical_pos', r.take(2));
      case 0x4C: // GS L nL nH
        _generic('left_margin', r.take(2));
      case 0x57: // GS W nL nH
        _generic('print_width', r.take(2));
      case 0x50: // GS P x y
        _generic('motion_units', r.take(2));
      case 0x2A: // GS * x y d1...d(x*y*8)
        var x = r.u8();
        var y = r.u8();
        r.skip(x * y * 8);
        _generic('define_downloaded_image', [x, y]);
      case 0x2F: // GS / m
        _generic('print_downloaded_image', [r.u8()]);
      case 0x3A: // GS :
        _generic('macro');
      case 0x45: // GS E n
        _generic('print_density', [r.u8()]);
      case 0x54: // GS T n
        _generic('print_position_line_start', [r.u8()]);
      case 0x62: // GS b n
        _generic('smoothing', [r.u8()]);
      case 0x7C: // GS | n
        _generic('print_density', [r.u8()]);
      case 0x5E: // GS ^ r t m
        _generic('execute_macro', r.take(3));
      case 0x63: // GS c
        _generic('print_counter');
      case 0x67: // GS g 0 m nL nH / GS g 2 m nL nH
        _generic('maintenance_counter', r.take(4));
      case 0x7A: // GS z 0 t1 t2
        _generic('online_recovery_wait', r.take(3));
      default:
        _unknown('GS', c1);
    }
  }

  /// `GS ( L` / `GS 8 L`: graphics data.
  void _decodeGraphics(List<int> data) {
    if (data.length < 2) {
      _generic('graphics', [data]);
      return;
    }

    var fn = data[1];

    switch (fn) {
      case 0x70 when data.length >= 10: // fn 112: store raster graphics data
        var scaleX = data[3] == 2 ? 2 : 1;
        var scaleY = data[4] == 2 ? 2 : 1;
        var widthDots = data[6] | (data[7] << 8);
        var height = data[8] | (data[9] << 8);
        var imageData = data.sublist(10);

        // The spec defines `xL xH` in dots, but some generators (including
        // `esc_pos_dart` < 1.4.0) send it in bytes: use the data length.
        if (height > 0 && imageData.length % height == 0) {
          widthDots = (imageData.length ~/ height) * 8;
        }

        _graphics = (
          widthDots: widthDots,
          height: height,
          scaleX: scaleX,
          scaleY: scaleY,
          data: imageData,
        );
      case 0x32 || 0x02: // fn 50 (or 2): print the stored graphics data
        var graphics = _graphics;
        if (graphics != null) {
          var mode =
              (graphics.scaleX == 2 ? 1 : 0) | (graphics.scaleY == 2 ? 2 : 0);
          var widthBytes = (graphics.widthDots + 7) ~/ 8;
          _output.add(CommandEscPosRasterImage(
              mode, widthBytes, graphics.height, graphics.data));
        }
      default:
        _generic('graphics', [fn]);
    }
  }

  /// `GS ( k`: 2D codes (QR Code: `cn = 49`).
  void _decode2DCode(List<int> data) {
    if (data.length < 2) {
      _generic('code_2d', [data]);
      return;
    }

    var cn = data[0];
    var fn = data[1];

    if (cn != 0x31) {
      _generic('code_2d', [cn, fn]);
      return;
    }

    switch (fn) {
      case 0x41 when data.length >= 3: // fn 65: model
        _qrModel = data[2];
      case 0x43 when data.length >= 3: // fn 67: module size
        _qrSize = data[2];
      case 0x45 when data.length >= 3: // fn 69: error correction level
        _qrCorrection = data[2];
      case 0x50: // fn 80: store the data
        _qrData = data.length > 3 ? data.sublist(3) : <int>[];
      case 0x51: // fn 81: print the stored data
        _output.add(CommandEscPosQRCode(
          _decodeBytes(_qrData ?? const []),
          size: _qrSize,
          correction: _qrCorrection,
          model: _qrModel,
        ));
      default:
        _generic('qrcode_function', [fn]);
    }
  }

  void _decodeFs(_Reader r) {
    var c1 = r.u8();

    switch (c1) {
      case 0x26: // FS &
        _output.add(CommandEscPosKanji(on: true));
      case 0x2E: // FS .
        _output.add(CommandEscPosKanji(on: false));
      case 0x21: // FS ! n
        _generic('kanji_print_mode', [r.u8()]);
      case 0x2D: // FS - n
        _generic('kanji_underline', [r.u8()]);
      case 0x57: // FS W n
        _generic('kanji_quadruple', [r.u8()]);
      case 0x43: // FS C n
        _generic('kanji_code_system', [r.u8()]);
      case 0x53: // FS S n1 n2
        _generic('kanji_spacing', r.take(2));
      case 0x3F: // FS ? c1 c2
        _generic('cancel_user_kanji', r.take(2));
      case 0x70: // FS p n m
        _generic('nv_image_print', r.take(2));
      case 0x32: // FS 2 c1 c2 d1...d72
        r.skip(74);
        _generic('define_user_kanji');
      case 0x28: // FS ( X pL pH d...
        var fn = r.u8();
        var len = r.u16le();
        r.skip(len);
        _generic('fs(${String.fromCharCode(fn)}', [len]);
      case 0x71: // FS q n [xL xH yL yH d1...dk]...
        var n = r.u8();
        for (var i = 0; i < n; ++i) {
          var x = r.u16le();
          var y = r.u16le();
          r.skip(x * y * 8);
        }
        _generic('nv_image_define', [n]);
      default:
        _unknown('FS', c1);
    }
  }

  void _decodeDle(_Reader r) {
    var c1 = r.u8();

    switch (c1) {
      case 0x04: // DLE EOT n [a]
        var n = r.u8();
        if (n == 7 || n == 8) {
          var a = r.u8();
          _output.add(CommandEscPosStatusRequest('dle_eot', n, a));
        } else {
          _output.add(CommandEscPosStatusRequest('dle_eot', n));
        }
      case 0x05: // DLE ENQ n
        _generic('dle_enq', [r.u8()]);
      case 0x14: // DLE DC4 fn ...
        var fn = r.u8();
        switch (fn) {
          case 1: // DLE DC4 1 m t: generate pulse
            var m = r.u8();
            var t = r.u8();
            _output.add(CommandEscPosDrawer(m & 0x01, t, 0));
          case 2 || 3:
            _generic('dle_dc4', [fn, ...r.take(2)]);
          case 7:
            _generic('dle_dc4', [fn, r.u8()]);
          case 8:
            _generic('dle_dc4', [fn, ...r.take(7)]);
          default:
            throw _InvalidCommand('Invalid DLE DC4 function: $fn');
        }
      default:
        _unknown('DLE', c1);
    }
  }
}

String _decodeBytes(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } catch (_) {
    return latin1.decode(bytes);
  }
}

String _hex(List<int> bytes) => bytes
    .take(16)
    .map((b) => b.toRadixString(16).padLeft(2, '0'))
    .join(' ')
    .toUpperCase();

abstract class CommandEscPos extends Command {
  List get parameters;

  const CommandEscPos(super.name);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CommandEscPos &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          DeepCollectionEquality().equals(parameters, other.parameters);

  @override
  int get hashCode => name.hashCode ^ DeepCollectionEquality().hash(parameters);

  @override
  String toString() =>
      'CommandEscPos($name)${parameters.isNotEmpty ? '$parameters' : ''}';

  static List<CommandEscPos> fromJsonList(List jsonList) =>
      jsonList.whereType<Map>().map(CommandEscPos.fromJson).toList();

  factory CommandEscPos.fromJson(Map json) {
    var name = json["name"];

    switch (name) {
      case 'reset':
        return const CommandEscPosReset();
      case 'table':
        return CommandEscPosTable.fromJson(json);
      case 'font':
        return CommandEscPosFont.fromJson(json);
      case 'font-size':
        return CommandEscPosFontSize.fromJson(json);
      case 'align':
        return CommandEscPosAlign.fromJson(json);
      case 'bold':
        return CommandEscPosBold.fromJson(json);
      case 'feed':
        return CommandEscPosFeed.fromJson(json);
      case 'text':
        return CommandEscPosText.fromJson(json);
      case 'bit_image':
        return CommandEscPosBitImage.fromJson(json);
      case 'cut':
        return CommandEscPosCut.fromJson(json);
      case 'end_job':
        return const CommandEscPosEndJob();
      case 'underline':
        return CommandEscPosUnderline.fromJson(json);
      case 'reverse':
        return CommandEscPosReverse.fromJson(json);
      case 'turn90':
        return CommandEscPosTurn90.fromJson(json);
      case 'upside_down':
        return CommandEscPosUpsideDown.fromJson(json);
      case 'double_strike':
        return CommandEscPosDoubleStrike.fromJson(json);
      case 'print_mode':
        return CommandEscPosPrintMode.fromJson(json);
      case 'feed_dots':
        return CommandEscPosFeedDots.fromJson(json);
      case 'raster_image':
        return CommandEscPosRasterImage.fromJson(json);
      case 'barcode':
        return CommandEscPosBarcode.fromJson(json);
      case 'barcode_setting':
        return CommandEscPosBarcodeSetting.fromJson(json);
      case 'qrcode':
        return CommandEscPosQRCode.fromJson(json);
      case 'drawer':
        return CommandEscPosDrawer.fromJson(json);
      case 'beep':
        return CommandEscPosBeep.fromJson(json);
      case 'kanji':
        return CommandEscPosKanji.fromJson(json);
      case 'intl_charset':
        return CommandEscPosIntlCharset.fromJson(json);
      case 'status_request':
        return CommandEscPosStatusRequest.fromJson(json);
      case 'unknown':
        return CommandEscPosUnknown.fromJson(json);
      case 'truncated':
        return CommandEscPosTruncated.fromJson(json);
      default:
        {
          var parameters = json["parameters"] as List?;
          return CommandEscPosGeneric(name, parameters: parameters);
        }
    }
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      "name": name,
      if (parameters.isNotEmpty) "parameters": _parameterToJson(parameters),
    };
  }
}

Object? _parameterToJson(Object? o) {
  if (o == null) return null;

  if (o is num || o is String || o is bool) {
    return o;
  } else if (o is List) {
    return o.map(_parameterToJson).toList();
  } else if (o is Map) {
    return o.map((k, v) => MapEntry('$k', _parameterToJson(v)));
  } else {
    return json.encode(o);
  }
}

List? _jsonParameters(Map json) => json["parameters"] as List?;

int _jsonInt(List? parameters, int index, [int def = 0]) =>
    (parameters != null && parameters.length > index
        ? (parameters[index] as num?)?.toInt()
        : null) ??
    def;

List<int> _jsonBytes(List? parameters, int index) =>
    parameters != null && parameters.length > index
        ? (parameters[index] as List)
            .whereType<num>()
            .map((e) => e.toInt())
            .toList()
        : <int>[];

bool _jsonOn(List? parameters, [int index = 0]) =>
    parameters != null && parameters.length > index
        ? parameters[index] == 'on'
        : false;

class CommandEscPosGeneric extends CommandEscPos {
  @override
  final List parameters;

  CommandEscPosGeneric(super.name, {List? parameters})
      : parameters = parameters ?? [];
}

class CommandEscPosReset extends CommandEscPos {
  const CommandEscPosReset() : super('reset');

  @override
  List get parameters => const [];
}

class CommandEscPosTable extends CommandEscPos {
  final int id;

  CommandEscPosTable(this.id) : super('table');

  @override
  List get parameters => [id];

  factory CommandEscPosTable.fromJson(Map json) {
    var parameters = json["parameters"] as List?;
    var id = (parameters?[0] as int?) ?? 0;
    return CommandEscPosTable(id);
  }
}

class CommandEscPosFont extends CommandEscPos {
  final String type;

  CommandEscPosFont({bool? a, bool? b})
      : type = a != null && a ? 'a' : (b != null && b ? 'b' : 'a'),
        super('font');

  @override
  List get parameters => [type];

  factory CommandEscPosFont.fromJson(Map json) {
    var parameters = json["parameters"] as List?;
    var p = parameters?[0] as String?;
    return CommandEscPosFont(a: p == 'a', b: p == 'b');
  }
}

class CommandEscPosFontSize extends CommandEscPos {
  final int widthSize;
  final int heightSize;

  CommandEscPosFontSize({int? widthSize, int? heightSize})
      : widthSize = (widthSize ?? 1).clamp(1, 8),
        heightSize = (heightSize ?? 1).clamp(1, 8),
        super('font-size');

  @override
  List get parameters => [widthSize, heightSize];

  factory CommandEscPosFontSize.fromJson(Map json) {
    var parameters = json["parameters"] as List?;
    var w = parameters?[0] as int?;
    var h = parameters?[1] as int?;
    return CommandEscPosFontSize(widthSize: w, heightSize: h);
  }
}

class CommandEscPosAlign extends CommandEscPos {
  final String type;

  CommandEscPosAlign({bool? left, bool? center, bool? right})
      : type = left != null && left
            ? 'left'
            : (center != null && center
                ? 'center'
                : (right != null && right ? 'right' : 'left')),
        super('align');

  @override
  List get parameters => [type];

  factory CommandEscPosAlign.fromJson(Map json) {
    var parameters = json["parameters"] as List?;
    var p = parameters?[0] as String?;
    return CommandEscPosAlign(
        left: p == 'left', center: p == 'center', right: p == 'right');
  }
}

class CommandEscPosBold extends CommandEscPos {
  final bool on;

  CommandEscPosBold({required this.on}) : super('bold');

  @override
  List get parameters => [on ? 'on' : 'off'];

  factory CommandEscPosBold.fromJson(Map json) {
    var parameters = json["parameters"] as List?;
    var p = parameters?[0] as String?;
    return CommandEscPosBold(on: p == 'on');
  }
}

class CommandEscPosFeed extends CommandEscPos {
  final int n;

  CommandEscPosFeed(this.n)
      : super(
          'feed',
        );

  @override
  List get parameters => [n];

  factory CommandEscPosFeed.fromJson(Map json) {
    var parameters = json["parameters"] as List?;
    var p = parameters![0] as int;
    return CommandEscPosFeed(p);
  }
}

class CommandEscPosText extends CommandEscPos {
  final String text;

  CommandEscPosText(this.text) : super('text');

  @override
  List get parameters => [text];

  factory CommandEscPosText.fromJson(Map json) {
    var parameters = json["parameters"] as List?;
    var p = parameters![0] as String;
    return CommandEscPosText(p);
  }
}

/// `ESC *`: a column format bit image stripe (8 or 24 dots high).
class CommandEscPosBitImage extends CommandEscPos {
  final int mode;
  final int nL;
  final int nH;

  final List<int> data;

  final bool lineBreak;

  CommandEscPosBitImage(this.mode, this.nL, this.nH, this.data,
      {this.lineBreak = false})
      : super('bit_image');

  @override
  List get parameters => [mode, nL, nH, data, lineBreak];

  factory CommandEscPosBitImage.fromJson(Map json) {
    var parameters = json["parameters"] as List?;

    var mode = parameters![0] as int;

    var nL = parameters[1] as int;
    var nH = parameters[2] as int;

    var dataList = parameters[3] as List;
    var data = dataList.whereType<num>().map((e) => e.toInt()).toList();

    var lineBreak = parameters.length > 4 ? parameters[4] as bool : false;

    return CommandEscPosBitImage(mode, nL, nH, data, lineBreak: lineBreak);
  }

  /// The number of columns (dots).
  int get columns => nL + (nH * 256);

  /// Returns `true` for the 24-dot modes (`32`, `33`).
  bool get is24Dots => mode == 32 || mode == 33;

  /// The height of this stripe (in dots).
  int get dotsHeight => is24Dots ? 24 : 8;

  /// The horizontal scale to the 180 DPI resolution (single-density modes are 90 DPI).
  int get scaleX => mode == 0 || mode == 32 ? 2 : 1;

  /// The vertical scale to the 180 DPI resolution (8-dot modes are 60 DPI).
  int get scaleY => mode == 0 || mode == 1 ? 3 : 1;

  /// Converts this stripe to an [Image] (black dots on white),
  /// scaled to the printer resolution (see [scaleX] and [scaleY]).
  Image toImage() {
    var k = columns;
    var bytesPerColumn = is24Dots ? 3 : 1;
    var scaleX = this.scaleX;
    var scaleY = this.scaleY;

    var width = k * scaleX;
    var height = dotsHeight * scaleY;

    var image = Image(
        width: width > 0 ? width : 1,
        height: height > 0 ? height : 1,
        numChannels: 1);
    fill(image, color: ColorRgb8(255, 255, 255));

    for (var col = 0; col < k; ++col) {
      for (var b = 0; b < bytesPerColumn; ++b) {
        var i = col * bytesPerColumn + b;
        if (i >= data.length) break;
        var byte = data[i];
        if (byte == 0) continue;

        for (var bit = 0; bit < 8; ++bit) {
          if (byte & (0x80 >> bit) == 0) continue;
          var y = (b * 8 + bit) * scaleY;
          var x = col * scaleX;
          for (var dy = 0; dy < scaleY; ++dy) {
            for (var dx = 0; dx < scaleX; ++dx) {
              image.setPixelRgb(x + dx, y + dy, 0, 0, 0);
            }
          }
        }
      }
    }

    return image;
  }
}

/// `GS v 0` / `GS ( L` / `GS 8 L`: a raster bit image.
class CommandEscPosRasterImage extends CommandEscPos {
  /// The raster mode: bit 0 = double width, bit 1 = double height.
  final int mode;

  /// The width of each line in bytes (8 dots per byte).
  final int widthBytes;

  /// The height in dots (lines).
  final int height;

  final List<int> data;

  CommandEscPosRasterImage(this.mode, this.widthBytes, this.height, this.data)
      : super('raster_image');

  @override
  List get parameters => [mode, widthBytes, height, data];

  factory CommandEscPosRasterImage.fromJson(Map json) {
    var parameters = _jsonParameters(json);
    return CommandEscPosRasterImage(
      _jsonInt(parameters, 0),
      _jsonInt(parameters, 1),
      _jsonInt(parameters, 2),
      _jsonBytes(parameters, 3),
    );
  }

  /// The width in dots.
  int get widthDots => widthBytes * 8;

  int get scaleX => (mode & 0x01) != 0 ? 2 : 1;

  int get scaleY => (mode & 0x02) != 0 ? 2 : 1;

  /// Converts to an [Image] (black dots on white), scaled by the [mode].
  Image toImage() {
    var scaleX = this.scaleX;
    var scaleY = this.scaleY;

    var width = widthDots * scaleX;
    var height = this.height * scaleY;

    var image = Image(
        width: width > 0 ? width : 1,
        height: height > 0 ? height : 1,
        numChannels: 1);
    fill(image, color: ColorRgb8(255, 255, 255));

    for (var row = 0; row < this.height; ++row) {
      for (var xb = 0; xb < widthBytes; ++xb) {
        var i = row * widthBytes + xb;
        if (i >= data.length) break;
        var byte = data[i];
        if (byte == 0) continue;

        for (var bit = 0; bit < 8; ++bit) {
          if (byte & (0x80 >> bit) == 0) continue;
          var x = (xb * 8 + bit) * scaleX;
          var y = row * scaleY;
          for (var dy = 0; dy < scaleY; ++dy) {
            for (var dx = 0; dx < scaleX; ++dx) {
              image.setPixelRgb(x + dx, y + dy, 0, 0, 0);
            }
          }
        }
      }
    }

    return image;
  }
}

class CommandEscPosCut extends CommandEscPos {
  final bool full;

  /// The feed (in motion units) before the cut (`GS V m n`), if defined.
  final int? feed;

  CommandEscPosCut({required this.full, this.feed}) : super('cut');

  @override
  List get parameters => [full ? 'full' : 'partial', if (feed != null) feed];

  factory CommandEscPosCut.fromJson(Map json) {
    var parameters = json["parameters"] as List?;
    var p = parameters![0] as String;
    var feed = parameters.length > 1 ? parameters[1] as int? : null;
    return CommandEscPosCut(full: p == 'full', feed: feed);
  }
}

class CommandEscPosEndJob extends CommandEscPos {
  const CommandEscPosEndJob() : super('end_job');

  @override
  List get parameters => const [];
}

/// `ESC - n`: underline mode (`0` off, `1` 1-dot, `2` 2-dots).
class CommandEscPosUnderline extends CommandEscPos {
  final int mode;

  CommandEscPosUnderline(this.mode) : super('underline');

  bool get on => mode > 0;

  @override
  List get parameters => [mode];

  factory CommandEscPosUnderline.fromJson(Map json) =>
      CommandEscPosUnderline(_jsonInt(_jsonParameters(json), 0));
}

/// `GS B n`: white/black reverse print mode.
class CommandEscPosReverse extends CommandEscPos {
  final bool on;

  CommandEscPosReverse({required this.on}) : super('reverse');

  @override
  List get parameters => [on ? 'on' : 'off'];

  factory CommandEscPosReverse.fromJson(Map json) =>
      CommandEscPosReverse(on: _jsonOn(_jsonParameters(json)));
}

/// `ESC V n`: 90° clockwise rotation mode.
class CommandEscPosTurn90 extends CommandEscPos {
  final bool on;

  CommandEscPosTurn90({required this.on}) : super('turn90');

  @override
  List get parameters => [on ? 'on' : 'off'];

  factory CommandEscPosTurn90.fromJson(Map json) =>
      CommandEscPosTurn90(on: _jsonOn(_jsonParameters(json)));
}

/// `ESC { n`: upside-down print mode.
class CommandEscPosUpsideDown extends CommandEscPos {
  final bool on;

  CommandEscPosUpsideDown({required this.on}) : super('upside_down');

  @override
  List get parameters => [on ? 'on' : 'off'];

  factory CommandEscPosUpsideDown.fromJson(Map json) =>
      CommandEscPosUpsideDown(on: _jsonOn(_jsonParameters(json)));
}

/// `ESC G n`: double-strike mode (printed as bold).
class CommandEscPosDoubleStrike extends CommandEscPos {
  final bool on;

  CommandEscPosDoubleStrike({required this.on}) : super('double_strike');

  @override
  List get parameters => [on ? 'on' : 'off'];

  factory CommandEscPosDoubleStrike.fromJson(Map json) =>
      CommandEscPosDoubleStrike(on: _jsonOn(_jsonParameters(json)));
}

/// `ESC ! n`: select print modes.
class CommandEscPosPrintMode extends CommandEscPos {
  final int n;

  CommandEscPosPrintMode(this.n) : super('print_mode');

  bool get fontB => (n & 0x01) != 0;

  bool get bold => (n & 0x08) != 0;

  bool get doubleHeight => (n & 0x10) != 0;

  bool get doubleWidth => (n & 0x20) != 0;

  bool get underline => (n & 0x80) != 0;

  @override
  List get parameters => [n];

  factory CommandEscPosPrintMode.fromJson(Map json) =>
      CommandEscPosPrintMode(_jsonInt(_jsonParameters(json), 0));
}

/// `ESC J n`: print and feed paper `n` motion units (dots).
class CommandEscPosFeedDots extends CommandEscPos {
  final int n;

  CommandEscPosFeedDots(this.n) : super('feed_dots');

  @override
  List get parameters => [n];

  factory CommandEscPosFeedDots.fromJson(Map json) =>
      CommandEscPosFeedDots(_jsonInt(_jsonParameters(json), 0));
}

/// `GS k`: print a barcode.
class CommandEscPosBarcode extends CommandEscPos {
  /// The `GS k m` type.
  final int type;

  final List<int> data;

  CommandEscPosBarcode(this.type, this.data) : super('barcode');

  BarcodeType get barcodeType => BarcodeType.fromValue(type);

  /// The [barcodeType] name.
  String get typeName => barcodeType.name;

  /// The [data] as a `String`.
  String get dataString => latin1.decode(data);

  @override
  List get parameters => [type, data];

  factory CommandEscPosBarcode.fromJson(Map json) {
    var parameters = _jsonParameters(json);
    return CommandEscPosBarcode(
        _jsonInt(parameters, 0), _jsonBytes(parameters, 1));
  }
}

/// `GS H`/`GS f`/`GS h`/`GS w`: barcode settings
/// (`hri_position`, `hri_font`, `height`, `width`).
class CommandEscPosBarcodeSetting extends CommandEscPos {
  final String setting;
  final int n;

  CommandEscPosBarcodeSetting(this.setting, this.n) : super('barcode_setting');

  @override
  List get parameters => [setting, n];

  factory CommandEscPosBarcodeSetting.fromJson(Map json) {
    var parameters = _jsonParameters(json);
    return CommandEscPosBarcodeSetting(
        parameters![0] as String, _jsonInt(parameters, 1));
  }
}

/// `GS ( k`: print a QR Code (with the stored data and settings).
class CommandEscPosQRCode extends CommandEscPos {
  final String data;

  /// The module size (`fn 67`).
  final int? size;

  /// The error correction level (`fn 69`: `48` L, `49` M, `50` Q, `51` H).
  final int? correction;

  /// The model (`fn 65`).
  final int? model;

  CommandEscPosQRCode(this.data, {this.size, this.correction, this.model})
      : super('qrcode');

  @override
  List get parameters => [data, size, correction, model];

  factory CommandEscPosQRCode.fromJson(Map json) {
    var parameters = _jsonParameters(json)!;
    int? opt(int i) =>
        parameters.length > i ? (parameters[i] as num?)?.toInt() : null;
    return CommandEscPosQRCode(parameters[0] as String,
        size: opt(1), correction: opt(2), model: opt(3));
  }
}

/// `ESC p m t1 t2` / `DLE DC4 1 m t`: open the cash drawer.
class CommandEscPosDrawer extends CommandEscPos {
  /// The connector pin: `0` = pin 2, `1` = pin 5.
  final int pin;
  final int t1;
  final int t2;

  CommandEscPosDrawer(this.pin, this.t1, this.t2) : super('drawer');

  @override
  List get parameters => [pin, t1, t2];

  factory CommandEscPosDrawer.fromJson(Map json) {
    var parameters = _jsonParameters(json);
    return CommandEscPosDrawer(_jsonInt(parameters, 0), _jsonInt(parameters, 1),
        _jsonInt(parameters, 2));
  }
}

/// `ESC B n t`: beeper.
class CommandEscPosBeep extends CommandEscPos {
  final int n;
  final int t;

  CommandEscPosBeep(this.n, this.t) : super('beep');

  @override
  List get parameters => [n, t];

  factory CommandEscPosBeep.fromJson(Map json) {
    var parameters = _jsonParameters(json);
    return CommandEscPosBeep(_jsonInt(parameters, 0), _jsonInt(parameters, 1));
  }
}

/// `FS &` / `FS .`: Kanji character mode.
class CommandEscPosKanji extends CommandEscPos {
  final bool on;

  CommandEscPosKanji({required this.on}) : super('kanji');

  @override
  List get parameters => [on ? 'on' : 'off'];

  factory CommandEscPosKanji.fromJson(Map json) =>
      CommandEscPosKanji(on: _jsonOn(_jsonParameters(json)));
}

/// `ESC R n`: international character set.
class CommandEscPosIntlCharset extends CommandEscPos {
  final int n;

  CommandEscPosIntlCharset(this.n) : super('intl_charset');

  @override
  List get parameters => [n];

  factory CommandEscPosIntlCharset.fromJson(Map json) =>
      CommandEscPosIntlCharset(_jsonInt(_jsonParameters(json), 0));
}

/// A status request that expects a reply from the printer:
/// - `dle_eot`: `DLE EOT n [a]` (real-time status).
/// - `gs_r`: `GS r n` (transmit status).
/// - `asb`: `GS a n` (automatic status back).
/// - `gs_i`: `GS I n` (printer ID).
/// - `esc_u`/`esc_v`: `ESC u n`/`ESC v` (peripheral/paper sensor status).
class CommandEscPosStatusRequest extends CommandEscPos {
  final String kind;
  final int n;
  final int? a;

  CommandEscPosStatusRequest(this.kind, this.n, [this.a])
      : super('status_request');

  @override
  List get parameters => [kind, n, if (a != null) a];

  factory CommandEscPosStatusRequest.fromJson(Map json) {
    var parameters = _jsonParameters(json)!;
    return CommandEscPosStatusRequest(
      parameters[0] as String,
      _jsonInt(parameters, 1),
      parameters.length > 2 ? (parameters[2] as num?)?.toInt() : null,
    );
  }
}

/// An unknown or invalid command ([DecoderEscPos.lenient] mode).
class CommandEscPosUnknown extends CommandEscPos {
  final List<int> bytes;

  CommandEscPosUnknown(this.bytes) : super('unknown');

  @override
  List get parameters => [bytes];

  factory CommandEscPosUnknown.fromJson(Map json) =>
      CommandEscPosUnknown(_jsonBytes(_jsonParameters(json), 0));
}

/// A command truncated at the end of the data ([DecoderEscPos.lenient] mode).
class CommandEscPosTruncated extends CommandEscPos {
  final List<int> bytes;

  CommandEscPosTruncated(this.bytes) : super('truncated');

  @override
  List get parameters => [bytes];

  factory CommandEscPosTruncated.fromJson(Map json) =>
      CommandEscPosTruncated(_jsonBytes(_jsonParameters(json), 0));
}

bool _eq(int c, int v1, [int? v2]) {
  return c == v1 || c == v2;
}

bool _eq0(int c) => _eq(c, 0, 0x30);

bool _eq1(int c) => _eq(c, 1, 0x31);
