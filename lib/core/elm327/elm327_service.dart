class ParsedDtc {
  final String code;
  final String type; // CONFIRMED | PENDING | PERMANENT

  ParsedDtc({required this.code, required this.type});

  Map<String, dynamic> toJson() => {
        'code': code,
        'type': type,
      };
}

class ParsedReadiness {
  final bool milOn;
  final int dtcCount;
  final bool monitorsCompleted;
  final List<String> incompleteMonitors;

  /// Motor de encendido por compresión (diésel), leído del byte B bit 3.
  /// Determina qué sistemas designan los bits del byte D.
  final bool compressionIgnition;

  final String rawHex;
  final bool batteryResetSuspected;

  ParsedReadiness({
    required this.milOn,
    required this.dtcCount,
    required this.monitorsCompleted,
    required this.incompleteMonitors,
    this.compressionIgnition = false,
    required this.rawHex,
    required this.batteryResetSuspected,
  });

  Map<String, dynamic> toJson() => {
        'milOn': milOn,
        'dtcCount': dtcCount,
        'monitorsCompleted': monitorsCompleted,
        'incompleteMonitors': incompleteMonitors,
        'compressionIgnition': compressionIgnition,
        'rawHex': rawHex,
        'batteryResetSuspected': batteryResetSuspected,
      };
}

/// Protocolo OBD-II con el que el adaptador se comunicó con la ECU.
///
/// Se obtiene de `ATDPN` (Describe Protocol by Number) en lugar de inferirlo.
/// Es el dato que decide cómo parsear las respuestas de DTC: en CAN
/// (ISO 15765-4) la respuesta del Modo 03 trae un byte de conteo de códigos;
/// en ISO 9141-2 y KWP2000 no existe. Adivinarlo hacía que en vehículos
/// anteriores a ~2008 se perdiera el primer código y se desalineara el resto.
class ParsedProtocol {
  /// Número de protocolo ELM327: '1'..'9', 'A'..'C', o null si no se pudo leer.
  final String? number;

  /// Si la detección fue automática (ATSP0), ATDPN responde con prefijo 'A'.
  final bool automatic;

  final String label;
  final String raw;

  ParsedProtocol({
    required this.number,
    required this.automatic,
    required this.label,
    required this.raw,
  });

  /// Protocolos de la familia CAN, los únicos con byte de conteo en el Modo 03.
  static const Set<String> _canProtocols = {'6', '7', '8', '9', 'A', 'B', 'C'};

  bool get isCan => number != null && _canProtocols.contains(number);

  /// Cuando no se pudo determinar el protocolo se asume CAN, que es el caso de
  /// cualquier vehículo posterior a 2008 y por tanto el más probable.
  bool get assumeCountByte => number == null ? true : isCan;

  static const Map<String, String> _etiquetas = {
    '1': 'SAE J1850 PWM (41.6 kbaud)',
    '2': 'SAE J1850 VPW (10.4 kbaud)',
    '3': 'ISO 9141-2',
    '4': 'ISO 14230-4 KWP (iniciación 5 baud)',
    '5': 'ISO 14230-4 KWP (iniciación rápida)',
    '6': 'ISO 15765-4 CAN (11 bit, 500 kbaud)',
    '7': 'ISO 15765-4 CAN (29 bit, 500 kbaud)',
    '8': 'ISO 15765-4 CAN (11 bit, 250 kbaud)',
    '9': 'ISO 15765-4 CAN (29 bit, 250 kbaud)',
    'A': 'SAE J1939 CAN',
    'B': 'CAN definido por usuario 1',
    'C': 'CAN definido por usuario 2',
  };

  static String etiquetaDe(String? numero) =>
      _etiquetas[numero] ?? 'Protocolo no identificado';

  Map<String, dynamic> toJson() => {
        'number': number,
        'automatic': automatic,
        'isCan': isCan,
        'label': label,
        'raw': raw,
      };
}

