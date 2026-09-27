import 'package:flutter/material.dart';
import '../../core/api/api_client.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final ApiClient _apiClient = ApiClient();
  List<dynamic> _scans = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchScans();
  }

  Future<void> _fetchScans() async {
    setState(() {
      _loading = true;
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
          _error = 'No se pudo cargar el historial ($e)';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de Escaneos'),
        actions: [
          IconButton(
            onPressed: _fetchScans,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _fetchScans,
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _scans.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final s = _scans[index] as Map<String, dynamic>;
                    final vehicle = s['vehicle'] as Map<String, dynamic>? ?? {};
                    final dtcs = (s['dtcEntries'] as List<dynamic>?) ?? [];
                    final readiness =
                        s['readinessStatus'] as Map<String, dynamic>? ?? {};
                    final monitorsOk = readiness['monitorsCompleted'] != false;

                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${vehicle['plate'] ?? 'Vehículo'} (${dtcs.length} DTCs)',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                Chip(
                                  label: Text(
                                    '${s['severity'] ?? 'NONE'}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              'Monitores OBD: ${monitorsOk ? "Completos" : "Incompletos"} · Voltaje: ${s['batteryVoltage'] ?? "N/A"}V',
                              style: const TextStyle(fontSize: 12, color: Colors.black54),
                            ),
                            if (s['notes'] != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                '${s['notes']}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
