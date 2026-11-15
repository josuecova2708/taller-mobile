import 'package:flutter/material.dart';

import '../../core/bluetooth/bluetooth_service.dart';
import '../../core/elm327/elm327_service.dart';
import '../../core/elm327/live_monitor.dart';
import '../../simulator/mock_elm327.dart';

enum _MonitorState { connecting, running, stopped, failed }

/// Monitor en vivo (CU09): revoluciones, velocidad, temperatura del
/// refrigerante, posición del acelerador y voltaje, leídos del adaptador
/// mientras la pantalla está abierta.
///
/// Los valores se muestran solo en el teléfono: no se guardan ni se envían.
class LiveMonitorScreen extends StatefulWidget {
  /// Monitor sobre el simulador, con selector de escenario.
  LiveMonitorScreen.simulator({super.key, MockElm327? simulator})
      : simulator = simulator ?? MockElm327(),
        bluetooth = null,
        deviceAddress = null,
        deviceName = null;

  /// Monitor sobre un adaptador ELM327 real ya vinculado.
  const LiveMonitorScreen.bluetooth({
    super.key,
    required BluetoothService this.bluetooth,
    required String this.deviceAddress,
    required String this.deviceName,
  }) : simulator = null;

  final MockElm327? simulator;
  final BluetoothService? bluetooth;
  final String? deviceAddress;
  final String? deviceName;

  @override
  State<LiveMonitorScreen> createState() => _LiveMonitorScreenState();
}

class _LiveMonitorScreenState extends State<LiveMonitorScreen> {
  _MonitorState _state = _MonitorState.connecting;
  String? _error;
  LiveSnapshot? _snapshot;
  String _scenario = MockElm327.monitorScenarioLabels.keys.first;

  /// `false` pide al ciclo de lectura que termine.
  bool _running = false;

  /// Ciclo de lectura en curso; se espera antes de iniciar otro para que el
  /// cierre del anterior no corte la conexión del nuevo.
  Future<void>? _loop;

