import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/auth_service.dart';
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

    final auth = context.watch<AuthService>();
    final vehicles = _vehicles.whereType<Map<String, dynamic>>().toList();

    final unit = auth.user?['unit'] as Map<String, dynamic>?;

    // Un inspector con facultad recibe del backend solo los vehículos de su
    // facultad: se muestran todos juntos.
    if (auth.user?['role'] == 'INSPECTOR' && unit != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _SectionTitle(
              'Vehículos de ${unit['name'] ?? 'mi facultad'} (${vehicles.length})'),
          for (final v in vehicles) _VehicleCard(v),
        ],
      );
    }

    // Sin facultad, el inspector ve primero los vehículos de los que es
    // responsable.
    if (auth.user?['role'] == 'INSPECTOR') {
      final (mine, others) =
          separarPorResponsable(vehicles, auth.user?['id'] as String?);
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _SectionTitle('Mis vehículos (${mine.length})'),
          if (mine.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                'Todavía no es responsable de ningún vehículo. Lo asigna el administrador.',
                style: TextStyle(fontSize: 14, color: AppColors.ink2),
              ),
            ),
          for (final v in mine) _VehicleCard(v),
          if (others.isNotEmpty) ...[
            const SizedBox(height: 10),
            _SectionTitle('Resto de la flota (${others.length})'),
            for (final v in others) _VehicleCard(v),
          ],
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [for (final v in vehicles) _VehicleCard(v)],
    );
  }
}

/// Separa los vehículos de los que [userId] es responsable del resto,
/// conservando el orden original.
(List<Map<String, dynamic>>, List<Map<String, dynamic>>) separarPorResponsable(
  List<Map<String, dynamic>> vehicles,
  String? userId,
) {
  bool esMio(Map<String, dynamic> v) =>
      userId != null &&
      (v['responsible'] as Map<String, dynamic>?)?['id'] == userId;
  return (
    vehicles.where(esMio).toList(),
    vehicles.where((v) => !esMio(v)).toList(),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
      ),
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
    final subtitle =
        [alias, description].where((t) => t.isNotEmpty).join(' · ');
    final responsible =
        (vehicle['responsible'] as Map<String, dynamic>?)?['name'] as String?;
    final unit = (vehicle['unit'] as Map<String, dynamic>?)?['name'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
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
            const SizedBox(height: 2),
            Text(
              [
                if (unit != null) unit,
                'Responsable: ${responsible ?? 'sin asignar'}',
              ].join(' · '),
              style: const TextStyle(fontSize: 12, color: AppColors.ink3),
            ),
          ],
        ),
      ),
    );
  }
}
