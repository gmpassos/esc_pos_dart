import 'package:collection/collection.dart';
import 'package:image/image.dart' show Image, ColorRgb8, fill;

import '../esc_pos_base.dart';
import 'decoder_esc_pos.dart';
import 'enums.dart';

/// Converts decoded ESC/POS commands ([DecoderEscPos]) into [PrinterDocument]s.
///
/// - Text is split into lines ([PrinterCommandText]), with the styles in effect
///   ([PrinterCommandStyle]). Empty lines become [PrinterCommandFeed].
/// - Images (`ESC *` stripes and raster images) become [PrinterCommandImage].
/// - Barcodes and QR Codes become [PrinterCommandBarcode] and [PrinterCommandQRCode].
/// - A document ends at a cut ([splitOnCut]), an end of job (`FF`), or the end
///   of the commands.
class EscPosToPrinterDocument {
  /// The paper size (used to resolve absolute positions into columns).
  final PaperSize paperSize;

  /// If `true`, a line with a repeated char (`-=_*~`, at least 16 chars)
  /// becomes a [PrinterCommandHR].
  final bool detectHR;

  /// If `true`, a cut ends the current document.
  final bool splitOnCut;

  /// If `true`, documents without printable content are dropped.
  final bool dropEmptyDocuments;

  /// The default tab size (in chars), when `ESC D` is not defined.
  final int tabSize;

  /// The empty lines before a cut that belong to the cut (the paper feed to
  /// pass the cutter, added by [PrinterCommandCut] when printed: see
  /// `Generator.cut(extraLines)`): they're not converted to a feed.
  final int cutFeedLines;

  const EscPosToPrinterDocument({
    this.paperSize = PaperSize.mm80,
    this.detectHR = true,
    this.splitOnCut = true,
    this.dropEmptyDocuments = true,
    this.tabSize = 8,
    this.cutFeedLines = 4,
  });

  /// Converts the [commands] into [PrinterDocument]s.
  List<PrinterDocument> convert(List<CommandEscPos> commands) {
    var converter = _Converter(this);
    for (var cmd in commands) {
      converter.process(cmd);
    }
    return converter.finish();
  }
}

class _Converter {
  final EscPosToPrinterDocument options;

  _Converter(this.options);

  final List<PrinterDocument> _documents = [];
  List<PrinterCommand> _commands = [];

  // Styles state:
  bool _bold = false;
  bool _underline = false;
  bool _reverse = false;
  bool _turn90 = false;
  PosAlign _align = PosAlign.left;
  int _width = 1;
  int _height = 1;
  String _fontType = 'a';

  // Barcode settings:
  int? _barcodeWidth;
  int? _barcodeHeight;
  int? _barcodeHriPosition;
  int? _barcodeHriFont;

  List<int>? _tabStops;

  // Current line:
  final StringBuffer _line = StringBuffer();
  PosAlign _lineAlign = PosAlign.left;
  String _lineFontType = 'a';
  int _lineChars = 0;
  int _lineBoldChars = 0;
  int _lineUnderlineChars = 0;
  int _lineReverseChars = 0;
  int _lineMaxWidth = 1;
  int _lineMaxHeight = 1;

  // Pending `ESC *` image stripes:
  final List<CommandEscPosBitImage> _stripes = [];
  PosAlign _stripesAlign = PosAlign.left;

  void process(CommandEscPos cmd) {
    if (cmd is! CommandEscPosBitImage && !_isImageNeutral(cmd)) {
      _flushStripes();
    }

    switch (cmd) {
      case CommandEscPosText():
        _appendText(cmd.text);
      case CommandEscPosReset():
        _flushLine();
        _resetStyles();
      case CommandEscPosFont():
        _fontType = cmd.type == 'b' ? 'b' : 'a';
      case CommandEscPosFontSize():
        _width = cmd.widthSize;
        _height = cmd.heightSize;
      case CommandEscPosBold():
        _bold = cmd.on;
      case CommandEscPosDoubleStrike():
        _bold = cmd.on;
      case CommandEscPosUnderline():
        _underline = cmd.on;
      case CommandEscPosReverse():
        _reverse = cmd.on;
      case CommandEscPosTurn90():
        _turn90 = cmd.on;
      case CommandEscPosPrintMode():
        _fontType = cmd.fontB ? 'b' : 'a';
        _bold = cmd.bold;
        _underline = cmd.underline;
        _width = cmd.doubleWidth ? 2 : 1;
        _height = cmd.doubleHeight ? 2 : 1;
      case CommandEscPosAlign():
        _align = PosAlign.from(cmd.type) ?? PosAlign.left;
      case CommandEscPosFeed():
        _feed(cmd.n);
      case CommandEscPosFeedDots():
        _feed((cmd.n / 30).round());
      case CommandEscPosBitImage():
        _addStripe(cmd);
      case CommandEscPosRasterImage():
        _flushLine();
        _addCommand(PrinterCommandImage(cmd.toImage(), align: _align));
      case CommandEscPosBarcodeSetting():
        _setBarcodeSetting(cmd);
      case CommandEscPosBarcode():
        _flushLine();
        _addCommand(PrinterCommandBarcode(
          cmd.type,
          cmd.dataString,
          align: _align,
          width: _barcodeWidth,
          height: _barcodeHeight,
          hriPosition: _barcodeHriPosition,
          hriFont: _barcodeHriFont,
        ));
      case CommandEscPosQRCode():
        _flushLine();
        _addCommand(PrinterCommandQRCode(cmd.data,
            align: _align, size: cmd.size, correction: cmd.correction));
      case CommandEscPosCut():
        _flushLine();
        _absorbCutFeed();
        _addCommand(PrinterCommandCut(full: cmd.full));
        if (options.splitOnCut) {
          _closeDocument();
        }
      case CommandEscPosEndJob():
        _flushLine();
        _closeDocument();
      case CommandEscPosGeneric():
        _processGeneric(cmd);
      default:
        // Ignored: table, kanji, intl_charset, status_request, drawer, beep,
        // unknown, truncated...
        break;
    }
  }

