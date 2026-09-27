import 'package:flutter/material.dart';
import '../../core/api/api_client.dart';

class VehiclesScreen extends StatefulWidget {
  const VehiclesScreen({super.key});

  @override
  State<VehiclesScreen> createState() => _VehiclesScreenState();
}

class _VehiclesScreenState extends State<VehiclesScreen> {
  final ApiClient _apiClient = ApiClient();
  List<dynamic> _vehicles = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchVehicles();
  }

  Future<void> _fetchVehicles() async {
    setState(() {
      _loading = true;
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
          _error = 'No se pudo conectar al backend ($e)';
          _loading = false;
        });
      }
    }
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'CRITICAL':
        return Colors.red;
      case 'ALERT':
        return Colors.orange;
      default:
        return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vehículos UAGRM'),
        actions: [
          IconButton(
            onPressed: _fetchVehicles,
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
                          onPressed: _fetchVehicles,
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _vehicles.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final v = _vehicles[index] as Map<String, dynamic>;
                    final status = v['status'] as String? ?? 'OK';
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _statusColor(status).withValues(alpha: 0.15),
                          child: Icon(Icons.directions_car, color: _statusColor(status)),
                        ),
                        title: Text(
                          '${v['plate']} — ${v['make'] ?? ''} ${v['model'] ?? ''}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${v['alias'] ?? 'Sin alias'}\nVIN: ${v['vin'] ?? 'N/A'}',
                        ),
                        isThreeLine: true,
                        trailing: Chip(
                          label: Text(
                            status,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: _statusColor(status),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
