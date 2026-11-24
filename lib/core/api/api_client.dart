import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Error de API con código de estado, para que las pantallas puedan distinguir
/// un 401 (sesión vencida) de un 403 (rol sin permiso) o de un fallo de red.
class ApiException implements Exception {
  final int? statusCode;
  final String message;

  ApiException(this.message, {this.statusCode});

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;

  @override
  String toString() => message;
}

/// Mensaje listo para mostrar a partir de cualquier error. Los de la API ya
/// vienen redactados; a lo demás no se le muestra el detalle técnico.
String mensajeDeError(
  Object error, [
  String porDefecto = 'Ocurrió un error inesperado. Intente de nuevo.',
]) {
  return error is ApiException ? error.message : porDefecto;
}

class ApiClient {
  // Solo se guarda cuando alguien cambia el servidor a mano. La clave vieja
  // (`api_base_url`) guardaba la dirección en cada inicio de sesión, así que
  // los teléfonos ya instalados tenían fija la de desarrollo: se ignora.
  static const String _baseUrlOverrideKey = 'api_base_url_override';
  static const String _tokenKey = 'jwt_token';
  static const String _userKey = 'auth_user';

  /// Backend desplegado en Azure Container Apps.
  static const String productionBaseUrl =
      'https://taller-backend.proudriver-ee00705b.canadacentral.azurecontainerapps.io/api';