  bool _isImageNeutral(CommandEscPos cmd) =>
      cmd is CommandEscPosGeneric && cmd.name.startsWith('lines_spacing');

  void _processGeneric(CommandEscPosGeneric cmd) {
    switch (cmd.name) {
      case 'absolute_pos':
        _absolutePosition(cmd.parameters);
      case 'tab_positions':
        var stops = cmd.parameters.isNotEmpty ? cmd.parameters[0] : null;
        _tabStops = stops is List ? stops.whereType<int>().toList() : null;
      case 'nv_image_print':
        _flushLine();
        _addCommand(PrinterCommandText('[LOGO]',
            style: PrinterCommandStyle(
                align: _align != PosAlign.left ? _align : null)));
    }
  }

  void _resetStyles() {
    _bold = false;
    _underline = false;
    _reverse = false;
    _turn90 = false;
    _align = PosAlign.left;
    _width = 1;
    _height = 1;
    _fontType = 'a';
    _tabStops = null;
    // `ESC @` also resets the barcode settings:
    _barcodeWidth = null;
    _barcodeHeight = null;
    _barcodeHriPosition = null;
    _barcodeHriFont = null;
  }

  void _setBarcodeSetting(CommandEscPosBarcodeSetting cmd) {
    switch (cmd.setting) {
      case 'width':
        _barcodeWidth = cmd.n;
      case 'height':
        _barcodeHeight = cmd.n;
      case 'hri_position':
        _barcodeHriPosition = cmd.n;
      case 'hri_font':
        _barcodeHriFont = cmd.n;
    }
  }

  void _appendText(String text) {
    for (var i = 0; i < text.length; ++i) {
      var c = text[i];
      switch (c) {
        case '\n':
          _endLine();
        case '\r':
          break;
        case '\t':
          _tab();
        default:
          if (c.codeUnitAt(0) < 0x20) continue;
          _appendChar(c);
      }
    }
  }

  void _appendChar(String c) {
    if (_line.isEmpty) {
      _lineAlign = _align;
      _lineFontType = _fontType;
    }

    _line.write(c);

    if (c.trim().isEmpty) return;

    ++_lineChars;
    if (_bold) ++_lineBoldChars;
    if (_underline) ++_lineUnderlineChars;
    if (_reverse) ++_lineReverseChars;
    if (_width > _lineMaxWidth) _lineMaxWidth = _width;
    if (_height > _lineMaxHeight) _lineMaxHeight = _height;
  }

  void _appendSpaces(int n) {
    for (var i = 0; i < n; ++i) {
      _appendChar(' ');
    }
  }

  void _tab() {
    var column = _line.length;
    var tabStops = _tabStops;

    int target;
    if (tabStops != null && tabStops.isNotEmpty) {
      target = tabStops.firstWhereOrNull((t) => t > column) ?? (column + 1);
    } else {
      var tabSize = options.tabSize;
      target = ((column ~/ tabSize) + 1) * tabSize;
    }

    _appendSpaces(target - column);
  }

  void _absolutePosition(List parameters) {
    if (parameters.length < 2) return;

    var nL = parameters[0] as int;
    var nH = parameters[1] as int;
    var dots = nL + (nH * 256);

    var charDots = (_fontType == 'b' ? 9 : 12) * _width;
    var column = (dots / charDots).round();

    var length = _line.length;
    if (column > length) {
      _appendSpaces(column - length);
    } else if (length > 0 && !_line.toString().endsWith(' ')) {
      _appendSpaces(1);
    }
  }

