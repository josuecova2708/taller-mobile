import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../theme/app_theme.dart';

/// Franja con los dos colores de las siglas de la UAGRM.
class BrandStripe extends StatelessWidget {
  const BrandStripe({super.key});

  @override
  Widget build(BuildContext context) {
    return const ExcludeSemantics(
      child: SizedBox(
        height: 6,
        child: Row(
          children: [
            Expanded(child: ColoredBox(color: AppColors.navy)),
            Expanded(child: ColoredBox(color: AppColors.crimson)),
          ],
        ),
      ),
    );
  }
}

/// Superficie blanca delimitada por un borde fino, con título opcional.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    this.title,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final String? title;

  /// Etiqueta o acción alineada a la derecha del título.
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title!,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
            const Divider(),
          ],
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

/// Un dato con su rótulo, para las fichas de detalle.
class Dato extends StatelessWidget {
  const Dato({super.key, required this.label, required this.value, this.code = false});

  final String label;
  final String value;

  /// El valor es una placa, un VIN o un código.
  final bool code;

  @override
  Widget build(BuildContext context) {
    const valueStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: AppColors.ink,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: AppColors.ink3),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: code ? AppText.code.merge(valueStyle) : valueStyle,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pantalla o lista vacía, o que no se pudo cargar: dice qué pasa y, si
/// corresponde, qué hacer.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  /// Para un fallo de carga, con el botón de reintentar.
  factory EmptyState.error({
    Key? key,
    required String title,
    required Object error,
    required VoidCallback onRetry,
  }) {
    return EmptyState(
      key: key,
      title: title,
      message: mensajeDeError(error),
      actionLabel: 'Reintentar',
      onAction: onRetry,
    );
  }

  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        // Permite arrastrar para actualizar aunque no haya lista.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: AppColors.ink,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 4),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: AppColors.ink2),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
