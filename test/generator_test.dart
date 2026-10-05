import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:esc_pos_dart/esc_pos_dart.dart';
import 'package:esc_pos_dart/src/utils/char_encoder.dart';
import 'package:image/image.dart';
import 'package:test/test.dart';

const esc = 0x1B;
const gs = 0x1D;

/// A test image with an asymmetric pattern (black on white).
Image buildTestImage(int width, int height, {int numChannels = 3}) {
  var image = Image(width: width, height: height, numChannels: numChannels);
  fill(image, color: ColorRgb8(255, 255, 255));
  for (var y = 2; y < math.min(10, height); ++y) {
    for (var x = 3; x < math.min(15, width); ++x) {
      image.setPixelRgb(x, y, 0, 0, 0);
    }
  }
  for (var i = 0; i < math.min(width, height); ++i) {
    image.setPixelRgb(i, i, 0, 0, 0);
  }
  return image;
}

/// Black pixel (the red channel works for 1-channel and RGB(A) gray images).
bool isBlack(Image image, int x, int y) => image.getPixel(x, y).r < 128;

int countBlack(Image image) {
  var n = 0;
  for (var y = 0; y < image.height; ++y) {
    for (var x = 0; x < image.width; ++x) {
      if (isBlack(image, x, y)) ++n;
    }
  }
  return n;
}

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

String decodedText(List<int> bytes, {bool codeTable = false}) => DecoderEscPos(
      lenient: true,
      textDecoding:
          codeTable ? EscPosTextDecoding.codeTable : EscPosTextDecoding.latin1,
    ).decode(bytes).whereType<CommandEscPosText>().map((t) => t.text).join();

