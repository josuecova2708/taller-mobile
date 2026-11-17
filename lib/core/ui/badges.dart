import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Tonos de las etiquetas, los mismos de la web. Solo los tres colores de
/// estado, más neutro y azul de marca para lo que no es bueno ni malo. La
/// intensidad sube con la gravedad: suave para lo que hay que mirar, sólido
/// para lo que no puede esperar.
enum BadgeTone { neutral, ok, warn, severe, critical, brand, brandSolid }

/// Etiqueta de estado. Siempre lleva texto: el color nunca informa solo.
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.label, {super.key, required this.tone, this.dot = false});

  final String label;
  final BadgeTone tone;

  /// Punto de color delante del texto (estado del vehículo).
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final (Color background, Color foreground) = switch (tone) {
      BadgeTone.neutral => (AppColors.line, AppColors.ink2),
      BadgeTone.ok => (AppColors.okSoft, AppColors.ok),
      BadgeTone.warn => (AppColors.warnSoft, AppColors.warn),
      BadgeTone.severe => (AppColors.dangerSoft, AppColors.danger),
      BadgeTone.critical => (AppColors.danger, Colors.white),
      BadgeTone.brand => (AppColors.navySoft, AppColors.navy),
      BadgeTone.brandSolid => (AppColors.navy, Colors.white),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: foreground, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.3,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}

// Los textos de cada estado viven aquí, en un solo lugar para toda la app, y
// coinciden con los de la web (`Badges.tsx`).

/// Estado del vehículo: punto de color más texto.
class VehicleStatusBadge extends StatelessWidget {
  const VehicleStatusBadge(this.status, {super.key});

  final String? status;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = switch (status) {
      'ALERT' => ('En seguimiento', BadgeTone.warn),
      'CRITICAL' => ('Requiere evaluación', BadgeTone.severe),
      _ => ('Operativo', BadgeTone.ok),
    };
    return StatusBadge(label, tone: tone, dot: true);
  }
}

/// Severidad de un escaneo.
class SeverityBadge extends StatelessWidget {
  const SeverityBadge(this.severity, {super.key});

  final String? severity;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = switch (severity) {
      'LOW' => ('Leve', BadgeTone.neutral),
      'MEDIUM' => ('Media', BadgeTone.warn),
      'HIGH' => ('Alta', BadgeTone.severe),
      'CRITICAL' => ('Crítica', BadgeTone.critical),
      _ => ('Sin fallas', BadgeTone.ok),
    };
    return StatusBadge(label, tone: tone);
  }
}

/// Tipo de código de falla, según el modo OBD-II con que se leyó.
class DtcTypeBadge extends StatelessWidget {
  const DtcTypeBadge(this.type, {super.key});

  final String? type;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = switch (type) {
      'CONFIRMED' => ('Confirmado', BadgeTone.severe),
      'PENDING' => ('Pendiente', BadgeTone.warn),
      'PERMANENT' => ('Permanente', BadgeTone.brand),
      _ => (type ?? '-', BadgeTone.neutral),
    };
    return StatusBadge(label, tone: tone);
  }
}

class OrderStatusBadge extends StatelessWidget {
  const OrderStatusBadge(this.status, {super.key});

  final String? status;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = switch (status) {
      'IN_PROGRESS' => ('En proceso', BadgeTone.brandSolid),
      'COMPLETED' => ('Completada', BadgeTone.ok),
      'CANCELLED' => ('Cancelada', BadgeTone.neutral),
      _ => ('Abierta', BadgeTone.brand),
    };
    return StatusBadge(label, tone: tone);
  }
}

class PriorityBadge extends StatelessWidget {
  const PriorityBadge(this.priority, {super.key});

  final String? priority;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = switch (priority) {
      'LOW' => ('Prioridad baja', BadgeTone.neutral),
      'HIGH' => ('Prioridad alta', BadgeTone.severe),
      'CRITICAL' => ('Prioridad crítica', BadgeTone.critical),
      _ => ('Prioridad media', BadgeTone.warn),
    };
    return StatusBadge(label, tone: tone);
  }
}
