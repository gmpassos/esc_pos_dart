import 'dart:convert';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:image/image.dart';

import 'printer/generic_printer.dart';
import 'printer/network_printer.dart';
import 'utils/barcode.dart';
import 'utils/enums.dart';
import 'utils/pos_column.dart';
import 'utils/pos_styles.dart';
import 'utils/qrcode.dart';

/// An ESC/POS printer document.
/// See [NetworkPrinter].
class PrinterDocument {
  final String fontType;
  final int fontSize;

  final List<PrinterCommand> commands;

  PrinterDocument(
      {List<PrinterCommand>? commands, String fontType = 'a', int fontSize = 1})
      : commands = commands ?? [],
        fontType =
            fontType.trim().isNotEmpty ? fontType.trim().toLowerCase() : 'a',
        fontSize = fontSize.clamp(1, 8).toInt();

  /// - If [ignoreUnknownCommands] is `true`, commands with an unknown `type`
  ///   are skipped (otherwise throws an [ArgumentError]).
  factory PrinterDocument.fromJson(Map<String, dynamic> j,
          {bool ignoreUnknownCommands = false}) =>
      PrinterDocument(
        commands: (j['commands'] as List)
            .cast<Map<String, dynamic>>()
            .where((e) =>
                !ignoreUnknownCommands ||
                parsePrinterCommandType(e['type']) != null)
            .map((e) => PrinterCommand.fromJson(e))
            .toList(),
        fontType: j['fontType'] ?? 'a',
        fontSize: j['fontSize'] ?? 1,
      );

  PrinterCommand addCommand(PrinterCommand command) {
    commands.add(command);
    return command;
  }

  PrinterCommand addText({
    required String text,
    PrinterCommandStyle? style,
  }) =>
      addCommand(PrinterCommandText(text, style: style));

  PrinterCommand addHR(
          {String? ch, int? linesAfter, PrinterCommandStyle? style}) =>
      addCommand(
          PrinterCommandHR(ch: ch, linesAfter: linesAfter, style: style));

  PrinterCommand addRow(List<PrinterCommandColumn> columns) =>
      addCommand(PrinterCommandRow(columns));

  PrinterCommand addFeed({int n = 1}) => addCommand(PrinterCommandFeed(n));

  PrinterCommand addCut({bool full = true}) =>
      addCommand(PrinterCommandCut(full: full));

  PrinterCommand addImage(Image image, {PosAlign align = PosAlign.center}) =>
      addCommand(PrinterCommandImage(image, align: align));

  /// Sends the print commands to the given [printer].
  ///
  /// This method optionally resets the printer before printing and ends the job
  /// after all commands have been sent.
  ///
  /// - [printer]: The [GenericPrinter] instance to send commands to.
  /// - [reset]: If `true` (default), calls [printer.reset()] before printing.
  /// - [endJob]: If `true` (default), calls [printer.endJob()] after printing.
  ///
  /// Skips execution if there are no commands.
  void print(GenericPrinter printer,
      {bool reset = true, int? selectCharCodeTable, bool endJob = true}) {
    if (commands.isEmpty) return;

    var textFont = PosFontType.from(fontType);
    final textSize = PosTextSize.withValue(fontSize);

    if (reset) {
      var stylesInitial =
          PosStyles(fontType: textFont, width: textSize, height: textSize);
      printer.reset(styles: stylesInitial);
    }

    if (selectCharCodeTable != null) {
      printer.selectCharCodeTable(codeTable: selectCharCodeTable);
    }

    // Ensure `fontType` and `fontSize`:
    if (textFont != null || textSize != null) {
      printer.setStyles(
          PosStyles(fontType: textFont, width: textSize, height: textSize));
    }

    for (var c in commands) {
      c.print(printer);
    }

    if (endJob) {
      printer.endJob();
    }
  }

  Map<String, dynamic> toJson() => {
        'fontType': fontType,
        'fontSize': fontSize,
        'commands': commands.map((e) => e.toJson()).toList(),
      };

