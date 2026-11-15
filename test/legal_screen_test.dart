import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taller_mobile/features/legal/legal_texts.dart';
import 'package:taller_mobile/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> abrirLogin(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const TallerMobileApp());
    // Sin pumpAndSettle: el indicador de carga anima indefinidamente.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('desde el login se abre la política de privacidad', (tester) async {
    await abrirLogin(tester);

    final enlace = find.widgetWithText(TextButton, 'Política de privacidad');
    await tester.ensureVisible(enlace);
    await tester.tap(enlace);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Política de privacidad'), findsOneWidget);
    expect(find.text('Responsable'), findsOneWidget);
  });

  testWidgets('desde el login se abren los términos de uso', (tester) async {
    await abrirLogin(tester);

    final enlace = find.widgetWithText(TextButton, 'Términos de uso');
    await tester.ensureVisible(enlace);
    await tester.tap(enlace);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Términos de uso'), findsOneWidget);
    expect(find.text('Quién puede usarlo'), findsOneWidget);
  });

  test('los dos documentos tienen fecha y secciones con contenido', () {
    for (final documento in [privacyPolicy, termsOfUse]) {
      expect(documento.updated, legalUpdated);
      expect(documento.sections, isNotEmpty);
      for (final seccion in documento.sections) {
        expect(
          seccion.paragraphs.isNotEmpty || seccion.bullets.isNotEmpty,
          isTrue,
          reason: '${documento.title} › ${seccion.title} está vacía',
        );
      }
    }
  });
}
