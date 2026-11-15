import 'dart:async';

import 'package:flutter/foundation.dart';
import '../api/api_client.dart';
import '../push/push_service.dart';

/// Estado de sesión de la app.
///
/// Mantiene el usuario autenticado y sus permisos efectivos (tal como los
/// entrega el backend), de modo que la UI no duplique la matriz de permisos.
class AuthService extends ChangeNotifier {
  final ApiClient _apiClient;

  /// Notificaciones push: se activan con la sesión y se apagan al salir.
  final PushService push;

  AuthService({ApiClient? apiClient, PushService? pushService})
      : _apiClient = apiClient ?? ApiClient(),
        push = pushService ?? PushService(apiClient: apiClient);

  Map<String, dynamic>? _user;
  bool _loading = true;
  String? _error;

  Map<String, dynamic>? get user => _user;
  bool get isAuthenticated => _user != null;
  bool get loading => _loading;
  String? get error => _error;

  String get userName => (_user?['name'] as String?) ?? '';
  String get roleLabel => (_user?['roleLabel'] as String?) ?? (_user?['role'] as String? ?? '');

  List<String> get permissions =>
      ((_user?['permissions'] as List<dynamic>?) ?? const []).cast<String>();

  bool can(String permission) => permissions.contains(permission);

  /// Restaura la sesión al abrir la app y la revalida contra el backend.
  Future<void> restoreSession() async {
    _loading = true;
    notifyListeners();

    final token = await _apiClient.getToken();
    if (token == null || token.isEmpty) {
      _user = null;
      _loading = false;
      notifyListeners();
      return;
    }

    // Se muestra primero el usuario guardado para no bloquear la UI...
    _user = await _apiClient.getStoredUser();
    notifyListeners();

    // ...y luego se confirma con el backend. Si el token venció, se cierra.
    try {
      _user = await _apiClient.fetchProfile();
      // En segundo plano: registrar el teléfono no debe demorar la entrada.
      unawaited(push.start());
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        await _apiClient.clearSession();
        _user = null;
      }
      // Sin conexión: se conserva la sesión local y se reintentará luego.
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> login(String email, String password) async {
    _error = null;
    _loading = true;
    notifyListeners();

    try {
      _user = await _apiClient.login(email, password);
      unawaited(push.start());
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      _user = null;
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    // Antes de borrar la sesión: quitar el teléfono requiere el token.
    await push.stop();
    await _apiClient.clearSession();
    _user = null;
    _error = null;
    notifyListeners();
  }

  /// Invocado por el `ApiClient` ante un 401 en cualquier request.
  void handleUnauthorized() {
    if (_user == null) return;
    _apiClient.clearSession();
    _user = null;
    notifyListeners();
  }
}
