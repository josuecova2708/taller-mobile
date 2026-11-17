import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui/badges.dart';
import '../../core/ui/format.dart';
import '../../core/ui/panel.dart';
import '../alerts/work_order_detail_screen.dart';

const _estadosAbiertos = ['OPEN', 'IN_PROGRESS'];

const _ordenPrioridad = ['CRITICAL', 'HIGH', 'MEDIUM', 'LOW'];

/// Separa las órdenes abiertas en las secciones de la pantalla.
///
/// Función pura para poder probarla sin widgets. Dentro de cada sección, lo
/// más urgente primero y, a igual prioridad, lo más antiguo.
({
  List<Map<String, dynamic>> sinAsignar,
  List<Map<String, dynamic>> mias,
  List<Map<String, dynamic>> otras
}) agruparOrdenes(List<dynamic> ordenes, String? userId) {
  final abiertas = ordenes
      .whereType<Map<String, dynamic>>()
      .where((o) => _estadosAbiertos.contains(o['status']))
      .toList()
    ..sort((a, b) {
      final porPrioridad = _ordenPrioridad
          .indexOf('${a['priority']}')
          .compareTo(_ordenPrioridad.indexOf('${b['priority']}'));
      if (porPrioridad != 0) return porPrioridad;
      return '${a['createdAt']}'.compareTo('${b['createdAt']}');
    });

  String? asignadoA(Map<String, dynamic> o) =>
      (o['assignedTo'] as Map<String, dynamic>?)?['id'] as String?;

  return (
    sinAsignar: abiertas.where((o) => asignadoA(o) == null).toList(),
    mias: abiertas
        .where((o) => userId != null && asignadoA(o) == userId)
        .toList(),
    otras: abiertas
        .where((o) => asignadoA(o) != null && asignadoA(o) != userId)
        .toList(),
  );
}

/// Órdenes de trabajo abiertas, para mecánicos y administradores.
///
/// «Sin asignar» son las que cualquier mecánico puede tomar; «Mis órdenes»,
/// las que el usuario tiene a cargo. Quien administra las órdenes ve también
/// las asignadas a otros, para poder reasignarlas o cerrarlas.
class WorkOrdersScreen extends StatefulWidget {
  const WorkOrdersScreen({super.key});

  @override
  State<WorkOrdersScreen> createState() => _WorkOrdersScreenState();
}

class _WorkOrdersScreenState extends State<WorkOrdersScreen> {
  final ApiClient _apiClient = ApiClient();
  List<dynamic> _orders = [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = _orders.isEmpty;
      _error = null;
    });
    try {
      final data = await _apiClient.getWorkOrders();
      if (mounted) {
        setState(() {
          _orders = data;
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

  Future<void> _open(String id) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
          builder: (_) => WorkOrderDetailScreen(workOrderId: id)),
    );
    // Al volver, la orden pudo haberse tomado o cerrado.
    if (mounted) _fetch();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Órdenes de trabajo'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _fetch,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(onRefresh: _fetch, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return EmptyState.error(
        title: 'No se pudieron cargar las órdenes',
        error: _error!,
        onRetry: _fetch,
      );
    }

    final auth = context.watch<AuthService>();
    final grupos = agruparOrdenes(_orders, auth.user?['id'] as String?);
    final manages = auth.can('order:assign');

    if (grupos.sinAsignar.isEmpty &&
        grupos.mias.isEmpty &&
        (!manages || grupos.otras.isEmpty)) {
      return const EmptyState(
        title: 'No hay órdenes pendientes',
        message:
            'Las órdenes se crean solas cuando un escaneo detecta una falla.',
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        _SectionHeader('Sin asignar', grupos.sinAsignar.length),
        if (grupos.sinAsignar.isEmpty)
          const _EmptyLine('No hay órdenes esperando a un mecánico.')
        else
          for (final o in grupos.sinAsignar) _OrderCard(order: o, onTap: _open),
        const SizedBox(height: 20),
        _SectionHeader('Mis órdenes', grupos.mias.length),
        if (grupos.mias.isEmpty)
          const _EmptyLine('No tiene órdenes a su cargo.')
        else
          for (final o in grupos.mias) _OrderCard(order: o, onTap: _open),
        if (manages) ...[
          const SizedBox(height: 20),
          _SectionHeader('Asignadas a otros', grupos.otras.length),
          if (grupos.otras.isEmpty)
            const _EmptyLine('Ninguna.')
          else
            for (final o in grupos.otras)
              _OrderCard(order: o, onTap: _open, showAssignee: true),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, this.count);

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        '$title ($count)',
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
      ),
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(fontSize: 14, color: AppColors.ink2));
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.onTap,
    this.showAssignee = false,
  });

  final Map<String, dynamic> order;
  final void Function(String id) onTap;
  final bool showAssignee;

  @override
  Widget build(BuildContext context) {
    final vehicle = (order['vehicle'] as Map<String, dynamic>?) ?? const {};
    final alias = (vehicle['alias'] as String?)?.trim() ?? '';
    final assignedTo = order['assignedTo'] as Map<String, dynamic>?;
    final id = order['id'] as String;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onTap(id),
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
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    PriorityBadge(order['priority'] as String?),
                  ],
                ),
                if (alias.isNotEmpty)
                  Text(alias,
                      style:
                          const TextStyle(fontSize: 13, color: AppColors.ink2)),
                const SizedBox(height: 6),
                Text(
                  '${order['description'] ?? ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, height: 1.35),
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    'Creada ${hace(order['createdAt'] as String?)}',
                    if (showAssignee && assignedTo != null)
                      'A cargo de ${assignedTo['name']}',
                    if (order['status'] == 'IN_PROGRESS') 'En proceso',
                  ].join(' · '),
                  style: const TextStyle(fontSize: 12, color: AppColors.ink3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
