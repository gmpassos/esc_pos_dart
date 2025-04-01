/*
 * esc_pos_utils
 * Created by Andrey U.
 * 
 * Copyright (c) 2019-2020. All rights reserved.
 * See LICENSE for distribution and usage details.
 */

import 'dart:typed_data' show Uint8List;

import 'package:gbk_codec/gbk_codec.dart';
import 'package:image/image.dart';

import 'barcode.dart';
import 'char_encoder.dart';
import 'enums.dart';
import 'pos_column.dart';
import 'pos_styles.dart';
import 'qrcode.dart';

abstract class Generator {
  /// The printer paper size:
  final PaperSize _paperSize;

  PaperSize get paperSize => _paperSize;

  final int spaceBetweenRows;

  /// The initial style to use on [reset].
  late final PosStyles initialStyle;

  Generator(this._paperSize,
      {this.spaceBetweenRows = 5, PosStyles? initialStyle}) {
    initialStyle ??= const PosStyles.defaults();

    this.initialStyle =
        initialStyle.ensureWithCodeTable(defaultCodeTable: defaultCodeTable);

    assert(this.initialStyle.codeTable != null);
    assert(this.initialStyle.codeTable!.isNotEmpty);
  }

  String get defaultCodeTable;

  //**************************** Global Styles ************************

  int? globalMaxCharsPerLine;

  PosStyles globalStyles = PosStyles();

  PosFontType get globalFont => globalStyles.fontType ?? PosFontType.fontA;

  String get codeTable => globalStyles.codeTable ?? defaultCodeTable;

  //**************************** Encoding ************************

  Uint8List encode(String text, {bool isKanji = false}) {
    // replace some non-ascii characters
    text = text
        .replaceAll("’", "'")
        .replaceAll("´", "'")
        .replaceAll("»", '"')
        .replaceAll(" ", ' ')
        .replaceAll("•", '.');

    if (!isKanji) {
      return encodeChars(text);
    } else {
      return Uint8List.fromList(gbk_bytes.encode(text));
    }
  }

  (List<String>, List<bool>) getLexemes(String text) {
    final List<String> lexemes = [];
    final List<bool> isLexemeChinese = [];

    var start = 0;
    var end = 0;
    var curLexemeChinese = isChinese(text[0]);

    for (var i = 1; i < text.length; ++i) {
      if (curLexemeChinese == isChinese(text[i])) {
        end += 1;
      } else {
        lexemes.add(text.substring(start, end + 1));
        isLexemeChinese.add(curLexemeChinese);
        start = i;
        end = i;
        curLexemeChinese = !curLexemeChinese;
      }
    }

    lexemes.add(text.substring(start, end + 1));
    isLexemeChinese.add(curLexemeChinese);

    return (lexemes, isLexemeChinese);
  }

  /// Break text into chinese/non-chinese lexemes
  bool isChinese(String ch) {
    return ch.codeUnitAt(0) > 255;
  }

  /// charWidth = default width * text size multiplier
  double getCharWidth(PosStyles styles, {int? maxCharsPerLine}) {
    var charsPerLine = getCharsPerLine(styles, maxCharsPerLine);
    var charWidth = (paperSize.width / charsPerLine) * styles.width.value;
    return charWidth;
  }

  /// Calculates the average character width based on [styles] and [maxCharsPerLine].
  int getCharsPerLine(PosStyles styles, int? maxCharsPerLine) {
    int charsPerLine;
    if (maxCharsPerLine != null) {
      charsPerLine = maxCharsPerLine;
    } else {
      var fontType = styles.fontType;
      if (fontType != null) {
        charsPerLine = getMaxCharsPerLine(fontType);
      } else {
        charsPerLine = maxCharsPerLine ??
            getMaxCharsPerLine(fontType ?? PosFontType.fontA);
      }
    }
    return charsPerLine;
  }

  //**************************** Public command generators ************************

  /// Clear the buffer and reset text styles.
  List<int> reset();

