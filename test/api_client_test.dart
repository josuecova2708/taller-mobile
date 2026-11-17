import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taller_mobile/core/api/api_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Dirección del servidor', () {
    test('sin configurar nada, la app apunta al backend desplegado', () async {
      SharedPreferences.setMockInitialValues({});

      expect(await ApiClient().getBaseUrl(), ApiClient.productionBaseUrl);
      expect(ApiClient.productionBaseUrl, startsWith('https://'));
      expect(ApiClient.productionBaseUrl, endsWith('/api'));
    });

    test('la dirección de desarrollo que guardaban las versiones anteriores se ignora',
        () async {
      SharedPreferences.setMockInitialValues({
        'api_base_url': 'http://10.0.2.2:3000/api',
      });

      expect(await ApiClient().getBaseUrl(), ApiClient.productionBaseUrl);
    });

    test('un servidor elegido a mano se conserva, y vacío vuelve al de fábrica',
        () async {
      SharedPreferences.setMockInitialValues({});
      final api = ApiClient();

      await api.setBaseUrl(' http://192.168.1.20:3000/api/ ');
      expect(await api.getBaseUrl(), 'http://192.168.1.20:3000/api');

      await api.setBaseUrl('');
      expect(await api.getBaseUrl(), ApiClient.productionBaseUrl);
    });

    test('si solo se pega el dominio, se agrega /api', () {
      expect(
        ApiClient.normalizeBaseUrl('https://ejemplo.azurecontainerapps.io/'),
        'https://ejemplo.azurecontainerapps.io/api',
      );
      expect(
        ApiClient.normalizeBaseUrl('http://10.0.2.2:3000/api'),
        'http://10.0.2.2:3000/api',
      );
    });
  });

  test('un fallo de red se informa con un mensaje claro, sin detalle técnico',
      () async {
    SharedPreferences.setMockInitialValues({});
    // El entorno de pruebas responde 400 a todo sin salir a la red; aquí hace
    // falta la red de verdad para que la conexión falle.
    final previous = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = previous);

    // Puerto cerrado en la propia máquina: la conexión se rechaza al instante.
    await ApiClient().setBaseUrl('http://127.0.0.1:9/api');

    await expectLater(
      ApiClient().getVehicles(),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', isNull)
            .having((e) => e.message, 'message', contains('No se pudo conectar')),
      ),
    );
  });
}
