import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial_plus/flutter_bluetooth_serial_plus.dart';
import '../../core/api/api_client.dart';
import '../../core/bluetooth/bluetooth_service.dart';
import '../../core/elm327/elm327_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui/badges.dart';
import '../../core/ui/format.dart';
import '../../core/ui/notice.dart';
import '../../core/ui/panel.dart';
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

  String _statusMessage =
      'Conecte el adaptador al puerto OBD-II del vehículo, ponga el contacto e inicie el escaneo.';
  NoticeTone _statusTone = NoticeTone.info;

  List<BluetoothDevice> _pairedDevices = [];
  BluetoothDevice? _selectedDevice;

  List<dynamic> _vehicles = [];
  String? _selectedVehicleId;

  ObdScanResult? _lastResult;
  Map<String, dynamic>? _backendEvaluation;

  /// La lectura mostrada ya se guardó: no se envía dos veces.
  bool _sent = false;

  /// El servidor está generando la hipótesis de IA del escaneo enviado.
  bool _aiRequested = false;

  final TextEditingController _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadVehicles();
  }

  Future<void> _loadVehicles() async {
    try {
      final list = await _apiClient.getVehicles();
      if (mounted) {
        // No se preselecciona ningún vehículo: elegir el primero de la lista
        // por defecto hacía fácil registrar el escaneo en el vehículo
        // equivocado. Lo decide el VIN leído o el inspector.
        setState(() => _vehicles = list);
      }
    } catch (_) {
      // Sin conexión se puede leer igual: el vehículo se identifica por su VIN.
    }
  }

  @override
  void dispose() {
    _bluetoothService.disconnect();
    _notesController.dispose();
    super.dispose();
  }

  void _setStatus(String message, [NoticeTone tone = NoticeTone.info]) {
    if (!mounted) return;
    setState(() {
      _statusMessage = message;
      _statusTone = tone;
    });
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
          _statusTone = NoticeTone.warning;
          _statusMessage =
              'No hay adaptadores vinculados. Vincule el ELM327 en los ajustes de Bluetooth del teléfono.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pairedDevices = [];
        _statusTone = NoticeTone.error;
        _statusMessage = e is BluetoothException
            ? e.message
            : 'No se pudo consultar el Bluetooth del teléfono.';
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
    if (result == null || !result.isComplete || _sent) return false;
    return _selectedVehicleId != null || (result.vin?.isNotEmpty ?? false);
  }

  Future<void> _startScan() async {
    if (!_useSimulator && _selectedDevice == null) {
      _setStatus(
        'Seleccione primero el adaptador ELM327 vinculado.',
        NoticeTone.warning,
      );
      return;
    }

    // Por si el listado no cargó al abrir (sin conexión, servidor arrancando).
    if (_vehicles.isEmpty) _loadVehicles();

    setState(() {
      _isScanning = true;
      _lastResult = null;
      _backendEvaluation = null;
      _sent = false;
      _aiRequested = false;
      _statusTone = NoticeTone.info;
      _statusMessage = 'Iniciando la comunicación con el adaptador…';
    });

    try {
      Future<String> Function(String) sender;

      if (_useSimulator) {
        _mockElm327.scenario = _selectedScenario;
        sender = _mockElm327.sendCommand;
      } else {
        _setStatus(
          'Conectando por Bluetooth con ${_selectedDevice!.name ?? 'el adaptador'}…',
        );
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
        onStep: _setStatus,
      );

      if (mounted) {
        final porVin = _vehicleIdForVin(result.vin);
        final codigos = cuentaCodigos(result.dtcs.length);
        setState(() {
          _lastResult = result;
          // El VIN que reporta la ECU manda sobre la selección manual.
          if (porVin != null) _selectedVehicleId = porVin;

          if (!result.isComplete) {
            _statusTone = NoticeTone.error;
            _statusMessage =
                'Lectura incompleta: no se puede registrar este escaneo.';
          } else if (porVin != null) {
            _statusTone = NoticeTone.info;
            _statusMessage =
                'Lectura completa: $codigos. Vehículo identificado por su VIN.';
          } else if (_selectedVehicleId == null &&
              (result.vin?.isEmpty ?? true)) {
            _statusTone = NoticeTone.warning;
            _statusMessage =
                'Lectura completa: $codigos. Seleccione el vehículo antes de enviar.';
          } else {
            _statusTone = NoticeTone.info;
            _statusMessage = 'Lectura completa: $codigos.';
          }
        });
      }
    } on ObdCommunicationException catch (e) {
      _setStatus(e.message, NoticeTone.error);
    } on BluetoothException catch (e) {
      _setStatus(e.message, NoticeTone.error);
    } catch (_) {
      _setStatus(
        'No se pudo completar el escaneo. Revise el adaptador y vuelva a intentar.',
        NoticeTone.error,
      );
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
      _setStatus(
        'Seleccione primero el adaptador ELM327 vinculado.',
        NoticeTone.warning,
      );
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

  Future<void> _sendScan() async {
    if (!_canSend) return;
    setState(() {
      _isSending = true;
      _statusTone = NoticeTone.info;
      _statusMessage = 'Enviando el escaneo al servidor…';
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
        final diagnosis = response['diagnosis'] as Map<String, dynamic>?;
        setState(() {
          _backendEvaluation = response['evaluation'] as Map<String, dynamic>?;
          _aiRequested = diagnosis?['requested'] == true;
          _sent = true;
          _statusTone = NoticeTone.success;
          _statusMessage = response['workOrderId'] != null
              ? 'Escaneo guardado. Se generó una orden de trabajo.'
              : 'Escaneo guardado.';
        });
      }
    } catch (e) {
      // La lectura queda en pantalla: se puede reintentar el envío.
      _setStatus(
        mensajeDeError(e, 'No se pudo enviar el escaneo. Intente de nuevo.'),
        NoticeTone.error,
      );
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _lastResult;

    return Scaffold(
      appBar: AppBar(title: const Text('Escanear vehículo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSource(),
          const SizedBox(height: 12),

          // Selección de vehículo (respaldo si la ECU no reporta VIN)
          if (_vehicles.isNotEmpty) ...[
            _buildVehicle(),
            const SizedBox(height: 12),
          ],

          FilledButton.icon(
            onPressed: _isScanning || _isSending ? null : _startScan,
            icon: _isScanning
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.sensors),
            label: Text(_isScanning ? 'Leyendo el vehículo…' : 'Iniciar escaneo'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _isScanning ? null : _openLiveMonitor,
            icon: const Icon(Icons.speed),
            label: const Text('Monitor en vivo'),
          ),
          const SizedBox(height: 12),

          Notice.text(_statusMessage, tone: _statusTone),

          if (result != null) ...[
            const SizedBox(height: 12),
            _buildResult(result),
          ],

          if (_backendEvaluation != null) ...[
            const SizedBox(height: 12),
            Panel(
              title: 'Dictamen',
              trailing: SeverityBadge(_backendEvaluation!['severity'] as String?),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${_backendEvaluation!['rationale'] ?? ''}',
                    style: const TextStyle(fontSize: 14, height: 1.4),
                  ),
                  if (_aiRequested) ...[
                    const SizedBox(height: 12),
                    Notice.text(
                      'La hipótesis de la inteligencia artificial se está '
                      'generando. Podrá verla en la plataforma web, sujeta a '
                      'validación humana.',
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSource() {
    return Panel(
      title: 'Origen de la lectura',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Usar el simulador',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              _useSimulator
                  ? 'Lecturas de ejemplo, sin adaptador ni vehículo.'
                  : 'Adaptador ELM327 conectado por Bluetooth.',
              style: const TextStyle(fontSize: 13, color: AppColors.ink2),
            ),
            value: _useSimulator,
            onChanged: _isScanning
                ? null
                : (val) {
                    setState(() => _useSimulator = val);
                    if (!val) _loadPairedDevices();
                  },
          ),
          const SizedBox(height: 8),
          if (_useSimulator)
            DropdownButtonFormField<String>(
              initialValue: _selectedScenario,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Escenario de prueba',
              ),
              items: MockElm327.scenarioLabels.entries
                  .map(
                    (e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(
                        e.value,
                        style: const TextStyle(fontSize: 14),
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
            )
          else
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<BluetoothDevice>(
                    // `initialValue` solo se lee al crear el campo.
                    key: ValueKey(_selectedDevice?.address),
                    initialValue: _selectedDevice,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Adaptador vinculado',
                    ),
                    items: _pairedDevices
                        .map(
                          (d) => DropdownMenuItem(
                            value: d,
                            child: Text(
                              '${d.name ?? "Dispositivo"} (${d.address})',
                              style: const TextStyle(fontSize: 14),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (d) => setState(() => _selectedDevice = d),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Actualizar la lista de adaptadores',
                  onPressed: _loadPairedDevices,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildVehicle() {
    return Panel(
      title: 'Vehículo',
      child: DropdownButtonFormField<String>(
        // La clave fuerza a redibujar cuando el VIN leído cambia la
        // selección: `initialValue` solo se lee al crear el campo.
        key: ValueKey(_selectedVehicleId),
        initialValue: _selectedVehicleId,
        isExpanded: true,
        decoration: const InputDecoration(
          helperText: 'Si el vehículo informa su VIN, se identifica solo.',
        ),
        items: [
          const DropdownMenuItem<String>(
            value: null,
            child: Text('Identificar por el VIN leído'),
          ),
          ..._vehicles.map((v) {
            final vehicle = v as Map<String, dynamic>;
            final description = descripcionVehiculo(vehicle);
            return DropdownMenuItem<String>(
              value: vehicle['id'] as String,
              child: Text(
                description.isEmpty
                    ? '${vehicle['plate']}'
                    : '${vehicle['plate']} · $description',
                overflow: TextOverflow.ellipsis,
              ),
            );
          }),
        ],
        onChanged:
            _sent ? null : (val) => setState(() => _selectedVehicleId = val),
      ),
    );
  }

  Widget _buildResult(ObdScanResult result) {
    return Panel(
      title: 'Resultado de la lectura',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Dato(
            label: 'VIN',
            value: result.vin ?? 'No informado',
            code: result.vin != null,
          ),
          Dato(
            label: 'Voltaje de la batería',
            value: result.batteryVoltage != null
                ? '${result.batteryVoltage!.toStringAsFixed(1)} V'
                : 'No disponible',
          ),
          Dato(
            label: 'Luz de falla del motor',
            value: result.readiness.milOn ? 'Encendida' : 'Apagada',
          ),
          Dato(
            label: 'Monitores OBD',
            value: result.readiness.monitorsCompleted
                ? 'Completos'
                : 'Incompletos (${result.readiness.incompleteMonitors.join(", ")})',
          ),
          if (!result.isComplete) ...[
            const SizedBox(height: 12),
            Notice(
              tone: NoticeTone.error,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'No se pudo leer:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  ...result.readErrors.map((e) => Text('• $e')),
                  const SizedBox(height: 6),
                  const Text(
                    'Que no aparezcan códigos no significa que el vehículo '
                    'esté sano. Revise el adaptador y vuelva a escanear.',
                  ),
                ],
              ),
            ),
          ],
          ...result.warnings.map(
            (w) => Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Notice.text(w),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Códigos de falla (${result.dtcs.length})',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (!result.isComplete && result.dtcs.isEmpty)
            const Text(
              'Sin datos: la lectura no se completó.',
              style: TextStyle(fontSize: 14, color: AppColors.ink2),
            )
          else if (result.dtcs.isEmpty)
            const Row(
              children: [
                Icon(Icons.check_circle_outline, size: 18, color: AppColors.ok),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'El vehículo no registra códigos de falla.',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ],
            )
          else
            ...result.dtcs.map(
              (d) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        d.code,
                        style: AppText.code.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    DtcTypeBadge(d.type),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          TextField(
            controller: _notesController,
            enabled: !_sent,
            maxLines: null,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Observación (opcional)',
              helperText: 'Por ejemplo: se cambió la batería hace poco.',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _isSending || !_canSend ? null : _sendScan,
            icon: Icon(_sent ? Icons.check : Icons.cloud_upload_outlined),
            label: Text(
              _sent
                  ? 'Escaneo enviado'
                  : _isSending
                      ? 'Enviando…'
                      : 'Enviar escaneo',
            ),
          ),
        ],
      ),
    );
  }
}
