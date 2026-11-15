import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../../features/alerts/work_order_detail_screen.dart';

/// Estado de las notificaciones en este teléfono, para mostrarlo en «Cuenta».
enum PushStatus {
  /// Todavía no se intentó (no hay sesión o está arrancando).
  inactivo,

  /// El teléfono está registrado y recibirá los avisos.
  activo,

  /// El usuario no permitió las notificaciones en Android.
  sinPermiso,

  /// Firebase no está disponible (por ejemplo, sin Google Play Services).
  noDisponible,

  /// Hay token, pero el backend no pudo guardarlo (sin conexión, etc.).
  sinRegistrar,
}

/// Notificaciones push (CU18).
///
/// Al iniciar sesión pide permiso, obtiene el token de Firebase y lo registra
/// en el backend. El backend envía un push cuando se crea una orden de
/// trabajo; al tocarlo, la app abre el detalle de esa orden.
///
/// Nada de esto puede impedir el uso de la app: si Firebase falla, se anota
/// el estado y la app sigue funcionando sin avisos.
class PushService {
  PushService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  /// Permiten navegar y mostrar avisos desde fuera del árbol de widgets.
  static final navigatorKey = GlobalKey<NavigatorState>();
  static final messengerKey = GlobalKey<ScaffoldMessengerState>();

  final ValueNotifier<PushStatus> status = ValueNotifier(PushStatus.inactivo);

  String? _token;
  bool _listening = false;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  /// Se llama cuando hay una sesión válida (login o sesión restaurada).
  Future<void> start() async {
    try {
      await Firebase.initializeApp();
      final messaging = FirebaseMessaging.instance;

      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        status.value = PushStatus.sinPermiso;
        return;
      }

      // firebase_messaging 17 propone un esquema nuevo de registro (FID) y
      // marca el token como obsoleto. Se mantiene el token: sigue vigente y
      // es lo que el backend guarda y usa para enviar.
      // ignore: deprecated_member_use
      final token = await messaging.getToken();
      if (token == null) {
        status.value = PushStatus.noDisponible;
        return;
      }

      _listen(messaging);
      await _register(token);

      // La app estaba cerrada y se abrió tocando una notificación.
      final initial = await messaging.getInitialMessage();
      if (initial != null) _open(initial);
    } catch (_) {
      status.value = PushStatus.noDisponible;
    }
  }

  /// Se llama al cerrar sesión, antes de borrar el token de sesión: el
  /// teléfono deja de recibir los avisos de esa cuenta.
  Future<void> stop() async {
    final token = _token;
    _token = null;
    status.value = PushStatus.inactivo;
    if (token == null) return;
    try {
      await _api.unregisterDevice(token);
    } catch (_) {
      // Sin conexión: el backend lo reasigna cuando otra cuenta inicie sesión.
    }
  }

  /// Pide al backend un push de prueba para este usuario.
  /// Devuelve el texto que se le muestra al usuario.
  Future<String> sendTest() async {
    if (status.value != PushStatus.activo) {
      await start();
    }
    if (status.value != PushStatus.activo) {
      return describe(status.value);
    }
    try {
      final result = await _api.sendTestPush();
      if (result['enviado'] == true) {
        return 'Notificación de prueba enviada.';
      }
      return (result['motivo'] as String?) ?? 'No se pudo enviar la prueba.';
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'No se pudo contactar al servidor.';
    }
  }

  static String describe(PushStatus status) {
    switch (status) {
      case PushStatus.activo:
        return 'Este teléfono recibe los avisos de órdenes de trabajo.';
      case PushStatus.sinPermiso:
        return 'Las notificaciones están bloqueadas. Actívelas en los ajustes de Android para esta aplicación.';
      case PushStatus.noDisponible:
        return 'Las notificaciones no están disponibles en este teléfono.';
      case PushStatus.sinRegistrar:
        return 'No se pudo registrar el teléfono en el servidor. Revise la conexión.';
      case PushStatus.inactivo:
        return 'Las notificaciones todavía no se activaron.';
    }
  }

  Future<void> _register(String token) async {
    _token = token;
    try {
      await _api.registerDevice(token);
      status.value = PushStatus.activo;
    } catch (_) {
      status.value = PushStatus.sinRegistrar;
    }
  }

  void _listen(FirebaseMessaging messaging) {
    if (_listening) return;
    _listening = true;

    _subscriptions.addAll([
      // Firebase puede renovar el token en cualquier momento.
      // ignore: deprecated_member_use
      messaging.onTokenRefresh.listen((token) {
        if (_token != null) _register(token);
      }),
      // Con la app abierta Android no muestra la notificación: se avisa adentro.
      FirebaseMessaging.onMessage.listen(_showInApp),
      // La app estaba en segundo plano y el usuario tocó la notificación.
      FirebaseMessaging.onMessageOpenedApp.listen(_open),
    ]);
  }

  void _showInApp(RemoteMessage message) {
    final messenger = messengerKey.currentState;
    final notification = message.notification;
    if (messenger == null || notification == null) return;

    final orderId = message.data['workOrderId'] as String?;
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        behavior: SnackBarBehavior.floating,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              notification.title ?? 'Aviso',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if ((notification.body ?? '').isNotEmpty)
              Text(
                notification.body!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        action: orderId == null
            ? null
            : SnackBarAction(label: 'Ver', onPressed: () => _open(message)),
      ),
    );
  }

  void _open(RemoteMessage message) {
    final orderId = message.data['workOrderId'] as String?;
    if (orderId == null || orderId.isEmpty) return;

    void push() {
      navigatorKey.currentState?.push(
        MaterialPageRoute<void>(
          builder: (_) => WorkOrderDetailScreen(workOrderId: orderId),
        ),
      );
    }

    if (navigatorKey.currentState != null) {
      push();
    } else {
      // La app recién arranca: se espera a que exista el navegador.
      WidgetsBinding.instance.addPostFrameCallback((_) => push());
    }
  }
}
