import 'package:flutter/material.dart';
import '../../core/api/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui/badges.dart';
import '../../core/ui/format.dart';
import '../../core/ui/panel.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final ApiClient _apiClient = ApiClient();
  List<dynamic> _scans = [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _fetchScans();
  }

  Future<void> _fetchScans() async {
    setState(() {
      // Al actualizar con la lista a la vista no se reemplaza por el spinner.
      _loading = _scans.isEmpty;
      _error = null;
    });
    try {
      final data = await _apiClient.getScans();
      if (mounted) {
        setState(() {
          _scans = data;
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
        title: const Text('Historial de escaneos'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _fetchScans,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchScans,
              child: _buildBody(),
            ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return EmptyState.error(
        title: 'No se pudo cargar el historial',
        error: _error!,
        onRetry: _fetchScans,
      );
    }
    if (_scans.isEmpty) {
      return const EmptyState(
        title: 'Todavía no hay escaneos',
        message: 'Los escaneos que envíe desde «Escanear» aparecerán aquí.',
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: _scans.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        return _ScanCard(_scans[index] as Map<String, dynamic>);
      },
    );
  }
}

class _ScanCard extends StatelessWidget {
  const _ScanCard(this.scan);

  final Map<String, dynamic> scan;

  @override
  Widget build(BuildContext context) {
    final vehicle = scan['vehicle'] as Map<String, dynamic>? ?? const {};
    final dtcs = (scan['dtcEntries'] as List<dynamic>?) ?? const [];
    final readiness = scan['readinessStatus'] as Map<String, dynamic>? ?? const {};
    final monitorsOk = readiness['monitorsCompleted'] != false;
    final voltage = scan['batteryVoltage'];
    final text = (scan['rationale'] ?? scan['notes'])?.toString().trim() ?? '';
    final description = descripcionVehiculo(vehicle);

    final details = [
      cuentaCodigos(dtcs.length),
      monitorsOk ? 'Monitores completos' : 'Monitores incompletos',
      if (voltage is num) '${voltage.toStringAsFixed(1)} V',
    ].join(' · ');

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
                    '${vehicle['plate'] ?? 'Vehículo'}',
                    style: AppText.code.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SeverityBadge(scan['severity'] as String?),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [
                if (description.isNotEmpty) description,
                fechaHora(scan['scannedAt'] as String?),
              ].join(' · '),
              style: const TextStyle(fontSize: 13, color: AppColors.ink2),
            ),
            const SizedBox(height: 6),
            Text(
              details,
              style: AppText.nums.copyWith(fontSize: 13, color: AppColors.ink3),
            ),
            if (dtcs.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 4,
                children: [
                  for (final dtc in dtcs)
                    Text(
                      '${(dtc as Map<String, dynamic>)['code']}',
                      style: AppText.code.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                ],
              ),
            ],
            if (text.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                text,
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
