import 'dart:convert';

import 'package:esc_pos_dart/esc_pos_dart.dart';
import 'package:image/image.dart';
import 'package:test/test.dart';

const esc = 0x1B;
const gs = 0x1D;

Image buildTestImage(int width, int height) {
  var image = Image(width: width, height: height);
  fill(image, color: ColorRgb8(255, 255, 255));
  for (var i = 0; i < width && i < height; ++i) {
    image.setPixelRgb(i, i, 0, 0, 0);
  }
  image.setPixelRgb(width - 2, 1, 0, 0, 0);
  return image;
}

void main() {
  late CapabilityProfile profile;

  setUpAll(() async {
    profile = await CapabilityProfile.load();
  });

  List<int> printToBytes(PrinterDocument doc) {
    var printer = BytesPrinter(PaperSize.mm80, profile);
    doc.print(printer);
    return printer.toBytes();
  }

  List<PrinterDocument> bytesToDocuments(List<int> bytes) =>
      const EscPosToPrinterDocument().convert(DecoderEscPos(
        lenient: true,
        textDecoding: EscPosTextDecoding.codeTable,
      ).decode(bytes));

  group('Round trip', () {
    test('document -> bytes -> document reaches a fixed point', () {
      var doc1 = PrinterDocument(commands: [
        PrinterCommandText('Title',
            style: const PrinterCommandStyle(
                bold: true, align: PosAlign.center, width: 2, height: 2)),
        PrinterCommandHR(),
        PrinterCommandText('Açaí 2x  12,00'),
        PrinterCommandText('Underlined',
            style: const PrinterCommandStyle(underline: true)),
        PrinterCommandFeed(2),
        PrinterCommandImage(buildTestImage(40, 30)),
        PrinterCommandQRCode('https://menuici.com', size: 5),
        PrinterCommandBarcode(73, '{B1234', height: 60),
        PrinterCommandCut(full: false),
      ]);

      var doc2 = bytesToDocuments(printToBytes(doc1)).single;
      var doc3 = bytesToDocuments(printToBytes(doc2)).single;

      expect(doc3.toJson(), equals(doc2.toJson()));

      var texts =
          doc2.commands.whereType<PrinterCommandText>().map((t) => t.text);
      expect(texts, containsAll(['Title', 'Açaí 2x  12,00', 'Underlined']));

      var image = doc2.commands.whereType<PrinterCommandImage>().single.image;
      expect(image.width, equals(40));
    });

    test('JSON round trip prints the same bytes', () {
      var doc = PrinterDocument(fontSize: 2, commands: [
        PrinterCommandText('A', style: const PrinterCommandStyle(bold: true)),
        PrinterCommandImage(buildTestImage(16, 8)),
        PrinterCommandQRCode('QR'),
        PrinterCommandBarcode(4, 'ABC'),
        PrinterCommandRow([
          PrinterCommandColumn('L', width: 6),
          PrinterCommandColumn('R',
              width: 6,
              style: const PrinterCommandStyle(align: PosAlign.right)),
        ]),
        PrinterCommandCut(),
      ]);

      var json = jsonDecode(jsonEncode(doc.toJson())) as Map<String, dynamic>;
      var doc2 = PrinterDocument.fromJson(json);

      expect(doc2.toJson(), equals(doc.toJson()));
      expect(printToBytes(doc2), equals(printToBytes(doc)));
    });
  });

  group('PrinterDocument', () {
    test('toString', () {
      expect(PrinterDocument().toString(), isEmpty);

      var doc = PrinterDocument(commands: [
        PrinterCommandText('A long line of text here'),
        PrinterCommandHR(),
        PrinterCommandQRCode('QR'),
        PrinterCommandBarcode(73, '{BX'),
        PrinterCommandFeed(1),
        PrinterCommandCut(),
      ]);

      var s = doc.toString();
      expect(s, contains('A long line of text here'));
      expect(s, contains('-' * 24));
      expect(s, contains('[QR: QR]'));
      expect(s, contains('[BARCODE code128: {BX]'));
    });

    test('empty document prints nothing', () {
      expect(printToBytes(PrinterDocument()), isEmpty);
    });

    test('PrinterCommandImage.fromJson without mimeType/align', () {
      var png = base64.encode(encodePng(buildTestImage(4, 3)));

      var cmd = PrinterCommandImage.fromJson(
          {'type': 'image', 'width': 4, 'height': 3, 'image': png});
      expect(cmd.image.width, equals(4));
      expect(cmd.align, equals(PosAlign.center));
    });

    test('PrinterCommandImage: JPEG and raw RGB', () {
      var jpeg = encodeJpg(buildTestImage(8, 8));
      expect(PrinterCommandImage.fromBytes(8, 8, jpeg).image.width, equals(8));
      expect(
          PrinterCommandImage.fromBytes(8, 8, jpeg, mimeType: 'jpg')
              .image
              .height,
          equals(8));

      var raw = List<int>.filled(2 * 2 * 3, 255);
      expect(PrinterCommandImage.fromBytes(2, 2, raw).image.width, equals(2));

      expect(
          () => PrinterCommandImage.fromBytes(4, 4, raw), throwsArgumentError);
    });

    test('PrinterCommandCut.fromJson defaults to full', () {
      expect(PrinterCommandCut.fromJson({'type': 'cut'}).full, isTrue);
    });

    test('PrinterCommandStyle', () {
      const style = PrinterCommandStyle(
          bold: true,
          reverse: true,
          underline: true,
          turn90: true,
          align: PosAlign.right,
          width: 2,
          height: 3,
          fontType: PosFontType.fontB,
          codeTable: 'CP850');

      var style2 = PrinterCommandStyle.fromJson(style.toJson());
      expect(style2.toJson(), equals(style.toJson()));

      var pos = style.toPosStyles();
      expect(pos.bold, isTrue);
      expect(pos.width, equals(PosTextSize.size2));
      expect(pos.fontType, equals(PosFontType.fontB));

      expect(const PrinterCommandStyle().isDefault, isTrue);
    });

    test('code table style prints with the profile code page', () {
      var bytes = printToBytes(PrinterDocument(commands: [
        PrinterCommandText('ç',
            style: const PrinterCommandStyle(codeTable: 'cp850')),
      ]));

      var text = DecoderEscPos(textDecoding: EscPosTextDecoding.codeTable)
          .decode(bytes)
          .whereType<CommandEscPosText>()
          .first
          .text;
      expect(text, startsWith('ç'));
    });
  });

  group('DecoderEscPos (strict) recovery', () {
    test('after an invalid command', () {
      var decoder = DecoderEscPos();

      expect(() => decoder.decode([...'A'.codeUnits, esc, 0x3A, 0x42]),
          throwsFormatException);

      // Reusable (no duplicated commands):
      var cmds = decoder.decode('C\n'.codeUnits);
      expect(cmds.whereType<CommandEscPosText>().map((t) => t.text).join(),
          equals('BC\n'));
    });

    test('after a truncated command', () {
      var decoder = DecoderEscPos();

      expect(
          () => decoder.decode([esc, 0x2A, 33, 5, 0]), throwsFormatException);
      expect(decoder.pendingBytes, isEmpty);

      expect(decoder.decode('OK'.codeUnits).single.parameters, ['OK']);
    });
  });

  group('EscPosToPrinterDocument', () {
    List<PrinterDocument> convert(List<int> bytes,
            {EscPosToPrinterDocument converter =
                const EscPosToPrinterDocument()}) =>
        converter.convert(DecoderEscPos(lenient: true).decode(bytes));

    test('options: splitOnCut / dropEmptyDocuments', () {
      var bytes = [
        ...'A\n'.codeUnits, gs, 0x56, 0, //
        ...'B\n'.codeUnits, gs, 0x56, 0, //
        ...'\n'.codeUnits, gs, 0x56, 0, //
      ];

      expect(convert(bytes).length, equals(2));
      expect(
          convert(bytes,
                  converter:
                      const EscPosToPrinterDocument(dropEmptyDocuments: false))
              .length,
          equals(3));
      expect(
          convert(bytes,
                  converter: const EscPosToPrinterDocument(splitOnCut: false))
              .length,
          equals(1));
    });

    test('styles: print mode, double strike, reverse, turn90', () {
      var bytes = [
        esc, 0x21, 0x39, ...'PM\n'.codeUnits, // font B, bold, double h/w
        esc, 0x21, 0x00, //
        esc, 0x47, 1, ...'DS\n'.codeUnits, esc, 0x47, 0, //
        gs, 0x42, 1, ...'RV\n'.codeUnits, gs, 0x42, 0, //
        esc, 0x56, 1, ...'T90\n'.codeUnits, esc, 0x56, 0, //
      ];

      var texts = convert(bytes)
          .single
          .commands
          .whereType<PrinterCommandText>()
          .toList();

      var pm = texts[0].style!;
      expect(pm.fontType, equals(PosFontType.fontB));
      expect(pm.bold, isTrue);
      expect(pm.width, equals(2));
      expect(pm.height, equals(2));

      expect(texts[1].style?.bold, isTrue);
      expect(texts[2].style?.reverse, isTrue);
      expect(texts[3].style?.turn90, isTrue);
    });

    test('raster image align and NV logo', () {
      var bytes = [
        esc, 0x61, 2, // align right
        gs, 0x76, 0x30, 0, 1, 0, 1, 0, 0x80, //
        0x1C, 0x70, 1, 0, // FS p (NV logo)
        ...'\n'.codeUnits,
      ];

      var commands = convert(bytes).single.commands;
      expect(commands.whereType<PrinterCommandImage>().single.align,
          equals(PosAlign.right));
      expect(commands.whereType<PrinterCommandText>().single.text,
          equals('[LOGO]'));
    });

    test('barcode settings are reset by ESC @', () {
      var bytes = [
        gs, 0x68, 80, gs, 0x6B, 4, ...'A1'.codeUnits, 0, //
        esc, 0x40, //
        gs, 0x6B, 4, ...'B2'.codeUnits, 0, //
      ];

      var barcodes = convert(bytes)
          .single
          .commands
          .whereType<PrinterCommandBarcode>()
          .toList();
      expect(barcodes.map((b) => b.height), [80, null]);
    });

    test('large feeds print in chunks', () {
      var doc = PrinterDocument(
          commands: [PrinterCommandText('A'), PrinterCommandFeed(300)]);
      var bytes = printToBytes(doc);

      var feeds = DecoderEscPos()
          .decode(bytes)
          .whereType<CommandEscPosFeed>()
          .map((f) => f.n)
          .toList();
      expect(feeds, [255, 45]);
    });
  });
}