/// Resultado de una consulta OBD individual.
///
/// Distinguir estos tres casos es lo que impide que una lectura fallida se
/// confunda con un vehículo sin fallas: "la ECU respondió que no hay códigos"
/// (`ok`) no es lo mismo que "la ECU no respondió" (`failed`).
enum ObdReadStatus {
  /// La ECU respondió con la cabecera esperada.
  ok,

  /// El adaptador respondió `NO DATA`: la ECU no soporta esa consulta.
  noData,

  /// Timeout, error de bus o respuesta ilegible: no se sabe qué hay.
  failed,
}

/// No hay comunicación con la ECU (contacto apagado, adaptador mal puesto o
/// vehículo sin OBD-II). El escaneo se aborta: no hay nada que registrar.
class ObdCommunicationException implements Exception {
  final String message;

  ObdCommunicationException(this.message);

  @override
  String toString() => message;
}

class ObdScanResult {
  final String? vin;
  final double? batteryVoltage;
  final ParsedReadiness readiness;
  final ParsedProtocol protocol;
  final List<ParsedDtc> dtcs;
  final DateTime scannedAt;
  final Map<String, String> rawResponses;

  /// Lecturas obligatorias que fallaron. Si no está vacía, el escaneo está
  /// incompleto y NO debe enviarse: registraría como sano un vehículo que en
  /// realidad no se pudo leer.
  final List<String> readErrors;

  /// Lecturas opcionales que no se obtuvieron (no bloquean el envío).
  final List<String> warnings;

  ObdScanResult({
    required this.vin,
    required this.batteryVoltage,
    required this.readiness,
    required this.protocol,
    required this.dtcs,
    required this.scannedAt,
    required this.rawResponses,
    this.readErrors = const [],
    this.warnings = const [],
  });

  bool get isComplete => readErrors.isEmpty;

  Map<String, dynamic> toApiPayload({String? vehicleId, String? notes}) => {
        if (vehicleId != null && vehicleId.isNotEmpty) 'vehicleId': vehicleId,
        if (vin != null && vin!.isNotEmpty) 'vin': vin,
        if (batteryVoltage != null) 'batteryVoltage': batteryVoltage,
        // En UTC y con la 'Z': una hora local sin zona la interpreta el
        // servidor en SU zona horaria y el escaneo queda corrido varias horas.
        'scannedAt': scannedAt.toUtc().toIso8601String(),
        'complete': isComplete,
        'readinessStatus': readiness.toJson(),
        'protocol': protocol.toJson(),
        'dtcs': dtcs.map((d) => d.toJson()).toList(),
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        'rawPayload': rawResponses,
      };
}

class Elm327Service {
  static final RegExp _parHex = RegExp(r'^[0-9A-F]{2}$');
  static final RegExp _segmentoMultitrama = RegExp(r'^([0-9A-F]):\s*(.*)$');
  static final RegExp _longitudMultitrama = RegExp(r'^[0-9A-F]{3}$');

  /// Convierte un texto en bytes hexadecimales, o null si no lo es.
  /// Acepta bytes separados por espacios o pegados (adaptador con `ATS0`).
  List<String>? _bytes(String texto) {
    final t = texto.trim();
    if (t.isEmpty) return const [];

    final List<String> partes;
    if (t.contains(' ')) {
      partes = t.split(RegExp(r'\s+'));
    } else {
      if (t.length.isOdd) return null;
      partes = [
        for (var i = 0; i + 1 < t.length; i += 2) t.substring(i, i + 2),
      ];
    }

    return partes.every(_parHex.hasMatch) ? partes : null;
  }

