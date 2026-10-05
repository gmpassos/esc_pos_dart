@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:esc_pos_dart/esc_pos_dart.dart';
import 'package:image/image.dart';
import 'package:test/test.dart';

/// A fake network printer (a local [ServerSocket]).
class FakePrinter {
  final ServerSocket server;
  final List<Socket> sockets = [];
  final BytesBuilder received = BytesBuilder();

  /// Reply for each received chunk (e.g. a status byte).
  List<int>? Function(List<int> chunk)? reply;

  /// If `true`, the reading is paused for a while (a slow printer).
  bool slow = false;

  final _done = <Completer<void>>[];

  FakePrinter._(this.server) {
    server.listen((socket) {
      sockets.add(socket);
      var done = Completer<void>();
      _done.add(done);

      late StreamSubscription<Uint8List> sub;
      sub = socket.listen(
        (chunk) {
          received.add(chunk);
          var r = reply?.call(chunk);
          if (r != null) socket.add(r);
          if (slow) {
            sub.pause(Future.delayed(Duration(milliseconds: 20)));
          }
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        onError: (_) {
          if (!done.isCompleted) done.complete();
        },
      );
    });
  }

  static Future<FakePrinter> start() async =>
      FakePrinter._(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0));

  int get port => server.port;

  /// Waits until [connections] connections were accepted and closed by the
  /// client.
  /// - The server may accept a connection after the client already wrote and
  ///   closed it: wait for the accepted connections first.
  Future<void> waitClosed({int connections = 1}) async {
    var timeout = DateTime.now().add(Duration(seconds: 10));

    while (_done.length < connections) {
      if (DateTime.now().isAfter(timeout)) {
        throw TimeoutException('Connections not accepted: $connections');
      }
      await Future.delayed(Duration(milliseconds: 10));
    }

    await Future.wait(_done.map((c) => c.future))
        .timeout(timeout.difference(DateTime.now()));
  }

  Future<void> close() async {
    for (var s in sockets) {
      s.destroy();
    }
    await server.close();
  }
}

PrinterDocument buildDocument() => PrinterDocument(commands: [
      PrinterCommandText('Hello',
          style: const PrinterCommandStyle(bold: true, align: PosAlign.center)),
      PrinterCommandHR(),
      PrinterCommandQRCode('QR'),
      PrinterCommandCut(),
    ]);

void main() {
  late CapabilityProfile profile;
  late FakePrinter fake;

  setUpAll(() async {
    profile = await CapabilityProfile.load();
  });

  setUp(() async {
    fake = await FakePrinter.start();
  });

  tearDown(() => fake.close());

  NetworkPrinter newPrinter() => NetworkPrinter(PaperSize.mm80, profile);

  test('default port', () {
    expect(NetworkPrinter.defaultPort, equals(9100));
  });

  test('print: received bytes == BytesPrinter bytes', () async {
    var printer = newPrinter();

    var r = await printer.connect('127.0.0.1', port: fake.port);
    expect(r, equals(PosPrintResult.success));
    expect(printer.isConnected, isTrue);
    expect(printer.host, equals('127.0.0.1'));
    expect(printer.port, equals(fake.port));

    buildDocument().print(printer);
    await printer.disconnect();
    expect(printer.isConnected, isFalse);

    await fake.waitClosed();

    var bytesPrinter = BytesPrinter(PaperSize.mm80, profile);
    buildDocument().print(bytesPrinter);

    expect(fake.received.toBytes(), equals(bytesPrinter.toBytes()));
  });

  test('disconnect sends all the pending data (slow printer)', () async {
    fake.slow = true;

    var printer = newPrinter();
    await printer.connect('127.0.0.1', port: fake.port);

    // A large image (~70 KB of raster data):
    var image = Image(width: 576, height: 1000);
    fill(image, color: ColorRgb8(0, 0, 0));
    printer.imageRaster(image);
    printer.text('END');

    var expectedLength = BytesPrinter(PaperSize.mm80, profile)
      ..imageRaster(image)
      ..text('END');

    await printer.disconnect();
    await fake.waitClosed();

    expect(fake.received.length, equals(expectedLength.toBytes().length));
  });

  test('transmissionOfStatus', () async {
    fake.reply =
        (chunk) => chunk.length >= 2 && chunk[0] == 0x1D ? [0x12] : null;

    var printer = newPrinter();
    await printer.connect('127.0.0.1', port: fake.port);

    var status = await printer.transmissionOfStatus(n: 1);
    expect(status, equals(0x02)); // 0x12 without the reserved bits

    await printer.disconnect();
  });

  test('transmissionOfStatus timeout (no reply)', () async {
    var printer = newPrinter();
    await printer.connect('127.0.0.1', port: fake.port);

    var status = await printer.transmissionOfStatus(
        n: 1, timeout: Duration(milliseconds: 200));
    expect(status, isNull);

    await printer.disconnect();
  });

  test('connection closed by the printer: no crash, not connected', () async {
    var printer = newPrinter();
    await printer.connect('127.0.0.1', port: fake.port);

    // Wait the server side socket:
    var t0 = DateTime.now();
    while (fake.sockets.isEmpty &&
        DateTime.now().difference(t0) < Duration(seconds: 5)) {
      await Future.delayed(Duration(milliseconds: 10));
    }

    fake.sockets.single.destroy();

    t0 = DateTime.now();
    while (printer.isConnected &&
        DateTime.now().difference(t0) < Duration(seconds: 5)) {
      await Future.delayed(Duration(milliseconds: 10));
    }
    expect(printer.isConnected, isFalse);

    // A status request on a closed connection returns `null`:
    expect(await printer.transmissionOfStatus(), isNull);

    // Reconnects:
    expect(await printer.ensureConnected(), equals(PosPrintResult.success));
    await printer.disconnect();
  });

  test('connect to another port reconnects', () async {
    var fake2 = await FakePrinter.start();
    try {
      var printer = newPrinter();
      await printer.connect('127.0.0.1', port: fake.port);
      await printer.connect('127.0.0.1', port: fake2.port);
      expect(printer.port, equals(fake2.port));

      printer.text('B');
      await printer.disconnect();
      await fake2.waitClosed();

      expect(fake2.received.length, greaterThan(0));
      expect(fake.received.length, equals(0));
    } finally {
      await fake2.close();
    }
  });

  test('connection refused / not connected', () async {
    var printer = newPrinter();

    // Not connected:
    expect(() => printer.text('X'), throwsStateError);
    expect(await printer.ensureConnected(), equals(PosPrintResult.timeout));
    await printer.disconnect(); // No error.

    var port = fake.port;
    await fake.close();

    var r = await printer.connect('127.0.0.1',
        port: port, timeout: Duration(seconds: 2));
    expect(r, equals(PosPrintResult.timeout));
    expect(printer.isConnected, isFalse);
  });
}
