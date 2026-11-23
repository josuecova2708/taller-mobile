import 'dart:math' as math;

class MockElm327 {
  String scenario;

  /// Demora de cada respuesta, parecida a la de un adaptador real.
  final Duration delay;

  /// Con `true`, los parámetros del motor cambian en el tiempo en vez de
  /// responder siempre lo mismo. Lo activa el monitor en vivo (CU09); el
  /// escaneo lo deja apagado para que sus lecturas sean repetibles.
  bool live = false;

  /// Lecturas de RPM desde el último reinicio del adaptador: es el reloj de
  /// la simulación en vivo.
  int _liveReads = 0;

  MockElm327({
    this.scenario = 'tacoma_critical',
    this.delay = const Duration(milliseconds: 180),
  });

  /// Escenarios que ofrece el monitor en vivo.
  static const Map<String, String> monitorScenarioLabels = {
    'tacoma_critical': 'Camioneta a gasolina en ralentí',
    'bus_diesel': 'Bus diésel (sistema de 24 V)',
    'legacy_iso9141': 'Vehículo pre-2008 (no informa el acelerador)',
    'conexion_perdida': 'Se pierde la conexión a los 10 segundos',
    'ignition_off': 'Contacto apagado (la ECU no responde)',
  };

  /// Lecturas de RPM tras las que el escenario `conexion_perdida` corta la
  /// comunicación (unos 10 segundos a dos lecturas por segundo).
  static const int _readsBeforeDrop = 20;

  static const Map<String, String> scenarioLabels = {
    'tacoma_critical': 'Caso 1: Camioneta ficticia TESTTAC (P0300+P0301 Confirmados/Permanentes)',
    'bus_battery_reset': 'Caso 2: Bus 3110-BUS (P2195 Pendiente + Monitores Incompletos)',
    'hilux_clean': 'Caso 3: Hilux 4012-UAG (Sin Fallas + Monitores Completos)',
    'legacy_iso9141': 'Caso 4: Vehículo pre-2008 (ISO 9141-2, sin byte de conteo)',
    'bus_diesel': 'Caso 5: Bus diésel (encendido por compresión, monitores diésel)',
    'multi_ecu': 'Caso 6: Dos módulos responden (motor y caja) + respuesta multitrama',
    'ignition_off': 'Caso 7: Contacto apagado (la ECU no responde)',
    'lectura_fallida': 'Caso 8: Falla de bus al leer los códigos (escaneo incompleto)',
  };