  /// Ends printer job.
  List<int> endJob();

  /// Set global code table which will be used instead of the default printer's code table
  /// (even after resetting)
  List<int> setGlobalCodeTable(String? codeTable);

  /// Set global font which will be used instead of the default printer's font
  /// (even after resetting)
  List<int> setFont(PosFontType font, {int? maxCharsPerLine});

  int getMaxCharsPerLine(PosFontType font);

  List<int> setStyles(PosStyles styles, {bool isKanji = false});

  /// Sens raw command(s)
  List<int> rawBytes(List<int> cmd, {bool isKanji = false});

  List<int> text(
    String text, {
    PosStyles styles = const PosStyles(),
    int linesAfter = 0,
    bool containsChinese = false,
    int? maxCharsPerLine,
  });

  /// Skips [n] lines
  ///
  /// Similar to [feed] but uses an alternative command
  List<int> emptyLines(int n);

  /// Skips [lines] lines
  ///
  /// Similar to [emptyLines] but uses an alternative command
  List<int> feed(int lines);

  /// Cut the paper
  ///
  /// [mode] is used to define the full or partial cut (if supported by the priner)
  List<int> cut({PosCutMode mode = PosCutMode.full, int extraLines = 5});

  /// Request transmission of printer status.
  List<int> transmissionOfStatus({int n = 1});

  /// Print selected code table.
  ///
  /// If [codeTable] is null, global code table is used.
  /// If global code table is null, default printer code table is used.
  List<int> printCodeTable({String? codeTable});

  /// Beeps [n] times
  ///
  /// Beep [duration] could be between 50 and 450 ms.
  List<int> beep(
      {int n = 3, PosBeepDuration duration = PosBeepDuration.beep450ms});

  /// Reverse feed for [n] lines (if supported by the priner)
  List<int> reverseFeed(int n);

  /// Print a row.
  ///
  /// A row contains up to 12 columns. A column has a width between 1 and 12.
  /// Total width of columns in one row must be equal 12.
  List<int> row(List<PosColumn> cols);

  /// Print an image using (ESC *) command
  ///
  /// [image] is an instanse of class from [Image library](https://pub.dev/packages/image)
  List<int> image(Image imgSrc, {PosAlign align = PosAlign.center});

  /// Print an image using (GS v 0) obsolete command
  ///
  /// [image] is an instanse of class from [Image library](https://pub.dev/packages/image)
  List<int> imageRaster(
    Image image, {
    PosAlign align = PosAlign.center,
    bool highDensityHorizontal = true,
    bool highDensityVertical = true,
    PosImageFn imageFn = PosImageFn.bitImageRaster,
  });

  /// Print a barcode
  ///
  /// [width] range and units are different depending on the printer model (some printers use 1..5).
  /// [height] range: 1 - 255. The units depend on the printer model.
  /// Width, height, font, text position settings are effective until performing of ESC @, reset or power-off.
  List<int> barcode(
    Barcode barcode, {
    int? width,
    int? height,
    BarcodeFont? font,
    BarcodeText textPos = BarcodeText.below,
    PosAlign align = PosAlign.center,
  });

  /// Print a QR Code
  List<int> qrcode(
    String text, {
    PosAlign align = PosAlign.center,
    QRSize size = QRSize.size4,
    QRCorrection cor = QRCorrection.L,
  });

  /// Open cash drawer
  List<int> drawer({PosDrawer pin = PosDrawer.pin2});

  /// Print horizontal full width separator
  /// If [len] is null, then it will be defined according to the paper width
  List<int> hr({String ch = '-', int? len, int linesAfter = 0}) {
    len ??= getMaxCharsPerLine(globalFont);
    var line = ch * len;
    return text(line);
  }

  List<int> textEncoded(
    Uint8List textBytes, {
    PosStyles styles = const PosStyles(),
    int linesAfter = 0,
    int? maxCharsPerLine,
  });

// ************************ (end) Public command generators ************************
}
