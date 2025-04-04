/*
 * esc_pos_utils
 * Created by Andrey U.
 * 
 * Copyright (c) 2019-2020. All rights reserved.
 * See LICENSE for distribution and usage details.
 */

import 'dart:typed_data' show Uint8List;

import 'package:hex/hex.dart';
import 'package:image/image.dart';

import 'barcode.dart';
import 'capability_profile.dart';
import 'char_encoder.dart';
import 'commands.dart';
import 'enums.dart';
import 'generator.dart';
import 'pos_column.dart';
import 'pos_styles.dart';
import 'qrcode.dart';

/// A generator for ESC/POS commands, used to format and send print instructions
/// to compatible thermal printers.
class GeneratorEscPos extends Generator {
  final CapabilityProfile _profile;

  GeneratorEscPos(super._paperSize, this._profile,
      {super.spaceBetweenRows, super.newLine, super.isWindows});

  @override
  String get defaultCodeTable => 'CP437';

  // ************************ Internal helpers ************************

  double _colIndToPosition(int colInd) {
    final int width = paperSize.width;
    return colInd == 0 ? 0 : (width * colInd / 12 - 1);
  }

  /// Generate multiple bytes for a number: In lower and higher parts, or more parts as needed.
  ///
  /// [value] Input number
  /// [bytesNb] The number of bytes to output (1 - 4)
  List<int> _intLowHigh(int value, int bytesNb) {
    final maxInput = 256 << (bytesNb * 8) - 1;

    if (bytesNb < 1 || bytesNb > 4) {
      throw Exception('Can only output 1-4 bytes');
    }

    if (value < 0 || value > maxInput) {
      throw Exception(
          'Number is too large. Can only output up to $maxInput in $bytesNb bytes');
    }

    final res = <int>[];
    var buf = value;
    for (int i = 0; i < bytesNb; ++i) {
      res.add(buf % 256);
      buf = buf ~/ 256;
    }
    return res;
  }

  /// Extract slices of an image as equal-sized blobs of column-format data.
  ///
  /// [image] Image to extract from
  /// [lineHeight] Printed line height in dots
  List<List<int>> _toColumnFormat(Image imgSrc, int lineHeight) {
    final image = Image.from(imgSrc); // make a copy

    // Determine new width: closest integer that is divisible by lineHeight
    final widthPx = (image.width + lineHeight) - (image.width % lineHeight);
    final heightPx = image.height;

    // Create a black bottom layer
    final biggerImage = copyResize(image, width: widthPx, height: heightPx);
    fill(biggerImage, 0);

    // Insert source image into bigger one
    drawImage(biggerImage, image, dstX: 0, dstY: 0);

    var left = 0;
    final blobs = <List<int>>[];

    while (left < widthPx) {
      final slice = copyCrop(biggerImage, left, 0, lineHeight, heightPx);
      final bytes = slice.getBytes(format: Format.luminance);
      blobs.add(bytes);
      left += lineHeight;
    }

    return blobs;
  }

  /// Image rasterization
  List<int> _toRasterFormat(Image imgSrc) {
    final image = Image.from(imgSrc); // make a copy
    final widthPx = image.width;
    final heightPx = image.height;

    grayscale(image);
    invert(image);

    // R/G/B channels are same -> keep only one channel
    final oneChannelBytes = <int>[];
    final buffer = image.getBytes(format: Format.rgba);
    for (int i = 0; i < buffer.length; i += 4) {
      oneChannelBytes.add(buffer[i]);
    }

    // Add some empty pixels at the end of each line (to make the width divisible by 8)
    if (widthPx % 8 != 0) {
      final targetWidth = (widthPx + 8) - (widthPx % 8);
      final missingPx = targetWidth - widthPx;
      final extra = Uint8List(missingPx);
      for (var i = 0; i < heightPx; i++) {
        final pos = (i * widthPx + widthPx) + i * missingPx;
        oneChannelBytes.insertAll(pos, extra);
      }
    }

    // Pack bits into bytes
    return _packBitsIntoBytes(oneChannelBytes);
  }

