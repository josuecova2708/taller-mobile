import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taller_mobile/core/api/api_client.dart';
import 'package:taller_mobile/core/ui/format.dart';
import 'package:taller_mobile/core/ui/hipotesis.dart';
import 'package:taller_mobile/features/orders/work_orders_screen.dart';
import 'package:taller_mobile/features/vehicles/vehicles_screen.dart';
import 'package:taller_mobile/main.dart';

Map<String, dynamic> orden(
  String id, {
  String status = 'OPEN',
  String priority = 'MEDIUM',
  String? asignadoA,
  String createdAt = '2026-11-10T10:00:00Z',
}) =>
    {
      'id': id,
      'status': status,
      'priority': priority,
      'createdAt': createdAt,
      'assignedTo': asignadoA == null ? null : {'id': asignadoA, 'name': 'X'},
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Lista de órdenes', () {
    test('separa sin asignar, mías y de otros; deja fuera las cerradas', () {
      final grupos = agruparOrdenes([
        orden('a'),
        orden('b', asignadoA: 'yo', status: 'IN_PROGRESS'),
        orden('c', asignadoA: 'otro', status: 'IN_PROGRESS'),
        orden('d', status: 'COMPLETED', asignadoA: 'yo'),
        orden('e', status: 'CANCELLED'),
      ], 'yo');

      expect(grupos.sinAsignar.map((o) => o['id']), ['a']);
      expect(grupos.mias.map((o) => o['id']), ['b']);
      expect(grupos.otras.map((o) => o['id']), ['c']);
    });

    test('lo más urgente primero y, a igual prioridad, lo más antiguo', () {
      final grupos = agruparOrdenes([
        orden('media-nueva', createdAt: '2026-11-12T10:00:00Z'),
        orden('critica', priority: 'CRITICAL'),
        orden('media-vieja', createdAt: '2026-11-01T10:00:00Z'),
      ], 'yo');

      expect(grupos.sinAsignar.map((o) => o['id']), [
        'critica',
        'media-vieja',
        'media-nueva',
      ]);
    });
  });

  test('«Mis vehículos» separa los del responsable sin cambiar el orden', () {
    final (mios, resto) = separarPorResponsable([
      {
        'plate': 'A',
        'responsible': {'id': 'yo'}
      },
      {'plate': 'B', 'responsible': null},
      {
        'plate': 'C',
        'responsible': {'id': 'yo'}
      },
      {
        'plate': 'D',
        'responsible': {'id': 'otro'}
      },
    ], 'yo');

    expect(mios.map((v) => v['plate']), ['A', 'C']);
    expect(resto.map((v) => v['plate']), ['B', 'D']);
  });

  test('la antigüedad se lee en palabras', () {
    final ahora = DateTime.parse('2026-11-17T12:00:00Z');
    expect(hace('2026-11-17T11:55:00Z', ahora: ahora), 'hace 5 min');
    expect(hace('2026-11-17T09:00:00Z', ahora: ahora), 'hace 3 h');
    expect(hace('2026-11-16T11:00:00Z', ahora: ahora), 'hace 1 día');
    expect(hace('2026-11-10T12:00:00Z', ahora: ahora), 'hace 7 días');
  });

  test('el 404 «todavía se está generando» es una espera, no un error', () {
    expect(
      ApiClient.esHipotesisEnCurso(ApiException(
        'La hipótesis del escaneo x todavía se está generando.',
        statusCode: 404,
      )),
      isTrue,
    );
    expect(
      ApiClient.esHipotesisEnCurso(ApiException(
        'El escaneo x no generó hipótesis de IA (severidad LOW: no requiere evaluación).',
        statusCode: 404,
      )),
      isFalse,
    );
    expect(
      ApiClient.esHipotesisEnCurso(ApiException('generando', statusCode: 500)),
      isFalse,
    );
  });

  testWidgets('la hipótesis muestra el aviso, las causas y los pasos numerados',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HipotesisView(
              diagnosis: {
                'summary': 'Falla de encendido en el cilindro 1.',
                'recommendations': {
                  'probableCauses': [
                    {'cause': 'Bobina defectuosa', 'confidence': 'ALTA'},
                    {'cause': 'Bujía gastada', 'confidence': 'MEDIA'},
                  ],
                  'verificationSteps': [
                    'Inspeccionar la bujía',
                    'Medir la bobina'
                  ],
                  'correlations': null,
                },
              },
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Requiere validación de un profesional'),
        findsOneWidget);
    expect(find.text('Falla de encendido en el cilindro 1.'), findsOneWidget);
    expect(find.text('Bobina defectuosa'), findsOneWidget);
    expect(find.text('Confianza alta'), findsOneWidget);
    expect(find.text('Confianza media'), findsOneWidget);
    expect(find.text('1.'), findsOneWidget);
    expect(find.text('2.'), findsOneWidget);
    expect(find.text('Medir la bobina'), findsOneWidget);
  });

  group('Pestaña «Órdenes»', () {
    Future<void> abrirConPermisos(
        WidgetTester tester, List<String> permisos, String rol) async {
      final lista = permisos.map((p) => '"$p"').join(',');
      SharedPreferences.setMockInitialValues({
        'jwt_token': 'token-de-prueba',
        'auth_user': '{"id":"u1","email":"u@uagrm.edu.bo","name":"Usuario",'
            '"role":"$rol","roleLabel":"$rol","permissions":[$lista]}',
      });
      await tester.pumpWidget(const TallerMobileApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    }

    testWidgets('la ve el mecánico (order:read)', (tester) async {
      await abrirConPermisos(
        tester,
        [
          'vehicle:read',
          'scan:read',
          'scan:create',
          'diagnosis:read',
          'order:read'
        ],
        'MECHANIC',
      );
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Órdenes'), findsOneWidget);
    });

    testWidgets('el inspector no la ve', (tester) async {
      await abrirConPermisos(
        tester,
        ['vehicle:read', 'scan:read', 'scan:create', 'diagnosis:read'],
        'INSPECTOR',
      );
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Órdenes'), findsNothing);
    });
  });
}
