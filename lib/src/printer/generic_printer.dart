/*
 * esc_pos_printer
 * Created by Andrey Ushakov
 * Improved by Graciliano M. Passos.
 *
 * Copyright (c) 2019-2020. All rights reserved.
 * See LICENSE for distribution and usage details.
 */

import 'dart:typed_data' show Uint8List, BytesBuilder;

import 'package:image/image.dart';

import '../utils/barcode.dart';
import '../utils/capability_profile.dart';
import '../utils/enums.dart';
import '../utils/generator.dart';
import '../utils/generator_esc_pos.dart';
import '../utils/pos_column.dart';
import '../utils/pos_styles.dart';
import '../utils/qrcode.dart';

/// Base class for ESC/POS Printers.
abstract class GenericPrinter {
  final PaperSize _paperSize;
  final CapabilityProfile _profile;

  late final Generator _generator;

  GenericPrinter(this._paperSize, this._profile,
      {int spaceBetweenRows = 5, Generator? generator})
      : _generator = generator ??
            GeneratorEscPos(_paperSize, _profile,
                spaceBetweenRows: spaceBetweenRows);

  Generator get generator => _generator;

  PaperSize get paperSize => _paperSize;

  CapabilityProfile get profile => _profile;

  void writeBytes(List<int> bytes);

  // ************************ Printer Commands ************************
  void reset() {
    writeBytes(_generator.reset());
  }

  void endJob() {
    writeBytes(_generator.endJob());
  }

  void text(
    String text, {
    PosStyles styles = const PosStyles(),
    int linesAfter = 0,
    bool containsChinese = false,
    int? maxCharsPerLine,
  }) {
    writeBytes(_generator.text(text,
        styles: styles,
        linesAfter: linesAfter,
        containsChinese: containsChinese,
        maxCharsPerLine: maxCharsPerLine));
  }

  void setGlobalCodeTable(String codeTable) {
    writeBytes(_generator.setGlobalCodeTable(codeTable));
  }

  void setGlobalFont(PosFontType font, {int? maxCharsPerLine}) {
    writeBytes(_generator.setFont(font, maxCharsPerLine: maxCharsPerLine));
  }

  void setStyles(PosStyles styles, {bool isKanji = false}) {
    writeBytes(_generator.setStyles(styles, isKanji: isKanji));
  }

  void rawBytes(List<int> cmd, {bool isKanji = false}) {
    writeBytes(_generator.rawBytes(cmd, isKanji: isKanji));
  }

  void emptyLines(int n) {
    writeBytes(_generator.emptyLines(n));
  }

  void feed(int n) {
    writeBytes(_generator.feed(n));
  }

  void cut({PosCutMode mode = PosCutMode.full}) {
    writeBytes(_generator.cut(mode: mode));
  }

  void printCodeTable({String? codeTable}) {
    writeBytes(_generator.printCodeTable(codeTable: codeTable));
  }

  void beep({int n = 3, PosBeepDuration duration = PosBeepDuration.beep450ms}) {
    writeBytes(_generator.beep(n: n, duration: duration));
  }

  void reverseFeed(int n) {
    writeBytes(_generator.reverseFeed(n));
  }

  void row(List<PosColumn> cols) {
    writeBytes(_generator.row(cols));
  }

  void image(Image imgSrc, {PosAlign align = PosAlign.center}) {
    writeBytes(_generator.image(imgSrc, align: align));
  }

  void imageRaster(
    Image image, {
    PosAlign align = PosAlign.center,
    bool highDensityHorizontal = true,
    bool highDensityVertical = true,
    PosImageFn imageFn = PosImageFn.bitImageRaster,
  }) {
    writeBytes(_generator.imageRaster(
      image,
      align: align,
      highDensityHorizontal: highDensityHorizontal,
      highDensityVertical: highDensityVertical,
      imageFn: imageFn,
    ));
  }

  void barcode(
    Barcode barcode, {
    int? width,
    int? height,
    BarcodeFont? font,
    BarcodeText textPos = BarcodeText.below,
    PosAlign align = PosAlign.center,
  }) {
    writeBytes(_generator.barcode(
      barcode,
      width: width,
      height: height,
      font: font,
      textPos: textPos,
      align: align,
    ));
  }

  void qrcode(
    String text, {
    PosAlign align = PosAlign.center,
    QRSize size = QRSize.size4,
    QRCorrection cor = QRCorrection.L,
  }) {
    writeBytes(_generator.qrcode(text, align: align, size: size, cor: cor));
  }

  void drawer({PosDrawer pin = PosDrawer.pin2}) {
    writeBytes(_generator.drawer(pin: pin));
  }

  void hr(
      {String ch = '-',
      int? len,
      int linesAfter = 0,
      PosStyles styles = const PosStyles()}) {
    writeBytes(_generator.hr(ch: ch, linesAfter: linesAfter, styles: styles));
  }

  void textEncoded(
    Uint8List textBytes, {
    PosStyles styles = const PosStyles(),
    int linesAfter = 0,
    int? maxCharsPerLine,
  }) {
    writeBytes(_generator.textEncoded(
      textBytes,
      styles: styles,
      linesAfter: linesAfter,
      maxCharsPerLine: maxCharsPerLine,
    ));
  }

// ************************ (end) Printer Commands ************************
}

/// A virtual ESC/POS printer that stores printed data in an internal buffer.
/// The stored data can be retrieved using [toBytes].
class BytesPrinter extends GenericPrinter {
  BytesPrinter(super.paperSize, super.profile,
      {super.spaceBetweenRows, super.generator});

  final BytesBuilder _bytesBuilder = BytesBuilder();

  @override
  void writeBytes(List<int> bytes) => _bytesBuilder.add(bytes);

  Uint8List toBytes() => _bytesBuilder.toBytes();

  void clear() => _bytesBuilder.clear();
}
