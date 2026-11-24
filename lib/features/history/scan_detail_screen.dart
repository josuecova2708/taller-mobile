import 'dart:async';

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
import '../alerts/work_order_detail_screen.dart';

/// Severidades a partir de las cuales el backend pide hipótesis a la IA.
const severidadesConHipotesis = ['MEDIUM', 'HIGH', 'CRITICAL'];

/// Detalle de un escaneo: dictamen, códigos e hipótesis de IA.
///
/// Se abre al tocar un escaneo del historial y desde el aviso al responsable
/// del vehículo. Si la hipótesis se está generando, vuelve a consultar sola.
class ScanDetailScreen extends StatefulWidget {
  const ScanDetailScreen({super.key, required this.scanId, this.apiClient});

  final String scanId;
  final ApiClient? apiClient;

  @override
  State<ScanDetailScreen> createState() => _ScanDetailScreenState();
}

class _ScanDetailScreenState extends State<ScanDetailScreen> {
  static const _intervalo = Duration(seconds: 4);
  static const _maxSondeos = 15;

  late final ApiClient _api = widget.apiClient ?? ApiClient();
  Map<String, dynamic>? _scan;
  Object? _error;
  bool _loading = true;
  Timer? _timer;
  int _sondeos = 0;

  final _motivoController = TextEditingController();
  bool _enviando = false;
  String? _aviso;
  NoticeTone _avisoTono = NoticeTone.success;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _motivoController.dispose();
    super.dispose();
  }

  /// El inspector deriva al taller un escaneo que no abrió orden sola
  /// (severidad leve), con su observación para el mecánico.
  Future<void> _enviarAlTaller() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _enviando = true;
      _aviso = null;
    });
    try {
      await _api.createWorkOrder(
        widget.scanId,
        description: _motivoController.text,
      );
      if (!mounted) return;
      _motivoController.clear();
      setState(() {
        _aviso = 'Orden enviada al taller. Los mecánicos ya la ven en su lista.';
        _avisoTono = NoticeTone.success;
      });
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _aviso = mensajeDeError(e, 'No se pudo crear la orden de trabajo.');
        _avisoTono = NoticeTone.error;
      });
      // Si ya tenía orden, se recarga para mostrarla.
      if (e is ApiException && e.statusCode == 409) await _load();
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _abrirOrden(String id) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WorkOrderDetailScreen(workOrderId: id),
      ),
    );
  }

  bool _generando(Map<String, dynamic> scan) =>
      scan['diagnosis'] == null &&
      scan['aiProcessed'] != true &&
      severidadesConHipotesis.contains(scan['severity']);

  Future<void> _load() async {
    _timer?.cancel();
    setState(() {
      _loading = _scan == null;
      _error = null;
    });
    try {
      final scan = await _api.getScan(widget.scanId);
      if (!mounted) return;
      setState(() {
        _scan = scan;
        _loading = false;
      });
      // La hipótesis llega en segundo plano: se vuelve a consultar un rato.
      if (_generando(scan) && _sondeos < _maxSondeos) {
        _timer = Timer(_intervalo, () {
          _sondeos++;
          if (mounted) _load();
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Escaneo'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: () {
              _sondeos = 0;
              _load();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _scan == null) {
      return EmptyState.error(
        title: 'No se pudo cargar el escaneo',
        error: _error!,
        onRetry: _load,
      );
    }

    final scan = _scan!;
    final vehicle = (scan['vehicle'] as Map<String, dynamic>?) ?? const {};
    final dtcs = (scan['dtcEntries'] as List<dynamic>?) ?? const [];
    final readiness =
        (scan['readinessStatus'] as Map<String, dynamic>?) ?? const {};
    final monitorsOk = readiness['monitorsCompleted'] != false;
    final incompletos =
        (readiness['incompleteMonitors'] as List<dynamic>?) ?? const [];
    final dictamen =
        (scan['rationale'] ?? scan['notes'])?.toString().trim() ?? '';
    final scannedBy = scan['scannedBy'] as Map<String, dynamic>?;
    final description = descripcionVehiculo(vehicle);
    final auth = context.watch<AuthService>();
    final verHipotesis = auth.can('diagnosis:read');
    final workOrder = scan['workOrder'] as Map<String, dynamic>?;

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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${vehicle['plate'] ?? '-'}',
                          style: AppText.code.copyWith(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      SeverityBadge(scan['severity'] as String?),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (description.isNotEmpty) description,
                      fechaHora(scan['scannedAt'] as String?),
                      if (scannedBy?['name'] != null)
                        'por ${scannedBy!['name']}',
                    ].join(' · '),
                    style: const TextStyle(fontSize: 13, color: AppColors.ink2),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (dictamen.isNotEmpty) ...[
            Panel(
              title: 'Evaluación automática',
              child: Text(dictamen,
                  style: const TextStyle(fontSize: 14, height: 1.4)),
            ),
            const SizedBox(height: 12),
          ],
          if (_aviso != null) ...[
            Notice.text(_aviso!, tone: _avisoTono),
            const SizedBox(height: 12),
          ],
          _buildOrden(auth, workOrder),
          const SizedBox(height: 12),
          Panel(
            title: 'Códigos de falla (${dtcs.length})',
            child: dtcs.isEmpty
                ? const Text('El vehículo no reportó ningún código de falla.')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final raw in dtcs)
                        if (raw is Map<String, dynamic>) DtcRow(dtc: raw),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          Panel(
            title: 'Monitores de preparación',
            child: Text(
              monitorsOk
                  ? 'Completos: la lectura es concluyente.'
                  : 'Incompletos: ${incompletos.isEmpty ? 'no se identificó cuáles' : incompletos.join(', ')}. '
                      'Vuelva a escanear después de un ciclo de conducción completo.',
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
          ),
          if (verHipotesis) ...[
            const SizedBox(height: 12),
            Panel(
              title: 'Hipótesis técnica asistida por IA',
              child: _buildHipotesis(scan),
            ),
          ],
        ],
      ),
    );
  }

  /// La orden de trabajo del escaneo, o la opción de enviarlo al taller.
  Widget _buildOrden(AuthService auth, Map<String, dynamic>? workOrder) {
    if (workOrder != null) {
      final status = workOrder['status'] as String?;
      return Panel(
        title: 'Orden de trabajo',
        trailing: OrderStatusBadge(status),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              status == 'COMPLETED'
                  ? 'La orden de este escaneo se completó y el vehículo volvió a quedar operativo.'
                  : status == 'CANCELLED'
                      ? 'La orden de este escaneo se canceló.'
                      : 'Este escaneo tiene una orden abierta en el taller. El vehículo '
                          'sigue en evaluación hasta que se cierre como completada.',
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
            if (auth.can('order:read')) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => _abrirOrden(workOrder['id'] as String),
                child: const Text('Ver orden'),
              ),
            ],
          ],
        ),
      );
    }

    if (!auth.can('order:create')) {
      return const Panel(
        title: 'Orden de trabajo',
        child: Text(
          'Este escaneo no abrió una orden de trabajo.',
          style: TextStyle(fontSize: 14, color: AppColors.ink2),
        ),
      );
    }

    return Panel(
      title: 'Enviar al taller',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Este escaneo no abrió una orden sola. Si en terreno nota algo que '
            'requiere revisión, puede derivar el vehículo al mecánico.',
            style: TextStyle(fontSize: 14, color: AppColors.ink2, height: 1.4),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _motivoController,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Observación para el mecánico',
              hintText: 'Ej.: Vibración en ralentí aunque el código es pendiente',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _enviando ? null : _enviarAlTaller,
            icon: const Icon(Icons.build_outlined),
            label: Text(_enviando ? 'Enviando…' : 'Enviar al taller'),
          ),
        ],
      ),
    );
  }

  Widget _buildHipotesis(Map<String, dynamic> scan) {
    final diagnosis = scan['diagnosis'];
    if (diagnosis is Map<String, dynamic>) {
      return HipotesisView(diagnosis: diagnosis);
    }
    if (!severidadesConHipotesis.contains(scan['severity'])) {
      return const Text(
        'Este escaneo no necesitó hipótesis: la IA se consulta desde la severidad media.',
        style: TextStyle(fontSize: 14, color: AppColors.ink2),
      );
    }
    if (_generando(scan) && _sondeos < _maxSondeos) {
      return const Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Generando la hipótesis. Aparece sola en unos segundos.',
              style: TextStyle(fontSize: 14, color: AppColors.ink2),
            ),
          ),
        ],
      );
    }
    return const Text(
      'La hipótesis todavía no está disponible. Actualice en un momento.',
      style: TextStyle(fontSize: 14, color: AppColors.ink2),
    );
  }
}

/// Un código de falla con su tipo y descripción.
class DtcRow extends StatelessWidget {
  const DtcRow({super.key, required this.dtc});

  final Map<String, dynamic> dtc;

  @override
  Widget build(BuildContext context) {
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
              DtcTypeBadge(dtc['type'] as String?),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            (dtc['description'] as String?) ?? 'Sin descripción',
            style: const TextStyle(fontSize: 13, color: AppColors.ink2),
          ),
        ],
      ),
    );
  }
}