  void _feed(int n) {
    if (_line.isNotEmpty) {
      _endLine();
      --n;
    }

    if (n > 0) {
      _addFeed(n);
    }
  }

  /// Emits the current line (if not empty), without a line feed.
  void _flushLine() {
    if (_line.isNotEmpty) {
      _endLine();
    }
  }

  void _endLine() {
    if (_line.isEmpty) {
      _addFeed(1);
      return;
    }

    var text = _line.toString();
    var trimmed = text.trim();

    var style = PrinterCommandStyle(
      bold: _majority(_lineBoldChars) ? true : null,
      underline: _majority(_lineUnderlineChars) ? true : null,
      reverse: _majority(_lineReverseChars) ? true : null,
      turn90: _turn90 ? true : null,
      align: _lineAlign != PosAlign.left ? _lineAlign : null,
      width: _lineMaxWidth > 1 ? _lineMaxWidth : null,
      height: _lineMaxHeight > 1 ? _lineMaxHeight : null,
      fontType: _lineFontType == 'b' ? PosFontType.fontB : null,
    );

    if (trimmed.isEmpty) {
      _addFeed(1);
    } else if (options.detectHR && _isHR(trimmed)) {
      _addCommand(PrinterCommandHR(
          ch: trimmed[0], style: style.isDefault ? null : style));
    } else {
      _addCommand(
          PrinterCommandText(text, style: style.isDefault ? null : style));
    }

    _clearLine();
  }

  bool _majority(int count) => _lineChars > 0 && count * 2 > _lineChars;

  static const _hrChars = '-=_*~';

  bool _isHR(String s) =>
      s.length >= 16 &&
      _hrChars.contains(s[0]) &&
      s.codeUnits.every((c) => c == s.codeUnitAt(0));

  void _clearLine() {
    _line.clear();
    _lineChars = 0;
    _lineBoldChars = 0;
    _lineUnderlineChars = 0;
    _lineReverseChars = 0;
    _lineMaxWidth = 1;
    _lineMaxHeight = 1;
  }

  void _addStripe(CommandEscPosBitImage cmd) {
    _flushLine();

    if (_stripes.isNotEmpty) {
      var last = _stripes.last;
      if (last.columns != cmd.columns || last.mode != cmd.mode) {
        _flushStripes();
      }
    }

    if (_stripes.isEmpty) {
      _stripesAlign = _align;
    }

    _stripes.add(cmd);
  }

  void _flushStripes() {
    if (_stripes.isEmpty) return;

    var images = _stripes.map((s) => s.toImage()).toList();
    _stripes.clear();

    var width = images.map((i) => i.width).max;
    var height = images.map((i) => i.height).sum;

    var image = Image(width: width, height: height, numChannels: 1);
    fill(image, color: ColorRgb8(255, 255, 255));

    var y0 = 0;
    for (var img in images) {
      for (var y = 0; y < img.height; ++y) {
        for (var x = 0; x < img.width; ++x) {
          if (img.getPixel(x, y).r < 128) {
            image.setPixelRgb(x, y0 + y, 0, 0, 0);
          }
        }
      }
      y0 += img.height;
    }

    _addCommand(PrinterCommandImage(image, align: _stripesAlign));
  }

  /// Removes the [EscPosToPrinterDocument.cutFeedLines] from a feed just
  /// before a cut (the cut adds them when printed).
  void _absorbCutFeed() {
    var last = _commands.lastOrNull;
    if (last is! PrinterCommandFeed) return;

    var n = last.n - options.cutFeedLines;
    if (n > 0) {
      _commands[_commands.length - 1] = PrinterCommandFeed(n);
    } else {
      _commands.removeLast();
    }
  }

  void _addFeed(int n) {
    var last = _commands.lastOrNull;
    if (last is PrinterCommandFeed) {
      _commands[_commands.length - 1] = PrinterCommandFeed(last.n + n);
    } else {
      _commands.add(PrinterCommandFeed(n));
    }
  }

  void _addCommand(PrinterCommand command) => _commands.add(command);

  void _closeDocument() {
    _flushStripes();
    _flushLine();

    var commands = _commands;
    _commands = [];

    if (commands.isEmpty) return;

    if (options.dropEmptyDocuments && !commands.any(_isPrintable)) {
      return;
    }

    _documents.add(PrinterDocument(commands: commands));
  }

  static bool _isPrintable(PrinterCommand c) =>
      c is PrinterCommandText ||
      c is PrinterCommandHR ||
      c is PrinterCommandImage ||
      c is PrinterCommandBarcode ||
      c is PrinterCommandQRCode ||
      c is PrinterCommandRow;

  List<PrinterDocument> finish() {
    _closeDocument();
    return _documents;
  }
}
