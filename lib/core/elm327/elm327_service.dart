/// ELM327 protocol handler.
/// Manages init sequence, command queue, response parsing.
/// Full implementation in Phase 2.
library;

class Elm327Service {
  /// Initialize the ELM327 adapter (ATZ, ATE0, ATSP0, etc.)
  Future<bool> initialize() async {
    // TODO: Implement in Phase 2
    throw UnimplementedError('ELM327 init not yet implemented');
  }

  /// Read the vehicle VIN (mode 09, PID 02)
  Future<String?> readVin() async {
    // TODO: Implement in Phase 2
    throw UnimplementedError('VIN reading not yet implemented');
  }

  /// Read battery voltage (ATRV)
  Future<double?> readBatteryVoltage() async {
    // TODO: Implement in Phase 2
    throw UnimplementedError('Voltage reading not yet implemented');
  }

  /// Read DTCs - confirmed (mode 03), pending (mode 07), permanent (mode 0A)
  Future<List<DtcCode>> readDtcs() async {
    // TODO: Implement in Phase 2
    throw UnimplementedError('DTC reading not yet implemented');
  }
}

class DtcCode {
  final String code;
  final String type; // CONFIRMED, PENDING, PERMANENT
  final String monitorStatus; // COMPLETED, NOT_COMPLETED, UNKNOWN

  DtcCode({
    required this.code,
    required this.type,
    this.monitorStatus = 'UNKNOWN',
  });

  Map<String, dynamic> toJson() => {
    'code': code,
    'type': type,
    'monitorStatus': monitorStatus,
  };
}
