import 'package:flutter/material.dart';
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
    return MaterialApp(
      title: 'Taller OBD-II',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
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
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.qr_code_scanner),
            selectedIcon: Icon(Icons.qr_code_scanner, color: Colors.blue),
            label: 'Escanear',
          ),
          NavigationDestination(
            icon: Icon(Icons.directions_car),
            selectedIcon: Icon(Icons.directions_car, color: Colors.blue),
            label: 'Vehículos',
          ),
          NavigationDestination(
            icon: Icon(Icons.history),
            selectedIcon: Icon(Icons.history, color: Colors.blue),
            label: 'Historial',
          ),
        ],
      ),
    );
  }
}
