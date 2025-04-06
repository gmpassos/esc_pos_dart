import 'dart:convert';

import 'package:collection/collection.dart';

import 'decoder.dart';

/// Decodes ESC/POS commands from received print data,
/// extracting text, formatting, and control instructions.
class DecoderEscPos extends Decoder {
  static const _esc = 0x1B;
  static const _escReset = 0x40;
  static const _escTable = 0x74;
  static const _escFont = 0x4D;
  static const _escAlign = 0x61;
  static const _escBold = 0x45;
  static const _escFeed = 0x64;
  static const _escLineSpacing = 0x33;
  static const _escLineSpacing1_6 = 0x32;
  static const _escLineSpacing1_8 = 0x30;
  static const _escAbsolutePos = 0x24;
  static const _escBitImage = 0x2A;

  static const _gs = 0x1D;
  static const _gsCut = 0x56;

  static const _endJob = 0x0C;

  final List<CommandEscPos> _output = [];

  @override
  void reset() {
    _output.clear();
    _textBuffer = null;
  }

  List<int>? _textBuffer;

  void _flushText() {
    var text = _textBuffer;
    if (text != null && text.isNotEmpty) {
      var s = latin1.decode(text);
      _output.add(CommandEscPosText(s));
    }
    _textBuffer = null;
  }

  @override
  List<CommandEscPos> decode(List<int> serial, {int offset = 0, int? length}) {
    length ??= serial.length - offset;
    if (length == 0) return [];

    var length0 = _output.length;

    _decodeImpl(serial, offset, length);

    var decoded = _output.sublist(length0);
    return decoded;
  }

  void _decodeImpl(List<int> serial, int offset, int length) {
    if (length <= 0) return;

    var consumed = 0;

    while ((length - consumed) > 0) {
      var c0 = serial[(offset + consumed)];
      ++consumed;

      switch (c0) {
        case _esc:
          {
            _flushText();

            var c1 = serial[(offset + consumed)];
            ++consumed;

            switch (c1) {
              case _escReset:
                {
                  _output.add(const CommandEscPosReset());
                }
              case _escTable:
                {
                  var c2 = serial[(offset + consumed)];
                  ++consumed;
                  _output.add(CommandEscPosTable(c2));
                }
              case _escFont:
                {
                  var c2 = serial[(offset + consumed)];
                  ++consumed;
                  _output.add(CommandEscPosFont(
                    a: _eq0(c2) ? true : null,
                    b: _eq1(c2) ? true : null,
                  ));
                }
              case _escAlign:
                {
                  var c2 = serial[(offset + consumed)];
                  ++consumed;
                  _output.add(CommandEscPosAlign(
                    left: _eq0(c2) ? true : null,
                    center: _eq1(c2) ? true : null,
                    right: c2 == 2 ? true : null,
                  ));
                }
              case _escBold:
                {
                  var c2 = serial[(offset + consumed)];
                  ++consumed;
                  _output.add(
                    CommandEscPosBold(
                        on: _eq0(c2)
                            ? false
                            : (_eq1(c2)
                                ? true
                                : throw FormatException(
                                    "Invalid bold parameter: $c2"))),
                  );
                }
              case _escFeed:
                {
                  var c2 = serial[(offset + consumed)];
                  ++consumed;
                  _output.add(CommandEscPosFeed(c2));
                }
              case _escLineSpacing:
                {
                  var c2 = serial[(offset + consumed)];
                  ++consumed;
                  _output.add(CommandEscPosGeneric(
                    'lines_spacing',
                    parameters: [c2],
                  ));
                }
              case _escLineSpacing1_6:
                {
                  _output.add(CommandEscPosGeneric('lines_spacing:1/6'));
                }
              case _escLineSpacing1_8:
                {
                  _output.add(CommandEscPosGeneric('lines_spacing:1/8'));
                }
              case _escAbsolutePos:
                {
                  var nL = serial[(offset + consumed)];
                  ++consumed;

                  var nH = serial[(offset + consumed)];
                  ++consumed;

                  _output.add(CommandEscPosGeneric('absolute_pos',
                      parameters: [nL, nH]));
                }
              case _escBitImage:
                {
                  var mode = serial[(offset + consumed)];
                  ++consumed;

                  var nL = serial[(offset + consumed)];
                  ++consumed;

                  var nH = serial[(offset + consumed)];
                  ++consumed;

                  var dataLength = ((nL + (256 * nH)) / 8).ceil();

                  var imgInit = offset + consumed;
                  var imgData = serial.sublist(imgInit, imgInit + dataLength);
                  consumed += dataLength;

                  _output.add(CommandEscPosBitImage(mode, nL, nH, imgData));
                }
              default:
                throw FormatException("Unknown ESC char: $c1");
            }
          }
        case _gs:
          {
            _flushText();

            var c1 = serial[(offset + consumed)];
            ++consumed;

            switch (c1) {
              case _gsCut:
                {
                  var c2 = serial[(offset + consumed)];
                  ++consumed;
                  _output.add(
                    CommandEscPosCut(
                        full: _eq0(c2)
                            ? true
                            : (_eq1(c2)
                                ? false
                                : throw FormatException(
                                    "Invalid cut parameter: $c2"))),
                  );
                }
              default:
                throw FormatException("Unknown GS char: $c1");
            }
          }
        case _endJob:
          {
            _output.add(CommandEscPosEndJob());
          }
        default:
          {
            var text = _textBuffer ??= [];
            text.add(c0);
          }
      }
    }

    _flushText();
  }
}

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

class CommandEscPosBitImage extends CommandEscPos {
  final int mode;
  final int nL;
  final int nH;

  final List<int> data;

  CommandEscPosBitImage(this.mode, this.nL, this.nH, this.data)
      : super('bit_image');

  @override
  List get parameters => [mode, nL, nH, data];

  factory CommandEscPosBitImage.fromJson(Map json) {
    var parameters = json["parameters"] as List?;

    var mode = parameters![0] as int;

    var nL = parameters[1] as int;
    var nH = parameters[2] as int;

    var dataList = parameters[3] as List;
    var data = dataList.whereType<num>().map((e) => e.toInt()).toList();

    return CommandEscPosBitImage(mode, nL, nH, data);
  }
}

class CommandEscPosCut extends CommandEscPos {
  final bool full;

  CommandEscPosCut({required this.full}) : super('cut');

  @override
  List get parameters => [full ? 'full' : 'partial'];

  factory CommandEscPosCut.fromJson(Map json) {
    var parameters = json["parameters"] as List?;
    var p = parameters![0] as String;
    return CommandEscPosCut(full: p == 'full');
  }
}

class CommandEscPosEndJob extends CommandEscPos {
  const CommandEscPosEndJob() : super('end_job');

  @override
  List get parameters => const [];
}

bool _eq(int c, int v1, [int? v2]) {
  return c == v1 || c == v2;
}

bool _eq0(int c) => _eq(c, 0, 0x30);

bool _eq1(int c) => _eq(c, 1, 0x31);