  /// Separa la respuesta del adaptador en mensajes, uno por ECU.
  ///
  /// Antes se juntaban todos los bytes en una sola lista. Cuando respondían
  /// dos módulos (motor y caja, por ejemplo) la cabecera del segundo se leía
  /// como si fuera un código de falla y aparecían códigos que ninguna ECU
  /// reportó. Aquí cada línea es un mensaje propio, y las respuestas
  /// multitrama de CAN (`00A`, `0: ...`, `1: ...`) se rearman en uno solo.
  List<List<String>> _frames(String raw) {
    final frames = <List<String>>[];
    List<String>? multi;
    int? longitudMulti;
    int? longitudPendiente;

    void cerrarMulti() {
      final m = multi;
      if (m == null) return;
      final largo = longitudMulti;
      frames.add(largo != null && largo < m.length ? m.sublist(0, largo) : m);
      multi = null;
      longitudMulti = null;
    }

    final lineas = raw.replaceAll('>', '').split(RegExp(r'[\r\n]+'));
    for (final cruda in lineas) {
      final linea = cruda.trim().toUpperCase();
      if (linea.isEmpty) continue;

      final segmento = _segmentoMultitrama.firstMatch(linea);
      if (segmento != null) {
        final bytes = _bytes(segmento.group(2)!);
        if (bytes == null) continue;
        if (segmento.group(1) == '0') {
          cerrarMulti();
          multi = [...bytes];
          longitudMulti = longitudPendiente;
          longitudPendiente = null;
        } else {
          multi?.addAll(bytes);
        }
        continue;
      }

      // Longitud total de un mensaje multitrama (tres dígitos hex, sin espacios).
      if (_longitudMultitrama.hasMatch(linea)) {
        longitudPendiente = int.parse(linea, radix: 16);
        continue;
      }

      // Lo que no es hexadecimal ("SEARCHING...", "BUS INIT: OK", "NO DATA")
      // no es un mensaje de la ECU.
      final bytes = _bytes(linea);
      if (bytes == null || bytes.isEmpty) continue;
      cerrarMulti();
      frames.add(bytes);
    }

    cerrarMulti();
    return frames;
  }

  bool _empiezaCon(List<String> frame, List<String> cabecera) {
    if (frame.length < cabecera.length) return false;
    for (var i = 0; i < cabecera.length; i++) {
      if (frame[i] != cabecera[i]) return false;
    }
    return true;
  }

  /// Clasifica la respuesta a una consulta: ¿respondió la ECU, no soporta la
  /// consulta, o la lectura falló? [header] es la cabecera esperada, por
  /// ejemplo `'43'` para el Modo 03 o `'41 01'` para el PID 01.
  ObdReadStatus readStatus(String raw, String header) {
    final cabecera = header.trim().toUpperCase().split(RegExp(r'\s+'));
    if (_frames(raw).any((f) => _empiezaCon(f, cabecera))) {
      return ObdReadStatus.ok;
    }
    return raw.toUpperCase().contains('NO DATA')
        ? ObdReadStatus.noData
        : ObdReadStatus.failed;
  }

  /// Extrae el voltaje en voltios desde respuesta ATRV (ej: "13.3V\r\r>")
  double? parseVoltage(String raw) {
    final match = RegExp(r'(\d+\.\d+)').firstMatch(raw);
    if (match != null) {
      return double.tryParse(match.group(1)!);
    }
    return null;
  }

  /// Bytes de datos con los que la ECU respondió a un PID del Modo 01, sin la
  /// cabecera `41 XX`. Devuelve null si no hay una respuesta válida (el
  /// vehículo no soporta el PID o la lectura falló). Lo usa el monitor en vivo.
  List<int>? parsePidData(String raw, int pid) {
    final cabecera = ['41', pid.toRadixString(16).toUpperCase().padLeft(2, '0')];
    for (final frame in _frames(raw)) {
      if (!_empiezaCon(frame, cabecera) || frame.length <= 2) continue;
      return [for (final b in frame.sublist(2)) int.parse(b, radix: 16)];
    }
    return null;
  }

