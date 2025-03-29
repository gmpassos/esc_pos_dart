import 'dart:convert';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:image/image.dart';

import 'printer/generic_printer.dart';
import 'printer/network_printer.dart';
import 'utils/enums.dart';
import 'utils/pos_column.dart';
import 'utils/pos_styles.dart';

/// An ESC/POS printer document.
/// See [NetworkPrinter].
class PrinterDocument {
  final List<PrinterCommand> commands;

  PrinterDocument([List<PrinterCommand>? commands]) : commands = commands ?? [];

  factory PrinterDocument.fromJson(Map<String, dynamic> j) => PrinterDocument(
        (j['commands'] as List).map((e) => PrinterCommand.fromJson(e)).toList(),
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

  PrinterCommand addHR({String? ch, int? linesAfter}) =>
      addCommand(PrinterCommandHR(ch: ch, linesAfter: linesAfter));

  PrinterCommand addRow(List<PrinterCommandColumn> columns) =>
      addCommand(PrinterCommandRow(columns));

  PrinterCommand addFeed({int n = 1}) => addCommand(PrinterCommandFeed(n));

  PrinterCommand addCut({bool full = true}) =>
      addCommand(PrinterCommandCut(full: full));

  PrinterCommand addImage(Image image, {String align = 'center'}) =>
      addCommand(PrinterCommandImage(image, align: align));

  void print(GenericPrinter printer) {
    for (var c in commands) {
      c.print(printer);
    }
  }

  Map<String, dynamic> toJson() => {
        'commands': commands.map((e) => e.toJson()).toList(),
      };

  @override
  String toString() {
    var lines = commands.map((e) => e.toString()).toList();

    var maxLine =
        lines.map((e) => e.replaceAll('\n', '').trimRight().length).max;

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
    default:
      return null;
  }
}

class PrinterCommandStyle {
  final bool bold;
  final bool reverse;
  final bool underline;
  final bool turn90;
  final String align;
  final int width;
  final int height;
  final String fontType;
  final String codeTable;

  PrinterCommandStyle(
      {this.bold = false,
      this.reverse = false,
      this.underline = false,
      this.turn90 = false,
      this.align = 'left',
      this.width = 1,
      this.height = 1,
      this.fontType = 'a',
      this.codeTable = 'CP437'});

  factory PrinterCommandStyle.fromJson(Map<String, dynamic> j) =>
      PrinterCommandStyle(
        bold: j['bold'] as bool? ?? false,
        reverse: j['reverse'] as bool? ?? false,
        underline: j['underline'] as bool? ?? false,
        turn90: j['turn90'] as bool? ?? false,
        align: j['align'] as String? ?? 'left',
        width: j['width'] as int? ?? 1,
        height: j['height'] as int? ?? 1,
        fontType: j['fontType'] as String? ?? 'a',
        codeTable: j['codeTable'] as String? ?? 'CP437',
      );

  bool get isDefault => toJson().isEmpty;

  Map<String, dynamic> toJson() => {
        if (bold) 'bold': bold,
        if (reverse) 'reverse': reverse,
        if (underline) 'underline': underline,
        if (turn90) 'turn90': turn90,
        if (align != 'left') 'align': align,
        if (width != 1) 'width': width,
        if (height != 1) 'height': height,
        if (fontType != 'a') 'fontType': fontType,
        if (codeTable != 'CP437') 'codeTable': codeTable,
      };

  PosStyles toPosStyles() => PosStyles(
        bold: bold,
        reverse: reverse,
        underline: underline,
        turn90: turn90,
        align: PosAlign.values.firstWhere((e) => e.name == align),
        width: getPosTextSize(width),
        height: getPosTextSize(height),
        fontType: fontType == 'b' ? PosFontType.fontB : PosFontType.fontA,
        codeTable: codeTable,
      );

  static PosTextSize getPosTextSize(int size) {
    switch (size) {
      case 1:
        return PosTextSize.size1;
      case 2:
        return PosTextSize.size2;
      case 3:
        return PosTextSize.size3;
      case 4:
        return PosTextSize.size4;
      case 5:
        return PosTextSize.size5;
      case 6:
        return PosTextSize.size6;
      case 7:
        return PosTextSize.size7;
      case 8:
        return PosTextSize.size8;
      default:
        throw UnsupportedError("Unsupported size: $size");
    }
  }
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

  PrinterCommandHR({this.ch, this.linesAfter});

  factory PrinterCommandHR.fromJson(Map<String, dynamic> j) => PrinterCommandHR(
        ch: j['ch'] as String?,
        linesAfter: j['linesAfter'] as int?,
      );

  @override
  PrinterCommandType get type => PrinterCommandType.hr;

  @override
  void print(GenericPrinter printer) => printer.hr(
        ch: ch ?? '-',
        linesAfter: linesAfter ?? 0,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': type.name,
        if (ch != null) 'ch': ch,
        if (linesAfter != null) 'linesAfter': linesAfter,
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
        full: j['full'] as bool,
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
  final String align;

  PrinterCommandImage(this.image, {this.align = 'center'});

  PrinterCommandImage.fromBytes(int width, int height, List<int> bytes,
      {String align = 'center'})
      : this(Image.fromBytes(width, height, bytes), align: align);

  PrinterCommandImage.fromBase64(int width, int height, String bytes,
      {String align = 'center'})
      : this.fromBytes(width, height, base64.decode(bytes), align: align);

  factory PrinterCommandImage.fromJson(Map<String, dynamic> j) =>
      PrinterCommandImage.fromBase64(
        j['width'] as int,
        j['height'] as int,
        j['image'] as String,
        align: j['align'] as String,
      );

  @override
  PrinterCommandType get type => PrinterCommandType.image;

  @override
  void print(GenericPrinter printer) => printer.image(image,
      align: PosAlign.values.firstWhere((e) => e.name == align));

  Uint8List toPNG() {
    var bytes = encodePng(image);
    return bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  }

  String toPNGBase64() => base64.encode(toPNG());

  @override
  Map<String, dynamic> toJson() => {
        'type': type.name,
        'width': image.width,
        'height': image.height,
        'align': align,
        'image': toPNGBase64(),
      };

  @override
  String toString() =>
      '(image width=${image.width} height=${image.height} align="$align" type="${type.name}")\n';
}
