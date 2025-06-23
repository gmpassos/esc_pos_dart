import 'dart:typed_data';

import 'package:esc_pos_dart/esc_pos_dart.dart';
import 'package:image/image.dart';
import 'package:intl/intl.dart';
import 'package:resource_portable/resource.dart';

Future<void> main(List<String> args) async {
  var ip = args[0];
  var port = args.length > 1 ? int.parse(args[1]) : 9100;

  print('** Printing to> $ip $port');

  var profiles = await CapabilityProfile.getAvailableProfiles();

  for (var p in profiles) {
    print('-- $p');
  }

  var profile = await CapabilityProfile.load();

  final printer = NetworkPrinter(PaperSize.mm80, profile);

  final res = await printer.connect(ip, port: port);

  print('-- Printer connection: $res');

  var printOK1 = await printHelloWorld(printer);
  print('-- Print(1) finished: ${printOK1 ? 'OK' : 'FAIL'}');

  await printer.ensureConnected();

  var printOK2 = await printDemoReceipt(printer);
  print('-- Print(2) finished: ${printOK2 ? 'OK' : 'FAIL'}');
}

Future<bool> printHelloWorld(NetworkPrinter printer) async {
  print('-----------------------------------------------------------------');
  print('** Printing Hello World:');

  printer.feed(1);

  printer.hr();
  printer.text('Hello', styles: PosStyles(align: PosAlign.left));
  printer.text('World!', styles: PosStyles(align: PosAlign.right));
  printer.hr();

  printer.feed(1);
  printer.cut();
  printer.feed(1);

  printer.endJob();

  printer.disconnect(delayMs: 300);

  return true;
}

Future<bool> printDemoReceipt(NetworkPrinter printer) async {
  print('-----------------------------------------------------------------');
  print('** Printing demo receipt:');

  // Print image
  final bytes =
      await Resource('package:esc_pos_dart/resources/rabbit_black.jpg')
          .readAsBytes();
  final image = decodeImage(Uint8List.fromList(bytes))!;

  printer.image(image);

  printer.text('GROCERYLY',
      styles: PosStyles(
        align: PosAlign.center,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ),
      linesAfter: 1);

  printer.text('889  Watson Lane', styles: PosStyles(align: PosAlign.center));
  printer.text('New Braunfels, TX', styles: PosStyles(align: PosAlign.center));
  printer.text('Tel: 830-221-1234', styles: PosStyles(align: PosAlign.center));
  printer.text('Web: www.example.com',
      styles: PosStyles(align: PosAlign.center), linesAfter: 1);

  printer.hr();

  printer.row([
    PosColumn(text: 'Qty', width: 1),
    PosColumn(text: 'Item', width: 7),
    PosColumn(
        text: 'Price', width: 2, styles: PosStyles(align: PosAlign.right)),
    PosColumn(
        text: 'Total', width: 2, styles: PosStyles(align: PosAlign.right)),
  ]);

  printer.row([
    PosColumn(text: '2', width: 1),
    PosColumn(text: 'ONION RINGS', width: 7),
    PosColumn(text: '0.99', width: 2, styles: PosStyles(align: PosAlign.right)),
    PosColumn(text: '1.98', width: 2, styles: PosStyles(align: PosAlign.right)),
  ]);

  printer.row([
    PosColumn(text: '1', width: 1),
    PosColumn(text: 'PIZZA', width: 7),
    PosColumn(text: '3.45', width: 2, styles: PosStyles(align: PosAlign.right)),
    PosColumn(text: '3.45', width: 2, styles: PosStyles(align: PosAlign.right)),
  ]);

  printer.row([
    PosColumn(text: '1', width: 1),
    PosColumn(text: 'SPRING ROLLS', width: 7),
    PosColumn(text: '2.99', width: 2, styles: PosStyles(align: PosAlign.right)),
    PosColumn(text: '2.99', width: 2, styles: PosStyles(align: PosAlign.right)),
  ]);

  printer.row([
    PosColumn(text: '3', width: 1),
    PosColumn(text: 'CRUNCHY STICKS', width: 7),
    PosColumn(text: '0.85', width: 2, styles: PosStyles(align: PosAlign.right)),
    PosColumn(text: '2.55', width: 2, styles: PosStyles(align: PosAlign.right)),
  ]);

  printer.hr();

  printer.row([
    PosColumn(
        text: 'TOTAL',
        width: 6,
        styles: PosStyles(
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        )),
    PosColumn(
        text: '\$10.97',
        width: 6,
        styles: PosStyles(
          align: PosAlign.right,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        )),
  ]);

  printer.hr(ch: '=', linesAfter: 1);

  printer.row([
    PosColumn(
        text: 'Cash',
        width: 8,
        styles: PosStyles(align: PosAlign.right, width: PosTextSize.size2)),
    PosColumn(
        text: '\$15.00',
        width: 4,
        styles: PosStyles(align: PosAlign.right, width: PosTextSize.size2)),
  ]);

  printer.row([
    PosColumn(
        text: 'Change',
        width: 8,
        styles: PosStyles(align: PosAlign.right, width: PosTextSize.size2)),
    PosColumn(
        text: '\$4.03',
        width: 4,
        styles: PosStyles(align: PosAlign.right, width: PosTextSize.size2)),
  ]);

  printer.feed(2);
  printer.text('Thank you!',
      styles: PosStyles(align: PosAlign.center, bold: true));

  final now = DateTime.now();
  final formatter = DateFormat('MM/dd/yyyy H:m');
  final timestamp = formatter.format(now);

  printer.text(timestamp,
      styles: PosStyles(align: PosAlign.center), linesAfter: 2);

  printer.feed(1);
  printer.cut();
  printer.feed(1);

  printer.endJob();

  printer.disconnect(delayMs: 300);

  return true;
}
