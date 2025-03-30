import 'package:esc_pos_dart/esc_pos_dart.dart';
import 'package:image/image.dart';
import 'package:test/test.dart';

void main() {
  group('PrinterDocument', () {
    test('Tests not implemented', () {
      var doc = _buildPrinterDocument();

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
  });

  group('PrinterDocument', () {
    test('', () async {
      var profile = await CapabilityProfile.load();

      final printer = BytesPrinter(PaperSize.mm80, profile);

      var doc = _buildPrinterDocument();

      doc.print(printer);

      var printedBytes = printer.toBytes();

      expect(printedBytes.length, greaterThan(10));

      print(printedBytes);

      expect(
          printedBytes,
          equals([
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
  });
}

PrinterDocument _buildPrinterDocument() {
  var image = Image(1, 1);
  image.setPixel(0, 0, 0xFF0000FF);

  var doc = PrinterDocument();

  doc.addText(text: 'Hello', style: PrinterCommandStyle(align: 'left'));

  doc.addText(
      text: 'World!', style: PrinterCommandStyle(align: 'right', bold: true));

  doc.addHR();

  doc.addImage(image);

  doc.addCut();
  return doc;
}
