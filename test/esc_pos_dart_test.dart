import 'dart:convert';

import 'package:esc_pos_dart/esc_pos_dart.dart';
import 'package:image/image.dart';
import 'package:test/test.dart';

void main() {
  group('PrinterDocument', () {
    test('toJson', () {
      var doc = _buildPrinterDocument1();

      var json1 = doc.toJson();
      expect(
          json1,
          equals(
            {
              'commands': [
                {'type': 'text', 'text': 'Hello'},
                {
                  'type': 'text',
                  'text': 'World!',
                  'style': {'bold': true, 'align': 'right'}
                },
                {'type': 'hr'},
                {
                  'type': 'image',
                  'width': 1,
                  'height': 1,
                  'align': 'center',
                  'image':
                      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4XmP5z8DwHwAFFAIDXs329AAAAABJRU5ErkJggg==',
                  'mimeType': 'image/png',
                },
                {
                  'type': 'hr',
                  'style': {'fontType': 'b'}
                },
                {'type': 'cut', 'full': true}
              ]
            },
          ));

      var doc2 = PrinterDocument.fromJson(json1);

      var json2 = doc2.toJson();
      expect(json2, equals(json1));
    });

    test('BytesPrinter (ESC/POS 0)', () async {
      var profile = await CapabilityProfile.load();

      final printer = BytesPrinter(PaperSize.mm80, profile);

      var doc = _buildPrinterDocument0();

      doc.print(printer);

      var printedBytes = printer.toBytes();

      expect(printedBytes.length, greaterThan(10));

      print("<<${latin1.decode(printedBytes)}>>");
      print(printedBytes);

      var decodedCommands = DecoderEscPos().decode(printedBytes);

      var commandsJson = decodedCommands.toJson();
      var decodedCommands2 = CommandEscPos.fromJsonList(commandsJson);
      expect(decodedCommands2, decodedCommands);

      expect(commandsJson, [
        {'name': 'reset'},
        {
          'name': 'table',
          'parameters': [0]
        },
        {
          'name': 'font',
          'parameters': ['a']
        },
        {
          'name': 'align',
          'parameters': ['left']
        },
        {
          'name': 'text',
          'parameters': ['Hello\n']
        },
        {
          'name': 'align',
          'parameters': ['right']
        },
        {
          'name': 'bold',
          'parameters': ['on']
        },
        {
          'name': 'text',
          'parameters': ['World!\n']
        },
        {
          'name': 'align',
          'parameters': ['left']
        },
        {
          'name': 'bold',
          'parameters': ['off']
        },
        {
          'name': 'align',
          'parameters': ['center']
        },
        {
          'name': 'text',
          'parameters': ['------------------------------------------\n']
        },
        {
          'name': 'align',
          'parameters': ['left']
        },
        {
          'name': 'feed',
          'parameters': [2]
        },
        {
          'name': 'text',
          'parameters': [
            'By!\n'
                '\n'
                '\n'
                '\n'
                '\n'
          ]
        },
        {
          'name': 'cut',
          'parameters': ['full']
        },
        {'name': 'end_job'}
      ]);

      expect(
          printedBytes,
          equals([
            27,
            64,
            27,
            116,
            0,
            27,
            77,
            0,
            27,
            97,
            0,
            72,
            101,
            108,
            108,
            111,
            10,
            27,
            97,
            2,
            27,
            69,
            1,
            87,
            111,
            114,
            108,
            100,
            33,
            10,
            27,
            97,
            0,
            27,
            69,
            0,
            27,
            97,
            1,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            10,
            27,
            97,
            0,
            27,
            100,
            2,
            66,
            121,
            33,
            10,
            10,
            10,
            10,
            10,
            29,
            86,
            0,
            12
          ]));
    });

    test('BytesPrinter (ESC/POS 1)', () async {
      var profile = await CapabilityProfile.load();

      final printer = BytesPrinter(PaperSize.mm80, profile);

      var doc = _buildPrinterDocument1();

      doc.print(printer);

      var printedBytes = printer.toBytes();

      expect(printedBytes.length, greaterThan(10));

      print("<<${latin1.decode(printedBytes)}>>");
      print(printedBytes);

      var decodedCommands = DecoderEscPos().decode(printedBytes);

      var commandsJson = decodedCommands.toJson();
      var decodedCommands2 = CommandEscPos.fromJsonList(commandsJson);
      expect(decodedCommands2, decodedCommands);

      expect(commandsJson, [
        {'name': 'reset'},
        {
          'name': 'table',
          'parameters': [0]
        },
        {
          'name': 'font',
          'parameters': ['a']
        },
        {
          'name': 'align',
          'parameters': ['left']
        },
        {
          'name': 'text',
          'parameters': ['Hello\n']
        },
        {
          'name': 'align',
          'parameters': ['right']
        },
        {
          'name': 'bold',
          'parameters': ['on']
        },
        {
          'name': 'text',
          'parameters': ['World!\n']
        },
        {
          'name': 'align',
          'parameters': ['left']
        },
        {
          'name': 'bold',
          'parameters': ['off']
        },
        {
          'name': 'text',
          'parameters': ['------------------------------------------\n']
        },
        {
          'name': 'align',
          'parameters': ['center']
        },
        {
          'name': 'lines_spacing',
          'parameters': [16]
        },
        {
          'name': 'bit_image',
          'parameters': [
            33,
            1,
            0,
            [128, 0, 0],
            true
          ]
        },
        {'name': 'lines_spacing:1/6'},
        {
          'name': 'align',
          'parameters': ['left']
        },
        {
          'name': 'font',
          'parameters': ['b']
        },
        {
          'name': 'text',
          'parameters': [
            '--------------------------------------------------------\n'
          ]
        },
        {
          'name': 'font',
          'parameters': ['a']
        },
        {
          'name': 'text',
          'parameters': [
            '\n'
                '\n'
                '\n'
                '\n'
          ]
        },
        {
          'name': 'cut',
          'parameters': ['full']
        },
        {'name': 'end_job'}
      ]);

      expect(
          printedBytes,
          equals([
            27,
            64,
            27,
            116,
            0,
            27,
            77,
            0,
            27,
            97,
            0,
            72,
            101,
            108,
            108,
            111,
            10,
            27,
            97,
            2,
            27,
            69,
            1,
            87,
            111,
            114,
            108,
            100,
            33,
            10,
            27,
            97,
            0,
            27,
            69,
            0,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            10,
            27,
            97,
            1,
            27,
            51,
            16,
            27,
            42,
            33,
            1,
            0,
            128,
            0,
            0,
            10,
            27,
            50,
            27,
            97,
            0,
            27,
            77,
            1,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            10,
            27,
            77,
            0,
            10,
            10,
            10,
            10,
            29,
            86,
            0,
            12
          ]));
    });

    test('BytesPrinter (ESC/POS 2)', () async {
      var profile = await CapabilityProfile.load();

      final printer = BytesPrinter(PaperSize.mm80, profile);

      var doc = _buildPrinterDocument2();

      doc.print(printer);

      var printedBytes = printer.toBytes();

      expect(printedBytes.length, greaterThan(10));

      print("<<${latin1.decode(printedBytes)}>>");
      print(printedBytes);

      var decodedCommands = DecoderEscPos().decode(printedBytes);

      var commandsJson = decodedCommands.toJson();
      var decodedCommands2 = CommandEscPos.fromJsonList(commandsJson);
      expect(decodedCommands2, decodedCommands);

      //print(JsonEncoder.withIndent('  ').convert(commandsJson));

      expect(commandsJson, [
        {"name": "reset"},
        {
          "name": "table",
          "parameters": [0]
        },
        {
          "name": "font",
          "parameters": ["a"]
        },
        {
          "name": "align",
          "parameters": ["left"]
        },
        {
          "name": "text",
          "parameters": ["Hello\n"]
        },
        {
          "name": "align",
          "parameters": ["right"]
        },
        {
          "name": "bold",
          "parameters": ["on"]
        },
        {
          "name": "text",
          "parameters": ["World!\n"]
        },
        {
          "name": "align",
          "parameters": ["left"]
        },
        {
          "name": "bold",
          "parameters": ["off"]
        },
        {
          "name": "text",
          "parameters": [
            "------------------------------------------\nBlock 2\n"
          ]
        },
        {
          "name": "feed",
          "parameters": [3]
        },
        {
          "name": "text",
          "parameters": ["Image:\n"]
        },
        {
          "name": "align",
          "parameters": ["center"]
        },
        {
          "name": "lines_spacing",
          "parameters": [16]
        },
        {
          "name": "bit_image",
          "parameters": [
            33,
            1,
            0,
            [128, 0, 0],
            true
          ]
        },
        {"name": "lines_spacing:1/6"},
        {
          "name": "align",
          "parameters": ["left"]
        },
        {
          "name": "absolute_pos",
          "parameters": [0, 0]
        },
        {
          "name": "text",
          "parameters": ["A Col1"]
        },
        {
          "name": "absolute_pos",
          "parameters": [22, 1]
        },
        {
          "name": "text",
          "parameters": ["A Col2\n"]
        },
        {
          "name": "absolute_pos",
          "parameters": [0, 0]
        },
        {
          "name": "text",
          "parameters": ["B Col1"]
        },
        {
          "name": "absolute_pos",
          "parameters": [139, 0]
        },
        {
          "name": "text",
          "parameters": ["B Col2\nBy!\n\n\n\n\n"]
        },
        {
          "name": "cut",
          "parameters": ["full"]
        },
        {"name": "end_job"}
      ]);

      expect(
          printedBytes,
          equals([
            27,
            64,
            27,
            116,
            0,
            27,
            77,
            0,
            27,
            97,
            0,
            72,
            101,
            108,
            108,
            111,
            10,
            27,
            97,
            2,
            27,
            69,
            1,
            87,
            111,
            114,
            108,
            100,
            33,
            10,
            27,
            97,
            0,
            27,
            69,
            0,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            10,
            66,
            108,
            111,
            99,
            107,
            32,
            50,
            10,
            27,
            100,
            3,
            73,
            109,
            97,
            103,
            101,
            58,
            10,
            27,
            97,
            1,
            27,
            51,
            16,
            27,
            42,
            33,
            1,
            0,
            128,
            0,
            0,
            10,
            27,
            50,
            27,
            97,
            0,
            27,
            36,
            0,
            0,
            65,
            32,
            67,
            111,
            108,
            49,
            27,
            36,
            22,
            1,
            65,
            32,
            67,
            111,
            108,
            50,
            10,
            27,
            36,
            0,
            0,
            66,
            32,
            67,
            111,
            108,
            49,
            27,
            36,
            139,
            0,
            66,
            32,
            67,
            111,
            108,
            50,
            10,
            66,
            121,
            33,
            10,
            10,
            10,
            10,
            10,
            29,
            86,
            0,
            12
          ]));
    });

    test('BytesPrinter (ESC/POS 3)', () async {
      var profile = await CapabilityProfile.load();

      final printer = BytesPrinter(PaperSize.mm80, profile);

      var doc = _buildPrinterDocument3();

      doc.print(printer);

      var printedBytes = printer.toBytes();

      expect(printedBytes.length, greaterThan(10));

      print("<<${latin1.decode(printedBytes)}>>");
      print(printedBytes);

      var decodedCommands = DecoderEscPos().decode(printedBytes);

      var commandsJson = decodedCommands.toJson();
      var decodedCommands2 = CommandEscPos.fromJsonList(commandsJson);
      expect(decodedCommands2, decodedCommands);

      //print(JsonEncoder.withIndent('  ').convert(commandsJson));

      expect(commandsJson, [
        {'name': 'reset'},
        {
          'name': 'table',
          'parameters': [0]
        },
        {
          'name': 'font',
          'parameters': ['a']
        },
        {
          'name': 'align',
          'parameters': ['left']
        },
        {
          'name': 'text',
          'parameters': [
            '------------------------------------------\n'
                ''
          ]
        },
        {
          "name": "align",
          "parameters": ["center"]
        },
        {
          "name": "lines_spacing",
          "parameters": [16]
        },
        {
          "name": "bit_image",
          "parameters": [33, 100, 0, List.generate(300, (i) => 255), true]
        },
        {
          "name": "bit_image",
          "parameters": [
            33,
            100,
            0,
            List.generate(100, (i) => [255, 224, 0]).expand((l) => l).toList(),
            true
          ]
        },
        {'name': 'lines_spacing:1/6'},
        {
          'name': 'align',
          'parameters': ['left']
        },
        {
          'name': 'text',
          'parameters': [
            '------------------------------------------\n'
                'By!\n'
                '\n'
                '\n'
                '\n'
                '\n'
                ''
          ]
        },
        {
          'name': 'cut',
          'parameters': ['full']
        },
        {'name': 'end_job'}
      ]);

      expect(
          printedBytes,
          equals([
            27,
            64,
            27,
            116,
            0,
            27,
            77,
            0,
            27,
            97,
            0,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            10,
            27,
            97,
            1,
            27,
            51,
            16,
            27,
            42,
            33,
            100,
            0,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            255,
            10,
            27,
            42,
            33,
            100,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            255,
            224,
            0,
            10,
            27,
            50,
            27,
            97,
            0,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            45,
            10,
            66,
            121,
            33,
            10,
            10,
            10,
            10,
            10,
            29,
            86,
            0,
            12
          ]));
    });
  });
}

