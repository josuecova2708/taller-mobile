import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_bluetooth_serial_plus/flutter_bluetooth_serial_plus.dart';

class BluetoothService {
  BluetoothConnection? _connection;
  final StreamController<String> _incomingBufferController =
      StreamController<String>.broadcast();
  String _currentBuffer = '';

  bool get isConnected => _connection != null && _connection!.isConnected;

  Future<List<BluetoothDevice>> getPairedDevices() async {
    try {
      return await FlutterBluetoothSerial.instance.getBondedDevices();
    } catch (_) {
      return [];
    }
  }

  Future<void> connect(String address) async {
    await disconnect();
    _connection = await BluetoothConnection.toAddress(address);
    _connection!.input.listen(
      (Uint8List data) {
        final chunk = ascii.decode(data, allowInvalid: true);
        _currentBuffer += chunk;
        if (_currentBuffer.contains('>')) {
          _incomingBufferController.add(_currentBuffer);
        }
      },
      onDone: () {
        _connection = null;
      },
    );
  }

  /// Envía un comando AT/OBD esperando el carácter '>' del ELM327 para evitar desfase de buffer
  Future<String> sendCommand(
    String command, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (!isConnected) {
      throw StateError('No hay conexión Bluetooth activa con el ELM327');
    }

    // Limpiar buffer residual antes de enviar nuevo comando
    _currentBuffer = '';
    final completer = Completer<String>();

    late StreamSubscription<String> sub;
    sub = _incomingBufferController.stream.listen((response) {
      if (response.contains('>') && !completer.isCompleted) {
        completer.complete(response);
      }
    });

    _connection!.output.add(Uint8List.fromList(ascii.encode('$command\r')));
    await _connection!.output.allSent;

    try {
      return await completer.future.timeout(
        timeout,
        onTimeout: () => _currentBuffer.isNotEmpty ? _currentBuffer : 'TIMEOUT\r\r>',
      );
    } finally {
      await sub.cancel();
      _currentBuffer = '';
    }
  }

  Future<void> disconnect() async {
    try {
      await _connection?.close();
    } catch (_) {}
    _connection = null;
    _currentBuffer = '';
  }
}
