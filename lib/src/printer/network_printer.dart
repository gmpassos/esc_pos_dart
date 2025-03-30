/*
 * esc_pos_printer
 * Created by Andrey Ushakov
 * Improved by Graciliano M. Passos.
 *
 * Copyright (c) 2019-2020. All rights reserved.
 * See LICENSE for distribution and usage details.
 */

import 'dart:async';
import 'dart:io';
import 'dart:typed_data' show Uint8List;

import 'enums.dart';
import 'generic_printer.dart';

/// Network ESC/POS Printer.
class NetworkPrinter extends GenericPrinter {
  NetworkPrinter(super._paperSize, super._profile,
      {super.spaceBetweenRows, super.generator});

  String? _host;

  String? get host => _host;

  int? _port;

  int? get port => _port;

  late Socket _socket;
  final List<int> _inputBytes = <int>[];

  bool _connected = false;

  bool get isConnected => _connected;

  Future<PosPrintResult> connect(String host,
      {int port = 91000, Duration timeout = const Duration(seconds: 5)}) async {
    _host = host;
    _port = port;
    return await ensureConnected(timeout: timeout);
  }

  Future<PosPrintResult> ensureConnected(
      {Duration timeout = const Duration(seconds: 5)}) async {
    if (_connected) {
      return PosPrintResult.success;
    }

    try {
      var host = _host;
      var port = _port;

      if (host == null || port == null) {
        throw StateError("Call `connect` first to define `host` and `port`!");
      }

      _socket = await Socket.connect(host, port, timeout: timeout);
      _connected = true;

      _socket.listen(_addInputBytes);
      _socket.add(generator.reset());

      return Future<PosPrintResult>.value(PosPrintResult.success);
    } catch (e) {
      return Future<PosPrintResult>.value(PosPrintResult.timeout);
    }
  }

  /// Closes the printer [Socket] and disposes any received byte in buffer.
  /// [delayMs]: milliseconds to wait after destroying the socket
  Future<void> disconnect({int? delayMs}) async {
    if (delayMs != null && delayMs > 0) {
      await Future.delayed(Duration(milliseconds: delayMs));
    }

    _connected = false;
    _socket.destroy();
    _disposeInputBytes();
  }

  @override
  void writeBytes(List<int> bytes) => _socket.add(bytes);

  void _disposeInputBytes() {
    _inputBytes.clear();
  }

  void _addInputBytes(Uint8List bs) {
    _inputBytes.addAll(bs);
    _notifyInputBytes();
  }

  void _notifyInputBytes() {
    var completer = _waitingBytes;
    if (completer != null && !completer.isCompleted) {
      _waitingBytes = null;
      completer.complete(true);
    }
  }

  Completer<bool>? _waitingBytes;

  Future<bool> _waitInputByte() {
    var completer = _waitingBytes;
    if (completer != null) {
      return completer.future;
    }

    completer = _waitingBytes = Completer<bool>();

    var future = completer.future.then((ok) {
      if (identical(_waitingBytes, completer)) {
        _waitingBytes = null;
      }
      return ok;
    });

    return future;
  }

  Future<int?> transmissionOfStatus({int n = 1}) async {
    var waitFuture = _waitInputByte();
    writeBytes(generator.transmissionOfStatus(n: n));

    await waitFuture;

    var status = _inputBytes.lastOrNull;
    if (status != null) {
      // Remove reserved bits:
      status = status & 0x0F;
    }
    return status;
  }
}
