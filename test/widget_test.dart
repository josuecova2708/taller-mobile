import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taller_mobile/main.dart';
import 'package:taller_mobile/core/elm327/elm327_service.dart';
import 'package:taller_mobile/simulator/mock_elm327.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Puerta de autenticación', () {
    testWidgets('sin sesión guardada, la app exige iniciar sesión', (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(const TallerMobileApp());
      // No se usa pumpAndSettle: el spinner de carga anima indefinidamente.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Iniciar Sesión'), findsOneWidget);
      expect(find.text('Correo institucional'), findsOneWidget);

      // Regresión: antes la app entraba directo al escaneo sin autenticar.
      expect(find.text('Escanear Vehículo'), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('con sesión guardada, la app entra a la navegación principal',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'jwt_token': 'token-de-prueba',
        'auth_user':
            '{"id":"u1","email":"inspector@uagrm.edu.bo","name":"Inspector Demo",'
                '"role":"INSPECTOR","roleLabel":"Inspector",'
                '"permissions":["vehicle:read","scan:read","scan:create"]}',
      });

      await tester.pumpWidget(const TallerMobileApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // La revalidación contra el backend falla en el test (no hay servidor),
      // pero la sesión local se conserva: la app no debe expulsar al usuario
      // por falta de conectividad.
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Iniciar Sesión'), findsNothing);
    });
  });

  test('Elm327Service decodes Tacoma VIN, Readiness (0101), Voltage, and DTCs (03/07/0A)',
      () async {
    final elm = Elm327Service();
    final mock = MockElm327(scenario: 'tacoma_critical');

    final result = await elm.runFullScan(sendCommand: mock.sendCommand);

    expect(result.vin, '5TFCZ5AN3MX255216');
    expect(result.batteryVoltage, 13.3);
    expect(result.readiness.milOn, true);
    expect(result.readiness.monitorsCompleted, true);
    expect(result.dtcs.length, 4);
    expect(result.dtcs.first.code, 'P0300');
    expect(result.dtcs.first.type, 'CONFIRMED');
  });

  test('Elm327Service decodes Bus post-battery incomplete monitors and P2195 pending',
      () async {
    final elm = Elm327Service();
    final mock = MockElm327(scenario: 'bus_battery_reset');

    final result = await elm.runFullScan(sendCommand: mock.sendCommand);

    expect(result.vin, 'JTGFB518701122334');
    expect(result.readiness.monitorsCompleted, false);
    expect(result.readiness.batteryResetSuspected, true);
    expect(result.dtcs.length, 1);
    expect(result.dtcs.first.code, 'P2195');
    expect(result.dtcs.first.type, 'PENDING');
  });
}