  @override
  String toString() {
    var lines = commands.map((e) => e.toString()).toList();

    var maxLine =
        lines.map((e) => e.replaceAll('\n', '').trimRight().length).maxOrNull ??
            0;

    if (maxLine > 10) {
      var hr = '${'-' * 10}\n';
      var hrFull = '${'-' * maxLine}\n';

      for (var i = 0; i < lines.length; ++i) {
        var l = lines[i];
        if (l == hr) {
          lines[i] = hrFull;
        }
      }
    }

    return lines.join();
  }
}

enum PrinterCommandType {
  text,
  hr,
  column,
  row,
  feed,
  cut,
  image,
  barcode,
  qrcode,
}

PrinterCommandType? parsePrinterCommandType(Object? o) {
  if (o == null) return null;
  if (o is PrinterCommandType) return o;

  final s = o.toString().toLowerCase().trim();

  switch (s) {
    case 'text':
      return PrinterCommandType.text;
    case 'hr':
      return PrinterCommandType.hr;
    case 'column':
      return PrinterCommandType.column;
    case 'row':
      return PrinterCommandType.row;
    case 'feed':
      return PrinterCommandType.feed;
    case 'cut':
      return PrinterCommandType.cut;
    case 'image':
      return PrinterCommandType.image;
    case 'barcode':
      return PrinterCommandType.barcode;
    case 'qrcode':
      return PrinterCommandType.qrcode;
    default:
      return null;
  }
}

class PrinterCommandStyle {
  final bool? bold;
  final bool? reverse;
  final bool? underline;
  final bool? turn90;
  final PosAlign? align;
  final int? width;
  final int? height;
  final PosFontType? fontType;
  final String? codeTable;

  const PrinterCommandStyle(
      {this.bold,
      this.reverse,
      this.underline,
      this.turn90,
      this.align,
      this.width,
      this.height,
      this.fontType,
      this.codeTable});

  const PrinterCommandStyle.defaults({
    this.bold = false,
    this.reverse = false,
    this.underline = false,
    this.turn90 = false,
    this.align = PosAlign.left,
    this.width = 1,
    this.height = 1,
    this.fontType = PosFontType.fontA,
    this.codeTable = 'CP437',
  });

  factory PrinterCommandStyle.fromJson(Map<String, dynamic> j) =>
      PrinterCommandStyle(
        bold: j['bold'] as bool?,
        reverse: j['reverse'] as bool?,
        underline: j['underline'] as bool?,
        turn90: j['turn90'] as bool?,
        align: PosAlign.from(j['align']),
        width: j['width'] as int?,
        height: j['height'] as int?,
        fontType: PosFontType.from(j['fontType']),
        codeTable: j['codeTable'] as String?,
      );

  bool get isDefault => toJson().isEmpty;

  Map<String, dynamic> toJson() => {
        if (bold != null) 'bold': bold,
        if (reverse != null) 'reverse': reverse,
        if (underline != null) 'underline': underline,
        if (turn90 != null) 'turn90': turn90,
        if (align != null) 'align': align!.name,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (fontType != null) 'fontType': fontType!.valueName,
        if (codeTable != null) 'codeTable': codeTable,
      };

  PosStyles toPosStyles() => PosStyles(
        bold: bold ?? false,
        reverse: reverse ?? false,
        underline: underline ?? false,
        turn90: turn90 ?? false,
        align: align,
        width: width != null ? PosTextSize.withValue(width!) : null,
        height: height != null ? PosTextSize.withValue(height!) : null,
        fontType: fontType,
        codeTable: codeTable,
      );
}

abstract class PrinterCommand {
  PrinterCommand();

  factory PrinterCommand.fromJson(Map<String, dynamic> j) {
    var type = parsePrinterCommandType(j['type'] as String?);
    if (type == null) {
      throw ArgumentError("JSON with invalid `type`: ${j['type']}");
    }

    switch (type) {
      case PrinterCommandType.text:
        return PrinterCommandText.fromJson(j);
      case PrinterCommandType.hr:
        return PrinterCommandHR.fromJson(j);
      case PrinterCommandType.column:
        return PrinterCommandColumn.fromJson(j);
      case PrinterCommandType.row:
        return PrinterCommandRow.fromJson(j);
      case PrinterCommandType.feed:
        return PrinterCommandFeed.fromJson(j);
      case PrinterCommandType.cut:
        return PrinterCommandCut.fromJson(j);
      case PrinterCommandType.image:
        return PrinterCommandImage.fromJson(j);
      case PrinterCommandType.barcode:
        return PrinterCommandBarcode.fromJson(j);
      case PrinterCommandType.qrcode:
        return PrinterCommandQRCode.fromJson(j);
    }
  }

