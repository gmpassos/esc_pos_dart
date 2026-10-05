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
  /// The default ESC/POS network printer port (RAW/JetDirect).
  static const defaultPort = 9100;

  NetworkPrinter(super._paperSize, super._profile,
      {super.spaceBetweenRows, super.generator});

  String? _host;

  String? get host => _host;

  int? _port;

  int? get port => _port;

  Socket? _socket;
  final List<int> _inputBytes = <int>[];

  bool _connected = false;

  /// Returns `true` if connected (`false` after the connection is closed by
  /// the printer, an error, or [disconnect]).
  bool get isConnected => _connected;

  /// Connects to the printer at [host]:[port].
  /// - If already connected to another host/port, disconnects first.
  /// - Returns [PosPrintResult.timeout] if the connection fails.
  Future<PosPrintResult> connect(String host,
      {int port = defaultPort,
      Duration timeout = const Duration(seconds: 5)}) async {
    if (_connected && (host != _host || port != _port)) {
      await disconnect();
    }

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

      var socket = await Socket.connect(host, port, timeout: timeout);
      _socket = socket;
      _connected = true;
      _inputBytes.clear();

      socket.listen(
        _addInputBytes,
        onError: (_) => _onClosed(socket),
        onDone: () => _onClosed(socket),
        cancelOnError: true,
      );

      // Avoid an unhandled error if a write fails after the connection is lost:
      socket.done.catchError((_) => _onClosed(socket));

      return PosPrintResult.success;
    } catch (e) {
      return PosPrintResult.timeout;
    }
  }

  void _onClosed(Socket socket) {
    if (!identical(socket, _socket)) return;
    _connected = false;
    _notifyInputBytes(false);
  }

  /// Sends the buffered data to the printer.
  Future<void> flush() async {
    var socket = _socket;
    if (socket == null || !_connected) return;
    try {
      await socket.flush();
    } catch (_) {
      _onClosed(socket);
    }
  }

  /// Flushes the pending data and closes the printer [Socket] (disposing any
  /// received byte in buffer).
  /// - [delayMs]: milliseconds to wait before closing the socket.
  /// - [timeout]: the maximum time waiting for the pending data to be sent.
  Future<void> disconnect(
      {int? delayMs, Duration timeout = const Duration(seconds: 10)}) async {
    if (delayMs != null && delayMs > 0) {
      await Future.delayed(Duration(milliseconds: delayMs));
    }

    var socket = _socket;
    _connected = false;
    _socket = null;

    if (socket != null) {
      try {
        // Send the pending data before closing (`destroy` discards it):
        await socket.flush().timeout(timeout);
        await socket.close().timeout(timeout);
      } catch (_) {
        // ignore
      } finally {
        socket.destroy();
      }
    }

    _disposeInputBytes();
    _notifyInputBytes(false);
  }

  @override
  void writeBytes(List<int> bytes) {
    var socket = _socket;
    if (socket == null || !_connected) {
      throw StateError("Printer not connected: call `connect` first.");
    }
    socket.add(bytes);
  }

  void _disposeInputBytes() {
    _inputBytes.clear();
  }

  void _addInputBytes(Uint8List bs) {
    _inputBytes.addAll(bs);
    _notifyInputBytes(true);
  }

  void _notifyInputBytes(bool received) {
    var completer = _waitingBytes;
    if (completer != null && !completer.isCompleted) {
      _waitingBytes = null;
      completer.complete(received);
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

  /// Requests the printer status (`GS r n`) and returns the status byte
  /// (the low 4 bits), or `null` if the printer doesn't reply within
  /// [timeout] (or the connection is closed).
  Future<int?> transmissionOfStatus(
      {int n = 1, Duration timeout = const Duration(seconds: 5)}) async {
    if (!_connected) return null;

    // Ignore any previously received byte (e.g. ASB):
    _inputBytes.clear();

    var waitFuture = _waitInputByte();
    writeBytes(generator.transmissionOfStatus(n: n));
    await flush();

    var received = await waitFuture.timeout(timeout, onTimeout: () {
      _notifyInputBytes(false);
      return false;
    });

    if (!received) return null;

    var status = _inputBytes.lastOrNull;
    if (status != null) {
      // Remove reserved bits:
      status = status & 0x0F;
    }
    return status;
  }
}
