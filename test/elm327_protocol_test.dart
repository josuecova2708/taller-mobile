import 'package:flutter_test/flutter_test.dart';
import 'package:taller_mobile/core/elm327/elm327_service.dart';
import 'package:taller_mobile/simulator/mock_elm327.dart';

void main() {
  final elm = Elm327Service();

  group('Detección de protocolo (ATDPN)', () {
    test('reconoce CAN con detección automática', () {
      final p = elm.parseProtocol('A6\r\r>');

      expect(p.number, '6');
      expect(p.automatic, true);
      expect(p.isCan, true);
      expect(p.assumeCountByte, true);
      expect(p.label, contains('ISO 15765-4'));
    });

    test('reconoce ISO 9141-2 como NO CAN', () {
      final p = elm.parseProtocol('A3\r\r>');

      expect(p.number, '3');
      expect(p.isCan, false);
      expect(p.assumeCountByte, false);
      expect(p.label, contains('ISO 9141-2'));
    });

    test('reconoce protocolo fijado sin prefijo automático', () {
      final p = elm.parseProtocol('6\r\r>');
      expect(p.number, '6');
      expect(p.automatic, false);
      expect(p.isCan, true);
    });

    test('ante respuesta ilegible asume CAN, el caso más probable', () {
      final p = elm.parseProtocol('SEARCHING...\r\r>');

      expect(p.number, isNull);
      expect(p.isCan, false);
      // Sin dato, se asume el byte de conteo: cualquier vehículo posterior a
      // 2008 es CAN, así que es la suposición que falla menos veces.
      expect(p.assumeCountByte, true);
      expect(p.label, contains('no identificado'));
    });
  });

  group('parseDtcs según protocolo', () {
    // Misma trama, dos protocolos: la interpretación correcta depende de si
    // existe el byte de conteo de códigos.
    const tramaSinConteo = '43 03 00 03 01 00 00\r\r>';

    test('CAN: salta el byte de conteo', () {
      final dtcs = elm.parseDtcs('43 02 03 00 03 01\r\r>', '43', 'CONFIRMED');

      expect(dtcs.map((d) => d.code), ['P0300', 'P0301']);
    });

    test('no-CAN: NO salta byte de conteo (bug corregido)', () {
      final dtcs = elm.parseDtcs(
        tramaSinConteo,
        '43',
        'CONFIRMED',
        hasCountByte: false,
      );

      expect(dtcs.map((d) => d.code), ['P0300', 'P0301']);
    });

    test('regresión: tratar una trama no-CAN como CAN desalinea los códigos', () {
      // Comportamiento ANTERIOR a la corrección, documentado para que quede
      // claro qué se estaba perdiendo: no solo se pierde un código, se
      // inventan códigos que la ECU nunca reportó.
      final malInterpretados = elm.parseDtcs(
        tramaSinConteo,
        '43',
        'CONFIRMED',
        hasCountByte: true,
      );

      expect(malInterpretados.map((d) => d.code), isNot(contains('P0300')));
      expect(malInterpretados.map((d) => d.code), ['P0003', 'P0100']);
    });
  });

  group('Lecturas fallidas no se confunden con vehículo sano', () {
    test('clasifica la respuesta de cada consulta', () {
      expect(elm.readStatus('43 00\r\r>', '43'), ObdReadStatus.ok);
      expect(elm.readStatus('NO DATA\r\r>', '43'), ObdReadStatus.noData);
      expect(elm.readStatus('TIMEOUT\r\r>', '43'), ObdReadStatus.failed);
      expect(elm.readStatus('CAN ERROR\r\r>', '43'), ObdReadStatus.failed);
      expect(
        elm.readStatus('SEARCHING...\rUNABLE TO CONNECT\r\r>', '41 00'),
        ObdReadStatus.failed,
      );
      expect(
        elm.readStatus('SEARCHING...\r41 00 BE 3F A8 13\r\r>', '41 00'),
        ObdReadStatus.ok,
      );
    });

    test('contacto apagado: el escaneo se aborta', () async {
      final mock = MockElm327(scenario: 'ignition_off');

      expect(
        () => elm.runFullScan(sendCommand: mock.sendCommand),
        throwsA(isA<ObdCommunicationException>()),
      );
    });

    test('falla de bus al leer códigos: escaneo incompleto, no "sin fallas"',
        () async {
      final mock = MockElm327(scenario: 'lectura_fallida');
      final result = await elm.runFullScan(sendCommand: mock.sendCommand);

      expect(result.dtcs, isEmpty);
      expect(result.isComplete, false);
      expect(result.readErrors, hasLength(2));
      expect(result.toApiPayload()['complete'], false);
    });

    test('un escaneo limpio de verdad sí está completo', () async {
      final mock = MockElm327(scenario: 'hilux_clean');
      final result = await elm.runFullScan(sendCommand: mock.sendCommand);

      expect(result.dtcs, isEmpty);
      expect(result.isComplete, true);
      expect(result.toApiPayload()['complete'], true);
    });

    test('NO DATA en el Modo 0A (pre-2010) no bloquea el escaneo', () async {
      final mock = MockElm327(scenario: 'legacy_iso9141');
      final result = await elm.runFullScan(sendCommand: mock.sendCommand);

      expect(result.isComplete, true);
      expect(result.warnings, isNotEmpty);
    });
  });

  group('Negociación de protocolo', () {
    test('consulta 0100 antes de ATDPN', () async {
      final mock = MockElm327(scenario: 'hilux_clean');
      final enviados = <String>[];

      await elm.runFullScan(
        sendCommand: (c) {
          enviados.add(c);
          return mock.sendCommand(c);
        },
      );

      expect(enviados.indexOf('0100'), greaterThan(-1));
      expect(enviados.indexOf('0100'), lessThan(enviados.indexOf('ATDPN')));
    });

    test('A0 (protocolo sin determinar) no se toma como un protocolo', () {
      final p = elm.parseProtocol('A0\r\r>');
      expect(p.number, isNull);
      expect(p.assumeCountByte, true);
    });
  });

  group('Varias ECU y respuestas multitrama', () {
    test('la cabecera de la segunda ECU no se lee como código', () {
      final dtcs = elm.parseDtcs('43 01 03 00\r43 00\r\r>', '43', 'CONFIRMED');
      expect(dtcs.map((d) => d.code), ['P0300']);
    });

    test('el relleno después del conteo se ignora', () {
      final dtcs =
          elm.parseDtcs('43 01 03 00 AA AA AA\r\r>', '43', 'CONFIRMED');
      expect(dtcs.map((d) => d.code), ['P0300']);
    });

    test('el mismo código en dos módulos se reporta una vez', () {
      final dtcs = elm.parseDtcs(
        '43 01 03 00\r43 01 03 00\r\r>',
        '43',
        'CONFIRMED',
      );
      expect(dtcs.map((d) => d.code), ['P0300']);
    });

    test('rearma una respuesta multitrama de CAN', () {
      final dtcs = elm.parseDtcs(
        '00A\r0: 43 04 03 00 03 01\r1: 01 71 04 20 AA AA AA\r\r>',
        '43',
        'CONFIRMED',
      );
      expect(dtcs.map((d) => d.code), ['P0300', 'P0301', 'P0171', 'P0420']);
    });

    test('no-CAN: varias líneas, cada una con su cabecera', () {
      final dtcs = elm.parseDtcs(
        '43 03 00 03 01 01 71\r43 04 20 00 00 00 00\r\r>',
        '43',
        'CONFIRMED',
        hasCountByte: false,
      );
      expect(dtcs.map((d) => d.code), ['P0300', 'P0301', 'P0171', 'P0420']);
    });

    test('escenario completo con motor y caja', () async {
      final mock = MockElm327(scenario: 'multi_ecu');
      final result = await elm.runFullScan(sendCommand: mock.sendCommand);

      expect(result.isComplete, true);
      expect(result.vin, '5TFCZ5AN3MX255216');
      expect(
        result.dtcs.map((d) => d.code),
        ['P0300', 'P0301', 'P0171', 'P0420', 'P0700'],
      );
    });
  });

  group('Fecha del escaneo', () {
    test('se envía en UTC con zona explícita', () async {
      final mock = MockElm327(scenario: 'hilux_clean');
      final result = await elm.runFullScan(sendCommand: mock.sendCommand);

      final enviado = result.toApiPayload()['scannedAt'] as String;
      expect(enviado, endsWith('Z'));
      expect(DateTime.parse(enviado).isAtSameMomentAs(result.scannedAt), true);
    });
  });

  group('Escenario pre-2008 completo (ISO 9141-2)', () {
    test('decodifica P0300 y P0301 pese a no haber byte de conteo', () async {
      final mock = MockElm327(scenario: 'legacy_iso9141');
      final result = await elm.runFullScan(sendCommand: mock.sendCommand);

      expect(result.protocol.number, '3');
      expect(result.protocol.isCan, false);
      expect(result.vin, 'JT1AB2CD304050607');

      final confirmados = result.dtcs
          .where((d) => d.type == 'CONFIRMED')
          .map((d) => d.code)
          .toList();
      expect(confirmados, ['P0300', 'P0301']);

      // El Modo 0A no existe en vehículos anteriores a 2010: NO DATA.
      expect(result.dtcs.where((d) => d.type == 'PERMANENT'), isEmpty);
    });
  });

  group('Readiness de motor diésel (encendido por compresión)', () {
    test('detecta compresión por el bit 3 del byte B', () {
      final r = elm.parseReadiness('41 01 82 0F 65 21\r\r>');
      expect(r.compressionIgnition, true);
    });

    test('usa los nombres de monitores diésel, no los de gasolina', () {
      final r = elm.parseReadiness('41 01 82 0F 65 21\r\r>');

      expect(r.incompleteMonitors, contains('Catalizador NMHC'));
      expect(r.incompleteMonitors, contains('Sensor de gases de escape'));

      // Regresión: antes reportaba "Sistema EVAP" en un vehículo que no lo
      // tiene, y "Sensor de Oxígeno" en lugar del sensor de gases de escape.
      expect(r.incompleteMonitors, isNot(contains('Sistema EVAP')));
      expect(r.incompleteMonitors, isNot(contains('Sensor de Oxígeno')));
    });

    test('un motor a gasolina sigue usando los nombres de gasolina', () {
      // Mismo byte D, byte B sin el bit de compresión.
      final r = elm.parseReadiness('41 01 82 07 65 21\r\r>');

      expect(r.compressionIgnition, false);
      expect(r.incompleteMonitors, contains('Catalizador'));
      expect(r.incompleteMonitors, contains('Sensor de Oxígeno'));
      expect(r.incompleteMonitors, isNot(contains('Catalizador NMHC')));
    });

    test('el byte C enmascara monitores no soportados', () {
      // DD marca el bit 2 (EVAP) como no completado, pero CC dice que el
      // vehículo no soporta ese monitor: no debe reportarse.
      final sinSoporte = elm.parseReadiness('41 01 00 07 01 04\r\r>');
      expect(sinSoporte.incompleteMonitors, isEmpty);
      expect(sinSoporte.monitorsCompleted, true);

      final conSoporte = elm.parseReadiness('41 01 00 07 05 04\r\r>');
      expect(conSoporte.incompleteMonitors, contains('Sistema EVAP'));
    });

    test('escenario completo de bus diésel', () async {
      final mock = MockElm327(scenario: 'bus_diesel');
      final result = await elm.runFullScan(sendCommand: mock.sendCommand);

      expect(result.readiness.compressionIgnition, true);
      expect(result.batteryVoltage, 24.3);
      expect(result.readiness.monitorsCompleted, false);
      expect(
        result.readiness.incompleteMonitors,
        isNot(contains('Sistema EVAP')),
      );

      final codigos = result.dtcs.map((d) => d.code).toSet();
      expect(codigos, contains('P0401'));
      expect(codigos, contains('P242F'));
    });
  });
}