  PrinterCommandType get type;

  void print(GenericPrinter printer);

  Map<String, dynamic> toJson();

  @override
  String toString();
}

class PrinterCommandText extends PrinterCommand {
  final String text;
  final PrinterCommandStyle? style;

  PrinterCommandText(this.text, {this.style});

  factory PrinterCommandText.fromJson(Map<String, dynamic> j) =>
      PrinterCommandText(
        j['text'] as String,
        style: j['style'] is Map
            ? PrinterCommandStyle.fromJson(j['style']!)
            : null,
      );

  @override
  PrinterCommandType get type => PrinterCommandType.text;

  @override
  void print(GenericPrinter printer) =>
      printer.text(text, styles: style?.toPosStyles() ?? const PosStyles());

  @override
  Map<String, dynamic> toJson() => {
        'type': type.name,
        'text': text,
        if (style != null && !style!.isDefault) 'style': style!.toJson(),
      };

  @override
  String toString() => '$text\n';
}

class PrinterCommandHR extends PrinterCommand {
  final String? ch;
  final int? linesAfter;
  final PrinterCommandStyle? style;

  PrinterCommandHR({this.ch, this.linesAfter, this.style});

  factory PrinterCommandHR.fromJson(Map<String, dynamic> j) => PrinterCommandHR(
        ch: j['ch'] as String?,
        linesAfter: j['linesAfter'] as int?,
        style: j['style'] != null
            ? PrinterCommandStyle.fromJson(j['style'])
            : null,
      );

  @override
  PrinterCommandType get type => PrinterCommandType.hr;

  @override
  void print(GenericPrinter printer) => printer.hr(
      ch: ch ?? '-',
      linesAfter: linesAfter ?? 0,
      styles: style?.toPosStyles() ?? const PosStyles());

  @override
  Map<String, dynamic> toJson() => {
        'type': type.name,
        if (ch != null) 'ch': ch,
        if (linesAfter != null) 'linesAfter': linesAfter,
        if (style != null) 'style': style!.toJson(),
      };

  @override
  String toString() {
    var ch = this.ch ?? '-';
    return '${ch * 10}\n';
  }
}

class PrinterCommandColumn extends PrinterCommand {
  final String text;

  final int width;

  final PrinterCommandStyle? style;

  PrinterCommandColumn(this.text, {this.width = 2, this.style});

  factory PrinterCommandColumn.fromJson(Map<String, dynamic> j) =>
      PrinterCommandColumn(
        j['text'] as String,
        width: (j['width'] as int?) ?? 2,
        style: j['style'] is Map
            ? PrinterCommandStyle.fromJson(j['style']!)
            : null,
      );

  @override
  PrinterCommandType get type => PrinterCommandType.column;

  @override
  void print(GenericPrinter printer) => throw UnsupportedError(
      "No a printer command. Should be used as a row parameter.");

  @override
  Map<String, dynamic> toJson() => {
        'type': type.name,
        'text': text,
        'width': width,
        if (style != null && !style!.isDefault) 'style': style!.toJson(),
      };

  PosColumn toPosColumn() => PosColumn(
      text: text,
      width: width,
      styles: style?.toPosStyles() ?? const PosStyles());

  @override
  String toString() => text;
}

class PrinterCommandRow extends PrinterCommand {
  final List<PrinterCommandColumn> columns;

  PrinterCommandRow(this.columns);

  factory PrinterCommandRow.fromJson(Map<String, dynamic> j) =>
      PrinterCommandRow(
        (j['columns'] as List)
            .map((e) => PrinterCommandColumn.fromJson(e))
            .toList(),
      );

  @override
  PrinterCommandType get type => PrinterCommandType.row;

  @override
  void print(GenericPrinter printer) =>
      printer.row(columns.map((e) => e.toPosColumn()).toList());