PrinterDocument _buildPrinterDocument0() {
  var doc = PrinterDocument();

  doc.addText(text: 'Hello', style: PrinterCommandStyle(align: PosAlign.left));

  doc.addText(
      text: 'World!',
      style: PrinterCommandStyle(align: PosAlign.right, bold: true));

  doc.addHR(style: PrinterCommandStyle(align: PosAlign.center));

  doc.addFeed(n: 2);

  doc.addText(text: "By!");

  doc.addCut();
  return doc;
}

PrinterDocument _buildPrinterDocument1() {
  var image = Image(width: 1, height: 1, numChannels: 4);
  image.setPixel(0, 0, ColorRgba8(255, 0, 0, 255));

  var doc = PrinterDocument();

  doc.addText(text: 'Hello', style: PrinterCommandStyle(align: PosAlign.left));

  doc.addText(
      text: 'World!',
      style: PrinterCommandStyle(align: PosAlign.right, bold: true));

  doc.addHR();

  doc.addImage(image);

  doc.addHR(style: PrinterCommandStyle(fontType: PosFontType.fontB));

  doc.addCut();
  return doc;
}

PrinterDocument _buildPrinterDocument2() {
  var image = Image(width: 1, height: 1);
  image.setPixel(0, 0, ColorRgba8(255, 0, 0, 255));

  var doc = PrinterDocument();

  doc.addText(text: 'Hello', style: PrinterCommandStyle(align: PosAlign.left));

  doc.addText(
      text: 'World!',
      style: PrinterCommandStyle(align: PosAlign.right, bold: true));

  doc.addHR();

  doc.addText(text: "Block 2");

  doc.addFeed(n: 3);

  doc.addText(text: "Image:");

  doc.addImage(image);

  doc.addRow([
    PrinterCommandColumn("A Col1", width: 6),
    PrinterCommandColumn("A Col2", width: 6),
  ]);

  doc.addRow([
    PrinterCommandColumn("B Col1", width: 3),
    PrinterCommandColumn("B Col2", width: 9),
  ]);

  doc.addText(text: "By!");

  doc.addCut();
  return doc;
}

PrinterDocument _buildPrinterDocument3() {
  var image = Image(width: 100, height: 23 + 12);

  for (var x = 0; x < image.width; ++x) {
    for (var y = 0; y < image.height; ++y) {
      image.setPixelRgba(x, y, 64, 64, 64, 255);
    }
  }

  var doc = PrinterDocument();

  doc.addHR();

  doc.addImage(image);

  doc.addHR();

  doc.addText(text: "By!");

  doc.addCut();
  return doc;
}