  /// PID del Modo 01 (del 01 al 20) que el vehículo declara soportar en su
  /// respuesta a `0100`. Si responden varias ECU, se suman.
  Set<int> parseSupportedPids(String raw0100) {
    final soportados = <int>{};
    for (final frame in _frames(raw0100)) {
      if (!_empiezaCon(frame, const ['41', '00']) || frame.length < 6) continue;
      for (var i = 0; i < 4; i++) {
        final byte = int.parse(frame[2 + i], radix: 16);
        for (var bit = 0; bit < 8; bit++) {
          if (byte & (0x80 >> bit) != 0) soportados.add(i * 8 + bit + 1);
        }
      }
    }
    return soportados;
  }

  /// Decodifica el VIN (Modo 09 PID 02) desde bytes hexadecimales ASCII
  String? parseVin(String raw) {
    final cleaned = raw
        .replaceAll('>', '')
        .replaceAll('\r', ' ')
        .replaceAll('\n', ' ')
        .trim();
    if (cleaned.contains('NO DATA') || cleaned.contains('ERROR')) {
      return null;
    }

    final tokens = cleaned
        .split(RegExp(r'\s+'))
        .where((t) => RegExp(r'^[0-9A-Fa-f]{2}$').hasMatch(t))
        .toList();

    // Remover cabecera 49 02 01 si está presente
    List<String> hexBytes = tokens;
    for (int i = 0; i <= tokens.length - 3; i++) {
      if (tokens[i].toUpperCase() == '49' &&
          tokens[i + 1].toUpperCase() == '02') {
        hexBytes = tokens.sublist(i + 3);
        break;
      }
    }

    final chars = <int>[];
    for (final hex in hexBytes) {
      final val = int.tryParse(hex, radix: 16);
      if (val != null && val >= 0x30 && val <= 0x5A) {
        chars.add(val);
      }
    }

    final vin = String.fromCharCodes(chars);
    return vin.length >= 11 ? vin : null;
  }

  /// Interpreta la respuesta de `ATDPN` (Describe Protocol by Number).
  ///
  /// Con detección automática (ATSP0) el adaptador prefija la letra 'A',
  /// de modo que una respuesta típica es `A6` para CAN de 11 bit a 500 kbaud.
  ParsedProtocol parseProtocol(String raw) {
    final cleaned = raw
        .replaceAll('>', '')
        .replaceAll('\r', ' ')
        .replaceAll('\n', ' ')
        .trim()
        .toUpperCase();

    final compacto = cleaned.replaceAll(' ', '');
    final match = RegExp(r'^(A)?([1-9A-C])$').firstMatch(compacto);

    if (match == null) {
      return ParsedProtocol(
        number: null,
        automatic: false,
        label: ParsedProtocol.etiquetaDe(null),
        raw: cleaned,
      );
    }

    final numero = match.group(2);
    return ParsedProtocol(
      number: numero,
      automatic: match.group(1) == 'A',
      label: ParsedProtocol.etiquetaDe(numero),
      raw: cleaned,
    );
  }