  @override
  Map<String, dynamic> toJson() => {
        'type': type.name,
        'columns': columns.map((e) => e.toJson()).toList(),
      };

  @override
  String toString() => '${columns.join('\t')}\n';
}

class PrinterCommandFeed extends PrinterCommand {
  final int n;

  PrinterCommandFeed(this.n);

  factory PrinterCommandFeed.fromJson(Map<String, dynamic> j) =>
      PrinterCommandFeed(
        j['n'] as int,
      );

  @override
  PrinterCommandType get type => PrinterCommandType.feed;

  @override
  void print(GenericPrinter printer) => printer.feed(n);

  @override
  Map<String, dynamic> toJson() => {'type': type.name, 'n': n};

  @override
  String toString() => '\n' * n;
}

class PrinterCommandCut extends PrinterCommand {
  final bool full;

  PrinterCommandCut({this.full = true});

  factory PrinterCommandCut.fromJson(Map<String, dynamic> j) =>
      PrinterCommandCut(
        full: (j['full'] as bool?) ?? true,
      );

  @override
  PrinterCommandType get type => PrinterCommandType.cut;

  @override
  void print(GenericPrinter printer) =>
      printer.cut(mode: full ? PosCutMode.full : PosCutMode.partial);

  @override
  Map<String, dynamic> toJson() => {'type': type.name, 'full': full};

  @override
  String toString() => '-.-\n';
}

class PrinterCommandImage extends PrinterCommand {
  final Image image;
  final PosAlign align;

  PrinterCommandImage(this.image, {this.align = PosAlign.center});

  PrinterCommandImage.fromBytes(int width, int height, List<int> bytes,
      {String? mimeType, PosAlign align = PosAlign.center})
      : this(decodeImage(width, height, bytes, mimeType: mimeType),
            align: align);

  PrinterCommandImage.fromBase64(int width, int height, String bytes,
      {String? mimeType, PosAlign align = PosAlign.center})
      : this.fromBytes(width, height, base64.decode(bytes),
            align: align, mimeType: mimeType);

  factory PrinterCommandImage.fromJson(Map<String, dynamic> j) =>
      PrinterCommandImage.fromBase64(
        j['width'] as int,
        j['height'] as int,
        j['image'] as String,
        mimeType: j['mimeType'] as String?,
        align: PosAlign.from(j['align'] as String?) ?? PosAlign.center,
      );

  /// Decodes an image (PNG, JPEG or raw RGB bytes).
  /// - If [mimeType] is not defined, PNG and JPEG are detected by their
  ///   signature, otherwise [bytes] are handled as raw RGB (`width * height * 3`).
  static Image decodeImage(int width, int height, List<int> bytes,
      {String? mimeType}) {
    var bytesUint8 = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

    mimeType ??= _detectMimeType(bytesUint8);

    switch (mimeType?.trim().toLowerCase()) {
      case 'image/png':
      case 'png':
        {
          return PngDecoder().decode(bytesUint8) ??
              (throw ArgumentError("Can't decode PNG image!"));
        }
      case 'image/jpeg':
      case 'jpeg':
      case 'jpg':
        {
          return JpegDecoder().decode(bytesUint8) ??
              (throw ArgumentError("Can't decode JPEG image!"));
        }
      default:
        {
          var expectedLength = width * height * 3;
          if (width <= 0 || height <= 0 || bytesUint8.length < expectedLength) {
            throw ArgumentError(
                "Invalid raw RGB image data: ${bytesUint8.length} bytes "
                "(expected $expectedLength for ${width}x$height)");
          }

          return Image.fromBytes(
              width: width,
              height: height,
              bytes: bytesUint8.buffer,
              bytesOffset: bytesUint8.offsetInBytes);
        }
    }
  }

  static String? _detectMimeType(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    return null;
  }

  @override
  PrinterCommandType get type => PrinterCommandType.image;

  @override
  void print(GenericPrinter printer) => printer.image(image, align: align);

  Uint8List toPNG() {
    var bytes =
        encodePng(image, singleFrame: true, filter: PngFilter.paeth, level: 4);
    return bytes;
  }

