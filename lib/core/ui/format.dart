const _meses = [
  'ene', 'feb', 'mar', 'abr', 'may', 'jun',
  'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
];

/// "05 nov 2026, 14:30", en la hora del teléfono. Igual que en la web.
String fechaHora(String? iso) {
  final fecha = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
  if (fecha == null) return '-';
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(fecha.day)} ${_meses[fecha.month - 1]} ${fecha.year}, '
      '${dos(fecha.hour)}:${dos(fecha.minute)}';
}

/// "Toyota Hilux 2021", omitiendo lo que falte.
String descripcionVehiculo(Map<String, dynamic> vehiculo) {
  return [vehiculo['make'], vehiculo['model'], vehiculo['year']]
      .where((v) => v != null && v.toString().trim().isNotEmpty)
      .join(' ');
}

/// "1 código de falla", "3 códigos de falla".
String cuentaCodigos(int n) =>
    n == 1 ? '1 código de falla' : '$n códigos de falla';
