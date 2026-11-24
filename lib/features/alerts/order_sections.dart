import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui/format.dart';
import '../../core/ui/notice.dart';
import '../orders/order_rules.dart';

/// Checklist de verificación de la orden. Al principio lo siembra la IA con
/// sus pasos de verificación; el mecánico asignado marca lo que va haciendo y
/// puede agregar tareas.
class ChecklistSection extends StatefulWidget {
  const ChecklistSection({
    super.key,
    required this.tasks,
    required this.editable,
    required this.busy,
    required this.onToggle,
    required this.onAdd,
  });

  final List<dynamic> tasks;

  /// Solo el mecánico asignado (o el administrador) con la orden abierta.
  final bool editable;
  final bool busy;
  final void Function(String taskId, bool completed) onToggle;
  final Future<bool> Function(String description) onAdd;

  @override
  State<ChecklistSection> createState() => _ChecklistSectionState();
}

class _ChecklistSectionState extends State<ChecklistSection> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final ok = await widget.onAdd(_controller.text);
    if (ok && mounted) setState(_controller.clear);
  }

  @override
  Widget build(BuildContext context) {
    final tareas = widget.tasks.whereType<Map<String, dynamic>>().toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (tareas.isEmpty)
          Text(
            widget.editable
                ? 'Todavía no hay tareas. Llegan solas con la hipótesis de IA, o puede agregarlas abajo.'
                : 'Todavía no hay tareas de verificación.',
            style: const TextStyle(fontSize: 14, color: AppColors.ink2),
          ),
        for (final t in tareas)
          CheckboxListTile(
            key: ValueKey('tarea-${t['id']}'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            value: t['completed'] == true,
            onChanged: widget.editable && !widget.busy
                ? (v) => widget.onToggle(t['id'] as String, v ?? false)
                : null,
            title: Text(
              '${t['description'] ?? ''}',
              style: TextStyle(
                fontSize: 14,
                height: 1.35,
                color: t['completed'] == true ? AppColors.ink3 : AppColors.ink,
                decoration: t['completed'] == true
                    ? TextDecoration.lineThrough
                    : null,
              ),
            ),
            subtitle: t['completed'] == true && t['completedAt'] != null
                ? Text('Hecha ${hace(t['completedAt'] as String?)}',
                    style: const TextStyle(fontSize: 12))
                : null,
          ),
        if (widget.editable) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Nueva tarea',
                    hintText: 'Ej.: Revisar conector del sensor',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Agregar tarea',
                onPressed: widget.busy || _controller.text.trim().isEmpty
                    ? null
                    : _add,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Repuestos usados en la orden y botón para registrar uno.
class PartsSection extends StatelessWidget {
  const PartsSection({
    super.key,
    required this.partsUsed,
    required this.editable,
    required this.busy,
    required this.onRegister,
  });

  final List<dynamic> partsUsed;
  final bool editable;
  final bool busy;
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    final usados = partsUsed.whereType<Map<String, dynamic>>().toList();
    final total = costoRepuestos(usados);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (usados.isEmpty)
          const Text(
            'Todavía no se registraron repuestos.',
            style: TextStyle(fontSize: 14, color: AppColors.ink2),
          ),
        for (final u in usados)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${(u['sparePart'] as Map<String, dynamic>?)?['name'] ?? 'Repuesto'}',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                      Text(
                        [
                          '${(u['sparePart'] as Map<String, dynamic>?)?['sku'] ?? ''}',
                          if ((u['notes'] as String?)?.isNotEmpty ?? false)
                            '${u['notes']}',
                        ].where((t) => t.isNotEmpty).join(' · '),
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.ink3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${u['quantity']} × Bs ${_bs(u['unitCost'])}',
                  style: AppText.nums.copyWith(fontSize: 13),
                ),
              ],
            ),
          ),
        if (usados.isNotEmpty) ...[
          const Divider(),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Total: Bs ${_bs(total)}',
              style: AppText.nums
                  .copyWith(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
        if (editable) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: busy ? null : onRegister,
            icon: const Icon(Icons.inventory_2_outlined),
            label: const Text('Registrar repuesto'),
          ),
        ],
      ],
    );
  }
}

String _bs(Object? valor) => ((valor as num?) ?? 0).toStringAsFixed(2);

/// Lo que devuelve la hoja de registro de repuesto.
typedef RepuestoElegido = ({String sparePartId, int quantity, String notes});

