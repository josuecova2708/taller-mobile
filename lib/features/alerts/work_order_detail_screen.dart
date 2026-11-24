import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui/badges.dart';
import '../../core/ui/format.dart';
import '../../core/ui/hipotesis.dart';
import '../../core/ui/notice.dart';
import '../../core/ui/panel.dart';
import '../history/scan_detail_screen.dart' show DtcRow;
import '../orders/order_rules.dart';
import 'order_sections.dart';

/// Detalle de una orden de trabajo. Se abre desde la pestaña «Órdenes» y al
/// tocar la notificación push de una orden nueva (CU18).
///
/// Según quién mira, permite tomar la orden, marcar el checklist, registrar
/// repuestos y avances, y cerrarla. El inspector solo la consulta. Las mismas
/// reglas las aplica el backend; aquí solo deciden qué se muestra.
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

  Map<String, dynamic>? _order;
  Object? _loadError;
  bool _loading = true;

  bool _working = false;
  String? _message;
  NoticeTone _messageTone = NoticeTone.success;

  final _noteController = TextEditingController();
  final _resolutionController = TextEditingController();
  String _closeStatus = 'COMPLETED';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _noteController.dispose();
    _resolutionController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _order == null;
      _loadError = null;
    });
    try {
      final order = await _api.getWorkOrder(widget.workOrderId);
      if (!mounted) return;
      setState(() {
        _order = order;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  /// Ejecuta una acción, muestra su resultado y vuelve a cargar la orden.
  Future<void> _run(Future<String> Function() action) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      final message = await action();
      if (!mounted) return;
      setState(() {
        _message = message;
        _messageTone = NoticeTone.success;
      });
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _message = mensajeDeError(
            e, 'No se pudo completar la operación. Intente de nuevo.');
        _messageTone = NoticeTone.error;
      });
      // Una orden tomada por otro, o ya cerrada: se muestra cómo quedó.
      if (e is ApiException && (e.statusCode == 409 || e.statusCode == 403)) {
        await _load();
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _take() => _run(() async {
        await _api.takeWorkOrder(widget.workOrderId);
        return 'Tomó la orden. Ya puede registrar el avance y cerrarla al terminar.';
      });

  void _saveProgress() => _run(() async {
        await _api.advanceWorkOrder(
          widget.workOrderId,
          'IN_PROGRESS',
          notes: _noteController.text,
        );
        _noteController.clear();
        return 'Avance guardado en el historial.';
      });

  void _toggleTask(String taskId, bool completed) => _run(() async {
        await _api.toggleTask(widget.workOrderId, taskId, completed);
        return completed ? 'Tarea marcada como hecha.' : 'Tarea vuelta a pendiente.';
      });

  /// Devuelve si se agregó, para que el campo se limpie solo en ese caso.
  Future<bool> _addTask(String description) async {
    var ok = false;
    await _run(() async {
      await _api.addTask(widget.workOrderId, description);
      ok = true;
      return 'Tarea agregada al checklist.';
    });
    return ok;
  }

  Future<void> _registerPart() async {
    final elegido = await elegirRepuesto(context, _api);
    if (elegido == null || !mounted) return;
    await _run(() async {
      await _api.addPart(
        widget.workOrderId,
        elegido.sparePartId,
        elegido.quantity,
        notes: elegido.notes,
      );
      return 'Repuesto registrado y descontado del inventario.';
    });
  }

  Future<void> _confirmClose() async {
    final completed = _closeStatus == 'COMPLETED';
    final tareas = contarTareas(_order?['tasks'] as List<dynamic>?);
    final pendientes = tareas.total - tareas.hechas;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar orden'),
        content: Text(
          '${completed && pendientes > 0 ? 'Quedan $pendientes ${pendientes == 1 ? 'tarea' : 'tareas'} del checklist sin marcar. ' : ''}'
          'La orden quedará como ${completed ? 'completada' : 'cancelada'} y no se '
          'podrá volver a abrir. '
          '${completed ? 'El vehículo vuelve a quedar operativo y queda registrado que usted lo cerró.' : 'El estado del vehículo se tomará de su último escaneo.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(completed && pendientes > 0
                ? 'Cerrar igual'
                : 'Cerrar orden'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await _run(() async {
      final result = await _api.closeWorkOrder(
        widget.workOrderId,
        _closeStatus,
        _resolutionController.text,
      );
      _resolutionController.clear();
      if (result['operationAuthorized'] == true) {
        return 'Orden cerrada. El vehículo vuelve a estar operativo.';
      }
      return completed
          ? 'Orden cerrada. El vehículo conserva su estado porque tiene otras órdenes sin cerrar.'
          : 'Orden cancelada. El estado del vehículo se toma de su último escaneo.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Orden de trabajo'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _working ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_order == null) {
      final error = _loadError ?? 'Error';
      final forbidden = error is ApiException && error.isForbidden;
      if (forbidden) {
        return const EmptyState(
          title: 'No puede ver esta orden de trabajo',
          message:
              'Las ven los mecánicos, los administradores y los inspectores de la '
              'facultad del vehículo.',
        );
      }
      return EmptyState.error(
        title: 'No se pudo cargar la orden',
        error: error,
        onRetry: _load,
      );
    }

    final auth = context.watch<AuthService>();
    final order = _order!;
    final userId = auth.user?['id'] as String?;
    final role = auth.user?['role'] as String?;

    final vehicle = (order['vehicle'] as Map<String, dynamic>?) ?? const {};
    final scan = (order['scan'] as Map<String, dynamic>?) ?? const {};
    final dtcs = (scan['dtcEntries'] as List<dynamic>?) ?? const [];
    final assignedTo = order['assignedTo'] as Map<String, dynamic>?;
    final responsible = vehicle['responsible'] as Map<String, dynamic>?;
    final closedBy = order['closedBy'] as Map<String, dynamic>?;
    final diagnosis = order['diagnosis'];
    final priority = (order['priority'] as String?) ?? '';
    final status = (order['status'] as String?) ?? '';
    final notes = (order['notes'] as String?)?.trim() ?? '';
    final tasks = (order['tasks'] as List<dynamic>?) ?? const [];
    final partsUsed = (order['partsUsed'] as List<dynamic>?) ?? const [];
    final history = (order['statusHistory'] as List<dynamic>?) ?? const [];
    final conteo = contarTareas(tasks);
    final unit = vehicle['unit'] as Map<String, dynamic>?;

    final open = estadosAbiertos.contains(status);
    final isAssigned = userId != null && assignedTo?['id'] == userId;
    final manages = auth.can('order:assign');
    // El inspector consulta las órdenes de su facultad pero no las atiende.
    final soloConsulta = !auth.can('order:update_status');
    final canTake = open &&
        status == 'OPEN' &&
        assignedTo == null &&
        role == 'MECHANIC' &&
        auth.can('order:update_status');
    final canAdvance = puedeTrabajarOrden(
      order,
      userId: userId,
      puedeActualizar: auth.can('order:update_status'),
      administra: manages,
    );
    final canClose = open && auth.can('order:close') && (isAssigned || manages);

    final plate = (vehicle['plate'] as String?) ?? '-';
    final alias = (vehicle['alias'] as String?) ?? '';
    final model = descripcionVehiculo(vehicle);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
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
                      style:
                          const TextStyle(fontSize: 14, color: AppColors.ink2),
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
          if (_message != null) ...[
            const SizedBox(height: 12),
            Notice.text(_message!, tone: _messageTone),
          ],
          if (soloConsulta) ...[
            const SizedBox(height: 12),
            Notice.text(pasoDeLaOrden(order)),
          ],
          const SizedBox(height: 12),
          _Section(
            title: 'Motivo',
            child: Text(
              (order['description'] as String?) ?? '-',
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
          ),
          _Section(
            title: 'Seguimiento',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Dato(
                  label: 'Creada',
                  value:
                      '${fechaHora(order['createdAt'] as String?)} (${hace(order['createdAt'] as String?)})',
                ),
                Dato(
                  label: 'Mecánico',
                  value: (assignedTo?['name'] as String?) ?? 'Sin asignar',
                ),
                if (unit != null)
                  Dato(
                    label: 'Facultad',
                    value: (unit['name'] as String?) ?? '-',
                  ),
                Dato(
                  label: 'Responsable del vehículo',
                  value: (responsible?['name'] as String?) ?? 'Sin responsable',
                ),
                if (!open)
                  Dato(
                    label: 'Cerrada',
                    value:
                        'Por ${(closedBy?['name'] as String?) ?? 'usuario no registrado'}'
                        ' el ${fechaHora(order['closedAt'] as String?)}',
                  ),
              ],
            ),
          ),
          if (canTake)
            _Section(
              title: 'Orden sin asignar',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Nadie tomó esta orden todavía. Al tomarla queda a su cargo y en proceso.',
                    style: TextStyle(fontSize: 14, color: AppColors.ink2),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _working ? null : _take,
                    icon: const Icon(Icons.pan_tool_alt_outlined),
                    label: Text(_working ? 'Tomando…' : 'Tomar orden'),
                  ),
                ],
              ),
            ),
          if (open &&
              !canTake &&
              !canAdvance &&
              auth.can('order:update_status'))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Notice.text(
                assignedTo != null
                    ? 'Esta orden está asignada a ${assignedTo['name']}. Solo esa persona puede registrar el avance y cerrarla.'
                    : 'Esta orden todavía no tiene mecánico asignado.',
              ),
            ),
          _Section(
            title: 'Checklist de verificación',
            trailing: conteo.total == 0
                ? null
                : Text(
                    '${conteo.hechas}/${conteo.total}',
                    style: AppText.nums.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: conteo.hechas == conteo.total
                          ? AppColors.ok
                          : AppColors.ink2,
                    ),
                  ),
            child: ChecklistSection(
              tasks: tasks,
              editable: canAdvance,
              busy: _working,
              onToggle: _toggleTask,
              onAdd: _addTask,
            ),
          ),
          _Section(
            title: 'Repuestos usados',
            child: PartsSection(
              partsUsed: partsUsed,
              editable: canAdvance && auth.can('inventory:read'),
              busy: _working,
              onRegister: _registerPart,
            ),
          ),
          if (canAdvance)
            _Section(
              title: 'Avance del trabajo',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _noteController,
                    minLines: 2,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Nota de avance',
                      helperText:
                          'Se agrega al historial con su nombre y la fecha.',
                      hintText: 'Qué se revisó, qué se encontró, qué falta',
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _working || _noteController.text.trim().isEmpty
                        ? null
                        : _saveProgress,
                    child: const Text('Guardar avance'),
                  ),
                ],
              ),
            ),
          if (canClose)
            _Section(
              title: 'Cierre de la orden',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _closeStatus,
                    decoration: const InputDecoration(labelText: 'Resultado'),
                    items: const [
                      DropdownMenuItem(
                          value: 'COMPLETED', child: Text('Completada')),
                      DropdownMenuItem(
                          value: 'CANCELLED', child: Text('Cancelada')),
                    ],
                    onChanged: _working
                        ? null
                        : (v) =>
                            setState(() => _closeStatus = v ?? 'COMPLETED'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _resolutionController,
                    minLines: 2,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Justificación del cierre',
                      helperText:
                          'Obligatoria. Queda en el historial de la orden.',
                      hintText: _closeStatus == 'COMPLETED'
                          ? 'Qué se reparó y cómo se comprobó'
                          : 'Por qué se cancela la orden',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _closeStatus == 'COMPLETED'
                        ? 'Al cerrar, el vehículo vuelve a quedar operativo y queda registrado que usted lo cerró.'
                        : 'Cancelar no da por reparado el vehículo: su estado se toma del último escaneo.',
                    style: const TextStyle(fontSize: 13, color: AppColors.ink2),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed:
                        _working || _resolutionController.text.trim().isEmpty
                            ? null
                            : _confirmClose,
                    child: Text(_working ? 'Cerrando…' : 'Cerrar orden'),
                  ),
                ],
              ),
            ),
          _Section(
            title: 'Historial de estados',
            child: StatusHistorySection(history: history),
          ),
          _Section(
            title: 'Notas de la orden',
            child: Text(
              notes.isEmpty ? 'Todavía no hay notas en esta orden.' : notes,
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: notes.isEmpty ? AppColors.ink2 : AppColors.ink,
              ),
            ),
          ),
          _Section(
            title: 'Códigos de falla',
            child: dtcs.isEmpty
                ? const Text('El escaneo no registró códigos de falla.')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final raw in dtcs)
                        if (raw is Map<String, dynamic>) DtcRow(dtc: raw),
                    ],
                  ),
          ),
          if (auth.can('diagnosis:read'))
            _Section(
              title: 'Hipótesis técnica asistida por IA',
              child: diagnosis is Map<String, dynamic>
                  ? HipotesisView(diagnosis: diagnosis)
                  : const Text(
                      'Esta orden todavía no tiene hipótesis de IA.',
                      style: TextStyle(fontSize: 14, color: AppColors.ink2),
                    ),
            ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Panel(title: title, trailing: trailing, child: child),
    );
  }
}
