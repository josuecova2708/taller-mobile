import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_bluetooth_serial_plus/flutter_bluetooth_serial_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// Falla de Bluetooth con un mensaje que se le puede mostrar al inspector.
class BluetoothException implements Exception {
  final String message;

  BluetoothException(this.message);

  @override
  String toString() => message;
}

class BluetoothService {
  BluetoothConnection? _connection;
  final StreamController<String> _incomingBufferController =
      StreamController<String>.broadcast();
  String _currentBuffer = '';

  bool get isConnected => _connection != null && _connection!.isConnected;

  /// Pide los permisos de Bluetooth en tiempo de ejecución.
  ///
  /// Desde Android 12 no basta con declararlos en el manifiesto: sin
  /// `BLUETOOTH_CONNECT` concedido por el usuario, listar o conectar
  /// dispositivos falla. En versiones anteriores se conceden solos.
  Future<void> ensurePermissions() async {
    final Map<Permission, PermissionStatus> estados;
    try {
      estados = await [
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
      ].request();
    } on MissingPluginException {
      // Plataforma sin el plugin (escritorio o web): no hay permisos que pedir.
      return;
    }

    final conexion = estados[Permission.bluetoothConnect];
    if (conexion == null || conexion.isGranted) return;

    throw BluetoothException(
      conexion.isPermanentlyDenied
          ? 'El permiso de Bluetooth está bloqueado. Actívelo en Ajustes > '
              'Aplicaciones > Permisos > Dispositivos cercanos.'
          : 'La aplicación necesita el permiso de Bluetooth ("Dispositivos '
              'cercanos") para conectarse al adaptador.',
    );
  }

  /// Adaptadores ya vinculados al teléfono.
  ///
  /// Lanza [BluetoothException] en lugar de devolver una lista vacía: una
  /// lista vacía no le dice al inspector si falta el permiso, si el Bluetooth
  /// está apagado o si simplemente no vinculó el adaptador.
  Future<List<BluetoothDevice>> getPairedDevices() async {
    await ensurePermissions();

    try {
      final encendido = await FlutterBluetoothSerial.instance.isEnabled;
      if (encendido == false) {
        throw BluetoothException(
          'El Bluetooth del teléfono está apagado. Enciéndalo e intente de nuevo.',
        );
      }
      return await FlutterBluetoothSerial.instance.getBondedDevices();
    } on BluetoothException {
      rethrow;
    } catch (e) {
      throw BluetoothException(
        'No se pudieron leer los dispositivos Bluetooth vinculados: $e',
      );
    }
  }

  Future<void> connect(String address) async {
    await ensurePermissions();
    await disconnect();
    try {
      _connection = await BluetoothConnection.toAddress(address);
    } catch (_) {
      throw BluetoothException(
        'No se pudo conectar con el adaptador. Verifique que esté enchufado '
        'al puerto OBD-II y que no esté en uso por otra aplicación.',
      );
    }
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
