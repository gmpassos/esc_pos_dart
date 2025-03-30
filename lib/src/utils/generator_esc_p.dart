import 'dart:typed_data';

import 'package:image/image.dart';

import 'barcode.dart';
import 'enums.dart';
import 'generator.dart';
import 'pos_column.dart';
import 'pos_styles.dart';
import 'qrcode.dart';

class GeneratorEscP extends Generator {
  GeneratorEscP(super._paperSize);

  // ************************ Internal helpers ************************

  @override
  int getMaxCharsPerLine(PosFontType? font) {
    switch (paperSize) {
      case PaperSize.mm58:
        return (font == null || font == PosFontType.fontA) ? 22 : 27;
      case PaperSize.mm80:
        return (font == null || font == PosFontType.fontA) ? 31 : 38;
    }
  }

  /// Helper to wrap commands in ESC sequences
  List<int> _wrapCommand(String escSequence) {
    return escSequence.codeUnits;
  }

  /// Generate multiple bytes for a number (low/high)
  List<int> _intLowHigh(int value, int byteCount) {
    final List<int> res = <int>[];
    for (int i = 0; i < byteCount; i++) {
      res.add(value & 0xFF); // Get the least significant byte
      value = value >> 8; // Shift to get the next byte
    }
    return res;
  }

  // ************************ Command Generators ************************

  /// Resets the printer
  @override
  List<int> reset() {
    return _wrapCommand('\x1B@'); // ESC @
  }

  /// Sets the default font type
  List<int> setFont(PosFontType fontType) {
    globalFont = fontType;

    switch (fontType) {
      case PosFontType.fontA:
        return _wrapCommand('\x1BP'); // ESC P (Font A: 10 CPI)
      case PosFontType.fontB:
        return _wrapCommand('\x1BM'); // ESC M (Font B: 12 CPI)
    }
  }

  @override
  List<int> setGlobalFont(PosFontType? font, {int? maxCharsPerLine}) {
    globalFont = font;
    List<int> bytes;
    if (font != null) {
      globalMaxCharsPerLine = maxCharsPerLine ?? getMaxCharsPerLine(font);
      globalStyles = globalStyles.copyWith(fontType: font);
      bytes = font == PosFontType.fontB
          ? _wrapCommand('\x1BM')
          : _wrapCommand('\x1BP');
    } else {
      if (maxCharsPerLine != null) {
        globalMaxCharsPerLine = maxCharsPerLine;
      }
      bytes = <int>[];
    }
    return bytes;
  }

  /// Sets text alignment
  ///
  /// 0: Left alignment
  /// 1: Center alignment
  /// 2: Right alignment
  List<int> setAlignment(int align) {
    return _wrapCommand('\x1Bt${align.toRadixString(16)}');
  }

  /// Prints a single line of text
  @override
  List<int> text(
    String text, {
    PosStyles styles = const PosStyles(),
    int linesAfter = 0,
    bool containsChinese = false,
    int? maxCharsPerLine,
  }) {
    var fontType = styles.fontType ?? globalFont;
    var bytes = <int>[];
    if (fontType != null) {
      bytes += setFont(fontType);
    }
    bytes += encode(text);
    bytes.addAll('\n'.codeUnits); // Add a line break
    return bytes;
  }

  /// Prints empty lines
  @override
  List<int> emptyLines(int n) {
    var bytes = <int>[];
    if (n > 0) {
      bytes = _wrapCommand('\n' * n);
    }
    return bytes;
  }

  /// Feeds (advances) paper by a specified number of lines
  @override
  List<int> feed(int lines) {
    return _wrapCommand('\x1BJ${lines.toRadixString(16)}');
  }

  /// Cuts the paper (if supported by the printer)
  ///
  /// 0: Full cut
  /// 1: Partial cut
  @override
  List<int> cut({PosCutMode mode = PosCutMode.full, int extraLines = 5}) {
    var bytes = emptyLines(extraLines);
    switch (mode) {
      case PosCutMode.partial:
        bytes += _wrapCommand('\x1BM'); // ESC M for partial cut
      case PosCutMode.full:
        bytes += _wrapCommand('\x1BV'); // ESC V for full cut
    }
    return bytes;
  }