/// Hoja inferior para elegir un repuesto del inventario y la cantidad.
Future<RepuestoElegido?> elegirRepuesto(
  BuildContext context,
  ApiClient api,
) {
  return showModalBottomSheet<RepuestoElegido>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _RepuestoSheet(api: api),
  );
}

class _RepuestoSheet extends StatefulWidget {
  const _RepuestoSheet({required this.api});

  final ApiClient api;

  @override
  State<_RepuestoSheet> createState() => _RepuestoSheetState();
}

class _RepuestoSheetState extends State<_RepuestoSheet> {
  List<Map<String, dynamic>> _repuestos = [];
  Object? _error;
  bool _loading = true;
  String? _elegido;
  int _cantidad = 1;
  final _notas = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _notas.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.api.getSpareParts();
      if (!mounted) return;
      setState(() {
        _repuestos = repuestosDisponibles(data);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Map<String, dynamic>? get _repuesto {
    for (final r in _repuestos) {
      if (r['id'] == _elegido) return r;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final stock = (_repuesto?['stock'] as num?)?.toInt() ?? 0;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Registrar repuesto',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          const Text(
            'Se descuenta del inventario del taller.',
            style: TextStyle(fontSize: 13, color: AppColors.ink2),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Notice.text(
              mensajeDeError(_error!, 'No se pudo cargar el inventario.'),
              tone: NoticeTone.error,
            )
          else if (_repuestos.isEmpty)
            Notice.text(
              'No hay repuestos con stock en el inventario. El administrador los carga desde la web.',
              tone: NoticeTone.warning,
            )
          else ...[
            DropdownButtonFormField<String>(
              initialValue: _elegido,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Repuesto'),
              items: [
                for (final r in _repuestos)
                  DropdownMenuItem(
                    value: r['id'] as String,
                    child: Text(
                      '${r['name']} (stock ${r['stock']})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) => setState(() {
                _elegido = v;
                _cantidad = 1;
              }),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(
                  child: Text('Cantidad', style: TextStyle(fontSize: 14)),
                ),
                IconButton(
                  tooltip: 'Menos',
                  onPressed:
                      _cantidad > 1 ? () => setState(() => _cantidad--) : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text('$_cantidad', style: AppText.nums.copyWith(fontSize: 16)),
                IconButton(
                  tooltip: 'Más',
                  onPressed: _repuesto != null && _cantidad < stock
                      ? () => setState(() => _cantidad++)
                      : null,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            TextField(
              controller: _notas,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nota (opcional)',
                hintText: 'Ej.: Reemplazo de bujía del cilindro 1',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _elegido == null
                  ? null
                  : () => Navigator.of(context).pop((
                        sparePartId: _elegido!,
                        quantity: _cantidad,
                        notes: _notas.text,
                      )),
              child: const Text('Registrar'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Historial de cambios de estado de la orden: quién la movió y por qué.
class StatusHistorySection extends StatelessWidget {
  const StatusHistorySection({super.key, required this.history});

  final List<dynamic> history;

  @override
  Widget build(BuildContext context) {
    final cambios = history.whereType<Map<String, dynamic>>().toList();
    if (cambios.isEmpty) {
      return const Text(
        'Sin cambios de estado registrados.',
        style: TextStyle(fontSize: 14, color: AppColors.ink2),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < cambios.length; i++)
          _HistoryItem(cambio: cambios[i], last: i == cambios.length - 1),
      ],
    );
  }
}

class _HistoryItem extends StatelessWidget {
  const _HistoryItem({required this.cambio, required this.last});

  final Map<String, dynamic> cambio;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final quien =
        (cambio['changedBy'] as Map<String, dynamic>?)?['name'] as String?;
    final desde = cambio['fromStatus'] as String?;
    final hasta = cambio['toStatus'] as String?;
    final motivo = (cambio['reason'] as String?)?.trim() ?? '';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 20,
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: AppColors.navy,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!last)
                  const Expanded(
                    child: VerticalDivider(width: 2, thickness: 2),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    desde == null
                        ? 'Creada como ${nombreEstado(hasta).toLowerCase()}'
                        : '${nombreEstado(desde)} → ${nombreEstado(hasta)}',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  Text(
                    [
                      fechaHora(cambio['changedAt'] as String?),
                      quien ?? 'Sistema',
                    ].join(' · '),
                    style:
                        const TextStyle(fontSize: 12, color: AppColors.ink3),
                  ),
                  if (motivo.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(motivo,
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.ink2, height: 1.35)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
