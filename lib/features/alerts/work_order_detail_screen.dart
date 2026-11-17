import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui/badges.dart';
import '../../core/ui/format.dart';
import '../../core/ui/panel.dart';

/// Detalle de la alerta que se abre al tocar una notificación push (CU18).
///
/// Es de solo lectura: la orden se asigna, avanza y cierra desde la web.
class WorkOrderDetailScreen extends StatefulWidget {
  const WorkOrderDetailScreen({
    super.key,
    required this.workOrderId,
    this.apiClient,
  });

  final String workOrderId;
  final ApiClient? apiClient;

  @override
  State<WorkOrderDetailScreen> createState() => _WorkOrderDetailScreenState();
}

class _WorkOrderDetailScreenState extends State<WorkOrderDetailScreen> {
  late final ApiClient _api = widget.apiClient ?? ApiClient();
  late Future<Map<String, dynamic>> _order = _load();

  Future<Map<String, dynamic>> _load() => _api.getWorkOrder(widget.workOrderId);

  void _retry() {
    setState(() {
      _order = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Orden de trabajo'),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _order,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorView(error: snapshot.error!, onRetry: _retry);
          }
          return _OrderView(order: snapshot.data!);
        },
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final forbidden = error is ApiException && (error as ApiException).isForbidden;
    if (forbidden) {
      return const EmptyState(
        title: 'Su rol no puede ver órdenes de trabajo',
        message: 'Las ven los mecánicos y los administradores.',
      );
    }
    return EmptyState.error(
      title: 'No se pudo cargar la orden',
      error: error,
      onRetry: onRetry,
    );
  }
}

class _OrderView extends StatelessWidget {
  const _OrderView({required this.order});

  final Map<String, dynamic> order;

  @override
  Widget build(BuildContext context) {
    final vehicle = (order['vehicle'] as Map<String, dynamic>?) ?? const {};
    final scan = (order['scan'] as Map<String, dynamic>?) ?? const {};
    final dtcs = (scan['dtcEntries'] as List<dynamic>?) ?? const [];
    final assignedTo = order['assignedTo'] as Map<String, dynamic>?;
    final priority = (order['priority'] as String?) ?? '';
    final status = (order['status'] as String?) ?? '';
    final notes = (order['notes'] as String?)?.trim() ?? '';

    final plate = (vehicle['plate'] as String?) ?? '-';
    final alias = (vehicle['alias'] as String?) ?? '';
    final model = descripcionVehiculo(vehicle);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plate,
                  style: AppText.code.copyWith(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                if (alias.isNotEmpty || model.isNotEmpty)
                  Text(
                    [alias, model].where((t) => t.isNotEmpty).join(' · '),
                    style: const TextStyle(fontSize: 14, color: AppColors.ink2),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    PriorityBadge(priority),
                    OrderStatusBadge(status),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _Section(
          title: 'Motivo',
          child: Text(
            (order['description'] as String?) ?? '-',
            style: const TextStyle(fontSize: 14, height: 1.4),
          ),
        ),
        _Section(
          title: 'Códigos de falla',
          child: dtcs.isEmpty
              ? const Text('El escaneo no registró códigos de falla.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: dtcs.map((entry) {
                    final dtc = entry as Map<String, dynamic>;
                    final type = (dtc['type'] as String?) ?? '';
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${dtc['code']}',
                                  style: AppText.code.copyWith(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              DtcTypeBadge(type),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            (dtc['description'] as String?) ?? 'Sin descripción',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.ink2,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
        _Section(
          title: 'Seguimiento',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Dato(
                label: 'Creada',
                value: fechaHora(order['createdAt'] as String?),
              ),
              Dato(
                label: 'Mecánico',
                value: (assignedTo?['name'] as String?) ?? 'Sin asignar',
              ),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  notes,
                  style: const TextStyle(fontSize: 14, color: AppColors.ink2),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'La orden se asigna, avanza y cierra desde la plataforma web.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: AppColors.ink3),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Panel(title: title, child: child),
    );
  }
}
