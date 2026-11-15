import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taller_mobile/core/elm327/elm327_service.dart';
import 'package:taller_mobile/core/elm327/live_monitor.dart';
import 'package:taller_mobile/features/monitor/live_monitor_screen.dart';
import 'package:taller_mobile/simulator/mock_elm327.dart';

/// Adaptador de prueba con respuestas fijas por comando.
Future<String> Function(String) adaptador(Map<String, String> respuestas) {
  return (command) async {
    if (command.startsWith('AT') && !respuestas.containsKey(command)) {
      return 'OK\r\r>';
    }
    return respuestas[command] ?? 'NO DATA\r\r>';
  };
}

MockElm327 simulador(String scenario) =>
    MockElm327(scenario: scenario, delay: Duration.zero)..live = true;

void main() {
  group('Lectura de PID del Modo 01', () {
    final elm = Elm327Service();

    test('devuelve los bytes de datos sin la cabecera', () {
      expect(elm.parsePidData('41 0C 1A F8\r\r>', 0x0C), [0x1A, 0xF8]);
      expect(elm.parsePidData('410C1AF8\r\r>', 0x0C), [0x1A, 0xF8]);
    });

    test('no confunde la respuesta de otro PID ni un error', () {
      expect(elm.parsePidData('41 0D 28\r\r>', 0x0C), isNull);
      expect(elm.parsePidData('NO DATA\r\r>', 0x0C), isNull);
      expect(elm.parsePidData('TIMEOUT\r\r>', 0x0C), isNull);
    });

    test('lee de 0100 qué PID soporta el vehículo', () {
      final soportados = elm.parseSupportedPids('41 00 BE 3F A8 13\r\r>');

      expect(soportados, containsAll([0x05, 0x0C, 0x0D, 0x11]));
      expect(soportados.contains(0x02), isFalse);
    });

    test('suma los PID de todas las ECU que responden', () {
      final soportados = elm.parseSupportedPids(
        '41 00 80 00 00 00\r41 00 00 10 00 00\r\r>',
      );

      expect(soportados, {0x01, 0x0C});
    });
  });

  group('LiveMonitor', () {
    test('decodifica RPM, velocidad, temperatura, acelerador y voltaje',
        () async {
      final monitor = LiveMonitor(
        sendCommand: adaptador({
          '0100': '41 00 BE 3F A8 13\r\r>',
          '010C': '41 0C 1A F8\r\r>', // (0x1AF8) / 4 = 1726
          '010D': '41 0D 28\r\r>', // 40 km/h
          '0105': '41 05 7B\r\r>', // 123 - 40 = 83 °C
          '0111': '41 11 80\r\r>', // 128 * 100 / 255 = 50,2 %
          'ATRV': '13.3V\r\r>',
        }),
      );

      await monitor.start();
      final foto = await monitor.poll();

      expect(foto[LiveParam.rpm].value, 1726);
      expect(foto[LiveParam.speed].value, 40);
      expect(foto[LiveParam.coolant].value, 83);
      expect(foto[LiveParam.throttle].value, closeTo(50.2, 0.05));
      expect(foto[LiveParam.voltage].value, 13.3);
    });

    test('un parámetro que el vehículo no soporta queda como no disponible',
        () async {
      final consultados = <String>[];
      final mock = simulador('legacy_iso9141');
      final monitor = LiveMonitor(
        sendCommand: (c) {
          consultados.add(c);
          return mock.sendCommand(c);
        },
      );

      await monitor.start();
      final foto = await monitor.poll();

      expect(foto[LiveParam.throttle].supported, isFalse);
      expect(foto[LiveParam.rpm].supported, isTrue);
      expect(foto[LiveParam.rpm].value, isNotNull);
      // No se le sigue preguntando lo que ya dijo que no informa.
      expect(consultados.contains('0111'), isFalse);
    });

    test('con el contacto apagado no arranca y explica por qué', () async {
      final monitor = LiveMonitor(
        sendCommand: simulador('ignition_off').sendCommand,
      );

      expect(
        monitor.start(),
        throwsA(
          isA<ObdCommunicationException>().having(
            (e) => e.message,
            'mensaje',
            contains('contacto'),
          ),
        ),
      );
    });

    test('si el adaptador se desconecta, avisa que se perdió la conexión',
        () async {
      final monitor = LiveMonitor(
        sendCommand: simulador('conexion_perdida').sendCommand,
      );
      await monitor.start();

      Object? error;
      var ciclos = 0;
      try {
        while (ciclos < 200) {
          await monitor.poll();
          ciclos++;
        }
      } catch (e) {
        error = e;
      }

      expect(error, isA<ObdConnectionLostException>());
      expect(ciclos, greaterThan(5)); // primero leyó con normalidad
    });

    test('si la ECU deja de responder varios ciclos, da la conexión por perdida',
        () async {
      var vivo = true;
      final monitor = LiveMonitor(
        sendCommand: (c) async {
          if (c == '0100') return '41 00 BE 3F A8 13\r\r>';
          if (c.startsWith('AT')) return c == 'ATRV' ? '12.1V\r\r>' : 'OK\r\r>';
          return vivo ? '41 ${c.substring(2)} 10 00\r\r>' : 'NO DATA\r\r>';
        },
      );
      await monitor.start();
      await monitor.poll();

      vivo = false;
      // Un par de ciclos malos se toleran y se conserva el último valor.
      final foto = await monitor.poll();
      expect(foto[LiveParam.rpm].value, isNotNull);
      await monitor.poll();

      expect(monitor.poll(), throwsA(isA<ObdConnectionLostException>()));
    });

    test('una lectura suelta que falla no borra el valor ni corta el monitoreo',
        () async {
      var fallarRpm = false;
      final monitor = LiveMonitor(
        sendCommand: (c) async {
          if (c == '0100') return '41 00 BE 3F A8 13\r\r>';
          if (c.startsWith('AT')) return 'OK\r\r>';
          if (c == '010C' && fallarRpm) return 'TIMEOUT\r\r>';
          return '41 ${c.substring(2)} 10 00\r\r>';
        },
      );
      await monitor.start();
      final antes = await monitor.poll();

      fallarRpm = true;
      late LiveSnapshot despues;
      for (var i = 0; i < 10; i++) {
        despues = await monitor.poll();
      }

      expect(despues[LiveParam.rpm].value, antes[LiveParam.rpm].value);
    });

    test('el simulador en vivo cambia las RPM con el tiempo', () async {
      final monitor = LiveMonitor(
        sendCommand: simulador('tacoma_critical').sendCommand,
      );
      await monitor.start();

      final rpm = <double>{};
      for (var i = 0; i < 30; i++) {
        rpm.add((await monitor.poll())[LiveParam.rpm].value!);
      }

      expect(rpm.length, greaterThan(10));
      expect(rpm.every((v) => v > 500 && v < 7000), isTrue);
    });

    test('fuera del monitor, el simulador responde siempre lo mismo', () async {
      // El escaneo depende de lecturas repetibles.
      final mock = MockElm327(scenario: 'tacoma_critical', delay: Duration.zero);

      expect(await mock.sendCommand('010C'), await mock.sendCommand('010C'));
      expect(await mock.sendCommand('ATRV'), '13.3V\r\r>');
    });
  });

  group('Pantalla del monitor en vivo', () {
    // En las pruebas de pantalla el reloj es simulado: con demora cero el
    // ciclo de lectura nunca cedería el turno, así que el simulador tarda
    // 10 ms por comando y el reloj se avanza de a 10 ms.
    const demora = Duration(milliseconds: 10);

    Future<void> avanzar(WidgetTester tester, [int veces = 40]) async {
      for (var i = 0; i < veces; i++) {
        await tester.pump(demora);
      }
    }

    // Al cerrar la pantalla el ciclo termina solo; se le da tiempo para que
    // no queden temporizadores pendientes al final de la prueba.
    Future<void> cerrar(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await avanzar(tester, 20);
    }

    testWidgets('muestra los valores y se puede detener', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LiveMonitorScreen.simulator(
            simulator: MockElm327(delay: demora),
          ),
        ),
      );
      await avanzar(tester);

      expect(find.textContaining('Leyendo en vivo'), findsOneWidget);
      expect(find.text('rpm'), findsOneWidget);
      expect(find.text('—'), findsNothing);
      expect(find.text('No disponible'), findsNothing);

      await tester.tap(find.text('Detener'));
      await avanzar(tester);

      expect(find.textContaining('Monitoreo detenido'), findsOneWidget);
      expect(find.text('Reanudar'), findsOneWidget);
      await cerrar(tester);
    });

    testWidgets('informa cuando se pierde la conexión', (tester) async {
      final mock = MockElm327(delay: demora);
      await tester.pumpWidget(
        MaterialApp(home: LiveMonitorScreen.simulator(simulator: mock)),
      );
      await avanzar(tester, 5);

      // Se elige el escenario que corta la comunicación.
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      // Sin pumpAndSettle: el monitor redibuja sin parar y nunca "se asienta".
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.textContaining('Se pierde la conexión').last);
      await tester.pump(const Duration(milliseconds: 400));
      await avanzar(tester, 400);

      expect(find.textContaining('Se perdió la conexión'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      await cerrar(tester);
    });
  });
}