  // La app sale apuntando al backend desplegado. Para desarrollar contra un
  // backend local se fija otra dirección al compilar o ejecutar:
  //   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000/api
  // (10.0.2.2 es el localhost de la PC visto desde el emulador de Android).
  static const String defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: productionBaseUrl,
  );

  // El backend desplegado se apaga cuando no tiene uso y tarda en volver a
  // arrancar: la primera solicitud necesita un margen amplio.
  static const Duration _timeout = Duration(seconds: 60);

  static const String _sinConexion =
      'No se pudo conectar con el servidor. Revise su conexión e intente de nuevo.';

  /// Se invoca cuando el backend responde 401: la app debe volver al login.
  static void Function()? onUnauthorized;

  Future<String> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_baseUrlOverrideKey) ?? defaultBaseUrl;
  }

  /// Cambia el servidor. Vacío, o igual al de fábrica, vuelve al de fábrica.
  Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = normalizeBaseUrl(url);
    if (normalized.isEmpty || normalized == defaultBaseUrl) {
      await prefs.remove(_baseUrlOverrideKey);
    } else {
      await prefs.setString(_baseUrlOverrideKey, normalized);
    }
  }

  /// Quita espacios y barras finales, y agrega `/api` si solo se escribió el
  /// dominio: es fácil pegar la dirección del servidor sin la ruta.
  static String normalizeBaseUrl(String url) {
    final clean = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (clean.isEmpty) return '';
    final uri = Uri.tryParse(clean);
    if (uri != null && uri.hasAuthority && uri.path.isEmpty) {
      return '$clean/api';
    }
    return clean;
  }

  /// Ejecuta una solicitud y convierte los fallos de red (sin conexión,
  /// servidor caído, tiempo agotado) en un `ApiException` con un mensaje claro.
  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(_timeout);
    } catch (_) {
      throw ApiException(_sinConexion);
    }
  }

  // ---------------------------------------------------------------- sesión

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<Map<String, dynamic>?> getStoredUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_userKey);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
  }

  /// Autentica contra el backend y persiste token + usuario.
  ///
  /// Hasta ahora la app leía `jwt_token` de SharedPreferences pero nada lo
  /// escribía: el header Authorization nunca se enviaba y `POST /scans` tenía
  /// que quedar abierto. Este método cierra ese hueco.
  Future<Map<String, dynamic>> login(String email, String password) async {
    final baseUrl = await getBaseUrl();

    final response = await _send(
      () => http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email.trim(), 'password': password}),
      ),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        _extractMessage(response.body) ??
            'No se pudo iniciar sesión. Intente de nuevo.',
        statusCode: response.statusCode,
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final token = data['accessToken'] as String?;
    final user = data['user'] as Map<String, dynamic>?;

    if (token == null || user == null) {
      throw ApiException(
          'El servidor respondió algo inesperado. Intente de nuevo.');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userKey, jsonEncode(user));

    return user;
  }

  /// Revalida la sesión guardada contra el backend (token vencido o revocado).
  Future<Map<String, dynamic>> fetchProfile() async {
    final data = await _get('/auth/me');
    final user = data as Map<String, dynamic>;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(user));

    return user;
  }

  // ---------------------------------------------------------------- helpers

  Future<Map<String, String>> _headers() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  String? _extractMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['message'] != null) {
        final message = decoded['message'];
        return message is List ? message.join('. ') : message.toString();
      }
    } catch (_) {
      // cuerpo no-JSON
    }
    return null;
  }

  Never _fail(http.Response response) {
    if (response.statusCode == 401) {
      onUnauthorized?.call();
      throw ApiException(
        'Su sesión expiró. Vuelva a iniciar sesión.',
        statusCode: 401,
      );
    }
    if (response.statusCode == 403) {
      throw ApiException(
        _extractMessage(response.body) ??
            'Su rol no tiene permiso para esta operación.',
        statusCode: 403,
      );
    }
    throw ApiException(
      _extractMessage(response.body) ??
          'El servidor no pudo completar la operación (error ${response.statusCode}).',
      statusCode: response.statusCode,
    );
  }

  Future<dynamic> _get(String path) async {
    final baseUrl = await getBaseUrl();
    final headers = await _headers();
    final response = await _send(
      () => http.get(Uri.parse('$baseUrl$path'), headers: headers),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body);
    }
    _fail(response);
  }

  Future<dynamic> _post(String path, [Map<String, dynamic>? body]) async {
    final baseUrl = await getBaseUrl();
    final headers = await _headers();
    final response = await _send(
      () => http.post(
        Uri.parse('$baseUrl$path'),
        headers: headers,
        body: jsonEncode(body ?? const {}),
      ),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body);
    }
    _fail(response);
  }

  Future<dynamic> _patch(String path, Map<String, dynamic> body) async {
    final baseUrl = await getBaseUrl();
    final headers = await _headers();
    final response = await _send(
      () => http.patch(
        Uri.parse('$baseUrl$path'),
        headers: headers,
        body: jsonEncode(body),
      ),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body);
    }
    _fail(response);
  }

  // ---------------------------------------------------------------- push

  /// Registra este teléfono para recibir notificaciones push (CU18).
  Future<void> registerDevice(String token) async {
    await _post('/devices', {'token': token, 'platform': 'android'});
  }

  /// Al cerrar sesión, el teléfono deja de recibir avisos de esta cuenta.
  Future<void> unregisterDevice(String token) async {
    await _post('/devices/unregister', {'token': token});
  }

  /// Pide un push de prueba para los teléfonos del usuario.
  Future<Map<String, dynamic>> sendTestPush() async {
    return await _post('/devices/test') as Map<String, dynamic>;
  }

  // ---------------------------------------------------------------- vehículos

  /// Flota activa. Con [mine], solo los vehículos de los que el usuario es
  /// responsable.
  Future<List<dynamic>> getVehicles({bool mine = false}) async {
    return await _get(mine ? '/vehicles?mine=true' : '/vehicles')
        as List<dynamic>;
  }

  // ---------------------------------------------------------------- escaneos

  Future<List<dynamic>> getScans() async {
    return await _get('/scans') as List<dynamic>;
  }

  Future<Map<String, dynamic>> getScan(String id) async {
    return await _get('/scans/$id') as Map<String, dynamic>;
  }

  /// Hipótesis de IA de un escaneo.
  ///
  /// Devuelve `null` mientras se está generando: el backend responde 404 con
  /// «todavía se está generando», y eso es una espera, no un error. Cualquier
  /// otro error (incluido el 404 de «no requiere evaluación») se propaga.
  Future<Map<String, dynamic>?> getDiagnosis(String scanId) async {
    try {
      return await _get('/scans/$scanId/diagnosis') as Map<String, dynamic>;
    } on ApiException catch (e) {
      if (esHipotesisEnCurso(e)) return null;
      rethrow;
    }
  }

  /// El 404 de la hipótesis significa «todavía no llegó».
  static bool esHipotesisEnCurso(ApiException e) =>
      e.statusCode == 404 && e.message.contains('generando');

  Future<Map<String, dynamic>> submitScan(Map<String, dynamic> payload) async {
    return await _post('/scans', payload) as Map<String, dynamic>;
  }

  // ---------------------------------------------------------------- órdenes

  Future<List<dynamic>> getWorkOrders() async {
    return await _get('/work-orders') as List<dynamic>;
  }

  Future<Map<String, dynamic>> getWorkOrder(String id) async {
    return await _get('/work-orders/$id') as Map<String, dynamic>;
  }

  /// El mecánico toma una orden sin asignar. Si otro la tomó antes, el
  /// backend responde 409 con su nombre.
  Future<Map<String, dynamic>> takeWorkOrder(String id) async {
    return await _post('/work-orders/$id/take') as Map<String, dynamic>;
  }

  /// Registra el avance y, si hay, una nota que se agrega al historial.
  Future<Map<String, dynamic>> advanceWorkOrder(
    String id,
    String status, {
    String? notes,
  }) async {
    return await _patch('/work-orders/$id/status', {
      'status': status,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    }) as Map<String, dynamic>;
  }

  /// Cierra la orden como `COMPLETED` o `CANCELLED`, con justificación.
  Future<Map<String, dynamic>> closeWorkOrder(
    String id,
    String status,
    String resolution,
  ) async {
    return await _post('/work-orders/$id/close', {
      'status': status,
      'resolution': resolution.trim(),
    }) as Map<String, dynamic>;
  }

  /// Crea a mano la orden de un escaneo que no abrió una sola (severidad
  /// leve). Lo usa el inspector para derivar el vehículo al taller. Responde
  /// 409 si el escaneo ya tiene orden o el vehículo tiene otra abierta.
  Future<Map<String, dynamic>> createWorkOrder(
    String scanId, {
    String? description,
  }) async {
    return await _post('/work-orders', {
      'scanId': scanId,
      if (description != null && description.trim().isNotEmpty)
        'description': description.trim(),
    }) as Map<String, dynamic>;
  }

  // ------------------------------------------------- checklist y repuestos

  /// Agrega una tarea al checklist de verificación de la orden.
  Future<void> addTask(String workOrderId, String description) async {
    await _post('/work-orders/$workOrderId/tasks', {
      'description': description.trim(),
    });
  }

  /// Marca una tarea como hecha o la vuelve a pendiente.
  Future<void> toggleTask(
    String workOrderId,
    String taskId,
    bool completed,
  ) async {
    await _patch('/work-orders/$workOrderId/tasks/$taskId', {
      'completed': completed,
    });
  }

  /// Inventario de repuestos del taller.
  Future<List<dynamic>> getSpareParts() async {
    return await _get('/catalog/spare-parts') as List<dynamic>;
  }

  /// Registra un repuesto usado en la orden y lo descuenta del stock. Si no
  /// alcanza, el backend responde 400 con el stock disponible.
  Future<void> addPart(
    String workOrderId,
    String sparePartId,
    int quantity, {
    String? notes,
  }) async {
    await _post('/work-orders/$workOrderId/parts', {
      'sparePartId': sparePartId,
      'quantity': quantity,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    });
  }
}
