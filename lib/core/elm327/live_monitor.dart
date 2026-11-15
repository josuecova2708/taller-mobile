import 'elm327_service.dart';

/// Parámetros que muestra el monitor en vivo (CU09).
enum LiveParam { rpm, speed, coolant, throttle, voltage }

/// Último valor conocido de un parámetro.
class LiveValue {
  /// `null` si todavía no se leyó o si el vehículo no lo informa.
  final double? value;

  /// `false` cuando el vehículo no soporta el parámetro: se muestra como
  /// «No disponible» y se deja de consultar.
  final bool supported;

  const LiveValue({this.value, this.supported = true});

  static const unsupported = LiveValue(supported: false);
}

/// Foto de todos los parámetros después de un ciclo de lectura.
class LiveSnapshot {
  final Map<LiveParam, LiveValue> values;

  const LiveSnapshot(this.values);

  LiveValue operator [](LiveParam param) =>
      values[param] ?? const LiveValue();
}

/// Se perdió la comunicación con el adaptador o con el vehículo durante el
/// monitoreo. La pantalla detiene la consulta e informa al inspector.
class ObdConnectionLostException implements Exception {
  final String message;

  ObdConnectionLostException(this.message);

  @override
  String toString() => message;
}

/// Consulta periódica de parámetros del motor (CU09).
///
/// No depende de Flutter ni de Bluetooth: recibe la función que envía un
/// comando al adaptador, igual que el escaneo, así funciona con el adaptador
/// real y con el simulador. Los valores viven solo en memoria: nada se guarda
/// ni se envía al backend.
class LiveMonitor {
  LiveMonitor({required this.sendCommand, Elm327Service? elm})
      : _elm = elm ?? Elm327Service();

  final Future<String> Function(String command) sendCommand;
  final Elm327Service _elm;

  /// PID del Modo 01 de cada parámetro. El voltaje no es un PID: lo mide el
  /// propio adaptador (`ATRV`), por eso siempre está disponible.
  static const Map<LiveParam, int> _pids = {
    LiveParam.rpm: 0x0C,
    LiveParam.speed: 0x0D,
    LiveParam.coolant: 0x05,
    LiveParam.throttle: 0x11,
  };

  /// Cambian despacio: se leen cada [_slowEvery] ciclos para que las RPM, la
  /// velocidad y el acelerador se actualicen dos o tres veces por segundo.
  static const Set<LiveParam> _slow = {LiveParam.coolant, LiveParam.voltage};
  static const int _slowEvery = 5;

  /// Ciclos seguidos sin ninguna respuesta válida que se toleran antes de
  /// dar la comunicación por perdida.
  static const int _maxFailedCycles = 3;

  final Map<LiveParam, LiveValue> _values = {};
  int _cycle = 0;
  int _failedCycles = 0;

  /// Prepara el adaptador y averigua qué parámetros informa el vehículo.
  ///
  /// Lanza [ObdCommunicationException] si la ECU no responde (contacto
  /// apagado o adaptador mal conectado).
  Future<void> start() async {
    _values.clear();
    _cycle = 0;
    _failedCycles = 0;

    final String raw0100;
    try {
      for (final command in const ['ATZ', 'ATE0', 'ATL0', 'ATH0', 'ATSP0']) {
        await sendCommand(command);
      }
      raw0100 = await sendCommand('0100');
    } on ObdCommunicationException {
      rethrow;
    } catch (_) {
      throw ObdCommunicationException(
        'No se pudo comunicar con el adaptador OBD-II.',
      );
    }

    if (_elm.readStatus(raw0100, '41 00') != ObdReadStatus.ok) {
      throw ObdCommunicationException(
        'El vehículo no respondió al protocolo OBD-II. Verifique que el '
        'contacto esté encendido y que el adaptador esté bien conectado.',
      );
    }

    // La respuesta a 0100 dice qué PID soporta el vehículo: los que no
    // figuran se muestran como no disponibles sin consultarlos.
    final supported = _elm.parseSupportedPids(raw0100);
    for (final entry in _pids.entries) {
      _values[entry.key] = supported.contains(entry.value)
          ? const LiveValue()
          : LiveValue.unsupported;
    }
    _values[LiveParam.voltage] = const LiveValue();
  }

  /// Lee una vez los parámetros y devuelve la foto actualizada.
  ///
  /// Lanza [ObdConnectionLostException] si el adaptador deja de responder.
  Future<LiveSnapshot> poll() async {
    final slowTurn = _cycle % _slowEvery == 0;
    _cycle++;
    var answered = false;

    for (final param in LiveParam.values) {
      if (!(_values[param]?.supported ?? false)) continue;
      if (_slow.contains(param) && !slowTurn) continue;

      final String raw;
      try {
        raw = await sendCommand(_commandFor(param));
      } catch (_) {
        throw ObdConnectionLostException(
          'Se perdió la conexión con el adaptador OBD-II.',
        );
      }

      if (param == LiveParam.voltage) {
        // El voltaje lo mide el adaptador: que responda no prueba que la ECU
        // siga viva, así que no cuenta para detectar la pérdida de conexión.
        final volts = _elm.parseVoltage(raw);
        if (volts != null) _values[param] = LiveValue(value: volts);
        continue;
      }

      final pid = _pids[param]!;
      final data = _elm.parsePidData(raw, pid);
      if (data != null) {
        final value = _decode(param, data);
        if (value != null) {
          _values[param] = LiveValue(value: value);
          answered = true;
        }
      }
      // Sin respuesta se conserva el último valor: un dato perdido en un
      // ciclo no debe hacer parpadear la pantalla.
    }

    if (answered || !_pollsEcu(slowTurn)) {
      _failedCycles = 0;
    } else if (++_failedCycles >= _maxFailedCycles) {
      throw ObdConnectionLostException(
        'El vehículo dejó de responder. Verifique que el contacto siga '
        'encendido y que el adaptador no se haya soltado.',
      );
    }

    return LiveSnapshot(Map.unmodifiable(_values));
  }

  /// ¿En este ciclo se le preguntó algo a la ECU? Si el vehículo no soporta
  /// ningún PID rápido, un ciclo sin respuestas no es una falla.
  bool _pollsEcu(bool slowTurn) => _pids.keys.any(
        (param) =>
            (_values[param]?.supported ?? false) &&
            (slowTurn || !_slow.contains(param)),
      );

  String _commandFor(LiveParam param) {
    if (param == LiveParam.voltage) return 'ATRV';
    return '01${_pids[param]!.toRadixString(16).toUpperCase().padLeft(2, '0')}';
  }

  /// Fórmulas de SAE J1979 para cada PID.
  double? _decode(LiveParam param, List<int> data) {
    if (data.isEmpty) return null;
    switch (param) {
      case LiveParam.rpm:
        if (data.length < 2) return null;
        return (data[0] * 256 + data[1]) / 4;
      case LiveParam.speed:
        return data[0].toDouble();
      case LiveParam.coolant:
        return data[0] - 40;
      case LiveParam.throttle:
        return data[0] * 100 / 255;
      case LiveParam.voltage:
        return null;
    }
  }
}