  String toPNGBase64() => base64.encode(toPNG());

  @override
  Map<String, dynamic> toJson() => {
        'type': type.name,
        'width': image.width,
        'height': image.height,
        'align': align.name,
        'image': toPNGBase64(),
        'mimeType': 'image/png',
      };

  @override
  String toString() =>
      '(image width=${image.width} height=${image.height} align="${align.name}" type="${type.name}")\n';
}

/// A barcode command (`GS k`).
class PrinterCommandBarcode extends PrinterCommand {
  /// The ESC/POS barcode type (`GS k m`), see [BarcodeType].
  final int barcodeType;

  /// The barcode data (as printed).
  final String data;

  final PosAlign align;

  /// Module width (`GS w n`).
  final int? width;

  /// Height in dots (`GS h n`).
  final int? height;

  /// HRI characters position (`GS H n`): `0` none, `1` above, `2` below, `3` both.
  final int? hriPosition;

  /// HRI characters font (`GS f n`).
  final int? hriFont;

  PrinterCommandBarcode(this.barcodeType, this.data,
      {this.align = PosAlign.center,
      this.width,
      this.height,
      this.hriPosition,
      this.hriFont});

  factory PrinterCommandBarcode.fromJson(Map<String, dynamic> j) =>
      PrinterCommandBarcode(
        j['barcodeType'] as int,
        j['data'] as String,
        align: PosAlign.from(j['align']) ?? PosAlign.center,
        width: j['width'] as int?,
        height: j['height'] as int?,
        hriPosition: j['hriPosition'] as int?,
        hriFont: j['hriFont'] as int?,
      );

  /// The barcode type name (e.g. `code128`).
  String get typeName => BarcodeType.fromValue(barcodeType).name;

  @override
  PrinterCommandType get type => PrinterCommandType.barcode;

  @override
  void print(GenericPrinter printer) => printer.barcode(
        Barcode.raw(BarcodeType.fromValue(barcodeType), latin1.encode(data)),
        width: width,
        height: height,
        font: switch (hriFont) {
          0 || 0x30 => BarcodeFont.fontA,
          1 || 0x31 => BarcodeFont.fontB,
          _ => null,
        },
        textPos: switch (hriPosition) {
          0 || 0x30 => BarcodeText.none,
          1 || 0x31 => BarcodeText.above,
          3 || 0x33 => BarcodeText.both,
          _ => BarcodeText.below,
        },
        align: align,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': type.name,
        'barcodeType': barcodeType,
        'typeName': typeName,
        'data': data,
        'align': align.name,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (hriPosition != null) 'hriPosition': hriPosition,
        if (hriFont != null) 'hriFont': hriFont,
      };

  @override
  String toString() => '[BARCODE $typeName: $data]\n';
}

/// A QR Code command (`GS ( k`).
class PrinterCommandQRCode extends PrinterCommand {
  final String data;

  final PosAlign align;

  /// Module size (`1..16`).
  final int? size;

  /// Error correction level: `48` (L), `49` (M), `50` (Q), `51` (H).
  final int? correction;

  PrinterCommandQRCode(this.data,
      {this.align = PosAlign.center, this.size, this.correction});

  factory PrinterCommandQRCode.fromJson(Map<String, dynamic> j) =>
      PrinterCommandQRCode(
        j['data'] as String,
        align: PosAlign.from(j['align']) ?? PosAlign.center,
        size: j['size'] as int?,
        correction: j['correction'] as int?,
      );

  @override
  PrinterCommandType get type => PrinterCommandType.qrcode;

  @override
  void print(GenericPrinter printer) => printer.qrcode(
        data,
        align: align,
        size: QRSize((size ?? QRSize.size4.value).clamp(1, 16)),
        cor: switch (correction) {
          49 || 1 => QRCorrection.M,
          50 || 2 => QRCorrection.Q,
          51 || 3 => QRCorrection.H,
          _ => QRCorrection.L,
        },
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': type.name,
        'data': data,
        'align': align.name,
        if (size != null) 'size': size,
        if (correction != null) 'correction': correction,
      };

  @override
  String toString() => '[QR: $data]\n';
}