  /// Merges each 8 values (bits) into one byte
  List<int> _packBitsIntoBytes(List<int> bytes) {
    const pxPerLine = 8;
    final res = <int>[];
    const threshold = 127; // set the greyscale -> b/w threshold here
    for (var i = 0; i < bytes.length; i += pxPerLine) {
      var newVal = 0;
      for (int j = 0; j < pxPerLine; j++) {
        newVal = _transformUint32Bool(
          newVal,
          pxPerLine - j,
          bytes[i + j] > threshold,
        );
      }
      res.add(newVal ~/ 2);
    }
    return res;
  }

  /// Replaces a single bit in a 32-bit unsigned integer.
  int _transformUint32Bool(int uint32, int shift, bool newValue) {
    return ((0xFFFFFFFF ^ (0x1 << shift)) & uint32) |
        ((newValue ? 1 : 0) << shift);
  }

  // ************************ (end) Internal helpers  ************************

  //**************************** Public command generators ************************

  @override
  List<int> reset() {
    globalStyles = const PosStyles();
    var bytes = cInit.codeUnits;
    bytes += setGlobalCodeTable(codeTable);
    bytes += setFont(globalFont);
    bytes += setStyles(initialStyle);
    globalStyles = initialStyle;
    return bytes;
  }

  @override
  List<int> endJob() {
    var bytes = cEndJob.codeUnits;
    return bytes;
  }

  @override
  List<int> setGlobalCodeTable(String? codeTable) {
    List<int> bytes;
    if (codeTable != null && globalStyles.codeTable != codeTable) {
      globalStyles = globalStyles.copyWith(codeTable: codeTable);
      bytes = <int>[
        ...cCodeTable.codeUnits,
        _profile.getCodePageId(codeTable),
      ];
    } else {
      bytes = [];
    }
    return bytes;
  }

  @override
  List<int> setFont(PosFontType font, {int? maxCharsPerLine}) {
    List<int> bytes;
    if (globalStyles.fontType != font) {
      globalStyles = globalStyles.copyWith(fontType: font);
      globalMaxCharsPerLine = maxCharsPerLine ?? getMaxCharsPerLine(font);
      bytes = font == PosFontType.fontB ? cFontB.codeUnits : cFontA.codeUnits;
    } else {
      bytes = [];
    }
    return bytes;
  }

  @override
  int getMaxCharsPerLine(PosFontType? font) {
    switch (paperSize) {
      case PaperSize.mm58:
        return (font == null || font == PosFontType.fontA) ? 32 : 42;
      case PaperSize.mm80:
        return (font == null || font == PosFontType.fontA) ? 48 : 64;
    }
  }