  /// Decodifica el estado global de preparación de monitores (Mode 01 PID 01: 41 01 AA BB CC DD)
  ParsedReadiness parseReadiness(String raw) {
    final cleaned = raw
        .replaceAll('>', '')
        .replaceAll('\r', ' ')
        .replaceAll('\n', ' ')
        .trim();

    final tokens = cleaned
        .split(RegExp(r'\s+'))
        .where((t) => RegExp(r'^[0-9A-Fa-f]{2}$').hasMatch(t))
        .map((t) => t.toUpperCase())
        .toList();

    int startIdx = -1;
    for (int i = 0; i <= tokens.length - 6; i++) {
      if (tokens[i] == '41' && tokens[i + 1] == '01') {
        startIdx = i + 2;
        break;
      }
    }

    if (startIdx == -1 || startIdx + 4 > tokens.length) {
      return ParsedReadiness(
        milOn: false,
        dtcCount: 0,
        monitorsCompleted: true,
        incompleteMonitors: [],
        rawHex: cleaned,
        batteryResetSuspected: false,
      );
    }

    final aa = int.parse(tokens[startIdx], radix: 16);
    final bb = int.parse(tokens[startIdx + 1], radix: 16);
    final cc = int.parse(tokens[startIdx + 2], radix: 16);
    final dd = int.parse(tokens[startIdx + 3], radix: 16);

    final milOn = (aa & 0x80) != 0;
    final dtcCount = aa & 0x7F;

    // Bit 3 del byte B: motor de encendido por compresión (diésel).
    // Cambia por completo el significado del byte D.
    final compressionIgnition = (bb & 0x08) != 0;

    // El byte C indica qué monitores soporta el vehículo y el byte D cuáles no
    // completó. Se aplica la máscara porque algunas ECU dejan bits activos en D
    // para monitores que ni siquiera soportan, lo que produciría monitores
    // "incompletos" fantasma.
    final noCompletados = dd & cc;

    final incomplete = compressionIgnition
        ? _monitoresDiesel(noCompletados)
        : _monitoresGasolina(noCompletados);

    final monitorsCompleted = incomplete.isEmpty;

    return ParsedReadiness(
      milOn: milOn,
      dtcCount: dtcCount,
      monitorsCompleted: monitorsCompleted,
      incompleteMonitors: incomplete,
      compressionIgnition: compressionIgnition,
      rawHex: tokens.sublist(startIdx - 2, startIdx + 4).join(' '),
      batteryResetSuspected: !monitorsCompleted && incomplete.length >= 2,
    );
  }

  /// Monitores no continuos de un motor de encendido por chispa (gasolina).
  List<String> _monitoresGasolina(int dd) {
    final incomplete = <String>[];
    if ((dd & 0x01) != 0) incomplete.add('Catalizador');
    if ((dd & 0x02) != 0) incomplete.add('Catalizador calentado');
    if ((dd & 0x04) != 0) incomplete.add('Sistema EVAP');
    if ((dd & 0x08) != 0) incomplete.add('Sistema de aire secundario');
    if ((dd & 0x10) != 0) incomplete.add('Refrigerante A/C');
    if ((dd & 0x20) != 0) incomplete.add('Sensor de Oxígeno');
    if ((dd & 0x40) != 0) incomplete.add('Calefactor Sensor O2');
    if ((dd & 0x80) != 0) incomplete.add('Sistema EGR');
    return incomplete;
  }

  /// Monitores no continuos de un motor de encendido por compresión (diésel).
  ///
  /// Los mismos bits del byte D designan sistemas distintos. Interpretarlos
  /// como si fueran de gasolina reportaba "Sistema EVAP incompleto" en
  /// vehículos que no tienen sistema EVAP.
  List<String> _monitoresDiesel(int dd) {
    final incomplete = <String>[];
    if ((dd & 0x01) != 0) incomplete.add('Catalizador NMHC');
    if ((dd & 0x02) != 0) incomplete.add('Sistema SCR / NOx');
    if ((dd & 0x08) != 0) incomplete.add('Presión de sobrealimentación');
    if ((dd & 0x20) != 0) incomplete.add('Sensor de gases de escape');
    if ((dd & 0x40) != 0) incomplete.add('Filtro de partículas (DPF)');
    if ((dd & 0x80) != 0) incomplete.add('Sistema EGR / VVT');
    return incomplete;
  }

