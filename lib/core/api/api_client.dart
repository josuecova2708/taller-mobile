import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiClient {
  static const String _baseUrlKey = 'api_base_url';
  static const String _tokenKey = 'jwt_token';

  // En emulador Android 10.0.2.2 apunta al localhost de la PC; en web/Windows localhost
  static const String defaultBaseUrl = 'http://localhost:3000/api';

  Future<String> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_baseUrlKey) ?? defaultBaseUrl;
  }

  Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, url.trim().replaceAll(RegExp(r'/$'), ''));
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<Map<String, String>> _headers() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Future<List<dynamic>> getVehicles() async {
    final baseUrl = await getBaseUrl();
    final response = await http
        .get(Uri.parse('$baseUrl/vehicles'), headers: await _headers())
        .timeout(const Duration(seconds: 10));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw Exception('Error ${response.statusCode}: ${response.body}');
  }

  Future<List<dynamic>> getScans() async {
    final baseUrl = await getBaseUrl();
    final response = await http
        .get(Uri.parse('$baseUrl/scans'), headers: await _headers())
        .timeout(const Duration(seconds: 10));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw Exception('Error ${response.statusCode}: ${response.body}');
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
    throw Exception('Error ${response.statusCode}: ${response.body}');
  }
}
