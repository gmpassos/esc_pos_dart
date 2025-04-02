import 'dart:convert';

import 'package:esc_pos_dart/esc_pos_dart.dart';
import 'package:image/image.dart';
import 'package:test/test.dart';

void main() {
  group('PrinterDocument', () {
    test('toJson', () {
      var doc = _buildPrinterDocument1();

      expect(
          doc.toJson(),
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
                      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4AWP5z8DwHwAFFAIDECIziQAAAABJRU5ErkJggg=='
                },
                {'type': 'cut', 'full': true}
              ]
            },
          ));
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

      expect(
          printedBytes,
          equals([
            27,
            64,
            27,
            77,
            0,
            27,
            36,
            0,
            0,
            28,
            46,
            27,
            116,
            0,
            72,
            101,
            108,
            108,
            111,
            10,
            27,
            36,
            0,
            0,
            27,
            97,
            50,
            27,
            69,
            1,
            28,
            46,
            27,
            116,
            0,
            87,
            111,
            114,
            108,
            100,
            33,
            10,
            27,
            36,
            0,
            0,
            27,
            97,
            48,
            27,
            69,
            0,
            28,
            46,
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
            100,
            2,
            27,
            36,
            0,
            0,
            28,
            46,
            66,
            121,
            33,
            10,
            10,
            10,
            10,
            10,
            10,
            29,
            86,
            48
          ]));
    });

    test('BytesPrinter (ESC/POS 1)', () async {
      var profile = await CapabilityProfile.load();

      final printer = BytesPrinter(PaperSize.mm80, profile);

      var doc = _buildPrinterDocument1();

      doc.print(printer);

      var printedBytes = printer.toBytes();

      expect(printedBytes.length, greaterThan(10));

      print(printedBytes);

      expect(
          printedBytes,
          equals([
            27,
            64,
            27,
            36,
            0,
            0,
            27,
            77,
            0,
            28,
            46,
            27,
            116,
            0,
            72,
            101,
            108,
            108,
            111,
            10,
            27,
            36,
            0,
            0,
            27,
            97,
            50,
            27,
            69,
            1,
            28,
            46,
            27,
            116,
            0,
            87,
            111,
            114,
            108,
            100,
            33,
            10,
            27,
            36,
            0,
            0,
            27,
            97,
            48,
            27,
            69,
            0,
            28,
            46,
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
            97,
            49,
            28,
            46,
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
            10,
            10,
            10,
            10,
            10,
            29,
            86,
            48
          ]));
    });

    test('BytesPrinter (ESC/POS 2)', () async {
      var profile = await CapabilityProfile.load();

      final printer = BytesPrinter(PaperSize.mm80, profile);

      var doc = _buildPrinterDocument2();

      doc.print(printer);

      var printedBytes = printer.toBytes();

      expect(printedBytes.length, greaterThan(10));

      print(printedBytes);

      expect(
          printedBytes,
          equals([
            27,
            64,
            27,
            36,
            0,
            0,
            27,
            77,
            0,
            28,
            46,
            27,
            116,
            0,
            72,
            101,
            108,
            108,
            111,
            10,
            27,
            36,
            0,
            0,
            27,
            97,
            50,
            27,
            69,
            1,
            28,
            46,
            27,
            116,
            0,
            87,
            111,
            114,
            108,
            100,
            33,
            10,
            27,
            36,
            0,
            0,
            27,
            97,
            48,
            27,
            69,
            0,
            28,
            46,
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
            36,
            0,
            0,
            28,
            46,
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
            27,
            36,
            0,
            0,
            28,
            46,
            73,
            109,
            97,
            103,
            101,
            58,
            10,
            27,
            97,
            49,
            28,
            46,
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
            36,
            0,
            0,
            27,
            97,
            48,
            28,
            46,
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
            28,
            46,
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
            28,
            46,
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
            28,
            46,
            66,
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
            28,
            46,
            66,
            121,
            33,
            10,
            10,
            10,
            10,
            10,
            10,
            29,
            86,
            48
          ]));
    });

    test('BytesPrinter (ESC/P 0)', () async {
      var profile = await CapabilityProfile.load();

      final printer = BytesPrinter(PaperSize.mm80, profile,
          generator: GeneratorEscP(PaperSize.mm80));

      var doc = _buildPrinterDocument0();

      doc.print(printer);

      var printedBytes = printer.toBytes();

      expect(printedBytes.length, greaterThan(10));

      print(printedBytes);

      expect(
          printedBytes,
          equals([
            27,
            64,
            27,
            80,
            72,
            101,
            108,
            108,
            111,
            10,
            27,
            80,
            87,
            111,
            114,
            108,
            100,
            33,
            10,
            27,
            80,
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
            74,
            50,
            27,
            80,
            66,
            121,
            33,
            10,
            10,
            10,
            10,
            10,
            10,
            27,
            86
          ]));
    });
  });
}

PrinterDocument _buildPrinterDocument0() {
  var image = Image(1, 1);
  image.setPixel(0, 0, 0xFF0000FF);

  var doc = PrinterDocument();

  doc.addText(text: 'Hello', style: PrinterCommandStyle(align: PosAlign.left));

  doc.addText(
      text: 'World!',
      style: PrinterCommandStyle(align: PosAlign.right, bold: true));

  doc.addHR();

  doc.addFeed(n: 2);

  doc.addText(text: "By!");

  doc.addCut();
  return doc;
}

PrinterDocument _buildPrinterDocument1() {
  var image = Image(1, 1);
  image.setPixel(0, 0, 0xFF0000FF);

  var doc = PrinterDocument();

  doc.addText(text: 'Hello', style: PrinterCommandStyle(align: PosAlign.left));

  doc.addText(
      text: 'World!',
      style: PrinterCommandStyle(align: PosAlign.right, bold: true));

  doc.addHR();

  doc.addImage(image);

  doc.addCut();
  return doc;
}

PrinterDocument _buildPrinterDocument2() {
  var image = Image(1, 1);
  image.setPixel(0, 0, 0xFF0000FF);

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