  /// Decodifica DTCs de los Modos 03 (43), 07 (47) y 0A (4A).
  ///
  /// [hasCountByte] indica si la respuesta trae el byte de conteo de códigos
  /// que define ISO 15765-4 (CAN). En ISO 9141-2 y KWP2000 ese byte NO existe:
  /// la respuesta son tres pares de bytes de DTC rellenados con ceros.
  /// Asumirlo siempre presente hacía que en vehículos anteriores a ~2008 se
  /// perdiera el primer código y se desalinearan todos los demás.
  ///
  /// El valor sale de `ATDPN`, o sea del propio adaptador, en lugar de
  /// inferirse de la forma de la respuesta.
  List<ParsedDtc> parseDtcs(
    String raw,
    String expectedHeader,
    String dtcType, {
    bool hasCountByte = true,
  }) {
    final cabecera = [expectedHeader.trim().toUpperCase()];
    final results = <ParsedDtc>[];
    final vistos = <String>{};

    // Un mensaje por ECU: cada uno trae su propia cabecera y su propio conteo.
    for (final frame in _frames(raw)) {
      if (!_empiezaCon(frame, cabecera)) continue;

      // Saltar la cabecera (43, 47 o 4A) y, solo en CAN, el byte de conteo.
      var cursor = hasCountByte ? 2 : 1;

      // En CAN el conteo dice cuántos códigos son reales: lo que sigue es
      // relleno, que algunas ECU no ponen en 00 sino en AA o 55.
      var restantes = hasCountByte && frame.length > 1
          ? int.parse(frame[1], radix: 16)
          : -1;

      while (cursor + 1 < frame.length && restantes != 0) {
        final b1 = int.parse(frame[cursor], radix: 16);
        final b2 = int.parse(frame[cursor + 1], radix: 16);
        cursor += 2;
        if (restantes > 0) restantes--;

        if (b1 == 0 && b2 == 0) continue;

        final code = _decodeDtcBytes(b1, b2);
        // Dos módulos pueden reportar el mismo código.
        if (vistos.add(code)) {
          results.add(ParsedDtc(code: code, type: dtcType));
        }
      }
    }

    return results;
  }

  String _decodeDtcBytes(int b1, int b2) {
    const prefixes = ['P', 'C', 'B', 'U'];
    final prefix = prefixes[(b1 >> 6) & 0x03];
    final secondChar = ((b1 >> 4) & 0x03).toString();
    final thirdChar = (b1 & 0x0F).toRadixString(16).toUpperCase();
    final fourthFifth = b2.toRadixString(16).toUpperCase().padLeft(2, '0');
    return '$prefix$secondChar$thirdChar$fourthFifth';
  }

