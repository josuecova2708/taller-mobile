import 'package:flutter_test/flutter_test.dart';
import 'package:taller_mobile/main.dart';

void main() {
  testWidgets('TallerMobileApp renders scan screen by default', (WidgetTester tester) async {
    await tester.pumpWidget(const TallerMobileApp());

    expect(find.text('Escanear Vehículo'), findsOneWidget);
    expect(find.text('Iniciar Escaneo'), findsOneWidget);
  });
}