  bool get _usesSimulator => widget.simulator != null;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    // El ciclo termina solo y libera el adaptador en su `finally`.
    _running = false;
    super.dispose();
  }

  Future<void> _start() async {
    _running = false;
    await _loop;
    if (!mounted) return;

    _running = true;
    setState(() {
      _state = _MonitorState.connecting;
      _error = null;
      _snapshot = null;
    });
    _loop = _run();
  }

  void _stop() {
    _running = false;
    setState(() => _state = _MonitorState.stopped);
  }

  Future<void> _changeScenario(String scenario) async {
    setState(() => _scenario = scenario);
    await _start();
  }

  Future<String> _send(String command) {
    final simulator = widget.simulator;
    if (simulator != null) return simulator.sendCommand(command);

    // El reinicio del adaptador y la primera consulta (cuando busca el
    // protocolo) tardan bastante más; el resto debe fallar rápido para
    // notar pronto una conexión perdida.
    return widget.bluetooth!.sendCommand(
      command,
      timeout: command == 'ATZ' || command == '0100'
          ? const Duration(seconds: 12)
          : const Duration(seconds: 2),
    );
  }

  Future<void> _run() async {
    try {
      final simulator = widget.simulator;
      if (simulator != null) {
        simulator
          ..scenario = _scenario
          ..live = true;
      } else {
        await widget.bluetooth!.connect(widget.deviceAddress!);
      }

      final monitor = LiveMonitor(sendCommand: _send);
      await monitor.start();
      if (!mounted || !_running) return;
      setState(() => _state = _MonitorState.running);

      while (mounted && _running) {
        final snapshot = await monitor.poll();
        if (!mounted || !_running) break;
        setState(() => _snapshot = snapshot);
      }
    } on ObdCommunicationException catch (e) {
      _fail(e.message);
    } on ObdConnectionLostException catch (e) {
      _fail(e.message);
    } on BluetoothException catch (e) {
      _fail(e.message);
    } catch (_) {
      _fail('No se pudo leer el adaptador OBD-II.');
    } finally {
      // Se libera el adaptador: dejar el canal abierto impide reconectar.
      widget.simulator?.live = false;
      await widget.bluetooth?.disconnect();
    }
  }

  void _fail(String message) {
    if (!mounted || !_running) return;
    _running = false;
    setState(() {
      _state = _MonitorState.failed;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final active = _state == _MonitorState.connecting ||
        _state == _MonitorState.running;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Monitor en vivo'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_usesSimulator) ...[
            DropdownButtonFormField<String>(
              initialValue: _scenario,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Escenario del simulador',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: MockElm327.monitorScenarioLabels.entries
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
              onChanged: (value) {
                if (value != null && value != _scenario) _changeScenario(value);
              },
            ),
            const SizedBox(height: 12),
          ],
          _StatusBanner(
            state: _state,
            error: _error,
            source: _usesSimulator ? 'simulador' : widget.deviceName!,
          ),
          const SizedBox(height: 12),
          _ParamTile(
            label: 'Revoluciones del motor',
            unit: 'rpm',
            reading: _snapshot?[LiveParam.rpm],
            max: 7000,
            decimals: 0,
            large: true,
          ),
          Row(
            children: [
              Expanded(
                child: _ParamTile(
                  label: 'Velocidad',
                  unit: 'km/h',
                  reading: _snapshot?[LiveParam.speed],
                  max: 160,
                  decimals: 0,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ParamTile(
                  label: 'Acelerador',
                  unit: '%',
                  reading: _snapshot?[LiveParam.throttle],
                  max: 100,
                  decimals: 0,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: _ParamTile(
                  label: 'Temperatura del refrigerante',
                  unit: '°C',
                  reading: _snapshot?[LiveParam.coolant],
                  max: 130,
                  decimals: 0,
                  // Por encima de 105 °C el motor está recalentando.
                  warnFrom: 105,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ParamTile(
                  label: 'Voltaje',
                  unit: 'V',
                  reading: _snapshot?[LiveParam.voltage],
                  decimals: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (active)
            FilledButton.icon(
              onPressed: _state == _MonitorState.running ? _stop : null,
              icon: const Icon(Icons.stop),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Detener'),
              ),
            )
          else
            FilledButton.icon(
              onPressed: _start,
              icon: const Icon(Icons.play_arrow),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _state == _MonitorState.failed ? 'Reintentar' : 'Reanudar',
                ),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            'Estos valores se muestran solo en este teléfono. No se guardan '
            'ni forman parte del escaneo.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.state,
    required this.error,
    required this.source,
  });

  final _MonitorState state;
  final String? error;
  final String source;

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final Color color;
    final String text;

    switch (state) {
      case _MonitorState.connecting:
        icon = Icons.sync;
        color = Colors.blueGrey.shade700;
        text = 'Conectando con el vehículo ($source)…';
      case _MonitorState.running:
        icon = Icons.sensors;
        color = Colors.green.shade700;
        text = 'Leyendo en vivo ($source)';
      case _MonitorState.stopped:
        icon = Icons.pause_circle_outline;
        color = Colors.blueGrey.shade700;
        text = 'Monitoreo detenido. Se muestran los últimos valores leídos.';
      case _MonitorState.failed:
        icon = Icons.error_outline;
        color = Colors.red.shade700;
        text = 'Monitoreo detenido. ${error ?? ''}';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: color, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

/// Un parámetro: nombre, valor grande con su unidad y, si tiene rango, una
/// barra que muestra dónde está dentro de él.
class _ParamTile extends StatelessWidget {
  const _ParamTile({
    required this.label,
    required this.unit,
    required this.reading,
    required this.decimals,
    this.max,
    this.warnFrom,
    this.large = false,
  });

  final String label;
  final String unit;
  final LiveValue? reading;
  final int decimals;
  final double? max;
  final double? warnFrom;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final supported = reading?.supported ?? true;
    final value = reading?.value;
    final warn = value != null && warnFrom != null && value >= warnFrom!;
    final color = warn ? Colors.red.shade700 : Colors.blue.shade700;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 6),
            if (!supported)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  'No disponible',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                  ),
                ),
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    value == null ? '—' : value.toStringAsFixed(decimals),
                    style: TextStyle(
                      fontSize: large ? 44 : 28,
                      fontWeight: FontWeight.bold,
                      color: warn ? color : Colors.black87,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    unit,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                ],
              ),
            if (max != null) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: supported && value != null
                    ? (value / max!).clamp(0.0, 1.0)
                    : 0,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
                color: color,
                backgroundColor: Colors.grey.shade200,
              ),
            ],
            if (warn) ...[
              const SizedBox(height: 6),
              Text(
                'Temperatura alta',
                style: TextStyle(fontSize: 12, color: color),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
