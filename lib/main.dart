import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/api/api_client.dart';
import 'core/auth/auth_service.dart';
import 'core/push/push_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/account_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/scan/scan_screen.dart';
import 'features/vehicles/vehicles_screen.dart';
import 'features/history/history_screen.dart';

void main() {
  runApp(const TallerMobileApp());
}

class TallerMobileApp extends StatelessWidget {
  const TallerMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) {
        final auth = AuthService();
        // Un 401 en cualquier request devuelve la app al login.
        ApiClient.onUnauthorized = auth.handleUnauthorized;
        auth.restoreSession();
        return auth;
      },
      child: MaterialApp(
        title: 'Diagnóstico vehicular UAGRM',
        // Las notificaciones push navegan y avisan desde fuera de los widgets.
        navigatorKey: PushService.navigatorKey,
        scaffoldMessengerKey: PushService.messengerKey,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const AuthGate(),
      ),
    );
  }
}

/// Decide qué ve el usuario según el estado de la sesión.
///
/// Antes la app entraba directo a la pantalla de escaneo sin autenticar, y el
/// backend tenía que aceptar escaneos anónimos. Ahora ningún escaneo puede
/// enviarse sin una sesión válida.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    if (auth.loading && !auth.isAuthenticated) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!auth.isAuthenticated) {
      return const LoginScreen();
    }

    return const MainScreen();
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = const [
    ScanScreen(),
    VehiclesScreen(),
    HistoryScreen(),
    AccountScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // La pantalla de escaneo se conserva al cambiar de pestaña, para no
      // descartar una lectura que todavía no se envió. Las demás se vuelven a
      // crear al entrar, así muestran datos recientes.
      body: IndexedStack(
        index: _selectedIndex == 0 ? 0 : 1,
        children: [
          _screens[0],
          if (_selectedIndex == 0)
            const SizedBox.shrink()
          else
            KeyedSubtree(
              key: ValueKey(_selectedIndex),
              child: _screens[_selectedIndex],
            ),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) {
            setState(() => _selectedIndex = index);
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.sensors),
              label: 'Escanear',
            ),
            NavigationDestination(
              icon: Icon(Icons.directions_car_outlined),
              selectedIcon: Icon(Icons.directions_car),
              label: 'Vehículos',
            ),
            NavigationDestination(
              icon: Icon(Icons.history),
              label: 'Historial',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Cuenta',
            ),
          ],
        ),
      ),
    );
  }
}
