/// Mock ELM327 responses for development without hardware.
/// Toggle via Settings or environment flag.
library;

class MockElm327 {
  static const Map<String, String> _responses = {
    'ATZ': 'ELM327 v2.1\r\r>',
    'ATE0': 'OK\r\r>',
    'ATL0': 'OK\r\r>',
    'ATH0': 'OK\r\r>',
    'ATSP0': 'OK\r\r>',
    'ATRV': '13.3V\r\r>',
    '0100': '41 00 BE 3E B8 13\r\r>',
    '0902': '49 02 01 35 54 46 43 5A 35 41 4E 33 4D 58 32 35 35 32 31 36\r\r>',
    '03': '43 02 03 00 03 01\r\r>',
    '07': '47 01 21 95\r\r>',
    '0A': '4A 02 03 00 03 01\r\r>',
  };

  /// Simulate sending a command and receiving a response.
  static String sendCommand(String command) {
    final cmd = command.trim().toUpperCase();
    return _responses[cmd] ?? 'NO DATA\r\r>';
  }

  /// Simulate a complete scan returning a scan payload map.
  static Map<String, dynamic> simulateFullScan() {
    return {
      'vin': '5TFCZ5AN3MX255216',
      'scannedAt': DateTime.now().toUtc().toIso8601String(),
      'batteryVoltage': 13.3,
      'dtcs': [
        {'code': 'P0300', 'type': 'PERMANENT', 'monitorStatus': 'COMPLETED'},
        {'code': 'P0301', 'type': 'PERMANENT', 'monitorStatus': 'COMPLETED'},
        {'code': 'P2195', 'type': 'PENDING', 'monitorStatus': 'NOT_COMPLETED'},
      ],
    };
  }
}
