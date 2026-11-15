import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';

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
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
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
    final message = forbidden
        ? 'Su rol no puede ver órdenes de trabajo.'
        : error is ApiException
            ? (error as ApiException).message
            : 'No se pudo cargar la orden. Revise la conexión.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: Colors.grey.shade600),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (!forbidden) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onRetry,
                child: const Text('Reintentar'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OrderView extends StatelessWidget {
  const _OrderView({required this.order});

  final Map<String, dynamic> order;

  static const _priorityLabels = {
    'LOW': 'Prioridad baja',
    'MEDIUM': 'Prioridad media',
    'HIGH': 'Prioridad alta',
    'CRITICAL': 'Prioridad crítica',
  };

  static const _statusLabels = {
    'OPEN': 'Abierta',
    'IN_PROGRESS': 'En proceso',
    'COMPLETED': 'Completada',
    'CANCELLED': 'Cancelada',
  };

  static const _dtcTypeLabels = {
    'CONFIRMED': 'Confirmado',
    'PENDING': 'Pendiente',
    'PERMANENT': 'Permanente',
  };

  Color _priorityColor(String priority) {
    switch (priority) {
      case 'CRITICAL':
      case 'HIGH':
        return Colors.red.shade700;
      case 'MEDIUM':
        return Colors.orange.shade800;
      default:
        return Colors.green.shade700;
    }
  }

  String _date(String? iso) {
    final date = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
    if (date == null) return '-';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} '
        '${two(date.hour)}:${two(date.minute)}';
  }

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
    final model = [vehicle['make'], vehicle['model'], vehicle['year']]
        .where((v) => v != null && v.toString().isNotEmpty)
        .join(' ');

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
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
                if (alias.isNotEmpty || model.isNotEmpty)
                  Text(
                    [alias, model].where((t) => t.isNotEmpty).join(' · '),
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Chip(
                      avatar: Icon(
                        Icons.flag,
                        size: 16,
                        color: _priorityColor(priority),
                      ),
                      label: Text(_priorityLabels[priority] ?? priority),
                      visualDensity: VisualDensity.compact,
                    ),
                    Chip(
                      label: Text(_statusLabels[status] ?? status),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _Section(
          title: 'Motivo',
          child: Text((order['description'] as String?) ?? '-'),
        ),
        _Section(
          title: 'Códigos de falla',
          child: dtcs.isEmpty
              ? const Text('El escaneo no registró códigos de falla.')
              : Column(
                  children: dtcs.map((entry) {
                    final dtc = entry as Map<String, dynamic>;
                    final type = (dtc['type'] as String?) ?? '';
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${dtc['code']} · ${_dtcTypeLabels[type] ?? type}',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        (dtc['description'] as String?) ?? 'Sin descripción',
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
              Text('Creada: ${_date(order['createdAt'] as String?)}'),
              const SizedBox(height: 4),
              Text(
                'Mecánico: ${(assignedTo?['name'] as String?) ?? 'sin asignar'}',
              ),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(notes, style: TextStyle(color: Colors.grey.shade800)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'La orden se asigna, avanza y cierra desde la plataforma web.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}
