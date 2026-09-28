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

class ApiClient {
  static const String _baseUrlKey = 'api_base_url';
  static const String _tokenKey = 'jwt_token';
  static const String _userKey = 'auth_user';

  // En emulador Android 10.0.2.2 apunta al localhost de la PC; en web/Windows localhost
  static const String defaultBaseUrl = 'http://10.0.2.2:3000/api';

  /// Se invoca cuando el backend responde 401: la app debe volver al login.
  static void Function()? onUnauthorized;

  Future<String> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_baseUrlKey) ?? defaultBaseUrl;
  }

  Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, url.trim().replaceAll(RegExp(r'/$'), ''));
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

    final http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('$baseUrl/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email.trim(), 'password': password}),
          )
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      throw ApiException(
        'No se pudo contactar al backend en $baseUrl. Verifique la URL y que el servidor esté corriendo.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        _extractMessage(response.body) ?? 'Credenciales inválidas',
        statusCode: response.statusCode,
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final token = data['accessToken'] as String?;
    final user = data['user'] as Map<String, dynamic>?;

    if (token == null || user == null) {
      throw ApiException('Respuesta de login inesperada del backend.');
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
        return message is List ? message.join(', ') : message.toString();
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
        _extractMessage(response.body) ?? 'Su rol no tiene permiso para esta operación.',
        statusCode: 403,
      );
    }
    throw ApiException(
      _extractMessage(response.body) ?? 'Error ${response.statusCode}',
      statusCode: response.statusCode,
    );
  }

  Future<dynamic> _get(String path) async {
    final baseUrl = await getBaseUrl();
    final response = await http
        .get(Uri.parse('$baseUrl$path'), headers: await _headers())
        .timeout(const Duration(seconds: 10));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body);
    }
    _fail(response);
  }

  // ---------------------------------------------------------------- recursos

  Future<List<dynamic>> getVehicles() async {
    return await _get('/vehicles') as List<dynamic>;
  }

  Future<List<dynamic>> getScans() async {
    return await _get('/scans') as List<dynamic>;
  }

  Future<Map<String, dynamic>> submitScan(Map<String, dynamic> payload) async {
    final baseUrl = await getBaseUrl();
    final response = await http
        .post(
          Uri.parse('$baseUrl/scans'),
          headers: await _headers(),
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    _fail(response);
  }
}
