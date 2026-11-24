/// Reglas de las órdenes de trabajo que deciden qué muestra la app.
///
/// Son funciones puras para poder probarlas sin widgets. Las mismas reglas
/// las aplica el backend: aquí solo deciden qué botones se ven.
library;

const estadosAbiertos = ['OPEN', 'IN_PROGRESS'];

const _ordenPrioridad = ['CRITICAL', 'HIGH', 'MEDIUM', 'LOW'];

/// Lo más urgente primero y, a igual prioridad, lo más antiguo.
int compararPorUrgencia(Map<String, dynamic> a, Map<String, dynamic> b) {
  final porPrioridad = _ordenPrioridad
      .indexOf('${a['priority']}')
      .compareTo(_ordenPrioridad.indexOf('${b['priority']}'));
  if (porPrioridad != 0) return porPrioridad;
  return '${a['createdAt']}'.compareTo('${b['createdAt']}');
}

String? asignadoA(Map<String, dynamic> orden) =>
    (orden['assignedTo'] as Map<String, dynamic>?)?['id'] as String?;

/// Si [userId] puede trabajar la orden: marcar tareas, registrar repuestos y
/// avances. Solo el mecánico asignado o quien administra órdenes, y solo
/// mientras la orden siga abierta. Es la misma regla que usa la web.
bool puedeTrabajarOrden(
  Map<String, dynamic> orden, {
  required String? userId,
  required bool puedeActualizar,
  required bool administra,
}) {
  if (!estadosAbiertos.contains(orden['status'])) return false;
  if (!puedeActualizar) return false;
  final asignado = userId != null && asignadoA(orden) == userId;
  return asignado || administra;
}

/// Tareas hechas y totales del checklist.
({int hechas, int total}) contarTareas(List<dynamic>? tareas) {
  final lista = (tareas ?? const []).whereType<Map<String, dynamic>>();
  return (
    hechas: lista.where((t) => t['completed'] == true).length,
    total: lista.length,
  );
}

/// Repuestos que se pueden registrar: activos y con stock, ordenados por
/// nombre.
List<Map<String, dynamic>> repuestosDisponibles(List<dynamic> repuestos) {
  return repuestos
      .whereType<Map<String, dynamic>>()
      .where((r) => r['active'] != false && ((r['stock'] as num?) ?? 0) > 0)
      .toList()
    ..sort((a, b) => '${a['name']}'
        .toLowerCase()
        .compareTo('${b['name']}'.toLowerCase()));
}

/// Costo total de los repuestos usados en una orden.
double costoRepuestos(List<dynamic>? usados) {
  return (usados ?? const [])
      .whereType<Map<String, dynamic>>()
      .fold<double>(
        0,
        (suma, u) =>
            suma +
            ((u['quantity'] as num?) ?? 0) * ((u['unitCost'] as num?) ?? 0),
      );
}

/// Las órdenes vistas por quien solo las consulta (el inspector): las abiertas
/// separadas en «sin mecánico» y «en el taller», y las últimas cerradas para
/// saber cuándo el vehículo volvió a estar operativo.
({
  List<Map<String, dynamic>> sinMecanico,
  List<Map<String, dynamic>> enTaller,
  List<Map<String, dynamic>> cerradas
}) agruparOrdenesPorEstado(List<dynamic> ordenes, {int maxCerradas = 10}) {
  final todas = ordenes.whereType<Map<String, dynamic>>().toList();
  final abiertas = todas
      .where((o) => estadosAbiertos.contains(o['status']))
      .toList()
    ..sort(compararPorUrgencia);
  final cerradas = todas
      .where((o) => !estadosAbiertos.contains(o['status']))
      .toList()
    // La más reciente primero; sin fecha de cierre, al final.
    ..sort((a, b) =>
        '${b['closedAt'] ?? ''}'.compareTo('${a['closedAt'] ?? ''}'));

  return (
    sinMecanico: abiertas.where((o) => asignadoA(o) == null).toList(),
    enTaller: abiertas.where((o) => asignadoA(o) != null).toList(),
    cerradas: cerradas.take(maxCerradas).toList(),
  );
}

/// En qué paso va la orden, en palabras, para quien solo la consulta.
String pasoDeLaOrden(Map<String, dynamic> orden) {
  final mecanico =
      (orden['assignedTo'] as Map<String, dynamic>?)?['name'] as String?;
  return switch (orden['status']) {
    'OPEN' when mecanico == null =>
      'La orden está en el taller esperando que un mecánico la tome.',
    'OPEN' => 'La orden está asignada a $mecanico y todavía no empezó.',
    'IN_PROGRESS' =>
      '${mecanico ?? 'Un mecánico'} está trabajando en el vehículo.',
    'COMPLETED' =>
      'La orden se completó y el vehículo volvió a quedar operativo.',
    'CANCELLED' =>
      'La orden se canceló. El estado del vehículo se toma de su último escaneo.',
    _ => 'Estado de la orden desconocido.',
  };
}

/// Etiqueta de un estado de orden para el historial.
String nombreEstado(String? estado) => switch (estado) {
      'OPEN' => 'Abierta',
      'IN_PROGRESS' => 'En proceso',
      'COMPLETED' => 'Completada',
      'CANCELLED' => 'Cancelada',
      null => 'Creación',
      _ => estado,
    };
