import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui/badges.dart';
import '../../core/ui/format.dart';
import '../../core/ui/panel.dart';
import '../alerts/work_order_detail_screen.dart';
import 'order_rules.dart';

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
      .where((o) => estadosAbiertos.contains(o['status']))
      .toList()
    ..sort(compararPorUrgencia);

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

/// Órdenes de trabajo.
///
/// Para mecánicos y administradores: «Sin asignar» son las que cualquier
/// mecánico puede tomar; «Mis órdenes», las que el usuario tiene a cargo.
/// Quien administra las órdenes ve también las asignadas a otros.
///
/// El inspector solo las consulta (las de los vehículos de su facultad): las
/// ve por estado, sin acciones, y con las últimas cerradas.
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
    if (!auth.can('order:update_status')) return _buildSoloConsulta();

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

  /// Vista del inspector: consulta en qué va cada orden, sin acciones.
  Widget _buildSoloConsulta() {
    final grupos = agruparOrdenesPorEstado(_orders);

    if (grupos.sinMecanico.isEmpty &&
        grupos.enTaller.isEmpty &&
        grupos.cerradas.isEmpty) {
      return const EmptyState(
        title: 'No hay órdenes de sus vehículos',
        message:
            'Se crean solas cuando un escaneo detecta una falla, o desde el detalle '
            'de un escaneo con «Enviar al taller».',
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Text(
            'Órdenes de los vehículos de su facultad. Las atienden los mecánicos; '
            'aquí puede seguir en qué paso va cada una.',
            style: TextStyle(fontSize: 13, color: AppColors.ink2),
          ),
        ),
        _SectionHeader('Esperando mecánico', grupos.sinMecanico.length),
        if (grupos.sinMecanico.isEmpty)
          const _EmptyLine('Ninguna.')
        else
          for (final o in grupos.sinMecanico) _OrderCard(order: o, onTap: _open),
        const SizedBox(height: 20),
        _SectionHeader('En el taller', grupos.enTaller.length),
        if (grupos.enTaller.isEmpty)
          const _EmptyLine('Ninguna.')
        else
          for (final o in grupos.enTaller)
            _OrderCard(order: o, onTap: _open, showAssignee: true),
        if (grupos.cerradas.isNotEmpty) ...[
          const SizedBox(height: 20),
          _SectionHeader('Cerradas recientemente', grupos.cerradas.length),
          for (final o in grupos.cerradas)
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
                    if (estadosAbiertos.contains(order['status']))
                      PriorityBadge(order['priority'] as String?)
                    else
                      OrderStatusBadge(order['status'] as String?),
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
                    if (estadosAbiertos.contains(order['status']))
                      'Creada ${hace(order['createdAt'] as String?)}'
                    else
                      'Cerrada ${hace(order['closedAt'] as String?)}',
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