  /// Prints rasterized images
  ///
  /// Images should be in black/white or grayscale format.
  @override
  List<int> imageRaster(
    Image image, {
    PosAlign align = PosAlign.center,
    bool highDensityHorizontal = true,
    bool highDensityVertical = true,
    PosImageFn imageFn = PosImageFn.bitImageRaster,
  }) {
    var bytes = <int>[];

    // Grayscale conversion
    grayscale(image);

    // Convert to a binary bitmap (threshold = 128)
    invert(image);
    final oneChannelBytes = image.getBytes(format: Format.luminance);

    final widthBytes = ((image.width + 7) ~/ 8);
    final heightBytes = image.height;

    // ESC * m nL nH - Select bitmap mode
    const int m = 0; // 0 = 8-dot single-density
    final nL = widthBytes & 0xFF;
    final nH = (widthBytes >> 8) & 0xFF;

    bytes += '\x1B*'.codeUnits;
    bytes.add(m);
    bytes.add(nL);
    bytes.add(nH);

    bytes.addAll(_packBitsIntoBytes(oneChannelBytes));
    return bytes;
  }

  /// Packs an array of 8 bits into bytes
  List<int> _packBitsIntoBytes(List<int> bytes) {
    List<int> packed = [];
    for (int i = 0; i < bytes.length; i += 8) {
      int byte = 0;
      for (int j = 0; j < 8; ++j) {
        if (i + j < bytes.length) {
          byte |= (bytes[i + j] >> 7 & 1) << (7 - j);
        }
      }
      packed.add(byte);
    }
    return packed;
  }

  /// Print barcode
  ///
  /// ESC i Barcode types supported depend on the printer.
  List<int> printBarcode(String text, {int type = 3}) {
    List<int> bytes = [];
    bytes += _wrapCommand('\x1Dk$type');
    bytes.addAll(text.codeUnits);
    bytes.add(0); // Null-terminate for older printers
    return bytes;
  }

  @override
  List<int> endJob() {
    // Reset printer and return as ready (if supported by printer)
    return _wrapCommand('\x0C'); // FF (Form Feed)
  }

  @override
  List<int> beep(
      {int n = 3, PosBeepDuration duration = PosBeepDuration.beep450ms}) {
    return [];
  }

  @override
  List<int> barcode(Barcode barcode,
      {int? width,
      int? height,
      BarcodeFont? font,
      BarcodeText textPos = BarcodeText.below,
      PosAlign align = PosAlign.center}) {
    // TODO: implement barcode
    throw UnimplementedError();
  }

  @override
  List<int> drawer({PosDrawer pin = PosDrawer.pin2}) {
    // TODO: implement drawer
    throw UnimplementedError();
  }

  @override
  List<int> image(Image imgSrc, {PosAlign align = PosAlign.center}) {
    // TODO: implement image
    throw UnimplementedError();
  }

  @override
  List<int> printCodeTable({String? codeTable}) {
    // TODO: implement use of `codeTable`.
    var bytes = List<int>.generate(256, (i) => i);
    return bytes;
  }

  @override
  List<int> qrcode(String text,
      {PosAlign align = PosAlign.center,
      QRSize size = QRSize.size4,
      QRCorrection cor = QRCorrection.L}) {
    // TODO: implement qrcode
    throw UnimplementedError();
  }

  @override
  List<int> rawBytes(List<int> cmd, {bool isKanji = false}) {
    // TODO: implement rawBytes
    throw UnimplementedError();
  }

  @override
  List<int> reverseFeed(int n) {
    // TODO: implement reverseFeed
    throw UnimplementedError();
  }

  @override
  List<int> row(List<PosColumn> cols) {
    // TODO: implement row
    throw UnimplementedError();
  }

  @override
  List<int> setGlobalCodeTable(String? codeTable) {
    // TODO: implement setGlobalCodeTable
    throw UnimplementedError();
  }

  @override
  List<int> setStyles(PosStyles styles, {bool isKanji = false}) {
    // TODO: implement setStyles
    throw UnimplementedError();
  }

  @override
  List<int> textEncoded(Uint8List textBytes,
      {PosStyles styles = const PosStyles(),
      int linesAfter = 0,
      int? maxCharsPerLine}) {
    // TODO: implement textEncoded
    throw UnimplementedError();
  }

  @override
  List<int> transmissionOfStatus({int n = 1}) {
    // TODO: implement transmissionOfStatus
    throw UnimplementedError();
  }
}