  /// Ejecuta la secuencia completa de escaneo OBD-II
  /// (ATZ -> ATE0 -> ATL0 -> ATH0 -> ATSP0 -> 0100 -> ATDPN -> ATRV -> 0902
  ///  -> 0101 -> 03 -> 07 -> 0A)
  ///
  /// Lanza [ObdCommunicationException] si la ECU no responde a `0100`.
  Future<ObdScanResult> runFullScan({
    required Future<String> Function(String command) sendCommand,
    void Function(String step)? onStep,
  }) async {
    final rawResponses = <String, String>{};

    onStep?.call('Inicializando adaptador ELM327...');
    rawResponses['ATZ'] = await sendCommand('ATZ');
    rawResponses['ATE0'] = await sendCommand('ATE0');
    rawResponses['ATL0'] = await sendCommand('ATL0');
    // Sin cabeceras de red: el parser espera solo los bytes de datos.
    rawResponses['ATH0'] = await sendCommand('ATH0');
    rawResponses['ATSP0'] = await sendCommand('ATSP0');

    // El adaptador negocia el protocolo recién con la PRIMERA consulta OBD.
    // Hasta entonces `ATDPN` responde `A0` (sin determinar). `0100` cumple dos
    // funciones: fuerza esa negociación y comprueba que la ECU está viva.
    onStep?.call('Estableciendo comunicación con la ECU (0100)...');
    final raw0100 = await sendCommand('0100');
    rawResponses['0100'] = raw0100;
    if (readStatus(raw0100, '41 00') != ObdReadStatus.ok) {
      throw ObdCommunicationException(
        'El vehículo no respondió al protocolo OBD-II. Verifique que el '
        'contacto esté encendido y que el adaptador esté bien conectado.',
      );
    }

    onStep?.call('Detectando protocolo de la ECU (ATDPN)...');
    final rawProtocol = await sendCommand('ATDPN');
    rawResponses['ATDPN'] = rawProtocol;
    final protocol = parseProtocol(rawProtocol);
    onStep?.call('Protocolo: ${protocol.label}');

    onStep?.call('Leyendo voltaje de batería (ATRV)...');
    final rawVoltage = await sendCommand('ATRV');
    rawResponses['ATRV'] = rawVoltage;
    final voltage = parseVoltage(rawVoltage);

    onStep?.call('Consultando número de chasis VIN (Modo 09 PID 02)...');
    final rawVin = await sendCommand('0902');
    rawResponses['0902'] = rawVin;
    final vin = parseVin(rawVin);

    onStep?.call('Consultando estado global de monitores (Modo 01 PID 01)...');
    final rawReadiness = await sendCommand('0101');
    rawResponses['0101'] = rawReadiness;
    final readiness = parseReadiness(rawReadiness);

    onStep?.call('Leyendo códigos DTC Confirmados (Modo 03)...');
    final raw03 = await sendCommand('03');
    rawResponses['03'] = raw03;
    final confirmedDtcs = parseDtcs(raw03, '43', 'CONFIRMED',
        hasCountByte: protocol.assumeCountByte);

    onStep?.call('Leyendo códigos DTC Pendientes (Modo 07)...');
    final raw07 = await sendCommand('07');
    rawResponses['07'] = raw07;
    final pendingDtcs = parseDtcs(raw07, '47', 'PENDING',
        hasCountByte: protocol.assumeCountByte);

    onStep?.call('Leyendo códigos DTC Permanentes (Modo 0A)...');
    final raw0A = await sendCommand('0A');
    rawResponses['0A'] = raw0A;
    final permanentDtcs = parseDtcs(raw0A, '4A', 'PERMANENT',
        hasCountByte: protocol.assumeCountByte);

    final allDtcs = <ParsedDtc>[
      ...confirmedDtcs,
      ...pendingDtcs,
      ...permanentDtcs,
    ];

    // ¿Se pudo leer de verdad, o las listas vacías son lecturas fallidas?
    final readErrors = <String>[];
    final warnings = <String>[];

    if (readStatus(rawReadiness, '41 01') != ObdReadStatus.ok) {
      readErrors.add('Estado de monitores (PID 01)');
    }
    // El Modo 03 es obligatorio en OBD-II: sin respuesta no se puede afirmar
    // que no haya códigos confirmados.
    if (readStatus(raw03, '43') != ObdReadStatus.ok) {
      readErrors.add('Códigos confirmados (Modo 03)');
    }
    // Modos 07 y 0A: `NO DATA` es legítimo (el 0A no existe antes de 2010).
    // Un timeout o error de bus en el 07 sí deja el escaneo incompleto.
    final estado07 = readStatus(raw07, '47');
    if (estado07 == ObdReadStatus.failed) {
      readErrors.add('Códigos pendientes (Modo 07)');
    } else if (estado07 == ObdReadStatus.noData) {
      warnings.add('La ECU no reporta códigos pendientes (Modo 07).');
    }
    if (readStatus(raw0A, '4A') != ObdReadStatus.ok) {
      warnings.add('La ECU no reporta códigos permanentes (Modo 0A).');
    }
    if (vin == null) {
      warnings.add('La ECU no reportó el VIN: seleccione el vehículo a mano.');
    }

    return ObdScanResult(
      readErrors: readErrors,
      warnings: warnings,
      vin: vin,
      batteryVoltage: voltage,
      readiness: readiness,
      protocol: protocol,
      dtcs: allDtcs,
      scannedAt: DateTime.now(),
      rawResponses: rawResponses,
    );
  }
}
