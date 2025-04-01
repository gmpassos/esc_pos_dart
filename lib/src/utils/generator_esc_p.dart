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

  @override
  String get defaultCodeTable => 'CP437';

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

  // ************************ Command Generators ************************

  @override
  List<int> reset() {
    var bytes = _wrapCommand('\x1B@'); // ESC @
    globalStyles = PosStyles();
    bytes += setFont(globalFont);
    return bytes;
  }

  @override
  List<int> setFont(PosFontType font, {int? maxCharsPerLine}) {
    globalStyles = globalStyles.copyWith(fontType: font);
    globalMaxCharsPerLine = maxCharsPerLine ?? getMaxCharsPerLine(font);
    var bytes = font == PosFontType.fontB
        ? _wrapCommand('\x1BM')
        : _wrapCommand('\x1BP');
    return bytes;
  }

  List<int> setAlignment(int align) {
    return _wrapCommand('\x1Bt${align.toRadixString(16)}');
  }

  @override
  List<int> text(
    String text, {
    PosStyles styles = const PosStyles(),
    int linesAfter = 0,
    bool containsChinese = false,
    int? maxCharsPerLine,
  }) {
    var bytes = setStyles(styles);
    bytes += encode(text);
    // Ensure at least one line break after the text
    bytes += emptyLines(linesAfter + 1);
    return bytes;
  }

  @override
  List<int> emptyLines(int n) {
    if (n > 0) {
      return _wrapCommand('\n' * n);
    } else {
      return <int>[];
    }
  }

  @override
  List<int> feed(int lines) {
    return _wrapCommand('\x1BJ${lines.toRadixString(16)}');
  }

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
    //final heightBytes = image.height;

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
  List<int> setStyles(PosStyles styles, {bool isKanji = false}) {
    var bytes = <int>[];

    // Set alignment
    if (styles.align != globalStyles.align) {
      bytes.addAll(
          _wrapCommand('\x1Ba${String.fromCharCode(styles.align.value)}'));
      globalStyles = globalStyles.copyWith(align: styles.align);
    }

    // Bold
    if (styles.bold != globalStyles.bold) {
      bytes.addAll(_wrapCommand(styles.bold ? '\x1BE\x01' : '\x1BE\x00'));
      globalStyles = globalStyles.copyWith(bold: styles.bold);
    }

    // Underline
    if (styles.underline != globalStyles.underline) {
      bytes.addAll(_wrapCommand(styles.underline ? '\x1B-\x01' : '\x1B-\x00'));
      globalStyles = globalStyles.copyWith(underline: styles.underline);
    }

    // Reverse
    if (styles.reverse != globalStyles.reverse) {
      bytes.addAll(_wrapCommand(styles.reverse ? '\x1DB\x01' : '\x1DB\x00'));
      globalStyles = globalStyles.copyWith(reverse: styles.reverse);
    }

    // Font Type
    if (styles.fontType != null && styles.fontType != globalStyles.fontType) {
      bytes.addAll(_wrapCommand(
          styles.fontType == PosFontType.fontB ? '\x1BM\x01' : '\x1BM\x00'));
      globalStyles = globalStyles.copyWith(fontType: styles.fontType);
    }

    // Character Size
    if (styles.height.value != globalStyles.height.value ||
        styles.width.value != globalStyles.width.value) {
      bytes.addAll(_wrapCommand(
          '\x1D!${String.fromCharCode((styles.height.value << 4) | styles.width.value)}'));
      globalStyles =
          globalStyles.copyWith(height: styles.height, width: styles.width);
    }

    // Kanji Mode
    bytes.addAll(_wrapCommand(isKanji ? '\x1C&' : '\x1C.'));

    return bytes;
  }

  @override
  List<int> image(Image imgSrc, {PosAlign align = PosAlign.center}) {
    final bytes = <int>[];

    // Convert image to monochrome (1-bit)
    final Image image = convertToMonochrome(imgSrc);
    final int width = (image.width + 7) ~/ 8; // Bytes per row
    final int height = image.height;

    // Alignment
    if (align == PosAlign.center) {
      bytes.addAll(_wrapCommand('\x1Ba\x01')); // Center alignment
    } else if (align == PosAlign.right) {
      bytes.addAll(_wrapCommand('\x1Ba\x02')); // Right alignment
    } else {
      bytes.addAll(_wrapCommand('\x1Ba\x00')); // Left alignment
    }

    // Set line spacing to match image height
    bytes.addAll(_wrapCommand('\x1B3\x24'));

    // Image printing command
    for (int y = 0; y < height; y++) {
      bytes
          .addAll(_wrapCommand('\x1B*\x21')); // ESC * m (Select bit image mode)
      bytes.add(width & 0xFF); // Width in bytes (low byte)
      bytes.add((width >> 8) & 0xFF); // Width in bytes (high byte)

      for (int x = 0; x < width * 8; x += 8) {
        int byte = 0;
        for (int bit = 0; bit < 8; bit++) {
          int pixelX = x + bit;
          if (pixelX < image.width) {
            int pixel = image.getPixel(pixelX, y);
            int grayscale = getLuminance(pixel);
            if (grayscale < 128) {
              byte |= (1 << (7 - bit));
            }
          }
        }
        bytes.add(byte);
      }
      bytes.addAll(_wrapCommand('\n'));
    }

    // Reset line spacing
    bytes.addAll(_wrapCommand('\x1B2'));

    return bytes;
  }

  Image convertToMonochrome(Image src) {
    final Image monochrome = Image(src.width, src.height);
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final pixel = src.getPixel(x, y);
        final gray = getLuminance(pixel);
        final bw = gray < 128 ? 0xFF000000 : 0xFFFFFFFF;
        monochrome.setPixel(x, y, bw);
      }
    }
    return monochrome;
  }

  int getLuminance(int color) {
    final r = (color >> 16) & 0xFF;
    final g = (color >> 8) & 0xFF;
    final b = color & 0xFF;
    return (r * 0.3 + g * 0.59 + b * 0.11).toInt();
  }

  @override
  List<int> barcode(
    Barcode barcode, {
    int? width,
    int? height,
    BarcodeFont? font,
    BarcodeText textPos = BarcodeText.below,
    PosAlign align = PosAlign.center,
  }) {
    var bytes = <int>[];

    // Set alignment
    if (align == PosAlign.center) {
      bytes.addAll(_wrapCommand('\x1Ba\x01'));
    } else if (align == PosAlign.right) {
      bytes.addAll(_wrapCommand('\x1Ba\x02'));
    } else {
      bytes.addAll(_wrapCommand('\x1Ba\x00'));
    }

    // Set height (ESC i h)
    if (height != null && height >= 1 && height <= 255) {
      bytes.addAll(_wrapCommand('\x1Di${String.fromCharCode(height)}'));
    }

    // Set width (ESC w n)
    if (width != null && width >= 1 && width <= 3) {
      bytes.addAll(_wrapCommand('\x1Dw${String.fromCharCode(width)}'));
    }

    // Set text position (ESC i p)
    bytes.addAll(_wrapCommand('\x1Dip${String.fromCharCode(textPos.value)}'));

    // Print barcode (ESC b t d...)
    bytes.addAll(
        _wrapCommand('\x1Db${String.fromCharCode(barcode.type!.value)}'));
    bytes.add(barcode.data!.length);
    bytes.addAll(barcode.data!);

    return bytes;
  }

  @override
  List<int> qrcode(
    String text, {
    PosAlign align = PosAlign.center,
    QRSize size = QRSize.size4,
    QRCorrection cor = QRCorrection.L,
  }) {
    var bytes = <int>[];

    // Set alignment
    if (align == PosAlign.center) {
      bytes.addAll(_wrapCommand('\x1Ba\x01'));
    } else if (align == PosAlign.right) {
      bytes.addAll(_wrapCommand('\x1Ba\x02'));
    } else {
      bytes.addAll(_wrapCommand('\x1Ba\x00'));
    }

    // Set QR code size (ESC ( k pL pH cn fn)
    bytes.addAll(_wrapCommand(
        '\x1D(k\x04\x00\x31\x43${String.fromCharCode(size.value)}'));

    // Set error correction level (ESC ( k pL pH cn fn)
    bytes.addAll(_wrapCommand(
        '\x1D(k\x03\x00\x31\x45${String.fromCharCode(cor.value)}'));

    // Store QR code data (ESC ( k pL pH cn fn)
    final dataBytes = text.codeUnits;
    final dataLen = dataBytes.length + 3;
    bytes.addAll(_wrapCommand(
        '\x1D(k${String.fromCharCode(dataLen & 0xFF)}${String.fromCharCode((dataLen >> 8) & 0xFF)}\x31\x50\x30'));
    bytes.addAll(dataBytes);

    // Print QR code (ESC ( k pL pH cn fn)
    bytes.addAll(_wrapCommand('\x1D(k\x03\x00\x31\x51\x30'));

    return bytes;
  }

  @override
  List<int> drawer({PosDrawer pin = PosDrawer.pin2}) {
    // TODO: implement drawer
    throw UnimplementedError();
  }

  @override
  List<int> printCodeTable({String? codeTable}) {
    // TODO: implement use of `codeTable`.
    var bytes = List<int>.generate(256, (i) => i);
    return bytes;
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
