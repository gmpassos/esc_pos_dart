import 'dart:math' as math;

import 'package:esc_pos_dart/esc_pos_dart.dart';
import 'package:image/image.dart';
import 'package:test/test.dart';

const esc = 0x1B;
const gs = 0x1D;
const fs = 0x1C;
const dle = 0x10;

List<Map<String, dynamic>> decodeJson(List<int> bytes,
        {bool lenient = false}) =>
    DecoderEscPos(lenient: lenient)
        .decode(bytes)
        .map((e) => e.toJson())
        .toList();

/// Merges adjacent text commands (streaming may split text runs).
List<CommandEscPos> mergeText(List<CommandEscPos> cmds) {
  var out = <CommandEscPos>[];
  for (var c in cmds) {
    var last = out.isNotEmpty ? out.last : null;
    if (c is CommandEscPosText && last is CommandEscPosText) {
      out[out.length - 1] = CommandEscPosText(last.text + c.text);
    } else {
      out.add(c);
    }
  }
  return out;
}

/// A test image with an asymmetric pattern (to detect flips/rotations).
Image buildTestImage(int width, int height) {
  var image = Image(width: width, height: height);
  fill(image, color: ColorRgb8(255, 255, 255));
  // Black rectangle at the top-left:
  for (var y = 2; y < 10; ++y) {
    for (var x = 3; x < 15; ++x) {
      image.setPixelRgb(x, y, 0, 0, 0);
    }
  }
  // Black diagonal:
  for (var i = 0; i < math.min(width, height); ++i) {
    image.setPixelRgb(i, i, 0, 0, 0);
  }
  // Black dot at the bottom-right area:
  image.setPixelRgb(width - 4, height - 3, 0, 0, 0);
  return image;
}

bool isBlack(Image image, int x, int y) => image.getPixel(x, y).r < 128;

void expectSamePixels(Image decoded, Image source) {
  expect(decoded.width, greaterThanOrEqualTo(source.width));
  expect(decoded.height, greaterThanOrEqualTo(source.height));

  for (var y = 0; y < source.height; ++y) {
    for (var x = 0; x < source.width; ++x) {
      expect(isBlack(decoded, x, y), equals(isBlack(source, x, y)),
          reason: 'Pixel ($x,$y)');
    }
  }
}

/// Stacks `ESC *` stripes into one image (like the converter).
Image stackStripes(List<CommandEscPosBitImage> stripes) {
  var images = stripes.map((s) => s.toImage()).toList();
  var width = images.map((i) => i.width).reduce(math.max);
  var height = images.fold<int>(0, (h, i) => h + i.height);
  var out = Image(width: width, height: height);
  fill(out, color: ColorRgb8(255, 255, 255));
  var y0 = 0;
  for (var img in images) {
    for (var y = 0; y < img.height; ++y) {
      for (var x = 0; x < img.width; ++x) {
        if (isBlack(img, x, y)) out.setPixelRgb(x, y0 + y, 0, 0, 0);
      }
    }
    y0 += img.height;
  }
  return out;
}