  Map<String, String> get _activeResponses {
    switch (scenario) {
      // Dos ECU responden a cada consulta. El Modo 03 del motor trae cuatro
      // códigos, así que llega en multitrama (longitud + segmentos numerados);
      // la caja responde en una trama simple. Antes la cabecera de la segunda
      // ECU se leía como un código de falla.
      case 'multi_ecu':
        return {
          'ATDPN': 'A6\r\r>',
          'ATRV': '13.7V\r\r>',
          '0902':
              '014\r0: 49 02 01 54 45 53\r1: 54 54 41 43 30 30 30\r2: 30 30 30 30 30 30 31\r\r>',
          '0101': '41 01 84 07 65 00\r41 01 00 04 00 00\r\r>',
          // Motor: P0300, P0301, P0171, P0420. Caja: P0700.
          '03':
              '00A\r0: 43 04 03 00 03 01\r1: 01 71 04 20 AA AA AA\r43 01 07 00 AA AA AA\r\r>',
          '07': '47 00\r47 00\r\r>',
          '0A': '4A 00\r4A 00\r\r>',
        };

      // Contacto apagado: el adaptador tiene alimentación (ATRV responde) pero
      // ninguna ECU contesta.
      case 'ignition_off':
        return {
          'ATDPN': 'A0\r\r>',
          'ATRV': '12.1V\r\r>',
          '0100': 'SEARCHING...\rUNABLE TO CONNECT\r\r>',
        };

      // La ECU responde al inicio pero el bus falla al leer los códigos. Sin
      // el control de lectura esto se registraba como "vehículo sin fallas".
      case 'lectura_fallida':
        return {
          'ATDPN': 'A6\r\r>',
          'ATRV': '13.2V\r\r>',
          '0902':
              '49 02 01 38 41 4A 42 41 33 43 44 32 30 31 39 32 38 33 37 34\r\r>',
          '0101': '41 01 00 07 65 00\r\r>',
          '03': 'CAN ERROR\r\r>',
          '07': 'TIMEOUT\r\r>',
          '0A': 'NO DATA\r\r>',
        };

      case 'bus_battery_reset':
        return {
          'ATZ': 'ELM327 v2.1\r\r>',
          'ATE0': 'OK\r\r>',
          'ATL0': 'OK\r\r>',
          'ATSP0': 'OK\r\r>',
          'ATDPN': 'A6\r\r>',
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
          'ATDPN': 'A6\r\r>',
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

      // Vehículo anterior a ~2008 sobre ISO 9141-2 (protocolo 3).
      //
      // Diferencia clave: la respuesta del Modo 03 NO trae byte de conteo de
      // códigos. Son tres pares de bytes de DTC, rellenados con 00 00.
      // Si el parser asume el byte de conteo de CAN, se come el primer código
      // y desalinea todos los demás.
      case 'legacy_iso9141':
        return {
          'ATZ': 'ELM327 v1.5\r\r>',
          'ATE0': 'OK\r\r>',
          'ATL0': 'OK\r\r>',
          'ATSP0': 'OK\r\r>',
          'ATDPN': 'A3\r\r>',
          'ATRV': '13.1V\r\r>',
          // PID soportados: igual que el resto, pero sin el 11 (posición del
          // acelerador), que muchos vehículos de esa época no informan.
          '0100': '41 00 BE 3F 28 13\r\r>',
          '0111': 'NO DATA\r\r>',
          // 49 02 01 + ASCII "JT1AB2CD304050607"
          '0902':
              '49 02 01 4A 54 31 41 42 32 43 44 33 30 34 30 35 30 36 30 37\r\r>',
          '0101': '41 01 81 07 65 00\r\r>',
          // Sin byte de conteo: 43 + P0300 + P0301 + relleno
          '03': '43 03 00 03 01 00 00\r\r>',
          '07': '47 00 00 00 00 00 00\r\r>',
          '0A': 'NO DATA\r\r>', // Modo 0A no existe antes de 2010
          '010C': '41 0C 0A 00\r\r>',
          '010D': '41 0D 00\r\r>',
          '0105': '41 05 70\r\r>',
        };

      // Bus diésel: encendido por compresión.
      //
      // Byte B con el bit 3 activo (0x08) indica compresión. Eso cambia el
      // significado del byte D: ya no son catalizador/EVAP/sensor O2 sino
      // catalizador NMHC, SCR/NOx, presión de sobrealimentación, sensor de
      // gases de escape y filtro de partículas.
      //
      // Aquí DD = 0x21 -> bit 0 y bit 5 incompletos, que en diésel son
      // "Catalizador NMHC" y "Sensor de gases de escape", NO "Catalizador" y
      // "Sensor de Oxígeno".
      case 'bus_diesel':
        return {
          'ATZ': 'ELM327 v2.1\r\r>',
          'ATE0': 'OK\r\r>',
          'ATL0': 'OK\r\r>',
          'ATSP0': 'OK\r\r>',
          'ATDPN': 'A6\r\r>',
          'ATRV': '24.3V\r\r>', // sistema de 24 V, típico en buses
          // 49 02 01 + ASCII "LZZ5BLSD6PA123456"
          '0902':
              '49 02 01 4C 5A 5A 35 42 4C 53 44 36 50 41 31 32 33 34 35 36\r\r>',
          // AA=82 (MIL ON, 2 DTC), BB=0F (bit3 -> compresión), CC=65, DD=21
          '0101': '41 01 82 0F 65 21\r\r>',
          '03': '43 02 04 01 24 2F\r\r>', // P0401 (EGR) + P242F (filtro DPF)
          '07': '47 00\r\r>',
          '0A': '4A 01 24 2F\r\r>',
          '010C': '41 0C 07 D0\r\r>',
          '010D': '41 0D 00\r\r>',
          '0105': '41 05 6E\r\r>',
        };

      case 'tacoma_critical':
      default:
        return {
          'ATZ': 'ELM327 v2.1\r\r>',
          'ATE0': 'OK\r\r>',
          'ATL0': 'OK\r\r>',
          'ATSP0': 'OK\r\r>',
          'ATDPN': 'A6\r\r>',
          'ATRV': '13.3V\r\r>',
          // 49 02 01 + ASCII "TESTTAC0000000001" (VIN ficticio: no debe cruzarse con un vehículo real)
          '0902':
              '49 02 01 54 45 53 54 54 41 43 30 30 30 30 30 30 30 30 30 31\r\r>',
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

  /// Byte en hexadecimal de dos dígitos, limitado a 0-255.
  String _hex(num valor) =>
      valor.round().clamp(0, 255).toRadixString(16).toUpperCase().padLeft(2, '0');

  /// Primer byte de datos de la respuesta fija del escenario a un PID.
  int? _baseByte(String pid, {int index = 0}) {
    final fija = _activeResponses[pid];
    if (fija == null) return null;
    final bytes = fija.replaceAll('>', '').trim().split(RegExp(r'\s+'));
    if (bytes.length < 3 + index) return null;
    return int.tryParse(bytes[2 + index], radix: 16);
  }

  /// Respuesta que cambia en el tiempo, para el monitor en vivo.
  ///
  /// Simula un vehículo detenido en ralentí al que cada tanto se le pisa el
  /// acelerador: las RPM y la posición del acelerador suben juntas, la
  /// temperatura sube de a poco y el voltaje oscila levemente. Parte de los
  /// valores fijos del escenario y no usa azar, para poder probarla.
  String? _liveResponse(String clean) {
    final respuestas = _activeResponses;
    final t = _liveReads.toDouble();
    // Pisada del acelerador: casi siempre 0, con un pico periódico.
    final pedal = math.pow(math.max(0, math.sin(t * 0.12)), 3).toDouble();

    switch (clean) {
      case '010C':
        if (respuestas['010C'] == null && scenario != 'conexion_perdida') {
          return null;
        }
        _liveReads++;
        final a = _baseByte('010C') ?? 0x0B;
        final b = _baseByte('010C', index: 1) ?? 0xB8;
        final ralenti = (a * 256 + b) / 4;
        final rpm = ralenti + pedal * 1800 + 25 * math.sin(t * 0.9);
        final crudo = (rpm * 4).round().clamp(0, 65535);
        return '41 0C ${_hex(crudo ~/ 256)} ${_hex(crudo % 256)}\r\r>';
      case '010D':
        final velocidad = _baseByte('010D');
        return velocidad == null ? null : '41 0D ${_hex(velocidad)}\r\r>';
      case '0105':
        final temperatura = _baseByte('0105');
        if (temperatura == null) return null;
        return '41 05 ${_hex(temperatura + math.min(t / 20, 6))}\r\r>';
      case '0111':
        if (respuestas['0111'] != null) return null; // el escenario lo niega
        return '41 11 ${_hex((14 + pedal * 40) * 255 / 100)}\r\r>';
      case 'ATRV':
        final fija = respuestas['ATRV'];
        final voltaje = fija == null
            ? null
            : double.tryParse(fija.replaceAll(RegExp(r'[^0-9.]'), ''));
        if (voltaje == null) return null;
        final actual = voltaje + 0.1 * math.sin(t * 0.3);
        return '${actual.toStringAsFixed(1)}V\r\r>';
    }
    return null;
  }

  Future<String> sendCommand(String command) async {
    await Future.delayed(delay);
    final clean = command.trim().toUpperCase().replaceAll(' ', '');

    // Reiniciar el adaptador reinicia también la simulación en vivo.
    if (clean == 'ATZ') _liveReads = 0;

    if (live) {
      if (scenario == 'conexion_perdida' && _liveReads >= _readsBeforeDrop) {
        // Igual que el servicio de Bluetooth cuando se corta el enlace.
        throw StateError('No hay conexión Bluetooth activa con el ELM327');
      }
      final enVivo = _liveResponse(clean);
      if (enVivo != null) return enVivo;
    }

    final respuesta = _activeResponses[clean];
    if (respuesta != null) return respuesta;

    // Comandos de configuración del adaptador: siempre responden OK.
    if (clean == 'ATZ') return 'ELM327 v2.1\r\r>';
    if (clean.startsWith('AT')) return 'OK\r\r>';
    // PIDs soportados: confirma que la ECU está viva.
    if (clean == '0100') return '41 00 BE 3F A8 13\r\r>';
    return 'NO DATA\r\r>';
  }
}