  @override
  List<int> setStyles(PosStyles styles, {bool isKanji = false}) {
    var bytes = <int>[];

    // Set local code table
    final codeTable = styles.codeTable;
    if (codeTable != null && globalStyles.codeTable != codeTable) {
      bytes += [
        ...cCodeTable.codeUnits,
        _profile.getCodePageId(codeTable),
      ];
      globalStyles = globalStyles.copyWith(codeTable: codeTable);
    }

    if (styles.align != globalStyles.align) {
      bytes += encodeChars(styles.align == PosAlign.left
    final align = styles.align;
    if (align != null && align != globalStyles.align) {
      bytes += encodeChars(align == PosAlign.left
          ? cAlignLeft
          : (align == PosAlign.center ? cAlignCenter : cAlignRight));
      globalStyles = globalStyles.copyWith(align: align);
    }

    final bold = styles.bold;
    if (bold != globalStyles.bold) {
      bytes += (bold ? cBoldOn : cBoldOff).codeUnits;
      globalStyles = globalStyles.copyWith(bold: bold);
    }

    final turn90 = styles.turn90;
    if (turn90 != globalStyles.turn90) {
      bytes += (turn90 ? cTurn90On : cTurn90Off).codeUnits;
      globalStyles = globalStyles.copyWith(turn90: turn90);
    }

    final reverse = styles.reverse;
    if (reverse != globalStyles.reverse) {
      bytes += (reverse ? cReverseOn : cReverseOff).codeUnits;
      globalStyles = globalStyles.copyWith(reverse: reverse);
    }

    final underline = styles.underline;
    if (underline != globalStyles.underline) {
      bytes += (underline ? cUnderline1dot : cUnderlineOff).codeUnits;
      globalStyles = globalStyles.copyWith(underline: underline);
    }

    // Set font
    final fontType = styles.fontType;
    if (fontType != null && fontType != globalStyles.fontType) {
      bytes += (fontType == PosFontType.fontB ? cFontB : cFontA).codeUnits;
      globalStyles = globalStyles.copyWith(fontType: fontType);
    }

    // Characters size
    final height = styles.height;
    final width = styles.width;
    if (height.value != globalStyles.height.value ||
        width.value != globalStyles.width.value) {
      bytes += [
        ...cSizeGSn.codeUnits,
        PosTextSize.decSize(height, width),
      ];
      globalStyles = globalStyles.copyWith(height: height, width: width);
    }

    if (globalStyles.isKanji != isKanji) {
      // Set Kanji mode:
      bytes += (isKanji ? cKanjiOn : cKanjiOff).codeUnits;
      globalStyles = globalStyles.copyWith(isKanji: isKanji);
    }

    return bytes;
  }

  @override
  List<int> rawBytes(List<int> cmd, {bool isKanji = false}) {
    var bytes = <int>[];
    if (!isKanji) {
      bytes += cKanjiOff.codeUnits;
    }
    bytes += Uint8List.fromList(cmd);
    return bytes;
  }

  @override
  List<int> text(
    String text, {
    PosStyles styles = const PosStyles(),
    int linesAfter = 0,
    bool containsChinese = false,
    int? maxCharsPerLine,
  }) {
    var bytes = <int>[];
    if (!containsChinese) {
      bytes += _text(
        encode(text),
        styles: styles,
        isKanji: containsChinese,
        maxCharsPerLine: maxCharsPerLine,
      );
      // Ensure at least one line break after the text
      bytes += emptyLines(linesAfter + 1);
    } else {
      bytes += _mixedKanji(text, styles: styles, linesAfter: linesAfter);
    }
    return bytes;
  }

  @override
  List<int> emptyLines(int n) {
    var bytes = <int>[];
    if (n > 0) {
      bytes = (newLine * n).codeUnits;
    }
    return bytes;
  }

  @override
  List<int> feed(int lines) {
    var bytes = <int>[];
    if (lines >= 0 && lines <= 255) {
      bytes = [...cFeedN.codeUnits, lines];
    }
    return bytes;
  }

  @override
  List<int> cut({PosCutMode mode = PosCutMode.full, int extraLines = 2}) {
    var bytes = emptyLines(extraLines);
    switch (mode) {
      case PosCutMode.partial:
        bytes += cCutPart.codeUnits;
      case PosCutMode.full:
        bytes += cCutFull.codeUnits;
    }
    return bytes;
  }

  @override
  List<int> transmissionOfStatus({int n = 1}) {
    var bytes = <int>[];
    if (n >= 0 && n <= 255) {
      bytes += Uint8List.fromList(
        List.from(cTransmissionOfStatus.codeUnits)..add(n),
      );
    }
    return bytes;
  }

  @override
  List<int> printCodeTable({String? codeTable}) {
    var bytes = cKanjiOff.codeUnits;

    var prevCodeTable = this.codeTable;

    if (codeTable != null && prevCodeTable != codeTable) {
      bytes += <int>[
        ...cCodeTable.codeUnits,
        _profile.getCodePageId(codeTable),
      ];
    }

    bytes += List<int>.generate(256, (i) => i);

    if (codeTable != null && prevCodeTable != codeTable) {
      // Back to initial code table
      bytes += setGlobalCodeTable(prevCodeTable);
    }

    return bytes;
  }

  @override
  List<int> beep(
      {int n = 3, PosBeepDuration duration = PosBeepDuration.beep450ms}) {
    if (n <= 0) return [];

    var beepCount = n;
    if (beepCount > 9) {
      beepCount = 9;
    }

    var bytes = <int>[
      ...cBeep.codeUnits,
      beepCount,
      duration.value,
      ...beep(n: n - 9, duration: duration),
    ];

    return bytes;
  }

  @override
  List<int> reverseFeed(int n) {
    var bytes = <int>[...cReverseFeedN.codeUnits, n];
    return bytes;
  }

  @override
  List<int> row(List<PosColumn> cols) {
    var bytes = <int>[];
    final isSumValid = cols.fold(0, (int sum, col) => sum + col.width) == 12;
    if (!isSumValid) {
      throw Exception('Total columns width must be equal to 12');
    }

    var isNextRow = false;
    var nextRow = <PosColumn>[];

    for (int i = 0; i < cols.length; ++i) {
      int colInd =
          cols.sublist(0, i).fold(0, (int sum, col) => sum + col.width);
      var charWidth = getCharWidth(cols[i].styles);
      var fromPos = _colIndToPosition(colInd);
      final toPos =
          _colIndToPosition(colInd + cols[i].width) - spaceBetweenRows;
      int maxCharactersNb = ((toPos - fromPos) / charWidth).floor();

      if (!cols[i].containsChinese) {
        // CASE 1: containsChinese = false
        Uint8List encodedToPrint = cols[i].textEncoded != null
            ? cols[i].textEncoded!
            : encode(cols[i].text);

        // If the col's content is too long, split it to the next row
        int realCharactersNb = encodedToPrint.length;
        if (realCharactersNb > maxCharactersNb) {
          // Print max possible and split to the next row
          Uint8List encodedToPrintNextRow =
              encodedToPrint.sublist(maxCharactersNb);
          encodedToPrint = encodedToPrint.sublist(0, maxCharactersNb);
          isNextRow = true;
          nextRow.add(PosColumn(
              textEncoded: encodedToPrintNextRow,
              width: cols[i].width,
              styles: cols[i].styles));
        } else {
          // Insert an empty col
          nextRow.add(PosColumn(
              text: '', width: cols[i].width, styles: cols[i].styles));
        }
        // end rows splitting
        bytes += _text(
          encodedToPrint,
          styles: cols[i].styles,
          colInd: colInd,
          colWidth: cols[i].width,
        );
      } else {
        // CASE 1: containsChinese = true
        // Split text into multiple lines if it too long
        int counter = 0;
        int splitPos = 0;
        for (int p = 0; p < cols[i].text.length; ++p) {
          final int w = isChinese(cols[i].text[p]) ? 2 : 1;
          if (counter + w >= maxCharactersNb) {
            break;
          }
          counter += w;
          splitPos += 1;
        }
        String toPrintNextRow = cols[i].text.substring(splitPos);
        String toPrint = cols[i].text.substring(0, splitPos);

        if (toPrintNextRow.isNotEmpty) {
          isNextRow = true;
          nextRow.add(PosColumn(
              text: toPrintNextRow,
              containsChinese: true,
              width: cols[i].width,
              styles: cols[i].styles));
        } else {
          // Insert an empty col
          nextRow.add(PosColumn(
              text: '', width: cols[i].width, styles: cols[i].styles));
        }

        // Print current row
        final (lexemes, isLexemeChinese) = getLexemes(toPrint);

        // Print each lexeme using codetable OR kanji
        for (var j = 0; j < lexemes.length; ++j) {
          bytes += _text(
            encode(lexemes[j], isKanji: isLexemeChinese[j]),
            styles: cols[i].styles,
            colInd: colInd,
            colWidth: cols[i].width,
            isKanji: isLexemeChinese[j],
          );
          // Define the absolute position only once (we print one line only)
          // colInd = null;
        }
      }
    }

    bytes += emptyLines(1);

    if (isNextRow) {
      row(nextRow);
    }
    return bytes;
  }

  @override
  List<int> image(Image imgSrc, {PosAlign align = PosAlign.center}) {
    var bytes = <int>[];
    // Image alignment
    bytes += setStyles(PosStyles().copyWith(align: align));

    final Image image = Image.from(imgSrc); // make a copy
    //const bool highDensityHorizontal = true;
    //const bool highDensityVertical = true;

    invert(image);
    flip(image, Flip.horizontal);
    final Image imageRotated = copyRotate(image, 270);

    //const int lineHeight = highDensityVertical ? 3 : 1;
    const int lineHeight = 3;
    final List<List<int>> blobs = _toColumnFormat(imageRotated, lineHeight * 8);

    // Compress according to line density
    // Line height contains 8 or 24 pixels of src image
    // Each blobs[i] contains greyscale bytes [0-255]
    // const int pxPerLine = 24 ~/ lineHeight;
    for (int blobInd = 0; blobInd < blobs.length; blobInd++) {
      blobs[blobInd] = _packBitsIntoBytes(blobs[blobInd]);
    }

    final int heightPx = imageRotated.height;
    //const int densityByte = (highDensityHorizontal ? 1 : 0) + (highDensityVertical ? 32 : 0);
    const int densityByte = 1 + 32;

    final List<int> header = List.from(cBitImg.codeUnits);
    header.add(densityByte);
    header.addAll(_intLowHigh(heightPx, 2));

    // Adjust line spacing (for 16-unit line feeds): ESC 3 0x10 (HEX: 0x1b 0x33 0x10)
    bytes += [27, 51, 16];
    for (int i = 0; i < blobs.length; ++i) {
      bytes += List.from(header)
        ..addAll(blobs[i])
        ..addAll(newLine.codeUnits);
    }
    // Reset line spacing: ESC 2 (HEX: 0x1b 0x32)
    bytes += [27, 50];
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
    // Image alignment
    bytes += setStyles(PosStyles().copyWith(align: align));

    final int widthPx = image.width;
    final int heightPx = image.height;
    final int widthBytes = (widthPx + 7) ~/ 8;
    final List<int> resterizedData = _toRasterFormat(image);

    if (imageFn == PosImageFn.bitImageRaster) {
      // GS v 0
      final int densityByte =
          (highDensityVertical ? 0 : 1) + (highDensityHorizontal ? 0 : 2);

      final List<int> header = List.from(cRasterImg2.codeUnits);
      header.add(densityByte); // m
      header.addAll(_intLowHigh(widthBytes, 2)); // xL xH
      header.addAll(_intLowHigh(heightPx, 2)); // yL yH
      bytes += List.from(header)..addAll(resterizedData);
    } else if (imageFn == PosImageFn.graphics) {
      // 'GS ( L' - FN_112 (Image data)
      final List<int> header1 = List.from(cRasterImg.codeUnits);
      header1.addAll(_intLowHigh(widthBytes * heightPx + 10, 2)); // pL pH
      header1.addAll([48, 112, 48]); // m=48, fn=112, a=48
      header1.addAll([1, 1]); // bx=1, by=1
      header1.addAll([49]); // c=49
      header1.addAll(_intLowHigh(widthBytes, 2)); // xL xH
      header1.addAll(_intLowHigh(heightPx, 2)); // yL yH
      bytes += List.from(header1)..addAll(resterizedData);

      // 'GS ( L' - FN_50 (Run print)
      final List<int> header2 = List.from(cRasterImg.codeUnits);
      header2.addAll([2, 0]); // pL pH
      header2.addAll([48, 50]); // m fn[2,50]
      bytes += List.from(header2);
    }
    return bytes;
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
    bytes += setStyles(PosStyles().copyWith(align: align));

    // Set text position
    bytes += cBarcodeSelectPos.codeUnits + [textPos.value];

    // Set font
    if (font != null) {
      bytes += cBarcodeSelectFont.codeUnits + [font.value];
    }

    // Set width
    if (width != null && width >= 0) {
      bytes += cBarcodeSetW.codeUnits + [width];
    }
    // Set height
    if (height != null && height >= 1 && height <= 255) {
      bytes += cBarcodeSetH.codeUnits + [height];
    }

    // Print barcode
    final header = cBarcodePrint.codeUnits + [barcode.type!.value];
    if (barcode.type!.value <= 6) {
      // Function A
      bytes += header + barcode.data! + [0];
    } else {
      // Function B
      bytes += header + [barcode.data!.length] + barcode.data!;
    }
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
    bytes += setStyles(PosStyles().copyWith(align: align));
    QRCode qr = QRCode(text, size, cor);
    bytes += qr.bytes;
    return bytes;
  }

  @override
  List<int> drawer({PosDrawer pin = PosDrawer.pin2}) {
    var bytes = pin == PosDrawer.pin2
        ? cCashDrawerPin2.codeUnits
        : cCashDrawerPin5.codeUnits;
    return bytes;
  }

  @override
  List<int> textEncoded(
    Uint8List textBytes, {
    PosStyles styles = const PosStyles(),
    int linesAfter = 0,
    int? maxCharsPerLine,
  }) {
    var bytes =
        _text(textBytes, styles: styles, maxCharsPerLine: maxCharsPerLine);
    // Ensure at least one line break after the text
    bytes += emptyLines(linesAfter + 1);
    return bytes;
  }

  // ************************ (end) Public command generators ************************

  // ************************ (end) Internal command generators ************************
  /// Generic print for internal use
  ///
  /// [colInd] range: 0..11. If null: do not define the position
  List<int> _text(
    Uint8List textBytes, {
    PosStyles styles = const PosStyles(),
    int? colInd,
    bool isKanji = false,
    int colWidth = 12,
    int? maxCharsPerLine,
  }) {
    var bytes = <int>[];
    if (colInd != null) {
      var charWidth = getCharWidth(styles, maxCharsPerLine: maxCharsPerLine);
      var fromPos = _colIndToPosition(colInd);

      // Align
      if (colWidth != 12) {
        // Update fromPos
        final toPos = _colIndToPosition(colInd + colWidth) - spaceBetweenRows;
        final textLen = textBytes.length * charWidth;

        if (styles.align == PosAlign.right) {
          fromPos = toPos - textLen;
        } else if (styles.align == PosAlign.center) {
          fromPos = fromPos + (toPos - fromPos) / 2 - textLen / 2;
        }
        if (fromPos < 0) {
          fromPos = 0;
        }
      }

      final hexStr = fromPos.round().toRadixString(16).padLeft(3, '0');
      final hexPair = HEX.decode(hexStr);

      // Position
      bytes += <int>[
        ...cPos.codeUnits,
        hexPair[1],
        hexPair[0],
      ];
    }

    bytes += setStyles(styles, isKanji: isKanji);
    bytes += textBytes;

    return bytes;
  }

  /// Prints one line of styled mixed (chinese and latin symbols) text
  List<int> _mixedKanji(
    String text, {
    PosStyles styles = const PosStyles(),
    int linesAfter = 0,
    int? maxCharsPerLine,
  }) {
    var bytes = <int>[];
    final (lexemes, isLexemeChinese) = getLexemes(text);

    // Print each lexeme using codetable OR kanji
    int? colInd = 0;
    for (var i = 0; i < lexemes.length; ++i) {
      bytes += _text(
        encode(lexemes[i], isKanji: isLexemeChinese[i]),
        styles: styles,
        colInd: colInd,
        isKanji: isLexemeChinese[i],
        maxCharsPerLine: maxCharsPerLine,
      );
      // Define the absolute position only once (we print one line only)
      colInd = null;
    }

    bytes += emptyLines(linesAfter + 1);
    return bytes;
  }
// ************************ (end) Internal command generators ************************
}
