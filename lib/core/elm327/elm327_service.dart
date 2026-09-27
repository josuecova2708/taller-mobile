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
  final String rawHex;
  final bool batteryResetSuspected;

  ParsedReadiness({
    required this.milOn,
    required this.dtcCount,
    required this.monitorsCompleted,
    required this.incompleteMonitors,
    required this.rawHex,
    required this.batteryResetSuspected,
  });

  Map<String, dynamic> toJson() => {
        'milOn': milOn,
        'dtcCount': dtcCount,
        'monitorsCompleted': monitorsCompleted,
        'incompleteMonitors': incompleteMonitors,
        'rawHex': rawHex,
        'batteryResetSuspected': batteryResetSuspected,
      };
}

class ObdScanResult {
  final String? vin;
  final double? batteryVoltage;
  final ParsedReadiness readiness;
  final List<ParsedDtc> dtcs;
  final DateTime scannedAt;
  final Map<String, String> rawResponses;

  ObdScanResult({
    required this.vin,
    required this.batteryVoltage,
    required this.readiness,
    required this.dtcs,
    required this.scannedAt,
    required this.rawResponses,
  });

  Map<String, dynamic> toApiPayload({String? vehicleId, String? notes}) => {
        if (vehicleId != null && vehicleId.isNotEmpty) 'vehicleId': vehicleId,
        if (vin != null && vin!.isNotEmpty) 'vin': vin,
        if (batteryVoltage != null) 'batteryVoltage': batteryVoltage,
        'scannedAt': scannedAt.toIso8601String(),
        'readinessStatus': readiness.toJson(),
        'dtcs': dtcs.map((d) => d.toJson()).toList(),
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        'rawPayload': rawResponses,
      };
}

class Elm327Service {
  /// Extrae el voltaje en voltios desde respuesta ATRV (ej: "13.3V\r\r>")
  double? parseVoltage(String raw) {
    final match = RegExp(r'(\d+\.\d+)').firstMatch(raw);
    if (match != null) {
      return double.tryParse(match.group(1)!);
    }
    return null;
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
    final dd = int.parse(tokens[startIdx + 3], radix: 16);

    final milOn = (aa & 0x80) != 0;
    final dtcCount = aa & 0x7F;

    final incomplete = <String>[];
    if ((dd & 0x01) != 0) incomplete.add('Catalizador');
    if ((dd & 0x04) != 0) incomplete.add('Sistema EVAP');
    if ((dd & 0x20) != 0) incomplete.add('Sensor de Oxígeno');
    if ((dd & 0x40) != 0) incomplete.add('Calefactor Sensor O2');
    if ((dd & 0x80) != 0) incomplete.add('Sistema EGR');

    final monitorsCompleted = incomplete.isEmpty;

    return ParsedReadiness(
      milOn: milOn,
      dtcCount: dtcCount,
      monitorsCompleted: monitorsCompleted,
      incompleteMonitors: incomplete,
      rawHex: tokens.sublist(startIdx - 2, startIdx + 4).join(' '),
      batteryResetSuspected: !monitorsCompleted && incomplete.length >= 2,
    );
  }

  /// Decodifica DTCs de los Modos 03 (43), 07 (47) y 0A (4A)
  List<ParsedDtc> parseDtcs(String raw, String expectedHeader, String dtcType) {
    final cleaned = raw
        .replaceAll('>', '')
        .replaceAll('\r', ' ')
        .replaceAll('\n', ' ')
        .trim();

    if (cleaned.contains('NO DATA') || cleaned.contains('ERROR')) {
      return [];
    }

    final tokens = cleaned
        .split(RegExp(r'\s+'))
        .where((t) => RegExp(r'^[0-9A-Fa-f]{2}$').hasMatch(t))
        .map((t) => t.toUpperCase())
        .toList();

    int idx = tokens.indexOf(expectedHeader.toUpperCase());
    if (idx == -1) return [];

    // Saltar byte de cabecera (43, 47 o 4A) y el byte de conteo de códigos
    int cursor = idx + 2;
    final results = <ParsedDtc>[];

    while (cursor + 1 < tokens.length) {
      final b1 = int.parse(tokens[cursor], radix: 16);
      final b2 = int.parse(tokens[cursor + 1], radix: 16);
      cursor += 2;

      if (b1 == 0 && b2 == 0) continue;

      final code = _decodeDtcBytes(b1, b2);
      results.add(ParsedDtc(code: code, type: dtcType));
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

  /// Ejecuta la secuencia completa de escaneo OBD-II (ATZ -> ATE0 -> ATSP0 -> ATRV -> 0902 -> 0101 -> 03 -> 07 -> 0A)
  Future<ObdScanResult> runFullScan({
    required Future<String> Function(String command) sendCommand,
    void Function(String step)? onStep,
  }) async {
    final rawResponses = <String, String>{};

    onStep?.call('Inicializando adaptador ELM327 (ATZ, ATE0, ATSP0)...');
    rawResponses['ATZ'] = await sendCommand('ATZ');
    rawResponses['ATE0'] = await sendCommand('ATE0');
    rawResponses['ATSP0'] = await sendCommand('ATSP0');

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
    final confirmedDtcs = parseDtcs(raw03, '43', 'CONFIRMED');

    onStep?.call('Leyendo códigos DTC Pendientes (Modo 07)...');
    final raw07 = await sendCommand('07');
    rawResponses['07'] = raw07;
    final pendingDtcs = parseDtcs(raw07, '47', 'PENDING');

    onStep?.call('Leyendo códigos DTC Permanentes (Modo 0A)...');
    final raw0A = await sendCommand('0A');
    rawResponses['0A'] = raw0A;
    final permanentDtcs = parseDtcs(raw0A, '4A', 'PERMANENT');

    final allDtcs = <ParsedDtc>[
      ...confirmedDtcs,
      ...pendingDtcs,
      ...permanentDtcs,
    ];

    return ObdScanResult(
      vin: vin,
      batteryVoltage: voltage,
      readiness: readiness,
      dtcs: allDtcs,
      scannedAt: DateTime.now(),
      rawResponses: rawResponses,
    );
  }
}