void main() {
  late CapabilityProfile profile;
  late GeneratorEscPos generator;

  setUpAll(() async {
    profile = await CapabilityProfile.load();
  });

  setUp(() {
    generator = GeneratorEscPos(PaperSize.mm80, profile);
  });

  group('GeneratorEscPos: row', () {
    test('overflowing text continues in the next rows', () {
      var bytes = generator.row([
        PosColumn(text: 'A' * 40, width: 6),
        PosColumn(text: 'B', width: 6),
      ]);

      var text = decodedText(bytes);
      expect('A'.allMatches(text).length, equals(40));
      expect('B'.allMatches(text).length, equals(1));
    });

    test('a column narrower than 1 char (no infinite recursion)', () {
      var bytes = generator.row([
        PosColumn(
            text: 'abc',
            width: 1,
            styles: const PosStyles(
                width: PosTextSize.size8, height: PosTextSize.size8)),
        PosColumn(text: 'x', width: 11),
      ]);

      expect(decodedText(bytes), allOf(contains('a'), contains('c')));
    });

    test('Chinese column: one absolute position per column', () {
      var bytes = generator.row([
        PosColumn(text: 'ab中文cd', width: 12, containsChinese: true),
      ]);

      var positions = DecoderEscPos(lenient: true)
          .decode(bytes)
          .where((c) => c.name == 'absolute_pos');
      expect(positions.length, equals(1));
    });

    test('invalid widths', () {
      expect(() => generator.row([PosColumn(text: 'a', width: 6)]),
          throwsException);
    });
  });

  group('GeneratorEscPos: images', () {
    for (var channels in [1, 3, 4]) {
      test('image (ESC *) with $channels channel(s)', () {
        var source = buildTestImage(40, 30, numChannels: channels);
        var bytes = generator.image(source);

        var stripes = DecoderEscPos()
            .decode(bytes)
            .whereType<CommandEscPosBitImage>()
            .toList();

        var image = const EscPosToPrinterDocument()
            .convert(DecoderEscPos().decode([...bytes, 0x0C]))
            .single
            .commands
            .whereType<PrinterCommandImage>()
            .single
            .image;

        expect(stripes, isNotEmpty);
        expectSamePixels(image, buildTestImage(40, 30));
      });

      test('imageRaster (GS v 0) with $channels channel(s)', () {
        var source = buildTestImage(37, 21, numChannels: channels);
        var raster = DecoderEscPos()
            .decode(generator.imageRaster(source))
            .whereType<CommandEscPosRasterImage>()
            .single;
        expectSamePixels(raster.toImage(), buildTestImage(37, 21));
      });
    }

    test('height multiple of 24: no extra stripe', () {
      var stripes = DecoderEscPos()
          .decode(generator.image(buildTestImage(30, 48)))
          .whereType<CommandEscPosBitImage>()
          .toList();
      expect(stripes.length, equals(2));
    });

    test('transparent pixels print white', () {
      var image = Image(width: 16, height: 4, numChannels: 4);
      // All transparent black (0,0,0,0), one opaque black pixel:
      image.setPixelRgba(1, 1, 0, 0, 0, 255);

      var raster = DecoderEscPos()
          .decode(generator.imageRaster(image))
          .whereType<CommandEscPosRasterImage>()
          .single;

      var decoded = raster.toImage();
      expect(countBlack(decoded), equals(1));
      expect(isBlack(decoded, 1, 1), isTrue);
    });

    test('imageRaster density flags', () {
      CommandEscPosRasterImage raster({bool h = true, bool v = true}) =>
          DecoderEscPos()
              .decode(generator.imageRaster(buildTestImage(16, 8),
                  highDensityHorizontal: h, highDensityVertical: v))
              .whereType<CommandEscPosRasterImage>()
              .single;

      expect(raster().mode, equals(0));
      // Low horizontal density = double width:
      expect(raster(h: false).scaleX, equals(2));
      expect(raster(h: false).scaleY, equals(1));
      // Low vertical density = double height:
      expect(raster(v: false).scaleY, equals(2));
    });

    test('imageRaster (graphics) larger than 64KB: GS 8 L', () {
      var source = buildTestImage(576, 1000);
      var bytes = generator.imageRaster(source, imageFn: PosImageFn.graphics);

      // `GS 8 L`:
      var gs8L = [gs, 0x38, 0x4C];
      var index = List.generate(bytes.length - 2, (i) => i).firstWhere((i) =>
          bytes[i] == gs8L[0] &&
          bytes[i + 1] == gs8L[1] &&
          bytes[i + 2] == gs8L[2]);
      expect(index, greaterThanOrEqualTo(0));

      var raster = DecoderEscPos()
          .decode(bytes)
          .whereType<CommandEscPosRasterImage>()
          .single;
      expect(raster.widthBytes, equals(72));
      expect(raster.height, equals(1000));
      expectSamePixels(raster.toImage(), source);
    });
  });

  group('GeneratorEscPos: QR Code', () {
    test('data larger than 252 bytes (2-byte length)', () {
      var data = 'Q' * 600;
      var qr = DecoderEscPos()
          .decode(generator.qrcode(data))
          .whereType<CommandEscPosQRCode>()
          .single;
      expect(qr.data, equals(data));
    });

    test('data too long', () {
      expect(() => generator.qrcode('Q' * (QRCode.maxDataLength + 1)),
          throwsArgumentError);
    });
  });

  group('GeneratorEscPos: code tables', () {
    test('reset: text encoded with the announced table (CP437)', () {
      var bytes = [...generator.reset(), ...generator.text('é')];

      // `é` in CP437 is 0x82 (latin1 would be 0xE9):
      expect(bytes, containsAllInOrder([0x82, 0x0A]));
      expect(bytes.contains(0xE9), isFalse);
      expect(decodedText(bytes, codeTable: true), equals('é\n'));
    });

    test('selectCharCodeTable (CP1252)', () {
      var bytes = [
        ...generator.reset(),
        ...generator.selectCharCodeTable(codeTable: 16),
        ...generator.text('é€'),
      ];

      expect(bytes, containsAllInOrder([0xE9, 0x80]));
      expect(generator.codeTable, equals('CP1252'));
      expect(decodedText(bytes, codeTable: true), equals('é€\n'));
    });

    test('setStyles(codeTable) switches the encoder', () {
      var bytes = [
        ...generator.reset(),
        ...generator.text('ç', styles: const PosStyles(codeTable: 'CP850')),
      ];

      expect(decodedText(bytes, codeTable: true), contains('ç'));
    });

    test('printCodeTable restores the table and skips control bytes', () {
      generator.reset();
      var bytes = generator.printCodeTable(codeTable: 'CP850');

      var tables = DecoderEscPos(lenient: true)
          .decode(bytes)
          .whereType<CommandEscPosTable>()
          .map((t) => t.id)
          .toList();
      expect(tables, [2, 0]);
      expect(generator.codeTable, equals('CP437'));
    });
  });

  group('GeneratorEscPos: other commands', () {
    test('hr(len, linesAfter)', () {
      var bytes = generator.hr(len: 5, linesAfter: 2);
      expect(decodedText(bytes), equals('-----\n\n\n'));
    });

    test('feed and reverseFeed > 255', () {
      var feeds = DecoderEscPos()
          .decode(generator.feed(300))
          .whereType<CommandEscPosFeed>()
          .map((f) => f.n);
      expect(feeds, [255, 45]);

      expect(generator.feed(0), isEmpty);
      expect(generator.reverseFeed(300).length, equals(6));
    });

    test('beep > 9', () {
      var beeps = DecoderEscPos()
          .decode(generator.beep(n: 12))
          .whereType<CommandEscPosBeep>()
          .map((b) => b.n);
      expect(beeps, [9, 3]);
      expect(generator.beep(n: 0), isEmpty);
    });

    test('drawer pins', () {
      var pins = DecoderEscPos()
          .decode([
            ...generator.drawer(pin: PosDrawer.pin2),
            ...generator.drawer(pin: PosDrawer.pin5),
          ])
          .whereType<CommandEscPosDrawer>()
          .map((d) => d.pin);
      expect(pins, [0, 1]);
    });

    test('transmissionOfStatus', () {
      expect(generator.transmissionOfStatus(n: 2), [gs, 0x72, 2]);
    });

    test('styles are restored without a reset', () {
      var bytes = [
        ...generator.text('Big',
            styles: const PosStyles(
                width: PosTextSize.size2, height: PosTextSize.size2)),
        ...generator.text('Normal'),
      ];

      var sizes = DecoderEscPos()
          .decode(bytes)
          .whereType<CommandEscPosFontSize>()
          .map((s) => '${s.widthSize}x${s.heightSize}')
          .toList();
      expect(sizes, ['2x2', '1x1']);
    });

    test('code128 with the code set prefix', () {
      var barcode = Barcode.code128(['{A', '1', '2']);
      expect(utf8.decode(barcode.data!), equals('{A12'));
    });
  });

  group('Barcode', () {
    test('valid', () {
      expect(Barcode.upcA('12345678901'.split('')).type, BarcodeType.upcA);
      expect(Barcode.upcE('012345'.split('')).type, BarcodeType.upcE);
      expect(Barcode.ean13('123456789012'.split('')).type, BarcodeType.ean13);
      expect(Barcode.ean8('1234567'.split('')).type, BarcodeType.ean8);
      expect(Barcode.code39('ABC-123'.split('')).type, BarcodeType.code39);
      expect(Barcode.itf('1234'.split('')).type, BarcodeType.itf);
      expect(Barcode.codabar('A123B'.split('')).type, BarcodeType.codabar);
      expect(Barcode.code128('{B12'.split('')).type, BarcodeType.code128);
    });

    test('invalid', () {
      expect(() => Barcode.upcA('123'.split('')), throwsException);
      expect(() => Barcode.upcA('1234567890A'.split('')), throwsException);
      expect(() => Barcode.ean13('12'.split('')), throwsException);
      expect(() => Barcode.ean8('1'.split('')), throwsException);
      expect(() => Barcode.itf('123'.split('')), throwsException);
      expect(() => Barcode.code128(['1']), throwsException);
    });

    test('BarcodeType', () {
      expect(BarcodeType.fromValue(73), same(BarcodeType.code128));
      expect(BarcodeType.fromValue(72).name, equals('code93'));
      expect(BarcodeType.fromValue(200).name, equals('type200'));
      expect(BarcodeType.fromValue(4), equals(BarcodeType.code39));
      expect(BarcodeType.code39.toString(), contains('code39'));
    });

    test('raw', () {
      var b = Barcode.raw(BarcodeType.fromValue(4), 'X1'.codeUnits);
      expect(b.data, 'X1'.codeUnits);
    });
  });

  group('CapabilityProfile', () {
    test('code pages', () {
      expect(profile.getCodePageId('CP850'), equals(2));
      // Case-insensitive:
      expect(profile.getCodePageId('cp850'), equals(2));
      expect(() => profile.getCodePageId('XYZ'), throwsException);

      expect(profile.getCodePageName(16), equals('CP1252'));
      expect(profile.getCodePageName(6), isNull); // 'Unknown'
      expect(profile.getCodePageName(9999), isNull);
    });

    test('profiles', () async {
      var profiles = await CapabilityProfile.getAvailableProfiles();
      expect(profiles.map((p) => p['key']), contains('default'));

      expect(() => CapabilityProfile.load(name: 'no-such-profile'),
          throwsException);
    });
  });

  group('char_encoder', () {
    test('codePageCharset', () {
      expect(codePageCharset('CP437'), equals('cp437'));
      expect(codePageCharset('cp850'), equals('cp850'));
      expect(codePageCharset('CP1252'), equals('windows1252'));
      expect(codePageCharset('CP874'), equals('windows874'));
      expect(codePageCharset('ISO_8859-15'), equals('latin-9'));
      expect(codePageCharset('ISO_8859-7'), equals('greek'));
      expect(codePageCharset('Unknown'), isNull);
      expect(codePageCharset(null), isNull);
    });

    test('encode/decode', () {
      for (var cs in ['cp437', 'cp850', 'cp858', 'windows1252', 'latin-2']) {
        var bytes = getCharsetEncoder(cs)!.convert('Açé');
        expect(getCharsetDecoder(cs)!.convert(bytes), equals('Açé'),
            reason: cs);
      }
      expect(getCharsetEncoder('nope'), isNull);
      expect(getCharsetDecoder(null), isNull);
      expect(encodeChars('abc', charset: 'cp437'), 'abc'.codeUnits);
      // Unsupported chars fall back to UTF-8:
      expect(encodeChars('☕'), utf8.encode('☕'));
    });
  });

  group('GenericPrinter', () {
    test('delegates every command to the generator', () {
      var image = buildTestImage(16, 8);
      var columns = [
        PosColumn(text: 'L', width: 6),
        PosColumn(text: 'R', width: 6),
      ];

      // The same commands, with a printer and with an independent generator:
      var printer = BytesPrinter(PaperSize.mm80, profile);
      var gen = GeneratorEscPos(PaperSize.mm80, profile);

      printer.reset();
      printer.selectCharCodeTable(codeTable: 16);
      printer.text('Text', linesAfter: 1);
      printer.setGlobalCodeTable('CP850');
      printer.setGlobalFont(PosFontType.fontB);
      printer.setStyles(const PosStyles(bold: true));
      printer.rawBytes([0x41, 0x42]);
      printer.emptyLines(2);
      printer.feed(1);
      printer.cut(mode: PosCutMode.partial);
      printer.printCodeTable();
      printer.beep(n: 1);
      printer.reverseFeed(1);
      printer.row(columns);
      printer.image(image);
      printer.imageRaster(image);
      printer.barcode(Barcode.code39('A1'.split('')));
      printer.qrcode('QR');
      printer.drawer();
      printer.hr(len: 3);
      printer.textEncoded(Uint8List.fromList('enc'.codeUnits));
      printer.endJob();

      var expected = [
        ...gen.reset(),
        ...gen.selectCharCodeTable(codeTable: 16),
        ...gen.text('Text', linesAfter: 1),
        ...gen.setGlobalCodeTable('CP850'),
        ...gen.setFont(PosFontType.fontB),
        ...gen.setStyles(const PosStyles(bold: true)),
        ...gen.rawBytes([0x41, 0x42]),
        ...gen.emptyLines(2),
        ...gen.feed(1),
        ...gen.cut(mode: PosCutMode.partial),
        ...gen.printCodeTable(),
        ...gen.beep(n: 1),
        ...gen.reverseFeed(1),
        ...gen.row(columns),
        ...gen.image(image),
        ...gen.imageRaster(image),
        ...gen.barcode(Barcode.code39('A1'.split(''))),
        ...gen.qrcode('QR'),
        ...gen.drawer(),
        ...gen.hr(len: 3),
        ...gen.textEncoded(Uint8List.fromList('enc'.codeUnits)),
        ...gen.endJob(),
      ];

      expect(printer.toBytes(), equals(expected));
      expect(printer.paperSize, equals(PaperSize.mm80));
      expect(printer.profile, same(profile));

      printer.clear();
      expect(printer.toBytes(), isEmpty);
    });
  });

  group('enums', () {
    test('PosAlign / PosFontType', () {
      expect(PosAlign.from('center'), equals(PosAlign.center));
      expect(PosAlign.from(' RIGHT '), equals(PosAlign.right));
      expect(PosAlign.from(''), isNull);
      expect(PosAlign.from(null), isNull);

      expect(PosFontType.from('b'), equals(PosFontType.fontB));
      expect(PosFontType.from('fontA'), equals(PosFontType.fontA));
      expect(PosFontType.from(null), isNull);
    });

    test('PosTextSize', () {
      for (var w in PosTextSize.values) {
        for (var h in PosTextSize.values) {
          var n = PosTextSize.encodeSize(h, w);
          var decoded = PosTextSize.decodeSize(n);
          expect(decoded.width, equals(w));
          expect(decoded.height, equals(h));
        }
      }
      expect(PosTextSize.withValue(3), equals(PosTextSize.size3));
      expect(PosTextSize.withValue(9), isNull);
    });

    test('PaperSize / PosBeepDuration', () {
      expect(PaperSize.mm80.width, greaterThan(PaperSize.mm58.width));
      expect(PosBeepDuration.values.map((d) => d.value).toSet().length,
          equals(PosBeepDuration.values.length));
    });
  });

  group('charsets', () {
    test('all charset names', () {
      var names = [
        'latin-1', 'latin-2', 'latin-3', 'latin-4', 'latin-5', 'latin-6', //
        'latin-7', 'latin-8', 'latin-9', 'latin-10', 'cyrillic', 'arabic',
        'greek', 'hebrew', 'tis620', 'windows874', 'windows1250',
        'windows1251', 'windows1252', 'windows1253', 'windows1254',
        'windows1255', 'windows1256', 'windows1257', 'windows1258', 'cp437',
        'cp737', 'cp775', 'cp850', 'cp852', 'cp855', 'cp856', 'cp857',
        'cp858', 'cp860', 'cp861', 'cp862', 'cp863', 'cp864', 'cp865',
        'cp866', 'cp869', 'cp922', 'cp1046', 'cp1124', 'cp1125', 'cp1129',
        'cp1133', 'cp1161', 'cp1162', 'cp1163',
      ];

      for (var name in names) {
        var codePage = getCharsetCodePage(name);
        expect(codePage, isNotNull, reason: name);
        // ASCII is the same in all of them:
        expect(codePage!.decoder.convert('AZ09'.codeUnits), equals('AZ09'),
            reason: name);
      }

      expect(getCharsetCodePage(' CP850 '), isNotNull);
      expect(getCharsetCodePage(''), isNull);
    });

    test('CharCodeTableEscPos', () {
      for (var t in CharCodeTableEscPos.values) {
        expect(t.encoder, isNotNull, reason: t.name);
        expect(t.decoder, isNotNull, reason: t.name);
      }
      expect(
          CharCodeTableEscPos.fromCode(2), equals(CharCodeTableEscPos.pc850));
      expect(CharCodeTableEscPos.fromCode(255), isNull);
    });
  });

  group('PosPrintResult', () {
    test('msg', () {
      for (var r in [
        PosPrintResult.success,
        PosPrintResult.timeout,
        PosPrintResult.printerNotSelected,
        PosPrintResult.ticketEmpty,
        PosPrintResult.printInProgress,
        PosPrintResult.scanInProgress,
      ]) {
        expect(r.msg, isNotEmpty);
        expect(r.toString(), contains('${r.value}'));
      }
    });
  });
}
