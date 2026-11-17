import 'package:flutter/material.dart';
import '../../core/api/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui/badges.dart';
import '../../core/ui/format.dart';
import '../../core/ui/panel.dart';

class VehiclesScreen extends StatefulWidget {
  const VehiclesScreen({super.key});

  @override
  State<VehiclesScreen> createState() => _VehiclesScreenState();
}

class _VehiclesScreenState extends State<VehiclesScreen> {
  final ApiClient _apiClient = ApiClient();
  List<dynamic> _vehicles = [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _fetchVehicles();
  }

  Future<void> _fetchVehicles() async {
    setState(() {
      // Al actualizar con la lista a la vista no se reemplaza por el spinner.
      _loading = _vehicles.isEmpty;
      _error = null;
    });
    try {
      final data = await _apiClient.getVehicles();
      if (mounted) {
        setState(() {
          _vehicles = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vehículos'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _fetchVehicles,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchVehicles,
              child: _buildBody(),
            ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return EmptyState.error(
        title: 'No se pudieron cargar los vehículos',
        error: _error!,
        onRetry: _fetchVehicles,
      );
    }
    if (_vehicles.isEmpty) {
      return const EmptyState(
        title: 'No hay vehículos registrados',
        message: 'El administrador los registra desde la plataforma web.',
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: _vehicles.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        return _VehicleCard(_vehicles[index] as Map<String, dynamic>);
      },
    );
  }
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard(this.vehicle);

  final Map<String, dynamic> vehicle;

  @override
  Widget build(BuildContext context) {
    final alias = (vehicle['alias'] as String?)?.trim() ?? '';
    final description = descripcionVehiculo(vehicle);
    final vin = (vehicle['vin'] as String?)?.trim() ?? '';
    final subtitle = [alias, description].where((t) => t.isNotEmpty).join(' · ');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${vehicle['plate'] ?? '-'}',
                    style: AppText.code.copyWith(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                VehicleStatusBadge(vehicle['status'] as String?),
              ],
            ),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 14, color: AppColors.ink2),
              ),
            ],
            const SizedBox(height: 6),
            Text.rich(
              TextSpan(
                text: 'VIN  ',
                style: const TextStyle(fontSize: 12, color: AppColors.ink3),
                children: [
                  TextSpan(
                    text: vin.isEmpty ? 'sin registrar' : vin,
                    style: vin.isEmpty
                        ? null
                        : AppText.code.copyWith(color: AppColors.ink2),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