void main() {
  late CapabilityProfile profile;
  late GeneratorEscPos generator;

  setUpAll(() async {
    profile = await CapabilityProfile.load();
  });

  setUp(() {
    generator = GeneratorEscPos(PaperSize.mm80, profile);
  });

  group('DecoderEscPos: sequences', () {
    test('styles', () {
      expect(
          decodeJson([
            esc, 0x2D, 1, // ESC - 1
            esc, 0x2D, 0x32, // ESC - '2'
            gs, 0x42, 1, // GS B 1
            esc, 0x56, 1, // ESC V 1
            esc, 0x7B, 1, // ESC { 1
            esc, 0x47, 1, // ESC G 1
            esc, 0x21, 0xB9, // ESC ! (fontB, bold, dblH, dblW, underline)
            esc, 0x45, 0x31, // ESC E '1'
            esc, 0x45, 3, // ESC E 3 (low bit)
            esc, 0x61, 0x32, // ESC a '2'
          ]),
          [
            {
              'name': 'underline',
              'parameters': [1]
            },
            {
              'name': 'underline',
              'parameters': [2]
            },
            {
              'name': 'reverse',
              'parameters': ['on']
            },
            {
              'name': 'turn90',
              'parameters': ['on']
            },
            {
              'name': 'upside_down',
              'parameters': ['on']
            },
            {
              'name': 'double_strike',
              'parameters': ['on']
            },
            {
              'name': 'print_mode',
              'parameters': [0xB9]
            },
            {
              'name': 'bold',
              'parameters': ['on']
            },
            {
              'name': 'bold',
              'parameters': ['on']
            },
            {
              'name': 'align',
              'parameters': ['right']
            },
          ]);

      var printMode = DecoderEscPos().decode([esc, 0x21, 0xB9]).single
          as CommandEscPosPrintMode;
      expect(printMode.fontB, isTrue);
      expect(printMode.bold, isTrue);
      expect(printMode.doubleHeight, isTrue);
      expect(printMode.doubleWidth, isTrue);
      expect(printMode.underline, isTrue);
    });

    test('GS ! (masked size)', () {
      expect(decodeJson([gs, 0x21, 0x11]), [
        {
          'name': 'font-size',
          'parameters': [2, 2]
        }
      ]);
      // Bytes >= 0x80 used to throw:
      expect(decodeJson([gs, 0x21, 0xF7]), [
        {
          'name': 'font-size',
          'parameters': [8, 8]
        }
      ]);
    });

    test('cuts', () {
      expect(decodeJson([gs, 0x56, 0]).single['parameters'], ['full']);
      expect(decodeJson([gs, 0x56, 1]).single['parameters'], ['partial']);
      expect(decodeJson([gs, 0x56, 0x30]).single['parameters'], ['full']);
      expect(decodeJson([gs, 0x56, 0x31]).single['parameters'], ['partial']);
      expect(decodeJson([gs, 0x56, 65, 3]).single['parameters'], ['full', 3]);
      expect(
          decodeJson([gs, 0x56, 66, 5]).single['parameters'], ['partial', 5]);
      expect(decodeJson([esc, 0x69]).single['parameters'], ['partial']);
      expect(decodeJson([esc, 0x6D]).single['parameters'], ['partial']);
    });

    test('feeds and positions', () {
      expect(decodeJson([esc, 0x64, 3, esc, 0x4A, 60]), [
        {
          'name': 'feed',
          'parameters': [3]
        },
        {
          'name': 'feed_dots',
          'parameters': [60]
        },
      ]);
      expect(decodeJson([esc, 0x24, 10, 1, esc, 0x5C, 5, 0]), [
        {
          'name': 'absolute_pos',
          'parameters': [10, 1]
        },
        {
          'name': 'relative_pos',
          'parameters': [5, 0]
        },
      ]);
      expect(decodeJson([esc, 0x44, 8, 16, 24, 0]), [
        {
          'name': 'tab_positions',
          'parameters': [
            [8, 16, 24]
          ]
        },
      ]);
    });

    test('drawer, beep, status requests', () {
      expect(
          decodeJson([
            esc, 0x70, 0x30, 0x33, 0x30, // ESC p '0' '3' '0'
            dle, 0x14, 1, 1, 2, // DLE DC4 1 m t
            esc, 0x42, 3, 2, // ESC B n t
            dle, 0x04, 1, // DLE EOT 1
            dle, 0x04, 7, 1, // DLE EOT 7 a
            gs, 0x72, 1, // GS r 1
            gs, 0x61, 0xFF, // GS a n
            gs, 0x49, 1, // GS I 1
            esc, 0x76, // ESC v
          ]),
          [
            {
              'name': 'drawer',
              'parameters': [0, 0x33, 0x30]
            },
            {
              'name': 'drawer',
              'parameters': [1, 2, 0]
            },
            {
              'name': 'beep',
              'parameters': [3, 2]
            },
            {
              'name': 'status_request',
              'parameters': ['dle_eot', 1]
            },
            {
              'name': 'status_request',
              'parameters': ['dle_eot', 7, 1]
            },
            {
              'name': 'status_request',
              'parameters': ['gs_r', 1]
            },
            {
              'name': 'status_request',
              'parameters': ['asb', 0xFF]
            },
            {
              'name': 'status_request',
              'parameters': ['gs_i', 1]
            },
            {
              'name': 'status_request',
              'parameters': ['esc_v', 0]
            },
          ]);
    });

    test('kanji and generic commands', () {
      expect(decodeJson([fs, 0x26, fs, 0x2E]), [
        {
          'name': 'kanji',
          'parameters': ['on']
        },
        {
          'name': 'kanji',
          'parameters': ['off']
        },
      ]);

      expect(
          decodeJson([
            esc, 0x20, 1, // ESC SP n
            gs, 0x4C, 10, 0, // GS L nL nH
            gs, 0x28, 0x45, 3, 0, 1, 2, 3, // GS ( E pL pH d...
            fs, 0x70, 1, 0, // FS p n m
          ]).map((e) => e['name']).toList(),
          ['right_spacing', 'left_margin', 'gs(E', 'nv_image_print']);
    });

    test('text and end_job (text flushed before end_job)', () {
      expect(decodeJson([...'Hello'.codeUnits, 0x0C, ...'World'.codeUnits]), [
        {
          'name': 'text',
          'parameters': ['Hello']
        },
        {'name': 'end_job'},
        {
          'name': 'text',
          'parameters': ['World']
        },
      ]);
    });

    test('barcodes', () {
      var cmds = DecoderEscPos().decode([
        gs, 0x6B, 4, ...'ABC123'.codeUnits, 0, // Function A
        gs, 0x6B, 73, 5, ...'{BXYZ'.codeUnits, // Function B
      ]);

      var b1 = cmds[0] as CommandEscPosBarcode;
      expect(b1.type, equals(4));
      expect(b1.typeName, equals('code39'));
      expect(b1.dataString, equals('ABC123'));

      var b2 = cmds[1] as CommandEscPosBarcode;
      expect(b2.type, equals(73));
      expect(b2.typeName, equals('code128'));
      expect(b2.dataString, equals('{BXYZ'));
    });
  });

  group('DecoderEscPos: generator round-trip', () {
    test('styles', () {
      var bytes = generator.text('Styled',
          styles: const PosStyles(
              underline: true,
              reverse: true,
              turn90: true,
              bold: true,
              align: PosAlign.center,
              width: PosTextSize.size2,
              height: PosTextSize.size3,
              fontType: PosFontType.fontB));

      var names = DecoderEscPos().decode(bytes).map((e) => e.name).toList();
      expect(
          names,
          containsAll([
            'align',
            'bold',
            'turn90',
            'reverse',
            'underline',
            'font',
            'font-size',
            'text'
          ]));
    });

    test('image (ESC *)', () {
      var source = buildTestImage(40, 30);
      var bytes = generator.image(source);

      var stripes = DecoderEscPos()
          .decode(bytes)
          .whereType<CommandEscPosBitImage>()
          .toList();
      expect(stripes, isNotEmpty);

      var image = stackStripes(stripes);
      expectSamePixels(image, source);
    });

    test('imageRaster (GS v 0)', () {
      var source = buildTestImage(37, 21);
      var bytes = generator.imageRaster(source);

      var raster = DecoderEscPos()
          .decode(bytes)
          .whereType<CommandEscPosRasterImage>()
          .single;
      expect(raster.widthBytes, equals(5));
      expect(raster.height, equals(21));

      expectSamePixels(raster.toImage(), source);
    });

    test('imageRaster (GS ( L)', () {
      var source = buildTestImage(37, 21);
      var bytes = generator.imageRaster(source, imageFn: PosImageFn.graphics);

      var raster = DecoderEscPos()
          .decode(bytes)
          .whereType<CommandEscPosRasterImage>()
          .single;
      expect(raster.widthBytes, equals(5));
      expect(raster.height, equals(21));

      expectSamePixels(raster.toImage(), source);
    });

    test('barcode', () {
      var bytes = [
        ...generator.barcode(Barcode.code39('ABC123'.split('')),
            width: 2, height: 80, font: BarcodeFont.fontB),
        ...generator.barcode(Barcode.code128('{BXYZ'.split(''))),
      ];

      var cmds = DecoderEscPos().decode(bytes);

      var barcodes = cmds.whereType<CommandEscPosBarcode>().toList();
      expect(barcodes.map((e) => e.dataString), ['ABC123', '{BXYZ']);
      expect(barcodes.map((e) => e.typeName), ['code39', 'code128']);

      var settings = cmds
          .whereType<CommandEscPosBarcodeSetting>()
          .map((e) => '${e.setting}:${e.n}')
          .toList();
      expect(settings, containsAll(['hri_font:1', 'width:2', 'height:80']));
    });

    test('qrcode', () {
      var bytes = generator.qrcode('https://menuici.com/ç',
          size: QRSize.size6, cor: QRCorrection.M);

      var qr =
          DecoderEscPos().decode(bytes).whereType<CommandEscPosQRCode>().single;
      expect(qr.data, equals('https://menuici.com/ç'));
      expect(qr.size, equals(6));
      expect(qr.correction, equals(QRCorrection.M.value));
    });

    test('drawer, beep, cut, rawBytes', () {
      var bytes = [
        ...generator.drawer(pin: PosDrawer.pin5),
        ...generator.beep(n: 2),
        ...generator.cut(mode: PosCutMode.partial),
        ...generator.rawBytes([0x41]),
      ];

      var names = DecoderEscPos().decode(bytes).map((e) => e.name).toList();
      expect(names, ['drawer', 'beep', 'text', 'cut', 'kanji', 'text']);
    });
  });

  group('DecoderEscPos: JSON', () {
    test('round-trip of all commands', () {
      var bytes = [
        esc, 0x2D, 1, gs, 0x42, 1, esc, 0x56, 1, esc, 0x7B, 1, esc, 0x47, 1, //
        esc, 0x21, 0x08, esc, 0x4A, 30, gs, 0x56, 65, 3, //
        gs, 0x6B, 4, 0x41, 0, gs, 0x48, 2, esc, 0x70, 0, 25, 250, //
        esc, 0x42, 1, 1, fs, 0x26, esc, 0x52, 1, dle, 0x04, 1, //
        gs, 0x76, 0x30, 0, 1, 0, 1, 0, 0x80, //
        ...QRCode('qr', QRSize.size3, QRCorrection.H).bytes, //
        esc, 0x3A, 1, // unknown (lenient)
        esc, 0x2A, 33, 2, 0, // truncated (lenient)
      ];

      var cmds = DecoderEscPos(lenient: true).decode(bytes);
      expect(cmds.map((e) => e.name),
          containsAll(['qrcode', 'raster_image', 'unknown', 'truncated']));

      var json = cmds.map((e) => e.toJson()).toList();
      var cmds2 = CommandEscPos.fromJsonList(json);
      expect(cmds2, equals(cmds));
      expect(cmds2.map((e) => e.runtimeType), cmds.map((e) => e.runtimeType));
    });
  });

  group('DecoderEscPos: lenient / truncated', () {
    test('unknown commands', () {
      expect(() => DecoderEscPos().decode([esc, 0x3A, ...'A'.codeUnits]),
          throwsFormatException);

      var decoder = DecoderEscPos(lenient: true);
      var cmds = decoder.decode([esc, 0x3A, ...'A'.codeUnits]);
      expect(cmds.map((e) => e.toJson()), [
        {
          'name': 'unknown',
          'parameters': [
            [esc, 0x3A]
          ]
        },
        {
          'name': 'text',
          'parameters': ['A']
        },
      ]);
      expect(decoder.warnings.single.code, equals('invalid_command'));
    });

    test('every truncated prefix', () {
      var full = [
        esc, 0x2A, 33, 2, 0, 1, 2, 3, 4, 5, 6, //
        gs, 0x76, 0x30, 0, 1, 0, 2, 0, 0xFF, 0xFF, //
        gs, 0x6B, 73, 3, 0x41, 0x42, 0x43, //
        gs, 0x28, 0x6B, 3, 0, 0x31, 0x43, 4, //
        esc, 0x70, 0, 25, 250, //
      ];

      for (var i = 1; i < full.length; ++i) {
        var prefix = full.sublist(0, i);
        var lenient = DecoderEscPos(lenient: true);

        expect(() => lenient.decode(prefix), returnsNormally,
            reason: 'Prefix length: $i');

        var truncated = lenient.commands.whereType<CommandEscPosTruncated>();
        if (truncated.isNotEmpty) {
          expect(() => DecoderEscPos().decode(prefix), throwsFormatException,
              reason: 'Prefix length: $i');
          expect(lenient.warnings.last.code, equals('truncated'));
        }
      }
    });

    test('fuzz (lenient never throws)', () {
      var random = math.Random(1234);

      for (var i = 0; i < 2000; ++i) {
        var length = random.nextInt(64);
        var bytes = List.generate(length, (_) {
          // Bias to command prefixes:
          var r = random.nextInt(10);
          return r == 0
              ? esc
              : (r == 1 ? gs : (r == 2 ? dle : random.nextInt(256)));
        });

        expect(
            () => DecoderEscPos(lenient: true).decode(bytes), returnsNormally,
            reason: 'Bytes: $bytes');
      }
    });

    test('ignorable control chars', () {
      expect(decodeJson([0, ...'A'.codeUnits, 0x18, 9, 10], lenient: true), [
        {
          'name': 'text',
          'parameters': ['A\t\n']
        },
      ]);
    });
  });

  group('DecoderEscPos: streaming', () {
    test('split at every byte index == batch', () {
      var bytes = [
        ...generator.reset(),
        ...generator.text('Hello World!', styles: const PosStyles(bold: true)),
        ...generator.imageRaster(buildTestImage(20, 10)),
        ...generator.qrcode('QR'),
        ...generator.barcode(Barcode.code39('A1'.split(''))),
        ...generator.cut(),
        ...generator.endJob(),
      ];

      var batch = mergeText(DecoderEscPos().decode(bytes));

      for (var i = 0; i <= bytes.length; ++i) {
        var decoder = DecoderEscPos();
        var cmds = [
          ...decoder.add(bytes.sublist(0, i)),
          ...decoder.add(bytes.sublist(i)),
          ...decoder.close(),
        ];
        expect(mergeText(cmds), equals(batch), reason: 'Split at: $i');
      }
    });

    test('pending bytes', () {
      var decoder = DecoderEscPos();
      expect(decoder.add([esc, 0x2A, 33]), isEmpty);
      expect(decoder.pendingBytes, equals([esc, 0x2A, 33]));
      // Complete, but waits for the next byte (an optional CR/LF line break):
      expect(decoder.add([1, 0, 1, 2, 3]), isEmpty);
      expect(decoder.pendingBytes.length, equals(8));
      expect(decoder.close().single, isA<CommandEscPosBitImage>());
      expect(decoder.pendingBytes, isEmpty);
      expect(decoder.consumedBytes, equals(8));
    });
  });

  group('DecoderEscPos: text decoding', () {
    test('latin1 (default)', () {
      expect(DecoderEscPos().decode([esc, 0x74, 16, 0x80]).last.parameters,
          ['\x80']);
    });

    test('code table', () {
      DecoderEscPos decoder() =>
          DecoderEscPos(textDecoding: EscPosTextDecoding.codeTable);

      // Windows-1252:
      expect(decoder().decode([esc, 0x74, 16, 0x80]).last.parameters, ['€']);
      // PC850:
      expect(decoder().decode([esc, 0x74, 2, 0x82]).last.parameters, ['é']);
      // PC437 (default code table), after reset:
      expect(decoder().decode([esc, 0x74, 16, esc, 0x40, 0x82]).last.parameters,
          ['é']);
    });

    test('UTF-8 detection', () {
      // 'Pão' encoded in UTF-8 (ã = C3 A3):
      var bytes = [...'P'.codeUnits, 0xC3, 0xA3, ...'o'.codeUnits];

      expect(DecoderEscPos(detectUtf8: true).decode(bytes).single.parameters,
          ['Pão']);

      // Without detection: latin1.
      expect(DecoderEscPos().decode(bytes).single.parameters, ['PÃ£o']);

      // Invalid UTF-8 falls back to the code table / latin1:
      expect(
          DecoderEscPos(detectUtf8: true)
              .decode([...'P'.codeUnits, 0xE3, ...'o'.codeUnits])
              .single
              .parameters,
          ['Pão']);
    });
  });

  group('EscPosToPrinterDocument', () {
    test('PrinterDocument -> bytes -> decode -> convert', () {
      var printer = BytesPrinter(PaperSize.mm80, profile);

      var doc = PrinterDocument(commands: [
        PrinterCommandText('Title',
            style: const PrinterCommandStyle(
                bold: true, align: PosAlign.center, width: 2, height: 2)),
        PrinterCommandHR(),
        PrinterCommandText('Line 1'),
        PrinterCommandFeed(2),
        PrinterCommandImage(buildTestImage(40, 30)),
        PrinterCommandQRCode('QR-DATA', align: PosAlign.right, size: 5),
        PrinterCommandBarcode(73, '{BABC', align: PosAlign.left, height: 60),
        PrinterCommandText('Underline',
            style: const PrinterCommandStyle(underline: true)),
        PrinterCommandCut(full: false),
      ]);

      doc.print(printer);

      var cmds = DecoderEscPos(lenient: true).decode(printer.toBytes());
      var docs = const EscPosToPrinterDocument().convert(cmds);

      expect(docs.length, equals(1));
      var commands = docs.single.commands;

      var title = commands.whereType<PrinterCommandText>().first;
      expect(title.text, equals('Title'));
      expect(title.style?.bold, isTrue);
      expect(title.style?.align, equals(PosAlign.center));
      expect(title.style?.width, equals(2));
      expect(title.style?.height, equals(2));

      expect(commands.whereType<PrinterCommandHR>(), isNotEmpty);
      expect(commands.whereType<PrinterCommandText>().map((e) => e.text),
          containsAll(['Line 1', 'Underline']));
      expect(
          commands
              .whereType<PrinterCommandText>()
              .firstWhere((e) => e.text == 'Underline')
              .style
              ?.underline,
          isTrue);

      var image = commands.whereType<PrinterCommandImage>().single;
      expectSamePixels(image.image, buildTestImage(40, 30));
      expect(image.align, equals(PosAlign.center));

      var qr = commands.whereType<PrinterCommandQRCode>().single;
      expect(qr.data, equals('QR-DATA'));
      expect(qr.size, equals(5));
      expect(qr.align, equals(PosAlign.right));

      var barcode = commands.whereType<PrinterCommandBarcode>().single;
      expect(barcode.data, equals('{BABC'));
      expect(barcode.typeName, equals('code128'));
      expect(barcode.height, equals(60));

      expect(commands.last, isA<PrinterCommandCut>());
      expect((commands.last as PrinterCommandCut).full, isFalse);

      // JSON round-trip:
      var json = docs.single.toJson();
      var doc2 = PrinterDocument.fromJson(json);
      expect(doc2.toJson(), equals(json));
    });

    test('documents split by cut and end_job; empty documents dropped', () {
      var bytes = [
        ...'Doc 1\n'.codeUnits,
        gs, 0x56, 0, //
        ...'Doc 2\n'.codeUnits,
        0x0C, //
        ...'\n\n'.codeUnits, gs, 0x56, 1, // empty (dropped)
        ...'Doc 3\n'.codeUnits,
      ];

      var docs = const EscPosToPrinterDocument()
          .convert(DecoderEscPos().decode(bytes));

      expect(
          docs.map(
              (d) => d.commands.whereType<PrinterCommandText>().single.text),
          ['Doc 1', 'Doc 2', 'Doc 3']);
    });

    test('tabs, absolute positions and feeds', () {
      var bytes = [
        ...'A\tB\n'.codeUnits,
        ...'X'.codeUnits, esc, 0x24, 120, 0,
        ...'Y\n'.codeUnits, // 120 dots = 10 cols
        ...'\n\n'.codeUnits,
        esc, 0x64, 2, //
        ...'End\n'.codeUnits,
      ];

      var doc = const EscPosToPrinterDocument()
          .convert(DecoderEscPos().decode(bytes))
          .single;

      var json = doc.commands.map((e) => e.toJson()).toList();
      expect(json, [
        {'type': 'text', 'text': 'A       B'},
        {'type': 'text', 'text': 'X         Y'},
        {'type': 'feed', 'n': 4},
        {'type': 'text', 'text': 'End'},
      ]);
    });

    test('PrinterDocument.fromJson(ignoreUnknownCommands)', () {
      var json = {
        'commands': [
          {'type': 'text', 'text': 'A'},
          {'type': 'future_command'},
        ]
      };

      expect(() => PrinterDocument.fromJson(json), throwsArgumentError);
      expect(
          PrinterDocument.fromJson(json, ignoreUnknownCommands: true)
              .commands
              .length,
          equals(1));
    });
  });
}
