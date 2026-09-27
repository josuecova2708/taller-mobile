import 'package:flutter_test/flutter_test.dart';
import 'package:taller_mobile/main.dart';
import 'package:taller_mobile/core/elm327/elm327_service.dart';
import 'package:taller_mobile/simulator/mock_elm327.dart';

void main() {
  testWidgets('TallerMobileApp renders scan screen by default', (WidgetTester tester) async {
    await tester.pumpWidget(const TallerMobileApp());

    expect(find.text('Escanear Vehículo'), findsOneWidget);
    expect(find.text('Iniciar Escaneo'), findsOneWidget);
  });

  test('Elm327Service decodes Tacoma VIN, Readiness (0101), Voltage, and DTCs (03/07/0A)', () async {
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

  test('Elm327Service decodes Bus post-battery incomplete monitors and P2195 pending', () async {
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
