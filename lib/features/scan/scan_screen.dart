import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial_plus/flutter_bluetooth_serial_plus.dart';
import '../../core/api/api_client.dart';
import '../../core/bluetooth/bluetooth_service.dart';
import '../../core/elm327/elm327_service.dart';
import '../../simulator/mock_elm327.dart';
import '../monitor/live_monitor_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final ApiClient _apiClient = ApiClient();
  final BluetoothService _bluetoothService = BluetoothService();
  final Elm327Service _elm327Service = Elm327Service();
  final MockElm327 _mockElm327 = MockElm327();

  bool _useSimulator = true;
  String _selectedScenario = 'tacoma_critical';
  bool _isScanning = false;
  bool _isSending = false;
  String _statusMessage = 'Listo para iniciar escaneo preventivo OBD-II';

  List<BluetoothDevice> _pairedDevices = [];
  BluetoothDevice? _selectedDevice;

  List<dynamic> _vehicles = [];
  String? _selectedVehicleId;

  ObdScanResult? _lastResult;
  Map<String, dynamic>? _backendEvaluation;
  final TextEditingController _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      final list = await _apiClient.getVehicles();
      if (mounted) {
        // No se preselecciona ningún vehículo: elegir el primero de la lista
        // por defecto hacía fácil registrar el escaneo en el vehículo
        // equivocado. Lo decide el VIN leído o el inspector.
        setState(() => _vehicles = list);
      }
    } catch (_) {
      // Si el backend no está corriendo aún, permite escanear por VIN igualmente
    }
  }

  @override
  void dispose() {
    _bluetoothService.disconnect();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadPairedDevices() async {
    try {
      final devices = await _bluetoothService.getPairedDevices();
      if (!mounted) return;
      setState(() {
        _pairedDevices = devices;
        if (_pairedDevices.isNotEmpty && _selectedDevice == null) {
          _selectedDevice = _pairedDevices.first;
        }
        if (devices.isEmpty) {
          _statusMessage =
              'No hay adaptadores vinculados. Vincule el ELM327 en los ajustes de Bluetooth del teléfono.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pairedDevices = [];
        _statusMessage = '$e';
      });
    }
  }

  /// Vehículo registrado cuyo VIN coincide con el que reportó la ECU.
  String? _vehicleIdForVin(String? vin) {
    if (vin == null || vin.isEmpty) return null;
    for (final v in _vehicles) {
      final registrado = (v['vin'] as String?)?.trim().toUpperCase();
      if (registrado != null && registrado == vin.toUpperCase()) {
        return v['id'] as String?;
      }
    }
    return null;
  }

  bool get _canSend {
    final result = _lastResult;
    if (result == null || !result.isComplete) return false;
    return _selectedVehicleId != null || (result.vin?.isNotEmpty ?? false);
  }

  Future<void> _startScan() async {
    setState(() {
      _isScanning = true;
      _lastResult = null;
      _backendEvaluation = null;
      _statusMessage = 'Iniciando comunicación con ELM327...';
    });

    try {
      Future<String> Function(String) sender;

      if (_useSimulator) {
        _mockElm327.scenario = _selectedScenario;
        sender = _mockElm327.sendCommand;
      } else {
        if (_selectedDevice == null) {
          throw Exception('Selecciona primero un dispositivo Bluetooth ELM327 vinculado.');
        }
        setState(() {
          _statusMessage = 'Conectando por Bluetooth SPP a ${_selectedDevice!.name}...';
        });
        await _bluetoothService.connect(_selectedDevice!.address);
        // El reinicio del adaptador y la primera consulta OBD (cuando busca
        // el protocolo, "SEARCHING...") tardan bastante más que el resto.
        sender = (command) => _bluetoothService.sendCommand(
              command,
              timeout: command == 'ATZ' || command == '0100'
                  ? const Duration(seconds: 12)
                  : const Duration(seconds: 5),
            );
      }

      final result = await _elm327Service.runFullScan(
        sendCommand: sender,
        onStep: (step) {
          if (mounted) {
            setState(() => _statusMessage = step);
          }
        },
      );

      if (mounted) {
        final porVin = _vehicleIdForVin(result.vin);
        setState(() {
          _lastResult = result;
          // El VIN que reporta la ECU manda sobre la selección manual.
          if (porVin != null) _selectedVehicleId = porVin;

          if (!result.isComplete) {
            _statusMessage =
                'Lectura incompleta: no se puede registrar este escaneo.';
          } else if (porVin != null) {
            _statusMessage =
                'Lectura completada: ${result.dtcs.length} código(s). Vehículo identificado por su VIN.';
          } else if (_selectedVehicleId == null) {
            _statusMessage =
                'Lectura completada: ${result.dtcs.length} código(s). Seleccione el vehículo antes de enviar.';
          } else {
            _statusMessage =
                'Lectura completada: ${result.dtcs.length} código(s) DTC leídos.';
          }
        });
      }
    } on ObdCommunicationException catch (e) {
      if (mounted) setState(() => _statusMessage = e.message);
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Error en escaneo: $e';
        });
      }
    } finally {
      // Se libera el adaptador al terminar: dejar el canal abierto impide
      // reconectar y agota la batería del vehículo con el contacto puesto.
      if (!_useSimulator) await _bluetoothService.disconnect();
      if (mounted) {
        setState(() => _isScanning = false);
      }
    }
  }

  /// Abre el monitor en vivo (CU09) con la misma fuente elegida para el
  /// escaneo: el simulador o el adaptador Bluetooth seleccionado.
  void _openLiveMonitor() {
    if (!_useSimulator && _selectedDevice == null) {
      setState(() {
        _statusMessage =
            'Selecciona primero un dispositivo Bluetooth ELM327 vinculado.';
      });
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _useSimulator
            ? LiveMonitorScreen.simulator()
            : LiveMonitorScreen.bluetooth(
                bluetooth: _bluetoothService,
                deviceAddress: _selectedDevice!.address,
                deviceName: _selectedDevice!.name ?? 'ELM327',
              ),
      ),
    );
  }

  Future<void> _sendToBackend() async {
    if (!_canSend) return;
    setState(() {
      _isSending = true;
      _statusMessage = 'Enviando lectura al backend NestJS (/api/scans)...';
    });

    try {
      final payload = _lastResult!.toApiPayload(
        vehicleId: _selectedVehicleId,
        notes: _notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : null,
      );
      final response = await _apiClient.submitScan(payload);
      if (mounted) {
        setState(() {
          _backendEvaluation = response['evaluation'] as Map<String, dynamic>?;
          _statusMessage = '✅ Escaneo guardado y evaluado en Neon PostgreSQL';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = '❌ Error al enviar al backend: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _showApiUrlDialog() async {
    final currentUrl = await _apiClient.getBaseUrl();
    final ctrl = TextEditingController(text: currentUrl);
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Configurar URL del Backend'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '• Windows / Web: http://localhost:3000/api\n'
              '• Emulador Android: http://10.0.2.2:3000/api\n'
              '• Celular físico: http://<IP_DE_TU_PC>:3000/api',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                labelText: 'Base URL',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              await _apiClient.setBaseUrl(ctrl.text);
              if (ctx.mounted) Navigator.pop(ctx);
              _loadInitialData();
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Escanear Vehículo'),
        actions: [
          IconButton(
            tooltip: 'Configurar URL Backend',
            icon: const Icon(Icons.settings_ethernet),
            onPressed: _showApiUrlDialog,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Modo Simulador vs Bluetooth Real
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Modo Simulador (MockElm327)',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        _useSimulator
                            ? 'Simulando respuestas hexadecimales OBD-II sin hardware físico'
                            : 'Conexión Bluetooth Classic (SPP) con adaptador ELM327 real',
                      ),
                      value: _useSimulator,
                      onChanged: (val) {
                        setState(() => _useSimulator = val);
                        if (!val) _loadPairedDevices();
                      },
                    ),
                    if (_useSimulator) ...[
                      const Divider(),
                      const Text(
                        'Escenario de prueba:',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedScenario,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: MockElm327.scenarioLabels.entries
                            .map(
                              (e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(
                                  e.value,
                                  style: const TextStyle(fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedScenario = val);
                          }
                        },
                      ),
                    ] else ...[
                      const Divider(),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<BluetoothDevice>(
                              initialValue: _selectedDevice,
                              hint: const Text('Seleccionar ELM327 vinculado'),
                              isExpanded: true,
                              items: _pairedDevices
                                  .map(
                                    (d) => DropdownMenuItem(
                                      value: d,
                                      child: Text('${d.name ?? "Dispositivo"} (${d.address})'),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (d) => setState(() => _selectedDevice = d),
                            ),
                          ),
                          IconButton(
                            onPressed: _loadPairedDevices,
                            icon: const Icon(Icons.refresh),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Selección de vehículo (respaldo si la ECU no reporta VIN)
            if (_vehicles.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: DropdownButtonFormField<String>(
                    // La clave fuerza a redibujar cuando el VIN leído cambia la
                    // selección: `initialValue` solo se lee al crear el campo.
                    key: ValueKey(_selectedVehicleId),
                    initialValue: _selectedVehicleId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Vehículo objetivo (o detección automática por VIN)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('Detectar automáticamente por VIN (Modo 09)'),
                      ),
                      ..._vehicles.map(
                        (v) => DropdownMenuItem<String>(
                          value: v['id'] as String,
                          child: Text('${v['plate']} — ${v['make'] ?? ''} ${v['model'] ?? ''}'),
                        ),
                      ),
                    ],
                    onChanged: (val) => setState(() => _selectedVehicleId = val),
                  ),
                ),
              ),
            const SizedBox(height: 12),

            // Botón principal de escaneo
            FilledButton.icon(
              onPressed: _isScanning ? null : _startScan,
              icon: _isScanning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.radar),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  _isScanning ? 'Escaneando ECU...' : 'Iniciar Escaneo',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _isScanning ? null : _openLiveMonitor,
              icon: const Icon(Icons.speed),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text('Monitor en vivo'),
              ),
            ),
            const SizedBox(height: 10),

            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),

            // Resultado del escaneo
            if (_lastResult != null) ...[
              const SizedBox(height: 16),
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Resultado de Lectura OBD-II',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const Divider(),
                      _infoRow('VIN (Modo 09 PID 02):', _lastResult!.vin ?? 'No disponible'),
                      _infoRow(
                        'Voltaje Batería (ATRV):',
                        _lastResult!.batteryVoltage != null
                            ? '${_lastResult!.batteryVoltage!.toStringAsFixed(1)} V'
                            : 'N/A',
                      ),
                      _infoRow(
                        'Luz Check Engine (MIL):',
                        _lastResult!.readiness.milOn ? 'ENCENDIDA (ON)' : 'Apagada (OFF)',
                      ),
                      _infoRow(
                        'Monitores OBD (PID 0101):',
                        _lastResult!.readiness.monitorsCompleted
                            ? 'Completos'
                            : 'Incompletos (${_lastResult!.readiness.incompleteMonitors.join(", ")})',
                      ),
                      if (!_lastResult!.isComplete) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            border: Border.all(color: Colors.red.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'No se pudo leer:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red,
                                ),
                              ),
                              ..._lastResult!.readErrors.map(
                                (e) => Text('• $e', style: const TextStyle(fontSize: 13)),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Que no aparezcan códigos NO significa que el '
                                'vehículo esté sano. Revise el adaptador y '
                                'vuelva a escanear.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                      ..._lastResult!.warnings.map(
                        (w) => Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'ⓘ $w',
                            style: const TextStyle(fontSize: 12, color: Colors.black54),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Códigos DTC Detectados (${_lastResult!.dtcs.length}):',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      if (!_lastResult!.isComplete && _lastResult!.dtcs.isEmpty)
                        const Text(
                          'Sin datos: la lectura no se completó.',
                          style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
                        )
                      else if (_lastResult!.dtcs.isEmpty)
                        const Text(
                          '✅ Sin códigos de falla en Modos 03 / 07 / 0A',
                          style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600),
                        )
                      else
                        ..._lastResult!.dtcs.map(
                          (d) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.warning_amber_rounded, color: Colors.deepOrange),
                            title: Text(
                              d.code,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            trailing: Chip(
                              label: Text(d.type, style: const TextStyle(fontSize: 11)),
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _notesController,
                        decoration: const InputDecoration(
                          labelText: 'Observación del inspector (ej. cambio reciente de batería)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonalIcon(
                          onPressed: _isSending || !_canSend ? null : _sendToBackend,
                          icon: const Icon(Icons.cloud_upload),
                          label: Text(
                            _isSending
                                ? 'Enviando al Servidor...'
                                : 'Enviar Escaneo al Backend (POST /scans)',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            if (_backendEvaluation != null) ...[
              const SizedBox(height: 12),
              Card(
                color: Colors.blueGrey.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Dictamen Filtro Determinístico (Severidad: ${_backendEvaluation!['severity']})',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_backendEvaluation!['rationale'] ?? ''}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.black54, fontSize: 13)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
