import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taller_mobile/features/alerts/order_sections.dart';
import 'package:taller_mobile/features/orders/order_rules.dart';

Map<String, dynamic> orden(
  String id, {
  String status = 'OPEN',
  String priority = 'MEDIUM',
  String? asignadoA,
  String createdAt = '2026-11-10T10:00:00Z',
  String? closedAt,
}) =>
    {
      'id': id,
      'status': status,
      'priority': priority,
      'createdAt': createdAt,
      'closedAt': closedAt,
      'assignedTo': asignadoA == null ? null : {'id': asignadoA, 'name': 'Roberto'},
    };

void main() {
  group('Quién puede trabajar la orden (checklist, repuestos, avance)', () {
    test('el mecánico asignado, con la orden abierta', () {
      expect(
        puedeTrabajarOrden(
          orden('a', status: 'IN_PROGRESS', asignadoA: 'mec'),
          userId: 'mec',
          puedeActualizar: true,
          administra: false,
        ),
        isTrue,
      );
    });

    test('otro mecánico no', () {
      expect(
        puedeTrabajarOrden(
          orden('a', status: 'IN_PROGRESS', asignadoA: 'otro'),
          userId: 'mec',
          puedeActualizar: true,
          administra: false,
        ),
        isFalse,
      );
    });

    test('el administrador sí, aunque no esté asignado', () {
      expect(
        puedeTrabajarOrden(
          orden('a', asignadoA: 'mec'),
          userId: 'admin',
          puedeActualizar: true,
          administra: true,
        ),
        isTrue,
      );
    });

    test('el inspector no (no tiene order:update_status)', () {
      expect(
        puedeTrabajarOrden(
          orden('a', asignadoA: 'insp'),
          userId: 'insp',
          puedeActualizar: false,
          administra: false,
        ),
        isFalse,
      );
    });

    test('nadie, si la orden está cerrada', () {
      for (final estado in ['COMPLETED', 'CANCELLED']) {
        expect(
          puedeTrabajarOrden(
            orden('a', status: estado, asignadoA: 'mec'),
            userId: 'mec',
            puedeActualizar: true,
            administra: true,
          ),
          isFalse,
        );
      }
    });
  });

  test('cuenta las tareas hechas y totales', () {
    final c = contarTareas([
      {'id': '1', 'completed': true},
      {'id': '2', 'completed': false},
      {'id': '3', 'completed': true},
    ]);
    expect(c.hechas, 2);
    expect(c.total, 3);
    expect(contarTareas(null).total, 0);
  });

  test('solo ofrece repuestos activos y con stock, por nombre', () {
    final lista = repuestosDisponibles([
      {'id': '1', 'name': 'Filtro de aire', 'stock': 3, 'active': true},
      {'id': '2', 'name': 'Bujía', 'stock': 0, 'active': true},
      {'id': '3', 'name': 'Bobina', 'stock': 5, 'active': false},
      {'id': '4', 'name': 'aceite 5W30', 'stock': 2, 'active': true},
    ]);
    expect(lista.map((r) => r['id']), ['4', '1']);
  });

  test('suma el costo de los repuestos usados', () {
    expect(
      costoRepuestos([
        {'quantity': 2, 'unitCost': 45.5},
        {'quantity': 1, 'unitCost': 120},
      ]),
      211,
    );
  });

  test('el inspector ve las órdenes por estado y las últimas cerradas', () {
    final g = agruparOrdenesPorEstado([
      orden('espera'),
      orden('taller', status: 'IN_PROGRESS', asignadoA: 'mec'),
      orden('asignada', asignadoA: 'mec', priority: 'CRITICAL'),
      orden('vieja', status: 'COMPLETED', closedAt: '2026-11-01T10:00:00Z'),
      orden('nueva', status: 'CANCELLED', closedAt: '2026-11-20T10:00:00Z'),
    ]);
    expect(g.sinMecanico.map((o) => o['id']), ['espera']);
    // Lo más urgente primero, también en el taller.
    expect(g.enTaller.map((o) => o['id']), ['asignada', 'taller']);
    expect(g.cerradas.map((o) => o['id']), ['nueva', 'vieja']);
  });

  test('explica en qué paso va la orden', () {
    expect(pasoDeLaOrden(orden('a')), contains('esperando que un mecánico'));
    expect(
      pasoDeLaOrden(orden('a', status: 'IN_PROGRESS', asignadoA: 'mec')),
      'Roberto está trabajando en el vehículo.',
    );
    expect(pasoDeLaOrden(orden('a', status: 'COMPLETED')),
        contains('operativo'));
  });

  group('Checklist en pantalla', () {
    Future<void> mostrar(WidgetTester tester, {required bool editable}) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChecklistSection(
              tasks: const [
                {'id': 't1', 'description': 'Inspeccionar la bujía', 'completed': false},
                {'id': 't2', 'description': 'Medir la bobina', 'completed': true},
              ],
              editable: editable,
              busy: false,
              onToggle: (taskId, completed) {},
              onAdd: (_) async => true,
            ),
          ),
        ),
      );
    }

    testWidgets('el mecánico asignado puede marcar y agregar', (tester) async {
      await mostrar(tester, editable: true);
      final casillas = tester.widgetList<CheckboxListTile>(
          find.byType(CheckboxListTile));
      expect(casillas.length, 2);
      expect(casillas.every((c) => c.onChanged != null), isTrue);
      expect(find.text('Nueva tarea'), findsOneWidget);
    });

    testWidgets('quien solo consulta ve las tareas sin poder marcarlas',
        (tester) async {
      await mostrar(tester, editable: false);
      final casillas = tester.widgetList<CheckboxListTile>(
          find.byType(CheckboxListTile));
      expect(casillas.length, 2);
      expect(casillas.every((c) => c.onChanged == null), isTrue);
      expect(find.text('Nueva tarea'), findsNothing);
    });
  });
}
