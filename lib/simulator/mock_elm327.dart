class MockElm327 {
  String scenario;

  MockElm327({this.scenario = 'tacoma_critical'});

  static const Map<String, String> scenarioLabels = {
    'tacoma_critical': 'Caso 1: Toyota Tacoma (P0300+P0301 Confirmados/Permanentes)',
    'bus_battery_reset': 'Caso 2: Bus 3110-BUS (P2195 Pendiente + Monitores Incompletos)',
    'hilux_clean': 'Caso 3: Hilux 4012-UAG (Sin Fallas + Monitores Completos)',
  };

  Map<String, String> get _activeResponses {
    switch (scenario) {
      case 'bus_battery_reset':
        return {
          'ATZ': 'ELM327 v2.1\r\r>',
          'ATE0': 'OK\r\r>',
          'ATL0': 'OK\r\r>',
          'ATSP0': 'OK\r\r>',
          'ATRV': '12.6V\r\r>',
          // 49 02 01 + ASCII "JTGFB518701122334"
          '0902':
              '49 02 01 4A 54 47 46 42 35 31 38 37 30 31 31 32 32 33 33 34\r\r>',
          // MIL OFF (00), monitores incompletos (DD != 00 -> bits activos = incompletos)
          '0101': '41 01 00 07 65 25\r\r>',
          '03': '43 00\r\r>',
          '07': '47 01 21 95\r\r>', // P2195 pending
          '0A': '4A 00\r\r>',
          '010C': '41 0C 0C 80\r\r>',
          '010D': '41 0D 00\r\r>',
          '0105': '41 05 78\r\r>',
        };
      case 'hilux_clean':
        return {
          'ATZ': 'ELM327 v2.1\r\r>',
          'ATE0': 'OK\r\r>',
          'ATL0': 'OK\r\r>',
          'ATSP0': 'OK\r\r>',
          'ATRV': '13.9V\r\r>',
          // 49 02 01 + ASCII "8AJBA3CD201928374"
          '0902':
              '49 02 01 38 41 4A 42 41 33 43 44 32 30 31 39 32 38 33 37 34\r\r>',
          // MIL OFF (00), todos los monitores completados (DD = 00)
          '0101': '41 01 00 07 65 00\r\r>',
          '03': '43 00\r\r>',
          '07': '47 00\r\r>',
          '0A': '4A 00\r\r>',
          '010C': '41 0C 0D 20\r\r>',
          '010D': '41 0D 28\r\r>',
          '0105': '41 05 82\r\r>',
        };
      case 'tacoma_critical':
      default:
        return {
          'ATZ': 'ELM327 v2.1\r\r>',
          'ATE0': 'OK\r\r>',
          'ATL0': 'OK\r\r>',
          'ATSP0': 'OK\r\r>',
          'ATRV': '13.3V\r\r>',
          // 49 02 01 + ASCII "5TFCZ5AN3MX255216"
          '0902':
              '49 02 01 35 54 46 43 5A 35 41 4E 33 4D 58 32 35 35 32 31 36\r\r>',
          // MIL ON (82 = bit 7 ON + 2 DTCs), monitores completados (DD = 00)
          '0101': '41 01 82 07 65 00\r\r>',
          '03': '43 02 03 00 03 01\r\r>', // P0300 + P0301 confirmed
          '07': '47 00\r\r>',
          '0A': '4A 02 03 00 03 01\r\r>', // P0300 + P0301 permanent
          '010C': '41 0C 1A F8\r\r>',
          '010D': '41 0D 00\r\r>',
          '0105': '41 05 7B\r\r>',
        };
    }
  }

  Future<String> sendCommand(String command) async {
    await Future.delayed(const Duration(milliseconds: 180));
    final clean = command.trim().toUpperCase().replaceAll(' ', '');
    return _activeResponses[clean] ?? 'NO DATA\r\r>';
  }
}
